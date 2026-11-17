import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'ai/key_ai.dart';
import 'app_state.dart';
import 'data/dict_db.dart';
import 'data/user_db.dart';
import 'import/importers.dart' show looksGeneratedTitle, titleFromContent;
import 'import/text_repair.dart';
import 'import/word_gaps.dart';
import 'ui/dictionary_page.dart';
import 'ui/library_page.dart';
import 'online/update_check.dart';
import 'online/windows_updater.dart';
import 'ui/other_pages.dart';
import 'ui/settings_page.dart';
import 'ui/update_prompt.dart';
import 'ui/onboarding.dart';
import 'ui/grammar/grammar_page.dart';
import 'ui/theme.dart';
import 'tts/speech.dart';

import 'l10n.dart';

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
      final dir = override != null ? Directory(override) : await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      final dict = await DictDb.open(dir);
      final user = UserDb.open(dir);
      final a = AppState(dict, user);
      a.localAi = KeyAi(user);
      Speech.instance.init(dir, user);
      // Load the voice model early so the first tap on a speaker is quick.
      Future.delayed(const Duration(seconds: 3), Speech.instance.warmUp);
      // All voices come with the app: fetch the packs that are missing.
      if (override == null) Future.delayed(const Duration(seconds: 2), Speech.instance.downloadAll);
      try {
        user.repairJoinedWordsOnce((t) => splitJoinedWords(t, a.isWord));
      } catch (e) {
        debugPrint('repairJoinedWords: $e');
      }
      try {
        user.repairImportedTextOnce((t, format) => format == 'pdf' || format == 'image' ? repairPdfText(t, a.isWord) : cleanInvisible(t));
      } catch (e) {
        debugPrint('repairImportedText: $e');
      }
      try {
        user.repairBookTitles(looksGeneratedTitle, titleFromContent);
      } catch (e) {
        debugPrint('repairBookTitles: $e');
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
                      ? Padding(padding: const EdgeInsets.all(24), child: Text(L('Başlatılamadı: $error', 'Could not start: $error')))
                      : Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 16), Text(L('Sözlük hazırlanıyor…', 'Preparing the dictionary…'))]),
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

  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 4), _checkUpdate);
    // Apps left open for days still hear about a new release.
    _updateTimer = Timer.periodic(const Duration(hours: 6), (_) => _checkUpdate());
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  bool _installChecked = false;

  Future<void> _checkUpdate() async {
    if (!_installChecked && Platform.isWindows) {
      _installChecked = true;
      final failed = WindowsUpdater.takeFailedResult();
      if (failed != null && mounted) {
        UpdatePrompt.showInstallFailed(context, failed);
        return;
      }
    }
    final u = await checkForUpdate();
    if (u == null || !mounted) return;
    UpdatePrompt.showBanner(context, u);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [LibraryPage(app: widget.app), WordsPage(app: widget.app), DictionaryPage(app: widget.app), GrammarPage(app: widget.app), SettingsPage(app: widget.app)];
    final dests = [
      (Icons.auto_stories_outlined, Icons.auto_stories_rounded, L('Kitaplık', 'Library')),
      (Icons.bookmarks_outlined, Icons.bookmarks_rounded, L('Kelimeler', 'My words')),
      (Icons.search_rounded, Icons.manage_search_rounded, L('Sözlük', 'Dictionary')),
      (Icons.school_outlined, Icons.school_rounded, L('Gramer', 'Grammar')),
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
              destinations: [for (final d in dests) NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3))],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: _BottomNav(selected: tab, items: dests, onSelect: (i) => setState(() => tab = i)),
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
      final tp = TextPainter(
        text: TextSpan(text: d.$3, style: base),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      if (tp.width > widest) widest = tp.width;
      tp.dispose();
    }
    final fontSize = widest > slot ? 11.5 * slot / widest : 11.5;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: MediaQuery(
          data: mq.copyWith(textScaler: scaler),
          child: SizedBox(
            height: 66,
            child: Row(
              children: [
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
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOut,
                              width: i == selected ? 52 : 40,
                              height: 30,
                              decoration: BoxDecoration(color: i == selected ? cs.primaryContainer : Colors.transparent, borderRadius: BorderRadius.circular(12)),
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
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
