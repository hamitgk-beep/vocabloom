/// Repairs for text slips that book files bring with them, found by
/// importing many books (PDFs with and without pictures, scanned books with
/// a recognised text layer, Word, EPUB, ODT, RTF, HTML, TXT) and checking
/// every word of the result. Each repair that changes a word checks the
/// dictionary first, so real words, names and abbreviations stay as written.
///
/// * [cleanInvisible]: characters a reader never wants to see: soft hyphens,
///   zero-width spaces, control characters and symbol-font bullets (Word saves
///   a Wingdings or Symbol bullet as a private-use character, shown as an
///   empty box).
/// * [joinBrokenWords]: PDFium marks a word broken at the end of a line with
///   a hidden character ("dan|gerous", "good-for|nothing"); it is joined
///   ("dangerous") or keeps its hyphen ("good-for-nothing").
/// * [fixOcrSlips]: letters that text recognition mixed up in a scanned book
///   ("mormng" -> "morning", "woman m Morocco" -> "woman in Morocco",
///   "Aladdin,s" -> "Aladdin's"), a stray letter at the end of a word
///   ("overwhelmn" -> "overwhelm").
library;

import 'word_gaps.dart';

/// PDFium's mark for a word broken over two lines. [importPdf] turns it into
/// a soft hyphen right away, since the page layout uses U+0002 for captions.
const pdfiumBreak = '\u0002';
const softHyphen = '\u00AD';

/// Bullets drawn with a font: Word's symbol-font bullets come out as
/// private-use characters (U+F0B7, U+F0A7, U+F0D8 …).
const bulletChars = '•▪■□●○◆◇►▶▸➢➤✓✔❖◦\u2023\u2043\u25AA\u25CF';

/// A bullet at the start of a block, a • or ◦ after the end of a sentence
/// ("Classics • True Stories" and "5 • 3" stay), any other bullet after a space.
final bulletAt = RegExp(
  '(?:^\\s*[$bulletChars\uE000-\uF8FF]|(?<=[.!?:;)"”’\']\\s+)[•◦]|(?<=\\s)[$_strongBullets\uE000-\uF8FF])'
  '(?:\\s+|(?=["“‘\'(A-Z]))',
);
const _strongBullets = '▪■□●○◆◇►▶▸➢➤✓✔❖\u2023\u2043\u25AA\u25CF';

final _invisible = RegExp('[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F\u00AD\u200B\u2060\uFEFF\uFFFE\uFFFF]');
final _privateUse = RegExp('[\uE000-\uF8FF]\\s*');

/// Removes characters that are never part of the reading text.
String cleanInvisible(String s) {
  if (!_invisible.hasMatch(s) && !_privateUse.hasMatch(s)) return s;
  return s.replaceAll(_invisible, '').replaceAll(_privateUse, '').replaceAll(RegExp(r'  +'), ' ').trim();
}

final _broken = RegExp("([A-Za-z]+)[$softHyphen$pdfiumBreak]\\s*([A-Za-z]+)");

/// Joins a word broken at the end of a line ("dan\u00ADgerous") or, when both
/// halves are words and the whole is not, keeps it as a hyphenated compound
/// ("good-for\u00ADnothing" -> "good-for-nothing").
String joinBrokenWords(String s, bool Function(String word)? isWord) {
  if (!s.contains(softHyphen) && !s.contains(pdfiumBreak)) return s;
  return s.replaceAllMapped(_broken, (m) {
    // Part of a longer hyphenated name ("Badr-|al-Budur") keeps its hyphen.
    if (m.end < s.length && s[m.end] == '-') return '${m.group(1)}-${m.group(2)}';
    return joinHalves(m.group(1)!, m.group(2)!, isWord);
  });
}

/// [a] and [b] are the two halves of a word broken with a hyphen at the end
/// of a line.
String joinHalves(String a, String b, bool Function(String word)? isWord) {
  final joined = '$a$b';
  if (isWord == null) return joined;
  if (isWord(joined)) return joined;
  // A capital after the break is a name or a compound: "Badr-al-Budur", "anti-American".
  if (b[0] != b[0].toLowerCase()) return '$a-$b';
  if (isWord(a) && isWord(b)) return '$a-$b';
  return joined;
}

/// Letters text recognition confuses: what it read -> what was printed.
const _confusions = [
  ('m', 'rn'),
  ('rn', 'm'),
  ('m', 'ni'),
  ('ni', 'm'),
  ('m', 'in'),
  ('in', 'm'),
  ('cl', 'd'),
  ('vv', 'w'),
  ('ii', 'u'),
  ('1', 'l'),
  ('0', 'o'),
];

/// Two consonants that end many English words; a word ending in any other
/// pair of consonants, which is not in the dictionary but is a word without
/// its last letter, has a stray letter at the end ("overwhelmn").
const _commonEndings = {
  'ng', 'nt', 'nd', 'st', 'ct', 'ld', 'rd', 'rt', 'rk', 'nk', 'll', 'lt', 'pt', 'ft', 'sk', 'sp', 'rm', 'lm', 'wn',
  'rn', 'ck', 'ch', 'sh', 'th', 'gh', 'ph', 'ss', 'ff', 'zz', 'mp', 'mb', 'lf', 'lk', 'rb', 'rf', 'rg', 'rl', 'rp',
  'sm', 'tz', 'wl', 'wd', 'xt', 'lp', 'lb', 'rc', 'nc', 'gn', 'dt', 'tt', 'pp', 'bb', 'dd', 'gg', 'nn', 'rr',
  'cc', 'kh', 'sc', 'nx', 'nz', 'lch', 'rch', 'nch', 'tch', 'lv', 'rv', 'rz', 'ps', 'ks', 'ts', 'ns', 'ls', 'rs', //
  'ds', 'gs', 'ms', 'bs', 'ws', 'ys', 'hs', 'cs', 'fs', 'ry', 'ly', 'ny', 'ty', 'dy', 'by', 'my', 'py', 'gy', 'sy',
  'cy', 'fy', 'ky', 'vy', 'zy', 'hy', 'wy', 'xy',
};
const _vowels = 'aeiouy';

final _wordTok = RegExp(r"[A-Za-z0-9]+");

/// Short words text recognition often misreads; longer ones are found by [_confusions].
const _shortSlips = {'df': 'of', 'tbe': 'the', 'aud': 'and', 'wbo': 'who'};

/// Whether s[st..e) stands between spaces or punctuation, not inside a longer token.
bool _alone(String s, int st, int e) =>
    (st == 0 || RegExp(r'''[\s"“‘(]''').hasMatch(s[st - 1])) &&
    (e == s.length || RegExp(r'''[\s.,;:!?"”’)]''').hasMatch(s[e]));

/// Repairs the slips text recognition leaves in a scanned book's text layer
/// (see the library comment). Only words the dictionary does not know are
/// touched, and only when exactly one repair gives a known word.
String fixOcrSlips(String s, bool Function(String word) isWord) {
  // "Aladdin,s mother": a comma read instead of an apostrophe.
  s = s.replaceAllMapped(RegExp(r"(?<=[A-Za-z]{2}),s(?= [a-z])"), (m) => "'s");
  // "woman m Morocco": a lone m between words is "in".
  s = s.replaceAllMapped(RegExp(r"(?<=[A-Za-z,] )m(?= [A-Za-z])"), (m) => 'in');
  // "didn 't", "Abanazar 's ring": a space before the ending of a contraction.
  s = s.replaceAllMapped(RegExp(r"(?<=[A-Za-z]) (['’](?:s|t|ll|re|ve))(?=[\s.,;:!?]|$)"), (m) => m.group(1)!);
  // "flowers .", "beautiful. '", "that' s": spaces text recognition put
  // before punctuation, a closing quote or the ending of a contraction.
  s = s.replaceAllMapped(RegExp(r'''(?<=[A-Za-z]) ([.!?])(?=['’"”)]?(?:\s|$))(?!\s*\.)'''), (m) => m.group(1)!);
  s = s.replaceAllMapped(RegExp(r"(?<=[.,!?]) (['’])(?=\s|$)"), (m) => m.group(1)!);
  s = s.replaceAllMapped(RegExp(r"(?<=[A-Za-z])(['’]) (s|t|ll|re|ve|d|m)(?=[\s.,;:!?]|$)"), (m) => '${m[1]}${m[2]}');
  // "sho\ivs", "l\/Ir", "ho1ne": letters text recognition read as symbols.
  s = s.replaceAllMapped(RegExp(r'''[A-Za-z\\/|!1"'’]*[\\/|!1"][A-Za-z\\/|!1"'’]*'''), (m) {
    final t = m.group(0)!;
    final lead = RegExp(r'''^['’"]*''').firstMatch(t)!.group(0)!;
    final rest = t.substring(lead.length);
    final trail = RegExp(r'''['’"!]*$''').firstMatch(rest)!.group(0)!;
    final core = rest.substring(0, rest.length - trail.length);
    if (core.length < 2 || !RegExp(r'[A-Za-z]').hasMatch(core) || !RegExp(r'''[\\/|!1"]''').hasMatch('$lead$core')) return t;
    // A word already ("veiled sounds" in quotes), or capitals with digits
    // ("C16H10", "vitamin A1"): no slip.
    if (RegExp(r'^[A-Za-z]+$').hasMatch(core) && isWord(core.toLowerCase())) return t;
    if (!RegExp(r'[a-z]').hasMatch(core)) return t;
    // A quote mark in front is a misread letter only when it opens no quotation ('"valking').
    final stray = lead == '"' && '"'.allMatches(s).length.isOdd;
    for (final c in [if (stray) ..._symbolReadings('$lead$core').map((r) => (r, '')), ..._symbolReadings(core).map((r) => (r, lead))]) {
      final (word, before) = c;
      if (RegExp(r'^[A-Za-z]+$').hasMatch(word) && (isWord(word.toLowerCase()) || word == 'Mr' || word == 'Mrs'))
        return '$before$word$trail';
    }
    return t;
  });
  // "bo�tom": a letter the file could not name.
  s = s.replaceAllMapped(RegExp('[A-Za-z]*�[A-Za-z]*'), (m) {
    final w = m.group(0)!;
    if (w.length < 3) return w;
    final hits = [
      for (final c in 'abcdefghijklmnopqrstuvwxyz'.split(''))
        if (isWord(w.replaceFirst('�', c).toLowerCase())) w.replaceFirst('�', c),
    ];
    return hits.length == 1 ? hits.first : w;
  });
  // "£arly": a capital E read as a pound sign.
  s = s.replaceAllMapped(
    RegExp(r'(?<![\w£])£([a-z]{2,})\b'),
    (m) => isWord('e${m.group(1)}') ? 'E${m.group(1)}' : m.group(0)!,
  );
  return s.replaceAllMapped(_wordTok, (m) {
    final w = m.group(0)!;
    final st = m.start, e = m.end;
    if (w.length < 4) return _shortSlips[w] != null && !isWord(w) && _alone(s, st, e) ? _shortSlips[w]! : w;
    // Part of a longer token (apostrophes, hyphens, e-mail, web addresses): leave it.
    final glued = RegExp(r"['’\-_/@.&]");
    final before = st > 0 ? s[st - 1] : ' ', after = e < s.length ? s[e] : ' ';
    if (glued.hasMatch(before) ||
        (glued.hasMatch(after) && !(after == '.' && (e + 1 >= s.length || s[e + 1] == ' ')))) {
      return w;
    }
    final lower = w.toLowerCase();
    // Lower case words only: names and abbreviations stay.
    if (lower != w) return w;
    final hasDigit = RegExp(r'\d').hasMatch(w);
    if (hasDigit && !RegExp(r'[a-z]{2}').hasMatch(lower)) return w; // numbers, "A4"
    if (RegExp(r'^\d+(st|nd|rd|th|s)$').hasMatch(lower)) return w; // "10th", "1920s"
    if (!hasDigit && isWord(lower)) return w;

    // One mixed-up letter group.
    final found = <String>{};
    for (final (from, to) in _confusions) {
      var i = lower.indexOf(from);
      while (i >= 0) {
        final c = '${lower.substring(0, i)}$to${lower.substring(i + from.length)}';
        if (!RegExp(r'\d').hasMatch(c) && isWord(c)) found.add(c);
        i = lower.indexOf(from, i + 1);
      }
    }
    if (hasDigit) {
      // "ma11" -> "mall": every digit read for a letter.
      final c = lower.replaceAll('1', 'l').replaceAll('0', 'o');
      if (found.isEmpty && isWord(c)) found.add(c);
      return found.length == 1 ? found.first : w;
    }
    if (found.length == 1) return found.first;
    if (found.length > 1) return w;

    // A stray letter at the end: "overwhelmn". Not s or t, which end old
    // spellings ("pluckt", "stretcht") and words the dictionary lacks.
    final n = lower.length;
    if (n >= 6) {
      final last = lower[n - 1], prev = lower[n - 2];
      if (!_vowels.contains(last) &&
          !_vowels.contains(prev) &&
          last != 's' &&
          last != 't' &&
          !_commonEndings.contains('$prev$last') &&
          isWord(lower.substring(0, n - 1))) {
        return lower.substring(0, n - 1);
      }
    }

    return w;
  });
}

/// Symbols text recognition reads for letters, longest first.
const _symbolSlips = [
  (r'l\/I', 'M'),
  (r'l\/l', 'M'),
  (r'I\/I', 'M'),
  (r'l\1', 'M'),
  (r'l\!l', 'M'),
  (r'\iV', 'w'),
  (r'\iv', 'w'),
  (r'\V', 'W'),
  (r'\v', 'w'),
  ("'1v", 'w'),
  ('"v', 'w'),
  ('1v', 'w'),
  ('1n', 'm'),
  ('11', 'u'),
  ('1', 'l'),
  ('!', 'l'),
  ('|', 'l'),
];

/// Ways to read [core] with the symbols in it taken for letters: all slips
/// at once, then each one alone.
Iterable<String> _symbolReadings(String core) sync* {
  var all = core;
  for (final (from, to) in _symbolSlips) {
    all = all.replaceAll(from, to);
  }
  yield all;
  for (final (from, to) in _symbolSlips) {
    if (core.contains(from)) yield core.replaceAll(from, to);
  }
}

/// Letters text recognition mixes up inside a word ("evety", "seivant").
const _letterSlips = [
  ('t', 'r'),
  ('i', 'r'),
  ('r', 't'),
  ('n', 'u'),
  ('u', 'n'),
  ('c', 'e'),
  ('e', 'c'),
  ('c', 'a'),
  ('l', 'i'),
  ('i', 'l'),
  ('lr', 'h'),
  ('li', 'h'),
  ('rn', 'm'),
  ('ni', 'n'),
];

/// Pairs of letters text recognition mixes up: what it read, what was printed.
const _mixedUp = {
  'tr',
  'ir',
  'rt',
  'nu',
  'un',
  'ce',
  'ec',
  'ca',
  'li',
  'il',
  'Il',
  'lI',
  'hb',
  'bh',
  'oe',
  'eo',
  'ao',
  'vy',
  'Tr',
  'TG',
  'VU',
  'CG',
  'nr',
  'rn',
  'ft',
};

/// Words of grammar the dictionary may not list.
const _smallWords = {
  'myself',
  'yourself',
  'himself',
  'herself',
  'itself',
  'ourselves',
  'yourselves',
  'themselves',
  'into',
  'onto',
  'upon',
  'within',
  'without',
  'because',
  'before',
  'after',
  'about',
  'above',
  'below',
  'between',
  'through',
  'something',
  'anything',
  'nothing',
  'everything',
  'someone',
  'anyone',
  'everyone',
  'nobody',
  'somebody',
  'everybody',
};

/// Repairs that need the whole book: a misread word ("Herny") becomes the
/// word the book uses many times ("Henry") when it is one letter or one swap
/// away, or the only word one mixed-up letter away ("evety" -> "every"); a
/// word cut in two ("Dori an", "mys elf", "H ow") is joined when the halves
/// are not both words and the whole is a word or a name the book uses.
List<String> fixWithBookWords(List<String> paras, bool Function(String word) isWord) {
  final tok = RegExp(r'[A-Za-z]+');
  final count = <String, int>{};
  for (final p in paras) {
    for (final m in tok.allMatches(p)) {
      count[m.group(0)!] = (count[m.group(0)!] ?? 0) + 1;
    }
  }
  bool capital(String w) => w[0] != w[0].toLowerCase();
  // Words the dictionary leaves out (it has no pronouns) count when the book uses them.
  bool known(String w) => isWord(w.toLowerCase()) || _smallWords.contains(w.toLowerCase()) || (count[w] ?? 0) >= 3;
  bool single(String w) => w.length == 1 ? (w == 'a' || w == 'A' || w == 'I') : isWord(w.toLowerCase());
  final byLen = <int, List<String>>{};
  for (final e in count.entries) {
    if (e.value >= 3 && e.key.length >= 4 && (capital(e.key) || isWord(e.key))) (byLen[e.key.length] ??= []).add(e.key);
  }
  bool oneAway(String a, String b) {
    final diff = <int>[];
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) diff.add(i);
      if (diff.length > 2) return false;
    }
    // One letter that text recognition mixes up ("Henty"; not "Kong" for "King").
    if (diff.length == 1) return _mixedUp.contains('${a[diff[0]]}${b[diff[0]]}');
    // Two letters swapped: "Herny".
    return diff.length == 2 && diff[1] == diff[0] + 1 && a[diff[0]] == b[diff[1]] && a[diff[1]] == b[diff[0]];
  }

  final fixes = <String, String?>{};
  String? better(String w) {
    if (fixes.containsKey(w)) return fixes[w];
    String? found;
    if (w.length >= 4 && !isWord(w.toLowerCase()) && (count[w] ?? 0) <= 2) {
      final hits = <String>{
        for (final c in byLen[w.length] ?? const <String>[])
          if (c != w && capital(c) == capital(w) && oneAway(w, c)) c,
      };
      // Only a word the book also has, so that a loose dictionary match
      // ("acttes") does not win.
      if (hits.isEmpty && w == w.toLowerCase()) {
        for (final (from, to) in _letterSlips) {
          var i = w.indexOf(from);
          while (i >= 0) {
            final c = '${w.substring(0, i)}$to${w.substring(i + from.length)}';
            if ((count[c] ?? 0) >= 1 && isWord(c)) hits.add(c);
            i = w.indexOf(from, i + 1);
          }
        }
      }
      if (hits.length == 1) found = hits.first;
    }
    fixes[w] = found;
    return found;
  }

  // Joins "a b" where a is a word piece and b one in small letters, looking
  // at every pair in turn ("of mys elf" tries "of mys", then "mys elf").
  final piece = RegExp(r"(?<![A-Za-z'’])[A-Za-z]+(?![A-Za-z'’])");
  String joinHalves(String p) {
    final ms = piece.allMatches(p).toList();
    final out = StringBuffer();
    var at = 0;
    for (var i = 0; i + 1 < ms.length; i++) {
      final m = ms[i], n = ms[i + 1];
      if (n.start != m.end + 1 || p[m.end] != ' ' || m.start < at) continue;
      final a = m.group(0)!, b = n.group(0)!, j = '$a$b';
      if (b != b.toLowerCase()) continue;
      // Both are words: they are joined only into a word the book uses often,
      // when one half is rare in the book ("Hall ward", "mys elf"; never "in to").
      final rare = (count[a] ?? 0) <= 2 || (count[b] ?? 0) <= 2;
      // A name cut in two ("Dori an") is joined only into a name the book has ("Dar es Salaam" stays).
      final join = single(a) && single(b)
          ? rare && (count[j] ?? 0) >= 3
          : capital(a) && a.length > 1
          ? (count[j] ?? 0) >= 2 || (b.length == 1 && known(j))
          : known(j) || (count[j] ?? 0) >= 2;
      if (!join) continue;
      out
        ..write(p.substring(at, m.start))
        ..write(j);
      at = n.end;
      i++;
    }
    out.write(p.substring(at));
    return out.toString();
  }

  return [
    for (final p in paras)
      joinHalves(
        p.replaceAllMapped(tok, (m) {
          // Part of a longer token ("bett.er", an address): leave it.
          final before = m.start > 0 ? p[m.start - 1] : ' ', after = m.end < p.length ? p[m.end] : ' ';
          final next = m.end + 1 < p.length ? p[m.end + 1] : ' ';
          if (RegExp(r'[.,@/_\-]').hasMatch(before) || (RegExp(r'[.,@/_\-]').hasMatch(after) && RegExp(r'[A-Za-z]').hasMatch(next))) {
            return m.group(0)!;
          }
          return better(m.group(0)!) ?? m.group(0)!;
        }),
      ),
  ];
}

/// A block of a PDF page cut where a bullet starts a new item: list items that
/// the page layout ran together ("... very fair. ■ From house to house ...").
/// The bullet itself is dropped.
List<String> splitAtBullets(String block) => [
  for (final p in block.split(bulletAt))
    if (p.trim().isNotEmpty) p.trim(),
];

/// Every repair for a paragraph that came from a PDF or a scanned page, in
/// order. Also used once on books imported before these repairs existed.
String repairPdfText(String s, bool Function(String word)? isWord) {
  s = joinBrokenWords(s, isWord);
  s = cleanInvisible(s);
  // A "J" some fonts give as a bracket ("Editors: ] ennifer Bassett").
  s = s.replaceAllMapped(RegExp(r'(^|[\s:])\] ?(?=[a-z]{3,})'), (m) => '${m[1]}${m[1] == ':' ? ' ' : ''}J');
  if (isWord == null) return s;
  s = splitJoinedWords(s, isWord);
  s = fixGlyphSlips(s, isWord);
  return fixOcrSlips(s, isWord);
}

/// A large first letter (a drop cap) stands apart from its paragraph on the
/// page, so it comes out as a line of its own ("A") next to a line that
/// starts with the rest of the word ("nd as the day passed").
/// The letter goes back in front of its word.
List<String> joinDropCaps(List<String> blocks, bool Function(String word)? isWord) {
  final out = [...blocks];
  for (var i = 0; i < out.length; i++) {
    final m = RegExp(r'''^(["“‘']?)([A-Z])$''').firstMatch(out[i].trim());
    if (m == null) continue;
    final letter = m.group(2)!;
    int step(int j, int d) {
      while (j >= 0 && j < out.length && out[j].trim().isEmpty) {
        j += d;
      }
      return j;
    }

    for (final j in [step(i + 1, 1), step(i - 1, -1)]) {
      if (j < 0 || j >= out.length) continue;
      final rest = RegExp(r'^[a-z]+').firstMatch(out[j].trimLeft());
      if (rest == null) continue;
      final w = rest.group(0)!;
      // "A" + "nd as the day" -> "And as the day"; "A" + "little cloud" -> "A little cloud".
      final glued = isWord == null || w.length == 1 || isWord('$letter$w'.toLowerCase()) || !isWord(w);
      if (!glued && letter != 'A' && letter != 'I') continue;
      out[j] = '${m.group(1)}$letter${glued ? '' : ' '}${out[j].trimLeft()}';
      out.removeAt(i);
      i--;
      break;
    }
  }
  return out;
}

/// Titles set in spaced-out capitals come out of a PDF cut in odd places
/// ("AL A D D IN", "AN D T HE EN C H ANTE D L A MP", "CONT ENTS", "A ND").
/// In a line of capitals, pieces are joined again into dictionary words:
/// when most pieces are one or two letters the whole line is split anew
/// into words; otherwise two neighbours are joined where together they are
/// a word and one of them is not ("A ND" -> "AND") or is a stray piece of one
/// or two letters ("EN CHANTED" -> "ENCHANTED").
String joinSpacedCaps(String s, bool Function(String word)? isWord) {
  if (isWord == null) return s;
  final letters = RegExp(r'[A-Za-z]').allMatches(s).length;
  final upper = RegExp(r'[A-Z]').allMatches(s).length;
  if (letters < 3 || upper < letters * 0.9) return s;
  bool word(String w) => w.length > 1 || w == 'A' || w == 'I' ? isWord(w.toLowerCase()) : false;
  // Runs of capitals separated by single spaces; punctuation ends a run.
  return s.replaceAllMapped(RegExp(r"[A-Z]+(?: [A-Z]+)+"), (m) {
    final toks = m.group(0)!.split(' ');
    final short = toks.where((t) => t.length <= 2).length;
    if (toks.length >= 3 && short >= toks.length * 0.5) {
      // Split the letters again: known words cost 1, an unknown piece (a
      // name) costs more the longer it is, so words win where they fit.
      final all = toks.join();
      final n = all.length;
      final best = List<double>.filled(n + 1, double.infinity)..[0] = 0;
      final from = List<int>.filled(n + 1, -1);
      for (var e = 1; e <= n; e++) {
        for (var b = e - 1; b >= 0 && e - b <= 20; b--) {
          if (best[b] == double.infinity) continue;
          final piece = all.substring(b, e);
          final c = word(piece) ? 1.0 : (piece.length >= 4 ? 1 + 0.25 * piece.length : double.infinity);
          if (best[b] + c < best[e]) {
            best[e] = best[b] + c;
            from[e] = b;
          }
        }
      }
      if (best[n] == double.infinity) return m.group(0)!;
      final out = <String>[];
      for (var e = n; e > 0; e = from[e]) {
        out.insert(0, all.substring(from[e], e));
      }
      return out.join(' ');
    }
    final out = <String>[];
    for (final t in toks) {
      final j = out.isEmpty ? '' : out.last + t;
      if (out.isNotEmpty &&
          word(j) &&
          ((!word(out.last) || !word(t)) ||
              ((out.last.length <= 2 || t.length <= 2) && j.length >= 6) ||
              (out.last.length <= 2 && t.length <= 2))) {
        out[out.length - 1] = out.last + t;
      } else {
        out.add(t);
      }
    }
    return out.join(' ');
  });
}
