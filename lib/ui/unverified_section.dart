import 'package:flutter/material.dart';

import '../l10n.dart';

/// The closed, labelled section with an entry's unreviewed AI drafts
/// (DictDb.sourcePolicy). Closed until tapped; [children] are built only then.
class UnverifiedAiSection extends StatefulWidget {
  final int count;
  final List<Widget> Function() children;
  const UnverifiedAiSection({super.key, required this.count, required this.children});

  @override
  State<UnverifiedAiSection> createState() => _UnverifiedAiSectionState();
}

class _UnverifiedAiSectionState extends State<UnverifiedAiSection> {
  bool open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Material(
        color: dark ? const Color(0x0EFFECCD) : Color.lerp(theme.colorScheme.surfaceContainerLowest, Colors.white, 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: dark ? const Color(0x1CFFE6BE) : theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              key: const ValueKey('unverified-ai-toggle'),
              onTap: () => setState(() => open = !open),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome_outlined, size: 20, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('${unverifiedAiSection()} (${widget.count})',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    ),
                    Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: theme.colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
            if (open) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Text(
                  L('Yapay zekâ taslağı; henüz kimse kontrol etmedi. Yanlış olabilir.',
                      'Drafted by AI and not checked by anyone yet. It may be wrong.'),
                  key: const ValueKey('unverified-ai-note'),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor, fontStyle: FontStyle.italic),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 12, 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: widget.children()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
