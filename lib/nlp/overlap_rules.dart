// Task 5L (research, all OFF by default): structural checks for a phrasal
// verb whose particle may really be a preposition with its own object, and
// for expressions that share words with another expression of the sentence.
// No parser, no model, no network: only the sentence's tokens, the
// dictionary's parts of speech, its own example sentences and the matcher.
// Measured in docs/nlp_engine_research/EXPRESSION_OVERLAP_RESOLVER_5L.md.

import '../data/dict_db.dart';
import 'text.dart';

/// Which of the 5L checks run (each one can be measured alone).
///  * [copulaObject] (A): "be" + particle ("be on") is read word by word when
///    the particle has its own noun phrase ("was on the bridge", "was on
///    hand"); not for a time phrase ("was on all night"), and only when the
///    expression's checked senses never give the particle an object in their
///    own examples ("be after the money" keeps its meaning).
///  * [senseFrame] (A2): an expression sense whose own dictionary examples
///    always leave the particle without an object ("the match is on
///    tonight") loses to the word-by-word reading when the sentence gives
///    the particle a noun phrase. Any phrasal verb, by its examples.
///  * [prepPhraseTakesParticle] (B): a two-word phrasal verb whose particle
///    starts another expression of the sentence that is not a phrasal verb
///    ("be on" + "on hand", "put on" + "on hold") is read word by word.
///  * [sharedNotSure] (C): an expression that shares a word with another
///    expression of the sentence (neither holding the other) is never sure.
///  * [copulaNeverSure] (D): "be" + particle is never sure.
class OverlapRules {
  final bool copulaObject, senseFrame, prepPhraseTakesParticle, sharedNotSure, copulaNeverSure;
  const OverlapRules({
    this.copulaObject = false,
    this.senseFrame = false,
    this.prepPhraseTakesParticle = false,
    this.sharedNotSure = false,
    this.copulaNeverSure = false,
  });

  static const none = OverlapRules();

  bool get any => copulaObject || senseFrame || prepPhraseTakesParticle || sharedNotSure || copulaNeverSure;

  /// Part of the sense cache key.
  String get key => [
        if (copulaObject) 'A',
        if (senseFrame) 'A2',
        if (prepPhraseTakesParticle) 'B',
        if (sharedNotSure) 'C',
        if (copulaNeverSure) 'D',
      ].join();

  /// By name, for the research harness ("A", "A+B", "B+C" ...).
  static OverlapRules parse(String s) {
    final p = s.toUpperCase().split(RegExp(r'[+,\s]+')).toSet();
    return OverlapRules(
      copulaObject: p.contains('A'),
      senseFrame: p.contains('A2'),
      prepPhraseTakesParticle: p.contains('B'),
      sharedNotSure: p.contains('C'),
      copulaNeverSure: p.contains('D'),
    );
  }
}

const _copula = {'be'};
const _gapAdverbs = {'still', 'already', 'now', 'not', "n't", 'never', 'always', 'just', 'also', 'all', 'often', 'usually', 'again', 'back'};

const _npDets = {
  'a', 'an', 'the', 'my', 'your', 'his', 'her', 'its', 'our', 'their', 'this', 'that', 'these', 'those', 'some', 'any',
  'no', 'every', 'each', 'another', 'all', 'both', 'one', 'two', 'three', 'four', 'five', 'many', 'much', 'several',
  'last', 'next', 'whole',
};
const _objPronouns = {'me', 'you', 'him', 'her', 'us', 'them', 'it', 'myself', 'yourself', 'himself', 'herself', 'itself', 'ourselves', 'themselves', 'something', 'someone', 'somebody', 'anything', 'everything', 'nothing'};

/// Time units: "all night", "every day", "this morning" are adverbials of
/// time, not the particle's object. A closed class of the language, not of
/// any sentence.
const _timeNouns = {
  'night', 'nights', 'day', 'days', 'morning', 'mornings', 'evening', 'evenings', 'afternoon', 'afternoons', 'week', 'weeks',
  'weekend', 'weekends', 'month', 'months', 'year', 'years', 'hour', 'hours', 'minute', 'minutes', 'time', 'times', 'season',
  'summer', 'winter', 'spring', 'autumn', 'fall', 'term', 'semester', 'tonight', 'today', 'long', 'while',
};
const _durationDets = {'all', 'every', 'each', 'this', 'that', 'last', 'next', 'whole', 'the'};

/// Whether a noun phrase starts at token [k] (the particle's own object):
/// a determiner, an object pronoun, a number, a name inside the sentence, or
/// a word the dictionary knows as a noun that is not a grammar word.
bool npStartsAt(DictDb dict, List<Token> toks, int k, List<bool>? breaks) {
  if (k >= toks.length || (breaks != null && breaks[k])) return false;
  final t = toks[k];
  final w = t.lower;
  if (!RegExp(r"[a-z0-9]").hasMatch(w)) return false;
  if (_npDets.contains(w) || _objPronouns.contains(w)) return true;
  if (RegExp(r'^\d').hasMatch(w)) return true;
  if (stopWords.contains(w)) return false;
  if (w.endsWith('ly')) return false;
  if (t.text.isNotEmpty && t.text[0] != t.text[0].toLowerCase()) return true;
  final p = dict.posOf(w);
  return p.contains('n') && !p.contains('r');
}

/// Whether the noun phrase at [k] is a time adverbial ("all night", "this
/// morning", "every day") rather than an object.
bool timePhraseAt(List<Token> toks, int k) {
  if (k >= toks.length) return false;
  final w = toks[k].lower;
  if (w == 'tonight' || w == 'today' || w == 'now') return true;
  if (!_durationDets.contains(w)) return false;
  for (var j = k + 1; j < toks.length && j <= k + 3; j++) {
    final x = toks[j].lower;
    if (_timeNouns.contains(x)) return true;
    if (!RegExp(r'^[a-z]+$').hasMatch(x) || stopWords.contains(x)) return false;
  }
  return false;
}

/// Whether the particle at token [p] of a phrasal verb has its own object.
bool particleHasObject(DictDb dict, List<Token> toks, int p, List<bool>? breaks) =>
    npStartsAt(dict, toks, p + 1, breaks) && !timePhraseAt(toks, p + 1);

/// Whether "be" + particle ("be on", "be after").
bool isCopulaParticle(Expr e) => e.cat == 'phrasal_verbs' && e.pattern.length == 2 && _copula.contains(e.pattern.first);

/// [senseFrame]: whether every example of an expression sense leaves the
/// particle without an object. Null when the examples do not show it (fewer
/// than one example holding the verb and the particle).
bool? strandedOnly(DictDb dict, Expr e, List<String> examples) {
  if (e.pattern.length != 2) return null;
  final verb = e.pattern.first, part = e.pattern.last;
  var seen = 0;
  for (final ex in examples) {
    final t = tokenize(ex);
    final br = clauseBreaks(ex, t);
    for (var i = 0; i < t.length; i++) {
      if (!(t[i].lower == verb || dict.lemmatizer.lemmas(t[i].lower).contains(verb))) continue;
      for (var k = i + 1; k < t.length && k <= i + 4; k++) {
        if (t[k].lower != part) continue;
        // "is the match on tonight?": words between "be" and its particle are
        // its subject (a question), not an object; that use shows nothing.
        // "is currently on", "was still on": adverbs in between are no object.
        final gap = [for (var j = i + 1; j < k; j++) t[j].lower];
        final adverbs = gap.every((w) => w.endsWith('ly') || _gapAdverbs.contains(w));
        if (!adverbs && _copula.contains(verb)) break;
        seen++;
        // an object between verb and particle, or after the particle
        if (!adverbs || particleHasObject(dict, t, k, br)) return false;
        break;
      }
    }
  }
  return seen >= 1 ? true : null;
}

/// Whether the expression's checked senses (no AI draft) all leave the
/// particle without an object in their own examples (at least one shows it).
bool checkedSensesStranded(DictDb dict, Expr e, Iterable<({List<String> examples, bool draft})> senses) {
  var any = false;
  for (final s in senses) {
    if (s.draft) continue;
    final v = strandedOnly(dict, e, s.examples);
    if (v == false) return false;
    if (v == true) any = true;
  }
  return any;
}
