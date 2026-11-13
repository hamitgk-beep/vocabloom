import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app_state.dart';
import 'data/dict_db.dart';
import 'data/user_db.dart';
import 'ui/library_page.dart';
import 'online/update_check.dart';
import 'online/windows_updater.dart';
import 'ui/other_pages.dart';
import 'ui/onboarding.dart';
import 'ui/theme.dart';

import 'l10n.dart';
import 'package:url_launcher/url_launcher.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(KelimeOkurApp(args: args));
}

class KelimeOkurApp extends StatefulWidget {
  final List<String> args;
  const KelimeOkurApp({super.key, this.args = const []});

  @override
  State<KelimeOkurApp> createState() => _KelimeOkurAppState();
}

class _KelimeOkurAppState extends State<KelimeOkurApp> {
  AppState? app;
  Object? error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final override = Platform.environment['KELIME_OKUR_DATA'];
      final dir = override != null
          ? Directory(override)
          : await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      final dict = await DictDb.open(dir);
      final user = UserDb.open(dir);
      final a = AppState(dict, user);
      // Optional: import files given on the command line (desktop "Open with").
      for (final f in widget.args.where((a) => File(a).existsSync())) {
        await importForTest(a, f);
      }
      a.analyzer.start();
      setState(() => app = a);
    } catch (e, st) {
      debugPrint('$e\n$st');
      setState(() => error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = app;
    return ListenableBuilder(
      listenable: a ?? ValueNotifier(0),
      builder: (context, _) => MaterialApp(
        title: 'VocaBloom',
        debugShowCheckedModeBanner: false,
        themeMode: a?.themeMode ?? ThemeMode.light,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: app != null
            ? (OnboardingPage.needed(app!) ? OnboardingPage(app: app!, onDone: () => setState(() {})) : HomePage(app: app!))
            : Scaffold(
                body: Center(
                  child: error != null
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(L('Başlatılamadı: $error', 'Could not start: $error')),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text(L('Sözlük hazırlanıyor…', 'Preparing the dictionary…')),
                          ],
                        ),
                ),
              ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final AppState app;
  const HomePage({super.key, required this.app});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 4), _checkUpdate);
  }

  Future<void> _checkUpdate() async {
    final u = await checkForUpdate();
    if (u == null || !mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.showMaterialBanner(
      MaterialBanner(
        leading: const Icon(Icons.system_update),
        content: Text(
          Platform.isAndroid
              ? L('VocaBloom\'un yeni sürümü var. İndirip açınca mevcut uygulamanın üstüne kurulur; kitapların ve kelimelerin korunur.', 'A new version of VocaBloom is available. Download and open it to install over the current app; your books and words are kept.')
              : Platform.isWindows
                  ? L('VocaBloom\'un yeni sürümü var. Güncelle\'ye basınca indirilip kurulur ve uygulama yeniden açılır; kitapların ve kelimelerin korunur.', 'A new version of VocaBloom is available. Press Update to download and install it; the app restarts and your books and words are kept.')
                  : L('VocaBloom\'un yeni sürümü var.', 'A new version of VocaBloom is available.'),
        ),
        actions: [
          TextButton(
            onPressed: m.hideCurrentMaterialBanner,
            child: Text(L('Sonra', 'Later')),
          ),
          FilledButton(
            onPressed: () {
              m.hideCurrentMaterialBanner();
              if (Platform.isWindows) {
                _installWindowsUpdate(u.url);
              } else {
                launchUrl(Uri.parse(u.url), mode: LaunchMode.externalApplication);
              }
            },
            child: Text(Platform.isWindows ? L('Güncelle', 'Update') : L('İndir', 'Download')),
          ),
        ],
      ),
    );
  }

  /// Downloads the new Windows build, then replaces the app and restarts it.
  Future<void> _installWindowsUpdate(String url) async {
    final progress = ValueNotifier<double?>(null);
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
              if (v != null) ...[const SizedBox(height: 8), Text('%${(v * 100).round()}')],
            ]),
          ),
        ),
      ),
    );
    try {
      final dir = await WindowsUpdater.prepare(url, (v) => progress.value = v);
      progress.value = 1;
      await WindowsUpdater.installAndRestart(dir);
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(L('Güncelleme kurulamadı. Yeni sürüm tarayıcıda indiriliyor.', 'The update could not be installed. Downloading it in the browser instead.')),
      ));
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      LibraryPage(app: widget.app),
      WordsPage(app: widget.app),
      CategoriesPage(app: widget.app),
      SettingsPage(app: widget.app),
    ];
    final dests = [
      (Icons.auto_stories_outlined, Icons.auto_stories_rounded, L('Kitaplık', 'Library')),
      (Icons.bookmarks_outlined, Icons.bookmarks_rounded, L('Kelimelerim', 'My words')),
      (Icons.search_rounded, Icons.manage_search_rounded, L('Sözlük', 'Dictionary')),
      (Icons.tune_outlined, Icons.tune_rounded, L('Ayarlar', 'Settings')),
    ];
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final body = IndexedStack(index: tab, children: pages);
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: tab,
              labelType: NavigationRailLabelType.all,
              minWidth: 88,
              groupAlignment: -0.9,
              leading: const Padding(padding: EdgeInsets.only(top: 12, bottom: 20), child: BrandMark(size: 40)),
              onDestinationSelected: (i) => setState(() => tab = i),
              destinations: [
                for (final d in dests)
                  NavigationRailDestination(
                    icon: Icon(d.$1),
                    selectedIcon: Icon(d.$2),
                    label: Text(d.$3),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant))),
        child: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: [
          for (final d in dests)
            NavigationDestination(
              icon: Icon(d.$1),
              selectedIcon: Icon(d.$2),
              label: d.$3,
            ),
        ],
      ),
      ),
    );
  }
}
