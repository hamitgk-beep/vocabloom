import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Turkish word -> English meanings, for English speakers who read Turkish
/// books. Built by tools/tr_en/build_tr_en.py from open data only:
/// Kaikki.org / English Wiktionary (CC BY-SA 4.0), FrequencyWords (CC BY-SA
/// 4.0, ranking only) and Tatoeba sentence pairs (CC BY 2.0 FR).
class TrEnDict {
  static const _version = '1';
  final Database db;
  TrEnDict(this.db);

  static Future<TrEnDict?> open(Directory dir) async {
    final file = File(p.join(dir.path, 'tr_en_v$_version.db'));
    for (final f in dir.listSync().whereType<File>()) {
      final n = p.basename(f.path);
      if (n.startsWith('tr_en_v') && n.endsWith('.db') && f.path != file.path) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
    try {
      if (!file.existsSync() || file.lengthSync() < 100000) {
        final data = await rootBundle.load('assets/tr_en.db');
        await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
      }
      return TrEnDict(sqlite3.open(file.path, mode: OpenMode.readOnly));
    } catch (_) {
      return null;
    }
  }

  /// Turkish lower case: "I" is "ı" and "İ" is "i".
  static String lower(String s) => s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase().replaceAll('̇', '').replaceAll('’', "'");

  bool _has(String w) => db.select('SELECT 1 FROM lemma WHERE word=?', [w]).isNotEmpty;

  /// Base words a tapped word can belong to, the most likely first:
  /// the word itself, then the dictionary's inflected forms (evlerimizden ->
  /// ev), then a few endings the tables do not list ("seninle", "Ankara'da").
  List<String> lemmas(String surface) {
    var w = lower(surface.trim());
    final apo = w.indexOf("'");
    if (apo > 0) w = w.substring(0, apo);
    List<String> direct(String t) {
      final out = <String>[];
      if (_has(t)) out.add(t);
      final rows = db.select('SELECT f.lemma FROM form f JOIN lemma l ON l.word = f.lemma WHERE f.form=? ORDER BY l.rank', [t]);
      for (final r in rows) {
        final l = r.columnAt(0) as String;
        if (!out.contains(l)) out.add(l);
      }
      return out;
    }

    final found = direct(w);
    if (found.isNotEmpty) return found;
    for (final end in _endings) {
      if (w.length > end.length + 1 && w.endsWith(end)) {
        final r = direct(w.substring(0, w.length - end.length));
        if (r.isNotEmpty) return r;
      }
    }
    // Verb forms the tables leave out ("olduğumu", "yaptığını", "alabilir"):
    // cut a verb ending and look for the infinitive (ol -> olmak).
    for (final end in _verbEndings) {
      if (w.length >= end.length + 2 && w.endsWith(end)) {
        var stem = w.substring(0, w.length - end.length);
        for (final st in {stem, if (stem.endsWith('d')) '${stem.substring(0, stem.length - 1)}t'}) {
          for (final inf in ['${st}mak', '${st}mek']) {
            if (_has(inf)) return [inf];
          }
        }
      }
    }
    return const [];
  }

  static final List<String> _verbEndings = () {
    final out = <String>{};
    const tails = ['', 'ı', 'i', 'u', 'ü', 'ını', 'ini', 'unu', 'ünü', 'ımı', 'imi', 'umu', 'ümü', 'ımızı', 'imizi', 'umuzu', 'ümüzü',
      'ında', 'inde', 'unda', 'ünde', 'ına', 'ine', 'una', 'üne', 'ından', 'inden', 'undan', 'ünden', 'ım', 'im', 'um', 'üm', 'ımız', 'imiz', 'umuz', 'ümüz'];
    for (final b in ['dığ', 'diğ', 'duğ', 'düğ', 'tığ', 'tiğ', 'tuğ', 'tüğ', 'acağ', 'eceğ', 'yacağ', 'yeceğ']) {
      for (final t in tails) {
        if (t.isNotEmpty) out.add('$b$t');
      }
    }
    for (final b in ['ma', 'me']) {
      for (final t in ['sı', 'si', 'sını', 'sini', 'sında', 'sinde', 'sına', 'sine', 'yı', 'yi', 'dan', 'den', 'k', 'z', 'm', 'n', 'nız', 'niz', 'mız', 'miz']) {
        out.add('$b$t');
      }
    }
    out.addAll([
      'abilir', 'ebilir', 'abilirim', 'ebilirim', 'abilirsin', 'ebilirsin', 'abiliriz', 'ebiliriz', 'abilirler', 'ebilirler', 'yabilir', 'yebilir',
      'acak', 'ecek', 'yacak', 'yecek', 'arak', 'erek', 'yarak', 'yerek', 'ınca', 'ince', 'unca', 'ünce', 'yınca', 'yince',
      'mış', 'miş', 'muş', 'müş', 'mıştı', 'mişti', 'muştu', 'müştü', 'dı', 'di', 'du', 'dü', 'tı', 'ti', 'tu', 'tü',
      'dım', 'dim', 'dum', 'düm', 'tım', 'tim', 'tum', 'tüm', 'dın', 'din', 'dun', 'dün', 'dık', 'dik', 'duk', 'dük', 'dılar', 'diler', 'dular', 'düler',
      'ıyor', 'iyor', 'uyor', 'üyor', 'yor', 'ıyorum', 'iyorum', 'uyorum', 'üyorum', 'yorum', 'ıyorsun', 'iyorsun', 'uyorsun', 'üyorsun', 'yorsun',
      'ıyordu', 'iyordu', 'uyordu', 'üyordu', 'yordu', 'ıyoruz', 'iyoruz', 'uyoruz', 'üyoruz', 'yoruz', 'ıyorlar', 'iyorlar', 'uyorlar', 'üyorlar', 'yorlar',
      'malı', 'meli', 'malıyım', 'meliyim', 'malısın', 'melisin', 'malıyız', 'meliyiz', 'sa', 'se', 'saydı', 'seydi', 'alım', 'elim', 'ayım', 'eyim',
    ]);
    final list = out.toList()..sort((a, b) => b.length.compareTo(a.length));
    return list;
  }();

  // Clitics and endings that are written on the word but are not in the
  // inflection tables, longest first.
  static const _endings = [
    'ndaki', 'ndeki', 'daki', 'deki', 'taki', 'teki', 'yla', 'yle', 'la', 'le', 'ki',
    'dır', 'dir', 'dur', 'dür', 'tır', 'tir', 'tur', 'tür', 'ydı', 'ydi', 'ydu', 'ydü', 'ysa', 'yse',
    'mı', 'mi', 'mu', 'mü',
  ];

  TrEntry? entry(String lemma) {
    final r = db.select('SELECT word, senses FROM lemma WHERE word=?', [lemma]);
    if (r.isEmpty) return null;
    final senses = [
      for (final s in jsonDecode(r.first['senses'] as String) as List)
        TrSense((s as Map)['p'] as String? ?? '', [for (final g in s['g'] as List) '$g']),
    ];
    final ex = [
      for (final e in db.select('SELECT tr, en, id FROM ex WHERE lemma=?', [lemma])) TrExample(e['tr'] as String, e['en'] as String, e['id'] as int?),
    ];
    return TrEntry(lemma, senses, ex);
  }

  /// Words that start with [prefix], most common first (dictionary search).
  List<String> search(String prefix, {int limit = 40}) {
    final w = lower(prefix.trim());
    if (w.isEmpty) return const [];
    return [
      for (final r in db.select("SELECT word FROM lemma WHERE word >= ? AND word < ? ORDER BY rank LIMIT ?", [w, '$w￿', limit])) r.columnAt(0) as String,
    ];
  }

  String meta(String key) {
    final r = db.select('SELECT value FROM meta WHERE key=?', [key]);
    return r.isEmpty ? '' : r.first.columnAt(0) as String;
  }
}

class TrSense {
  final String pos;
  final List<String> glosses;
  const TrSense(this.pos, this.glosses);
}

class TrExample {
  final String tr, en;
  final int? tatoebaId;
  const TrExample(this.tr, this.en, this.tatoebaId);
}

class TrEntry {
  final String lemma;
  final List<TrSense> senses;
  final List<TrExample> examples;
  const TrEntry(this.lemma, this.senses, this.examples);
}
