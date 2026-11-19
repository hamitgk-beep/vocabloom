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
import 'ui/intro_animation.dart';
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
  bool introDone = false;

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
        themeMode: a?.themeMode ?? ThemeMode.light,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        builder: (context, child) => WindowFrame(
          child: Stack(
            children: [
              child ?? const SizedBox.shrink(),
              if (!introDone) Positioned.fill(child: IntroAnimation(onDone: () => setState(() => introDone = true))),
            ],
          ),
        ),
        home: app != null
            ? (OnboardingPage.needed(app!) ? OnboardingPage(app: app!, onDone: () => setState(() {})) : HomePage(app: app!))
            : Scaffold(
                body: Center(
                  child: error != null
                      ? Padding(padding: const EdgeInsets.all(24), child: Text(L('Başlatılamadı: $error', 'Could not start: $error')))
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [CircularProgressIndicator(), SizedBox(height: 16), Text(L('Sözlük hazırlanıyor…', 'Preparing the dictionary…'))],
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
      (Icons.home_outlined, Icons.home_rounded, L('Kitaplık', 'Library')),
      (Icons.layers_outlined, Icons.layers_rounded, L('Kelimeler', 'My words')),
      (Icons.menu_book_outlined, Icons.menu_book_rounded, L('Sözlük', 'Dictionary')),
      (Icons.school_outlined, Icons.school_rounded, L('Gramer', 'Grammar')),
      (Icons.explore_outlined, Icons.explore_rounded, L('Ücretsiz kütüphane', 'Free library')),
      (Icons.insights_outlined, Icons.insights_rounded, L('İstatistiklerim', 'My stats')),
      (Icons.settings_outlined, Icons.settings_rounded, L('Ayarlar', 'Settings')),
    ];
    if (tab >= pages.length) tab = pages.length - 1;
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
                items: [for (final (i, d) in dests.indexed) i == 1 ? (d.$1, d.$2, L('Kelimelerim', 'My words')) : d],
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
          Positioned.fill(child: DecoratedBox(decoration: pageBackground(theme), child: body)),
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
          onCenter: _continueReading,
          menuOpen: menuOpen,
          onMenu: () => setState(() => menuOpen = !menuOpen),
          dark: theme.brightness == Brightness.dark,
          onDark: (v) => widget.app.setTheme(v ? ThemeMode.dark : ThemeMode.light),
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
  const _SideMenu({
    required this.selected,
    required this.items,
    required this.full,
    required this.onSelect,
    required this.todaySeconds,
    required this.onContinue,
  });

  /// Daily reading goal shown in the side menu, in minutes.
  static const goalMinutes = 25;

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
                  gradient: Brand.goldGradient,
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
    final main = [for (var i = 0; i < last && i < 4; i++) item(i)];
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
              Padding(
                padding: EdgeInsets.only(left: full ? 6 : 0, top: 4, bottom: 22),
                child: Row(
                  mainAxisAlignment: full ? MainAxisAlignment.start : MainAxisAlignment.center,
                  children: [
                    const BrandMark(size: 36),
                    if (full) ...[
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          'Storilex',
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: theme.textTheme.titleLarge?.copyWith(fontFamily: readingFont, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ],
                ),
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

/// Phone bottom bar: a floating rounded bar with Library, My words,
/// Dictionary and Menu, and a round gold button in the middle that opens the
/// book read last. Menu raises the bar like a phone's quick settings: day /
/// night on top, then Grammar, Free library, Stats and Settings. Labels
/// never wrap: a label that does not fit is scaled down.
class _BottomNav extends StatelessWidget {
  final int selected;

  /// All pages: 0-2 in the bar, 3-6 in the menu.
  final List<(IconData, IconData, String)> items;
  final ValueChanged<int> onSelect;
  final VoidCallback onCenter;
  final bool menuOpen;
  final VoidCallback onMenu;
  final bool dark;
  final ValueChanged<bool> onDark;
  const _BottomNav({
    required this.selected,
    required this.items,
    required this.onSelect,
    required this.onCenter,
    required this.menuOpen,
    required this.onMenu,
    required this.dark,
    required this.onDark,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final mq = MediaQuery.of(context);
    // Keep the bar readable but bounded when the system font is very large.
    final scaler = mq.textScaler.clamp(maxScaleFactor: 1.15);
    Widget tab(int i, {bool menu = false}) {
      final d = menu ? (Icons.grid_view_outlined, Icons.grid_view_rounded, L('Menü', 'Menu')) : items[i];
      final on = menu ? menuOpen || selected >= 3 : i == selected && !menuOpen;
      final color = on ? cs.primary : cs.onSurfaceVariant;
      return Expanded(
        child: KeyedSubtree(
          key: ValueKey(menu ? 'nav-menu' : 'nav_$i'),
          child: Semantics(
            selected: on,
            button: true,
            label: d.$3,
            excludeSemantics: true,
            child: InkResponse(
              onTap: menu ? onMenu : () => onSelect(i),
              radius: 34,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 40,
                    height: 28,
                    decoration: BoxDecoration(color: menu && menuOpen ? goldSoft(theme) : null, borderRadius: BorderRadius.circular(14)),
                    child: Icon(on ? d.$2 : d.$1, size: 24, color: color),
                  ),
                  const SizedBox(height: 2),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        d.$3,
                        maxLines: 1,
                        softWrap: false,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 11,
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

    final center = Semantics(
      button: true,
      label: L('Okumaya devam et', 'Continue reading'),
      excludeSemantics: true,
      child: Tooltip(
        message: L('Okumaya devam et', 'Continue reading'),
        child: GestureDetector(
          key: const ValueKey('nav-continue'),
          onTap: onCenter,
          child: Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: Brand.goldGradient,
              border: Border.all(color: dark ? Brand.dBg : Brand.lBg, width: 4),
              boxShadow: [BoxShadow(color: const Color(0xFFA67D3A).withValues(alpha: 0.45), blurRadius: 18, offset: const Offset(0, 6))],
            ),
            child: Icon(Icons.auto_stories_rounded, size: 26, color: onGold(theme)),
          ),
        ),
      ),
    );

    // Day / night, then the pages that live in the menu.
    Widget mode(bool night) {
      final on = night == dark;
      final fg = on ? onGold(theme) : cs.onSurface;
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey(night ? 'menu-night' : 'menu-day'),
            borderRadius: BorderRadius.circular(22),
            onTap: () => onDark(night),
            child: Ink(
              height: 58,
              decoration: BoxDecoration(
                gradient: on ? Brand.goldGradient : null,
                color: on ? null : cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(children: [
                const SizedBox(width: 11),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: on ? Colors.white.withValues(alpha: 0.22) : goldSoft(theme)),
                  child: Icon(night ? Icons.dark_mode_rounded : Icons.light_mode_rounded, size: 20, color: on ? fg : cs.primary),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    night ? L('Gece modu', 'Night mode') : L('Gündüz modu', 'Day mode'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: fg),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    Widget tile(int i) {
      final d = items[i];
      final on = i == selected;
      return Expanded(
        child: InkWell(
          key: ValueKey('nav_$i'),
          borderRadius: BorderRadius.circular(18),
          onTap: () => onSelect(i),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(color: on ? goldSoft(theme) : cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(19)),
                child: Icon(on ? d.$2 : d.$1, color: cs.primary),
              ),
              const SizedBox(height: 6),
              Text(d.$3,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(fontSize: 11.5, height: 1.2, fontWeight: FontWeight.w600, color: on ? cs.primary : cs.onSurface)),
            ]),
          ),
        ),
      );
    }

    final panel = Padding(
      key: const ValueKey('nav-menu-panel'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 30),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 38, height: 4, decoration: BoxDecoration(color: cs.outline, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 12),
        Row(children: [mode(true), const SizedBox(width: 10), mode(false)]),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final i in [3, 4, 5, 6]) tile(i)]),
      ]),
    );

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 10),
      child: MediaQuery(
        data: mq.copyWith(textScaler: scaler),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 26, 14, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: dark ? const Color(0xF22B231A) : Colors.white,
                  borderRadius: BorderRadius.circular(34),
                  border: Border.all(color: dark ? const Color(0x24FFE6BE) : Brand.lBorder),
                  boxShadow: [
                    BoxShadow(
                      color: dark ? Colors.black.withValues(alpha: 0.35) : const Color(0xFF785A28).withValues(alpha: 0.14),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.bottomCenter,
                    child: menuOpen ? panel : const SizedBox(width: double.infinity),
                  ),
                  SizedBox(
                    height: 68,
                    child: Row(children: [tab(0), tab(1), const SizedBox(width: 70), tab(2), tab(3, menu: true)]),
                  ),
                ]),
              ),
            ),
            // The gold button stays on the bar's row, half above it.
            Positioned(left: 0, right: 0, bottom: 32, child: Center(child: center)),
          ],
        ),
      ),
    );
  }
}
