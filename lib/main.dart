import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'ai/key_ai.dart';
import 'app_state.dart';
import 'ai/device_translate.dart';
import 'data/dict_db.dart';
import 'data/tr_en_dict.dart';
import 'data/user_db.dart';
import 'import/importers.dart' show looksGeneratedTitle, titleFromContent;
import 'import/text_repair.dart';
import 'import/word_gaps.dart';
import 'ui/dictionary_page.dart';
import 'ui/free_library_page.dart';
import 'ui/journey_page.dart';
import 'ui/library_page.dart';
import 'online/update_check.dart';
import 'online/windows_updater.dart';
import 'online/rename_migration.dart';
import 'ui/other_pages.dart';
import 'ui/settings_page.dart';
import 'ui/update_prompt.dart';
import 'ui/onboarding.dart';
import 'ui/reader_page.dart';
import 'ui/grammar/grammar_page.dart';
import 'ui/theme.dart';
import 'ui/window_frame.dart';
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

  /// The opening animation plays once per start, over the loading screen.

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final override = Platform.environment['KELIME_OKUR_DATA'];
      var dir = override != null ? Directory(override) : await getApplicationSupportDirectory();
      // Windows names the data folder after the product: books and words
      // from the VocaBloom days move to the Storilex folder.
      if (override == null && Platform.isWindows) {
        dir = RenameMigration.dataFolder(dir);
        unawaited(RenameMigration.moveShortcuts());
      }
      await dir.create(recursive: true);
      final dict = await DictDb.open(dir);
      final user = UserDb.open(dir);
      final a = AppState(dict, user);
      a.trEn = await TrEnDict.open(dir);
      Speech.instance.bookLang = a.learnTurkish ? 'tr' : 'en';
      user.lang = a.learnTurkish ? 'tr' : 'en';
      a.localAi = KeyAi(user);
      Speech.instance.init(dir, user);
      // Load the voice model early so the first tap on a speaker is quick.
      Future.delayed(const Duration(seconds: 3), Speech.instance.warmUp);
      // All voices come with the app: fetch the packs that are missing.
      if (override == null) Future.delayed(const Duration(seconds: 2), Speech.instance.downloadAll);
      // The instant Turkish translation package (phones and tablets) comes the same way.
      if (override == null) Future.delayed(const Duration(seconds: 4), () => DeviceTranslate.instance.prepare(user));
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
        title: 'Storilex',
        debugShowCheckedModeBanner: false,
        locale: uiLocale,
        supportedLocales: uiLocales,
        localizationsDelegates: uiLocalizationsDelegates,
        // While loading, follow the system like the launch screen before it.
        themeMode: a?.themeMode ?? ThemeMode.system,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        builder: (context, child) => WindowFrame(child: child ?? const SizedBox.shrink()),
        home: app != null
            ? (OnboardingPage.needed(app!) ? OnboardingPage(app: app!, onDone: () => setState(() {})) : HomePage(app: app!))
            : error != null
                ? Scaffold(
                    body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(L('Başlatılamadı: $error', 'Could not start: $error')))),
                  )
                : const LoadingScreen(),
      ),
    );
  }
}

/// While the dictionary opens: the gold wordmark on the plain theme colour
/// (as on the launch screen), a thin gold line and what is happening.
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Scaffold(
      key: const ValueKey('loading'),
      body: Stack(children: [
        Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Wordmark(height: 46),
            const SizedBox(height: 18),
            const GoldRule(width: 220),
            const SizedBox(height: 16),
            Text(
              L('· OKU · ÖĞREN ·', '· READ · LEARN ·'),
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, letterSpacing: 5, color: muted),
            ),
          ]),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 110,
          child: Column(children: [
            SizedBox(
              width: 140,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(1),
                child: LinearProgressIndicator(
                  minHeight: 2,
                  color: Brand.goldLight,
                  backgroundColor: Brand.goldLight.withValues(alpha: 0.18),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(L('Sözlük hazırlanıyor…', 'Preparing the dictionary…'), style: TextStyle(fontSize: 12.5, color: muted)),
          ]),
        ),
      ]),
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

  /// The phone's bottom menu is raised (grammar, free library, stats,
  /// settings and day / night).
  bool menuOpen = false;

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

  /// The phone's center button: back into the book read last, or the free
  /// library when there is no book yet.
  Future<void> _continueReading() async {
    final b = recentBooks(widget.app).firstOrNull;
    if (b == null) {
      setState(() => tab = 4);
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReaderPage(app: widget.app, book: b),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final theme = Theme.of(context);
    void go(int i) => setState(() {
          tab = i;
          menuOpen = false;
        });
    // On phones grammar, the free library, stats and settings open from the
    // bottom bar's menu; on wide screens they have their own place in the side menu.
    final pages = [
      LibraryPage(app: widget.app, onTab: wide ? null : go),
      WordsPage(app: widget.app),
      DictionaryPage(app: widget.app),
      GrammarPage(app: widget.app),
      // Built only while shown: the catalog loads when opened, the numbers are current.
      tab == 4 ? FreeLibraryPage(app: widget.app) : const SizedBox.shrink(),
      tab == 5 ? JourneyPage(app: widget.app) : const SizedBox.shrink(),
      SettingsPage(app: widget.app),
    ];
    final dests = [
      // Names as reading and learning apps usually call these pages.
      (Icons.auto_stories_outlined, Icons.auto_stories_rounded, L('Kitaplık', 'Library')),
      (Icons.bookmarks_outlined, Icons.bookmarks_rounded, L('Kelimelerim', 'My words')),
      (Icons.search_rounded, Icons.search_rounded, L('Sözlük', 'Dictionary')),
      (Icons.school_outlined, Icons.school_rounded, L('Gramer', 'Grammar')),
      (Icons.explore_outlined, Icons.explore_rounded, L('Ücretsiz kitaplar', 'Free books')),
      (Icons.insights_outlined, Icons.insights_rounded, L('İstatistikler', 'Statistics')),
      (Icons.settings_outlined, Icons.settings_rounded, L('Ayarlar', 'Settings')),
    ];
    if (tab >= pages.length) tab = pages.length - 1;
    final due = widget.app.review.dueCount();
    // The tab pages sit on one shared background: cream by day, a warm glow by night.
    final body = Theme(
      data: theme.copyWith(
        scaffoldBackgroundColor: Colors.transparent,
        appBarTheme: theme.appBarTheme.copyWith(backgroundColor: Colors.transparent),
      ),
      child: IndexedStack(index: tab, children: pages),
    );
    if (wide) {
      return Scaffold(
        body: DecoratedBox(
          decoration: pageBackground(theme),
          child: Row(
            children: [
              _SideMenu(
                selected: tab,
                items: dests,
                due: due,
                full: MediaQuery.sizeOf(context).width >= 1000,
                onSelect: go,
                todaySeconds: widget.app.stats.readingSeconds(from: DateTime.now()),
                onContinue: _continueReading,
              ),
              Expanded(child: body),
            ],
          ),
        ),
      );
    }
    return PopScope(
      // Back on a phone first returns to the library.
      canPop: tab == 0 && !menuOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        menuOpen ? setState(() => menuOpen = false) : go(0);
      },
      child: Scaffold(
        extendBody: true,
        body: Stack(children: [
          // The pages end at the top of the bottom bar (its closed height), so
          // the last row of every list scrolls fully into view. The bar's
          // own sheet still opens over the page without moving it.
          Positioned.fill(
            child: DecoratedBox(
              decoration: pageBackground(theme),
              child: Padding(
                key: const ValueKey('tab-body'),
                padding: EdgeInsets.only(bottom: bottomBarHeight + 1 + MediaQuery.viewPaddingOf(context).bottom),
                child: MediaQuery.removePadding(context: context, removeBottom: true, child: body),
              ),
            ),
          ),
          // A tap anywhere outside the raised menu closes it.
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !menuOpen,
              child: GestureDetector(
                key: const ValueKey('menu-barrier'),
                onTap: () => setState(() => menuOpen = false),
                child: AnimatedOpacity(
                  opacity: menuOpen ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: ColoredBox(color: Colors.black.withValues(alpha: theme.brightness == Brightness.dark ? 0.45 : 0.22)),
                ),
              ),
            ),
          ),
        ]),
        bottomNavigationBar: _BottomNav(
          selected: tab,
          items: dests,
          onSelect: go,
          menuOpen: menuOpen,
          onMenu: () => setState(() => menuOpen = !menuOpen),
          mode: widget.app.themeMode,
          onMode: widget.app.setTheme,
          due: due,
        ),
      ),
    );
  }
}

/// Side menu on wide screens: icon and name on one line, the main pages on
/// top, the free library and the journey in their own group, Settings at the
/// bottom. Narrower windows show only the icons, with the name as a tooltip.
class _SideMenu extends StatelessWidget {
  final int selected;
  final List<(IconData, IconData, String)> items;
  final bool full;
  final ValueChanged<int> onSelect;
  final int todaySeconds;
  final VoidCallback onContinue;

  /// Words due for review: a badge on My words.
  final int due;
  const _SideMenu({
    required this.selected,
    required this.items,
    required this.full,
    required this.onSelect,
    required this.todaySeconds,
    required this.onContinue,
    required this.due,
  });

  static const goalMinutes = readingGoalMinutes;

  /// Today's reading against the goal, with a button back into the last book.
  Widget _goalCard(ThemeData theme) {
    final cs = theme.colorScheme;
    final mins = (todaySeconds / 60).floor();
    return Container(
      key: const ValueKey('side-goal'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(L('Bugünkü hedef', 'Today\'s goal'), style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(L('$mins / $goalMinutes dk', '$mins / $goalMinutes min'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: (mins / goalMinutes).clamp(0.0, 1.0), minHeight: 4),
        const SizedBox(height: 12),
        GoldButton(label: L('Okumaya devam', 'Continue reading'), height: 40, onPressed: onContinue),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    Widget item(int i) {
      final d = items[i];
      final on = i == selected;
      final color = on ? onGold(theme) : cs.onSurfaceVariant;
      final tile = Material(
        color: Colors.transparent,
        shape: const StadiumBorder(),
        child: Ink(
          decoration: on
              ? BoxDecoration(
                  gradient: goldFill(theme),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: const Color(0xFFA67D3A).withValues(alpha: 0.28), blurRadius: 14, offset: const Offset(0, 5))],
                )
              : null,
          child: InkWell(
            key: ValueKey('side-menu-$i'),
            customBorder: const StadiumBorder(),
            onTap: () => onSelect(i),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: full ? 14 : 0, vertical: 11),
              child: Row(
                mainAxisAlignment: full ? MainAxisAlignment.start : MainAxisAlignment.center,
                children: [
                  Icon(on ? d.$2 : d.$1, size: 22, color: color),
                  if (full) ...[
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        d.$3,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14.5, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on ? color : cs.onSurface),
                      ),
                    ),
                    if (i == 1 && due > 0)
                      Container(
                        key: const ValueKey('side-due'),
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                        decoration: BoxDecoration(color: learnColor(theme), borderRadius: BorderRadius.circular(9)),
                        child: Text(due > 99 ? '99+' : '$due', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: onLearn(theme))),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: full ? tile : Tooltip(message: d.$3, waitDuration: const Duration(milliseconds: 300), child: tile),
      );
    }

    final last = items.length - 1;
    // Reading, Dictionary, My words, Grammar; then the free library and stats.
    final main = [for (final i in const [0, 2, 1, 3]) item(i)];
    final extra = [for (var i = 4; i < last; i++) item(i)];
    return SizedBox(
      width: full ? 232 : 76,
      child: SafeArea(
        right: false,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: full ? 12 : 10, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The gold wordmark heads the menu; the narrow menu has the S.
              if (full)
                const Padding(
                  padding: EdgeInsets.fromLTRB(10, 8, 6, 0),
                  child: Align(alignment: Alignment.centerLeft, child: Wordmark(height: 25)),
                )
              else
                const Padding(padding: EdgeInsets.only(top: 4), child: Center(child: BrandMark(size: 36))),
              Padding(
                padding: EdgeInsets.fromLTRB(full ? 6 : 10, 14, full ? 6 : 10, 16),
                child: const GoldRule(),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    ...main,
                    if (extra.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Divider(height: 1, indent: full ? 8 : 6, endIndent: full ? 8 : 6),
                      ),
                      ...extra,
                    ],
                  ],
                ),
              ),
              if (full) ...[_goalCard(theme), const SizedBox(height: 10)]
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Center(
                    child: RoundIconButton(icon: Icons.auto_stories_rounded, gold: true, tooltip: L('Okumaya devam', 'Continue reading'), onPressed: onContinue),
                  ),
                ),
              item(last),
            ],
          ),
        ),
      ),
    );
  }
}

/// Phone bottom bar, flat along the screen's foot: Reading (the library),
/// Dictionary, My words (with the number of words due for review) and More.
/// More raises a sheet above the bar: day / night on top, then
/// Grammar, Free books, Statistics and Settings. Labels never wrap: a label
/// that does not fit is scaled down.
/// Height of the phone's bottom bar without its raised sheet.
const bottomBarHeight = 64.0;

class _BottomNav extends StatelessWidget {
  final int selected;

  /// All pages: 0-2 in the bar, 3-6 in the More sheet.
  final List<(IconData, IconData, String)> items;
  final ValueChanged<int> onSelect;
  final bool menuOpen;
  final VoidCallback onMenu;
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onMode;

  /// Words due for review: a badge on My words.
  final int due;
  const _BottomNav({
    required this.selected,
    required this.items,
    required this.onSelect,
    required this.menuOpen,
    required this.onMenu,
    required this.mode,
    required this.onMode,
    required this.due,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final mq = MediaQuery.of(context);
    // Keep the bar readable but bounded when the system font is very large.
    final scaler = mq.textScaler.clamp(maxScaleFactor: 1.15);
    final barColor = dark ? Brand.dSurface : const Color(0xFFFBF7EF);

    Widget tab(int i, {bool menu = false}) {
      final d = menu ? (Icons.more_horiz_rounded, Icons.more_horiz_rounded, L('Diğer', 'More')) : items[i];
      final on = menu ? menuOpen || selected >= 3 : i == selected && !menuOpen;
      final color = on ? cs.primary : cs.onSurfaceVariant;
      final badge = !menu && i == 1 && due > 0;
      return Expanded(
        child: KeyedSubtree(
          key: ValueKey(menu ? 'nav-menu' : 'nav_$i'),
          child: Semantics(
            selected: on,
            button: true,
            label: badge ? '${d.$3}, ${L('$due kelime tekrar bekliyor', '$due words to review')}' : d.$3,
            excludeSemantics: true,
            child: InkResponse(
              onTap: menu ? onMenu : () => onSelect(i),
              radius: 34,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 40,
                    height: 28,
                    child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                      Icon(on ? d.$2 : d.$1, size: 25, color: color),
                      if (badge)
                        Positioned(
                          right: 0,
                          top: -2,
                          child: Container(
                            key: const ValueKey('nav-due'),
                            constraints: const BoxConstraints(minWidth: 18),
                            height: 18,
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: learnColor(theme), borderRadius: BorderRadius.circular(9), border: Border.all(color: barColor, width: 1.5)),
                            child: Text(due > 99 ? '99+' : '$due', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: onLearn(theme), height: 1)),
                          ),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 3),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        d.$3,
                        maxLines: 1,
                        softWrap: false,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 11.5,
                          letterSpacing: 0,
                          color: color,
                          fontWeight: on ? FontWeight.w700 : FontWeight.w500,
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

    // Day / Night, as one segmented row.
    Widget seg(ThemeMode m, IconData icon, String label) {
      final on = m == mode;
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey('menu-${m == ThemeMode.dark ? 'night' : 'day'}'),
            borderRadius: BorderRadius.circular(12),
            onTap: () => onMode(m),
            child: Ink(
              height: 42,
              decoration: BoxDecoration(
                color: on ? (dark ? Brand.dBg : Colors.white) : null,
                borderRadius: BorderRadius.circular(12),
                boxShadow: on && !dark ? [const BoxShadow(color: Color(0x14785A28), blurRadius: 6, offset: Offset(0, 2))] : null,
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 17, color: on ? cs.primary : cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on ? cs.onSurface : cs.onSurfaceVariant)),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    Widget row(int i, String sub) {
      final d = items[i];
      final on = i == selected;
      return InkWell(
        key: ValueKey('nav_$i'),
        onTap: () => onSelect(i),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(shape: BoxShape.circle, color: goldSoft(theme)),
              child: Icon(on ? d.$2 : d.$1, size: 21, color: cs.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.$3, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: on ? cs.primary : cs.onSurface)),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
          ]),
        ),
      );
    }

    final subs = {
      3: L('Konular ve alıştırmalar', 'Lessons and exercises'),
      4: L('Hikâyeler ve kitaplar', 'Stories and books'),
      5: L('Okuma süresi ve seri', 'Reading time and streak'),
      6: L('Tema, dil, ses', 'Theme, language, voice'),
    };
    final panel = Padding(
      key: const ValueKey('nav-menu-panel'),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4, decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(15)),
          child: Row(children: [
            seg(ThemeMode.light, Icons.light_mode_outlined, L('Açık', 'Light')),
            seg(ThemeMode.dark, Icons.dark_mode_outlined, L('Koyu', 'Dark')),
          ]),
        ),
        const SizedBox(height: 12),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: dark ? Brand.dSurfaceLow : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(children: [
            for (final (n, i) in [3, 4, 5, 6].indexed) ...[
              if (n > 0) Divider(height: 1, color: cs.outlineVariant),
              row(i, subs[i]!),
            ],
          ]),
        ),
      ]),
    );

    return MediaQuery(
      data: mq.copyWith(textScaler: scaler),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: barColor,
          border: Border(top: BorderSide(color: cs.outlineVariant)),
          borderRadius: menuOpen ? const BorderRadius.vertical(top: Radius.circular(24)) : null,
          boxShadow: menuOpen ? [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 30, offset: const Offset(0, -10))] : null,
        ),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.bottomCenter,
              child: menuOpen ? panel : const SizedBox(width: double.infinity),
            ),
            SizedBox(
              height: bottomBarHeight,
              child: Row(children: [tab(0), tab(2), tab(1), tab(3, menu: true)]),
            ),
          ]),
        ),
      ),
    );
  }
}
