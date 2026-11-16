import 'package:flutter/material.dart';

import '../ai/grammar_practice.dart';
import '../app_state.dart';
import '../l10n.dart';
import '../nlp/grammar_marks.dart';
import '../nlp/text.dart';
import 'grammar/grammar_page.dart';
import 'panel.dart';
import 'paragraph_view.dart';

/// Opens the explanation of the grammar structures on a tapped word (a tense,
/// a conditional …) with links to the matching Grammar topics.
/// [onWord] opens the word's own card instead.
Future<void> showGrammarMarkSheet(BuildContext context, AppState app, ParaAnalysis a, List<GMark> marks, int tokenIndex, {required VoidCallback onWord}) {
  return showPanel(context, (c, sc) => GrammarMarkPanel(app: app, analysis: a, marks: marks, tokenIndex: tokenIndex, scroll: sc, onWord: onWord));
}

String _tx(Tx t) => uiEnglish ? t.$2 : t.$1;

class GrammarMarkPanel extends StatelessWidget {
  final AppState app;
  final ParaAnalysis analysis;
  final List<GMark> marks;
  final int tokenIndex;
  final ScrollController? scroll;
  final VoidCallback onWord;
  const GrammarMarkPanel({super.key, required this.app, required this.analysis, required this.marks, required this.tokenIndex, this.scroll, required this.onWord});

  /// The sentence that holds token [i], as a [start, end) range of the paragraph.
  (int, int) _sentence(int i) {
    final t = analysis.tokens[i];
    for (final r in sentenceRanges(analysis.text)) {
      if (t.start >= r.$1 && t.start < r.$2) return r;
    }
    return (0, analysis.text.length);
  }

  Future<void> _openLesson(BuildContext context, String id) async {
    final topics = await loadGrammarTopics();
    final t = topics.where((t) => t.id == id).firstOrNull;
    if (t == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GrammarTopicPage(app: app, topic: t),
      ),
    );
  }

  Widget _card(BuildContext context, GMark m, List<GrammarTopic> topics) {
    final theme = Theme.of(context);
    final color = highlightColor(theme, m.cat, m);
    final cat = categoryById[m.cat]!;
    var (s0, s1) = _sentence(m.tokens.first);
    final text = analysis.text;
    while (s0 < s1 && text[s0].trim().isEmpty) {
      s0++;
    }
    // The sentence with the structure's words in its colour.
    final spans = <InlineSpan>[];
    var pos = s0;
    for (final i in m.tokens) {
      final t = analysis.tokens[i];
      if (t.start < pos || t.end > s1) continue;
      spans.add(TextSpan(text: text.substring(pos, t.start)));
      spans.add(
        TextSpan(
          text: t.text,
          style: TextStyle(color: color, fontWeight: FontWeight.w700, decoration: TextDecoration.underline, decorationColor: color, decorationThickness: 2),
        ),
      );
      pos = t.end;
    }
    spans.add(TextSpan(text: text.substring(pos, s1)));
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(left: BorderSide(color: color, width: 4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            uiEnglish ? cat.name : '${cat.tr} · ${cat.name}',
            style: theme.textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w700, letterSpacing: 0.4),
          ),
          const SizedBox(height: 4),
          Text(m.en, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          if (!uiEnglish) Text(m.tr, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(style: theme.textTheme.bodyLarge?.copyWith(height: 1.45), children: spans),
            key: ValueKey('gm-sentence-${m.key}'),
          ),
          const SizedBox(height: 10),
          Text(_tx(m.explain), style: theme.textTheme.bodyMedium),
          if (m.note != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline_rounded, size: 18, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(_tx(m.note!), style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (final id in m.lessons)
                if (topics.any((t) => t.id == id))
                  TextButton.icon(
                    key: ValueKey('gm-lesson-$id'),
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                    onPressed: () => _openLesson(context, id),
                    icon: const Icon(Icons.school_outlined, size: 18),
                    label: Text(L('Gramer konusu: ${topics.firstWhere((t) => t.id == id).title}', 'Grammar topic: ${topics.firstWhere((t) => t.id == id).title}')),
                  ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final word = analysis.tokens[tokenIndex].text;
    return FutureBuilder<List<GrammarTopic>>(
      future: loadGrammarTopics(),
      builder: (context, snap) {
        final topics = snap.data ?? const <GrammarTopic>[];
        return ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Text(L('Gramer', 'Grammar'), style: theme.textTheme.labelLarge?.copyWith(color: theme.hintColor, letterSpacing: 1.1)),
            const SizedBox(height: 10),
            for (final m in marks) _card(context, m, topics),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey('gm-word'),
                onPressed: () {
                  Navigator.of(context).pop();
                  onWord();
                },
                icon: const Icon(Icons.translate_rounded, size: 18),
                label: Text(L('"$word" kelimesinin anlamı', 'Meaning of "$word"')),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              L(
                'Bu işaretler kurallarla bulunur; emin olunmayan yerler işaretlenmez. Cümlenin tamamı için kelimeye uzun bas.',
                'These marks come from rules; places where they are not sure are left unmarked. Long press a word for the whole sentence.',
              ),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
          ],
        );
      },
    );
  }
}
