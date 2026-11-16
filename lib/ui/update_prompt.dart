import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n.dart';
import '../online/update_check.dart';
import '../online/windows_updater.dart';

/// The "new version" banner and, on Windows, the in-app download and install.
class UpdatePrompt {
  static int _shownBuild = 0;

  static String _versionText(UpdateInfo u) => u.version.isEmpty ? '' : ' (${u.version})';

  /// Shows the banner once per new build. [force] shows it again (manual check).
  static void showBanner(BuildContext context, UpdateInfo u, {bool force = false}) {
    if (!force && u.build <= _shownBuild) return;
    _shownBuild = u.build;
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentMaterialBanner();
    final v = _versionText(u);
    m.showMaterialBanner(
      MaterialBanner(
        leading: const Icon(Icons.system_update),
        content: Text(
          Platform.isAndroid
              ? L('VocaBloom\'un yeni sürümü var$v. İndirip açınca mevcut uygulamanın üstüne kurulur; kitapların ve kelimelerin korunur.', 'A new version of VocaBloom is available$v. Download and open it to install over the current app; your books and words are kept.')
              : Platform.isWindows
                  ? L('VocaBloom\'un yeni sürümü var$v. Güncelle\'ye basınca indirilip kurulur ve uygulama yeniden açılır; kitapların ve kelimelerin korunur.', 'A new version of VocaBloom is available$v. Press Update to download and install it; the app restarts and your books and words are kept.')
                  : L('VocaBloom\'un yeni sürümü var$v.', 'A new version of VocaBloom is available$v.'),
        ),
        actions: [
          TextButton(
            onPressed: m.hideCurrentMaterialBanner,
            child: Text(L('Sonra', 'Later')),
          ),
          FilledButton(
            onPressed: () {
              m.hideCurrentMaterialBanner();
              start(context, u);
            },
            child: Text(Platform.isWindows ? L('Güncelle', 'Update') : L('İndir', 'Download')),
          ),
        ],
      ),
    );
  }

  /// Windows: download, replace and restart. Elsewhere: open the download.
  static void start(BuildContext context, UpdateInfo u) {
    if (Platform.isWindows) {
      _installWindows(context, u);
    } else {
      launchUrl(Uri.parse(u.url), mode: LaunchMode.externalApplication);
    }
  }

  static Future<void> _installWindows(BuildContext context, UpdateInfo u) async {
    final progress = ValueNotifier<double?>(null);
    final nav = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(L('Güncelleniyor', 'Updating')),
          content: ValueListenableBuilder<double?>(
            valueListenable: progress,
            builder: (_, v, _) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v == null || v < 1
                  ? L('Yeni sürüm indiriliyor…', 'Downloading the new version…')
                  : L('Kuruluyor, VocaBloom birazdan yeniden açılacak…', 'Installing, VocaBloom will reopen in a moment…')),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: v),
              if (v != null) ...[const SizedBox(height: 8), Text(percent((v * 100).round()))],
            ]),
          ),
        ),
      ),
    );
    try {
      final dir = await WindowsUpdater.prepare(u.url, (v) => progress.value = v, expectedSize: u.size > 0 ? u.size : null);
      progress.value = 1;
      await WindowsUpdater.installAndRestart(dir);
    } catch (e) {
      nav.pop();
      messenger.showSnackBar(SnackBar(
        duration: const Duration(seconds: 12),
        content: Text(L('Güncelleme uygulama içinden kurulamadı, tarayıcıda indiriliyor. İnen zip\'i aç ve içindekileri VocaBloom klasörünün üstüne kopyala. (${errorText(e)})',
            'The update could not be installed from the app, so it is downloading in the browser. Open the zip and copy its contents over the VocaBloom folder. (${errorText(e)})')),
      ));
      launchUrl(Uri.parse(u.url), mode: LaunchMode.externalApplication);
    }
  }
}

/// "Check for updates" button for the About page.
class CheckUpdateButton extends StatefulWidget {
  const CheckUpdateButton({super.key});

  @override
  State<CheckUpdateButton> createState() => _CheckUpdateButtonState();
}

class _CheckUpdateButtonState extends State<CheckUpdateButton> {
  bool busy = false;
  String? note;
  UpdateInfo? found;

  Future<void> _check() async {
    setState(() {
      busy = true;
      note = null;
      found = null;
    });
    try {
      final u = await checkForUpdateOrThrow();
      if (!mounted) return;
      setState(() {
        found = u;
        note = appBuild == 0
            ? L('Geliştirme derlemesinde güncelleme denetlenmez.', 'Updates are not checked in a development build.')
            : u == null
                ? L('En son sürümü kullanıyorsun.', 'You have the latest version.')
                : L('Yeni sürüm var${UpdatePrompt._versionText(u)}.', 'A new version is available${UpdatePrompt._versionText(u)}.');
      });
    } catch (e) {
      if (mounted) setState(() => note = L('Güncelleme denetlenemedi: ${errorText(e)}', 'Could not check for updates: ${errorText(e)}'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
          onPressed: busy ? null : _check,
          icon: busy ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh_rounded),
          label: Text(L('Güncellemeleri denetle', 'Check for updates')),
        ),
        if (found != null)
          FilledButton.icon(
            onPressed: () => UpdatePrompt.start(context, found!),
            icon: const Icon(Icons.download_rounded),
            label: Text(Platform.isWindows ? L('Güncelle', 'Update') : L('İndir', 'Download')),
          ),
      ]),
      if (note != null) ...[
        const SizedBox(height: 8),
        SelectableText(note!, style: theme.textTheme.bodySmall),
      ],
    ]);
  }
}
