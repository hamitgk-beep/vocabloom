import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

import '../data/user_db.dart';
import 'importers.dart';
import '../l10n.dart';
import 'ocr.dart';
import 'pdf_layout.dart';
import 'pdf_pictures.dart';
import 'text_repair.dart';
import 'word_gaps.dart';

String _clean(String s) => s.replaceAll(RegExp(r'[\s ]+'), ' ').trim();

Future<Uint8List> _toPng(ui.Image img) async {
  final bd = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return bd!.buffer.asUint8List();
}

Future<Uint8List> _renderPage(PdfPage page) async {
  // ~2200 px wide is enough for OCR and keeps memory reasonable on phones.
  final scale = (2200 / page.width).clamp(1.5, 4.0);
  final im = await page.render(
      fullWidth: page.width * scale, fullHeight: page.height * scale, backgroundColor: 0xffffffff);
  if (im == null) throw ImportException(L('Sayfa görüntüsü oluşturulamadı.', 'Could not render the page image.'));
  try {
    return await _toPng(await im.createImage());
  } finally {
    im.dispose();
  }
}

/// PDF: text layer when present, OCR for pages that only contain pictures.
Future<ImportedBook> importPdf(String path, String fallbackTitle,
    {OcrEngine? ocr, ImportProgress? onProgress, bool Function(String word)? isWord}) async {
  await pdfrxFlutterInitialize();
  final doc = await PdfDocument.openFile(path);
  try {
    final n = doc.pages.length;
    final pages = <String>[];
    final ocrPages = <int>{};
    final layouts = <PageLayout>[];
    final images = <String, List<int>>{};
    for (var i = 0; i < n; i++) {
      if (i % 5 == 0) onProgress?.call(L('Sayfalar okunuyor: ${i + 1}/$n', 'Reading pages: ${i + 1}/$n'));
      final page = doc.pages[i];
      final raw = await page.loadText();
      final boxes = raw == null
          ? const <GlyphBox>[]
          : [for (final r in raw.charRects) (left: r.left, top: r.top, right: r.right, bottom: r.bottom)];
      // PDFium marks a word broken at a line end with U+0002, which the layout
      // uses for captions: make it a soft hyphen (same length, so the letter boxes still match).
      final full = raw == null ? '' : raw.fullText.replaceAll(pdfiumBreak, softHyphen);
      final blocks = <LayoutBlock>[];
      final t = raw == null ? '' : layoutPdfPage(full, boxes, isWord: isWord, blocks: blocks) ?? addGapSpaces(full, boxes, isWord);
      pages.add(t);
      final scanned = (raw?.fullText ?? '').trim().length < 25;
      if (scanned) ocrPages.add(i);
      // A scanned page without text is all picture to us; its text is read
      // by OCR, so it gets no pictures of its own.
      var pics = const <PagePicture>[];
      if (!scanned || ocr == null) {
        try {
          pics = await findPictures(page, i, full, boxes, images);
        } catch (_) {}
      }
      layouts.add(PageLayout(page.width, page.height, blocks, pics));
    }
    if (ocrPages.isNotEmpty) {
      if (ocr == null) {
        if (ocrPages.length == n) {
          throw ImportException(L(
              'Bu PDF taranmış (resim) bir belge; içinde seçilebilir metin yok. '
                  'Resimden metin okumak için bu cihazda OCR bulunamadı. Ayarlar\'dan resim okuyabilen bir yapay zekâ '
                  'servisi bağlayıp internete bağlıyken tekrar deneyin.',
              'This PDF is a scanned (image) document with no selectable text. '
                  'No OCR was found on this device to read text from images. Connect an AI service that can read images '
                  'in Settings and try again while online.'));
        }
      } else {
        var k = 0;
        for (final i in ocrPages) {
          k++;
          onProgress?.call(L('Resimden metin okunuyor (${ocr.name}): sayfa $k/${ocrPages.length}', 'Reading text from image (${ocr.name}): page $k/${ocrPages.length}'));
          final png = await _renderPage(doc.pages[i]);
          pages[i] = '\u0001${await ocr.recognize(png)}';
        }
      }
    }
    onProgress?.call(L('Paragraflar düzenleniyor…', 'Arranging paragraphs…'));
    return buildBookFromPages(pages, fallbackTitle, 'pdf', isWord: isWord, layouts: layouts, images: images);
  } finally {
    await doc.dispose();
  }
}

/// A photo or scan of a page.
Future<ImportedBook> importImage(String path, String fallbackTitle,
    {OcrEngine? ocr, ImportProgress? onProgress, bool Function(String word)? isWord}) async {
  if (ocr == null) {
    throw ImportException(L(
        'Resimden metin okumak için bu cihazda OCR bulunamadı. Ayarlar\'dan resim okuyabilen bir yapay zekâ servisi bağlayın.',
        'No OCR was found on this device to read text from images. Connect an AI service that can read images in Settings.'));
  }
  final bytes = await File(path).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final png = await _toPng(frame.image);
  onProgress?.call(L('Resimden metin okunuyor (${ocr.name})…', 'Reading text from image (${ocr.name})…'));
  final text = await ocr.recognize(png);
  return buildBookFromPages(['\u0001$text'], fallbackTitle, 'image', isWord: isWord);
}

final _tocLine = RegExp(r'^(.*?[A-Za-z][^.]*?)\s*(?:[.·…]\s*){3,}\s*\d{1,4}\s*$');
final _sentenceEnd = RegExp(r'''[.!?:;"”’)]$''');

bool _noise(String l) {
  final t = l.trim();
  if (t.isEmpty) return true;
  if (RegExp(r'^\d{1,4}$').hasMatch(t)) return true; // page number
  final letters = RegExp(r'[A-Za-z]').allMatches(t).length;
  if (letters < 2) return true;
  // Puzzles and formulas; a sentence with a formula in it stays.
  final words = RegExp(r'[A-Za-zÀ-ÿ]{3,}').allMatches(t).length;
  final solid = t.replaceAll(RegExp(r'\s'), '').length;
  return (letters / t.length < 0.55 && words < 3) || letters / solid < 0.4;
}

/// Turns page texts into chapters/paragraphs. Pages starting with \u0001
/// come from OCR, where blank lines separate paragraphs.
/// Typical OCR slips: a vertical bar read instead of the capital I.
String fixOcr(String s) => fixMojibake(s)
    .replaceAllMapped(RegExp(r'''(^|[\s“"(‘'])\|(?=['’]|\s|$)''', multiLine: true), (m) => '${m.group(1)}I')
    .replaceAll(RegExp(r'[ \t]+'), ' ');

/// Repairs UTF-8 text that was decoded as Windows-1252/Latin-1 ("GÃ¶ttingen" -> "Göttingen").
String fixMojibake(String s) {
  if (!s.contains(RegExp('[ÃÂÅÄ][\u0080-\u00BF]'))) return s;
  return s.replaceAllMapped(RegExp('[\u00C2-\u00F4][\u0080-\u00BF]+'), (m) {
    try {
      return utf8.decode(latin1.encode(m.group(0)!));
    } catch (_) {
      return m.group(0)!;
    }
  });
}


final _tocNoLeader = RegExp(r'^(?:(?:chapter|part|bölüm)\s+)?(\d{1,3}|[ivxlc]{1,6})[.)]?\s+(.*?[A-Za-z].*?)\s+(\d{1,4})$', caseSensitive: false);
final _chapterWord = RegExp(r'^(chapter|part|book|bölüm|kısım|kapitel)\s+(\d{1,3}|[ivxlc]{1,7}|one|two|three|four|five|six|seven|eight|nine|ten)\b', caseSensitive: false);
final _contentsLine = RegExp(r'^(contents|table of contents|içindekiler)$', caseSensitive: false);

/// Letters only, lower case: compares lines whatever their spacing and numbers.
String _key(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');

/// Similarity of two strings from 0 to 1 (Levenshtein).
double _similar(String a, String b) {
  if (a == b) return 1;
  if (a.isEmpty || b.isEmpty) return 0;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final c = a[i - 1] == b[j - 1] ? 0 : 1;
      cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + c].reduce((x, y) => x < y ? x : y);
    }
    prev = cur;
  }
  return 1 - prev[b.length] / (a.length > b.length ? a.length : b.length);
}

/// Pages a scanned book repeats by mistake: almost the same words as one of the
/// three pages before.
Set<int> _repeatedPages(List<String> pages) {
  List<String> words(String s) => RegExp(r'[a-z]+').allMatches(s.toLowerCase()).map((m) => m.group(0)!).toList();
  Set<String> pairs(List<String> w) => {for (var i = 0; i + 1 < w.length; i++) '${w[i]} ${w[i + 1]}'};
  final sets = [for (final p in pages) pairs(words(p))];
  final out = <int>{};
  for (var i = 0; i < pages.length; i++) {
    if (sets[i].length < 40) continue;
    for (var j = i - 1; j >= 0 && j >= i - 3; j--) {
      if (out.contains(j) || sets[j].length < 40) continue;
      final common = sets[i].intersection(sets[j]).length;
      if (common / (sets[i].length + sets[j].length - common) > 0.85) {
        out.add(i);
        break;
      }
    }
  }
  return out;
}

/// What the layout found on one PDF page: its size, where its paragraphs and
/// captions are, and its pictures.
class PageLayout {
  final double width, height;
  final List<LayoutBlock> blocks;
  final List<PagePicture> pictures;
  PageLayout(this.width, this.height, this.blocks, this.pictures);
}

double _median(List<double> v) {
  if (v.isEmpty) return 0;
  final s = [...v]..sort();
  return s[s.length ~/ 2];
}

/// How the book sets the paragraph [text] of page [pg]: its size compared
/// with the body text and whether it is centred or justified ([Para.meta]).
/// `_t`/`_b` (top and bottom on the page) are only used while importing.
class _Styler {
  final List<PageLayout> layouts;
  late final double bodyX; // x-height of the body text
  late final double colW; // width of a full line of text
  final _used = <int, Set<int>>{};
  _Styler(this.layouts) {
    final xs = <double>[], ws = <double>[];
    for (final l in layouts) {
      for (final b in l.blocks) {
        if (b.caption || b.lines.length < 3 || b.xHeight == null) continue;
        for (final ln in b.lines) {
          xs.add(b.xHeight!);
          ws.add(ln.$2 - ln.$1);
        }
      }
    }
    bodyX = _median(xs);
    ws.sort();
    colW = ws.isEmpty ? 0 : ws[(ws.length * 0.8).floor().clamp(0, ws.length - 1)];
  }

  /// Centre of the text column of page [pg]: from its full lines, or the page's middle.
  double _centre(int pg) {
    final l = layouts[pg];
    final cs = [
      for (final b in l.blocks)
        if (!b.caption)
          for (final ln in b.lines)
            if (colW > 0 && ln.$2 - ln.$1 >= colW * 0.92) (ln.$1 + ln.$2) / 2
    ];
    return cs.length >= 3 ? _median(cs) : l.width / 2;
  }

  final _centres = <int, double>{};

  /// The layout block [text] came from (matched by its letters), if any.
  LayoutBlock? find(int pg, String text, {required bool caption}) {
    if (pg >= layouts.length) return null;
    final k = layoutKey(text);
    if (k.length < 2) return null;
    final used = _used.putIfAbsent(pg, () => {});
    final bs = layouts[pg].blocks;
    var best = -1, bestLen = 0;
    for (var i = 0; i < bs.length; i++) {
      if (used.contains(i) || bs[i].caption != caption) continue;
      final o = bs[i].key;
      var n = 0;
      while (n < k.length && n < o.length && k[n] == o[n]) {
        n++;
      }
      // Also a block whose start was cut off (a drop cap, a joined line).
      if (n < 6 && o.length >= 12 && k.contains(o.substring(0, 12))) n = 12;
      if (n < 6 && k.length >= 12 && o.contains(k.substring(0, 12))) n = 12;
      if (n > bestLen) {
        bestLen = n;
        best = i;
      }
    }
    if (best < 0) return null;
    final short = math.min(k.length, bs[best].key.length);
    if (bestLen < 8 && bestLen < short * 0.6) return null;
    used.add(best);
    return bs[best];
  }

  Map<String, Object?> meta(int pg, String text, {bool caption = false}) {
    final m = <String, Object?>{'pg': pg};
    final b = find(pg, text, caption: caption);
    if (b == null) return m;
    m['_t'] = b.top;
    m['_b'] = b.bottom;
    if (b.xHeight != null && bodyX > 0) {
      final sz = (b.xHeight! / bodyX * 20).round() / 20;
      if ((sz - 1).abs() >= 0.08) m['sz'] = sz.clamp(0.6, 3.0);
    }
    if (b.lines.isEmpty || colW <= 0) return m;
    final pw = layouts[pg].width;
    final centre = _centres.putIfAbsent(pg, () => _centre(pg));
    final ls = b.lines;
    final inner = ls.length >= 2 ? ls.sublist(0, ls.length - 1) : ls;
    final full = inner.every((l) => l.$2 - l.$1 >= colW * 0.9);
    final centred = ls.every((l) => ((l.$1 + l.$2) / 2 - centre).abs() < pw * 0.035) && ls.any((l) => l.$2 - l.$1 < colW * 0.85);
    m['al'] = centred ? 'c' : (ls.length >= 2 && full ? 'j' : 'l');
    m['_c'] = (ls.map((l) => l.$1).reduce(math.min) + ls.map((l) => l.$2).reduce(math.max)) / 2;
    m['_w'] = ls.map((l) => l.$2 - l.$1).reduce(math.max);
    m['_n'] = ls.length;
    return m;
  }
}

ImportedBook buildBookFromPages(List<String> pages, String title, String format,
    {bool Function(String word)? isWord, List<PageLayout>? layouts, Map<String, List<int>>? images}) {
  final styler = layouts != null && layouts.length == pages.length ? _Styler(layouts) : null;
  final dup = _repeatedPages(pages);
  pages = [for (var i = 0; i < pages.length; i++) dup.contains(i) ? '' : pages[i]];

  // Lines repeated on many pages are running headers/footers.
  final freq = <String, int>{};
  final edgeFreq = <String, int>{};
  for (final pg in pages) {
    if (pg.startsWith(layoutMark)) {
      for (final b in pg.substring(1).split('\n\n').where((b) => b.startsWith(edgeMark)).map((b) => _key(b.substring(2))).toSet()) {
        if (b.isNotEmpty) edgeFreq[b] = (edgeFreq[b] ?? 0) + 1;
      }
      continue;
    }
    for (final l in pg.split('\n').map((l) => l.trim()).toSet()) {
      final k = l.replaceAll(RegExp(r'\d+'), '#');
      if (k.isNotEmpty) freq[k] = (freq[k] ?? 0) + 1;
    }
  }
  final repeated = pages.length >= 6 ? freq.entries.where((e) => e.value > pages.length * 0.4).map((e) => e.key).toSet() : <String>{};
  final repeatedEdge = edgeFreq.entries.where((e) => e.value >= 3 || (pages.length < 6 && e.value >= 2)).map((e) => e.key).toSet();

  // 1. blocks per page
  final pageBlocks = <List<String>>[];
  final pageMeta = <List<Map<String, Object?>>>[];
  final pageToc = <List<bool>>[];
  final pageCaptions = <List<String>>[];
  final pageCapMeta = <List<Map<String, Object?>>>[];
  final toc = <String>[];
  final tocPage = <int, String>{}; // printed page number -> chapter title
  final printed = <int?>[]; // printed page number of each page, from its header or footer
  for (final raw in pages) {
    int? pageNo;
    final fromOcr = raw.startsWith('\u0001');
    final fromLayout = raw.startsWith(layoutMark);
    final captions = <String>[];
    var text = (fromOcr ? fixOcr(raw.substring(1)) : fromLayout ? raw.substring(1) : raw).replaceAll('\r', '\n');
    if (fromLayout) {
      // Headers, footers and captions found from the page layout.
      final kept = <String>[];
      for (final b in text.split('\n\n')) {
        if (b.startsWith(captionMark)) {
          captions.add(b.substring(1));
        } else if (b.startsWith(edgeMark)) {
          final t = b.substring(2);
          final num = pageNumberLine.firstMatch(t);
          if (num != null) pageNo = int.parse(num.group(1)!);
          if (num != null || _noise(t) || repeatedEdge.contains(_key(t))) continue;
          // A small running header with a chapter's name.
          if (b[1] == 's' && toc.any((e) => _key(e) == _key(t))) continue;
          if (b[1] == 's') {
            captions.add(t);
          } else {
            kept.add(t);
          }
        } else {
          kept.add(b);
        }
      }
      text = kept.join('\n\n');
    }
    text = joinDropCaps(text.split('\n'), isWord).join('\n');
    final hasContents = text.split('\n').any((l) => _contentsLine.hasMatch(l.trim().replaceAll(RegExp(r'(?<=\w) (?=\w)'), '')));
    final lines = text
        .split('\n')
        .map((l) => l.trimRight())
        .where((l) => l.trim().isEmpty || (!_noise(l) && !repeated.contains(l.trim().replaceAll(RegExp(r'\d+'), '#'))))
        .toList();
    final blocks = <String>[];
    final tocAt = <int>{}; // blocks that are lines of the table of contents
    void addLine(StringBuffer buf, String l) {
      final s = buf.toString();
      final broken = RegExp('([A-Za-z]+)[-$softHyphen]\$').firstMatch(s);
      final next = RegExp(r'^[a-z]+').firstMatch(l);
      if (s.endsWith(softHyphen) || (broken != null && next != null)) {
        // A word broken over two lines: joined ("dan-gerous") or kept as a compound ("good-for-nothing").
        final a = broken?.group(1) ?? '';
        buf
          ..clear()
          ..write(s.substring(0, s.length - 1 - a.length))
          ..write(next == null ? '$a$l' : '${joinHalves(a, next.group(0)!, isWord)}${l.substring(next.end)}');
      } else {
        if (s.isNotEmpty) buf.write(' ');
        buf.write(l);
      }
    }

    bool tocEntry(String l) {
      final m = _tocLine.firstMatch(l);
      if (m != null) {
        toc.add(_clean(m.group(1)!));
        final pn = int.tryParse(RegExp(r'(\d{1,4})\s*$').firstMatch(l)!.group(1)!);
        if (pn != null) tocPage.putIfAbsent(pn, () => toc.last);
        return true;
      }
      final n = hasContents ? _tocNoLeader.firstMatch(l) : null;
      if (n != null) {
        toc.add(_clean(n.group(2)!));
        tocPage.putIfAbsent(int.parse(n.group(3)!), () => toc.last);
        return true;
      }
      // Other lines of the contents page with a page number ("GLOSSARY 42")
      // stay lines too, but are no chapters.
      return hasContents && RegExp(r'^\D.{1,70}?\s\d{1,3}$').hasMatch(l) && l.split(' ').length <= 10;
    }

    if (fromOcr || fromLayout || text.contains(RegExp(r'\n\s*\n'))) {
      final buf = StringBuffer();
      for (final l in [...lines, '']) {
        if (l.trim().isEmpty) {
          if (buf.isNotEmpty) blocks.add(_clean(buf.toString()));
          buf.clear();
        } else {
          if (tocEntry(l.trim())) {
            // A line of the table of contents stays a line of its own.
            if (buf.isNotEmpty) blocks.add(_clean(buf.toString()));
            buf.clear();
            tocAt.add(blocks.length);
            blocks.add(_clean(l));
            continue;
          }
          addLine(buf, l.trim());
        }
      }
    } else {
      final ls = lines.where((l) => l.trim().isNotEmpty).toList();
      if (ls.isNotEmpty) {
        final lens = ls.map((l) => l.trim().length).toList()..sort();
        final typical = lens[(lens.length * 0.8).floor().clamp(0, lens.length - 1)];
        final buf = StringBuffer();
        for (final l0 in ls) {
          final l = l0.trim();
          if (tocEntry(l)) {
            if (buf.isNotEmpty) blocks.add(_clean(buf.toString()));
            buf.clear();
            tocAt.add(blocks.length);
            blocks.add(_clean(l));
            continue;
          }
          addLine(buf, l);
          if (_sentenceEnd.hasMatch(l) && l.length < typical * 0.75) {
            blocks.add(_clean(buf.toString()));
            buf.clear();
          }
        }
        if (buf.isNotEmpty) blocks.add(_clean(buf.toString()));
      }
    }
    // Drop OCR garbage from pictures: blocks made mostly of non-words.
    bool garbage(String b) {
      if (!fromOcr || isWord == null) return false;
      final ws = RegExp(r"[A-Za-z][A-Za-z'’]*").allMatches(b).map((m) => m.group(0)!).toList();
      if (ws.isEmpty) return true;
      final ok = ws.where((w) => isWord(w) || (w.length > 1 && w[0] == w[0].toUpperCase() && w.substring(1) == w.substring(1).toLowerCase())).length;
      return ok / ws.length < 0.6 || (ws.length <= 2 && ws.every((w) => w.length <= 2));
    }

    String fix(String b) => repairPdfText(b, isWord);
    final pg = pageBlocks.length;
    final kept = <String>[], keptMeta = <Map<String, Object?>>[], keptToc = <bool>[];
    for (var bi = 0; bi < blocks.length; bi++) {
      for (final b in splitAtBullets(blocks[bi])) {
        if (b.isEmpty || garbage(b)) continue;
        keptMeta.add(tocAt.contains(bi) ? {'pg': pg, 'al': 'l', 'toc': 1} : styler?.meta(pg, b) ?? {'pg': pg});
        kept.add(fix(joinSpacedCaps(b, isWord)));
        keptToc.add(tocAt.contains(bi));
      }
    }
    pageBlocks.add(kept);
    pageMeta.add(keptMeta);
    pageToc.add(keptToc);
    printed.add(pageNo);
    final caps = <String>[], capMeta = <Map<String, Object?>>[];
    for (final c in captions) {
      if (_noise(c)) continue;
      capMeta.add(styler?.meta(pg, c, caption: true) ?? {'pg': pg});
      caps.add(fix(joinSpacedCaps(_clean(c), isWord)));
    }
    pageCaptions.add(caps);
    pageCapMeta.add(capMeta);
  }

  // 2. join paragraphs that continue on the next page; captions and
  // pictures wait until the paragraph they interrupt is over.
  final flat = <_Flat>[];
  final waiting = <_Flat>[];
  for (var pg = 0; pg < pageBlocks.length; pg++) {
    // Pictures of the page, top first, each with the caption set next to it.
    final pics = [...?layouts?[pg].pictures]..sort((a, b) => b.top.compareTo(a.top));
    final capOf = <int, List<int>>{};
    final capFree = <int>[];
    final ph = layouts?[pg].height ?? 0;
    for (var c = 0; c < pageCaptions[pg].length; c++) {
      final t = pageCapMeta[pg][c]['_t'] as double?, bt = pageCapMeta[pg][c]['_b'] as double?;
      var best = -1;
      var bestGap = ph * 0.12;
      for (var q = 0; q < pics.length && t != null && bt != null; q++) {
        final gap = math.min((pics[q].bottom - t).abs(), (bt - pics[q].top).abs());
        final inside = t <= pics[q].top && bt >= pics[q].bottom;
        if (inside || gap < bestGap) {
          bestGap = inside ? -1 : gap;
          best = q;
        }
      }
      if (best < 0) {
        capFree.add(c);
      } else {
        (capOf[best] ??= []).add(c);
      }
    }
    final placed = <int>{};
    void picturesAbove(double? top) {
      for (var q = 0; q < pics.length; q++) {
        if (placed.contains(q) || (top != null && (pics[q].top + pics[q].bottom) / 2 < top)) continue;
        placed.add(q);
        final pic = pics[q];
        final lw = layouts![pg].width;
        waiting.add(_Flat(pg, 'i', pic.name, {
          'pg': pg,
          'ar': (pic.width / pic.height * 1000).round() / 1000,
          'wr': ((pic.right - pic.left) / lw * 100).round() / 100,
        }));
        for (final c in capOf[q] ?? const <int>[]) {
          waiting.add(_Flat(pg, 'c', pageCaptions[pg][c], {...pageCapMeta[pg][c], 'al': 'c'}));
        }
      }
    }

    for (var i = 0; i < pageBlocks[pg].length; i++) {
      final b = pageBlocks[pg][i];
      final meta = pageMeta[pg][i];
      // A short centred line right under a picture is its caption, even in the body's type.
      final top = meta['_t'] as double?;
      if (top != null && pics.isNotEmpty && meta['al'] == 'c' && (meta['_n'] as int? ?? 9) <= 2 && b.split(' ').length <= 25) {
        var q = -1;
        for (var k = 0; k < pics.length && q < 0; k++) {
          final p = pics[k];
          if (!placed.contains(k) && p.bottom >= top && p.bottom - top < ph * 0.06 &&
              ((meta['_c'] as double) - (p.left + p.right) / 2).abs() < layouts![pg].width * 0.05) {
            q = k;
          }
        }
        if (q >= 0) {
          (capOf[q] ??= []);
          pageCaptions[pg].add(b);
          pageCapMeta[pg].add(meta);
          capOf[q]!.add(pageCaptions[pg].length - 1);
          continue;
        }
      }
      picturesAbove(top);
      if (pageToc[pg][i]) {
        flat.addAll(waiting);
        waiting.clear();
        flat.add(_Flat(pg, 'p', b, meta, toc: true));
        continue;
      }
      final prevF = flat.isEmpty || flat.last.kind != 'p' || flat.last.toc ? null : flat.last;
      final prev = prevF?.text ?? '';
      final open = prev.isNotEmpty && !RegExp(r'''[.!?]["”’)]?$''').hasMatch(prev);
      // A sentence cut by a picture or a page turn goes on with a small letter,
      // or after a comma with anything ("'But he knows my name,' | Aladdin said.").
      final midSentence = open && prev.length > 25 && b.length > 40 && RegExp(r'''[,;]["”’']?$''').hasMatch(prev);
      if (open && (RegExp(r'^[a-z]').hasMatch(b) || midSentence)) {
        prevF!.text = '$prev $b';
      } else {
        flat.addAll(waiting);
        waiting.clear();
        flat.add(_Flat(pg, 'p', b, meta));
      }
    }
    picturesAbove(null);
    for (final c in capFree) {
      waiting.add(_Flat(pg, 'c', pageCaptions[pg][c], pageCapMeta[pg][c]));
    }
  }
  flat.addAll(waiting);

  // 3. headings and chapters
  final tocKeys = {for (final t in toc) _key(t): t};
  // The table of contents entry a heading stands for, also when its letters were misread ("Help from a rich ma11").
  String? tocTitle(String b) {
    final k = _key(b.replaceFirst(RegExp(r'^(?:(?:chapter|part|bölüm)\s+)?\d{1,3}[.)]?\s+', caseSensitive: false), ''));
    if (k.isEmpty || b.length > 80) return null;
    if (tocKeys.containsKey(k)) return tocKeys[k];
    for (final e in tocKeys.entries) {
      if (e.key.length >= 6 && _similar(k, e.key) >= 0.75) return e.value;
    }
    return null;
  }

  bool isHeading(String b) {
    final words = b.split(' ');
    if (tocTitle(b) != null) return true;
    if (words.length > 7 || _sentenceEnd.hasMatch(b)) return false;
    final caps = words.where((w) => w.isNotEmpty && w[0].toUpperCase() == w[0]).length;
    return caps >= (words.length * 0.6).ceil();
  }

  final chapters = <ImportedChapter>[];
  var cur = ImportedChapter('', []);
  var curStartPage = 0;
  final usedToc = <String>{};
  // A chapter starts on the page the table of contents gives for it.
  final startsAt = <int, String>{};
  if (tocPage.length >= 2) {
    for (var pg = 0; pg < printed.length; pg++) {
      final t = tocPage[printed[pg]];
      if (t != null && !startsAt.containsValue(t)) startsAt[pg] = t;
    }
  }
  final pageDone = <int>{};
  for (var fi = 0; fi < flat.length; fi++) {
    final f = flat[fi];
    final pg = f.page, kind = f.kind, meta = f.meta;
    var b = f.text;
    if (kind == 'c' || kind == 'i') {
      // A picture the book file does not have (it was not kept) is left out.
      if (kind == 'c' || (images?.containsKey(b) ?? false)) cur.add(kind, b, meta);
      continue;
    }
    if (f.toc) {
      cur.add('p', b, meta);
      continue;
    }
    var heading = isHeading(b);
    var fromToc = heading ? tocTitle(b) : null;
    final start = startsAt[pg];
    if (start != null && pageDone.add(pg) && !usedToc.contains(start)) {
      fromToc = start;
      // The heading printed there, maybe with misread letters ("A wallt to 11owl1crc").
      final short = b.split(' ').length <= 8 && !_sentenceEnd.hasMatch(b);
      if (short) {
        heading = true;
      } else {
        if (cur.paragraphs.isNotEmpty) chapters.add(cur);
        cur = ImportedChapter(start, []);
        curStartPage = pg;
        usedToc.add(start);
        // The heading is drawn as a picture on the page: show the contents' title
        // (and not also the picture of it, a wide strip at the top of the page).
        for (final c in [cur, if (chapters.isNotEmpty) chapters.last]) {
          final k = c.paragraphs.length - 1;
          final m = c.metaAt(k);
          if (k >= 0 && c.paragraphs[k].$1 == 'i' && m?['pg'] == pg && ((m?['ar'] as num?) ?? 0) > 2.5) {
            c.paragraphs.removeAt(k);
            if (k < c.meta.length) c.meta.removeAt(k);
            break;
          }
        }
        cur.add('h', start, {'pg': pg, 'sz': 1.5, 'al': 'c'});
        cur.add('p', b, meta);
        continue;
      }
    }
    // Without a table of contents, a heading followed by real paragraphs starts a chapter.
    final storyHeading = tocKeys.isEmpty &&
        heading &&
        fi + 3 < flat.length &&
        flat.sublist(fi + 1, fi + 4).every((x) => x.kind != 'p' || (!isHeading(x.text) && x.text.length > 60));
    // "Chapter 2", "CHAPTER XII. Alice's Evidence", "Bölüm 3" always start a chapter.
    final named = heading && _chapterWord.hasMatch(b) && b.length <= 70;
    final tocBreak = heading && ((fromToc != null && !usedToc.contains(fromToc)) || storyHeading || named);
    if (fromToc != null && tocBreak) {
      usedToc.add(fromToc);
      b = fromToc;
    }
    // Long books without headings are cut every 25 pages, between paragraphs.
    final prev = cur.paragraphs.lastWhere((p) => p.$1 != 'c' && p.$1 != 'i', orElse: () => ('p', '.')).$2;
    final pageBreak = pg - curStartPage >= (tocKeys.isEmpty ? 25 : 40) && RegExp(r'''[.!?]["”’)]?$''').hasMatch(prev);
    if ((tocBreak || pageBreak) && cur.paragraphs.isNotEmpty) {
      chapters.add(cur);
      cur = ImportedChapter(tocBreak ? b : '', []);
      curStartPage = pg;
    } else if (tocBreak && cur.title.isEmpty) {
      cur = ImportedChapter(b, cur.paragraphs, cur.meta);
      curStartPage = pg;
    }
    // In a book whose type sizes are known, a heading is set larger than the
    // text; a short line in the text's own size is a line of the text.
    final sz = (meta['sz'] as num?)?.toDouble();
    // The chapter's name again in small type at the foot or head of a page.
    if (fromToc != null && !tocBreak && usedToc.contains(fromToc) && meta['_t'] != null && (sz ?? 1) < 1.05) continue;
    final shownAsHeading = heading && (styler == null || meta['_t'] == null || (sz ?? 1) >= 1.12 || fromToc != null);
    cur.add(shownAsHeading ? 'h' : 'p', b, meta);
  }
  if (cur.paragraphs.isNotEmpty) chapters.add(cur);
  // A book set justified: its paragraphs are shown justified too (the last
  // lines of paragraphs and one-line paragraphs look left aligned anyway).
  var justified = 0, ragged = 0;
  for (final f in flat) {
    if (f.kind != 'p' || f.meta['sz'] != null || (f.meta['_n'] as int? ?? 0) < 3) continue;
    if (f.meta['al'] == 'j') justified++;
    if (f.meta['al'] == 'l') ragged++;
  }
  if (justified > ragged) {
    for (final c in chapters) {
      for (var k = 0; k < c.paragraphs.length; k++) {
        final m = c.metaAt(k);
        if (c.paragraphs[k].$1 == 'p' && m != null && m['al'] == 'l' && m['sz'] == null && m['toc'] == null) m['al'] = 'j';
      }
    }
  }
  // Pages only go forward (a picture waiting for its paragraph keeps the
  // page it was on), and the import-only keys go.
  var page = 0;
  for (var i = 0; i < chapters.length; i++) {
    final c = chapters[i];
    for (var k = 0; k < c.paragraphs.length; k++) {
      final m = c.metaAt(k);
      if (m == null) continue;
      final pg = m['pg'] as int? ?? page;
      if (pg > page) page = pg;
      m['pg'] = page;
      m.removeWhere((key, _) => key.startsWith('_'));
    }
    if (c.title.isEmpty) chapters[i] = ImportedChapter(L('Bölüm ${i + 1}', 'Chapter ${i + 1}'), c.paragraphs, c.meta);
  }
  final used = {for (final c in chapters) for (final p in c.paragraphs) if (p.$1 == 'i') p.$2};
  return ImportedBook(title, null, format, chapters, {
    for (final e in (images ?? const <String, List<int>>{}).entries)
      if (used.contains(e.key)) e.key: e.value
  });
}

/// A paragraph, caption or picture of the book in reading order, while importing.
class _Flat {
  final int page;
  final String kind;
  String text;
  final Map<String, Object?> meta;
  final bool toc;
  _Flat(this.page, this.kind, this.text, this.meta, {this.toc = false});
}
