import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../nlp/text.dart';
import 'word_sheet.dart';

/// The app the word and expression panels were opened with, so any English
/// text inside them can open a word's own panel when tapped.
AppState? panelApp;

/// English text in which every word can be tapped to open its meaning.
class TapText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  /// Words drawn bold and underlined (e.g. the expression in its sentence).
  final Set<String>? highlight;
  const TapText(this.text, {super.key, this.style, this.highlight});

  @override
  State<TapText> createState() => _TapTextState();
}

class _TapTextState extends State<TapText> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  bool _hl(Token t) {
    final h = widget.highlight;
    if (h == null || h.isEmpty) return false;
    return h.contains(t.lower) || h.any((x) => t.lower.startsWith(x) && t.lower.length <= x.length + 3);
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    final app = panelApp;
    final s = widget.text;
    final spans = <TextSpan>[];
    var pos = 0;
    for (final t in tokenize(s)) {
      if (t.start > pos) spans.add(TextSpan(text: s.substring(pos, t.start)));
      final word = RegExp(r'[A-Za-z]').hasMatch(t.text);
      TapGestureRecognizer? r;
      if (word && app != null) {
        r = TapGestureRecognizer()..onTap = () => showWordSheet(context, app, t.text);
        _recognizers.add(r);
      }
      spans.add(TextSpan(
        text: t.text,
        recognizer: r,
        style: _hl(t) ? const TextStyle(fontWeight: FontWeight.w800, decoration: TextDecoration.underline) : null,
      ));
      pos = t.end;
    }
    if (pos < s.length) spans.add(TextSpan(text: s.substring(pos)));
    return Text.rich(TextSpan(style: widget.style, children: spans));
  }
}
