import 'package:flutter/material.dart';

/// VocaBloom design system: colors, type and component styles in one place.
///
/// The brand color is a deep violet so it never gets confused with the blue
/// used for English text (see enStyle in panel.dart).
class Brand {
  static const violet = Color(0xFF5B3FD9);
  static const violetLight = Color(0xFFA895FF);
  static const ink = Color(0xFF17152B);

  // Light palette
  static const lBg = Color(0xFFF5F4F9);
  static const lSurface = Colors.white;
  static const lSurfaceLow = Color(0xFFF9F8FC);
  static const lSurfaceHigh = Color(0xFFEFEDF6);
  static const lBorder = Color(0xFFE6E3EF);
  static const lMuted = Color(0xFF6B6880);

  // Night palette: dark grey, not pure black, with soft off-white text.
  static const dBg = Color(0xFF111117);
  static const dSurface = Color(0xFF191921);
  static const dSurfaceLow = Color(0xFF15151C);
  static const dSurfaceHigh = Color(0xFF23232D);
  static const dBorder = Color(0xFF2B2B37);
  static const dText = Color(0xFFE4E1DA);
  static const dMuted = Color(0xFF9B98A8);

  /// Brand gradient used on the hero header and book covers.
  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6A4CF0), Color(0xFF4231B8)],
  );

  /// Soft cover gradients for books, picked by title so a book always keeps its color.
  static const covers = <List<Color>>[
    [Color(0xFF6A4CF0), Color(0xFF4231B8)],
    [Color(0xFF0F9D8A), Color(0xFF0B6E66)],
    [Color(0xFFE76F51), Color(0xFFC2410C)],
    [Color(0xFF2B6CB0), Color(0xFF1E3A8A)],
    [Color(0xFFD9467A), Color(0xFF9D174D)],
    [Color(0xFF8B6B3E), Color(0xFF5B4426)],
    [Color(0xFF3F8F4F), Color(0xFF256133)],
  ];

  static List<Color> coverFor(String title) {
    var h = 0;
    for (final c in title.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return covers[h % covers.length];
  }
}

/// Font used for the book text.
const readingFont = 'Literata';

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: Brand.violet, brightness: b).copyWith(
    primary: dark ? Brand.violetLight : Brand.violet,
    onPrimary: dark ? const Color(0xFF1D1147) : Colors.white,
    primaryContainer: dark ? const Color(0xFF2E2560) : const Color(0xFFECE8FF),
    onPrimaryContainer: dark ? const Color(0xFFE3DDFF) : const Color(0xFF24156E),
    secondaryContainer: dark ? const Color(0xFF2E2560) : const Color(0xFFECE8FF),
    onSecondaryContainer: dark ? const Color(0xFFE3DDFF) : const Color(0xFF24156E),
    surface: dark ? Brand.dSurface : Brand.lSurface,
    onSurface: dark ? Brand.dText : Brand.ink,
    onSurfaceVariant: dark ? Brand.dMuted : Brand.lMuted,
    surfaceContainerLowest: dark ? Brand.dBg : Brand.lSurface,
    surfaceContainerLow: dark ? Brand.dSurfaceLow : Brand.lSurfaceLow,
    surfaceContainer: dark ? Brand.dSurface : Brand.lBg,
    surfaceContainerHigh: dark ? Brand.dSurfaceHigh : Brand.lSurfaceHigh,
    surfaceContainerHighest: dark ? const Color(0xFF2A2A35) : const Color(0xFFE8E5F1),
    outline: dark ? const Color(0xFF4A4858) : const Color(0xFFCBC7D9),
    outlineVariant: dark ? Brand.dBorder : Brand.lBorder,
  );
  final bg = dark ? Brand.dBg : Brand.lBg;
  final border = dark ? Brand.dBorder : Brand.lBorder;
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, fontFamily: 'Inter');
  final t = base.textTheme;
  final text = t.copyWith(
    headlineLarge: t.headlineLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8),
    headlineMedium: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6),
    headlineSmall: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
    titleLarge: t.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
    titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.1),
    titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    labelMedium: t.labelMedium?.copyWith(fontWeight: FontWeight.w600),
    bodySmall: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
  );
  final r12 = BorderRadius.circular(12);
  final r16 = BorderRadius.circular(16);
  return base.copyWith(
    textTheme: text,
    scaffoldBackgroundColor: bg,
    hintColor: scheme.onSurfaceVariant,
    dividerColor: border,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: false,
      titleSpacing: 20,
      titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface, fontSize: 22),
      iconTheme: IconThemeData(color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: r16, side: BorderSide(color: border)),
      clipBehavior: Clip.antiAlias,
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: r12),
      titleTextStyle: text.titleMedium?.copyWith(color: scheme.onSurface),
      subtitleTextStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      iconColor: scheme.onSurfaceVariant,
    ),
    dividerTheme: DividerThemeData(color: border, space: 1, thickness: 1),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      indicatorColor: scheme.primaryContainer,
      indicatorShape: RoundedRectangleBorder(borderRadius: r12),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => text.labelMedium?.copyWith(
            color: s.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          )),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant,
          )),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primaryContainer,
      indicatorShape: RoundedRectangleBorder(borderRadius: r12),
      selectedIconTheme: IconThemeData(color: scheme.primary),
      unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      selectedLabelTextStyle: text.labelMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700),
      unselectedLabelTextStyle: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: r12),
        textStyle: text.labelLarge?.copyWith(fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: r12),
        side: BorderSide(color: border),
        foregroundColor: scheme.onSurface,
        textStyle: text.labelLarge?.copyWith(fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: r12), textStyle: text.labelLarge),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: r12)),
        side: WidgetStatePropertyAll(BorderSide(color: border)),
        textStyle: WidgetStatePropertyAll(text.labelLarge),
        visualDensity: VisualDensity.standard,
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      side: BorderSide(color: border),
      backgroundColor: scheme.surface,
      selectedColor: scheme.primaryContainer,
      labelStyle: text.labelLarge?.copyWith(color: scheme.onSurface),
      checkmarkColor: scheme.primary,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 2,
      highlightElevation: 4,
      shape: RoundedRectangleBorder(borderRadius: r16),
      extendedTextStyle: text.labelLarge?.copyWith(fontSize: 15),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: r12, borderSide: BorderSide(color: border)),
      enabledBorder: OutlineInputBorder(borderRadius: r12, borderSide: BorderSide(color: border)),
      focusedBorder: OutlineInputBorder(borderRadius: r12, borderSide: BorderSide(color: scheme.primary, width: 1.6)),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: scheme.outline,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    drawerTheme: DrawerThemeData(backgroundColor: scheme.surface, surfaceTintColor: Colors.transparent),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: r12, side: BorderSide(color: border)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: r12),
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: Colors.transparent,
      indicatorSize: TabBarIndicatorSize.tab,
      indicator: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: border)),
      labelColor: scheme.onSurface,
      unselectedLabelColor: scheme.onSurfaceVariant,
      labelStyle: text.labelLarge,
      unselectedLabelStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w500),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHigh,
      linearMinHeight: 6,
      borderRadius: BorderRadius.circular(3),
    ),
    checkboxTheme: CheckboxThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5))),
  );
}

/// Small rounded section header used on settings and lists.
class SectionLabel extends StatelessWidget {
  final String text;
  final EdgeInsets padding;
  const SectionLabel(this.text, {super.key, this.padding = const EdgeInsets.fromLTRB(4, 20, 4, 8)});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: padding,
      child: Text(text.toUpperCase(),
          style: t.textTheme.labelMedium?.copyWith(letterSpacing: 1.0, color: t.colorScheme.onSurfaceVariant)),
    );
  }
}

/// A white rounded box that groups related rows (settings-style).
class Panel extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets padding;
  const Panel({super.key, required this.children, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Material(
      color: t.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: t.colorScheme.outlineVariant)),
      child: Padding(
        padding: padding,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    );
  }
}

/// Book cover made from the title (no image needed).
class BookCover extends StatelessWidget {
  final String title;
  final String format;
  final double width;
  final List<Color>? colors;
  const BookCover({super.key, required this.title, required this.format, this.width = 56, this.colors});

  @override
  Widget build(BuildContext context) {
    final c = colors ?? Brand.coverFor(title);
    final initials = title.trim().isEmpty ? '?' : title.trim().characters.first.toUpperCase();
    return Container(
      width: width,
      height: width * 1.42,
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: c),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [BoxShadow(color: c.last.withValues(alpha: 0.28), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Stack(children: [
        Positioned(left: 5, top: 0, bottom: 0, child: Container(width: 1.5, color: Colors.white.withValues(alpha: 0.18))),
        Center(
          child: Text(initials,
              style: TextStyle(color: Colors.white, fontFamily: readingFont, fontWeight: FontWeight.w700, fontSize: width * 0.44)),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: width * 0.1,
          child: Text(format.toUpperCase(),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: width * 0.15, fontWeight: FontWeight.w700, letterSpacing: 1)),
        ),
      ]),
    );
  }
}

/// Page color behind the book text: warm paper by day, the night grey at night.
Color readerPaper(ThemeData t) => t.brightness == Brightness.dark ? Brand.dBg : const Color(0xFFFCFAF6);
