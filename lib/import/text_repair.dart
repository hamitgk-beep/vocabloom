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
