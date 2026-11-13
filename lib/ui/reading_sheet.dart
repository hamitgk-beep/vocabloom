import 'package:flutter/material.dart';

import '../app_state.dart';
import '../l10n.dart';
import 'theme.dart';

const sepiaPaper = Color(0xFFF4ECD8);
const sepiaInk = Color(0xFF3B2F22);

/// Page color behind the book text for the chosen reading theme.
Color pageColor(AppState app, ThemeData t) =>
    t.brightness == Brightness.dark ? readerPaper(t) : (app.paper == 'sepia' ? sepiaPaper : readerPaper(t));

/// Theme used inside the reader, so sepia also changes the text color.
ThemeData readerTheme(AppState app, ThemeData t) {
  if (t.brightness == Brightness.dark || app.paper != 'sepia') return t;
  return t.copyWith(
    colorScheme: t.colorScheme.copyWith(onSurface: sepiaInk),
    textTheme: t.textTheme.apply(bodyColor: sepiaInk, displayColor: sepiaInk),
  );
}

/// Font size, line spacing and page color for the reader.
Future<void> showReadingSheet(BuildContext context, AppState app) => showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => ListenableBuilder(
        listenable: app,
        builder: (c, _) => _ReadingSheet(app: app),
      ),
    );

class _ReadingSheet extends StatelessWidget {
  final AppState app;
  const _ReadingSheet({required this.app});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = app.themeMode == ThemeMode.dark || (app.themeMode == ThemeMode.system && theme.brightness == Brightness.dark);
    final current = dark ? 'night' : app.paper;
    Widget swatch(String id, String label, Color bg, Color fg) {
      final on = current == id;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            if (id == 'night') {
              app.setTheme(ThemeMode.dark);
            } else {
              app.setReading(paper: id);
              app.setTheme(ThemeMode.light);
            }
          },
          child: Column(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 64,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: on ? theme.colorScheme.primary : theme.colorScheme.outlineVariant, width: on ? 2.5 : 1),
              ),
              alignment: Alignment.center,
              child: Text('Aa', style: TextStyle(fontFamily: readingFont, fontSize: 22, color: fg, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 6),
            Text(label, style: theme.textTheme.labelMedium?.copyWith(color: on ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant)),
          ]),
        ),
      );
    }

    final spacing = [(1.45, L('Sık', 'Tight')), (1.65, L('Normal', 'Normal')), (1.9, L('Geniş', 'Wide'))];
    final selSpacing = spacing.reduce((a, b) => (a.$1 - app.lineHeight).abs() <= (b.$1 - app.lineHeight).abs() ? a : b).$1;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(L('Okuma görünümü', 'Reading view'), style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          Row(children: [
            swatch('white', L('Beyaz', 'White'), const Color(0xFFFCFAF6), Brand.ink),
            const SizedBox(width: 10),
            swatch('sepia', L('Sepya', 'Sepia'), sepiaPaper, sepiaInk),
            const SizedBox(width: 10),
            swatch('night', L('Gece', 'Night'), Brand.dBg, Brand.dText),
          ]),
          const SizedBox(height: 22),
          Text(L('Yazı boyutu', 'Font size'), style: theme.textTheme.titleSmall),
          Row(children: [
            const Text('A', style: TextStyle(fontSize: 14, fontFamily: readingFont)),
            Expanded(
              child: Slider(
                value: app.fontSize,
                min: 14,
                max: 32,
                divisions: 18,
                label: app.fontSize.round().toString(),
                onChanged: app.setFont,
              ),
            ),
            const Text('A', style: TextStyle(fontSize: 26, fontFamily: readingFont)),
          ]),
          const SizedBox(height: 6),
          Text(L('Satır aralığı', 'Line spacing'), style: theme.textTheme.titleSmall),
          const SizedBox(height: 10),
          SegmentedButton<double>(
            showSelectedIcon: false,
            segments: [
              for (final (v, l) in spacing)
                ButtonSegment(value: v, label: Text(l), icon: Icon(v < 1.5 ? Icons.density_small_rounded : v < 1.8 ? Icons.density_medium_rounded : Icons.density_large_rounded)),
            ],
            selected: {selSpacing},
            onSelectionChanged: (s) => app.setReading(lineHeight: s.first),
          ),
        ]),
      ),
    );
  }
}
