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

  /// One example sentence and its Turkish, when known.
  final String? exEn, exTr;
  const FamilyEntry(this.word, this.pos,
      {this.tr, this.affixNote, this.affixNoteEn, this.negative = false, this.exEn, this.exTr});

  /// The affix note in the interface language.
  String? get note => uiEnglish ? affixNoteEn ?? affixNote : affixNote;

  Map<String, dynamic> toJson() => {
        'w': word, 'p': pos, 't': tr, 'a': affixNote, 'ae': affixNoteEn, 'n': negative,
        if (exEn != null) 'x': exEn,
        if (exTr != null) 'xt': exTr,
      };
  factory FamilyEntry.fromJson(Map<String, dynamic> j) => FamilyEntry('${j['w']}', '${j['p']}',
      tr: j['t'] as String?, affixNote: j['a'] as String?, affixNoteEn: j['ae'] as String?, negative: j['n'] == true,
      exEn: j['x'] as String?, exTr: j['xt'] as String?);
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

/// The closest base of [word] among [bases] and the suffix that builds it,
/// allowing the usual spelling changes: differentiation <- differentiate + -ion,
/// differentiate <- different + -ate, difference <- differ + -ence,
/// happiness <- happy + -ness, ability <- able + -ity, stopper <- stop + -er.
(String, String)? derive(Iterable<String> bases, String word, String pos) {
  bool fits(String stem, String b) {
    if (stem == b || '${stem}e' == b || stem == '${b}i') return true;
    if (b.endsWith('y') && stem == '${b.substring(0, b.length - 1)}i') return true;
    if (b.endsWith('le') && stem == '${b.substring(0, b.length - 2)}il') return true;
    if (b.isNotEmpty && stem == b + b[b.length - 1]) return true; // stop -> stopp-er
    if (b.endsWith('e') && stem == '${b.substring(0, b.length - 1)}i') return true; // create -> creati-ve
    return false;
  }

  (String, String)? best;
  for (final strict in [true, false]) {
    for (final (suf, _, _, p) in _suffixes) {
      if (strict && p != null && p != pos) continue;
      if (!word.endsWith(suf) || word.length - suf.length < 2) continue;
      final stem = word.substring(0, word.length - suf.length);
      for (final b in bases) {
        if (b == word || b.length < 2) continue;
        if (fits(stem, b) && (best == null || b.length > best.$1.length)) best = (b, suf);
      }
    }
    if (best != null) return best;
  }
  return null;
}

String? _suffixNote(String suf, String pos) {
  for (final (s, noteTr, noteEn, p) in _suffixes) {
    if (s == suf && (p == null || p == pos)) return uiEnglish ? noteEn : noteTr;
  }
  for (final (s, noteTr, noteEn, _) in _suffixes) {
    if (s == suf) return uiEnglish ? noteEn : noteTr;
  }
  return null;
}

/// A rough Turkish meaning built from the base's meaning and the suffix, for
/// family members the dictionary does not list ("differentiator" ->
/// "≈ ayırdeden kişi ya da şey"). Marked with ≈.
String? derivedTr(String baseTr, String suf, String pos) {
  final first = baseTr.split(RegExp(r'[,;]')).first.replaceAll(RegExp(r'\([^)]*\)'), '').trim();
  if (first.isEmpty) return null;
  final verb = RegExp(r'(mak|mek)$').hasMatch(first);
  final stem = verb ? first.substring(0, first.length - 3) : first;
  final vowels = RegExp('[aıoueiöü]').allMatches(stem).toList();
  final back = vowels.isEmpty || 'aıou'.contains(vowels.last.group(0)!);
  final a = back ? 'a' : 'e';
  if (verb) {
    if (pos == 'n' && const {'er', 'or', 'ar', 'ant', 'ent', 'ist', 'ee'}.contains(suf)) return '≈ $stem${a}n kişi ya da şey';
    if (pos == 'n') return '≈ $stem${back ? 'ma' : 'me'}';
    if (pos == 'a' && (suf == 'able' || suf == 'ible')) return '≈ $stem${back ? 'abilir' : 'ebilir'}';
    if (pos == 'a') return '≈ $stem${a}n';
    return null;
  }
  if (pos == 'r' && suf == 'ly') return '≈ $first bir şekilde';
  if (pos == 'n' && const {'ness', 'ity', 'ence', 'ance', 'ency', 'ancy', 'hood', 'dom'}.contains(suf)) return '≈ $first olma durumu';
  if (pos == 'v') return '≈ $first hale getirmek';
  if (pos == 'a') return '≈ $first ile ilgili';
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

const _glossSkip = {'a', 'an', 'the', 'to', 'of', 'and', 'or', 'one', "one's", 'someone', 'something', 'somebody', 'be', 'is'};

// Short words whose first dictionary meaning is a rare one ("it" -> "ebe").
const _functionTr = {
  'it': 'o', 'he': 'o', 'she': 'o', 'they': 'onlar', 'we': 'biz', 'you': 'sen/siz', 'i': 'ben', 'me': 'beni',
  'him': 'onu', 'her': 'onu/onun', 'them': 'onları', 'us': 'bizi', 'his': 'onun', 'their': 'onların', 'its': 'onun',
  'this': 'bu', 'that': 'şu/o', 'these': 'bunlar', 'those': 'şunlar', 'about': 'hakkında', 'while': 'iken',
  'in': 'içinde', 'on': 'üstünde', 'at': '-de/-da', 'by': 'tarafından/yanında', 'for': 'için', 'with': 'ile',
  'from': '-den/-dan', 'into': 'içine', 'out': 'dışarı', 'up': 'yukarı', 'down': 'aşağı', 'off': 'uzak/kapalı',
  'over': 'üzerinde', 'under': 'altında', 'all': 'hepsi', 'no': 'hiç', 'not': 'değil', 'as': 'gibi/olarak',
  'so': 'öyle/bu yüzden', 'if': 'eğer', 'but': 'ama', 'than': '-den daha', 'then': 'sonra', 'now': 'şimdi',
  'there': 'orada', 'here': 'burada', 'when': 'ne zaman/-ince', 'what': 'ne', 'who': 'kim', 'how': 'nasıl',
  'why': 'neden', 'where': 'nerede', 'like': 'gibi', 'just': 'sadece', 'too': 'de/çok', 'very': 'çok',
  'more': 'daha', 'most': 'en', 'any': 'herhangi', 'some': 'biraz/bazı', 'have': 'sahip olmak', 'do': 'yapmak',
  'get': 'almak/olmak', 'go': 'gitmek', 'make': 'yapmak', 'take': 'almak', 'put': 'koymak', 'come': 'gelmek',
  'give': 'vermek', 'keep': 'tutmak', 'let': 'izin vermek', 'set': 'koymak/ayarlamak', 'back': 'geri',
  'away': 'uzağa', 'again': 'tekrar', 'once': 'bir kez', 'never': 'asla', 'ever': 'hiç', 'well': 'iyi',
};

/// Word-by-word Turkish of an expression the library has no Turkish for yet:
/// "above board" -> "above: yukarıda · board: tahta". Null when no word is known.
String? wordGloss(DictDb dict, String phrase) {
  final parts = <String>[];
  var known = 0;
  for (final w in phrase.toLowerCase().split(RegExp(r'\s+'))) {
    if (w.isEmpty || _glossSkip.contains(w)) continue;
    String? t = _functionTr[w];
    if (t != null) {
      known++;
      parts.add('$w: $t');
      continue;
    }
    for (final l in {w, ...dict.lemmatizer.lemmas(w)}) {
      final info = dict.lookup(l);
      final s = info.senses.where((s) => s.tr.isNotEmpty).firstOrNull;
      t = info.trFreeDict.isNotEmpty ? info.trFreeDict.first : s?.tr.first;
      if (t != null) break;
    }
    if (t != null) {
      t = t.replaceAll(RegExp(r'\([^)]*\)'), '').split(RegExp(r'[,;]')).first.trim();
      known++;
    }
    parts.add(t == null || t.isEmpty ? w : '$w: $t');
  }
  return known == 0 ? null : parts.join(' · ');
}

/// Turkish for a negative form the dictionary lacks, built from its base:
/// nonworker -> "işçi olmayan", disagree -> "tersi: katılmak".
String? negativeTr(DictDb dict, String base, String pos) {
  final t = trFor(dict, base, pos) ?? trFor(dict, base, 'n') ?? trFor(dict, base, 'a') ?? trFor(dict, base, 'v');
  if (t == null) return null;
  final first = t.split(RegExp(r'[,;]')).first.replaceAll(RegExp(r'\([^)]*\)'), '').trim();
  if (first.isEmpty) return null;
  return pos == 'v' ? 'tersi: $first' : '$first olmayan';
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
  final names = [for (final m in members) m[0] as String];
  final trOf = {for (final m in members) m[0] as String: trFor(dict, m[0] as String, m[1] as String)};
  (String, String)? baseOf(String w, String p) => w == root ? null : derive(names.where((b) => b.length < w.length + 2), w, p);
  String? baseNote(String w, String p) {
    final d = baseOf(w, p);
    if (d == null) return explainSuffix(root, w, p);
    final note = _suffixNote(d.$2, p);
    if (note == null) return null;
    return d.$1 == root ? '-${d.$2}: $note' : '${d.$1} + -${d.$2}: $note';
  }

  String? memberTr(String w, String p) {
    final t = trOf[w];
    if (t != null) return t;
    final d = baseOf(w, p);
    final bt = d == null ? null : trOf[d.$1];
    return bt == null ? null : derivedTr(bt, d!.$2, p);
  }

  (String?, String?) example(String w) {
    final e = dict.examples('w:$w', limit: 1);
    return e.isEmpty ? (null, null) : (e.first.$1, e.first.$2);
  }

  return WordFamily(root, trFor(dict, root, rootPos), [
    for (final m in members)
      FamilyEntry(m[0] as String, m[1] as String,
          tr: memberTr(m[0] as String, m[1] as String),
          affixNote: baseNote(m[0] as String, m[1] as String),
          exEn: example(m[0] as String).$1,
          exTr: example(m[0] as String).$2),
    for (final n in negs)
      FamilyEntry(n[0] as String, n[1] as String,
          tr: trFor(dict, n[0] as String, n[1] as String) ?? negativeTr(dict, n[2] as String, n[1] as String),
          affixNote: explainPrefix(n[2] as String, n[0] as String) ?? L('zıt anlam: ${n[2]}', 'opposite of: ${n[2]}'),
          negative: true,
          exEn: example(n[0] as String).$1,
          exTr: example(n[0] as String).$2),
  ]);
}
