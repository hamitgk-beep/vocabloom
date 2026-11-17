import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../import/importers.dart';
import '../online/native_fetch.dart';
import 'user_db.dart';

/// The free reading library: short stories (bundled with the app) and
/// public-domain classics (downloaded when first opened), grouped by CEFR level.
/// Made by tools/library/build_library.py; see that file for the sources.
const libraryLevels = ['A1', 'A2', 'B1', 'B2', 'C1'];

class LibraryItem {
  final String id, kind, title, level, license, credit, source;
  final String? author;
  final int words;
  final int? chapters, size;
  LibraryItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.level,
    required this.license,
    required this.credit,
    required this.source,
    required this.author,
    required this.words,
    this.chapters,
    this.size,
  });

  bool get isBook => kind == 'book';

  /// Reading time at a learner's ~120 words a minute.
  int get minutes => (words / 120).ceil();

  String get url => 'https://raw.githubusercontent.com/hamitgk-beep/vocabloom/main/library/books/$id.md.gz';

  factory LibraryItem.fromJson(Map<String, dynamic> j) => LibraryItem(
        id: j['id'] as String,
        kind: j['kind'] as String,
        title: j['title'] as String,
        level: j['level'] as String,
        license: j['license'] as String,
        credit: j['credit'] as String,
        source: j['source'] as String,
        author: j['author'] as String?,
        words: j['words'] as int,
        chapters: j['chapters'] as int?,
        size: j['size'] as int?,
      );
}

class FreeLibrary {
  final List<LibraryItem> items;
  final Map<String, String> _stories;
  FreeLibrary(this.items, this._stories);

  static FreeLibrary? _cached;

  /// Tests set this to read books from library/books instead of downloading.
  static Future<String> Function(LibraryItem it)? debugBookText;

  static Future<FreeLibrary> load() async {
    if (_cached != null) return _cached!;
    final cat = jsonDecode(await rootBundle.loadString('assets/library/catalog.json')) as List;
    final gz = await rootBundle.load('assets/library/stories.json.gz');
    final stories = (jsonDecode(utf8.decode(gzip.decode(gz.buffer.asUint8List()))) as Map).cast<String, String>();
    return _cached = FreeLibrary([for (final j in cat) LibraryItem.fromJson(j as Map<String, dynamic>)], stories);
  }

  /// The item's text as the app's book shape. Books are downloaded the first
  /// time; [onProgress] gets 0..1 while that runs.
  Future<ImportedBook> fetch(LibraryItem it, {void Function(double? p)? onProgress}) async {
    String md;
    if (it.isBook && debugBookText != null) {
      md = await debugBookText!(it);
    } else if (it.isBook) {
      final tmp = await Directory.systemTemp.createTemp('vocabloom_lib_');
      try {
        final f = File(p.join(tmp.path, '${it.id}.md.gz'));
        await fetchFile(it.url, f, onProgress: onProgress, expectedSize: it.size);
        md = utf8.decode(gzip.decode(await f.readAsBytes()));
      } finally {
        tmp.delete(recursive: true).ignore();
      }
    } else {
      md = _stories[it.id] ?? (throw StateError('missing story ${it.id}'));
      // CC BY: name the authors and say what was changed.
      md = '$md\n\n— ${it.credit} ${it.license}. Text only; the illustrations are not included.\n';
    }
    return importLibraryMarkdown(md, it.title, it.author, it.level);
  }
}

/// Adds [it] to the user's library (or finds it there) and returns its book.
Future<Book> addLibraryItem(UserDb db, FreeLibrary lib, LibraryItem it, {void Function(double? p)? onProgress}) async {
  final have = db.booksBySource()[it.id];
  if (have != null) return have;
  final book = await lib.fetch(it, onProgress: onProgress);
  final id = db.insertBook(book, source: it.id);
  return db.books().firstWhere((b) => b.id == id);
}
