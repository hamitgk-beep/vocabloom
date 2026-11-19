import 'package:flutter/material.dart';

import '../app_state.dart';
import '../l10n.dart';
import '../nlp/text.dart';
import 'meaning_parts.dart';

/// What the mouse bubble shows for a word: the head word (or expression),
/// its part of speech and its first Turkish meaning.
typedef HoverMeaning = ({String head, String? pos, String tr});

/// The first meaning of token [i]: an underlined expression it is part of
/// (one whose filter is on) first, otherwise the word's own dictionary
/// meaning, otherwise its main Turkish meaning. Null when nothing Turkish is
/// known, so no bubble with English only appears.
HoverMeaning? hoverMeaning(AppState app, List<Token> tokens, List<Match> matches, int i) {
  Match? best;
  for (final m in matches) {
    if (m.tokens.length < 2 || !m.tokens.contains(i) || !app.enabledCats.contains(m.expr.cat) || m.expr.trShown == null) continue;
    if (best == null || m.tokens.length > best.tokens.length) best = m;
  }
  if (best != null) return (head: displayPhrase(best.expr.phrase), pos: null, tr: best.expr.trShown!);

  final lower = tokens[i].lower.replaceAll('’', "'");
  final dict = app.dict;
  final cands = <String>[...?dict.irregularOf[lower], ...dict.lemmatizer.lemmas(lower), lower];
  // A common word beats a rare base form the suffix rules make ("never", not "neve").
  if (cands.contains(lower) && dict.ownSenses(lower).isNotEmpty && dict.irregularOf[lower] == null) {
    cands.remove(lower);
    cands.insert(0, lower);
  }
  for (final c in cands) {
    final own = dict.ownSenses(c);
    if (own.isNotEmpty) return (head: c, pos: own.first.pos, tr: own.first.tr);
  }
  for (final c in cands) {
    final info = dict.lookup(c);
    if (info.trFreeDict.isNotEmpty) return (head: c, pos: null, tr: info.trFreeDict.first);
    for (final s in info.senses) {
      if (s.tr.isNotEmpty) return (head: c, pos: posLabel(s.pos), tr: s.tr.take(3).join(', '));
    }
  }
  return null;
}

/// The small bubble over a word under the mouse.
class HoverBubble extends StatelessWidget {
  final HoverMeaning m;
  const HoverBubble({super.key, required this.m});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final dark = t.brightness == Brightness.dark;
    return Material(
      key: const ValueKey('hover-bubble'),
      color: dark ? const Color(0xFF2A221A) : Color.lerp(cs.surfaceContainerLowest, Colors.white, 0.4),
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: dark ? 0.5 : 0.25),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: dark ? const Color(0x24FFE6BE) : cs.outlineVariant),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 150, maxWidth: 300),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 9),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: m.head,
                      style: TextStyle(fontFamily: 'Literata', fontWeight: FontWeight.w700, fontSize: 17, color: cs.onSurface),
                    ),
                    if (m.pos != null && m.pos!.isNotEmpty)
                      TextSpan(
                        text: '   ${m.pos}',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 3),
              Text(
                m.tr,
                style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, height: 1.25, color: cs.onSurface),
              ),
              const SizedBox(height: 6),
              Text(L('Ayrıntılar için tıkla', 'Click for details'), style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}
