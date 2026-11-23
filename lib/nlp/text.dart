/// Tokenizing, lemmatizing and phrase matching for English text.
library;

class Token {
  final int start;
  final int end;
  final String text;
  final String lower;
  Token(this.start, this.end, this.text) : lower = _norm(text);
}

String _norm(String s) => s.toLowerCase().replaceAll('’', "'");

// Every Latin letter, with its accents, belongs to the word: Turkish books
// split into whole words, and so do "café", "naïve" and "Brontë" in English
// ones (a word cut at its accent is looked up as another word).
const _l = r'\p{Script=Latin}\p{M}';
final RegExp _wordRe = RegExp("[$_l]+(?:['’][$_l]+)*(?:-[$_l]+)*", unicode: true);

List<Token> tokenize(String text) => [
      for (final m in _wordRe.allMatches(text)) Token(m.start, m.end, m.group(0)!)
    ];

/// Splits a paragraph into sentences; returns [start, end) ranges that follow
/// each other in order.
///
/// A dot is not a sentence end when it belongs to an abbreviation, an initial
/// or a reference: "Prof. Child", "Mr. E. S. Hartland", "(No. 28)",
/// "(ed. 1886), i. 125", "p. 35", "e.g. an", "U.S.", "3.5". The translations
/// saved for a paragraph, the sentence panel, grammar marks and reading aloud
/// all use these boundaries, so a split in the middle of a sentence gave the
/// AI fragments that it joined, and the Turkish slid onto the next sentence.
List<(int, int)> sentenceRanges(String text) {
  final out = <(int, int)>[];
  void add(int s, int e) {
    if (e > s && text.substring(s, e).trim().isNotEmpty) out.add((s, e));
  }

  final n = text.length;
  var start = 0;
  var i = 0;
  while (i < n) {
    if (!_terminators.contains(text[i])) {
      i++;
      continue;
    }
    final runStart = i;
    while (i < n && _terminators.contains(text[i])) {
      i++;
    }
    final runEnd = i;
    while (i < n && _closers.contains(text[i])) {
      i++;
    }
    if (_endsSentence(text, runStart, runEnd, i)) {
      add(start, i);
      start = i;
    }
  }
  add(start, n);
  if (out.isEmpty) out.add((0, n));
  return out;
}

/// The sentence a word of a paragraph is in, as every screen sees it: the
/// reader's underline, the word panel, the sentence panel and the context
/// picker all cut it here, so they judge the same words.
class SentenceAt {
  /// The sentence, without the spaces around it.
  final String text;

  /// Its tokens (the paragraph's own, with their places in the paragraph).
  final List<Token> tokens;

  /// Index of [tokens].first among the paragraph's tokens.
  final int first;

  /// Number of the sentence in the paragraph, and the sentences around it.
  final int index;
  final String? prev;
  final String? next;
  const SentenceAt(this.text, this.tokens, this.first, this.index, this.prev, this.next);
}

/// The sentence of token [ti] of a paragraph. [ranges]: its
/// [sentenceRanges], when the caller has them.
SentenceAt sentenceAt(String text, List<Token> tokens, int ti, {List<(int, int)>? ranges}) {
  final rs = ranges ?? sentenceRanges(text);
  final t = tokens[ti];
  var k = 0;
  for (var i = 0; i < rs.length; i++) {
    if (t.start >= rs[i].$1 && t.start < rs[i].$2) k = i;
  }
  final r = rs[k];
  var a = ti, b = ti;
  while (a > 0 && tokens[a - 1].start >= r.$1) {
    a--;
  }
  while (b + 1 < tokens.length && tokens[b + 1].end <= r.$2) {
    b++;
  }
  String? at(int i) => i >= 0 && i < rs.length ? text.substring(rs[i].$1, rs[i].$2).trim() : null;
  return SentenceAt(text.substring(r.$1, r.$2).trim(), tokens.sublist(a, b + 1), a, k, at(k - 1), at(k + 1));
}

const _terminators = {'.', '!', '?', '…'};
const _closers = {'"', '”', '’', ')', ']', "'"};
const _dashes = {'—', '–', '-'};

/// Words that are written with a dot and are followed by a name or a
/// capitalised word without ending the sentence. Words that often end a
/// sentence ("etc.", "Inc.", "Jr.", "No." as an answer) are left out: a
/// number after them is handled by the digit rule.
const _abbreviations = {
  'Mr', 'Mrs', 'Ms', 'Mx', 'Dr', 'Prof', 'St', 'Mt', 'Rev', 'Revd', 'Fr', 'Gen', 'Col', 'Capt', 'Lt', 'Sgt',
  'Maj', 'Cmdr', 'Adm', 'Gov', 'Sen', 'Rep', 'Hon', 'Messrs', 'Mme', 'Mlle',
  'vs', 'viz', 'cf', 'Cf', 'ed', 'eds', 'Ed', 'Eds', 'trans', 'vol', 'vols', 'Vol', 'Vols', 'ch', 'chap', 'Ch', 'Chap',
  'fig', 'figs', 'Fig', 'Figs', 'pp', 'Pp',
};

bool _isLetter(String c) => c.toLowerCase() != c.toUpperCase();
bool _isDigit(String c) => c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;
bool _isSpace(String c) => c.trim().isEmpty;
bool _isLower(String c) => _isLetter(c) && c == c.toLowerCase();
bool _isUpper(String c) => _isLetter(c) && c == c.toUpperCase();

/// Whether the terminators at [runStart, runEnd) (with closing quotes and
/// brackets up to [end]) end a sentence.
bool _endsSentence(String text, int runStart, int runEnd, int end) {
  final n = text.length;
  if (end >= n) return true;
  final run = text.substring(runStart, runEnd);
  final dots = run.split('').every((c) => c == '.' || c == '…');
  final closed = end > runEnd;
  final next = text[end];
  if (!_isSpace(next)) {
    // A dot inside a word or a number: "U.S.", "e.g", "3.5", "etc.,".
    if (dots && !closed && (_isLetter(next) || _isDigit(next) || ',;:'.contains(next))) return false;
    return true;
  }
  var j = end;
  while (j < n && (_isSpace(text[j]) || _dashes.contains(text[j]))) {
    j++;
  }
  if (j >= n) return true;
  final c = text[j];
  // A sentence starts with a capital, so what goes on in small letters is
  // the same sentence: "'Well!' thought Alice", "“Where?” asked Tom",
  // "Ah! what a day", "pop. de", "these… and".
  if (_isLower(c)) return false;
  // Otherwise closing quotes or brackets, "!" and "?" end it
  // ("(see p. 4). After").
  if (!dots || closed) return true;
  // "ed. 1886", "i. 125".
  if (_isDigit(c)) return false;
  if (run != '.') return true;
  // The word right before the dot.
  var w = runStart;
  while (w > 0 && _isLetter(text[w - 1])) {
    w--;
  }
  final word = text.substring(w, runStart);
  if (_abbreviations.contains(word)) return false;
  // An initial before a name: "E. S. Hartland", "J. M. W. Turner" (not "I.").
  if (word.length == 1 && _isUpper(word) && word != 'I' && _isUpper(c)) return false;
  return true;
}

/// Morphy-style lemmatizer backed by the WordNet exception lists and the
/// set of known lemmas.
class Lemmatizer {
  final Set<String> known;
  final Map<String, List<String>> exc;
  final Map<String, List<String>> _cache = {};
  Lemmatizer(this.known, this.exc);

  static const _rules = [
    ['ies', 'y'], ['ves', 'f'], ['ves', 'fe'], ['ses', 's'], ['xes', 'x'], ['zes', 'z'],
    ['ches', 'ch'], ['shes', 'sh'], ['men', 'man'], ['es', 'e'], ['es', ''], ['s', ''],
    ['ied', 'y'], ['ed', 'e'], ['ed', ''], ['ying', 'ie'], ['ing', 'e'], ['ing', ''],
    ['ier', 'y'], ['iest', 'y'], ['er', 'e'], ['est', 'e'], ['er', ''], ['est', ''],
    ['ly', ''], ['ily', 'y'],
  ];

  /// Base-form candidates, most likely first. The surface form is last.
  List<String> lemmas(String lower) {
    final c = _cache[lower];
    if (c != null) return c;
    var w = lower;
    if (w.endsWith("'s")) w = w.substring(0, w.length - 2);
    final out = <String>[];
    void add(String x) {
      if (x.isNotEmpty && !out.contains(x) && known.contains(x)) out.add(x);
    }

    for (final l in exc[w] ?? const <String>[]) {
      add(l);
    }
    for (final r in _rules) {
      if (w.length > r[0].length + 1 && w.endsWith(r[0])) {
        final base = w.substring(0, w.length - r[0].length) + r[1];
        add(base);
        // stopped -> stopp -> stop
        if (r[1].isEmpty && base.length > 2 && base[base.length - 1] == base[base.length - 2]) {
          add(base.substring(0, base.length - 1));
        }
      }
    }
    if (known.contains(w)) {
      out.add(w);
    } else if (!out.contains(w)) {
      out.add(w); // keep unknown surface so statuses still work
    }
    // Ordinary plural nouns and real words such as "news", "during": prefer
    // the surface form when no exception applies and it is itself a word that
    // does not look inflected.
    if (out.length > 1 && known.contains(w) && !exc.containsKey(w) && !RegExp(r'(ed|ing|er|est|ly)$').hasMatch(w)) {
      out.remove(w);
      out.insert(0, w);
    }
    _cache[lower] = out;
    return out;
  }
}

const _poss = {'my', 'your', 'his', 'her', 'its', 'our', 'their', "one's"};
const _det = {
  'a', 'an', 'the', 'my', 'your', 'his', 'her', 'its', 'our', 'their', 'this',
  'that', 'these', 'those', 'some', 'any', 'no', 'every', 'each'
};
const _objPron = {'it', 'them', 'him', 'her', 'me', 'us', 'you', 'this', 'that', 'everything', 'something'};
const _reflexive = {'myself', 'yourself', 'himself', 'herself', 'itself', 'ourselves', 'themselves', 'oneself'};

class Expr {
  final int id;
  final String phrase;
  final String cat;
  final String? tr;
  final String? en;
  final List<String> pattern;

  /// Example sentence from the dictionary (Wiktionary), if any.
  String? ex;

  /// Turkish translation of [en] (built-in library), senses separated by "; ".
  String? enTr;

  /// Turkish translation of [ex].
  String? exTr;

  /// Turkish meaning / explanation made by the user's AI service (saved on device).
  String? aiTr;
  String? aiExp;
  Expr(this.id, this.phrase, this.cat, this.tr, this.en, this.pattern, {this.ex, this.enTr, this.exTr});

  /// Turkish of an unreviewed AI draft (own_expr, reviewed = 0). It never replaces
  /// [tr]; it is shown only when the dictionary has no Turkish, and labelled.
  String? trDraft;

  /// Turkish meaning: from the dictionary, otherwise the AI draft, otherwise the
  /// user's own AI translation.
  String? get trShown => tr ?? trDraft ?? aiTr;

  /// [trShown] comes from an unreviewed AI draft.
  bool get trShownIsDraft => tr == null && trDraft != null;

  /// Whether the AI still has something to translate for this entry.
  bool get needsAi => tr == null && trDraft == null && aiTr == null && en != null;
}

class Match {
  final Expr expr;
  final List<int> tokens; // token indexes that belong to the expression

  /// How a match found only by [PhraseMatcher.match]'s `variants` differs from
  /// the dictionary form ('insertion', 'possessive'); null for an ordinary match.
  final String? variant;
  Match(this.expr, this.tokens, {this.variant});
}

/// Matches multi-word expressions (and single-word category members) in a
/// tokenized paragraph.
class PhraseMatcher {
  final Lemmatizer lem;
  final Map<String, List<Expr>> _byFirst = {};
  final Map<String, List<Expr>> _byForm = {}; // irregular verb forms

  PhraseMatcher(this.lem, List<Expr> exprs, Map<int, List<String>> forms) {
    for (final e in exprs) {
      if (forms.containsKey(e.id)) {
        for (final f in forms[e.id]!.skip(1).where((f) => f != forms[e.id]!.first)) {
          _byForm.putIfAbsent(f, () => []).add(e);
        }
        continue;
      }
      final first = e.pattern.first;
      final key = (first == 'a' || first == 'the' || first == 'an') ? '*det' : first;
      _byFirst.putIfAbsent(key, () => []).add(e);
    }
  }

  /// Parts of speech of a word ('n', 'v', 'a', 'r'), for the experimental
  /// matching of [match]'s `variants`; set by the dictionary.
  Set<String> Function(String)? posOf;

  bool _tokMatches(String p, Token t, {bool variants = false}) {
    if (p == t.lower) return true;
    if (p == "one's") return _poss.contains(t.lower) || (variants && _ownerS(t.lower));
    // Task 5G, experimental: the dictionary writes "someone's" in 218
    // expressions ("burst someone's bubble"); a text has "his", "Oliver's".
    if (variants && p == "someone's") return _poss.contains(t.lower) || _ownerS(t.lower);
    if (p == 'oneself') return _reflexive.contains(t.lower);
    if (p == 'a' || p == 'an' || p == 'the') return _det.contains(t.lower);
    return lem.lemmas(t.lower).contains(p);
  }

  /// A noun or name with a possessive "'s" ("Oliver's", "people's").
  static bool _ownerS(String w) => (w.endsWith("'s") || w.endsWith('’s')) && w.length > 3;

  /// Words that may stand inside an expression in the experimental matching
  /// ("run the whole gamut", "cut a greater dash"): an adjective, an adverb
  /// or a participle before a word of the expression that is not a grammar word.
  bool _insertable(String w) {
    if (stopWords.contains(w) || _det.contains(w) || w.contains("'") || w.contains('’')) return false;
    if (w.endsWith('ing') || w.endsWith('ed')) return true;
    final pos = posOf?.call(w) ?? const <String>{};
    return pos.contains('a') || pos.contains('r');
  }

  /// Returns the token indexes matched, or null. With [variants] (Task 5G,
  /// experimental) one modifier may stand between two words of an expression
  /// of three or more words, and "someone's" / "one's" take any possessive.
  List<int>? _matchAt(Expr e, List<Token> toks, int i, {bool variants = false, List<String>? kind}) {
    final pat = e.pattern;
    final idx = <int>[];
    var j = i;
    var inserted = false;
    for (var k = 0; k < pat.length; k++) {
      final p = pat[k];
      if (p == 'sb' || p == 'sth' || p == 'someone' || p == 'something') {
        // wildcard 1..4 tokens, followed by the next pattern word
        if (k == pat.length - 1) {
          if (j >= toks.length) return null;
          j += 1;
          continue;
        }
        var found = false;
        for (var g = 1; g <= 4 && j + g < toks.length; g++) {
          if (_tokMatches(pat[k + 1], toks[j + g])) {
            j += g;
            found = true;
            break;
          }
        }
        if (!found) return null;
        continue;
      }
      if (j >= toks.length) return null;
      if (_tokMatches(p, toks[j], variants: variants)) {
        if (variants && (p == "someone's" || p == "one's") && !_poss.contains(toks[j].lower) && p != toks[j].lower) kind?.add('possessive');
        if (variants && p == "someone's" && _poss.contains(toks[j].lower)) kind?.add('possessive');
        idx.add(j);
        j++;
        continue;
      }
      if (variants &&
          !inserted &&
          k > 0 &&
          pat.length >= 3 &&
          e.cat != 'phrasal_verbs' &&
          !stopWords.contains(p) &&
          j + 1 < toks.length &&
          _insertable(toks[j].lower) &&
          _tokMatches(p, toks[j + 1], variants: variants)) {
        inserted = true;
        kind?.add('insertion');
        idx.add(j + 1);
        j += 2;
        continue;
      }
      // separable phrasal verbs: "give it up"
      if (e.cat == 'phrasal_verbs' && k == 1 && j + 1 < toks.length &&
          _objPron.contains(toks[j].lower) && _tokMatches(p, toks[j + 1])) {
        idx.add(j + 1);
        j += 2;
        continue;
      }
      return null;
    }
    return idx;
  }

  /// Particles that can stand after the object of a phrasal verb
  /// ("turn the light off", "look the word up").
  static const _sepParticles = {'up', 'down', 'off', 'out', 'away', 'back', 'on', 'over', 'in', 'around', 'about'};

  /// Words that may follow the particle when it closes the clause
  /// ("turn the light off and leave").
  static const _prepAfter = {'in', 'on', 'at', 'to', 'for', 'from', 'with', 'into', 'of'};

  static const _afterParticle = {
    'and', 'but', 'or', 'then', 'again', 'now', 'too', 'quickly', 'completely', 'first',
    // a new clause starts ("turn the light off before you leave")
    'before', 'after', 'when', 'while', 'because', 'so', 'until', 'till', 'if', 'unless', 'once', 'as',
    'soon', 'later', 'today', 'tonight', 'tomorrow', 'please', 'carefully', 'slowly',
  };

  /// A two-word phrasal verb split by a short noun object: verb at [i], a
  /// determiner or possessive at i+1, at most two more words, then the
  /// particle, which must end the clause (end of text, punctuation, or a word
  /// like "and"). "put the book on the table" is not "put on": "on" is
  /// followed by its own object there. Needs [text] to see punctuation.
  void _separableNoun(List<Token> toks, int i, String text, List<Match> out) {
    if (i + 2 >= toks.length || !_det.contains(toks[i + 1].lower) || _objPron.contains(toks[i + 1].lower)) return;
    final lemmas = {toks[i].lower, ...lem.lemmas(toks[i].lower)};
    for (var k = i + 2; k < toks.length && k <= i + 4; k++) {
      final p = toks[k].lower;
      if (!_sepParticles.contains(p)) {
        if (stopWords.contains(p)) return; // "the book on the table", "the dog that …"
        continue;
      }
      if (k == i + 2) return; // "the up": the object needs a noun
      // "look the word up in the dictionary": a preposition may follow "up" or
      // "out"; after other particles ("take the bus in town") it may not.
      final next = k + 1 < toks.length ? toks[k + 1].lower : '';
      final closes = k + 1 >= toks.length ||
          RegExp(r'[.,;:!?)"”]').hasMatch(text.substring(toks[k].end, toks[k + 1].start)) ||
          _afterParticle.contains(next) ||
          ((p == 'up' || p == 'out') && _prepAfter.contains(next));
      if (!closes) return;
      for (final l in lemmas) {
        for (final e in _byFirst[l] ?? const <Expr>[]) {
          if (e.cat == 'phrasal_verbs' && e.pattern.length == 2 && e.pattern[1] == p) out.add(Match(e, [i, k]));
        }
      }
      return;
    }
  }

  /// All expressions in a tokenized paragraph. With [text] (the paragraph the
  /// tokens come from) phrasal verbs split by a noun object are found too.
  List<Match> match(List<Token> toks, {String? text, bool variants = false}) {
    final out = <Match>[];
    // The sentence each token is in: an expression is inside one sentence
    // ("Take care. For now …" is not "care for").
    List<int>? sent;
    if (text != null) {
      final ranges = sentenceRanges(text);
      var r = 0;
      sent = [
        for (final t in toks)
          () {
            while (r + 1 < ranges.length && t.start >= ranges[r].$2) {
              r++;
            }
            return r;
          }(),
      ];
    }
    bool oneSentence(List<int> idx) => sent == null || idx.isEmpty || sent[idx.first] == sent[idx.last];
    for (var i = 0; i < toks.length; i++) {
      final t = toks[i];
      final keys = <String>{t.lower, ...lem.lemmas(t.lower)};
      if (_det.contains(t.lower)) keys.add('*det');
      for (final k in keys) {
        for (final e in _byFirst[k] ?? const <Expr>[]) {
          // "the dog out", "a bed in": after a determiner the word is a noun,
          // not the verb of a phrasal verb.
          if (e.cat == 'phrasal_verbs' && i > 0 && _det.contains(toks[i - 1].lower)) continue;
          final m = _matchAt(e, toks, i);
          if (m != null && oneSentence(m)) {
            out.add(Match(e, m));
          } else if (variants) {
            final kind = <String>[];
            final v = _matchAt(e, toks, i, variants: true, kind: kind);
            if (v != null && oneSentence(v)) out.add(Match(e, v, variant: kind.isEmpty ? 'other' : kind.join('+')));
          }
        }
      }
      for (final e in _byForm[t.lower] ?? const <Expr>[]) {
        out.add(Match(e, [i]));
      }
      if (text != null && (i == 0 || !_det.contains(toks[i - 1].lower))) {
        final before = out.length;
        _separableNoun(toks, i, text, out);
        for (var k = out.length - 1; k >= before; k--) {
          if (!oneSentence(out[k].tokens)) out.removeAt(k);
        }
      }
    }
    return out;
  }
}

/// Placeholder words of the dictionary patterns ("give sb the cold shoulder").
const placeholderWords = {'sb', 'sth'};

/// How an expression is written for people. The dictionary keeps "sb" / "sth"
/// as wildcards for matching; on screen "neither sb nor" reads as a typo, so a
/// gap before and / or / nor / but / than / when becomes "…" ("neither … nor",
/// "no sooner … than") and the rest
/// become "someone" / "something" ("give someone the cold shoulder").
String displayPhrase(String phrase) {
  final w = phrase.split(' ');
  for (var i = 0; i < w.length; i++) {
    if (!placeholderWords.contains(w[i])) continue;
    final next = i + 1 < w.length ? w[i + 1] : '';
    w[i] = const {'and', 'or', 'nor', 'but', 'than', 'when'}.contains(next) ? '…' : (w[i] == 'sb' ? 'someone' : 'something');
  }
  return w.join(' ');
}

List<String> patternOf(String phrase) => tokenize(phrase).map((t) => t.lower).toList();

/// For each token and one past the last: whether a mark that ends a clause
/// (comma, full stop, bracket, quote, dash …) stands right before it in
/// [sentence]. The words on the two sides of such a mark do not tell each
/// other's part of speech ("… property rights, the state …"). Null when the
/// tokens are not found in [sentence].
List<bool>? clauseBreaks(String sentence, List<Token> toks) {
  if (toks.isEmpty) return null;
  // Tokens may carry their place in a longer text (the paragraph).
  final at = sentence.indexOf(toks.first.text);
  if (at < 0) return null;
  final off = toks.first.start - at;
  final out = <bool>[true];
  for (var i = 0; i < toks.length; i++) {
    final s = toks[i].start - off, e = toks[i].end - off;
    if (s < 0 || e > sentence.length || sentence.substring(s, e) != toks[i].text) return null;
    if (i > 0) out.add(_clauseMark.hasMatch(sentence.substring(toks[i - 1].end - off, s)));
  }
  out.add(true);
  return out;
}

final _clauseMark = RegExp(r'[.,;:!?()\[\]"“”…—–]| - ');

/// Small part-of-speech guesser used to pick the right dictionary sense: the
/// part of speech the words right around token [i] call for, or null when
/// they do not say. [breaks] ([clauseBreaks]) keeps it from reading across a
/// comma or a full stop. [why] is told which rule decided (see
/// [SenseEngine] for the rules that are too often wrong to count as proof).
String? guessPos(List<Token> toks, int i, Set<String> availablePos, {Set<String> Function(String word)? posOf, List<bool>? breaks, void Function(String rule)? why}) {
  final w = toks[i].lower;
  final cutBefore = breaks != null && breaks[i], cutAfter = breaks != null && breaks[i + 1];
  final prev = i > 0 && !cutBefore ? toks[i - 1].lower : '';
  final next = i + 1 < toks.length && !cutAfter ? toks[i + 1].lower : '';
  // Forms of be / have / do are verbs ("had been" is not the metal beryllium).
  const aux = {
    'be', 'am', 'is', 'are', 'was', 'were', 'been', 'being', 'have', 'has', 'had', 'having',
    'do', 'does', 'did', 'done', 'doing',
  };
  if (aux.contains(w) && availablePos.contains('v')) return _why(why, 'aux', 'v');
  const modal = {'will', 'would', 'can', 'could', 'should', 'must', 'may', 'might', 'shall', "won't", "can't", "couldn't", "wouldn't", "shouldn't"};
  const finite = {...modal, 'is', 'are', 'was', 'were', 'has', 'have', 'had', 'do', 'does', 'did', "isn't", "aren't", "wasn't", "weren't", "don't", "doesn't", "didn't", "hasn't", "haven't"};
  const relative = {'who', 'which', 'that'};
  final nounVerb = availablePos.contains('n') && availablePos.contains('v');
  // A form in "-s" is a plural noun or a verb after he / she / it.
  if (nounVerb && w.endsWith('s') && !w.endsWith('ss')) {
    // After "to" or "can" a verb has no "-s": "to neighbors".
    if (prev == 'to' || modal.contains(prev)) return _why(why, 'sAfterTo', 'n');
    // "the fans were", "her channel has": what comes next is the verb.
    if (finite.contains(next)) return _why(why, 'sBeforeFinite', 'n');
    if (const {'he', 'she', 'it', 'who', 'which'}.contains(prev)) return _why(why, 'sAfterHe', 'v');
    // "property rights, …", "email alerts.": closing a clause right after a
    // noun, it is the plural that ends the noun group.
    if (breaks != null && cutAfter && posOf != null && prev.isNotEmpty && !stopWords.contains(prev) && posOf(prev).contains('n') && !posOf(prev).contains('r')) return _why(why, 'pluralEndsClause', 'n');
  }
  // "that benefit the …", "which causes a …": after a relative pronoun and
  // before an object stands a verb ("that" is no determiner there).
  if (availablePos.contains('v') && relative.contains(prev) && (_det.contains(next) || _objPron.contains(next) || next == 'to' || next == 'that')) return _why(why, 'verbAfterRelative', 'v');
  // "the rates of", "studies of": a word before "of" is a noun, unless it is
  // a verb form ("consisting of", "made of") or follows a subject or "to".
  const subject = {'i', 'you', 'we', 'they', 'he', 'she', 'it', 'who'};
  if (next == 'of' && availablePos.contains('n') && !w.endsWith('ing') && !w.endsWith('ed') && !subject.contains(prev) && !modal.contains(prev) && prev != 'to') {
    return _why(why, 'beforeOf', 'n');
  }
  // "unfortunate circumstances", "heavy rain": a word that can be an
  // adjective, followed by a noun, is an adjective.
  // "a complex one", "the individual Zurbarán paintings": after a determiner
  // and before "one" or a name the dictionary does not know.
  if (availablePos.contains('a') && _det.contains(prev) && posOf != null && !cutAfter && i + 1 < toks.length) {
    final t = toks[i + 1];
    if (next == 'one' || next == 'ones' || (t.text[0] != t.lower[0] && posOf(next).isEmpty)) return _why(why, 'adjBeforeName', 'a');
  }
  if (availablePos.contains('a') && next.isNotEmpty && !stopWords.contains(next) && posOf != null) {
    final np = posOf(next);
    // "the light shines" is noun + verb. That reading needs a verb that fits
    // a noun before it: "shines", "flickered"; in "the general interest" the
    // second word is the noun.
    final verbAfterNoun = np.contains('v') && (next.endsWith('s') || next.endsWith('ed')) && !w.endsWith('s');
    final nounThenVerb = _det.contains(prev) && availablePos.contains('n') && verbAfterNoun;
    if (np.contains('n') && !nounThenVerb) return _why(why, 'adjBeforeNoun', 'a');
  }
  const modals = {
    ...modal, "don't", "doesn't", "didn't", 'not', 'never',
    'i', 'you', 'we', 'they', 'he', 'she', 'it', 'please', "let's"
  };
  const adverbs = {'very', 'too', 'so', 'quite', 'more', 'most', 'rather', 'really', 'extremely', 'less', 'least'};
  const be = {'is', 'are', 'was', 'were', 'be', 'been', 'being', 'seems', 'seemed', 'looks', 'looked', 'became', 'become', 'felt', 'feel'};
  String? pick(List<String> order) {
    for (final p in order) {
      if (availablePos.contains(p)) return p;
    }
    return null;
  }

  if (w.endsWith('ly') && availablePos.contains('r')) return _why(why, 'lyAdverb', 'r');
  // "Further, …", "Later, …": alone before a comma at the start, an adverb.
  if (breaks != null && cutBefore && cutAfter && availablePos.contains('r')) return _why(why, 'aloneAdverb', 'r');
  if (_det.contains(prev)) return _why(why, 'afterDet', pick(['n', 'a', 'v']));
  if (adverbs.contains(prev)) return _why(why, 'afterDegree', pick(['a', 'r', 'v']));
  if (be.contains(prev)) {
    if (w.endsWith('ing') || w.endsWith('ed')) return _why(why, 'participleAfterBe', pick(['v', 'a', 'n']));
    return _why(why, 'afterBe', pick(['a', 'n', 'v']));
  }
  // "do it later.", "take them back,": after an object, closing the clause.
  if (breaks != null && cutAfter && availablePos.contains('r') && !availablePos.contains('v') && _objPron.contains(prev) && i > 1 && !breaks[i - 1]) return _why(why, 'adverbAfterObject', 'r');
  if (modals.contains(prev)) return _why(why, 'afterModal', pick(['v', 'n', 'a']));
  if (prev == 'to' && availablePos.contains('v')) return _why(why, 'afterTo', 'v');
  if (w.endsWith('ing') || w.endsWith('ed')) return _why(why, 'participle', pick(['v', 'a', 'n']));
  // "do it later.", "moving forward,": at the end of a clause after a verb
  // or its object, a word that can be an adverb is one.
  if (breaks != null && cutAfter && availablePos.contains('r') && prev.isNotEmpty && posOf != null && (_objPron.contains(prev) || posOf(prev).contains('v')) && !posOf(prev).contains('a')) {
    return _why(why, 'adverbAfterVerb', 'r');
  }
  if (prev == 'of' || prev == 'in' || prev == 'on' || prev == 'at' || prev == 'with' || prev == 'for') {
    return _why(why, 'afterPrep', pick(['n', 'a', 'v']));
  }
  return null;
}

// Tells [f] which rule of [guessPos] decided, when one did.
String? _why(void Function(String)? f, String tag, String? p) {
  if (p != null) f?.call(tag);
  return p;
}

const stopWords = {
  'the', 'a', 'an', 'and', 'or', 'but', 'of', 'to', 'in', 'on', 'at', 'for', 'with', 'by',
  'is', 'are', 'was', 'were', 'be', 'been', 'it', 'this', 'that', 'he', 'she', 'they', 'we',
  'you', 'i', 'his', 'her', 'their', 'as', 'from', 'not', 'so', 'if', 'than', 'then', 'there',
  'have', 'has', 'had', 'do', 'does', 'did', 'my', 'your', 'its', 'our', 'me', 'him', 'them',
  'one', 'some', 'any', 'all', 'what', 'which', 'who', 'when', 'where', 'how', 'into', 'out', 'up'
};
