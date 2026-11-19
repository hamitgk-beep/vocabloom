import 'dart:io';

import 'package:flutter/material.dart';

/// VocaBloom design system: colors, type and component styles in one place.
///
/// A warm "reading lamp" look: cream paper and gold accents by day, dark
/// brown with soft glassy cards and gold by night. Gold never gets confused
/// with the blue used for English text (see enStyle in panel.dart).
class Brand {
  /// Main accent (day). Dark enough for white text on buttons.
  static const gold = Color(0xFFA9792F);

  /// Main accent (night): lighter so it glows on dark brown.
  static const goldLight = Color(0xFFD6B16C);
  static const ink = Color(0xFF2A2216);

  // Day palette: cream paper, white cards, warm beige lines.
  static const lBg = Color(0xFFFAF6EE);
  static const lSurface = Colors.white;
  static const lSurfaceLow = Color(0xFFFDFAF4);
  static const lSurfaceHigh = Color(0xFFF4ECDC);
  static const lBorder = Color(0xFFEDE3D0);
  static const lMuted = Color(0xFF85775F);

  // Night palette: warm dark brown, not black, with soft cream text.
  static const dBg = Color(0xFF17130F);
  static const dSurface = Color(0xFF221C16);
  static const dSurfaceLow = Color(0xFF1C1713);
  static const dSurfaceHigh = Color(0xFF2E261E);
  static const dBorder = Color(0xFF3A3026);
  static const dText = Color(0xFFF2EADB);
  static const dMuted = Color(0xFFA99D89);

  /// Gold gradient for pill buttons, the center button and highlights.
  static const goldGradient = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFDBB873), Color(0xFFA67D3A)]);

  /// Deeper gold for banners that carry white text.
  static const gradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFA77B35), Color(0xFF6E4E1D)]);

  /// The cream "hero" card (weekly summary, profile).
  static const heroLight = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF2E8D2), Color(0xFFE5D3AE)]);
  static const heroDark = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFEFEAE0), Color(0xFFD8D0C1)]);

  /// Night background: a soft warm glow in the top corner.
  static const nightGlow = RadialGradient(
    center: Alignment(0.9, -1.1),
    radius: 1.3,
    colors: [Color(0xFF3A2E1F), Color(0xFF1C1712), Color(0xFF14110D)],
    stops: [0, 0.55, 1],
  );

  /// Muted, bookish cover colors, picked by title so a book always keeps its color.
  static const covers = <List<Color>>[
    [Color(0xFF2F4A49), Color(0xFF162626)],
    [Color(0xFF6B7B4A), Color(0xFF3F4B28)],
    [Color(0xFF34436A), Color(0xFF1A2238)],
    [Color(0xFF6A2F2F), Color(0xFF331616)],
    [Color(0xFF8A6630), Color(0xFF4A3414)],
    [Color(0xFF4F3B5E), Color(0xFF261B30)],
    [Color(0xFF2F5A45), Color(0xFF173024)],
  ];

  static List<Color> coverFor(String title) {
    var h = 0;
    for (final c in title.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return covers[h % covers.length];
  }
}

/// Pale gold behind icons and selected chips.
Color goldSoft(ThemeData t) => t.brightness == Brightness.dark ? const Color(0x29D6B16C) : const Color(0xFFF3E6CB);

/// Text and icon color on the gold gradient.
Color onGold(ThemeData t) => t.brightness == Brightness.dark ? const Color(0xFF21180A) : Colors.white;

/// Page background: cream by day, a warm glow by night.
BoxDecoration pageBackground(ThemeData t) => t.brightness == Brightness.dark
    ? const BoxDecoration(gradient: Brand.nightGlow)
    : const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFBF7EF), Color(0xFFF6EFE2)]),
      );

/// A pill-shaped button filled with the gold gradient.
class GoldButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final double height;
  final bool trailingIcon;
  const GoldButton({super.key, required this.label, this.icon, this.onPressed, this.height = 44, this.trailingIcon = false});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final fg = onGold(t);
    final ic = icon == null ? null : Icon(icon, size: 18, color: fg);
    return Opacity(
      opacity: onPressed == null ? 0.5 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: Brand.goldGradient,
          borderRadius: BorderRadius.circular(height / 2),
          boxShadow: [BoxShadow(color: const Color(0xFFA67D3A).withValues(alpha: 0.30), blurRadius: 14, offset: const Offset(0, 3))],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(height / 2),
            onTap: onPressed,
            child: SizedBox(
              height: height,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (ic != null && !trailingIcon) ...[ic, const SizedBox(width: 8)],
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.labelLarge?.copyWith(color: fg, fontSize: 14.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (ic != null && trailingIcon) ...[const SizedBox(width: 6), ic],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A round icon button on a soft card background (top bars, reader tools).
class RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final bool gold;
  const RoundIconButton({super.key, required this.icon, this.onPressed, this.tooltip, this.size = 42, this.gold = false});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final child = Material(
      shape: CircleBorder(side: gold ? BorderSide.none : BorderSide(color: cs.outlineVariant)),
      color: gold ? Colors.transparent : cs.surface,
      child: Ink(
        decoration: gold ? const BoxDecoration(shape: BoxShape.circle, gradient: Brand.goldGradient) : null,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: size * 0.47, color: gold ? onGold(t) : cs.onSurface),
          ),
        ),
      ),
    );
    return tooltip == null ? child : Tooltip(message: tooltip!, child: child);
  }
}

/// Font used for the book text.
const readingFont = 'Literata';

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: Brand.gold, brightness: b).copyWith(
    primary: dark ? Brand.goldLight : Brand.gold,
    onPrimary: dark ? const Color(0xFF21180A) : Colors.white,
    primaryContainer: dark ? const Color(0xFF3B3022) : const Color(0xFFF3E6CB),
    onPrimaryContainer: dark ? const Color(0xFFF0D9A8) : const Color(0xFF5A3F12),
    secondary: dark ? const Color(0xFFCDBB98) : const Color(0xFF7D6440),
    secondaryContainer: dark ? const Color(0xFF3B3022) : const Color(0xFFF3E6CB),
    onSecondaryContainer: dark ? const Color(0xFFF0D9A8) : const Color(0xFF5A3F12),
    tertiary: dark ? const Color(0xFFE9A24C) : const Color(0xFFC0702A),
    surface: dark ? Brand.dSurface : Brand.lSurface,
    onSurface: dark ? Brand.dText : Brand.ink,
    onSurfaceVariant: dark ? Brand.dMuted : Brand.lMuted,
    surfaceContainerLowest: dark ? Brand.dBg : Brand.lSurface,
    surfaceContainerLow: dark ? Brand.dSurfaceLow : Brand.lSurfaceLow,
    surfaceContainer: dark ? Brand.dSurface : Brand.lBg,
    surfaceContainerHigh: dark ? Brand.dSurfaceHigh : Brand.lSurfaceHigh,
    surfaceContainerHighest: dark ? const Color(0xFF362C22) : const Color(0xFFEDE2CC),
    outline: dark ? const Color(0xFF5A4C3C) : const Color(0xFFD5C7AC),
    outlineVariant: dark ? Brand.dBorder : Brand.lBorder,
  );
  final bg = dark ? Brand.dBg : Brand.lBg;
  final border = dark ? Brand.dBorder : Brand.lBorder;
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, fontFamily: 'Inter');
  final t = base.textTheme;
  final text = t.copyWith(
    // Page titles in the book font, like a title page.
    headlineLarge: t.headlineLarge?.copyWith(fontFamily: readingFont, fontWeight: FontWeight.w700, letterSpacing: -0.5),
    headlineMedium: t.headlineMedium?.copyWith(fontFamily: readingFont, fontWeight: FontWeight.w700, letterSpacing: -0.4),
    headlineSmall: t.headlineSmall?.copyWith(fontFamily: readingFont, fontWeight: FontWeight.w700, letterSpacing: -0.3),
    titleLarge: t.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
    titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.1),
    titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    labelMedium: t.labelMedium?.copyWith(fontWeight: FontWeight.w600),
    bodySmall: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
  );
  final r12 = BorderRadius.circular(14);
  final r16 = BorderRadius.circular(20);
  const pill = StadiumBorder();
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
      shape: RoundedRectangleBorder(
        borderRadius: r16,
        side: BorderSide(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      shadowColor: dark ? Colors.transparent : const Color(0x14785A28),
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
      indicatorShape: pill,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => text.labelMedium?.copyWith(
          color: s.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant)),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primaryContainer,
      indicatorShape: pill,
      selectedIconTheme: IconThemeData(color: scheme.primary),
      unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      selectedLabelTextStyle: text.labelMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700),
      unselectedLabelTextStyle: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        shape: pill,
        textStyle: text.labelLarge?.copyWith(fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: pill,
        side: BorderSide(color: dark ? const Color(0xFF4A3D2F) : const Color(0xFFE2D5BC)),
        backgroundColor: dark ? const Color(0x14FFECCD) : Colors.white,
        foregroundColor: scheme.onSurface,
        textStyle: text.labelLarge?.copyWith(fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: pill, textStyle: text.labelLarge),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(pill),
        side: WidgetStatePropertyAll(BorderSide(color: border)),
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? scheme.primaryContainer : scheme.surface),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? scheme.onPrimaryContainer : scheme.onSurface),
        textStyle: WidgetStatePropertyAll(text.labelLarge),
        visualDensity: VisualDensity.standard,
      ),
    ),
    chipTheme: ChipThemeData(
      shape: pill,
      side: BorderSide(color: border),
      backgroundColor: scheme.surface,
      selectedColor: scheme.primaryContainer,
      labelStyle: text.labelLarge?.copyWith(color: scheme.onSurface),
      checkmarkColor: scheme.primary,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 3,
      highlightElevation: 5,
      shape: pill,
      extendedTextStyle: text.labelLarge?.copyWith(fontSize: 15),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(26),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(26),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(26),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: scheme.outline,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
    ),
    drawerTheme: DrawerThemeData(backgroundColor: scheme.surface, surfaceTintColor: Colors.transparent),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: border),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: r12),
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: Colors.transparent,
      indicatorSize: TabBarIndicatorSize.tab,
      indicator: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(22)),
      labelColor: scheme.onPrimaryContainer,
      unselectedLabelColor: scheme.onSurfaceVariant,
      labelStyle: text.labelLarge,
      unselectedLabelStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w500),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHigh,
      linearMinHeight: 5,
      borderRadius: BorderRadius.circular(3),
    ),
    checkboxTheme: CheckboxThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5))),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? (dark ? const Color(0xFF21180A) : Colors.white) : null),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? scheme.primary : null),
    ),
  );
}

/// Colour of a CEFR level (A1 … C2) on chips and badges.
Color cefrColor(String level) => switch (level) {
  'A1' || 'A2' => const Color(0xFF0E9F6E),
  'B1' => const Color(0xFF2563EB),
  'B2' => const Color(0xFF7C3AED),
  'C1' => const Color(0xFFE0752D),
  _ => const Color(0xFFDC2626),
};

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
      child: Text(text.toUpperCase(), style: t.textTheme.labelMedium?.copyWith(letterSpacing: 1.0, color: t.colorScheme.onSurfaceVariant)),
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: t.colorScheme.outlineVariant),
      ),
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

  /// Height when the cover fills a box; a book's usual shape otherwise.
  final double? height;
  final List<Color>? colors;

  /// The book's own cover picture, shown instead of the drawn cover.
  final File? image;
  const BookCover({super.key, required this.title, required this.format, this.width = 56, this.height, this.colors, this.image});

  @override
  Widget build(BuildContext context) {
    final c = colors ?? Brand.coverFor(title);
    if (image != null) {
      return Container(
        width: width,
        height: height ?? width * 1.42,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(width > 90 ? 14 : 8),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.file(
          image!,
          fit: BoxFit.cover,
          cacheWidth: (width * 3).round(),
          errorBuilder: (_, _, _) => BookCover(title: title, format: format, width: width, height: height, colors: colors),
        ),
      );
    }
    final initials = title.trim().isEmpty ? '?' : title.trim().characters.first.toUpperCase();
    return Container(
      width: width,
      height: height ?? width * 1.42,
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: c),
        borderRadius: BorderRadius.circular(width > 90 ? 14 : 8),
        boxShadow: [BoxShadow(color: c.last.withValues(alpha: 0.28), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: width > 90
          // A big cover reads like a real one: the title in the book font.
          ? Padding(
              padding: EdgeInsets.all(width * 0.09),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color(0xFFF4E7C8),
                      fontFamily: readingFont,
                      fontWeight: FontWeight.w700,
                      fontSize: width * 0.105,
                      height: 1.15,
                    ),
                  ),
                  Container(width: 34, height: 1, margin: const EdgeInsets.symmetric(vertical: 10), color: const Color(0x99F4E7C8)),
                  Text(
                    format.toUpperCase(),
                    style: TextStyle(color: const Color(0xCCF4E7C8), fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.5),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                Positioned(left: 5, top: 0, bottom: 0, child: Container(width: 1.5, color: Colors.white.withValues(alpha: 0.18))),
                Center(
                  child: Text(
                    initials,
                    style: TextStyle(color: Colors.white, fontFamily: readingFont, fontWeight: FontWeight.w700, fontSize: width * 0.44),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: width * 0.1,
                  child: Text(
                    format.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: width * 0.15, fontWeight: FontWeight.w700, letterSpacing: 1),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Page color behind the book text: warm paper by day, the night grey at night.
Color readerPaper(ThemeData t) => t.brightness == Brightness.dark ? Brand.dBg : const Color(0xFFFCFAF6);

/// The app logo (same art as the launcher icon).
class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 30});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * 0.28),
    child: Image.asset('assets/brand/logo.png', width: size, height: size, filterQuality: FilterQuality.medium),
  );
}
