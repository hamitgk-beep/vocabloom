import 'package:flutter/material.dart';

import '../../ai/device_translate.dart';
import '../../app_state.dart';
import '../../l10n.dart';
import '../../mt/offline_mt.dart';
import '../panel.dart';

/// The instant on-device translation of [text] (Google ML Kit), or a button
/// that downloads the free Turkish package once. On Windows, the offline
/// OPUS-MT model when the learner downloaded and turned it on in Settings
/// (no button here). Nothing on other desktops, and nothing when the text
/// could not be translated.
class DeviceTranslation extends StatefulWidget {
  final AppState app;
  final String text;
  final TextStyle? style;

  /// Wraps whatever is shown (the Turkish, the progress, the button), so a
  /// caller's label and divider disappear with it when nothing is shown.
  final Widget Function(Widget child)? frame;
  /// [text] is a whole sentence. The offline OPUS-MT model on Windows only
  /// helps with sentences, never with a word's meaning.
  final bool sentence;
  const DeviceTranslation({super.key, required this.app, required this.text, this.style, this.frame, this.sentence = false});

  @override
  State<DeviceTranslation> createState() => _DeviceTranslationState();
}

class _DeviceTranslationState extends State<DeviceTranslation> {
  Future<String?>? result;
  bool downloading = false;
  String? error;

  DeviceTranslate get mt => DeviceTranslate.instance;
  OfflineMt get offline => OfflineMt.instance;

  /// Windows with the offline model turned on.
  bool get _offline => widget.sentence && offline.active(widget.app.user);

  Future<String?>? _ask() => _offline
      ? offline.translate(widget.app.user, widget.text)
      : mt.ready(widget.app.user)
          ? mt.translate(widget.app.user, widget.text)
          : null;

  @override
  void initState() {
    super.initState();
    result = _ask();
    mt.downloading.addListener(_changed);
    offline.addListener(_offlineChanged);
  }

  /// The offline model was turned on or off in Settings.
  void _offlineChanged() {
    if (!mounted) return;
    setState(() {
      result = _ask();
    });
  }

  /// The package was being prepared in the background: show the translation
  /// as soon as it is ready.
  void _changed() {
    if (!mounted) return;
    setState(() {
      if (result == null && mt.ready(widget.app.user)) result = mt.translate(widget.app.user, widget.text);
    });
  }

  /// The same panel now shows another text: its translation is asked anew,
  /// so the old text's answer can never show under the new one.
  @override
  void didUpdateWidget(DeviceTranslation old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      result = _ask();
      error = null;
    }
  }

  @override
  void dispose() {
    mt.downloading.removeListener(_changed);
    offline.removeListener(_offlineChanged);
    super.dispose();
  }

  Future<void> _download() async {
    setState(() {
      downloading = true;
      error = null;
    });
    bool ok = false;
    try {
      ok = await mt.download(widget.app.user);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      downloading = false;
      if (ok) {
        result = mt.translate(widget.app.user, widget.text);
      } else {
        error = L('İndirilemedi. İnternet bağlantını kontrol edip tekrar dene.', 'Could not download. Check your connection and try again.');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final offlineOn = _offline;
    if (!DeviceTranslate.supported && !offlineOn) return const SizedBox.shrink();
    final theme = Theme.of(context);
    Widget wrap(Widget w) => widget.frame == null ? w : widget.frame!(w);
    if (offlineOn && result == null) return const SizedBox.shrink();
    if (result == null && mt.downloading.value) {
      return wrap(Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(L('Türkçe çeviri hazırlanıyor…', 'Getting the Turkish translation ready…'), style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor)),
            ),
          ],
        ),
      ));
    }
    if (result == null) {
      return wrap(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutlinedButton.icon(
              onPressed: downloading ? null : _download,
              icon: downloading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.g_translate_rounded, size: 18),
              label: Text(
                downloading ? L('Çeviri paketi indiriliyor…', 'Downloading the translation package…') : L('Türkçe çeviriyi indir (~30 MB, bir kez)', 'Download the Turkish translation (~30 MB, once)'),
              ),
            ),
            if (error != null) Text(error!, style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
          ],
        ),
      ));
    }
    return FutureBuilder<String?>(
      future: result,
      builder: (c, s) {
        if (s.connectionState != ConnectionState.done) {
          return wrap(const Padding(
            padding: EdgeInsets.only(top: 6),
            child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ));
        }
        final t = s.data;
        if (t == null) return const SizedBox.shrink();
        return wrap(Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(t, style: trStyle(theme, widget.style)),
              Text(
                offlineOn
                    ? L('Otomatik çeviri (OPUS-MT, çevrimdışı) · hata içerebilir', 'Automatic translation (OPUS-MT, offline) · may contain mistakes')
                    : L('Cihaz içi anında çeviri (makine çevirisi)', 'Instant on-device translation (machine translation)'),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              ),
            ],
          ),
        ));
      },
    );
  }
}
