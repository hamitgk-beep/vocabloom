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

  /// Windows: tells the user when the last in-app update could not finish,
  /// with what to do. The old app was left as it was unless copying broke
  /// off midway ("fail copy").
  static void showInstallFailed(BuildContext context, String reason) {
    const zip = 'https://github.com/hamitgk-beep/vocabloom/releases/download/latest/VocaBloom-Windows.zip';
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentMaterialBanner();
    m.showMaterialBanner(
      MaterialBanner(
        leading: const Icon(Icons.error_outline),
        content: Text(
          L(
            'Son güncelleme kurulamadı ($reason). Storilex\'i kapat, yeni sürümün zip\'ini indirip aç ve içindekileri Storilex klasörünün üstüne kopyala ("Hedefteki dosyaları değiştir"). Kitapların ve kelimelerin korunur.',
            'The last update could not be installed ($reason). Close Storilex, download and open the new version\'s zip, and copy its contents over the Storilex folder ("Replace the files in the destination"). Your books and words are kept.',
          ),
        ),
        actions: [
          TextButton(onPressed: m.hideCurrentMaterialBanner, child: Text(L('Kapat', 'Close'))),
          FilledButton(
            onPressed: () {
              m.hideCurrentMaterialBanner();
              launchUrl(Uri.parse(zip), mode: LaunchMode.externalApplication);
            },
            child: Text(L('Zip\'i indir', 'Download the zip')),
          ),
        ],
      ),
    );
  }

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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Platform.isAndroid
                  ? L(
                      'Storilex\'in yeni sürümü var$v. İndirip açınca mevcut uygulamanın üstüne kurulur; kitapların ve kelimelerin korunur.',
                      'A new version of Storilex is available$v. Download and open it to install over the current app; your books and words are kept.',
                    )
                  : Platform.isWindows
                  ? L(
                      'Storilex\'in yeni sürümü var$v. Güncelle\'ye basınca indirilip kurulur ve uygulama yeniden açılır; kitapların ve kelimelerin korunur.',
                      'A new version of Storilex is available$v. Press Update to download and install it; the app restarts and your books and words are kept.',
                    )
                  : L('Storilex\'in yeni sürümü var$v.', 'A new version of Storilex is available$v.'),
            ),
            if (u.notes.isNotEmpty) ...[const SizedBox(height: 6), Text(L('Yenilikler: ', "What's new: ") + _areas(u.notes), style: const TextStyle(fontWeight: FontWeight.w600))],
          ],
        ),
        actions: [
          TextButton(onPressed: m.hideCurrentMaterialBanner, child: Text(L('Sonra', 'Later'))),
          if (u.notes.isNotEmpty) TextButton(onPressed: () => showWhatsNew(context, u), child: Text(L('Yenilikler', "What's new"))),
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

  /// The changed areas in one line: "Gramer, Sözlük, Uygulama".
  static String _areas(List<ReleaseNote> notes) => {for (final n in notes) n.areaName}.join(', ');

  /// The full "what's new" list, grouped by area, with the update button.
  static Future<void> showWhatsNew(BuildContext context, UpdateInfo u) {
    final groups = <String, List<ReleaseNote>>{};
    for (final n in u.notes) {
      groups.putIfAbsent(n.areaName, () => []).add(n);
    }
    return showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          title: Text(L('Yeni sürümde neler var${_versionText(u)}', "What's new${_versionText(u)}")),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final g in groups.entries) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: Text(
                        g.key,
                        style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w800),
                      ),
                    ),
                    for (final n in g.value)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(padding: EdgeInsets.only(top: 1, right: 8), child: Text('•')),
                            Expanded(child: Text(n.text, style: theme.textTheme.bodyMedium?.copyWith(height: 1.4))),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(L('Kapat', 'Close'))),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                start(context, u);
              },
              child: Text(Platform.isWindows ? L('Güncelle', 'Update') : L('İndir', 'Download')),
            ),
          ],
        );
      },
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
            builder: (_, v, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  v == null || v < 1
                      ? L('Yeni sürüm indiriliyor…', 'Downloading the new version…')
                      : L('Kuruluyor, Storilex birazdan yeniden açılacak…', 'Installing, Storilex will reopen in a moment…'),
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(value: v),
                if (v != null) ...[const SizedBox(height: 8), Text(percent((v * 100).round()))],
              ],
            ),
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
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 12),
          content: Text(
            L(
              'Güncelleme uygulama içinden kurulamadı, tarayıcıda indiriliyor. İnen zip\'i aç ve içindekileri Storilex klasörünün üstüne kopyala. (${errorText(e)})',
              'The update could not be installed from the app, so it is downloading in the browser. Open the zip and copy its contents over the Storilex folder. (${errorText(e)})',
            ),
          ),
        ),
      );
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: busy ? null : _check,
              icon: busy ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh_rounded),
              label: Text(L('Güncellemeleri denetle', 'Check for updates')),
            ),
            if (found != null && found!.notes.isNotEmpty)
              OutlinedButton.icon(onPressed: () => UpdatePrompt.showWhatsNew(context, found!), icon: const Icon(Icons.new_releases_outlined), label: Text(L('Yenilikler', "What's new"))),
            if (found != null)
              FilledButton.icon(
                onPressed: () => UpdatePrompt.start(context, found!),
                icon: const Icon(Icons.download_rounded),
                label: Text(Platform.isWindows ? L('Güncelle', 'Update') : L('İndir', 'Download')),
              ),
          ],
        ),
        if (note != null) ...[const SizedBox(height: 8), SelectableText(note!, style: theme.textTheme.bodySmall)],
      ],
    );
  }
}
