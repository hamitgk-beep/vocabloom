import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:image/image.dart' as im;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../data/user_db.dart';
import 'ocr.dart';
import '../l10n.dart';
import 'pdf_import.dart';
import 'text_repair.dart';

const supportedExtensions = [
  'epub', 'pdf', 'txt', 'md', 'markdown', 'html', 'htm', 'xhtml', 'docx', 'odt', 'fb2', 'rtf', 'jpg', 'jpeg', 'png'
];

/// Keeps a picture of an e-book file for the reader and returns its name in
/// [images], or null when it is not worth showing (an icon, a spacer, a
/// format the reader cannot draw). The same file is kept once.
String? keepPicture(Map<String, List<int>> images, Map<String, String> names, String path, List<int>? bytes) {
  if (bytes == null || bytes.length < 600) return null;
  final known = names[path];
  if (known != null) return known;
  final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  final dec = im.findDecoderForData(data);
  if (dec == null) return null;
  final ext = switch (dec.format) {
    im.ImageFormat.jpg => 'jpg',
    im.ImageFormat.png => 'png',
    im.ImageFormat.gif => 'gif',
    im.ImageFormat.webp => 'webp',
    im.ImageFormat.bmp => 'bmp',
    _ => null,
  };
  if (ext == null) return null;
  final info = dec.startDecode(data);
  if (info != null && (info.width < 60 || info.height < 60)) return null;
  final name = 'e${images.length + 1}.$ext';
  images[name] = data;
  names[path] = name;
  return name;
}

typedef ImportProgress = void Function(String message);

class ImportException implements Exception {
  final String message;
  ImportException(this.message);
  @override
  String toString() => message;
}

/// Whether a book title is a machine-made name rather than a real title:
/// a UUID or a long hex/number string ("9bfdefed-8b6d-4c1e-…"), which some
/// Android file providers give copied files, or an empty one.
bool looksGeneratedTitle(String title) {
  final t = title.trim().toLowerCase();
  if (t.isEmpty) return true;
  if (RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}').hasMatch(t)) return true;
  final core = t.replaceAll(RegExp(r'[\s_\-.()]'), '');
  if (core.length >= 12 && RegExp(r'^[0-9a-f]+$').hasMatch(core) && RegExp(r'\d').hasMatch(core)) return true;
  if (RegExp(r'^(document|msf|primary|image|file|download)[:_ \-]*\d+$').hasMatch(t)) return true;
  return false;
}

/// A readable title taken from the book itself: its first real chapter
/// title or heading, otherwise the opening words of its first paragraph.
String titleFromContent(List<String> chapterTitles, List<(String kind, String text)> firstParas) {
  final generic = RegExp(r'^(bölüm|chapter|part|kısım)\s*\d+', caseSensitive: false);
  String clip(String s) {
    final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length <= 60) return t;
    final cut = t.substring(0, 60);
    final sp = cut.lastIndexOf(' ');
    return '${(sp > 30 ? cut.substring(0, sp) : cut).trim()}…';
  }

  for (final c in chapterTitles) {
    final t = c.trim();
    if (t.length > 2 && !generic.hasMatch(t) && !looksGeneratedTitle(t)) return clip(t);
  }
  for (final p in firstParas) {
    if (p.$1 == 'h' && p.$2.trim().length > 2 && !looksGeneratedTitle(p.$2)) return clip(p.$2);
  }
  for (final p in firstParas) {
    if (p.$2.trim().length > 2) return clip(p.$2.split(RegExp(r'(?<=[.!?])\s')).first);
  }
  return chapterTitles.firstOrNull ?? '';
}

/// [b] with a title from its contents when its own title is machine-made.
ImportedBook withReadableTitle(ImportedBook b) {
  if (!looksGeneratedTitle(b.title)) return b;
  final t = titleFromContent(
      [for (final c in b.chapters) c.title], [for (final c in b.chapters.take(2)) ...c.paragraphs.take(5)]);
  return t.isEmpty ? b : ImportedBook(t, b.author, b.format, b.chapters, b.images);
}

/// Converts a book file into the app's own chapter/paragraph format.
Future<ImportedBook> importFile(String path, {OcrEngine? ocr, ImportProgress? onProgress, bool Function(String word)? isWord}) async =>
    withReadableTitle(await _importFile(path, ocr: ocr, onProgress: onProgress, isWord: isWord));

Future<ImportedBook> _importFile(String path, {OcrEngine? ocr, ImportProgress? onProgress, bool Function(String word)? isWord}) async {
  final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
  final base = p.basenameWithoutExtension(path);
  if (ext == 'pdf') return importPdf(path, base, ocr: ocr, onProgress: onProgress, isWord: isWord);
  if (ext == 'jpg' || ext == 'jpeg' || ext == 'png') {
    return importImage(path, base, ocr: ocr, onProgress: onProgress, isWord: isWord);
  }
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
      throw ImportException(L('Bu dosya türü desteklenmiyor: .$ext', 'This file type is not supported: .$ext'));
  }
  // Soft hyphens, zero-width spaces, control characters and symbol-font bullets.
  final chapters = [
    for (final c in book.chapters)
      ImportedChapter(cleanInvisible(c.title), [
        for (final p in c.paragraphs)
          if (cleanInvisible(p.$2).isNotEmpty) (p.$1, p.$1 == 'i' ? p.$2 : cleanInvisible(p.$2))
      ])
  ].where((c) => c.paragraphs.isNotEmpty).toList();
  if (!chapters.any((c) => c.paragraphs.any((p) => p.$1 != 'i'))) {
    throw ImportException(L('Dosyada okunabilir metin bulunamadı.', 'No readable text was found in the file.'));
  }
  return ImportedBook(book.title, book.author, book.format, chapters, book.images);
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
/// "CHAPTER VIII. The Queen's Croquet-Ground", "Chapter 3", "Part Two", "Bölüm 4", "Prologue".
final _chapterLine = RegExp(
    r'^\s*(?:(?:chapter|part|book|bölüm|kısım)\s+(?:\d{1,3}|[ivxlc]{1,7}|one|two|three|four|five|six|seven|eight|nine|ten|'
    r'eleven|twelve|first|second|third)\b|prologue\b|epilogue\b)[^\n]{0,60}$',
    caseSensitive: false);

/// Project Gutenberg's own notes before and after the book, and its licence.
String _withoutGutenbergNotes(String text) {
  final start = RegExp(r'^\*{3}\s*START OF (?:THE|THIS) PROJECT GUTENBERG.*$', multiLine: true, caseSensitive: false).firstMatch(text);
  final end = RegExp(r'^\*{3}\s*END OF (?:THE|THIS) PROJECT GUTENBERG.*$', multiLine: true, caseSensitive: false)
      .firstMatch(text);
  if (start == null || end == null || end.start <= start.end) return text;
  return text.substring(start.end, end.start);
}

/// _Italic_ words marked with underscores, as plain text books write them.
/// Blanks to fill in ("my __ ") stay.
String _withoutUnderscoreItalics(String s) =>
    s.replaceAllMapped(RegExp(r'''(?<![\w_])_(?=[^\s_])([^_]*?[A-Za-z][^_]*?)(?<=[^\s_])_(?![\w_])'''), (m) => m.group(1)!);

ImportedBook _fromPlain(String text, String title, String format, {required bool markdown}) {
  text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  text = _withoutGutenbergNotes(text);
  if (!markdown) text = _withoutUnderscoreItalics(text);
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

/// A text from the free library: Markdown made by tools/library/build_library.py.
/// `# Title` starts a chapter, `### Title` is a heading inside it, a block
/// that is only `![description](address "caption")` is a picture (with its
/// caption when the book prints one), and a line `---` turns the page: a
/// picture book keeps its pages, one picture and its text on each.
/// [pictures] has the pictures' files by address; a picture that is not
/// there is left out with its caption. [format] is shown on the cover (the level).
ImportedBook importLibraryMarkdown(String md, String title, String? author, String format,
    {Map<String, List<int>> pictures = const {}}) {
  final images = <String, List<int>>{}, names = <String, String>{};
  final paged = RegExp(r'^---\s*$', multiLine: true).hasMatch(md);
  final chapters = <ImportedChapter>[];
  var cur = ImportedChapter('', []);
  var page = 0;
  final picture = RegExp(r'^!\[([^\]]*)\]\(\s*(\S+?)(?:\s+"([^"]*)")?\s*\)$');
  for (var b in md.replaceAll('\r\n', '\n').split(RegExp(r'\n\s*\n'))) {
    b = b.trim();
    if (b.isEmpty) continue;
    Map<String, Object?>? meta() => paged ? {'pg': page} : null;
    if (RegExp(r'^---$').hasMatch(b)) {
      if (cur.paragraphs.isNotEmpty) page++;
      continue;
    }
    final h = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(b);
    if (h != null && h.group(1)!.length <= 2) {
      if (cur.paragraphs.isNotEmpty) chapters.add(cur);
      cur = ImportedChapter(_clean(h.group(2)!), []);
      cur.add('h', _clean(h.group(2)!), meta());
      continue;
    }
    if (h != null) {
      cur.add('h', _clean(h.group(2)!), meta());
      continue;
    }
    final pic = picture.firstMatch(b);
    if (pic != null) {
      final bytes = pictures[pic.group(2)!];
      final name = keepPicture(images, names, pic.group(2)!, bytes);
      if (name == null) continue;
      final m = <String, Object?>{...?meta()};
      final info = im.findDecoderForData(Uint8List.fromList(bytes!))?.startDecode(Uint8List.fromList(bytes));
      if (info != null && info.height > 0) {
        m['ar'] = (info.width / info.height * 1000).round() / 1000;
        // A small drawing (an ornament, a vignette) stays small.
        m['wr'] = (info.width / 640).clamp(0.3, 1.0);
      }
      cur.add('i', name, m);
      final cap = _clean(pic.group(3) ?? '');
      if (cap.isNotEmpty) cur.add('c', cap, {...?meta(), 'al': 'c'});
      continue;
    }
    final t = _clean(b.replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1)!).replaceAll(RegExp(r'[*_`>]+'), ''));
    if (t.isNotEmpty) cur.add('p', t, meta());
  }
  if (cur.paragraphs.isNotEmpty) chapters.add(cur);
  return _chunk(ImportedBook(title, author, format, chapters, images));
}

/// The addresses of the pictures in a free-library text, in order.
List<String> libraryPictures(String md) => [
  for (final m in RegExp(r'^!\[[^\]]*\]\(\s*(\S+?)(?:\s+"[^"]*")?\s*\)\s*$', multiLine: true).allMatches(md)) m.group(1)!,
];

/// Splits very long chapters so the reader stays fast; names unnamed chapters.
ImportedBook _chunk(ImportedBook b, {int size = 80}) {
  final out = <ImportedChapter>[];
  for (final c in b.chapters) {
    if (c.paragraphs.length <= size * 1.5) {
      out.add(c);
      continue;
    }
    for (var i = 0; i < c.paragraphs.length; i += size) {
      final end = (i + size).clamp(0, c.paragraphs.length);
      final part = c.paragraphs.sublist(i, end);
      out.add(ImportedChapter(c.title.isEmpty ? '' : '${c.title} (${i ~/ size + 1})', part, [for (var k = i; k < end; k++) c.metaAt(k)]));
    }
  }
  for (var i = 0; i < out.length; i++) {
    if (out[i].title.isEmpty) {
      final h = out[i].paragraphs.where((x) => x.$1 == 'h').map((x) => x.$2).firstOrNull;
      out[i] = ImportedChapter(h ?? L('Bölüm ${i + 1}', 'Chapter ${i + 1}'), out[i].paragraphs, out[i].meta);
    }
  }
  return ImportedBook(b.title, b.author, b.format, out, b.images);
}

// ---------------------------------------------------------------- HTML / EPUB
const _blockTags = {
  'p', 'div', 'section', 'article', 'blockquote', 'li', 'ul', 'ol', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
  'pre', 'dd', 'dt', 'dl', 'table', 'tr', 'td', 'th', 'figure', 'figcaption', 'header', 'footer', 'aside',
  'main', 'nav', 'body', 'hr', 'br'
};
const _skipTags = {'script', 'style', 'head', 'svg', 'math', 'img', 'nav'};

/// Paragraphs of an HTML page. With [picture], pictures (`<img>`, an `<svg>`
/// with an `<image>`) become 'i' paragraphs where they are, named by
/// [picture] from their address, and a `<figcaption>` is a caption ('c').
List<(String, String)> _htmlBlocks(dom.Element root, {String? Function(String src)? picture}) {
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
    if (picture != null && (tag == 'img' || tag == 'svg')) {
      final src = tag == 'img'
          ? n.attributes['src']
          : n.querySelector('image')?.attributes['xlink:href'] ?? n.querySelector('image')?.attributes['href'];
      final name = src == null ? null : picture(src);
      if (name != null) {
        flush();
        out.add(('i', name));
      }
      return;
    }
    if (_skipTags.contains(tag)) return;
    // Project Gutenberg's notes and licence around the book.
    if ({'pg-header', 'pg-footer', 'pg-machine-header', 'pg-start-separator', 'pg-end-separator'}.contains(n.id) ||
        n.classes.contains('pg-boilerplate')) {
      return;
    }
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
    if (tag == 'figcaption' && picture != null) kind = 'c';
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
  if (container == null) throw ImportException(L('Geçersiz EPUB dosyası.', 'Invalid EPUB file.'));
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
  final images = <String, List<int>>{}, names = <String, String>{};
  for (final ref in opf.descendants.whereType<XmlElement>().where((e) => e.name.local == 'itemref')) {
    final href = manifest[ref.getAttribute('idref')];
    if (href == null) continue;
    final full = p.posix.normalize('$opfDir$href');
    final f = find(full);
    if (f == null) continue;
    final doc = html.parse(read(f));
    String? picture(String src) {
      if (src.startsWith('data:') || src.contains('://')) return null;
      final path = p.posix.normalize(p.posix.join(p.posix.dirname(full), src.split('#').first));
      return keepPicture(images, names, path, find(path)?.content as List<int>?);
    }

    final blocks = _htmlBlocks(doc.body ?? doc.documentElement!, picture: picture);
    // A page with only a picture (the cover, a plate) is still a page of the book.
    if (blocks.isEmpty) continue;
    chapters.add(ImportedChapter(tocTitles[full] ?? '', blocks));
  }
  return _chunk(ImportedBook(title?.isNotEmpty == true ? title! : fallbackTitle, author, 'epub', chapters, images));
}

// ---------------------------------------------------------------- DOCX / ODT / FB2
ImportedBook _importDocx(List<int> bytes, String fallbackTitle) {
  final arc = ZipDecoder().decodeBytes(bytes);
  final f = arc.files.where((f) => f.name == 'word/document.xml').firstOrNull;
  if (f == null) throw ImportException(L('Geçersiz DOCX dosyası.', 'Invalid DOCX file.'));
  final doc = XmlDocument.parse(utf8.decode(f.content as List<int>));
  // Pictures: <a:blip r:embed="rId5"/> names a file in word/_rels/document.xml.rels.
  final rels = <String, String>{};
  final relFile = arc.files.where((f) => f.name == 'word/_rels/document.xml.rels').firstOrNull;
  if (relFile != null) {
    for (final r in XmlDocument.parse(utf8.decode(relFile.content as List<int>)).descendants.whereType<XmlElement>()) {
      final id = r.getAttribute('Id'), target = r.getAttribute('Target');
      if (r.name.local == 'Relationship' && id != null && target != null) rels[id] = p.posix.normalize(p.posix.join('word', target));
    }
  }
  final images = <String, List<int>>{}, names = <String, String>{};
  final chapters = <ImportedChapter>[];
  var cur = ImportedChapter('', []);
  for (final para in doc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'p' && e.name.prefix == 'w')) {
    final style = para.descendants.whereType<XmlElement>().where((e) => e.name.local == 'pStyle').firstOrNull?.getAttribute('w:val') ?? '';
    for (final blip in para.descendants.whereType<XmlElement>().where((e) => e.name.local == 'blip')) {
      final path = rels[blip.getAttribute('r:embed') ?? ''];
      if (path == null) continue;
      final name = keepPicture(images, names, path, arc.files.where((f) => f.name == path).firstOrNull?.content as List<int>?);
      if (name != null) cur.paragraphs.add(('i', name));
    }
    final text = _clean(_docxText(para));
    if (text.isEmpty) continue;
    if (RegExp(r'^(Caption|ResimYaz)', caseSensitive: false).hasMatch(style)) {
      cur.paragraphs.add(('c', text));
      continue;
    }
    final heading = RegExp(r'^(Heading|Başlık|Title)', caseSensitive: false).hasMatch(style);
    if (heading && RegExp(r'(1|Title)$').hasMatch(style)) {
      if (cur.paragraphs.isNotEmpty) chapters.add(cur);
      cur = ImportedChapter(text, []);
    }
    cur.paragraphs.add((heading ? 'h' : 'p', text));
  }
  if (cur.paragraphs.isNotEmpty) chapters.add(cur);
  return _chunk(ImportedBook(fallbackTitle, null, 'docx', chapters, images));
}

/// Text of a Word paragraph. Tabs and line breaks inside it separate words
/// ("Twinkle, twinkle, little star,<br>How I wonder").
String _docxText(XmlElement para) {
  final b = StringBuffer();
  for (final e in para.descendants.whereType<XmlElement>()) {
    if (e.name.prefix != 'w') continue;
    switch (e.name.local) {
      case 't':
        b.write(e.innerText);
      case 'tab' || 'br' || 'cr':
        if (e.parentElement?.name.local == 'r') b.write(' ');
      case 'noBreakHyphen':
        b.write('-');
    }
  }
  return b.toString();
}

/// Text of an OpenDocument paragraph: <text:s/> is a space, tabs and line
/// breaks separate words, and a footnote's text is not part of the sentence.
String _odtText(XmlNode n) {
  final b = StringBuffer();
  void walk(XmlNode n) {
    if (n is XmlText || n is XmlCDATA) {
      b.write(n.value);
      return;
    }
    if (n is! XmlElement) return;
    if (n.name.prefix == 'text') {
      switch (n.name.local) {
        case 's':
          b.write(' ' * (int.tryParse(n.getAttribute('text:c') ?? '') ?? 1));
          return;
        case 'tab' || 'line-break':
          b.write(' ');
          return;
        case 'note':
          return;
      }
    }
    n.children.forEach(walk);
  }

  walk(n);
  return b.toString();
}

ImportedBook _importOdt(List<int> bytes, String fallbackTitle) {
  final arc = ZipDecoder().decodeBytes(bytes);
  final f = arc.files.where((f) => f.name == 'content.xml').firstOrNull;
  if (f == null) throw ImportException(L('Geçersiz ODT dosyası.', 'Invalid ODT file.'));
  final doc = XmlDocument.parse(utf8.decode(f.content as List<int>));
  final chapters = <ImportedChapter>[];
  final images = <String, List<int>>{}, names = <String, String>{};
  var cur = ImportedChapter('', []);
  for (final e in doc.descendants.whereType<XmlElement>().where((e) => e.name.prefix == 'text' && (e.name.local == 'p' || e.name.local == 'h'))) {
    // Pictures anchored in this paragraph (not in a paragraph inside a frame of it).
    for (final img in e.descendants.whereType<XmlElement>().where((x) => x.name.prefix == 'draw' && x.name.local == 'image')) {
      final path = img.getAttribute('xlink:href');
      if (path == null || path.contains('://')) continue;
      final name = keepPicture(images, names, path, arc.files.where((f) => f.name == path).firstOrNull?.content as List<int>?);
      if (name != null) cur.paragraphs.add(('i', name));
    }
    final text = _clean(_odtText(e));
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
  return _chunk(ImportedBook(fallbackTitle, null, 'odt', chapters, images));
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
  // Pictures: <image l:href="#id"/> and <binary id="id">base64</binary>.
  final binaries = {
    for (final b in doc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'binary'))
      if (b.getAttribute('id') != null) b.getAttribute('id')!: b.innerText,
  };
  final images = <String, List<int>>{}, names = <String, String>{};
  String? fb2Picture(XmlElement e) {
    final href = e.attributes.where((a) => a.name.local == 'href').firstOrNull?.value;
    if (href == null || !href.startsWith('#')) return null;
    final data = binaries[href.substring(1)];
    if (data == null) return null;
    try {
      return keepPicture(images, names, href, base64.decode(data.replaceAll(RegExp(r'\s'), '')));
    } catch (_) {
      return null;
    }
  }

  // Sections can hold sections (parts with chapters): every section with its own
  // text becomes a chapter; the titles of the parts above it go first.
  final pending = <(String, String)>[];
  bool isSection(XmlElement e) => e.name.local == 'section';
  void visit(XmlElement s) {
    final t = s.childElements.where((e) => e.name.local == 'title').firstOrNull;
    final title = t == null ? '' : _clean(t.innerText);
    final paras = <(String, String)>[...pending];
    pending.clear();
    if (title.isNotEmpty) paras.add(('h', title));
    final subs = s.childElements.where(isSection).toList();
    for (final e in s.descendants.whereType<XmlElement>().where((e) => e.name.local == 'p' || e.name.local == 'v' || e.name.local == 'subtitle' || e.name.local == 'image')) {
      final up = e.ancestors.whereType<XmlElement>().takeWhile((a) => a != s);
      if (up.any((a) => a.name.local == 'title' || isSection(a))) continue;
      if (e.name.local == 'image') {
        final name = fb2Picture(e);
        if (name != null) paras.add(('i', name));
        continue;
      }
      final x = _clean(e.innerText);
      if (x.isNotEmpty) paras.add((e.name.local == 'subtitle' ? 'h' : 'p', x));
    }
    if (paras.any((p) => p.$1 == 'p') || subs.isEmpty) {
      if (paras.isNotEmpty) chapters.add(ImportedChapter(title, paras));
    } else {
      pending.addAll(paras);
    }
    subs.forEach(visit);
  }

  if (body != null) {
    final sections = body.childElements.where(isSection).toList();
    if (sections.isEmpty) {
      visit(body);
    } else {
      sections.forEach(visit);
    }
  }
  return _chunk(ImportedBook(title?.isNotEmpty == true ? title! : fallbackTitle, author, 'fb2', chapters, images));
}

/// Plain text of an RTF document: paragraphs separated by blank lines, the
/// font, colour and style tables, pictures, headers, footers and other
/// hidden groups left out.
String _rtfToText(String rtf) {
  const hidden = {
    'fonttbl', 'colortbl', 'stylesheet', 'info', 'pict', 'header', 'headerl', 'headerr', 'headerf', 'footer',
    'footerl', 'footerr', 'footerf', 'listtable', 'listoverridetable', 'rsidtbl', 'generator', 'xmlnstbl',
    'themedata', 'colorschememapping', 'latentstyles', 'datastore', 'object', 'fldinst', 'filetbl', 'revtbl',
  };
  final out = StringBuffer();
  // For every open group: whether its text is hidden.
  final stack = <bool>[false];
  var i = 0;
  var uc = 1; // characters to skip after \uN
  var skip = 0;
  while (i < rtf.length) {
    final c = rtf[i];
    if (c == '{') {
      stack.add(stack.last);
      i++;
      // {\*\dest ...} and known destinations are hidden.
      final m = RegExp(r'\\(\*\\)?([a-zA-Z]+)').matchAsPrefix(rtf, i);
      if (m != null && (m.group(1) != null || hidden.contains(m.group(2)))) stack[stack.length - 1] = true;
      continue;
    }
    if (c == '}') {
      if (stack.length > 1) stack.removeLast();
      i++;
      continue;
    }
    if (c == '\\') {
      final m = RegExp(r"\\([a-zA-Z]+)(-?\d+)? ?|\\'([0-9a-fA-F]{2})|\\([^a-zA-Z])").matchAsPrefix(rtf, i);
      if (m == null) {
        i++;
        continue;
      }
      i = m.end;
      String? emit;
      if (m.group(3) != null) {
        emit = String.fromCharCode(int.parse(m.group(3)!, radix: 16));
      } else if (m.group(4) != null) {
        final sym = m.group(4)!;
        emit = sym == '~' ? ' ' : (sym == '\\' || sym == '{' || sym == '}') ? sym : sym == '\n' || sym == '\r' ? '\n\n' : null;
      } else {
        final word = m.group(1)!;
        final arg = m.group(2) == null ? null : int.parse(m.group(2)!);
        switch (word) {
          case 'par' || 'sect' || 'page':
            emit = '\n\n';
          case 'line' || 'tab':
            emit = ' ';
          case 'uc':
            uc = arg ?? 1;
          case 'u':
            var code = arg ?? 0;
            if (code < 0) code += 65536;
            emit = String.fromCharCode(code);
            skip = uc;
          case 'emdash':
            emit = '—';
          case 'endash':
            emit = '–';
          case 'lquote':
            emit = '‘';
          case 'rquote':
            emit = '’';
          case 'ldblquote':
            emit = '“';
          case 'rdblquote':
            emit = '”';
          case 'bullet':
            emit = '•';
        }
      }
      if (emit != null && !stack.last) out.write(emit);
      continue;
    }
    i++;
    if (c == '\n' || c == '\r') continue;
    if (skip > 0) {
      skip--;
      continue;
    }
    if (!stack.last) out.write(c);
  }
  return out.toString();
}

