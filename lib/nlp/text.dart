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

final RegExp _wordRe = RegExp(r"[A-Za-z]+(?:['’][A-Za-z]+)*(?:-[A-Za-z]+)*");

List<Token> tokenize(String text) => [
      for (final m in _wordRe.allMatches(text)) Token(m.start, m.end, m.group(0)!)
    ];

/// Splits a paragraph into sentences; returns [start, end) ranges.
List<(int, int)> sentenceRanges(String text) {
  final out = <(int, int)>[];
  final re = RegExp(r'[^.!?…]+(?:[.!?…]+["”’)\]]*|$)');
  for (final m in re.allMatches(text)) {
    if (m.group(0)!.trim().isEmpty) continue;
    out.add((m.start, m.end));
  }
  if (out.isEmpty) out.add((0, text.length));
  return out;
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

  /// Turkish meaning / explanation made by the user's AI service (saved on device).
  String? aiTr;
  String? aiExp;
  Expr(this.id, this.phrase, this.cat, this.tr, this.en, this.pattern, {this.ex, this.enTr});

  /// Turkish meaning: from the dictionary, otherwise from the AI translation.
  String? get trShown => tr ?? aiTr;

  /// Whether the AI still has something to translate for this entry.
  bool get needsAi => tr == null && aiTr == null && en != null;
}

class Match {
  final Expr expr;
  final List<int> tokens; // token indexes that belong to the expression
  Match(this.expr, this.tokens);
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

  bool _tokMatches(String p, Token t) {
    if (p == t.lower) return true;
    if (p == "one's") return _poss.contains(t.lower);
    if (p == 'oneself') return _reflexive.contains(t.lower);
    if (p == 'a' || p == 'an' || p == 'the') return _det.contains(t.lower);
    return lem.lemmas(t.lower).contains(p);
  }

  /// Returns the token indexes matched, or null.
  List<int>? _matchAt(Expr e, List<Token> toks, int i) {
    final pat = e.pattern;
    final idx = <int>[];
    var j = i;
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
      if (_tokMatches(p, toks[j])) {
        idx.add(j);
        j++;
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

  List<Match> match(List<Token> toks) {
    final out = <Match>[];
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
          if (m != null) out.add(Match(e, m));
        }
      }
      for (final e in _byForm[t.lower] ?? const <Expr>[]) {
        out.add(Match(e, [i]));
      }
    }
    return out;
  }
}

List<String> patternOf(String phrase) => tokenize(phrase).map((t) => t.lower).toList();

/// Very small part-of-speech guesser used to pick the right dictionary sense.
String? guessPos(List<Token> toks, int i, Set<String> availablePos, {Set<String> Function(String word)? posOf}) {
  final w = toks[i].lower;
  final prev = i > 0 ? toks[i - 1].lower : '';
  final next = i + 1 < toks.length ? toks[i + 1].lower : '';
  // Forms of be / have / do are verbs ("had been" is not the metal beryllium).
  const aux = {
    'be', 'am', 'is', 'are', 'was', 'were', 'been', 'being', 'have', 'has', 'had', 'having',
    'do', 'does', 'did', 'done', 'doing',
  };
  if (aux.contains(w) && availablePos.contains('v')) return 'v';
  // "unfortunate circumstances", "heavy rain": a word that can be an
  // adjective, followed by a noun, is an adjective.
  if (availablePos.contains('a') && next.isNotEmpty && !stopWords.contains(next) && posOf != null) {
    final np = posOf(next);
    // "the light shines" is ambiguous (noun + verb), so only when that reading is impossible.
    final nounThenVerb = _det.contains(prev) && availablePos.contains('n') && np.contains('v');
    if (np.contains('n') && !nounThenVerb) return 'a';
  }
  const modals = {
    'will', 'would', 'can', 'could', 'should', 'must', 'may', 'might', 'shall',
    "don't", "doesn't", "didn't", "won't", "can't", "couldn't", "wouldn't", 'not', 'never',
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

  if (w.endsWith('ly') && availablePos.contains('r')) return 'r';
  if (_det.contains(prev)) return pick(['n', 'a', 'v']);
  if (adverbs.contains(prev)) return pick(['a', 'r', 'v']);
  if (be.contains(prev)) {
    if (w.endsWith('ing') || w.endsWith('ed')) return pick(['v', 'a', 'n']);
    return pick(['a', 'n', 'v']);
  }
  if (modals.contains(prev)) return pick(['v', 'n', 'a']);
  if (prev == 'to' && availablePos.contains('v')) return 'v';
  if (w.endsWith('ing') || w.endsWith('ed')) return pick(['v', 'a', 'n']);
  if (prev == 'of' || prev == 'in' || prev == 'on' || prev == 'at' || prev == 'with' || prev == 'for') {
    return pick(['n', 'a', 'v']);
  }
  return null;
}

const stopWords = {
  'the', 'a', 'an', 'and', 'or', 'but', 'of', 'to', 'in', 'on', 'at', 'for', 'with', 'by',
  'is', 'are', 'was', 'were', 'be', 'been', 'it', 'this', 'that', 'he', 'she', 'they', 'we',
  'you', 'i', 'his', 'her', 'their', 'as', 'from', 'not', 'so', 'if', 'than', 'then', 'there',
  'have', 'has', 'had', 'do', 'does', 'did', 'my', 'your', 'its', 'our', 'me', 'him', 'them',
  'one', 'some', 'any', 'all', 'what', 'which', 'who', 'when', 'where', 'how', 'into', 'out', 'up'
};
