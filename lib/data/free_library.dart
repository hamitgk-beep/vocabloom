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

  /// Language of the text: 'en' or 'tr'.
  final String lang;
  final String? author;
  final int words;
  final int? chapters, size;

  /// How many pictures the text has, and their size in bytes (books only).
  final int pics;
  final int? picsSize;
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
    this.pics = 0,
    this.picsSize,
    this.lang = 'en',
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
        pics: j['pics'] as int? ?? 0,
        picsSize: j['picsSize'] as int?,
        lang: j['lang'] as String? ?? 'en',
      );
}

class FreeLibrary {
  final List<LibraryItem> items;
  final Map<String, String> _stories;
  FreeLibrary(this.items, this._stories);

  static FreeLibrary? _cached;

  /// Tests set this to read books from library/books instead of downloading.
  static Future<String> Function(LibraryItem it)? debugBookText;

  static Future<FreeLibrary>? _loading;

  /// Tests set this to stand in for the app's bundled files.
  static AssetBundle? debugBundle;

  /// What went wrong while loading, one line per file; empty when all loaded.
  final List<String> problems = [];

  /// The catalog and the bundled stories. One broken or missing file never
  /// hides the rest: the English and the Turkish texts load on their own.
  /// Throws only when nothing at all could be read, and then the next call
  /// tries again.
  /// Forgets the loaded library (tests).
  static void debugReset() => _cached = null;

  static Future<FreeLibrary> load() {
    if (_cached != null) return Future.value(_cached!);
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  static Future<FreeLibrary> _load() async {
    final bundle = debugBundle ?? rootBundle;
    final items = <LibraryItem>[];
    final stories = <String, String>{};
    final problems = <String>[];
    // Read as bytes and decoded here: rootBundle.loadString hands big files
    // to a background isolate, and a library that waits on that forever only
    // shows a spinner.
    Future<List<int>> bytes(String key) async =>
        (await bundle.load(key).timeout(const Duration(seconds: 20))).buffer.asUint8List();
    // English, then Turkish (tools/library_tr/build_library_tr.py).
    for (final (cat, texts) in [
      ('assets/library/catalog.json', 'assets/library/stories.json.gz'),
      ('assets/library/catalog_tr.json', 'assets/library/stories_tr.json.gz'),
    ]) {
      final found = <LibraryItem>[];
      try {
        final list = jsonDecode(utf8.decode(await bytes(cat), allowMalformed: true)) as List;
        var bad = 0;
        for (final j in list) {
          try {
            found.add(LibraryItem.fromJson((j as Map).cast<String, dynamic>()));
          } catch (_) {
            bad++;
          }
        }
        if (bad > 0) problems.add('$cat: $bad entries skipped');
      } catch (e) {
        problems.add('$cat: $e');
        continue;
      }
      try {
        final text = utf8.decode(gzip.decode(await bytes(texts)), allowMalformed: true);
        (jsonDecode(text) as Map).forEach((k, v) {
          if (k is String && v is String) stories[k] = v;
        });
      } catch (e) {
        problems.add('$texts: $e');
      }
      // A story without its text cannot open: show only what can.
      items.addAll(found.where((it) => it.isBook || stories.containsKey(it.id)));
    }
    if (items.isEmpty) throw StateError(problems.join('\n'));
    return _cached = FreeLibrary(items, stories)..problems.addAll(problems);
  }

  /// Tests set this to read pictures from local copies instead of downloading.
  static Future<List<int>?> Function(String address)? debugPicture;

  /// Where a picture of a library text is: `pb:` the Pratham Books image bank
  /// (the stories' own illustrations, CC BY 4.0), `lib:` this app's copies of
  /// a Gutenberg book's illustrations.
  static String pictureUrl(String address) {
    if (address.startsWith('pb:')) return 'https://raw.githubusercontent.com/global-asp/pb-imagebank/master/medium/${address.substring(3)}';
    if (address.startsWith('lib:')) return 'https://raw.githubusercontent.com/hamitgk-beep/vocabloom/main/library/images/${address.substring(4)}';
    return address;
  }

  /// The item's text as the app's book shape, with its pictures. Books are
  /// downloaded the first time; pictures always are (a picture that does not
  /// come is left out). [onProgress] gets 0..1 while that runs.
  Future<ImportedBook> fetch(LibraryItem it, {void Function(double? p)? onProgress}) async {
    String md;
    final addresses = <String>[];
    final textShare = it.isBook && it.pics > 0 ? 0.2 : 1.0;
    if (it.isBook && debugBookText != null) {
      md = await debugBookText!(it);
    } else if (it.isBook) {
      final tmp = await Directory.systemTemp.createTemp('vocabloom_lib_');
      try {
        final f = File(p.join(tmp.path, '${it.id}.md.gz'));
        await fetchFile(it.url, f, onProgress: (x) => onProgress?.call(x == null ? null : x * textShare), expectedSize: it.size);
        md = utf8.decode(gzip.decode(await f.readAsBytes()));
      } finally {
        tmp.delete(recursive: true).ignore();
      }
    } else {
      md = _stories[it.id] ?? (throw StateError('missing story ${it.id}'));
      // CC BY: name the authors and the illustrators.
      md = '$md\n\n— ${it.credit}${it.license == 'Storilex' ? '' : ' ${it.license}'}.\n';
    }
    addresses.addAll(libraryPictures(md));
    final pictures = await _pictures(addresses, (done) {
      final start = it.isBook ? textShare : 0.0;
      onProgress?.call(start + (1 - start) * done);
    });
    return importLibraryMarkdown(md, it.title, it.author, it.level, pictures: pictures);
  }

  /// Downloads [addresses] four at a time; [onProgress] gets 0..1.
  static Future<Map<String, List<int>>> _pictures(List<String> addresses, void Function(double done) onProgress) async {
    final out = <String, List<int>>{};
    if (addresses.isEmpty) return out;
    final tmp = await Directory.systemTemp.createTemp('vocabloom_pics_');
    var next = 0, done = 0;
    Future<void> worker() async {
      while (next < addresses.length) {
        final k = next++;
        final a = addresses[k];
        try {
          if (debugPicture != null) {
            final b = await debugPicture!(a);
            if (b != null) out[a] = b;
          } else {
            final f = File(p.join(tmp.path, '$k'));
            await fetchFile(pictureUrl(a), f);
            out[a] = await f.readAsBytes();
          }
        } catch (_) {
          // The text is still worth reading without this picture.
        }
        onProgress(++done / addresses.length);
      }
    }

    try {
      await Future.wait([for (var i = 0; i < 4; i++) worker()]);
    } finally {
      tmp.delete(recursive: true).ignore();
    }
    return out;
  }
}

/// Adds [it] to the user's library (or finds it there) and returns its book.
Future<Book> addLibraryItem(UserDb db, FreeLibrary lib, LibraryItem it, {void Function(double? p)? onProgress}) async {
  final have = db.booksBySource()[it.id];
  if (have != null) return have;
  final book = await lib.fetch(it, onProgress: onProgress);
  final id = db.insertBook(book, source: it.id, lang: it.lang);
  return db.books(lang: it.lang).firstWhere((b) => b.id == id);
}

/// Whether [it] was added before the library had its pictures: the book in
/// the user's library has none, but the library's text has some.
bool lacksPictures(UserDb db, LibraryItem it) {
  final have = db.booksBySource()[it.id];
  return have != null && it.pics > 0 && db.pictureCount(have.id) == 0;
}

/// Puts the library's new edition of [it] (with its pictures) in place of the
/// one the user added before, at the same chapter when it still has it.
Future<Book> replaceLibraryItem(UserDb db, FreeLibrary lib, LibraryItem it, {void Function(double? p)? onProgress}) async {
  final old = db.booksBySource()[it.id];
  final book = await lib.fetch(it, onProgress: onProgress);
  final id = db.insertBook(book, source: it.id, lang: it.lang);
  if (old != null) {
    if (old.lastChapter > 0 && old.lastChapter < book.chapters.length) db.saveProgress(id, old.lastChapter, 0);
    db.deleteBook(old.id);
  }
  return db.books(lang: it.lang).firstWhere((b) => b.id == id);
}
