/// Pictures of a PDF page, found from where the ink is.
///
/// A PDF does not say where its pictures are in a way PDFium shows us, but a
/// picture is easy to see: a large area of ink with no letters in it. The page
/// is drawn small, the letters of the text layer are blanked out, and what is
/// left in big connected patches is a picture. Each one is drawn again at a
/// good size and kept as a PNG file, so the reader can show it where the book
/// has it.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as im;
import 'package:pdfrx/pdfrx.dart';

import 'word_gaps.dart';

/// A picture on a page, in PDF coordinates (top > bottom).
class PagePicture {
  final double left, top, right, bottom;

  /// File name in `ImportedBook.images`.
  final String name;

  /// Size of the PNG in pixels.
  final int width, height;
  PagePicture(this.left, this.top, this.right, this.bottom, this.name, this.width, this.height);
}

/// A large first letter (a drop cap) drawn as a picture, so that the text
/// layer does not have it: where it is (PDF coordinates, top > bottom) and
/// the shape of its ink, to tell which letter it is ([dropCapLetter]).
class InkLetter {
  final double left, top, right, bottom;

  /// Width / height of the ink; how much of the width the ink covers in the
  /// top and in the bottom rows; whether the middle row has ink at both sides
  /// with a hole between (O, H, A) or not (T, S, E).
  final double aspect, topSpan, bottomSpan;
  final bool hole;
  InkLetter(this.left, this.top, this.right, this.bottom, this.aspect, this.topSpan, this.bottomSpan, this.hole);
}

/// Finds the pictures of [page] (number [index], from 0) and adds their PNG
/// files to [files]. [boxes] are the page's letter boxes, [text] the text
/// they belong to. Drop caps drawn as pictures go to [letters].
Future<List<PagePicture>> findPictures(
  PdfPage page,
  int index,
  String text,
  List<GlyphBox> boxes,
  Map<String, List<int>> files, {
  List<InkLetter>? letters,
}) async {
  final pw = page.width, ph = page.height;
  if (pw <= 0 || ph <= 0) return const [];
  // 1. Draw the page small: one cell is a 4x4 pixel square.
  const target = 480.0;
  final scale = target / pw;
  final img = await page.render(fullWidth: pw * scale, fullHeight: ph * scale, backgroundColor: 0xffffffff);
  if (img == null) return const [];
  final w = img.width, h = img.height;
  const cell = 4;
  final cw = (w / cell).ceil(), chh = (h / cell).ceil();
  final ink = List<int>.filled(cw * chh, 0);
  try {
    final px = img.pixels;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final o = (y * w + x) * 4;
        final lum = (px[o] * 29 + px[o + 1] * 150 + px[o + 2] * 77) >> 8;
        if (lum < 170) ink[(y ~/ cell) * cw + x ~/ cell]++;
      }
    }
  } finally {
    img.dispose();
  }
  // 2. Blank out the letters (a little around them too).
  final letterH = <double>[];
  for (var i = 0; i < boxes.length && i < text.length; i++) {
    final b = boxes[i];
    if (b.right > b.left && b.top > b.bottom && text[i].trim().isNotEmpty) letterH.add(b.top - b.bottom);
  }
  letterH.sort();
  final pad = letterH.isEmpty ? 2.0 : letterH[letterH.length ~/ 2] * 0.35;
  for (var i = 0; i < boxes.length && i < text.length; i++) {
    final b = boxes[i];
    if (!(b.right > b.left && b.top > b.bottom) || text[i].trim().isEmpty) continue;
    final x0 = ((b.left - pad) * scale / cell).floor().clamp(0, cw - 1);
    final x1 = ((b.right + pad) * scale / cell).ceil().clamp(0, cw - 1);
    final y0 = ((ph - b.top - pad) * scale / cell).floor().clamp(0, chh - 1);
    final y1 = ((ph - b.bottom + pad) * scale / cell).ceil().clamp(0, chh - 1);
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        ink[y * cw + x] = 0;
      }
    }
  }
  // A cell with a few dark pixels is ink; specks of a scan are not.
  final on = List<bool>.generate(ink.length, (i) => ink[i] >= 2);
  // 3. Patches of ink: cells closer than [reach] cells belong together.
  const reach = 3;
  final label = List<int>.filled(on.length, -1);
  final rects = <List<int>>[]; // x0, y0, x1, y1, cells
  for (var s = 0; s < on.length; s++) {
    if (!on[s] || label[s] >= 0) continue;
    final r = [s % cw, s ~/ cw, s % cw, s ~/ cw, 0];
    final stack = [s];
    label[s] = rects.length;
    while (stack.isNotEmpty) {
      final c = stack.removeLast();
      final cx = c % cw, cy = c ~/ cw;
      r[4]++;
      if (cx < r[0]) r[0] = cx;
      if (cx > r[2]) r[2] = cx;
      if (cy < r[1]) r[1] = cy;
      if (cy > r[3]) r[3] = cy;
      for (var dy = -reach; dy <= reach; dy++) {
        final ny = cy + dy;
        if (ny < 0 || ny >= chh) continue;
        for (var dx = -reach; dx <= reach; dx++) {
          final nx = cx + dx;
          if (nx < 0 || nx >= cw) continue;
          final n = ny * cw + nx;
          if (on[n] && label[n] < 0) {
            label[n] = rects.length;
            stack.add(n);
          }
        }
      }
    }
    rects.add(r);
  }
  // 4. Big patches with enough ink are pictures (not a rule under a header,
  // an ornament or a dirty margin).
  final pics = <PagePicture>[];
  var k = 0;
  final lineH = letterH.isEmpty ? 0.0 : letterH[letterH.length ~/ 2];
  for (final r in rects) {
    final bw = (r[2] - r[0] + 1), bh = (r[3] - r[1] + 1);
    if (letters != null && lineH > 0) {
      // A patch two to six lines tall and about as wide as a letter, with
      // text beside it: a drop cap.
      final hPt = bh * cell / scale, wPt = bw * cell / scale;
      if (hPt > lineH * 1.8 && hPt < lineH * 10 && wPt < hPt * 1.6 && r[4] >= bw * bh * 0.15) {
        final l = r[0] * cell / scale, rt = (r[2] + 1) * cell / scale;
        final t = ph - r[1] * cell / scale, b = ph - (r[3] + 1) * cell / scale;
        final beside = boxes.any((g) => g.left >= rt && g.left - rt < lineH * 3 && g.top <= t + lineH && g.top >= b);
        if (beside) {
          final shape = await _letterShape(page, l, t, rt, b);
          if (shape != null) letters.add(shape);
        }
        continue;
      }
    }
    if (bw < cw * 0.18 || bh < chh * 0.08) continue;
    if (r[4] < bw * bh * 0.12) continue;
    // Back to PDF points, with a small margin.
    final m = 2.0;
    final left = math.max(0.0, r[0] * cell / scale - m);
    final right = math.min(pw, (r[2] + 1) * cell / scale + m);
    final top = math.min(ph, ph - r[1] * cell / scale + m);
    final bottom = math.max(0.0, ph - (r[3] + 1) * cell / scale - m);
    final png = await _renderPart(page, left, top, right, bottom);
    if (png == null) continue;
    final name = 'p${index + 1}_${++k}.jpg';
    files[name] = png.$1;
    pics.add(PagePicture(left, top, right, bottom, name, png.$2, png.$3));
  }
  return pics;
}

/// The ink of a drop cap, drawn large, measured.
Future<InkLetter?> _letterShape(PdfPage page, double left, double top, double right, double bottom) async {
  final m = 2.0;
  left = math.max(0, left - m);
  right = math.min(page.width, right + m);
  top = math.min(page.height, top + m);
  bottom = math.max(0, bottom - m);
  final scale = 160 / (top - bottom);
  final img = await page.render(
    x: (left * scale).round(),
    y: ((page.height - top) * scale).round(),
    width: math.max(1, ((right - left) * scale).round()),
    height: math.max(1, ((top - bottom) * scale).round()),
    fullWidth: page.width * scale,
    fullHeight: page.height * scale,
    backgroundColor: 0xffffffff,
  );
  if (img == null) return null;
  try {
    final w = img.width, h = img.height, px = img.pixels;
    bool dark(int x, int y) {
      final o = (y * w + x) * 4;
      return (px[o] * 29 + px[o + 1] * 150 + px[o + 2] * 77) >> 8 < 128;
    }

    var x0 = w, x1 = -1, y0 = h, y1 = -1;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (!dark(x, y)) continue;
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
    }
    if (x1 < x0 || y1 - y0 < 10) return null;
    final iw = x1 - x0 + 1, ih = y1 - y0 + 1;
    // Widest stretch from the first to the last dark pixel in a band of rows.
    double span(double from, double to) {
      var best = 0;
      for (var y = y0 + (ih * from).floor(); y <= y0 + (ih * to).floor() && y <= y1; y++) {
        var a = -1, b = -1;
        for (var x = x0; x <= x1; x++) {
          if (dark(x, y)) {
            if (a < 0) a = x;
            b = x;
          }
        }
        if (a >= 0 && b - a + 1 > best) best = b - a + 1;
      }
      return best / iw;
    }

    var hole = false;
    for (final f in [0.4, 0.5, 0.6]) {
      final y = y0 + (ih * f).floor();
      bool any(int a, int b) {
        for (var x = a; x < b; x++) {
          if (dark(x, y)) return true;
        }
        return false;
      }

      final q = iw ~/ 4;
      if (any(x0, x0 + q) && any(x1 - q + 1, x1 + 1) && !any(x0 + iw ~/ 2 - 1, x0 + iw ~/ 2 + 1)) hole = true;
    }
    return InkLetter(left, top, right, bottom, iw / ih, span(0, 0.12), span(0.88, 1), hole);
  } finally {
    img.dispose();
  }
}

/// The capital a drop cap is, for a line of text that starts with [rest]
/// ("n the garden"): of the letters that make a word with what follows
/// ("In", "An", "On"), the one whose shape fits the ink best. Null when no
/// letter makes a word.
String? dropCapLetter(String rest, InkLetter shape, bool Function(String word) isWord) {
  final m = RegExp(r'^[a-z]+').firstMatch(rest);
  if (m == null) return null;
  final w = m.group(0)!;
  final cands = [
    for (final c in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split(''))
      if (isWord('${c.toLowerCase()}$w')) c,
  ];
  // "A week later", "I went": a letter that is a word of its own, before a
  // word that needs no letter. It is the likelier reading, so it costs less.
  final alone = w.length >= 3 && isWord(w);
  if (alone) cands.addAll(['A ', 'I ']);
  if (cands.isEmpty) return null;
  if (cands.length == 1) return cands.first;
  double cost(String c) {
    final p = _shapes[c.trim()]!;
    return (c.length > 1 ? -0.3 : 0) +
        (p.$1 - shape.aspect).abs() * 2 +
        (p.$2 - shape.topSpan).abs() +
        (p.$3 - shape.bottomSpan).abs() +
        ((p.$4 == 1) != shape.hole ? 0.4 : 0);
  }

  cands.sort((a, b) => cost(a).compareTo(cost(b)));
  return cands.first;
}

/// Rough shape of each capital in a book face: width / height, ink across
/// the top and the bottom rows, a hole in the middle (1) or not (0).
const _shapes = <String, (double, double, double, int)>{
  'A': (0.9, 0.2, 1.0, 1),
  'B': (0.75, 0.9, 0.9, 1),
  'C': (0.85, 0.6, 0.6, 0),
  'D': (0.85, 0.9, 0.9, 1),
  'E': (0.75, 0.95, 0.95, 0),
  'F': (0.7, 0.95, 0.3, 0),
  'G': (0.9, 0.6, 0.6, 1),
  'H': (0.95, 1.0, 1.0, 1),
  'I': (0.35, 0.9, 0.9, 0),
  'J': (0.5, 0.8, 0.4, 0),
  'K': (0.9, 1.0, 1.0, 1),
  'L': (0.75, 0.4, 1.0, 0),
  'M': (1.1, 1.0, 1.0, 1),
  'N': (0.95, 1.0, 1.0, 1),
  'O': (0.95, 0.5, 0.5, 1),
  'P': (0.75, 0.9, 0.3, 1),
  'Q': (0.95, 0.5, 0.6, 1),
  'R': (0.85, 0.9, 1.0, 1),
  'S': (0.65, 0.7, 0.7, 0),
  'T': (0.9, 1.0, 0.35, 0),
  'U': (0.95, 1.0, 0.6, 1),
  'V': (0.95, 1.0, 0.15, 1),
  'W': (1.3, 1.0, 0.4, 1),
  'X': (0.95, 1.0, 1.0, 1),
  'Y': (0.95, 1.0, 0.35, 0),
  'Z': (0.8, 1.0, 1.0, 0),
};

/// The part of the page between the given PDF coordinates as a JPEG, at most
/// about 900 pixels wide.
Future<(Uint8List, int, int)?> _renderPart(PdfPage page, double left, double top, double right, double bottom) async {
  final wPt = right - left, hPt = top - bottom;
  final scale = math.min(2.5, 900 / wPt);
  final img = await page.render(
    x: (left * scale).round(),
    y: ((page.height - top) * scale).round(),
    width: (wPt * scale).round(),
    height: (hPt * scale).round(),
    fullWidth: page.width * scale,
    fullHeight: page.height * scale,
    backgroundColor: 0xffffffff,
  );
  if (img == null) return null;
  try {
    return (encodeJpeg(img.pixels, img.width, img.height), img.width, img.height);
  } finally {
    img.dispose();
  }
}

/// JPEG from BGRA pixels: grey when every pixel is grey (most book
/// drawings), colour otherwise.
Uint8List encodeJpeg(Uint8List bgra, int w, int h, {int quality = 78}) {
  var grey = true;
  for (var o = 0; o < bgra.length && grey; o += 4) {
    if ((bgra[o] - bgra[o + 1]).abs() > 6 || (bgra[o + 1] - bgra[o + 2]).abs() > 6) grey = false;
  }
  final image = im.Image.fromBytes(width: w, height: h, bytes: bgra.buffer, bytesOffset: bgra.offsetInBytes, numChannels: 4, order: im.ChannelOrder.bgra);
  return im.encodeJpg(grey ? im.grayscale(image) : image, quality: quality, chroma: grey ? im.JpegChroma.yuv420 : im.JpegChroma.yuv420);
}
