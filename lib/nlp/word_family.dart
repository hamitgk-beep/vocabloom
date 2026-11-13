import 'dart:convert';

import '../l10n.dart';
import '../data/dict_db.dart';

/// One member of a word family (create, creation, creative, uncreative ...).
class FamilyEntry {
  final String word;
  final String pos; // n, v, a, r
  final String? tr;

  /// How the affix changes the meaning, e.g. "-ation: eylemin kendisi ya da sonucu (isim yapar)".
  final String? affixNote;
  final String? affixNoteEn;
  final bool negative;
  const FamilyEntry(this.word, this.pos, {this.tr, this.affixNote, this.affixNoteEn, this.negative = false});

  /// The affix note in the interface language.
  String? get note => uiEnglish ? affixNoteEn ?? affixNote : affixNote;

  Map<String, dynamic> toJson() => {'w': word, 'p': pos, 't': tr, 'a': affixNote, 'ae': affixNoteEn, 'n': negative};
  factory FamilyEntry.fromJson(Map<String, dynamic> j) => FamilyEntry('${j['w']}', '${j['p']}',
      tr: j['t'] as String?, affixNote: j['a'] as String?, affixNoteEn: j['ae'] as String?, negative: j['n'] == true);
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
const _suffixes = <(String, String, String, String?)>[
  // (suffix, explanation, only for this part of speech)
  ('ation', 'eylemin kendisi ya da sonucu (isim yapar)', 'the action itself or its result (makes a noun)', 'n'),
  ('ition', 'eylemin kendisi ya da sonucu (isim yapar)', 'the action itself or its result (makes a noun)', 'n'),
  ('tion', 'eylemin kendisi ya da sonucu (isim yapar)', 'the action itself or its result (makes a noun)', 'n'),
  ('sion', 'eylemin kendisi ya da sonucu (isim yapar)', 'the action itself or its result (makes a noun)', 'n'),
  ('ion', 'eylemin kendisi ya da sonucu (isim yapar)', 'the action itself or its result (makes a noun)', 'n'),
  ('ment', 'eylem ya da onun sonucu (isim yapar)', 'an action or its result (makes a noun)', 'n'),
  ('ness', 'durum ya da nitelik, Türkçedeki -lık/-lik gibi (isim yapar)', 'a state or quality, like -ness (makes a noun)', 'n'),
  ('ity', 'nitelik, Türkçedeki -lık/-lik gibi (isim yapar)', 'a quality (makes a noun)', 'n'),
  ('ancy', 'durum (isim yapar)', 'a state (makes a noun)', 'n'),
  ('ency', 'durum (isim yapar)', 'a state (makes a noun)', 'n'),
  ('ance', 'eylem ya da durum (isim yapar)', 'an action or state (makes a noun)', 'n'),
  ('ence', 'eylem ya da durum (isim yapar)', 'an action or state (makes a noun)', 'n'),
  ('ship', 'durum, ilişki ya da beceri (isim yapar)', 'a state, relationship or skill (makes a noun)', 'n'),
  ('hood', 'dönem ya da durum, ör. childhood: çocukluk (isim yapar)', 'a period or state, e.g. childhood (makes a noun)', 'n'),
  ('dom', 'durum ya da alan, ör. freedom: özgürlük (isim yapar)', 'a state or domain, e.g. freedom (makes a noun)', 'n'),
  ('ism', 'akım, inanç ya da sistem, -cılık (isim yapar)', 'a movement, belief or system (makes a noun)', 'n'),
  ('ist', 'uzman ya da taraftar kişi, -cı (isim yapar)', 'an expert or supporter (makes a noun)', 'n'),
  ('ure', 'eylemin sonucu (isim yapar)', 'the result of an action (makes a noun)', 'n'),
  ('ee', 'işten etkilenen kişi, ör. employee: çalışan (isim yapar)', 'the person affected by the action, e.g. employee (makes a noun)', 'n'),
  ('al', 'eylemin kendisi, ör. arrival: varış (isim yapar)', 'the action itself, e.g. arrival (makes a noun)', 'n'),
  ('er', 'işi yapan kişi ya da araç, Türkçedeki -cı/-ci gibi (isim yapar)', 'the person or tool that does the action (makes a noun)', 'n'),
  ('or', 'işi yapan kişi ya da araç, Türkçedeki -cı/-ci gibi (isim yapar)', 'the person or tool that does the action (makes a noun)', 'n'),
  ('ar', 'işi yapan kişi (isim yapar)', 'the person who does the action (makes a noun)', 'n'),
  ('ant', 'işi yapan kişi ya da madde (isim yapar)', 'the person or substance that does the action (makes a noun)', 'n'),
  ('ent', 'işi yapan kişi ya da madde (isim yapar)', 'the person or substance that does the action (makes a noun)', 'n'),
  ('ing', 'eylemin kendisi (isim yapar)', 'the action itself (makes a noun)', 'n'),
  ('ative', 'o özelliğe sahip (sıfat yapar)', 'having that quality (makes an adjective)', 'a'),
  ('ive', 'o özelliğe sahip (sıfat yapar)', 'having that quality (makes an adjective)', 'a'),
  ('able', 'yapılabilir, -ebilir/-abilir (sıfat yapar)', 'can be done (makes an adjective)', 'a'),
  ('ible', 'yapılabilir, -ebilir/-abilir (sıfat yapar)', 'can be done (makes an adjective)', 'a'),
  ('ful', 'o şeyle dolu, Türkçedeki -lı/-li gibi (sıfat yapar)', 'full of that thing (makes an adjective)', 'a'),
  ('less', 'o şey olmadan, Türkçedeki -sız/-siz gibi (sıfat yapar)', 'without that thing (makes an adjective)', 'a'),
  ('ious', 'o niteliğe sahip (sıfat yapar)', 'having that quality (makes an adjective)', 'a'),
  ('ous', 'o niteliğe sahip (sıfat yapar)', 'having that quality (makes an adjective)', 'a'),
  ('ical', 'ile ilgili (sıfat yapar)', 'related to (makes an adjective)', 'a'),
  ('ic', 'ile ilgili (sıfat yapar)', 'related to (makes an adjective)', 'a'),
  ('al', 'ile ilgili, -sal/-sel (sıfat yapar)', 'related to (makes an adjective)', 'a'),
  ('ish', 'biraz, -ımsı/-imsi (sıfat yapar)', 'somewhat, -ish (makes an adjective)', 'a'),
  ('ant', 'o durumda olan (sıfat yapar)', 'being in that state (makes an adjective)', 'a'),
  ('ent', 'o durumda olan (sıfat yapar)', 'being in that state (makes an adjective)', 'a'),
  ('ed', 'o duruma gelmiş, ör. bored: sıkılmış (sıfat yapar)', 'having reached that state, e.g. bored (makes an adjective)', 'a'),
  ('ing', 'o etkiyi yaratan, ör. boring: sıkıcı (sıfat yapar)', 'causing that effect, e.g. boring (makes an adjective)', 'a'),
  ('y', 'o özelliği taşıyan, ör. rainy: yağmurlu (sıfat yapar)', 'having that feature, e.g. rainy (makes an adjective)', 'a'),
  ('ly', 'işin nasıl yapıldığını anlatır, Türkçedeki -ca/-ce, "bir şekilde" (zarf yapar)', 'tells how something is done (makes an adverb)', 'r'),
  ('ize', 'o hale getirmek (fiil yapar)', 'to make something that way (makes a verb)', 'v'),
  ('ise', 'o hale getirmek (fiil yapar)', 'to make something that way (makes a verb)', 'v'),
  ('ify', 'o hale getirmek (fiil yapar)', 'to make something that way (makes a verb)', 'v'),
  ('ate', 'o işi yapmak (fiil yapar)', 'to do that action (makes a verb)', 'v'),
  ('en', 'o hale getirmek, ör. widen: genişletmek (fiil yapar)', 'to make something that way, e.g. widen (makes a verb)', 'v'),
];

const _prefixes = <(String, String, String)>[
  ('non', 'olmayan, -sız (olumsuz yapar)', 'not, without (makes a negative)'),
  ('dis', 'zıt ya da ters anlam (olumsuz yapar)', 'the opposite or reverse meaning (makes a negative)'),
  ('un', 'zıt anlam, Türkçedeki -sız/-mayan gibi (olumsuz yapar)', 'the opposite meaning (makes a negative)'),
  ('in', 'zıt anlam, Türkçedeki -sız/-mayan gibi (olumsuz yapar)', 'the opposite meaning (makes a negative)'),
  ('im', 'zıt anlam (p/b/m ile başlayan kelimelerde in- yerine)', 'the opposite meaning (used instead of in- before p/b/m)'),
  ('il', 'zıt anlam (l ile başlayan kelimelerde in- yerine)', 'the opposite meaning (used instead of in- before l)'),
  ('ir', 'zıt anlam (r ile başlayan kelimelerde in- yerine)', 'the opposite meaning (used instead of in- before r)'),
];

/// "-ation: eylemin kendisi ya da sonucu (isim yapar)" for [word] built from [base].
String? explainSuffix(String base, String word, String pos) {
  if (word == base) return null;
  var l = 0;
  while (l < base.length && l < word.length && base[l] == word[l]) {
    l++;
  }
  if (l < 3 || l < base.length - 3) return null;
  for (final (suf, noteTr, noteEn, p) in _suffixes) {
    final note = uiEnglish ? noteEn : noteTr;
    if (p != null && p != pos) continue;
    if (word.endsWith(suf) && word.length - suf.length >= l - 2 && suf.length <= word.length - l + 3) {
      return '-$suf: $note';
    }
  }
  return null;
}

String? explainPrefix(String base, String word) {
  for (final (pre, noteTr, noteEn) in _prefixes) {
    final note = uiEnglish ? noteEn : noteTr;
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
          affixNote: explainPrefix(n[2] as String, n[0] as String) ?? L('zıt anlam: ${n[2]}', 'opposite of: ${n[2]}'),
          negative: true),
  ]);
}
