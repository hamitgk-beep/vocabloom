import 'package:flutter/material.dart';
import '../l10n.dart';
import 'reading_sheet.dart';

/// Shows a detail panel (word, sentence, expression). On wide screens it
/// slides in as a tall card on the right, so the book stays readable beside
/// it; a tap on the book closes it. [left] puts it on the left instead (the
/// sentence panel, so it does not cover the word panel's place). On phones it
/// is a tall bottom sheet; [short] opens it at about [shortSize] of the screen
/// (the book stays visible above it) and it snaps up when pulled.
Future<T?> showPanel<T>(BuildContext context, Widget Function(BuildContext context, ScrollController? scroll) builder, {bool left = false, bool short = false}) {
  final size = MediaQuery.sizeOf(context);
  // Opened from the reader: the panel takes the page's colours (sepia stays sepia).
  final pt = readingPanelTheme;
  Widget themed(BuildContext c, ScrollController? sc) => pt == null ? builder(c, sc) : Theme(data: pt, child: Builder(builder: (c2) => builder(c2, sc)));
  if (size.width >= 720) {
    final width = (size.width * 0.42).clamp(380.0, 480.0);
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: L('Kapat', 'Close'),
      barrierColor: Colors.black.withValues(alpha: 0.12),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (c, _, _) {
        final t = pt ?? Theme.of(c);
        final dark = t.brightness == Brightness.dark;
        return SafeArea(
          child: Align(
            alignment: left ? Alignment.centerLeft : Alignment.centerRight,
            child: Padding(
              padding: left ? const EdgeInsets.fromLTRB(16, 14, 0, 16) : const EdgeInsets.fromLTRB(0, 14, 16, 16),
              child: Material(
                key: ValueKey(left ? 'side-panel-left' : 'side-panel'),
                color: dark ? const Color(0xFF241D16) : (pt != null ? pt.colorScheme.surfaceContainerLowest : const Color(0xFFFFFDF8)),
                elevation: 12,
                shadowColor: Colors.black.withValues(alpha: dark ? 0.5 : 0.18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                  side: BorderSide(color: dark ? const Color(0x24FFE6BE) : (pt != null ? pt.colorScheme.outlineVariant : const Color(0xFFEDE3D0))),
                ),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  width: width,
                  height: double.infinity,
                  child: Stack(children: [
                    Padding(padding: const EdgeInsets.only(top: 22), child: themed(c, null)),
                    Positioned(
                      right: 6,
                      top: 6,
                      child: IconButton(tooltip: L('Kapat', 'Close'), icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(c)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (c, a, _, child) {
        final curve = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween(begin: Offset(left ? -0.25 : 0.25, 0), end: Offset.zero).animate(curve),
          child: FadeTransition(opacity: curve, child: child),
        );
      },
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: pt?.colorScheme.surfaceContainerLowest,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: short ? shortSize : 0.9,
      minChildSize: short ? 0.3 : 0.4,
      maxChildSize: 1,
      snap: short,
      snapSizes: short ? const [shortSize, 0.9] : null,
      builder: (c, sc) => themed(c, sc),
    ),
  );
}

/// How much of a phone screen a short word panel takes when it opens.
const shortSize = 0.55;

/// English text: bold blue. Turkish text: bold in the normal text color.
/// So the two languages can be told apart at a glance.
Color enColor(ThemeData t) => t.brightness == Brightness.dark ? const Color(0xFF90CAF9) : const Color(0xFF1565C0);

TextStyle enStyle(ThemeData t, [TextStyle? base, bool bold = true]) =>
    (base ?? const TextStyle()).copyWith(color: enColor(t), fontWeight: bold ? FontWeight.w600 : null);

TextStyle trStyle(ThemeData t, [TextStyle? base, bool bold = true]) =>
    (base ?? const TextStyle()).copyWith(color: t.colorScheme.onSurface, fontWeight: bold ? FontWeight.w600 : null);
