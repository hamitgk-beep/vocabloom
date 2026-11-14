import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../app_state.dart';
import '../data/user_db.dart';
import '../nlp/text.dart';
import 'theme.dart';

class ParaAnalysis {
  final List<Token> tokens;
  final List<Match> matches;
  ParaAnalysis(this.tokens, this.matches);
}

final _cache = <String, ParaAnalysis>{};

ParaAnalysis analyze(AppState app, String text) {
  final c = _cache[text];
  if (c != null) return c;
  final toks = tokenize(text);
  final a = ParaAnalysis(toks, app.dict.matcher.match(toks));
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
    final base = theme.textTheme.bodyLarge!.copyWith(
      fontSize: heading ? app.fontSize * 1.3 : app.fontSize,
      height: app.lineHeight,
      fontWeight: heading ? FontWeight.w700 : FontWeight.w400,
      fontFamily: readingFont,
    );

    // category per token (first enabled category in display order wins)
    final catOf = List<String?>.filled(a.tokens.length, null);
    final phraseStatus = List<WordStatus>.filled(a.tokens.length, WordStatus.none);
    final order = {for (var i = 0; i < categories.length; i++) categories[i].id: i};
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

    final spans = <InlineSpan>[];
    var pos = 0;
    final sp = widget.speaking;
    final speakBg = theme.colorScheme.primary.withValues(alpha: theme.brightness == Brightness.dark ? 0.32 : 0.16);
    bool inSpeech(int a, int b) => sp != null && a >= sp.$1 && b <= sp.$2;
    for (var i = 0; i < a.tokens.length; i++) {
      final t = a.tokens[i];
      if (t.start > pos) {
        // underline the gap inside a multi-word expression too
        final gapCat = i > 0 && catOf[i] != null && catOf[i] == catOf[i - 1] ? catOf[i] : null;
        final gc = gapCat == null ? null : categoryById[gapCat]!.color;
        spans.add(TextSpan(
          text: text.substring(pos, t.start),
          style: TextStyle(
            decoration: gc == null ? null : TextDecoration.underline,
            decorationColor: gc,
            decorationThickness: 2.2,
            backgroundColor: inSpeech(pos, t.start) ? speakBg : null,
          ),
        ));
      }
      var st = app.statusOf(t);
      if (st == WordStatus.none) st = phraseStatus[i];
      final cat = catOf[i];
      final dark = theme.brightness == Brightness.dark;
      final cc0 = cat == null ? null : categoryById[cat]!.color;
      final cc = cc0 == null || !dark ? cc0 : Color.lerp(cc0, Colors.white, 0.35);
      spans.add(TextSpan(
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
      ));
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
        child: RichText(key: _key, text: TextSpan(style: base, children: spans), textScaler: MediaQuery.textScalerOf(context)),
      ),
    );
  }
}
