import 'dart:convert';

import '../data/dict_db.dart';

/// One member of a word family (create, creation, creative, uncreative ...).
class FamilyEntry {
  final String word;
  final String pos; // n, v, a, r
  final String? tr;

  /// How the affix changes the meaning, e.g. "-ation: eylemin kendisi ya da sonucu (isim yapar)".
  final String? affixNote;
  final bool negative;
  const FamilyEntry(this.word, this.pos, {this.tr, this.affixNote, this.negative = false});

  Map<String, dynamic> toJson() => {'w': word, 'p': pos, 't': tr, 'a': affixNote, 'n': negative};
  factory FamilyEntry.fromJson(Map<String, dynamic> j) =>
      FamilyEntry('${j['w']}', '${j['p']}', tr: j['t'] as String?, affixNote: j['a'] as String?, negative: j['n'] == true);
}

class WordFamily {
  final String root;
  final String? rootTr;
  final List<FamilyEntry> entries;
  final bool fromAi;
  const WordFamily(this.root, this.rootTr, this.entries, {this.fromAi = false});

  List<FamilyEntry> byPos(String pos) => entries.where((e) => e.pos == pos && !e.negative).toList();
  List<FamilyEntry> get negatives => entries.where((e) => e.negative).toList();

  String toJsonString() => jsonEncode({'root': root, 'rootTr': rootTr, 'entries': [for (final e in entries) e.toJson()]});
  static WordFamily fromJsonString(String s, {bool fromAi = false}) {
    final j = jsonDecode(s) as Map<String, dynamic>;
    return WordFamily('${j['root']}', j['rootTr'] as String?,
        [for (final e in (j['entries'] as List)) FamilyEntry.fromJson((e as Map).cast<String, dynamic>())],
        fromAi: fromAi);
  }
}

// Suffix -> what it does, in Turkish. Longest suffixes first.
const _suffixes = <(String, String, String?)>[
  // (suffix, explanation, only for this part of speech)
  ('ation', 'eylemin kendisi ya da sonucu (isim yapar)', 'n'),
  ('ition', 'eylemin kendisi ya da sonucu (isim yapar)', 'n'),
  ('tion', 'eylemin kendisi ya da sonucu (isim yapar)', 'n'),
  ('sion', 'eylemin kendisi ya da sonucu (isim yapar)', 'n'),
  ('ion', 'eylemin kendisi ya da sonucu (isim yapar)', 'n'),
  ('ment', 'eylem ya da onun sonucu (isim yapar)', 'n'),
  ('ness', 'durum ya da nitelik, Türkçedeki -lık/-lik gibi (isim yapar)', 'n'),
  ('ity', 'nitelik, Türkçedeki -lık/-lik gibi (isim yapar)', 'n'),
  ('ancy', 'durum (isim yapar)', 'n'),
  ('ency', 'durum (isim yapar)', 'n'),
  ('ance', 'eylem ya da durum (isim yapar)', 'n'),
  ('ence', 'eylem ya da durum (isim yapar)', 'n'),
  ('ship', 'durum, ilişki ya da beceri (isim yapar)', 'n'),
  ('hood', 'dönem ya da durum, ör. childhood: çocukluk (isim yapar)', 'n'),
  ('dom', 'durum ya da alan, ör. freedom: özgürlük (isim yapar)', 'n'),
  ('ism', 'akım, inanç ya da sistem, -cılık (isim yapar)', 'n'),
  ('ist', 'uzman ya da taraftar kişi, -cı (isim yapar)', 'n'),
  ('ure', 'eylemin sonucu (isim yapar)', 'n'),
  ('ee', 'işten etkilenen kişi, ör. employee: çalışan (isim yapar)', 'n'),
  ('al', 'eylemin kendisi, ör. arrival: varış (isim yapar)', 'n'),
  ('er', 'işi yapan kişi ya da araç, Türkçedeki -cı/-ci gibi (isim yapar)', 'n'),
  ('or', 'işi yapan kişi ya da araç, Türkçedeki -cı/-ci gibi (isim yapar)', 'n'),
  ('ar', 'işi yapan kişi (isim yapar)', 'n'),
  ('ant', 'işi yapan kişi ya da madde (isim yapar)', 'n'),
  ('ent', 'işi yapan kişi ya da madde (isim yapar)', 'n'),
  ('ing', 'eylemin kendisi (isim yapar)', 'n'),
  ('ative', 'o özelliğe sahip (sıfat yapar)', 'a'),
  ('ive', 'o özelliğe sahip (sıfat yapar)', 'a'),
  ('able', 'yapılabilir, -ebilir/-abilir (sıfat yapar)', 'a'),
  ('ible', 'yapılabilir, -ebilir/-abilir (sıfat yapar)', 'a'),
  ('ful', 'o şeyle dolu, Türkçedeki -lı/-li gibi (sıfat yapar)', 'a'),
  ('less', 'o şey olmadan, Türkçedeki -sız/-siz gibi (sıfat yapar)', 'a'),
  ('ious', 'o niteliğe sahip (sıfat yapar)', 'a'),
  ('ous', 'o niteliğe sahip (sıfat yapar)', 'a'),
  ('ical', 'ile ilgili (sıfat yapar)', 'a'),
  ('ic', 'ile ilgili (sıfat yapar)', 'a'),
  ('al', 'ile ilgili, -sal/-sel (sıfat yapar)', 'a'),
  ('ish', 'biraz, -ımsı/-imsi (sıfat yapar)', 'a'),
  ('ant', 'o durumda olan (sıfat yapar)', 'a'),
  ('ent', 'o durumda olan (sıfat yapar)', 'a'),
  ('ed', 'o duruma gelmiş, ör. bored: sıkılmış (sıfat yapar)', 'a'),
  ('ing', 'o etkiyi yaratan, ör. boring: sıkıcı (sıfat yapar)', 'a'),
  ('y', 'o özelliği taşıyan, ör. rainy: yağmurlu (sıfat yapar)', 'a'),
  ('ly', 'işin nasıl yapıldığını anlatır, Türkçedeki -ca/-ce, "bir şekilde" (zarf yapar)', 'r'),
  ('ize', 'o hale getirmek (fiil yapar)', 'v'),
  ('ise', 'o hale getirmek (fiil yapar)', 'v'),
  ('ify', 'o hale getirmek (fiil yapar)', 'v'),
  ('ate', 'o işi yapmak (fiil yapar)', 'v'),
  ('en', 'o hale getirmek, ör. widen: genişletmek (fiil yapar)', 'v'),
];

const _prefixes = <(String, String)>[
  ('non', 'olmayan, -sız (olumsuz yapar)'),
  ('dis', 'zıt ya da ters anlam (olumsuz yapar)'),
  ('un', 'zıt anlam, Türkçedeki -sız/-mayan gibi (olumsuz yapar)'),
  ('in', 'zıt anlam, Türkçedeki -sız/-mayan gibi (olumsuz yapar)'),
  ('im', 'zıt anlam (p/b/m ile başlayan kelimelerde in- yerine)'),
  ('il', 'zıt anlam (l ile başlayan kelimelerde in- yerine)'),
  ('ir', 'zıt anlam (r ile başlayan kelimelerde in- yerine)'),
];

/// "-ation: eylemin kendisi ya da sonucu (isim yapar)" for [word] built from [base].
String? explainSuffix(String base, String word, String pos) {
  if (word == base) return null;
  var l = 0;
  while (l < base.length && l < word.length && base[l] == word[l]) {
    l++;
  }
  if (l < 3 || l < base.length - 3) return null;
  for (final (suf, note, p) in _suffixes) {
    if (p != null && p != pos) continue;
    if (word.endsWith(suf) && word.length - suf.length >= l - 2 && suf.length <= word.length - l + 3) {
      return '-$suf: $note';
    }
  }
  return null;
}

String? explainPrefix(String base, String word) {
  for (final (pre, note) in _prefixes) {
    if (word == '$pre$base') return '$pre-: $note';
  }
  return null;
}

/// Turkish meaning of [lemma] as part of speech [pos].
String? trFor(DictDb dict, String lemma, String pos) {
  final info = dict.lookup(lemma);
  for (final s in info.senses) {
    if ((s.pos == pos || (pos == 'a' && s.pos == 's')) && s.tr.isNotEmpty) return s.tr.take(2).join(', ');
  }
  if (info.trFreeDict.isNotEmpty) return info.trFreeDict.first;
  return null;
}

/// Family from the bundled dictionary (WordNet derivations), or null.
WordFamily? offlineFamily(DictDb dict, String lemma) {
  final List<Map<String, Object?>> r;
  try {
    r = dict.db.select('SELECT g.root, g.members, g.negs FROM fam f JOIN famg g ON g.id=f.gid WHERE f.word=?', [lemma]).toList();
  } catch (_) {
    return null; // older dictionary without families
  }
  if (r.isEmpty) return null;
  final root = r.first['root'] as String;
  final members = (jsonDecode(r.first['members'] as String) as List).cast<List>();
  final negs = (jsonDecode(r.first['negs'] as String) as List).cast<List>();
  final rootPos = members.firstWhere((m) => m[0] == root, orElse: () => members.first)[1] as String;
  String? baseNote(String w, String p) {
    // Explain against the closest shorter member (creatively <- creative).
    final cands = members.map((m) => m[0] as String).where((b) => b != w && w.startsWith(b.substring(0, (b.length - 2).clamp(3, b.length)))).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final b in cands.where((b) => b.length < w.length)) {
      final n = explainSuffix(b, w, p);
      if (n != null) return b == root ? n : '$b + $n';
    }
    return explainSuffix(root, w, p);
  }

  return WordFamily(root, trFor(dict, root, rootPos), [
    for (final m in members)
      FamilyEntry(m[0] as String, m[1] as String,
          tr: trFor(dict, m[0] as String, m[1] as String), affixNote: baseNote(m[0] as String, m[1] as String)),
    for (final n in negs)
      FamilyEntry(n[0] as String, n[1] as String,
          tr: trFor(dict, n[0] as String, n[1] as String),
          affixNote: explainPrefix(n[2] as String, n[0] as String) ?? 'zıt anlam: ${n[2]}',
          negative: true),
  ]);
}
