// Task 5M (research prototype, OFF by default; nothing in the app calls it):
// one shallow parse per sentence and dictionary expressions compiled to
// syntactic templates, matched against that one parse.
//
// Why: PhraseMatcher (text.dart) matches word sequences, so every variant of an
// expression ("make a quick decision", "the decision was made", "turn the
// kitchen light off") needs its own rule, and a possessive slot ("waste one's
// time") is reported as a word of the expression. Here the sentence is parsed
// once into parts of speech and noun phrases, and an expression is a template
// of constituents (verb, noun phrase with its head and determiner policy,
// particle, preposition, open slot). All templates match the same parse.
//
// Small and offline: no model, no network, no new dependency. Parts of speech
// come from the dictionary (DictDb.posOf) and closed word classes.
// Measured in docs/nlp_engine_research/SENTENCE_PARSER_TEMPLATES_5M.md.

import 'dart:math';

import '../data/dict_db.dart';
import 'text.dart';

/// Coarse part of speech of a token in the sentence.
enum Tag { det, poss, pron, noun, verb, adj, adv, prep, conj, aux, num, punct, other }

const _dets = {'a', 'an', 'the', 'this', 'that', 'these', 'those', 'some', 'any', 'no', 'every', 'each', 'another', 'such'};
const _possW = {'my', 'your', 'his', 'her', 'its', 'our', 'their'};
const _prons = {
  'i', 'you', 'he', 'she', 'it', 'we', 'they', 'me', 'him', 'us', 'them', 'myself', 'yourself', 'himself', 'herself',
  'itself', 'ourselves', 'themselves', 'someone', 'somebody', 'something', 'anyone', 'anything', 'everyone', 'everything',
  'nobody', 'nothing', 'one', 'who', 'what', 'which', 'mine', 'yours', 'hers', 'ours', 'theirs',
};
const _preps = {
  'of', 'in', 'on', 'at', 'to', 'for', 'with', 'by', 'from', 'into', 'onto', 'about', 'over', 'under', 'after', 'before',
  'through', 'between', 'among', 'against', 'during', 'without', 'within', 'around', 'up', 'down', 'out', 'off', 'away',
  'back', 'across', 'along', 'behind', 'beyond', 'near', 'past', 'since', 'until', 'toward', 'towards', 'upon', 'like',
};
const _conjs = {'and', 'or', 'but', 'nor', 'so', 'yet', 'because', 'if', 'when', 'while', 'although', 'though', 'than', 'as', 'that', 'whether', 'unless'};
const _auxs = {
  'be', 'am', 'is', 'are', 'was', 'were', 'been', 'being', "'s", "'re", "'m", 'have', 'has', 'had', "'ve", "'d", 'do', 'does',
  'did', 'will', 'would', "'ll", 'can', 'could', 'may', 'might', 'shall', 'should', 'must', 'not', "n't", 'to',
};
const _beForms = {'be', 'am', 'is', 'are', 'was', 'were', 'been', 'being', "'s", "'re", "'m", 'get', 'gets', 'got', 'gotten', 'getting'};

/// The one parse of a sentence that every template is matched against.
class SentenceParse {
  final List<Token> toks;
  final List<Tag> tags;

  /// For a token that starts a noun phrase: the phrase's end (exclusive) and
  /// head index; -1 elsewhere.
  final List<int> npEnd, npHead;

  /// A clause mark (comma, full stop …) stands right before the token.
  final List<bool> breaks;
  SentenceParse(this.toks, this.tags, this.npEnd, this.npHead, this.breaks);

  /// The noun phrase that starts at [i] has a determiner or possessive.
  bool npHasDet(int i) => tags[i] == Tag.det || tags[i] == Tag.poss || toks[i].lower.endsWith("'s");
}

class ConstructionParser {
  final DictDb dict;
  ConstructionParser(this.dict);

  Set<String> _pos(String w) => dict.posOf(w);

  Tag _lexTag(List<Token> toks, int i, List<Tag> before) {
    final prev = i == 0 ? null : before[i - 1];
    final t = toks[i];
    final w = t.lower;
    if (!RegExp(r'[a-z0-9]').hasMatch(w)) return Tag.punct;
    if (RegExp(r'^\d').hasMatch(w)) return Tag.num;
    if (_possW.contains(w)) return w == 'her' && (i + 1 >= toks.length || !_nounish(toks[i + 1].lower)) ? Tag.pron : Tag.poss;
    if (_dets.contains(w)) {
      // "that" / "this" as a pronoun or a conjunction when no noun follows
      if ((w == 'that' || w == 'this') && (i + 1 >= toks.length || !_nounish(toks[i + 1].lower))) {
        return w == 'that' ? Tag.conj : Tag.pron;
      }
      return Tag.det;
    }
    if (_prons.contains(w)) return Tag.pron;
    if (_auxs.contains(w)) return Tag.aux;
    if (_conjs.contains(w)) return Tag.conj;
    if (_preps.contains(w)) return Tag.prep;
    final p = _pos(w);
    final cap = i > 0 && t.text.isNotEmpty && t.text[0] != t.text[0].toLowerCase();
    if (p.isEmpty) return cap ? Tag.noun : (w.endsWith('ly') ? Tag.adv : Tag.noun);
    final afterNominal = prev == Tag.det || prev == Tag.poss || prev == Tag.adj || prev == Tag.num;
    if (afterNominal) {
      if (p.contains('a') && i + 1 < toks.length && _nounish(toks[i + 1].lower) && !_preps.contains(toks[i + 1].lower)) return Tag.adj;
      if (p.contains('n')) return Tag.noun;
      if (p.contains('a')) return Tag.adj;
      if (w.endsWith('ing') || w.endsWith('ed')) return Tag.adj;
    }
    if (prev == Tag.aux || prev == Tag.pron) {
      if (p.contains('v')) return Tag.verb;
    }
    if (w.endsWith('ly') && p.contains('r')) return Tag.adv;
    if (p.length == 1) {
      switch (p.first) {
        case 'n':
          return Tag.noun;
        case 'v':
          return Tag.verb;
        case 'a':
          return Tag.adj;
        case 'r':
          return Tag.adv;
      }
    }
    // "the kitchen light off": a noun after determiner + noun, before a particle, a preposition or the
    // clause end, is the head of the same noun phrase (a verb would be "-s" / "-ed" or take an object)
    if (prev == Tag.noun && p.contains('n') && i >= 2 && const {Tag.det, Tag.poss, Tag.adj}.contains(before[i - 2]) &&
        !w.endsWith('s') && !w.endsWith('ed') &&
        (i + 1 >= toks.length || _preps.contains(toks[i + 1].lower) || !RegExp(r'[a-z0-9]').hasMatch(toks[i + 1].lower))) {
      return Tag.noun;
    }
    if (p.contains('v') && (prev == Tag.noun || prev == null || prev == Tag.adv)) return Tag.verb;
    if (p.contains('n')) return Tag.noun;
    if (p.contains('v')) return Tag.verb;
    if (p.contains('a')) return Tag.adj;
    return Tag.other;
  }

  bool _nounish(String w) {
    if (!RegExp(r'^[a-z0-9]').hasMatch(w) || _preps.contains(w) || _conjs.contains(w) || _auxs.contains(w)) return false;
    final p = _pos(w);
    return p.isEmpty || p.contains('n') || p.contains('a');
  }

  SentenceParse parse(String sentence, List<Token> toks) {
    final tags = <Tag>[];
    for (var i = 0; i < toks.length; i++) {
      tags.add(_lexTag(toks, i, tags));
    }
    final br = clauseBreaks(sentence, toks) ?? List.filled(toks.length + 1, false);
    final npEnd = List.filled(toks.length, -1), npHead = List.filled(toks.length, -1);
    for (var i = 0; i < toks.length; i++) {
      if (tags[i] == Tag.pron) {
        npEnd[i] = i + 1;
        npHead[i] = i;
        continue;
      }
      var j = i;
      if (tags[j] == Tag.det || tags[j] == Tag.poss || toks[j].lower.endsWith("'s")) j++;
      if (j < toks.length && tags[j] == Tag.num) j++;
      var head = -1;
      while (j < toks.length && (j == i || !br[j])) {
        final g = tags[j];
        if (g == Tag.adv && j + 1 < toks.length && tags[j + 1] == Tag.adj) {
          j++;
          continue;
        }
        if (g == Tag.adj || g == Tag.noun || (g == Tag.verb && j > i && (toks[j].lower.endsWith('ed') || toks[j].lower.endsWith('ing')) && j + 1 < toks.length && tags[j + 1] == Tag.noun)) {
          if (g == Tag.noun) head = j;
          j++;
          continue;
        }
        break;
      }
      if (head >= 0) {
        npEnd[i] = head + 1;
        npHead[i] = head;
      }
    }
    return SentenceParse(toks, tags, npEnd, npHead, br);
  }
}

/// One constituent of a template.
sealed class Part {}

/// A word matched by its base form ("take", "by"). [verb]: may be passive.
class Lex extends Part {
  final String word;
  Lex(this.word);
}

/// A noun phrase with a fixed head ("a decision", "one's temper", "the time").
/// [det]: the dictionary writes a determiner ("a", "the": any determiner or
/// possessive) or a possessive slot ("one's": possessive only); [literalDet]:
/// the written determiner is part of the expression (reported as its token);
/// [mods]: modifiers the dictionary writes ("a good job"), which must be there.
class NounPhrase extends Part {
  final String head;
  final String? det; // null | 'det' | 'poss'
  final String? literalDet;
  final List<String> mods;

  /// Idioms are frozen: the written determiner must be the same one ("ring a
  /// bell", not "ring the little bell") and no other modifier may come in.
  final bool frozen;
  NounPhrase(this.head, this.det, this.literalDet, this.mods, {this.frozen = false});
}

/// An open slot ("sb", "sth"): any noun phrase; never reported as a word of the expression.
class Slot extends Part {}

/// An expression as a sequence of constituents.
class Template {
  final Expr expr;
  final List<Part> parts;
  Template(this.expr, this.parts);

  bool get hasNounPhrase => parts.any((p) => p is NounPhrase);
}

/// Compiles dictionary expressions into templates. Only expressions with a
/// noun phrase whose shape can vary (a determiner, a possessive slot or a
/// modifier, or a verb before it) get a template; the rest keep the sequence
/// matcher, which is already exact for them.
class TemplateCompiler {
  final DictDb dict;
  TemplateCompiler(this.dict);

  static const _cats = {'idioms', 'collocations', 'phrasal_verbs', 'chunks'};

  Template? compile(Expr e) {
    if (!_cats.contains(e.cat)) return null;
    final w = e.pattern;
    if (w.length < 2 || w.length > 7) return null;
    if (w.any((x) => !RegExp(r"^[a-z']+$").hasMatch(x))) return null;
    final parts = <Part>[];
    var i = 0;
    var npCount = 0;
    while (i < w.length) {
      final x = w[i];
      if (x == 'sb' || x == 'sth' || x == 'someone' || x == 'something') {
        parts.add(Slot());
        i++;
        continue;
      }
      // A noun phrase: [det | possessive slot] modifier* noun
      String? det, literalDet;
      var j = i;
      if (x == 'a' || x == 'an' || x == 'the') {
        det = 'det';
        literalDet = x;
        j++;
      } else if (x == "one's" || x == "someone's") {
        det = 'poss';
        j++;
      }
      final mods = <String>[];
      var head = -1;
      for (var k = j; k < w.length && k < j + 3; k++) {
        final p = dict.posOf(w[k]);
        if (stopWords.contains(w[k]) || _preps.contains(w[k])) break;
        if (p.contains('n')) {
          head = k;
          // the noun phrase ends at its last noun, before a preposition or the end
          if (k + 1 >= w.length || !dict.posOf(w[k + 1]).contains('n') || stopWords.contains(w[k + 1]) || _preps.contains(w[k + 1])) break;
        } else if (p.contains('a')) {
          continue;
        } else {
          break;
        }
      }
      // A determiner-led noun phrase, or a bare noun right after the verb
      // (the first word) of an expression whose first word is a verb.
      final bareAfterVerb = det == null && i == 1 && dict.posOf(w[0]).contains('v') && head == i;
      if (head >= 0 && (det != null || bareAfterVerb)) {
        for (var k = j; k < head; k++) {
          mods.add(w[k]);
        }
        parts.add(NounPhrase(w[head], det, literalDet, mods, frozen: e.cat == 'idioms'));
        npCount++;
        i = head + 1;
        continue;
      }
      parts.add(Lex(x));
      i++;
    }
    if (npCount == 0) return null;
    final v = (parts.first is Lex) ? (parts.first as Lex).word : '';
    // a base-form verb first ("relaxed atmosphere" is an adjective + noun)
    if (v.isEmpty || v.endsWith('ed') || v.endsWith('ing') || !dict.posOf(v).contains('v')) return null;
    return Template(e, parts);
  }
}

/// A template match: the expression's own words (slot fillers left out) and
/// how the sentence differs from the dictionary form.
class TemplateMatch {
  final Expr expr;
  final List<int> tokens;
  final String variant; // 'exact' | 'np' (determiner / modifier / possessive) | 'passive'
  TemplateMatch(this.expr, this.tokens, this.variant);
}

class TemplateMatcher {
  final DictDb dict;
  final List<Template> templates = [];
  final Map<String, List<Template>> _byWord = {};

  /// Two-word phrasal verbs by verb ("turn" -> turn off, turn on …), for the
  /// object-in-between form on the parse ("turn the kitchen light off").
  final Map<String, List<Expr>> _pv2 = {};

  TemplateMatcher(this.dict, Iterable<Expr> exprs) {
    final c = TemplateCompiler(dict);
    for (final e in exprs) {
      if (e.cat == 'phrasal_verbs' && e.pattern.length == 2 && _sepParticles.contains(e.pattern[1]) && e.pattern[0] != 'be') {
        _pv2.putIfAbsent(e.pattern[0], () => []).add(e);
      }
      final t = c.compile(e);
      if (t == null) continue;
      templates.add(t);
      final first = (t.parts.first as Lex).word;
      _byWord.putIfAbsent(first, () => []).add(t);
      final np = t.parts.whereType<NounPhrase>().first;
      _byWord.putIfAbsent('np:${np.head}', () => []).add(t);
    }
  }

  bool _is(Token t, String base) => t.lower == base || dict.lemmatizer.lemmas(t.lower).contains(base);

  /// Matches the noun phrase constituent at [k]; returns (end, tokens) or null.
  (int, List<int>)? _np(SentenceParse s, NounPhrase np, int k, List<String> how) {
    if (k >= s.toks.length || s.npEnd[k] < 0) return null;
    final end = s.npEnd[k], head = s.npHead[k];
    if (!_is(s.toks[head], np.head)) return null;
    final hasDet = s.npHasDet(k);
    if (np.det == null && hasDet) return null; // "take place" is not "take the place"
    if (np.det == 'det' && !hasDet) return null;
    if (np.det == 'poss' && !(s.tags[k] == Tag.poss || s.toks[k].lower.endsWith("'s"))) return null;
    final toks = <int>[];
    if (np.literalDet != null) {
      final d = s.toks[k].lower;
      if (np.frozen && !(d == np.literalDet || (np.literalDet == 'a' && d == 'an') || (np.literalDet == 'an' && d == 'a'))) return null;
      toks.add(k);
      if (s.toks[k].lower != np.literalDet && !(np.literalDet == 'a' && s.toks[k].lower == 'an')) how.add('np');
    }
    final first = hasDet ? k + 1 : k;
    for (final m in np.mods) {
      var found = -1;
      for (var x = first; x < head; x++) {
        if (_is(s.toks[x], m)) found = x;
      }
      if (found < 0) return null;
      toks.add(found);
    }
    // other modifiers ("a quick decision") are allowed when the dictionary writes a determiner
    final extra = head - first - np.mods.length;
    if (extra > 0) {
      if (np.det == null || np.frozen) return null;
      how.add('np');
    }
    if (np.det == 'poss') how.add('np');
    toks.add(head);
    return (end, toks);
  }

  List<int>? _matchFrom(SentenceParse s, Template t, int i, List<String> how) {
    final out = <int>[];
    var j = i;
    for (var p = 0; p < t.parts.length; p++) {
      final part = t.parts[p];
      if (j >= s.toks.length) return null;
      if (p > 0 && s.breaks[j]) return null;
      switch (part) {
        case Lex(:final word):
          if (!_is(s.toks[j], word)) {
            // one adverb may stand after the verb ("make really good money")
            if (p == 1 && s.tags[j] == Tag.adv && j + 1 < s.toks.length && _is(s.toks[j + 1], word)) {
              j++;
            } else {
              return null;
            }
          }
          out.add(j);
          j++;
        case NounPhrase():
          var r = _np(s, part, j, how);
          if (r == null && p == 1 && s.tags[j] == Tag.adv) {
            r = _np(s, part, j + 1, how);
          }
          if (r == null) return null;
          out.addAll(r.$2);
          j = r.$1;
        case Slot():
          if (s.npEnd[j] < 0) return null;
          j = s.npEnd[j];
      }
    }
    return out;
  }

  /// Passive of a verb + noun phrase template ("the decision was made",
  /// "strings were pulled"): the noun phrase, a form of "be" / "get", an
  /// optional adverb, the verb, then the rest of the template in order.
  List<int>? _passive(SentenceParse s, Template t, int k, List<String> how) {
    if (t.parts.length < 2 || t.parts[1] is! NounPhrase || t.expr.cat == 'phrasal_verbs') return null;
    final np = t.parts[1] as NounPhrase;
    if (np.det == 'poss') return null;
    final r = _np(s, NounPhrase(np.head, np.det ?? 'any', np.literalDet, np.mods, frozen: np.frozen), k, how);
    if (r == null) return null;
    var j = r.$1;
    if (j >= s.toks.length || !_beForms.contains(s.toks[j].lower)) return null;
    j++;
    if (j < s.toks.length && s.tags[j] == Tag.adv) j++;
    if (j >= s.toks.length) return null;
    final v = s.toks[j].lower;
    if (!(v.endsWith('ed') || v.endsWith('en') || !dict.lemmatizer.lemmas(v).contains(v))) return null;
    if (!_is(s.toks[j], (t.parts.first as Lex).word)) return null;
    final out = [...r.$2, j];
    var x = j + 1;
    for (var p = 2; p < t.parts.length; p++) {
      final part = t.parts[p];
      if (x >= s.toks.length || s.breaks[x]) return null;
      if (part is Lex) {
        if (!_is(s.toks[x], part.word)) return null;
        out.add(x);
        x++;
      } else if (part is NounPhrase) {
        final q = _np(s, part, x, how);
        if (q == null) return null;
        out.addAll(q.$2);
        x = q.$1;
      } else {
        if (s.npEnd[x] < 0) return null;
        x = s.npEnd[x];
      }
    }
    how.add('passive');
    return out..sort();
  }

  static const _sepParticles = {'up', 'down', 'off', 'out', 'away', 'back', 'on', 'over', 'in', 'around', 'about'};
  static const _closers = {
    'and', 'but', 'or', 'then', 'again', 'now', 'too', 'first', 'before', 'after', 'when', 'while', 'because', 'so',
    'until', 'till', 'if', 'unless', 'once', 'as', 'soon', 'later', 'today', 'tonight', 'tomorrow', 'please',
  };

  /// Verb, a whole noun phrase as its object (any length, not a pronoun: the
  /// sequence matcher has those), then the particle closing the clause.
  void _separable(SentenceParse s, int i, List<TemplateMatch> out) {
    if (s.tags[i] == Tag.det || s.tags[i] == Tag.poss || i + 1 >= s.toks.length) return;
    if (i > 0 && (s.tags[i - 1] == Tag.det || s.tags[i - 1] == Tag.poss)) return;
    final k = i + 1;
    if (s.npEnd[k] < 0 || s.tags[k] == Tag.pron || s.breaks[k]) return;
    final p = s.npEnd[k];
    if (p - k < 2 || p >= s.toks.length || s.breaks[p]) return; // one-word objects: the sequence matcher's job
    final part = s.toks[p].lower;
    if (!_sepParticles.contains(part)) return;
    final next = p + 1 < s.toks.length ? s.toks[p + 1].lower : '';
    final closes = p + 1 >= s.toks.length || s.breaks[p + 1] || _closers.contains(next) ||
        ((part == 'up' || part == 'out') && _preps.contains(next));
    if (!closes) return;
    for (final l in {s.toks[i].lower, ...dict.lemmatizer.lemmas(s.toks[i].lower)}) {
      for (final e in _pv2[l] ?? const <Expr>[]) {
        if (e.pattern[1] == part) out.add(TemplateMatch(e, [i, p], 'object'));
      }
    }
  }

  List<TemplateMatch> match(SentenceParse s) {
    final out = <TemplateMatch>[];
    for (var i = 0; i < s.toks.length; i++) {
      _separable(s, i, out);
      final keys = {s.toks[i].lower, ...dict.lemmatizer.lemmas(s.toks[i].lower)};
      for (final k in keys) {
        for (final t in _byWord[k] ?? const <Template>[]) {
          final how = <String>[];
          final m = _matchFrom(s, t, i, how);
          if (m != null) out.add(TemplateMatch(t.expr, m, how.isEmpty ? 'exact' : how.toSet().join('+')));
        }
      }
      if (s.npEnd[i] >= 0 && s.tags[i] != Tag.pron) {
        final head = s.npHead[i];
        final hk = {s.toks[head].lower, ...dict.lemmatizer.lemmas(s.toks[head].lower)};
        for (final k in hk) {
          for (final t in _byWord['np:$k'] ?? const <Template>[]) {
            final how = <String>[];
            final m = _passive(s, t, i, how);
            if (m != null) out.add(TemplateMatch(t.expr, m, 'passive'));
          }
        }
      }
    }
    return out;
  }
}

/// Features of a dictionary candidate in its sentence, for [UnitScorer]
/// ("is this expression a unit here, or just its words side by side?").
/// [conf]: the context engine's confidence for the candidate (SenseEngine.resolve);
/// [shared]: it shares a token with another candidate.
Map<String, double> unitFeatures(SentenceParse s, Expr e, List<int> tokens, {String? variant, String conf = 'none', bool shared = false}) {
  final t = [...tokens]..sort();
  final f = <String, double>{};
  void on(String k) => f[k] = 1;
  String tagAt(int i) => i < 0 ? 'BOS' : (i >= s.toks.length ? 'EOS' : s.tags[i].name);
  final first = t.first, last = t.last;
  on('bias');
  on('cat=${e.cat}');
  on('len=${t.length > 4 ? 4 : t.length}');
  if (last - first + 1 > t.length) on('gap');
  on('first=${tagAt(first)}');
  on('last=${tagAt(last)}');
  on('prev=${tagAt(first - 1)}');
  on('next=${tagAt(last + 1)}');
  on('cat=${e.cat}|next=${tagAt(last + 1)}');
  on('cat=${e.cat}|prev=${tagAt(first - 1)}');
  on('cat=${e.cat}|conf=$conf');
  if (last + 1 >= s.toks.length || s.breaks[last + 1]) on('endsClause');
  if (last + 1 < s.toks.length && s.npEnd[last + 1] >= 0 && !s.breaks[last + 1]) on('npAfter');
  if (last + 1 < s.toks.length && s.npEnd[last + 1] >= 0 && !s.breaks[last + 1]) on('cat=${e.cat}|npAfter');
  if (e.pattern.first == 'be') on('be+');
  for (final i in t) {
    if (i > 0 && s.toks[i].text.isNotEmpty && s.toks[i].text[0] != s.toks[i].text[0].toLowerCase()) {
      on('capital');
      break;
    }
  }
  if (e.pattern.any((w) => w == 'sb' || w == 'sth' || w == "one's" || w == "someone's" || w == 'someone' || w == 'something')) on('slot');
  if (variant != null) on('variant=$variant');
  if (shared) on('shared');
  on('conf=$conf');
  on('tr=${e.tr != null && e.tr!.trim().isNotEmpty ? 'checked' : (e.trDraft != null ? 'draft' : 'none')}');
  on('w=${e.phrase}');
  return f;
}

/// A logistic model over [unitFeatures]: the probability that a dictionary
/// candidate is used as one unit in this sentence. The weights are trained
/// offline (tools/parser_research_5m/train_unit_5m.py) and kept in Dart.
class UnitScorer {
  final Map<String, double> weights;
  final double threshold;
  const UnitScorer(this.weights, this.threshold);

  double score(Map<String, double> f) {
    var z = 0.0;
    f.forEach((k, v) => z += (weights[k] ?? 0) * v);
    return 1 / (1 + exp(-z));
  }
}

/// Task 5M switch for the reader (OFF by default; only tests turn it on).
/// On: [SentenceAnalyzer] makes the reader's expression candidates and hides
/// the ones its unit scorer finds unlikely to be a unit in their sentence.
bool sentenceAnalyzer5m = false;

/// The three 5M engines in one place, for the reader: sentence parse
/// ([ConstructionParser]), template candidates ([TemplateMatcher]) and the
/// unit decision ([UnitScorer]). The fourth engine is the existing
/// SenseEngine: the unit decision reads its confidence, and the panel and the
/// card keep using it unchanged.
class SentenceAnalyzer {
  final DictDb dict;
  final UnitScorer scorer;
  late final ConstructionParser parser = ConstructionParser(dict);
  late final TemplateMatcher templates = TemplateMatcher(dict, dict.exprs);
  final Map<String, SentenceParse> _parses = {};
  SentenceAnalyzer(this.dict, this.scorer);

  SentenceParse parseOf(String sentence, List<Token> toks) {
    if (_parses.length > 2000) _parses.clear();
    return _parses.putIfAbsent(sentence, () => parser.parse(sentence, toks));
  }

  /// The paragraph's candidates: [seq] (PhraseMatcher.match of the
  /// paragraph), where a template match of the same expression replaces a
  /// sequence match it shares a token with, plus the template matches the
  /// sequence matcher does not find. Template matches stay inside a sentence.
  List<Match> matches(String text, List<Token> toks, List<Match> seq) {
    final out = <Match>[];
    final tms = <Match>[];
    for (final r in sentenceRanges(text)) {
      final idx = [for (var i = 0; i < toks.length; i++) if (toks[i].start >= r.$1 && toks[i].end <= r.$2) i];
      if (idx.isEmpty) continue;
      final st = [for (final i in idx) toks[i]];
      // the parse sees the sentence's own text; token offsets stay the paragraph's
      final sentence = text.substring(r.$1, r.$2);
      final local = [for (final t in st) Token(t.start - r.$1, t.end - r.$1, t.text)];
      for (final m in templates.match(parser.parse(sentence, local))) {
        if (m.tokens.length < 2) continue;
        tms.add(Match(m.expr, [for (final k in m.tokens) idx[k]], variant: m.variant == 'exact' ? null : m.variant));
      }
    }
    for (final m in seq) {
      if (!tms.any((t) => t.expr.id == m.expr.id && t.tokens.any(m.tokens.contains))) out.add(m);
    }
    return out..addAll(tms);
  }

  /// Whether a candidate shown with a meaning ([conf] 'sure' / 'likely' from
  /// SenseEngine.resolve) is unlikely to be one unit in its sentence.
  /// [idx] index [toks], the tokens of [sentence].
  bool notAUnit(Expr e, String sentence, List<Token> toks, List<int> idx, {required String conf, String? variant, bool shared = false}) {
    if (conf == 'none') return false;
    // the parse needs offsets inside [sentence]; the reader's tokens carry the paragraph's
    final local = tokenize(sentence);
    if (local.length != toks.length) return false;
    final p = scorer.score(unitFeatures(parseOf(sentence, local), e, idx, variant: variant, conf: conf, shared: shared));
    return p < scorer.threshold;
  }
}
