import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../app_state.dart';
import '../data/user_db.dart';
import '../nlp/grammar_marks.dart';
import '../nlp/text.dart';
import 'hover_meaning.dart';
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

  final Map<Match, bool> _literal = {};

  /// Whether [m] is used literally here ("lived in Kansas"), computed once.
  bool _isLiteral(AppState app, Match m) => _literal.putIfAbsent(m, () {
    // The literal check is for phrasal verbs ("lived in Kansas"); an idiom
    // or collocation found in its own words is the expression.
    if (m.expr.cat != 'phrasal_verbs') return false;
    try {
      return app.senses.isLiteral(m.expr, tokens, m.tokens);
    } catch (_) {
      return false;
    }
  });

  /// The expressions that cover token [i] and are on in the filters, not
  /// used literally, the longest first (then in filter order). One rule for
  /// the underline, the tap and the panel, so they always agree.
  List<Match> expressionsAt(AppState app, int i) {
    final order = _catOrder;
    return [
      for (final m in matches)
        if (app.enabledCats.contains(m.expr.cat) && m.tokens.contains(i) && !_isLiteral(app, m)) m,
    ]..sort((x, y) {
      final byLen = y.tokens.length.compareTo(x.tokens.length);
      return byLen != 0 ? byLen : order[x.expr.cat]!.compareTo(order[y.expr.cat]!);
    });
  }

  /// The expression category underlined on each token: the expression a tap
  /// on that token opens ([expressionsAt]), or null.
  List<String?> expressionCats(AppState app) => [for (var i = 0; i < tokens.length; i++) expressionsAt(app, i).firstOrNull?.expr.cat];

  /// The highlight that colours token [i]: the expression [expressionsAt]
  /// picks, else an enabled grammar structure. Returns the expression
  /// category or the grammar mark.
  ({String? cat, GMark? mark}) shownAt(AppState app, int i) {
    final e = expressionsAt(app, i);
    if (e.isNotEmpty) return (cat: e.first.expr.cat, mark: null);
    final order = _catOrder;
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
  final a = ParaAnalysis(text, toks, app.dict.matcher.match(toks, text: text));
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

  // ---------------------------------------------------------------- mouse
  // Pointing at a word with the mouse shows its first meaning in a small
  // bubble above it, without a click; a click opens the full panel.
  OverlayEntry? _bubble;
  int? _hoverToken;
  Timer? _hoverTimer;

  void _hover(Offset local, ParaAnalysis a) {
    final i = _tokenAt(local, a);
    if (i == _hoverToken) return;
    _hideBubble();
    _hoverToken = i;
    if (i == null) return;
    _hoverTimer = Timer(const Duration(milliseconds: 120), () => _showBubble(a, i));
  }

  void _showBubble(ParaAnalysis a, int i) {
    final ro = _key.currentContext?.findRenderObject();
    if (!mounted || ro is! RenderParagraph || !ro.attached) return;
    final m = hoverMeaning(widget.app, a.tokens, a.matches, i, text: widget.para.text);
    if (m == null) return;
    final t = a.tokens[i];
    final boxes = ro.getBoxesForSelection(TextSelection(baseOffset: t.start, extentOffset: t.end));
    if (boxes.isEmpty) return;
    final overlay = Overlay.maybeOf(context);
    final ob = overlay?.context.findRenderObject();
    if (overlay == null || ob is! RenderBox) return;
    final word = boxes.first.toRect();
    final topLeft = ro.localToGlobal(word.topLeft, ancestor: ob);
    final theme = Theme.of(context);
    final size = ob.size;
    _bubble = OverlayEntry(
      builder: (_) => Positioned(
        left: (topLeft.dx - 14).clamp(8.0, (size.width - 308).clamp(8.0, double.infinity)),
        bottom: size.height - topLeft.dy + 6,
        child: IgnorePointer(
          child: Theme(
            data: theme,
            child: HoverBubble(m: m),
          ),
        ),
      ),
    );
    overlay.insert(_bubble!);
  }

  void _hideBubble() {
    _hoverTimer?.cancel();
    _hoverTimer = null;
    _bubble?.remove();
    _bubble = null;
  }

  @override
  void dispose() {
    _hideBubble();
    super.dispose();
  }

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
    // A book with known type sizes (a PDF) is shown with the same sizes in
    // proportion: a large title stays large, a small note small.
    final para = widget.para;
    final known = para.meta['pg'] != null && (para.meta.containsKey('sz') || para.meta.containsKey('al'));
    final scale = known || para.meta.containsKey('sz')
        ? para.size.clamp(0.7, 2.4)
        : heading
        ? 1.3
        : caption
        ? 0.88
        : 1.0;
    final base = theme.textTheme.bodyLarge!.copyWith(
      fontSize: app.fontSize * scale,
      height: app.lineHeight,
      fontWeight: heading || (known && para.size >= 1.3 && para.text.length < 80) ? FontWeight.w700 : FontWeight.w400,
      fontStyle: caption ? FontStyle.italic : null,
      color: caption ? theme.colorScheme.onSurfaceVariant : null,
      fontFamily: readingFont,
    );

    // category per token: the expression the tap opens (the same rule,
    // expressionsAt), then grammar structures
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
    }
    final ec = a.expressionCats(app);
    for (var t = 0; t < a.tokens.length; t++) {
      catOf[t] = ec[t];
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
            style: TextStyle(
              decoration: gc == null ? null : TextDecoration.underline,
              decorationColor: gc,
              decorationThickness: 2.2,
              backgroundColor: inSpeech(pos, t.start) ? speakBg : null,
            ),
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

    final align = switch (para.align) {
      'c' => TextAlign.center,
      'r' => TextAlign.right,
      'j' => TextAlign.justify,
      _ => caption ? TextAlign.center : TextAlign.start,
    };
    // Lines of a table of contents sit close together.
    final toc = para.meta['toc'] != null;
    return Padding(
      padding: EdgeInsets.only(bottom: toc ? 4 : (heading ? 14 : 12), top: heading ? 12 : 0),
      child: MouseRegion(
        onHover: (e) => _hover(e.localPosition, a),
        onExit: (_) {
          _hideBubble();
          _hoverToken = null;
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            _hideBubble();
            final i = _tokenAt(d.localPosition, a);
            if (i != null) widget.onWord(widget.para, a, i);
          },
          onLongPressStart: (d) {
            final i = _tokenAt(d.localPosition, a);
            if (i != null) widget.onSentence(widget.para, a, i);
          },
          child: RichText(
            key: _key,
            textAlign: align,
            text: TextSpan(style: base, children: spans),
            textScaler: MediaQuery.textScalerOf(context),
          ),
        ),
      ),
    );
  }
}
