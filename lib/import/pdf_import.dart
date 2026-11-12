import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

import '../data/user_db.dart';
import 'importers.dart';
import 'ocr.dart';

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
  if (im == null) throw ImportException('Sayfa görüntüsü oluşturulamadı.');
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
      final t = (await doc.pages[i].loadText())?.fullText ?? '';
      pages.add(t);
      if (t.trim().length < 25) ocrPages.add(i);
    }
    if (ocrPages.isNotEmpty) {
      if (ocr == null) {
        if (ocrPages.length == n) {
          throw ImportException('Bu PDF taranmış (resim) bir belge; içinde seçilebilir metin yok. '
              'Resimden metin okumak için bu cihazda OCR bulunamadı. Ayarlar\'dan resim okuyabilen bir yapay zekâ '
              'servisi bağlayıp internete bağlıyken tekrar deneyin.');
        }
      } else {
        var k = 0;
        for (final i in ocrPages) {
          k++;
          onProgress?.call('Resimden metin okunuyor (${ocr.name}): sayfa $k/${ocrPages.length}');
          final png = await _renderPage(doc.pages[i]);
          pages[i] = '\u0001${await ocr.recognize(png)}';
        }
      }
    }
    onProgress?.call('Paragraflar düzenleniyor…');
    return buildBookFromPages(pages, fallbackTitle, 'pdf', isWord: isWord);
  } finally {
    await doc.dispose();
  }
}

/// A photo or scan of a page.
Future<ImportedBook> importImage(String path, String fallbackTitle,
    {OcrEngine? ocr, ImportProgress? onProgress, bool Function(String word)? isWord}) async {
  if (ocr == null) {
    throw ImportException('Resimden metin okumak için bu cihazda OCR bulunamadı. Ayarlar\'dan resim okuyabilen bir '
        'yapay zekâ servisi bağlayın.');
  }
  final bytes = await File(path).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final png = await _toPng(frame.image);
  onProgress?.call('Resimden metin okunuyor (${ocr.name})…');
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
  return letters < 2 || letters / t.length < 0.55;
}

/// Turns page texts into chapters/paragraphs. Pages starting with \u0001
/// come from OCR, where blank lines separate paragraphs.
/// Typical OCR slips: a vertical bar read instead of the capital I.
String fixOcr(String s) => s
    .replaceAllMapped(RegExp(r'''(^|[\s“"(‘'])\|(?=['’]|\s|$)''', multiLine: true), (m) => '${m.group(1)}I')
    .replaceAll(RegExp(r'[ \t]+'), ' ');

ImportedBook buildBookFromPages(List<String> pages, String title, String format, {bool Function(String word)? isWord}) {
  // Lines repeated on many pages are running headers/footers.
  final freq = <String, int>{};
  for (final pg in pages) {
    for (final l in pg.split('\n').map((l) => l.trim()).toSet()) {
      final k = l.replaceAll(RegExp(r'\d+'), '#');
      if (k.isNotEmpty) freq[k] = (freq[k] ?? 0) + 1;
    }
  }
  final repeated = pages.length >= 6 ? freq.entries.where((e) => e.value > pages.length * 0.4).map((e) => e.key).toSet() : <String>{};

  // 1. blocks per page
  final pageBlocks = <List<String>>[];
  final toc = <String>[];
  for (final raw in pages) {
    final fromOcr = raw.startsWith('\u0001');
    final text = (fromOcr ? fixOcr(raw.substring(1)) : raw).replaceAll('\r', '\n');
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

    if (fromOcr || text.contains(RegExp(r'\n\s*\n'))) {
      final buf = StringBuffer();
      for (final l in [...lines, '']) {
        if (l.trim().isEmpty) {
          if (buf.isNotEmpty) blocks.add(_clean(buf.toString()));
          buf.clear();
        } else {
          final m = _tocLine.firstMatch(l.trim());
          if (m != null) {
            toc.add(_clean(m.group(1)!));
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
          final m = _tocLine.firstMatch(l);
          if (m != null) {
            toc.add(_clean(m.group(1)!));
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

    pageBlocks.add(blocks.where((b) => b.isNotEmpty && !garbage(b)).toList());
  }

  // 2. join paragraphs that continue on the next page
  final flat = <(int page, String text)>[];
  for (var pg = 0; pg < pageBlocks.length; pg++) {
    for (var i = 0; i < pageBlocks[pg].length; i++) {
      final b = pageBlocks[pg][i];
      final prev = flat.isEmpty ? '' : flat.last.$2;
      final open = prev.isNotEmpty && !RegExp(r'''[.!?]["”’)]?$''').hasMatch(prev);
      if (open && RegExp(r'^[a-z]').hasMatch(b)) {
        flat[flat.length - 1] = (flat.last.$1, '${flat.last.$2} $b');
      } else {
        flat.add((pg, b));
      }
    }
  }

  // 3. headings and chapters
  final tocSet = toc.map((t) => t.toLowerCase()).toSet();
  bool isHeading(String b) {
    final words = b.split(' ');
    if (tocSet.contains(b.toLowerCase())) return true;
    if (words.length > 7 || _sentenceEnd.hasMatch(b)) return false;
    final caps = words.where((w) => w.isNotEmpty && w[0].toUpperCase() == w[0]).length;
    return caps >= (words.length * 0.6).ceil();
  }

  final chapters = <ImportedChapter>[];
  var cur = ImportedChapter('', []);
  var curStartPage = 0;
  for (var fi = 0; fi < flat.length; fi++) {
    final (pg, b) = flat[fi];
    final heading = isHeading(b);
    // Without a table of contents, a heading followed by real paragraphs starts a chapter.
    final storyHeading = tocSet.isEmpty &&
        heading &&
        fi + 3 < flat.length &&
        flat.sublist(fi + 1, fi + 4).every((x) => !isHeading(x.$2) && x.$2.length > 60);
    final tocBreak = heading && (tocSet.contains(b.toLowerCase()) || storyHeading);
    final pageBreak = tocSet.isEmpty && pg - curStartPage >= 25;
    if ((tocBreak || pageBreak) && cur.paragraphs.isNotEmpty) {
      chapters.add(cur);
      cur = ImportedChapter(tocBreak ? b : '', []);
      curStartPage = pg;
    } else if (tocBreak && cur.title.isEmpty) {
      cur = ImportedChapter(b, cur.paragraphs);
    }
    cur.paragraphs.add((heading ? 'h' : 'p', b));
  }
  if (cur.paragraphs.isNotEmpty) chapters.add(cur);
  for (var i = 0; i < chapters.length; i++) {
    if (chapters[i].title.isEmpty) chapters[i] = ImportedChapter('Bölüm ${i + 1}', chapters[i].paragraphs);
  }
  return ImportedBook(title, null, format, chapters);
}
