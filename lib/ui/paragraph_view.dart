import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../app_state.dart';
import '../data/user_db.dart';
import '../nlp/grammar_marks.dart';
import '../nlp/text.dart';
import 'theme.dart';

class ParaAnalysis {
  final String text;
  final List<Token> tokens;
  final List<Match> matches;
  ParaAnalysis(this.text, this.tokens, this.matches);

  List<GMark>? _grammar;

  /// Grammar structures (tenses, conditionals …), found the first time a
  /// grammar filter needs them.
  List<GMark> grammar(AppState app) => _grammar ??= app.grammar.mark(text, tokens);

  /// The highlight that colours token [i]: an enabled expression first (in
  /// display order), then an enabled grammar structure. Returns the
  /// expression category or the grammar mark.
  ({String? cat, GMark? mark}) shownAt(AppState app, int i) {
    String? best;
    final order = _catOrder;
    for (final m in matches) {
      if (!app.enabledCats.contains(m.expr.cat) || !m.tokens.contains(i)) continue;
      if (best == null || order[m.expr.cat]! < order[best]!) best = m.expr.cat;
    }
    if (best != null) return (cat: best, mark: null);
    if (!app.enabledCats.any(grammarCatIds.contains)) return (cat: null, mark: null);
    GMark? g;
    for (final m in grammar(app)) {
      if (!app.enabledCats.contains(m.cat) || !m.tokens.contains(i)) continue;
      if (g == null || order[m.cat]! < order[g.cat]!) g = m;
    }
    return (cat: g?.cat, mark: g);
  }

  /// Every enabled grammar structure on token [i], in filter order.
  List<GMark> grammarAt(AppState app, int i) {
    if (!app.enabledCats.any(grammarCatIds.contains)) return const [];
    final order = _catOrder;
    return [
      for (final m in grammar(app))
        if (app.enabledCats.contains(m.cat) && m.tokens.contains(i)) m,
    ]..sort((a, b) => order[a.cat]!.compareTo(order[b.cat]!));
  }
}

final _catOrder = {for (var i = 0; i < allCategories.length; i++) allCategories[i].id: i};

/// Colour of a highlight in the current theme.
Color highlightColor(ThemeData theme, String cat, [GMark? mark]) {
  final c = cat == 'g_tenses' && mark != null ? tenseToneColors[mark.tone] : categoryById[cat]!.color;
  return theme.brightness == Brightness.dark ? Color.lerp(c, Colors.white, 0.35)! : c;
}

final _cache = <String, ParaAnalysis>{};

ParaAnalysis analyze(AppState app, String text) {
  final c = _cache[text];
  if (c != null) return c;
  final toks = tokenize(text);
  final a = ParaAnalysis(text, toks, app.dict.matcher.match(toks));
  if (_cache.length > 3000) _cache.clear();
  _cache[text] = a;
  return a;
}

typedef WordTap = void Function(Para para, ParaAnalysis a, int tokenIndex);

/// One paragraph of the book, with highlights. Tap = word, long press = sentence.
class ParagraphView extends StatefulWidget {
  final AppState app;
  final Para para;
  final WordTap onWord;
  final WordTap onSentence;

  /// Sentence being read aloud in this paragraph ([start, end) in its text).
  final (int, int)? speaking;
  const ParagraphView({super.key, required this.app, required this.para, required this.onWord, required this.onSentence, this.speaking});

  @override
  State<ParagraphView> createState() => _ParagraphViewState();
}

class _ParagraphViewState extends State<ParagraphView> {
  final _key = GlobalKey();

  @override
  void didUpdateWidget(ParagraphView old) {
    super.didUpdateWidget(old);
    if (widget.speaking != null && widget.speaking != old.speaking) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _followSpeech());
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.speaking != null) WidgetsBinding.instance.addPostFrameCallback((_) => _followSpeech());
  }

  /// Keeps the sentence being read aloud in view (about a quarter from the top).
  void _followSpeech() {
    final r = widget.speaking;
    final ro = _key.currentContext?.findRenderObject();
    if (!mounted || r == null || ro is! RenderParagraph || !ro.attached) return;
    final scrollable = Scrollable.maybeOf(context);
    final vp = scrollable?.context.findRenderObject();
    if (scrollable == null || vp is! RenderBox) return;
    final boxes = ro.getBoxesForSelection(TextSelection(baseOffset: r.$1, extentOffset: r.$2));
    if (boxes.isEmpty) return;
    final top = ro.localToGlobal(Offset(0, boxes.first.top), ancestor: vp).dy;
    final bottom = ro.localToGlobal(Offset(0, boxes.last.bottom), ancestor: vp).dy;
    final h = vp.size.height;
    if (top >= 8 && bottom <= h - 24) return;
    final pos = scrollable.position;
    final target = (pos.pixels + top - h * 0.22).clamp(pos.minScrollExtent, pos.maxScrollExtent);
    pos.animateTo(target, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
  }

  int? _tokenAt(Offset local, ParaAnalysis a) {
    final ro = _key.currentContext?.findRenderObject();
    if (ro is! RenderParagraph) return null;
    final pos = ro.getPositionForOffset(local).offset;
    for (var i = 0; i < a.tokens.length; i++) {
      final t = a.tokens[i];
      if (pos >= t.start && pos <= t.end) {
        // make sure the pointer is really over the word box
        final boxes = ro.getBoxesForSelection(TextSelection(baseOffset: t.start, extentOffset: t.end));
        if (boxes.any((b) => b.toRect().inflate(3).contains(local))) return i;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final text = widget.para.text;
    final a = analyze(app, text);
    final theme = Theme.of(context);
    final heading = widget.para.kind == 'h';
    // A picture caption from a PDF: shown apart from the story text.
    final caption = widget.para.kind == 'c';
    final base = theme.textTheme.bodyLarge!.copyWith(
      fontSize: heading
          ? app.fontSize * 1.3
          : caption
          ? app.fontSize * 0.88
          : app.fontSize,
      height: app.lineHeight,
      fontWeight: heading ? FontWeight.w700 : FontWeight.w400,
      fontStyle: caption ? FontStyle.italic : null,
      color: caption ? theme.colorScheme.onSurfaceVariant : null,
      fontFamily: readingFont,
    );

    // category per token (first enabled category in display order wins;
    // expressions before grammar structures)
    final catOf = List<String?>.filled(a.tokens.length, null);
    final markOf = List<GMark?>.filled(a.tokens.length, null);
    final phraseStatus = List<WordStatus>.filled(a.tokens.length, WordStatus.none);
    final order = _catOrder;
    for (final m in a.matches) {
      final st = app.user.statuses[m.expr.phrase];
      if (st != null) {
        for (final t in m.tokens) {
          phraseStatus[t] = st;
        }
      }
      if (!app.enabledCats.contains(m.expr.cat)) continue;
      for (final t in m.tokens) {
        final cur = catOf[t];
        if (cur == null || order[m.expr.cat]! < order[cur]!) catOf[t] = m.expr.cat;
      }
    }
    if (app.enabledCats.any(grammarCatIds.contains)) {
      for (final m in a.grammar(app)) {
        if (!app.enabledCats.contains(m.cat)) continue;
        for (final t in m.tokens) {
          if (catOf[t] != null && markOf[t] == null) continue; // an expression is shown here
          final cur = markOf[t];
          if (cur == null || order[m.cat]! < order[cur.cat]!) {
            markOf[t] = m;
            catOf[t] = m.cat;
          }
        }
      }
    }
    Color? colorAt(int i) => catOf[i] == null ? null : highlightColor(theme, catOf[i]!, markOf[i]);

    final spans = <InlineSpan>[];
    var pos = 0;
    final sp = widget.speaking;
    final speakBg = theme.colorScheme.primary.withValues(alpha: theme.brightness == Brightness.dark ? 0.32 : 0.16);
    bool inSpeech(int a, int b) => sp != null && a >= sp.$1 && b <= sp.$2;
    for (var i = 0; i < a.tokens.length; i++) {
      final t = a.tokens[i];
      if (t.start > pos) {
        // underline the gap inside a multi-word expression (or one grammar structure) too
        final same = i > 0 && catOf[i] != null && catOf[i] == catOf[i - 1] && markOf[i] == markOf[i - 1];
        final gc = same ? colorAt(i) : null;
        spans.add(
          TextSpan(
            text: text.substring(pos, t.start),
            style: TextStyle(decoration: gc == null ? null : TextDecoration.underline, decorationColor: gc, decorationThickness: 2.2, backgroundColor: inSpeech(pos, t.start) ? speakBg : null),
          ),
        );
      }
      var st = app.statusOf(t);
      if (st == WordStatus.none) st = phraseStatus[i];
      final cat = catOf[i];
      final cc = cat == null ? null : colorAt(i);
      spans.add(
        TextSpan(
          text: t.text,
          style: TextStyle(
            backgroundColor: switch (st) {
              WordStatus.learning => learningColor.withValues(alpha: 0.38),
              WordStatus.learned => learnedColor.withValues(alpha: 0.32),
              _ => inSpeech(t.start, t.end) ? speakBg : null,
            },
            color: cc,
            decoration: cc == null ? null : TextDecoration.underline,
            decorationColor: cc,
            decorationThickness: 2.2,
            fontWeight: cc == null ? null : FontWeight.w600,
          ),
        ),
      );
      pos = t.end;
    }
    if (pos < text.length) spans.add(TextSpan(text: text.substring(pos)));

    return Padding(
      padding: EdgeInsets.only(bottom: heading ? 14 : 12, top: heading ? 12 : 0),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          final i = _tokenAt(d.localPosition, a);
          if (i != null) widget.onWord(widget.para, a, i);
        },
        onLongPressStart: (d) {
          final i = _tokenAt(d.localPosition, a);
          if (i != null) widget.onSentence(widget.para, a, i);
        },
        child: RichText(
          key: _key,
          text: TextSpan(style: base, children: spans),
          textScaler: MediaQuery.textScalerOf(context),
        ),
      ),
    );
  }
}
