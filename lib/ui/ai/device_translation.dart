import 'package:flutter/material.dart';

import '../../ai/device_translate.dart';
import '../../app_state.dart';
import '../../l10n.dart';
import '../panel.dart';

/// The instant on-device translation of [text] (Google ML Kit), or a button
/// that downloads the free Turkish package once. Nothing on desktop.
class DeviceTranslation extends StatefulWidget {
  final AppState app;
  final String text;
  final TextStyle? style;
  const DeviceTranslation({super.key, required this.app, required this.text, this.style});

  @override
  State<DeviceTranslation> createState() => _DeviceTranslationState();
}

class _DeviceTranslationState extends State<DeviceTranslation> {
  Future<String?>? result;
  bool downloading = false;
  String? error;

  DeviceTranslate get mt => DeviceTranslate.instance;

  @override
  void initState() {
    super.initState();
    if (mt.ready(widget.app.user)) result = mt.translate(widget.app.user, widget.text);
    mt.downloading.addListener(_changed);
  }

  /// The package was being prepared in the background: show the translation
  /// as soon as it is ready.
  void _changed() {
    if (!mounted) return;
    setState(() {
      if (result == null && mt.ready(widget.app.user)) result = mt.translate(widget.app.user, widget.text);
    });
  }

  @override
  void dispose() {
    mt.downloading.removeListener(_changed);
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
    if (!DeviceTranslate.supported) return const SizedBox.shrink();
    final theme = Theme.of(context);
    if (result == null && mt.downloading.value) {
      return Padding(
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
      );
    }
    if (result == null) {
      return Padding(
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
      );
    }
    return FutureBuilder<String?>(
      future: result,
      builder: (c, s) {
        if (s.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.only(top: 6),
            child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final t = s.data;
        if (t == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(t, style: trStyle(theme, widget.style)),
              Text(L('Cihaz içi anında çeviri (makine çevirisi)', 'Instant on-device translation (machine translation)'), style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
            ],
          ),
        );
      },
    );
  }
}
