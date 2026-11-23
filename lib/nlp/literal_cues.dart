// Task 5G: signs in a sentence that a matched idiom is meant word by word.
//
// Each cue is a general rule about how idioms behave (no word lists of
// particular idioms): an idiom keeps its form (Fazly, Cook & Stevenson 2009:
// idioms are lexically and syntactically fixed; literal phrases vary their
// determiner and number freely), and a literal phrase goes on into a longer
// noun group ("oil and water levels", "in the raw water"). The cues are read
// by [SenseEngine] only when its `literalCues` switch is on.
import '../data/dict_db.dart';
import 'text.dart';

/// What the sentence says about a matched expression, one flag per cue
/// (tests and measurements read them all; the engine reads [LiteralCues.cue]).
class LiteralCues {
  /// The dictionary form has "a"/"an"/"the" and the sentence another
  /// determiner there ("have his ball" for "have a ball").
  final bool determiner;

  /// A noun of the dictionary form in the other number ("show their legs"
  /// for "show a leg", "for the songs").
  final bool number;

  /// The expression's last noun goes on into a longer noun group in the same
  /// clause ("oil and water levels", "a bucket of water").
  final bool nounGoesOn;

  /// "literal", "literally" or "real" right before ("a literal case of …").
  final bool literalWord;

  /// Talked about as words: "the phrase …", "the idiom …", or the expression
  /// in quotes. Not a sign of a literal reading, but of none at all.
  final bool mention;

  const LiteralCues({
    this.determiner = false,
    this.number = false,
    this.nounGoesOn = false,
    this.literalWord = false,
    this.mention = false,
  });

  Map<String, bool> toJson() => {
        'determiner': determiner,
        'number': number,
        'nounGoesOn': nounGoesOn,
        'literalWord': literalWord,
        'mention': mention,
      };

  static const none = LiteralCues();
}

const _articles = {'a', 'an', 'the'};
const _detLike = {
  'a', 'an', 'the', 'my', 'your', 'his', 'her', 'its', 'our', 'their', 'this', 'that', 'these', 'those', 'some', 'any',
  'no', 'every', 'each', "one's", "someone's",
};
const _mentionNouns = {'phrase', 'expression', 'idiom', 'saying', 'term', 'cliché', 'cliche', 'proverb', 'motto', 'slogan'};
const _literalWords = {'literal', 'literally'};
const _quotes = {'"', '“', '”', '‘', '’', "'"};

/// The cues for [e] matched on token indexes [idx] of [toks] in [sentence].
LiteralCues literalCuesOf(DictDb dict, Expr e, List<Token> toks, List<int> idx, String sentence) {
  if (idx.isEmpty || e.cat == 'phrasal_verbs') return LiteralCues.none;
  final pat = e.pattern;
  // The pattern words matched one to one (patterns with "sb"/"sth" gaps are
  // matched with a gap, so only their words before the first gap are lined up).
  final fixed = [for (final p in pat) if (!placeholderWords.contains(p) && p != 'someone' && p != 'something') p];
  final aligned = fixed.length == idx.length && fixed.length == pat.length;
  var determiner = false, number = false;
  if (aligned) {
    for (var k = 0; k < pat.length; k++) {
      final p = pat[k], t = toks[idx[k]].lower;
      if (_articles.contains(p)) {
        final same = t == p || ({'a', 'an'}.contains(p) && {'a', 'an'}.contains(t));
        if (!same && _detLike.contains(t)) determiner = true;
        continue;
      }
      if (k == 0 || stopWords.contains(p) || t == p) continue;
      // The other number of a noun: only a word that follows a determiner or
      // an adjective-like word in the pattern, or ends a noun pair, is a noun
      // here (the first word of most idioms is a verb, whose forms vary).
      final prev = pat[k - 1];
      final nounSlot = _articles.contains(prev) || _detLike.contains(prev) || prev == 'and' || prev == 'or' || dict.posOf(prev).contains('a');
      if (!nounSlot || !dict.posOf(p).contains('n')) continue;
      if (_plural(t, p) || _plural(p, t)) number = true;
    }
  }
  final first = idx.reduce((a, b) => a < b ? a : b), last = idx.reduce((a, b) => a > b ? a : b);
  // The noun group goes on: the word after the expression, in the same clause.
  var nounGoesOn = false;
  final breaks = clauseBreaks(sentence, toks);
  if (last + 1 < toks.length && !(breaks != null && breaks[last + 1])) {
    final lw = toks[last].lower, next = toks[last + 1].lower;
    final lp = dict.posOf(lw);
    if (!stopWords.contains(lw) && (lp.contains('n') || lp.contains('a'))) {
      if (next == 'of') {
        nounGoesOn = true;
      } else if (!stopWords.contains(next) && !next.endsWith('ing') && !next.endsWith('ed') && !next.endsWith('ly') && !next.contains("'")) {
        final np = dict.posOf(next);
        nounGoesOn = np.contains('n') && !np.contains('v') && !np.contains('r') && !np.contains('a');
      }
    }
  }
  var literalWord = false, mention = false;
  for (var i = first - 1; i >= 0 && i >= first - 3; i--) {
    final w = toks[i].lower;
    if (_literalWords.contains(w)) literalWord = true;
    if (_mentionNouns.contains(w)) mention = true;
  }
  // In quotes: a quote mark right before the first word and right after the last.
  if (!mention) {
    final before = sentence.substring(0, toks[first].start).trimRight();
    final after = sentence.substring(toks[last].end).trimLeft();
    if (before.isNotEmpty && after.isNotEmpty && _quotes.contains(before[before.length - 1]) && _quotes.contains(after[0])) {
      // "'s" after the last word is not a closing quote.
      if (!(after.startsWith("'s") || after.startsWith('’s'))) mention = true;
    }
  }
  return LiteralCues(determiner: determiner, number: number, nounGoesOn: nounGoesOn, literalWord: literalWord, mention: mention);
}

/// Whether [a] is a plural form of [b] ("legs" of "leg", "boxes" of "box",
/// "berries" of "berry"); irregular plurals are left out.
bool _plural(String a, String b) {
  if (a.length <= b.length || b.endsWith('s')) return false;
  if (a == '${b}s' || a == '${b}es') return true;
  return b.endsWith('y') && a == '${b.substring(0, b.length - 1)}ies';
}
