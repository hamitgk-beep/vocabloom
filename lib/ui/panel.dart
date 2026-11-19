import 'package:flutter/material.dart';
import '../l10n.dart';

/// Shows a detail panel (word, sentence, expression). On wide screens it
/// slides in as a tall card on the right, so the book stays readable beside
/// it; a tap on the book closes it. On phones it is a tall bottom sheet.
Future<T?> showPanel<T>(BuildContext context, Widget Function(BuildContext context, ScrollController? scroll) builder) {
  final size = MediaQuery.sizeOf(context);
  if (size.width >= 720) {
    final width = (size.width * 0.42).clamp(380.0, 480.0);
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: L('Kapat', 'Close'),
      barrierColor: Colors.black.withValues(alpha: 0.12),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (c, _, _) {
        final t = Theme.of(c);
        final dark = t.brightness == Brightness.dark;
        return SafeArea(
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 14, 16, 16),
              child: Material(
                key: const ValueKey('side-panel'),
                color: dark ? const Color(0xFF241D16) : const Color(0xFFFFFDF8),
                elevation: 12,
                shadowColor: Colors.black.withValues(alpha: dark ? 0.5 : 0.18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                  side: BorderSide(color: dark ? const Color(0x24FFE6BE) : const Color(0xFFEDE3D0)),
                ),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  width: width,
                  height: double.infinity,
                  child: Stack(children: [
                    Padding(padding: const EdgeInsets.only(top: 22), child: builder(c, null)),
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
          position: Tween(begin: const Offset(0.25, 0), end: Offset.zero).animate(curve),
          child: FadeTransition(opacity: curve, child: child),
        );
      },
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      minChildSize: 0.4,
      maxChildSize: 1,
      builder: (c, sc) => builder(c, sc),
    ),
  );
}

/// English text: bold blue. Turkish text: bold in the normal text color.
/// So the two languages can be told apart at a glance.
Color enColor(ThemeData t) => t.brightness == Brightness.dark ? const Color(0xFF90CAF9) : const Color(0xFF1565C0);

TextStyle enStyle(ThemeData t, [TextStyle? base, bool bold = true]) =>
    (base ?? const TextStyle()).copyWith(color: enColor(t), fontWeight: bold ? FontWeight.w600 : null);

TextStyle trStyle(ThemeData t, [TextStyle? base, bool bold = true]) =>
    (base ?? const TextStyle()).copyWith(color: t.colorScheme.onSurface, fontWeight: bold ? FontWeight.w600 : null);
