import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:xml/xml.dart';

import '../data/user_db.dart';

const supportedExtensions = ['epub', 'pdf', 'txt', 'md', 'markdown', 'html', 'htm', 'xhtml', 'docx', 'odt', 'fb2', 'rtf'];

class ImportException implements Exception {
  final String message;
  ImportException(this.message);
  @override
  String toString() => message;
}

/// Converts a book file into the app's own chapter/paragraph format.
Future<ImportedBook> importFile(String path) async {
  final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
  final base = p.basenameWithoutExtension(path);
  if (ext == 'pdf') return _importPdf(path, base);
  final bytes = await File(path).readAsBytes();
  return Isolate.run(() => importBytes(bytes, ext, base));
}

ImportedBook importBytes(List<int> bytes, String ext, String fallbackTitle) {
  final ImportedBook book;
  switch (ext) {
    case 'epub':
      book = _importEpub(bytes, fallbackTitle);
    case 'txt':
      book = _fromPlain(_decodeText(bytes), fallbackTitle, 'txt', markdown: false);
    case 'md':
    case 'markdown':
      book = _fromPlain(_decodeText(bytes), fallbackTitle, 'md', markdown: true);
    case 'html':
    case 'htm':
    case 'xhtml':
      final doc = html.parse(_decodeText(bytes));
      final title = doc.querySelector('title')?.text.trim();
      book = _chunk(ImportedBook(title?.isNotEmpty == true ? title! : fallbackTitle, null, 'html',
          [ImportedChapter('', _htmlBlocks(doc.body ?? doc.documentElement!))]));
    case 'docx':
      book = _importDocx(bytes, fallbackTitle);
    case 'odt':
      book = _importOdt(bytes, fallbackTitle);
    case 'fb2':
      book = _importFb2(_decodeText(bytes), fallbackTitle);
    case 'rtf':
      book = _fromPlain(_rtfToText(latin1.decode(bytes, allowInvalid: true)), fallbackTitle, 'rtf', markdown: false);
    default:
      throw ImportException('Bu dosya türü desteklenmiyor: .$ext');
  }
  final chapters = book.chapters.where((c) => c.paragraphs.isNotEmpty).toList();
  if (chapters.isEmpty) throw ImportException('Dosyada okunabilir metin bulunamadı.');
  return ImportedBook(book.title, book.author, book.format, chapters);
}

String _decodeText(List<int> bytes) {
  if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    bytes = bytes.sublist(3);
  }
  final s = utf8.decode(bytes, allowMalformed: true);
  final bad = '\uFFFD'.allMatches(s).length;
  if (bad > s.length / 200) return latin1.decode(bytes, allowInvalid: true);
  return s;
}

String _clean(String s) => s.replaceAll(RegExp(r'[\s\u00A0]+'), ' ').trim();

// ---------------------------------------------------------------- plain text
final _chapterLine = RegExp(r'^\s*(chapter|part|book|bölüm|kısım|prologue|epilogue)\b[\s\w.:-]{0,60}$', caseSensitive: false);

ImportedBook _fromPlain(String text, String title, String format, {required bool markdown}) {
  text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final blocks = text.split(RegExp(r'\n\s*\n'));
  // Text without blank lines: treat each line as a paragraph.
  final pieces = blocks.length < 3 ? text.split('\n') : blocks;
  final chapters = <ImportedChapter>[];
  var cur = ImportedChapter('', []);
  for (var b in pieces) {
    b = b.trim();
    if (b.isEmpty) continue;
    var kind = 'p';
    if (markdown) {
      final h = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(b);
      if (h != null) {
        kind = 'h';
        b = h.group(2)!;
        if (h.group(1)!.length <= 2) {
          if (cur.paragraphs.isNotEmpty) chapters.add(cur);
          cur = ImportedChapter(_clean(b), []);
        }
      }
      b = b
          .replaceAllMapped(RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1)!)
          .replaceAll(RegExp(r'[*_`>]+'), '')
          .replaceAll(RegExp(r'^\s*[-+]\s+', multiLine: true), '');
    } else if (b.length < 70 && !b.contains('\n') && _chapterLine.hasMatch(b)) {
      kind = 'h';
      if (cur.paragraphs.isNotEmpty) chapters.add(cur);
      cur = ImportedChapter(_clean(b), []);
    }
    final t = _clean(b);
    if (t.isNotEmpty) cur.paragraphs.add((kind, t));
  }
  if (cur.paragraphs.isNotEmpty) chapters.add(cur);
  return _chunk(ImportedBook(title, null, format, chapters));
}

/// Splits very long chapters so the reader stays fast; names unnamed chapters.
ImportedBook _chunk(ImportedBook b, {int size = 80}) {
  final out = <ImportedChapter>[];
  for (final c in b.chapters) {
    if (c.paragraphs.length <= size * 1.5) {
      out.add(c);
      continue;
    }
    for (var i = 0; i < c.paragraphs.length; i += size) {
      final part = c.paragraphs.sublist(i, (i + size).clamp(0, c.paragraphs.length));
      out.add(ImportedChapter(c.title.isEmpty ? '' : '${c.title} (${i ~/ size + 1})', part));
    }
  }
  for (var i = 0; i < out.length; i++) {
    if (out[i].title.isEmpty) {
      final h = out[i].paragraphs.where((x) => x.$1 == 'h').map((x) => x.$2).firstOrNull;
      out[i] = ImportedChapter(h ?? 'Bölüm ${i + 1}', out[i].paragraphs);
    }
  }
  return ImportedBook(b.title, b.author, b.format, out);
}

// ---------------------------------------------------------------- HTML / EPUB
const _blockTags = {
  'p', 'div', 'section', 'article', 'blockquote', 'li', 'ul', 'ol', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
  'pre', 'dd', 'dt', 'dl', 'table', 'tr', 'td', 'th', 'figure', 'figcaption', 'header', 'footer', 'aside',
  'main', 'nav', 'body', 'hr', 'br'
};
const _skipTags = {'script', 'style', 'head', 'svg', 'math', 'img', 'nav'};

List<(String, String)> _htmlBlocks(dom.Element root) {
  final out = <(String, String)>[];
  final buf = StringBuffer();
  var kind = 'p';
  void flush() {
    final t = _clean(buf.toString());
    if (t.isNotEmpty) out.add((kind, t));
    buf.clear();
    kind = 'p';
  }

  void walk(dom.Node n) {
    if (n is dom.Text) {
      buf.write(n.text);
      return;
    }
    if (n is! dom.Element) return;
    final tag = n.localName ?? '';
    if (_skipTags.contains(tag)) return;
    if (tag == 'br') {
      buf.write(' ');
      return;
    }
    final block = _blockTags.contains(tag);
    if (block) flush();
    final isHeading = RegExp(r'^h[1-6]$').hasMatch(tag);
    for (final c in n.nodes) {
      walk(c);
    }
    if (isHeading) kind = 'h';
    if (block) flush();
  }

  walk(root);
  flush();
  return out;
}

ImportedBook _importEpub(List<int> bytes, String fallbackTitle) {
  final arc = ZipDecoder().decodeBytes(bytes);
  ArchiveFile? find(String name) {
    final n = Uri.decodeFull(name).replaceAll('\\', '/');
    for (final f in arc.files) {
      if (f.name == n || f.name.toLowerCase() == n.toLowerCase()) return f;
    }
    return null;
  }

  String read(ArchiveFile f) => utf8.decode(f.content as List<int>, allowMalformed: true);
  final container = find('META-INF/container.xml');
  if (container == null) throw ImportException('Geçersiz EPUB dosyası.');
  final opfPath = XmlDocument.parse(read(container)).findAllElements('rootfile').first.getAttribute('full-path')!;
  final opfDir = p.posix.dirname(opfPath) == '.' ? '' : '${p.posix.dirname(opfPath)}/';
  final opf = XmlDocument.parse(read(find(opfPath)!));
  String? meta(String local) =>
      opf.descendants.whereType<XmlElement>().where((e) => e.name.local == local).firstOrNull?.innerText.trim();
  final title = meta('title');
  final author = meta('creator');
  final manifest = <String, String>{};
  for (final it in opf.descendants.whereType<XmlElement>().where((e) => e.name.local == 'item')) {
    manifest[it.getAttribute('id')!] = it.getAttribute('href')!;
  }
  // Titles from the table of contents (EPUB 2 NCX or EPUB 3 nav).
  final tocTitles = <String, String>{};
  for (final f in arc.files) {
    if (f.name.endsWith('.ncx')) {
      final ncx = XmlDocument.parse(read(f));
      final dir = p.posix.dirname(f.name);
      for (final np in ncx.descendants.whereType<XmlElement>().where((e) => e.name.local == 'navPoint')) {
        final label = np.descendants.whereType<XmlElement>().where((e) => e.name.local == 'text').firstOrNull?.innerText;
        final src = np.descendants.whereType<XmlElement>().where((e) => e.name.local == 'content').firstOrNull?.getAttribute('src');
        if (label != null && src != null) {
          tocTitles.putIfAbsent(p.posix.normalize(p.posix.join(dir == '.' ? '' : dir, src.split('#').first)), () => _clean(label));
        }
      }
    }
  }
  final chapters = <ImportedChapter>[];
  for (final ref in opf.descendants.whereType<XmlElement>().where((e) => e.name.local == 'itemref')) {
    final href = manifest[ref.getAttribute('idref')];
    if (href == null) continue;
    final full = p.posix.normalize('$opfDir$href');
    final f = find(full);
    if (f == null) continue;
    final doc = html.parse(read(f));
    final blocks = _htmlBlocks(doc.body ?? doc.documentElement!);
    if (blocks.isEmpty) continue;
    chapters.add(ImportedChapter(tocTitles[full] ?? '', blocks));
  }
  return _chunk(ImportedBook(title?.isNotEmpty == true ? title! : fallbackTitle, author, 'epub', chapters));
}

// ---------------------------------------------------------------- DOCX / ODT / FB2
ImportedBook _importDocx(List<int> bytes, String fallbackTitle) {
  final arc = ZipDecoder().decodeBytes(bytes);
  final f = arc.files.where((f) => f.name == 'word/document.xml').firstOrNull;
  if (f == null) throw ImportException('Geçersiz DOCX dosyası.');
  final doc = XmlDocument.parse(utf8.decode(f.content as List<int>));
  final chapters = <ImportedChapter>[];
  var cur = ImportedChapter('', []);
  for (final para in doc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'p' && e.name.prefix == 'w')) {
    final style = para.descendants.whereType<XmlElement>().where((e) => e.name.local == 'pStyle').firstOrNull?.getAttribute('w:val') ?? '';
    final text = _clean(para.descendants.whereType<XmlElement>().where((e) => e.name.local == 't').map((e) => e.innerText).join());
    if (text.isEmpty) continue;
    final heading = RegExp(r'^(Heading|Başlık|Title)', caseSensitive: false).hasMatch(style);
    if (heading && RegExp(r'(1|Title)$').hasMatch(style)) {
      if (cur.paragraphs.isNotEmpty) chapters.add(cur);
      cur = ImportedChapter(text, []);
    }
    cur.paragraphs.add((heading ? 'h' : 'p', text));
  }
  if (cur.paragraphs.isNotEmpty) chapters.add(cur);
  return _chunk(ImportedBook(fallbackTitle, null, 'docx', chapters));
}

ImportedBook _importOdt(List<int> bytes, String fallbackTitle) {
  final arc = ZipDecoder().decodeBytes(bytes);
  final f = arc.files.where((f) => f.name == 'content.xml').firstOrNull;
  if (f == null) throw ImportException('Geçersiz ODT dosyası.');
  final doc = XmlDocument.parse(utf8.decode(f.content as List<int>));
  final chapters = <ImportedChapter>[];
  var cur = ImportedChapter('', []);
  for (final e in doc.descendants.whereType<XmlElement>().where((e) => e.name.prefix == 'text' && (e.name.local == 'p' || e.name.local == 'h'))) {
    final text = _clean(e.innerText);
    if (text.isEmpty) continue;
    if (e.name.local == 'h') {
      if (e.getAttribute('text:outline-level') == '1' && cur.paragraphs.isNotEmpty) {
        chapters.add(cur);
        cur = ImportedChapter(text, []);
      }
      cur.paragraphs.add(('h', text));
    } else {
      cur.paragraphs.add(('p', text));
    }
  }
  if (cur.paragraphs.isNotEmpty) chapters.add(cur);
  return _chunk(ImportedBook(fallbackTitle, null, 'odt', chapters));
}

ImportedBook _importFb2(String xml, String fallbackTitle) {
  final doc = XmlDocument.parse(xml);
  XmlElement? first(XmlNode n, String local) =>
      n.descendants.whereType<XmlElement>().where((e) => e.name.local == local).firstOrNull;
  final ti = first(doc, 'title-info');
  final title = ti == null ? null : first(ti, 'book-title')?.innerText.trim();
  final authorEl = ti == null ? null : first(ti, 'author');
  final author = authorEl == null
      ? null
      : _clean([first(authorEl, 'first-name')?.innerText, first(authorEl, 'last-name')?.innerText].whereType<String>().join(' '));
  final chapters = <ImportedChapter>[];
  final body = first(doc, 'body');
  if (body != null) {
    final sections = body.childElements.where((e) => e.name.local == 'section').toList();
    for (final s in sections.isEmpty ? [body] : sections) {
      final t = s.childElements.where((e) => e.name.local == 'title').firstOrNull;
      final paras = <(String, String)>[];
      if (t != null) paras.add(('h', _clean(t.innerText)));
      for (final e in s.descendants.whereType<XmlElement>().where((e) => e.name.local == 'p' || e.name.local == 'v')) {
        if (e.ancestors.whereType<XmlElement>().any((a) => a.name.local == 'title')) continue;
        final x = _clean(e.innerText);
        if (x.isNotEmpty) paras.add(('p', x));
      }
      chapters.add(ImportedChapter(t == null ? '' : _clean(t.innerText), paras));
    }
  }
  return _chunk(ImportedBook(title?.isNotEmpty == true ? title! : fallbackTitle, author, 'fb2', chapters));
}

String _rtfToText(String rtf) {
  var s = rtf;
  // drop destination groups like {\*\generator ...}, font and color tables
  s = s.replaceAll(RegExp(r'\{\\\*[^{}]*\}'), '');
  s = s.replaceAll(RegExp(r'\{\\(fonttbl|colortbl|stylesheet|info)[\s\S]*?\}\s*\}'), '');
  s = s.replaceAllMapped(RegExp(r"\\'([0-9a-fA-F]{2})"), (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)));
  s = s.replaceAllMapped(RegExp(r'\\u(-?\d+)\??'), (m) {
    var c = int.parse(m.group(1)!);
    if (c < 0) c += 65536;
    return String.fromCharCode(c);
  });
  s = s.replaceAll(RegExp(r'\\(par|line)\b ?'), '\n\n');
  s = s.replaceAll(RegExp(r'\\[a-zA-Z]+-?\d* ?'), '');
  s = s.replaceAll(RegExp(r'[{}]'), '');
  return s;
}

// ---------------------------------------------------------------- PDF
Future<ImportedBook> _importPdf(String path, String fallbackTitle) async {
  await pdfrxFlutterInitialize();
  final doc = await PdfDocument.openFile(path);
  try {
    final pageLines = <List<String>>[];
    var chars = 0;
    for (final page in doc.pages) {
      final t = await page.loadText();
      final text = t?.fullText ?? '';
      chars += text.trim().length;
      pageLines.add(text.replaceAll('\r', '\n').split('\n').map((l) => l.trimRight()).toList());
    }
    if (chars < 40 * doc.pages.length.clamp(1, 1 << 30) && chars < 2000) {
      throw ImportException(
          'Bu PDF taranmış (resim) bir belge gibi görünüyor; içinde seçilebilir metin yok. '
          'Resimden metne (OCR) desteği sonraki sürümde gelecek.');
    }
    // Lines that repeat on many pages are headers/footers.
    final freq = <String, int>{};
    for (final lines in pageLines) {
      for (final l in lines.toSet()) {
        final k = l.trim().replaceAll(RegExp(r'\d+'), '#');
        if (k.isNotEmpty) freq[k] = (freq[k] ?? 0) + 1;
      }
    }
    final repeated = pageLines.length >= 6
        ? freq.entries.where((e) => e.value > pageLines.length * 0.4).map((e) => e.key).toSet()
        : <String>{};
    final chapters = <ImportedChapter>[];
    const perChapter = 10;
    String carry = '';
    for (var start = 0; start < pageLines.length; start += perChapter) {
      final end = (start + perChapter).clamp(0, pageLines.length);
      final paras = <(String, String)>[];
      for (var pg = start; pg < end; pg++) {
        final lines = pageLines[pg]
            .where((l) => l.trim().isNotEmpty)
            .where((l) => !RegExp(r'^\s*\d{1,4}\s*$').hasMatch(l))
            .where((l) => !repeated.contains(l.trim().replaceAll(RegExp(r'\d+'), '#')))
            .toList();
        if (lines.isEmpty) continue;
        final lens = lines.map((l) => l.trim().length).toList()..sort();
        final typical = lens[(lens.length * 0.8).floor().clamp(0, lens.length - 1)];
        var buf = carry;
        carry = '';
        for (var i = 0; i < lines.length; i++) {
          final l = lines[i].trim();
          if (buf.endsWith('-') && RegExp(r'^[a-z]').hasMatch(l)) {
            buf = buf.substring(0, buf.length - 1) + l;
          } else {
            buf = buf.isEmpty ? l : '$buf $l';
          }
          final endsSentence = RegExp(r'[.!?:"”’)]$').hasMatch(l);
          final short = l.length < typical * 0.75;
          if ((endsSentence && short) || (short && l.length < 60 && !endsSentence && i + 1 < lines.length && RegExp(r'^[A-Z0-9]').hasMatch(lines[i + 1].trim()) && l == l.toUpperCase())) {
            paras.add((l == l.toUpperCase() && l.length < 60 && !endsSentence ? 'h' : 'p', _clean(buf)));
            buf = '';
          }
        }
        if (buf.isNotEmpty) {
          if (RegExp(r'[.!?"”]$').hasMatch(buf)) {
            paras.add(('p', _clean(buf)));
          } else if (pg == end - 1) {
            carry = buf; // continues on the next chapter's first page
          } else {
            carry = buf;
          }
        }
        if (carry.isNotEmpty && pg < end - 1) {
          // keep carrying inside the chapter
        }
      }
      if (carry.isNotEmpty && end == pageLines.length) {
        paras.add(('p', _clean(carry)));
        carry = '';
      }
      chapters.add(ImportedChapter('Sayfa ${start + 1}–$end', paras));
    }
    return ImportedBook(fallbackTitle, null, 'pdf', chapters.where((c) => c.paragraphs.isNotEmpty).toList());
  } finally {
    await doc.dispose();
  }
}
