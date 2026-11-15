import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n.dart';
import 'speech.dart';
import 'voices.dart';

/// Makes sure a voice for [pack]'s language is on the device; offers the
/// one-time download. Returns true when it can be used now.
Future<bool> ensureVoicePack(BuildContext context, [VoicePack pack = englishPack]) async {
  final s = Speech.instance;
  final english = pack.lang == 'en';
  bool ok() => english ? s.ready : s.isReady(pack);
  if (ok()) return true;
  if (!Speech.supported) return false;
  await showDialog<void>(context: context, builder: (c) => _PackDialog(pack));
  return ok();
}

String packTitle(VoicePack pk) => switch (pk.engine) {
      'kokoro' => L('Doğal İngilizce ses', 'Natural English voice'),
      _ when pk == lightPack => L('Hafif İngilizce ses', 'Light English voice'),
      _ => L('Türkçe ses (${voiceById.values.firstWhere((v) => v.pack == pk).name})', 'Turkish voice (${voiceById.values.firstWhere((v) => v.pack == pk).name})'),
    };

int get _englishMb => englishPacks.fold(0, (a, p) => a + p.mb);

class _PackDialog extends StatelessWidget {
  final VoicePack pack;
  const _PackDialog(this.pack);

  @override
  Widget build(BuildContext context) {
    final s = Speech.instance;
    final english = pack.lang == 'en';
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        // English: close as soon as the light voice works; the natural one
        // keeps downloading in the background.
        final ready = english ? s.ready : s.isReady(pack);
        if (ready) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted && Navigator.canPop(context)) Navigator.pop(context);
          });
        }
        final packs = english ? englishPacks : [pack];
        final busy = packs.any((p) => s.stateOf(p) == PackState.downloading || s.stateOf(p) == PackState.extracting);
        return AlertDialog(
          icon: const Icon(Icons.record_voice_over_rounded),
          title: Text(english ? L('İngilizce sesler', 'English voices') : packTitle(pack)),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(english
                  ? L('Kitabı ve kelimeleri insan gibi doğal bir sesle dinlemek için sesler bir kez indirilir (~$_englishMb MB, Wi-Fi önerilir). Önce küçük hafif ses iner ve hemen kullanılabilir. Sonra internet olmadan çalışır.',
                      'To hear books and words in a natural, human-like voice, the voices are downloaded once (~$_englishMb MB, Wi-Fi recommended). The small light voice comes first and works right away. After that they work offline.')
                  : L('Türkçe anlamları ve çevirileri sesli dinlemek için ses paketi bir kez indirilir (~${pack.mb} MB). Sonra internet olmadan çalışır.',
                      'To listen to Turkish meanings and translations, the voice pack is downloaded once (~${pack.mb} MB). After that it works offline.')),
              for (final p in packs)
                if (s.stateOf(p) != PackState.missing) ...[const SizedBox(height: 12), VoicePackStatus(pack: p)],
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (busy) packs.forEach(s.cancelDownload);
                Navigator.pop(context);
              },
              child: Text(busy ? L('Vazgeç', 'Cancel') : L('Kapat', 'Close')),
            ),
            if (!busy)
              FilledButton.icon(
                onPressed: () => english ? s.downloadEnglish() : s.download(pack),
                icon: const Icon(Icons.download_rounded),
                label: Text(L('İndir (~${english ? _englishMb : pack.mb} MB)', 'Download (~${english ? _englishMb : pack.mb} MB)')),
              ),
          ],
        );
      },
    );
  }
}

/// One line with a progress bar describing a voice pack's download.
class VoicePackStatus extends StatelessWidget {
  final VoicePack pack;
  const VoicePackStatus({super.key, required this.pack});

  @override
  Widget build(BuildContext context) {
    final s = Speech.instance;
    final theme = Theme.of(context);
    final st = s.stateOf(pack);
    final pr = (s.progressOf(pack) * 100).round();
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${packTitle(pack)} · ${switch (st) {
        PackState.ready => L('yüklü', 'installed'),
        PackState.downloading => L('indiriliyor… %$pr', 'downloading… $pr%'),
        PackState.extracting => L('hazırlanıyor…', 'preparing…'),
        PackState.failed => L('indirilemedi', 'download failed'),
        PackState.missing => L('indirilmedi (~${pack.mb} MB)', 'not downloaded (~${pack.mb} MB)'),
      }}', style: theme.textTheme.bodyMedium),
      if (st == PackState.downloading || st == PackState.extracting) ...[
        const SizedBox(height: 6),
        LinearProgressIndicator(value: st == PackState.extracting ? null : s.progressOf(pack)),
      ],
      if (st == PackState.failed) ...[
        const SizedBox(height: 4),
        Text(
          [L('İnternet bağlantını kontrol edip tekrar dene.', 'Check your connection and try again.'), if (s.errorOf(pack) != null) s.errorOf(pack)!].join(' '),
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
        ),
      ],
    ]);
  }
}

/// Speaker button that says [text] in the chosen voice of [lang].
class SpeakButton extends StatefulWidget {
  final String text;
  final String lang;
  final double? speed;
  final String? tooltip;
  final bool autoPlay;
  final double size;

  /// Make the audio as soon as the button appears (short texts only).
  final bool prefetch;
  const SpeakButton(this.text, {super.key, this.lang = 'en', this.speed, this.tooltip, this.autoPlay = false, this.size = 24, this.prefetch = true});

  @override
  State<SpeakButton> createState() => _SpeakButtonState();
}

class _SpeakButtonState extends State<SpeakButton> {
  bool busy = false;

  Voice get _voice => Speech.instance.voiceFor(widget.lang);

  @override
  void initState() {
    super.initState();
    if (widget.autoPlay && Speech.instance.isReady(_voice.pack)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _say());
    } else if (widget.prefetch && widget.speed == null) {
      // Make the audio while the panel is read, so the tap plays at once.
      Speech.instance.prefetch(widget.text, lang: widget.lang);
    }
  }

  Future<void> _say() async {
    if (!await ensureVoicePack(context, _voice.pack)) return;
    if (!mounted) return;
    final v = _voice;
    setState(() => busy = true);
    try {
      await Speech.instance.say(widget.text, v: v, speed: widget.speed);
    } catch (e) {
      debugPrint('say: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IconButton(
      tooltip: widget.tooltip ?? (widget.lang == 'tr' ? L('Türkçesini dinle', 'Listen in Turkish') : L('Dinle', 'Listen')),
      iconSize: widget.size,
      visualDensity: VisualDensity.compact,
      onPressed: busy ? null : _say,
      icon: busy
          ? SizedBox(width: widget.size * 0.8, height: widget.size * 0.8, child: const CircularProgressIndicator(strokeWidth: 2.4))
          : Icon(Icons.volume_up_rounded, color: widget.lang == 'tr' ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.primary),
    );
  }
}

/// Settings: English and Turkish voice (each a drop-down with a sample
/// button), voice quality, reading speed and voice downloads.
class VoiceSettings extends StatefulWidget {
  const VoiceSettings({super.key});

  static const sample = 'Reading in English every day is the fastest way to learn new words.';
  static const sampleTr = 'Her gün biraz okumak, yeni kelimeler öğrenmenin en hızlı yoludur.';

  @override
  State<VoiceSettings> createState() => _VoiceSettingsState();
}

class _VoiceSettingsState extends State<VoiceSettings> {
  static const sample = VoiceSettings.sample, sampleTr = VoiceSettings.sampleTr;
  final s = Speech.instance;

  @override
  void initState() {
    super.initState();
    s.addListener(_prefetchSamples);
    _prefetchSamples();
  }

  // Make the samples in the background (chosen voices first), so a tap plays
  // at once. Samples are kept, so this happens only once per voice.
  final _asked = <String>{};
  void _prefetchSamples() {
    final list = [s.voice, s.trVoice, ...(s.useNatural ? voices : lightVoices), ...trVoices];
    for (final v in list) {
      if (!s.isReady(v.pack) || !_asked.add(v.id)) continue;
      s.prefetch(v.lang == 'tr' ? sampleTr : sample, voice: v);
    }
  }

  @override
  void dispose() {
    s.removeListener(_prefetchSamples);
    // Leaving the page stops a sample that is still playing.
    unawaited(s.stopPlayback());
    super.dispose();
  }

  String _kind(Voice v) => switch ((v.female, v.accent)) {
        (true, 'gb') => L('Kadın · İngiliz', 'Female · British'),
        (false, 'gb') => L('Erkek · İngiliz', 'Male · British'),
        (true, 'tr') || (false, 'tr') => L('Türkçe', 'Turkish'),
        (true, _) => L('Kadın · Amerikan', 'Female · American'),
        (false, _) => L('Erkek · Amerikan', 'Male · American'),
      };

  Widget _voicePicker(List<Voice> list, Voice current, String sampleText, ValueChanged<Voice> onPick) {
    final theme = Theme.of(context);
    return Row(children: [
      Expanded(
        child: DropdownButtonFormField<String>(
          initialValue: current.id,
          isExpanded: true,
          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
          items: [
            for (final v in list)
              DropdownMenuItem(
                value: v.id,
                enabled: s.isReady(v.pack),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: v.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  TextSpan(text: '  ${_kind(v)}', style: theme.textTheme.bodySmall),
                  if (!s.isReady(v.pack)) TextSpan(text: '  · ${L('indirilmedi', 'not downloaded')}', style: theme.textTheme.bodySmall),
                ])),
              ),
          ],
          onChanged: (id) {
            final v = voiceById[id];
            if (v == null || !s.isReady(v.pack)) return;
            onPick(v);
            s.say(sampleText, v: v);
          },
        ),
      ),
      const SizedBox(width: 4),
      IconButton.filledTonal(
        tooltip: L('Örneği dinle', 'Play a sample'),
        icon: const Icon(Icons.play_arrow_rounded),
        onPressed: s.isReady(current.pack) ? () => s.say(sampleText, v: current) : null,
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!Speech.supported) return Text(L('Bu cihazda desteklenmiyor.', 'Not supported on this device.'));
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final englishBusy = englishPacks.any((p) => s.stateOf(p) == PackState.downloading || s.stateOf(p) == PackState.extracting);
        final englishMissing = englishPacks.any((p) => !s.isReady(p));
        final both = englishPacks.every(s.isReady);
        final rtf = s.naturalSpeed;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(L('İngilizce ses', 'English voice'), style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          if (s.ready)
            _voicePicker(s.useNatural ? voices : lightVoices, s.voice, sample, (v) => s.voice = v)
          else
            Text(L('Kitabı ve kelimeleri doğal bir sesle dinlemek için İngilizce sesleri indir.', 'Download the English voices to hear books and words in a natural voice.'),
                style: theme.textTheme.bodySmall),
          if (englishMissing || englishBusy) ...[
            const SizedBox(height: 10),
            for (final p in englishPacks)
              if (!s.isReady(p)) Padding(padding: const EdgeInsets.only(bottom: 6), child: VoicePackStatus(pack: p)),
            if (englishBusy)
              TextButton(onPressed: () => englishPacks.forEach(s.cancelDownload), child: Text(L('Vazgeç', 'Cancel')))
            else
              FilledButton.tonalIcon(
                onPressed: s.downloadEnglish,
                icon: const Icon(Icons.download_rounded),
                label: Text(L('İndir (~${englishPacks.where((p) => !s.isReady(p)).fold(0, (a, p) => a + p.mb)} MB)',
                    'Download (~${englishPacks.where((p) => !s.isReady(p)).fold(0, (a, p) => a + p.mb)} MB)')),
              ),
          ],
          if (both) ...[
            const SizedBox(height: 14),
            Text(L('Ses kalitesi', 'Voice quality'), style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'auto', label: Text(L('Otomatik', 'Automatic'))),
                ButtonSegment(value: 'natural', label: Text(L('Doğal', 'Natural'))),
                ButtonSegment(value: 'light', label: Text(L('Hafif', 'Light'))),
              ],
              selected: {s.quality},
              onSelectionChanged: (q) => s.quality = q.first,
            ),
            const SizedBox(height: 6),
            Text(
              switch (s.quality) {
                'natural' => L('Her zaman en doğal ses. Yavaş telefonlarda cümleler arasında bekleme olabilir.', 'Always the most natural voice. Slow phones may pause between sentences.'),
                'light' => L('Daha hızlı ve daha az pil kullanır; ses biraz daha yapay.', 'Faster and lighter on the battery; the voice sounds a bit less natural.'),
                _ => rtf == null
                    ? L('Telefonun hızı ölçülünce en uygun ses seçilir.', 'The best voice is picked once the phone\'s speed is measured.')
                    : s.naturalTooSlow
                        ? L('Bu telefonda doğal ses akıcı okumaya yetişemiyor, hafif ses kullanılıyor.', 'The natural voice can\'t keep up on this phone, so the light voice is used.')
                        : L('Bu telefon doğal sesi rahatça çalıştırıyor.', 'This phone runs the natural voice comfortably.'),
              },
              style: theme.textTheme.bodySmall,
            ),
          ],
          const Divider(height: 32),
          Text(L('Türkçe ses', 'Turkish voice'), style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(L('Türkçe anlamların ve çevirilerin yanındaki hoparlöre dokununca okunur.', 'Used by the speaker next to Turkish meanings and translations.'), style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          _voicePicker(trVoices, s.trVoice, sampleTr, (v) => s.trVoice = v),
          for (final p in [fahrettinPack, fettahPack])
            if (!s.isReady(p))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Expanded(child: VoicePackStatus(pack: p)),
                  if (s.stateOf(p) == PackState.missing || s.stateOf(p) == PackState.failed)
                    TextButton(onPressed: () => s.download(p), child: Text(L('İndir', 'Download')))
                  else if (s.stateOf(p) == PackState.downloading)
                    TextButton(onPressed: () => s.cancelDownload(p), child: Text(L('Vazgeç', 'Cancel'))),
                ]),
              ),
          const Divider(height: 32),
          Text(L('Okuma hızı: ${s.speed.toStringAsFixed(2)}×', 'Speed: ${s.speed.toStringAsFixed(2)}×'), style: theme.textTheme.titleSmall),
          Slider(value: s.speed.clamp(0.6, 1.4), min: 0.6, max: 1.4, divisions: 16, label: '${s.speed.toStringAsFixed(2)}×', onChanged: (v) => s.speed = v),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: s.autoWord,
            onChanged: s.ready ? (v) => s.autoWord = v : null,
            title: Text(L('Kelimeye dokununca otomatik seslendir', 'Say a word when I tap it')),
          ),
          if (voicePacks.any(s.isReady))
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(L('İndirilen sesler', 'Downloaded voices'), style: theme.textTheme.titleSmall),
              children: [
                for (final pk in voicePacks)
                  if (s.isReady(pk))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(packTitle(pk)),
                      subtitle: Text('~${pk.mb} MB'),
                      trailing: IconButton(
                        tooltip: L('Sil', 'Delete'),
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () => s.deletePack(pk),
                      ),
                    ),
              ],
            ),
        ]);
      },
    );
  }
}
