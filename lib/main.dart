import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'ai/local_engine.dart';
import 'app_state.dart';
import 'data/dict_db.dart';
import 'data/user_db.dart';
import 'import/word_gaps.dart';
import 'ui/library_page.dart';
import 'online/update_check.dart';
import 'online/windows_updater.dart';
import 'ui/other_pages.dart';
import 'ui/settings_page.dart';
import 'ui/onboarding.dart';
import 'ui/ai/ai_page.dart';
import 'ui/grammar/grammar_page.dart';
import 'ai/tutor.dart';
import 'ui/theme.dart';
import 'tts/speech.dart';

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
      a.localAi = LlamaLocalAi(user, dir);
      Speech.instance.init(dir, user);
      // Load the voice model early so the first tap on a speaker is quick.
      Future.delayed(const Duration(seconds: 3), Speech.instance.warmUp);
      try {
        user.repairJoinedWordsOnce((t) => splitJoinedWords(t, a.isWord));
      } catch (e) {
        debugPrint('repairJoinedWords: $e');
      }
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
        locale: uiLocale,
        supportedLocales: uiLocales,
        localizationsDelegates: uiLocalizationsDelegates,
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
              if (v != null) ...[const SizedBox(height: 8), Text(percent((v * 100).round()))],
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
      GrammarPage(app: widget.app),
      if (widget.app.aiTab) AiPage(ai: widget.app.localAi, tutor: Tutor.of(widget.app)),
      SettingsPage(app: widget.app),
    ];
    final dests = [
      (Icons.auto_stories_outlined, Icons.auto_stories_rounded, L('Kitaplık', 'Library')),
      (Icons.bookmarks_outlined, Icons.bookmarks_rounded, L('Kelimeler', 'My words')),
      (Icons.search_rounded, Icons.manage_search_rounded, L('Sözlük', 'Dictionary')),
      (Icons.school_outlined, Icons.school_rounded, L('Gramer', 'Grammar')),
      if (widget.app.aiTab) (Icons.auto_awesome_outlined, Icons.auto_awesome_rounded, L('Yapay Zekâ', 'AI Tutor')),
      (Icons.tune_outlined, Icons.tune_rounded, L('Ayarlar', 'Settings')),
    ];
    if (tab >= pages.length) tab = pages.length - 1;
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
      bottomNavigationBar: _BottomNav(
        selected: tab,
        items: dests,
        onSelect: (i) => setState(() => tab = i),
      ),
    );
  }
}

/// Phone bottom bar. Every tab shows its label on one line: a label that
/// does not fit (six tabs, large system font) is scaled down, never wrapped.
class _BottomNav extends StatelessWidget {
  final int selected;
  final List<(IconData, IconData, String)> items;
  final ValueChanged<int> onSelect;
  const _BottomNav({required this.selected, required this.items, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final mq = MediaQuery.of(context);
    // Keep the bar readable but bounded when the system font is very large.
    final scaler = mq.textScaler.clamp(maxScaleFactor: 1.15);
    // One font size for every label: the largest at which the longest label
    // still fits its tab, so no label looks smaller than its neighbours.
    final base = theme.textTheme.labelSmall?.copyWith(fontSize: 11.5, letterSpacing: 0, fontWeight: FontWeight.w700) ?? const TextStyle(fontSize: 11.5);
    final slot = mq.size.width / items.length - 6;
    var widest = 0.0;
    for (final d in items) {
      final tp = TextPainter(text: TextSpan(text: d.$3, style: base), textDirection: TextDirection.ltr, textScaler: scaler, maxLines: 1)..layout();
      if (tp.width > widest) widest = tp.width;
      tp.dispose();
    }
    final fontSize = widest > slot ? 11.5 * slot / widest : 11.5;
    return Container(
      decoration: BoxDecoration(color: cs.surface, border: Border(top: BorderSide(color: cs.outlineVariant))),
      child: SafeArea(
        top: false,
        child: MediaQuery(
          data: mq.copyWith(textScaler: scaler),
          child: SizedBox(
            height: 66,
            child: Row(children: [
              for (final (i, d) in items.indexed)
                Expanded(
                  key: ValueKey('nav_$i'),
                  child: Semantics(
                    selected: i == selected,
                    button: true,
                    label: d.$3,
                    excludeSemantics: true,
                    child: InkResponse(
                      onTap: () => onSelect(i),
                      radius: 36,
                      highlightShape: BoxShape.rectangle,
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                          width: i == selected ? 52 : 40,
                          height: 30,
                          decoration: BoxDecoration(
                            color: i == selected ? cs.primaryContainer : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(i == selected ? d.$2 : d.$1, size: 23, color: i == selected ? cs.primary : cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              d.$3,
                              maxLines: 1,
                              softWrap: false,
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontSize: fontSize,
                                letterSpacing: 0,
                                color: i == selected ? cs.primary : cs.onSurfaceVariant,
                                fontWeight: i == selected ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
