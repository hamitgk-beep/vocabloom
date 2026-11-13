import 'package:flutter/material.dart';

import '../l10n.dart';
import '../online/ai_service.dart';
import 'panel.dart';

const _posTr = {
  'verb': 'fiil', 'noun': 'isim', 'adjective': 'sıfat', 'adverb': 'zarf', 'preposition': 'edat',
  'conjunction': 'bağlaç', 'pronoun': 'zamir', 'determiner': 'belirleyici', 'interjection': 'ünlem',
};

/// Teacher-style senses: heading, explanation and examples, each in English
/// and Turkish as the language toggles say.
class SenseCards extends StatelessWidget {
  final List<ExprSense> senses;
  final bool en, tr;
  final Color color;

  /// Part of speech ("verb") of the sense used in the sentence, to mark it.
  final String? highlightPos;
  const SenseCards({super.key, required this.senses, required this.en, required this.tr, required this.color, this.highlightPos});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    var marked = false;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < senses.length; i++)
        () {
          final s = senses[i];
          final mark = !marked && highlightPos != null && s.pos == highlightPos;
          if (mark) marked = true;
          final pos = s.pos == null ? null : (uiEnglish ? s.pos! : (_posTr[s.pos!] ?? s.pos!));
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: color, width: 4)),
              color: mark ? color.withValues(alpha: 0.12) : theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (pos != null)
                Text(pos, style: theme.textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w600)),
              Text('${i + 1}. ${en || !tr ? s.titleEn : s.titleTr}',
                  style: (en || !tr ? enStyle(theme) : trStyle(theme)).copyWith(fontWeight: FontWeight.w700, fontSize: 16)),
              if (en && tr) Text(s.titleTr, style: trStyle(theme, const TextStyle(fontSize: 16))),
              if (mark)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(L('Bu cümledeki kullanımına en yakın anlam', 'Closest to its use in this sentence'),
                      style: theme.textTheme.labelSmall?.copyWith(color: color)),
                ),
              const SizedBox(height: 4),
              if (en || !tr) Text(s.explainEn, style: enStyle(theme, null, false)),
              if (tr) Padding(padding: EdgeInsets.only(top: en ? 2 : 0), child: Text(s.explainTr, style: trStyle(theme, null, false))),
              for (final ex in s.examples) ...[
                const SizedBox(height: 6),
                Text('• ${ex.$1}', style: enStyle(theme, const TextStyle(fontStyle: FontStyle.italic), false)),
                if (tr) Padding(padding: const EdgeInsets.only(left: 12), child: Text(ex.$2, style: trStyle(theme, null, false))),
              ],
            ]),
          );
        }(),
    ]);
  }
}
