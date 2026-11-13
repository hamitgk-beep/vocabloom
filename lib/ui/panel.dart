import 'package:flutter/material.dart';

/// Shows a detail panel (word, sentence, expression). On wide screens it is a
/// large centred window so nothing is cut off; on phones a tall bottom sheet.
Future<T?> showPanel<T>(BuildContext context, Widget Function(BuildContext context, ScrollController? scroll) builder) {
  final size = MediaQuery.sizeOf(context);
  if (size.width >= 720) {
    return showDialog<T>(
      context: context,
      builder: (c) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Stack(children: [
            Padding(padding: const EdgeInsets.only(top: 20), child: builder(c, null)),
            Positioned(
              right: 4,
              top: 4,
              child: IconButton(tooltip: 'Kapat', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(c)),
            ),
          ]),
        ),
      ),
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
