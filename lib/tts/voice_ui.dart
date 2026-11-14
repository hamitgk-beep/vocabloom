import 'package:flutter/material.dart';

import '../l10n.dart';
import 'speech.dart';
import 'voices.dart';

/// Makes sure [pack] is on the device; offers the one-time download.
/// Returns true when it can be used now.
Future<bool> ensureVoicePack(BuildContext context, [VoicePack pack = englishPack]) async {
  final s = Speech.instance;
  if (s.isReady(pack)) return true;
  if (!Speech.supported) return false;
  await showDialog<void>(context: context, builder: (c) => _PackDialog(pack));
  return s.isReady(pack);
}

String packTitle(VoicePack pk) => pk.lang == 'tr' ? L('Türkçe ses paketi', 'Turkish voice pack') : L('Doğal İngilizce ses paketi', 'Natural English voice pack');

class _PackDialog extends StatelessWidget {
  final VoicePack pack;
  const _PackDialog(this.pack);

  @override
  Widget build(BuildContext context) {
    final s = Speech.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final st = s.stateOf(pack);
        if (st == PackState.ready) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted && Navigator.canPop(context)) Navigator.pop(context);
          });
        }
        return AlertDialog(
          icon: const Icon(Icons.record_voice_over_rounded),
          title: Text(packTitle(pack)),
          content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: VoicePackStatus(pack: pack)),
          actions: [
            TextButton(
              onPressed: () {
                if (st == PackState.downloading) s.cancelDownload(pack);
                Navigator.pop(context);
              },
              child: Text(st == PackState.downloading ? L('Vazgeç', 'Cancel') : L('Kapat', 'Close')),
            ),
            if (st == PackState.missing || st == PackState.failed)
              FilledButton.icon(
                onPressed: () => s.download(pack),
                icon: const Icon(Icons.download_rounded),
                label: Text(L('İndir (~${pack.mb} MB)', 'Download (~${pack.mb} MB)')),
              ),
          ],
        );
      },
    );
  }
}

/// Text + progress bar describing a voice pack download.
class VoicePackStatus extends StatelessWidget {
  final VoicePack pack;
  const VoicePackStatus({super.key, required this.pack});

  @override
  Widget build(BuildContext context) {
    final s = Speech.instance;
    final theme = Theme.of(context);
    final st = s.stateOf(pack);
    final pr = (s.progressOf(pack) * 100).round();
    final what = pack.lang == 'tr'
        ? L('Türkçe anlamları ve çevirileri sesli dinlemek için', 'To listen to Turkish meanings and translations,')
        : L('Kitabı ve kelimeleri insan gibi doğal bir sesle dinlemek için', 'To hear books and words in a natural, human-like voice,');
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(switch (st) {
        PackState.ready => L('Yüklü. İnternet olmadan çalışır.', 'Installed. Works offline.'),
        PackState.downloading => L('İndiriliyor… %$pr', 'Downloading… $pr%'),
        PackState.extracting => L('Hazırlanıyor…', 'Preparing…'),
        _ => L('$what ses paketi bir kez indirilir (~${pack.mb} MB). Sonra internet olmadan çalışır.', '$what the voice pack is downloaded once (~${pack.mb} MB). After that it works offline.'),
      }),
      if (st == PackState.downloading || st == PackState.extracting) ...[
        const SizedBox(height: 12),
        LinearProgressIndicator(value: st == PackState.extracting ? null : s.progressOf(pack)),
      ],
      if (st == PackState.failed) ...[
        const SizedBox(height: 8),
        Text(L('İndirilemedi. İnternet bağlantını kontrol edip tekrar dene.', 'Download failed. Check your connection and try again.'), style: TextStyle(color: theme.colorScheme.error)),
        if (s.errorOf(pack) != null) Text(s.errorOf(pack)!, style: theme.textTheme.bodySmall),
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
  const SpeakButton(this.text, {super.key, this.lang = 'en', this.speed, this.tooltip, this.autoPlay = false, this.size = 24});

  @override
  State<SpeakButton> createState() => _SpeakButtonState();
}

class _SpeakButtonState extends State<SpeakButton> {
  bool busy = false;

  Voice get _voice => Speech.instance.voiceFor(widget.lang);

  @override
  void initState() {
    super.initState();
    if (widget.autoPlay && Speech.instance.isReady(_voice.pack)) WidgetsBinding.instance.addPostFrameCallback((_) => _say());
  }

  Future<void> _say() async {
    final v = _voice;
    if (!await ensureVoicePack(context, v.pack)) return;
    if (!mounted) return;
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

/// Settings section: voice packs, voice lists with samples, speed.
class VoiceSettings extends StatelessWidget {
  const VoiceSettings({super.key});

  static const sample = 'Reading in English every day is the fastest way to learn new words. Though it can be hard at first, it gets easier.';
  static const sampleTr = 'Her gün biraz İngilizce okumak, yeni kelimeleri öğrenmenin en hızlı yoludur.';

  @override
  Widget build(BuildContext context) {
    final s = Speech.instance;
    final theme = Theme.of(context);
    if (!Speech.supported) return Text(L('Bu cihazda desteklenmiyor.', 'Not supported on this device.'));
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        Widget packBox(VoicePack pk) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              VoicePackStatus(pack: pk),
              const SizedBox(height: 10),
              if (s.stateOf(pk) == PackState.missing || s.stateOf(pk) == PackState.failed)
                FilledButton.tonalIcon(
                  onPressed: () => s.download(pk),
                  icon: const Icon(Icons.download_rounded),
                  label: Text(L('İndir (~${pk.mb} MB)', 'Download (~${pk.mb} MB)')),
                ),
              if (s.stateOf(pk) == PackState.downloading) TextButton(onPressed: () => s.cancelDownload(pk), child: Text(L('Vazgeç', 'Cancel'))),
            ]);

        Widget tile(Voice v, String sampleText) {
          final ok = s.isReady(v.pack);
          return RadioListTile<String>(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: v.id,
            enabled: ok,
            title: Text(v.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: ok || v.lang == 'en' ? null : Text(L('İndirilmedi (~${v.pack.mb} MB)', 'Not downloaded (~${v.pack.mb} MB)')),
            secondary: ok
                ? IconButton(tooltip: L('Örneği dinle', 'Play a sample'), icon: const Icon(Icons.play_circle_outline_rounded), onPressed: () => s.say(sampleText, v: v))
                : IconButton(tooltip: L('İndir', 'Download'), icon: const Icon(Icons.download_rounded), onPressed: () => ensureVoicePack(context, v.pack)),
          );
        }

        Widget group(String title, bool female) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 10, bottom: 2), child: Text(title, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary))),
              for (final v in voices.where((v) => v.female == female)) tile(v, sample),
            ]);

        final english = s.ready
            ? RadioGroup<String>(
                groupValue: s.voice.id,
                onChanged: (id) {
                  final v = voiceById[id];
                  if (v == null) return;
                  s.voice = v;
                  s.say(sample, v: v);
                },
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  group(L('Kadın sesleri · Amerikan aksanı', 'Female voices · American'), true),
                  group(L('Erkek sesleri · Amerikan aksanı', 'Male voices · American'), false),
                ]),
              )
            : packBox(englishPack);

        final turkish = RadioGroup<String>(
          groupValue: s.trVoice.id,
          onChanged: (id) {
            final v = voiceById[id];
            if (v == null || !s.isReady(v.pack)) return;
            s.trVoice = v;
            s.say(sampleTr, v: v);
          },
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final v in trVoices) tile(v, sampleTr)]),
        );

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(L('Bir sese dokun, örnek cümleyi o sesle dinle. Seçtiğin ses kelimeleri ve kitabı okur.', 'Tap a voice to hear a sample. The voice you pick reads words and books.'), style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Text(L('İngilizce sesler', 'English voices'), style: theme.textTheme.titleSmall),
          english,
          const Divider(height: 28),
          Text(L('Türkçe ses', 'Turkish voice'), style: theme.textTheme.titleSmall),
          Text(L('Türkçe anlamların ve çevirilerin yanındaki hoparlöre dokununca okunur.', 'Used by the speaker next to Turkish meanings and translations.'), style: theme.textTheme.bodySmall),
          turkish,
          const Divider(height: 28),
          Text(L('Okuma hızı: ${s.speed.toStringAsFixed(2)}×', 'Speed: ${s.speed.toStringAsFixed(2)}×'), style: theme.textTheme.titleSmall),
          Slider(value: s.speed.clamp(0.6, 1.4), min: 0.6, max: 1.4, divisions: 16, label: '${s.speed.toStringAsFixed(2)}×', onChanged: (v) => s.speed = v),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: s.autoWord,
            onChanged: s.ready ? (v) => s.autoWord = v : null,
            title: Text(L('Kelimeye dokununca otomatik seslendir', 'Say a word when I tap it')),
          ),
          Wrap(spacing: 4, children: [
            for (final pk in voicePacks)
              if (s.isReady(pk))
                TextButton.icon(
                  onPressed: () => s.deletePack(pk),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: Text(L('Sil: ${packTitle(pk)}', 'Delete: ${packTitle(pk)}')),
                ),
          ]),
        ]);
      },
    );
  }
}
