import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

import '../data/user_db.dart';
import 'importers.dart';
import '../l10n.dart';
import 'ocr.dart';
import 'pdf_layout.dart';
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
    for (var i = 0; i < n; i++) {
      final raw = await doc.pages[i].loadText();
      final boxes = raw == null
          ? const <GlyphBox>[]
          : [for (final r in raw.charRects) (left: r.left, top: r.top, right: r.right, bottom: r.bottom)];
      final t = raw == null
          ? ''
          : layoutPdfPage(raw.fullText, boxes, isWord: isWord) ?? addGapSpaces(raw.fullText, boxes, isWord);
      pages.add(t);
      if ((raw?.fullText ?? '').trim().length < 25) ocrPages.add(i);
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
    return buildBookFromPages(pages, fallbackTitle, 'pdf', isWord: isWord);
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

ImportedBook buildBookFromPages(List<String> pages, String title, String format, {bool Function(String word)? isWord}) {
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
  final pageCaptions = <List<String>>[];
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
    final hasContents = text.split('\n').any((l) => _contentsLine.hasMatch(l.trim().replaceAll(RegExp(r'(?<=\w) (?=\w)'), '')));
    final lines = text
        .split('\n')
        .map((l) => l.trimRight())
        .where((l) => l.trim().isEmpty || (!_noise(l) && !repeated.contains(l.trim().replaceAll(RegExp(r'\d+'), '#'))))
        .toList();
    final blocks = <String>[];
    void addLine(StringBuffer buf, String l) {
      final s = buf.toString();
      if (s.endsWith('-') && RegExp(r'^[a-z]').hasMatch(l)) {
        buf
          ..clear()
          ..write(s.substring(0, s.length - 1))
          ..write(l);
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
      return false;
    }

    if (fromOcr || fromLayout || text.contains(RegExp(r'\n\s*\n'))) {
      final buf = StringBuffer();
      for (final l in [...lines, '']) {
        if (l.trim().isEmpty) {
          if (buf.isNotEmpty) blocks.add(_clean(buf.toString()));
          buf.clear();
        } else {
          if (tocEntry(l.trim())) continue;
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
          if (tocEntry(l)) continue;
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

    String fix(String b) => isWord == null ? b : splitJoinedWords(b, isWord);
    pageBlocks.add([
      for (final b in blocks)
        if (b.isNotEmpty && !garbage(b)) fix(b)
    ]);
    printed.add(pageNo);
    pageCaptions.add([
      for (final c in captions)
        if (!_noise(c)) fix(_clean(c))
    ]);
  }

  // 2. join paragraphs that continue on the next page; captions wait until
  // the paragraph they interrupt is over.
  final flat = <(int page, String kind, String text)>[];
  final waiting = <(int, String, String)>[];
  for (var pg = 0; pg < pageBlocks.length; pg++) {
    for (var i = 0; i < pageBlocks[pg].length; i++) {
      final b = pageBlocks[pg][i];
      final prev = flat.isEmpty || flat.last.$2 != 'p' ? '' : flat.last.$3;
      final open = prev.isNotEmpty && !RegExp(r'''[.!?]["”’)]?$''').hasMatch(prev);
      if (open && RegExp(r'^[a-z]').hasMatch(b)) {
        flat[flat.length - 1] = (flat.last.$1, 'p', '$prev $b');
      } else {
        flat.addAll(waiting);
        waiting.clear();
        flat.add((pg, 'p', b));
      }
    }
    for (final c in pageCaptions[pg]) {
      waiting.add((pg, 'c', c));
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
    var (pg, kind, b) = flat[fi];
    if (kind == 'c') {
      cur.paragraphs.add(('c', b));
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
        // The heading is drawn as a picture on the page: show the contents' title.
        cur.paragraphs
          ..add(('h', start))
          ..add(('p', b));
        continue;
      }
    }
    // Without a table of contents, a heading followed by real paragraphs starts a chapter.
    final storyHeading = tocKeys.isEmpty &&
        heading &&
        fi + 3 < flat.length &&
        flat.sublist(fi + 1, fi + 4).every((x) => x.$2 == 'c' || (!isHeading(x.$3) && x.$3.length > 60));
    // "Chapter 2", "CHAPTER XII. Alice's Evidence", "Bölüm 3" always start a chapter.
    final named = heading && _chapterWord.hasMatch(b) && b.length <= 70;
    final tocBreak = heading && ((fromToc != null && !usedToc.contains(fromToc)) || storyHeading || named);
    if (fromToc != null && tocBreak) {
      usedToc.add(fromToc);
      b = fromToc;
    }
    // Long books without headings are cut every 25 pages, between paragraphs.
    final prev = cur.paragraphs.lastWhere((p) => p.$1 != 'c', orElse: () => ('p', '.')).$2;
    final pageBreak = pg - curStartPage >= (tocKeys.isEmpty ? 25 : 40) && RegExp(r'''[.!?]["”’)]?$''').hasMatch(prev);
    if ((tocBreak || pageBreak) && cur.paragraphs.isNotEmpty) {
      chapters.add(cur);
      cur = ImportedChapter(tocBreak ? b : '', []);
      curStartPage = pg;
    } else if (tocBreak && cur.title.isEmpty) {
      cur = ImportedChapter(b, cur.paragraphs);
      curStartPage = pg;
    }
    cur.paragraphs.add((heading ? 'h' : 'p', b));
  }
  if (cur.paragraphs.isNotEmpty) chapters.add(cur);
  for (var i = 0; i < chapters.length; i++) {
    if (chapters[i].title.isEmpty) chapters[i] = ImportedChapter(L('Bölüm ${i + 1}', 'Chapter ${i + 1}'), chapters[i].paragraphs);
  }
  return ImportedBook(title, null, format, chapters);
}
