/// Reading order for one PDF page from where its letters are.
///
/// PDFium gives a page's text line by line, but a book page also holds
/// running headers ("Aladdin and the Enchanted Lamp" on every other page),
/// page numbers and picture captions. A caption that sits beside the text
/// even ends up inside a line of the story ("Abanazar had tears in his eyes.
/// because I am a rich"). [layoutPdfPage] looks at the letter boxes to tell
/// these apart:
///
/// * captions and other notes are set in smaller type than the story, so a
///   part of a line whose letters are clearly smaller is pulled out;
/// * the first and last line of a page are marked as possible headers or
///   footers; [buildBookFromPages] drops the ones that repeat on many pages;
/// * paragraphs start at an indent, after a larger gap, or after a short line
///   that ends a sentence.
///
/// The result is text that [buildBookFromPages] reads: it starts with
/// [layoutMark], paragraphs are separated by blank lines, an edge line starts
/// with [edgeMark] followed by `s` (small type) or `n`, and a caption starts
/// with [captionMark].
library;

import 'pdf_pictures.dart';
import 'word_gaps.dart';

const layoutMark = '\u0004';
const edgeMark = '\u0003';
const captionMark = '\u0002';

/// A page number line: "12", "- 12 -", "Page 12", "12 / 80", "Sayfa 12".
final pageNumberLine = RegExp(r'^\W*(?:page|p\.|sayfa|seite)?\s*(\d{1,4})(?:\s*(?:of|/|von)\s*\d{1,4})?\W*$', caseSensitive: false);

double _median(List<double> v) {
  if (v.isEmpty) return 0;
  final s = [...v]..sort();
  return s[s.length ~/ 2];
}

class _Piece {
  final int start, end; // indices into the page text
  final double left, right, top, bottom;
  final bool small;
  String text;
  _Piece(this.start, this.end, this.left, this.right, this.top, this.bottom, this.small, this.text);
}

class _Line {
  final List<_Piece> body = [];
  final List<_Piece> small = [];
  double top = -1e9, bottom = 1e9, left = 1e9, right = -1e9;
  bool large = false; // set in bigger type than the text: a heading
  bool quote = false; // a block of smaller type inside the text
  bool get isEmpty => body.isEmpty && small.isEmpty;
  String get bodyText => body.map((p) => p.text).join(' ');
  String get allText => [...body, ...small].map((p) => p.text).join(' ');
  bool get allSmall => body.isEmpty && small.isNotEmpty;
}

/// Where a paragraph or caption of the page is and how it is set: what the
/// reader needs to show it the way the book does (size, centred or not) and
/// to put the pictures between the right paragraphs.
class LayoutBlock {
  /// Letters only, lower case: finds the block again after the text repairs.
  final String key;
  final bool caption;
  final double top, bottom;

  /// Left and right end of each line, top to bottom.
  final List<(double, double)> lines;

  /// Height of a small letter (x-height) in PDF points, null when unknown.
  final double? xHeight;
  LayoutBlock(this.key, this.caption, this.top, this.bottom, this.lines, this.xHeight);
}

String layoutKey(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');

/// [boxes] has one entry per character of [text] (PDF coordinates, top >
/// bottom). Returns `null` when the boxes do not match the text. When
/// [blocks] is given, it gets one entry per paragraph and caption.
///
/// [dropCaps] are large first letters drawn as pictures (see [findPictures]):
/// each goes back in front of the line beside it, which starts a paragraph.
String? layoutPdfPage(
  String text,
  List<GlyphBox> boxes, {
  bool Function(String word)? isWord,
  List<LayoutBlock>? blocks,
  List<InkLetter> dropCaps = const [],
}) {
  if (boxes.length != text.length) return null;
  bool hasBox(int i) {
    final b = boxes[i];
    return b.right > b.left && b.top > b.bottom && text[i].trim().isNotEmpty;
  }

  // Page statistics: typical letter width, and how tall each letter usually is
  // on this page (that is the main text, which has most of the letters).
  final widths = <double>[];
  final heightsOf = <String, List<double>>{};
  for (var i = 0; i < text.length; i++) {
    if (!hasBox(i)) continue;
    final b = boxes[i];
    if (!RegExp(r'[A-Za-z]').hasMatch(text[i])) continue;
    widths.add(b.right - b.left);
    (heightsOf[text[i]] ??= []).add(b.top - b.bottom);
  }
  if (widths.length < 5) return null;
  final cw = _median(widths);
  final ref = {for (final e in heightsOf.entries) if (e.value.length >= 3) e.key: _median(e.value)};
  final sized = widths.length >= 40;

  /// Letter size of text[a..b) compared with the main text (1 = same), null when too few letters.
  double? ratio(int a, int b) {
    if (!sized) return null;
    final rs = [
      for (var k = a; k < b; k++)
        if (hasBox(k) && ref[text[k]] != null && ref[text[k]]! > 0) (boxes[k].top - boxes[k].bottom) / ref[text[k]]!
    ];
    return rs.length < 3 ? null : _median(rs);
  }

  // Size of the type of the lines [ls]: x-height from the small letters
  // without ascenders, or from capitals (about 0.68 of their height).
  double? xHeightOf(Iterable<_Line> ls) {
    final hs = <double>[];
    for (final l in ls) {
      for (final pc in [...l.body, ...l.small]) {
        for (var k = pc.start; k < pc.end; k++) {
          if (!hasBox(k)) continue;
          final c = text[k], h = boxes[k].top - boxes[k].bottom;
          if ('acemnorsuvwxz'.contains(c)) {
            hs.add(h);
          } else if ('ABCDEFHIKLMNOPRSTUVWXYZ'.contains(c)) {
            hs.add(h * 0.68);
          }
        }
      }
    }
    return hs.length < 2 ? null : _median(hs);
  }

  // 1. lines, cut into pieces of main-size and small type.
  final lines = <_Line>[];
  var ls = 0;
  for (var i = 0; i <= text.length; i++) {
    if (i < text.length && text[i] != '\n' && text[i] != '\r') continue;
    final line = _Line();
    // Runs of letters with no wide gap between them.
    final runs = <(int, int)>[];
    var rs = -1, last = -1;
    for (var k = ls; k < i; k++) {
      if (!hasBox(k)) continue;
      if (rs < 0) {
        rs = k;
      } else if (boxes[k].left - boxes[last].right > 1.5 * cw) {
        runs.add((rs, last + 1));
        rs = k;
      }
      last = k;
    }
    if (rs >= 0) runs.add((rs, last + 1));
    // A letter with an empty box right after a run (text recognition gives
    // some letters no width: "tall" as "ta" + "l" + "l" of width 0) still
    // belongs to its word.
    for (var q = 0; q < runs.length; q++) {
      var e = runs[q].$2;
      final next = q + 1 < runs.length ? runs[q + 1].$1 : i;
      while (e < next && text[e].trim().isNotEmpty && !hasBox(e)) {
        e++;
      }
      runs[q] = (runs[q].$1, e);
    }
    double rightOf((int, int) r) {
      var e = r.$2 - 1;
      while (e > r.$1 && !hasBox(e)) {
        e--;
      }
      return boxes[e].right;
    }

    // Size class of each run: true = small, false = main, null = too few letters to tell.
    bool? sizeOf(int a, int b) {
      final r = ratio(a, b);
      return r == null ? null : r < 0.93;
    }

    final cls = [for (final r in runs) sizeOf(r.$1, r.$2)];
    for (var k = 0; k < cls.length; k++) {
      if (cls[k] != null) continue;
      bool? near;
      for (var d = 1; d < cls.length && near == null; d++) {
        if (k - d >= 0 && cls[k - d] != null) near = cls[k - d];
        if (near == null && k + d < cls.length && cls[k + d] != null) near = cls[k + d];
      }
      cls[k] = near ?? false;
    }
    // A line splits into small and main type only where there is a clear gap
    // (a caption beside the text); italics or a word in capitals inside a line do not.
    if (cls.toSet().length > 1) {
      var clear = true;
      for (var q = 1; q < runs.length; q++) {
        if (cls[q] != cls[q - 1] && boxes[runs[q].$1].left - rightOf(runs[q - 1]) < 2.2 * cw) clear = false;
      }
      if (!clear) {
        var small = 0, main = 0;
        for (var q = 0; q < runs.length; q++) {
          if (cls[q]!) {
            small += runs[q].$2 - runs[q].$1;
          } else {
            main += runs[q].$2 - runs[q].$1;
          }
        }
        cls.fillRange(0, cls.length, small > main);
      }
    }
    // Merge neighbouring runs of the same class into pieces.
    var k = 0;
    while (k < runs.length) {
      var e = k;
      while (e + 1 < runs.length && cls[e + 1] == cls[k]) {
        e++;
      }
      final a = runs[k].$1, b = runs[e].$2;
      double l = 1e9, r = -1e9, t = -1e9, bt = 1e9;
      for (var q = a; q < b; q++) {
        if (!hasBox(q)) continue;
        final bx = boxes[q];
        if (bx.left < l) l = bx.left;
        if (bx.right > r) r = bx.right;
        if (bx.top > t) t = bx.top;
        if (bx.bottom < bt) bt = bx.bottom;
      }
      final sub = text.substring(a, b);
      final s = (isWord == null ? sub : addGapSpaces(sub, boxes.sublist(a, b), isWord)).trim();
      final piece = _Piece(a, b, l, r, t, bt, cls[k]!, s);
      (piece.small ? line.small : line.body).add(piece);
      if (l < line.left) line.left = l;
      if (r > line.right) line.right = r;
      if (t > line.top) line.top = t;
      if (bt < line.bottom) line.bottom = bt;
      k = e + 1;
    }
    final r = line.body.isEmpty ? null : ratio(line.body.first.start, line.body.last.end);
    line.large = r != null && r > 1.15;
    if (!line.isEmpty) lines.add(line);
    ls = i + 1;
  }
  if (lines.isEmpty) return null;

  // A line made only of small type that is part of a bigger small block
  // (a whole page of notes, a glossary) is main text for that page.
  final smallChars = lines.fold<int>(0, (a, l) => a + l.small.fold<int>(0, (b, p) => b + p.text.length));
  final allChars = lines.fold<int>(0, (a, l) => a + l.allText.length);
  void toBody(_Line l) {
    l.body
      ..addAll(l.small)
      ..sort((a, b) => a.left.compareTo(b.left));
    l.small.clear();
  }

  if (smallChars > allChars * 0.6) {
    lines.forEach(toBody);
  } else {
    // Four or more whole lines of small type in a row are a poem, a letter or a
    // quotation in the story, not a caption: they stay where they are, as
    // their own paragraph.
    var k = 0;
    while (k < lines.length) {
      var e = k;
      while (e < lines.length && lines[e].allSmall) {
        e++;
      }
      if (e - k >= 4) {
        for (var q = k; q < e; q++) {
          toBody(lines[q]);
          lines[q].quote = true;
        }
      }
      k = e == k ? k + 1 : e;
    }
  }

  // Line pitch of the main text.
  final mid = [for (final l in lines) (l.top + l.bottom) / 2];
  final pitches = <double>[];
  for (var i = 1; i < lines.length; i++) {
    final d = mid[i - 1] - mid[i];
    if (d > 0 && lines[i].body.isNotEmpty && lines[i - 1].body.isNotEmpty) pitches.add(d);
  }
  final pitch = pitches.isEmpty ? 14.0 : _median(pitches);

  // 2. header and footer candidates: the top and bottom line of the page when
  // they stand apart from the text or are set small.
  final edge = <int>{};
  final order = List.generate(lines.length, (i) => i)..sort((a, b) => mid[b].compareTo(mid[a]));
  bool apart(int i, int j) => (mid[i] - mid[j]).abs() > pitch * 1.7;
  bool number(int i) => pageNumberLine.hasMatch(lines[i].allText);
  if (lines.length >= 2) {
    final t = order.first, t2 = order[1];
    if (lines[t].allSmall || apart(t, t2) || number(t)) edge.add(t);
    final b = order.last, b2 = order[order.length - 2];
    if (lines[b].allSmall || apart(b, b2) || number(b)) edge.add(b);
    // A page number under a footer line, or a header over a number.
    if (edge.contains(b) && number(b) && lines.length >= 3 && order.length > 2) {
      final b3 = order[order.length - 3];
      if (lines[b2].allSmall && apart(b2, b3)) edge.add(b2);
    }
  }

  // Small type in the flow of the text (a short poem, a quotation) stays where
  // it is. Small type beside the text, or with empty space above or below it
  // (where a picture is), is a caption.
  {
    final bodyLines = [for (var i = 0; i < lines.length; i++) if (!edge.contains(i) && lines[i].body.isNotEmpty) i];
    final smallIdx = [for (final i in order) if (!edge.contains(i) && lines[i].small.isNotEmpty) i];
    var k = 0;
    while (k < smallIdx.length) {
      var e = k + 1;
      while (e < smallIdx.length && mid[smallIdx[e - 1]] - mid[smallIdx[e]] <= pitch * 1.6) {
        e++;
      }
      final block = smallIdx.sublist(k, e);
      final top = mid[block.first], bottom = mid[block.last];
      final beside = block.any((i) => lines[i].body.isNotEmpty);
      var gapA = double.infinity, gapB = double.infinity;
      final l = block.map((i) => lines[i].small.first.left).reduce((a, b) => a < b ? a : b);
      final r = block.map((i) => lines[i].small.last.right).reduce((a, b) => a > b ? a : b);
      for (final j in bodyLines) {
        // Only text above or below it counts, not a column beside it.
        final bl = lines[j].body.first.left, br = lines[j].body.last.right;
        final overlap = (r < br ? r : br) - (l > bl ? l : bl);
        if (overlap < 0.3 * ((r - l) < (br - bl) ? (r - l) : (br - bl))) continue;
        final m = mid[j];
        if (m > top && m - top < gapA) gapA = m - top;
        if (m < bottom && bottom - m < gapB) gapB = bottom - m;
      }
      final caption = beside || gapA > pitch * 2.5 || gapB > pitch * 2.5;
      if (!caption) {
        for (final i in block) {
          toBody(lines[i]);
          lines[i].quote = true;
        }
      }
      k = e;
    }
  }

  // 3. paragraphs of the main text.
  final bodyIdx = [for (var i = 0; i < lines.length; i++) if (!edge.contains(i) && lines[i].body.isNotEmpty) i];
  final widthsBody = [for (final i in bodyIdx) lines[i].body.last.right - lines[i].body.first.left]..sort();
  final typical = widthsBody.isEmpty ? 0.0 : widthsBody[(widthsBody.length * 0.8).floor().clamp(0, widthsBody.length - 1)];
  final sentenceEnd = RegExp(r'''([.!?]['"”’)]?|[:;"”’)])$''');
  // The left margin most lines start at; a paragraph's first line starts a little to the right of it.
  final lefts = <int, int>{};
  for (final i in bodyIdx) {
    final k = lines[i].body.first.left.round();
    lefts[k] = (lefts[k] ?? 0) + 1;
  }
  int near(int k) => (lefts[k - 1] ?? 0) + (lefts[k] ?? 0) + (lefts[k + 1] ?? 0);
  final margin = lefts.isEmpty ? 0.0 : lefts.keys.reduce((a, b) => near(a) >= near(b) ? a : b).toDouble();
  final paras = <String>[];
  final buf = <String>[];
  final bufLines = <_Line>[];
  void note(String t, List<_Line> ls, bool caption, {bool small = false}) {
    if (blocks == null || ls.isEmpty) return;
    blocks.add(LayoutBlock(
      layoutKey(t),
      caption,
      ls.map((l) => l.top).reduce((a, b) => a > b ? a : b),
      ls.map((l) => l.bottom).reduce((a, b) => a < b ? a : b),
      [
        for (final l in ls)
          if ((small ? l.small : l.body).isNotEmpty) ((small ? l.small : l.body).first.left, (small ? l.small : l.body).last.right)
      ],
      xHeightOf(ls),
    ));
  }

  void flush() {
    if (buf.isNotEmpty) {
      paras.add(buf.join('\n'));
      note(paras.last, bufLines, false);
    }
    buf.clear();
    bufLines.clear();
  }

  // Drop caps: the letter goes in front of the first line beside it.
  final capStart = <int>{};
  if (isWord != null) {
    for (final cap in dropCaps) {
      for (var n = 0; n < bodyIdx.length; n++) {
        final l = lines[bodyIdx[n]];
        final first = l.body.first;
        if (first.left < cap.right - cw || first.left - cap.right > 4 * cw) continue;
        if (l.top > cap.top + pitch * 0.8 || l.top < cap.top - pitch * 1.2) continue;
        final letter = dropCapLetter(first.text, cap, isWord);
        if (letter != null) {
          first.text = '$letter${first.text}';
          capStart.add(n);
        }
        break;
      }
    }
  }

  for (var n = 0; n < bodyIdx.length; n++) {
    final i = bodyIdx[n];
    final l = lines[i];
    final left = l.body.first.left;
    if (capStart.contains(n)) {
      flush();
    } else if (n > 0) {
      final p = lines[bodyIdx[n - 1]];
      final pLeft = p.body.first.left;
      final pWidth = p.body.last.right - pLeft;
      final gap = (mid[bodyIdx[n - 1]] - mid[i]);
      final nextLeft = n + 1 < bodyIdx.length ? lines[bodyIdx[n + 1]].body.first.left : null;
      final indent = (left - pLeft > 1.2 * cw && (nextLeft == null || left - nextLeft > 1.2 * cw)) ||
          (left - margin > 1.2 * cw && left - margin < 6 * cw && (pLeft - margin).abs() < 6 * cw && sentenceEnd.hasMatch(p.bodyText));
      // A short last line: shorter than the lines around it (beside a picture all lines are narrow).
      double w(int m) => m < 0 || m >= bodyIdx.length ? 0 : lines[bodyIdx[m]].body.last.right - lines[bodyIdx[m]].body.first.left;
      final around = [w(n - 2), w(n), w(n + 1)].reduce((a, b) => a > b ? a : b);
      final shortEnd = sentenceEnd.hasMatch(p.bodyText) && pWidth < (around > 0 && around < typical ? around : typical) * 0.75;
      final heading = l.large != p.large || l.quote != p.quote;
      // A line far above or below (a new column, text under a picture) also ends the paragraph
      // unless the sentence clearly goes on.
      final jump = gap > pitch * 1.6 || gap < -pitch * 0.5;
      final continues = !sentenceEnd.hasMatch(p.bodyText) && RegExp(r'^[a-z]').hasMatch(l.bodyText);
      if (indent || shortEnd || heading || (jump && !continues)) flush();
    }
    buf.add(l.bodyText);
    bufLines.add(l);
  }
  flush();

  final out = <String>[];
  for (final i in order.take(1)) {
    if (edge.contains(i)) {
      out.add('$edgeMark${lines[i].allSmall ? 's' : 'n'}${lines[i].allText}');
      note(lines[i].allText, [lines[i]], lines[i].allSmall, small: lines[i].allSmall);
    }
  }
  out.addAll(paras);
  // Small type that is not a header: captions and notes, one block per run of lines.
  final caps = <String>[];
  var capBuf = <String>[];
  var capLines = <_Line>[];
  var lastCap = -1;
  void capFlush() {
    if (capBuf.isEmpty) return;
    caps.add(capBuf.join('\n'));
    note(caps.last, capLines, true, small: true);
    capBuf = [];
    capLines = [];
  }

  for (final i in order) {
    if (edge.contains(i) || lines[i].small.isEmpty) continue;
    final s = lines[i].small.map((p) => p.text).join(' ');
    if (lastCap >= 0 && (mid[lastCap] - mid[i]) > pitch * 1.6) capFlush();
    capBuf.add(s);
    capLines.add(lines[i]);
    lastCap = i;
  }
  capFlush();
  out.addAll(caps.map((c) => '$captionMark$c'));
  for (final i in order.reversed.take(3).toList().reversed) {
    if (edge.contains(i) && i != order.first) {
      out.add('$edgeMark${lines[i].allSmall ? 's' : 'n'}${lines[i].allText}');
      note(lines[i].allText, [lines[i]], lines[i].allSmall, small: lines[i].allSmall);
    }
  }
  return '$layoutMark${out.join('\n\n')}';
}
