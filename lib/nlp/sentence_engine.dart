// Task 5N: one call that breaks a sentence into its units and gives each its meaning.
//
//   final b = SentenceEngine(dict, senses, analyzer, grammar).analyze('Blacky the Crow was on hand promptly.');
//   b.units   -> [Blacky] [the] [Crow] [was: olmak] [on hand: hazırda, elde] [promptly: hemen] [.]
//   b.grammar -> Simple Past ("was")
//
// Every token belongs to exactly one unit: an expression or a single word. The expressions are chosen for the
// whole sentence at once (the set of non-overlapping candidates with the best total score), not token by token,
// so two candidates that share a word ("be on" / "on hand") are settled by which reading explains the sentence
// better, and the underline, the panel and the card can all read the same breakdown.
//
// Engines used, all offline and already in the app: PhraseMatcher + templates (candidates), the 5M unit scorer
// (is this candidate one unit here?), SenseEngine (which meaning, in this context), GrammarMarker (tenses and
// structures). No model, no network, no new data.

import '../data/dict_db.dart';
import 'construction.dart';
import 'context_sense.dart';
import 'grammar_marks.dart';
import 'cross_encoder.dart';
import 'text.dart';

/// One piece of the sentence.
class SentenceUnit {
  /// Token indexes (an expression may be split: "turn the light off").
  final List<int> tokens;

  /// The words as written ("turned … off").
  final String text;

  /// The dictionary expression, or null for a single word.
  final Expr? expr;

  /// Base form of a single word ("was" -> "be"), or the expression's phrase.
  final String headword;

  /// Turkish meaning chosen for this sentence, or null (no dictionary meaning fits).
  final String? tr;

  /// English definition of the chosen meaning.
  final String? en;

  /// SenseEngine's confidence for the chosen meaning ('sure', 'likely', 'none').
  final String confidence;

  /// Unit score (expressions only): how likely the words are used as the expression here (the idiom classifier
  /// when it is loaded, else the 5M unit scorer).
  final double? unitScore;

  /// Other dictionary meanings, best first (at most three).
  final List<String> others;

  /// With the sense model: every definition it read and its probability, in SenseEngine's order (for checks).
  final List<({String tr, String en, double p})> scored;

  const SentenceUnit({
    required this.tokens,
    required this.text,
    required this.headword,
    this.expr,
    this.tr,
    this.en,
    this.confidence = 'none',
    this.unitScore,
    this.others = const [],
    this.scored = const [],
  });

  bool get isExpression => expr != null;
}

class SentenceBreakdown {
  final String sentence;
  final List<Token> tokens;
  final List<SentenceUnit> units;
  final List<GMark> grammar;

  /// Expression candidates that lost (to a better reading or as not a unit here), for checks.
  final List<({Expr expr, List<int> tokens, double score, String why})> rejected;
  const SentenceBreakdown(this.sentence, this.tokens, this.units, this.grammar, this.rejected);

  /// The unit token [i] belongs to.
  SentenceUnit unitAt(int i) => units.firstWhere((u) => u.tokens.contains(i));
}

class SentenceEngine {
  final DictDb dict;
  final SenseEngine senses;
  final SentenceAnalyzer analyzer;
  final GrammarMarker? grammar;

  /// Expression categories that take part (the reader's expression filters).
  final Set<String> categories;

  /// Expression or literal, decided in context by the small cross-encoder (lib/nlp/cross_encoder.dart). When it
  /// is null the 5M rules decide (SenseEngine.isLiteral, then the unit scorer).
  final CrossEncoder? classifier;

  /// The classifier's cut: at or above it the words are read as the expression.
  final double threshold;

  /// Which dictionary meaning of a single word fits the sentence ("word: definition" against the sentence). When it
  /// is null SenseEngine's own choice stands.
  final CrossEncoder? senseModel;
  SentenceEngine(this.dict, this.senses, this.analyzer, this.grammar,
      {required this.categories, this.classifier, this.threshold = 0.5, this.senseModel});

  /// SenseEngine's meanings of a word that have an English definition and Turkish, one per Turkish text, in
  /// SenseEngine's order (at most [max]). Null when there is nothing to choose between.
  static List<SenseCandidate>? choicesOf(ContextSense r, {int max = 6}) {
    final seen = <String>{};
    final out = <SenseCandidate>[];
    for (final c in r.ranked) {
      final en = c.en, tr = c.trShown;
      if (c.literal || en == null || en.trim().isEmpty || tr == null || !seen.add(tr)) continue;
      out.add(c);
      if (out.length >= max) break;
    }
    return out.length < 2 ? null : out;
  }

  /// The classifier's input: [s] with each continuous piece of [t] in "[ ]", cut to [window] words on either side
  /// (the model was trained on such windows, so sentence length does not sway it).
  static String marked(String s, List<Token> toks, List<int> t, {int window = 6}) {
    final idx = [...t]..sort();
    final groups = <List<int>>[];
    for (final i in idx) {
      if (groups.isNotEmpty && groups.last.last == i - 1) {
        groups.last.add(i);
      } else {
        groups.add([i]);
      }
    }
    var out = s;
    for (final g in groups.reversed) {
      final a = toks[g.first].start, b = toks[g.last].end;
      out = '${out.substring(0, a)}[ ${out.substring(a, b)} ]${out.substring(b)}';
    }
    final w = out.split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
    final f = w.indexWhere((x) => x.contains('[')), l = w.lastIndexWhere((x) => x.contains(']'));
    return w.sublist(f - window < 0 ? 0 : f - window, l + window + 1 > w.length ? w.length : l + window + 1).join(' ');
  }

  /// The expression's own (non-literal) meanings with an English definition and Turkish, SenseEngine's pick first.
  static List<SenseCandidate>? _exprChoices(ContextSense r, {int max = 5}) {
    final seen = <String>{};
    final out = <SenseCandidate>[];
    final b = r.best;
    for (final c in [if (b != null && r.literalPhrase == null) b, ...r.ranked]) {
      final en = c.en, tr = c.trShown;
      if (c.literal || en == null || en.trim().isEmpty || tr == null || !seen.add(tr)) continue;
      out.add(c);
      if (out.length >= max) break;
    }
    return out.length < 2 ? null : out;
  }

  /// The expression's own meaning for the sentence: SenseEngine's pick when it reads the words as the expression,
  /// else its best expression (non-literal) meaning, else the dictionary entry's Turkish.
  static ({String? tr, String? en, List<String> others}) _exprMeaning(ContextSense r, Expr e) {
    if (r.tr != null && r.literalPhrase == null) {
      return (tr: r.tr, en: r.best?.en, others: [for (final o in r.others.take(3)) if (o.trShown != null) o.trShown!]);
    }
    final c = r.ranked.where((c) => !c.literal && c.tr.isNotEmpty).toList();
    if (c.isNotEmpty) {
      return (tr: c.first.trShown, en: c.first.en, others: [for (final o in c.skip(1).take(3)) o.trShown!]);
    }
    final t = e.trShown;
    return (tr: t == null || t.trim().isEmpty ? null : t, en: e.en, others: const []);
  }

  final Map<String, SentenceBreakdown> _cache = {};

  SentenceBreakdown analyze(String sentence, {String? prev, String? next}) {
    final key = '$sentence\u0000${prev ?? ''}\u0000${next ?? ''}';
    final c = _cache[key];
    if (c != null) return c;
    if (_cache.length > 2000) _cache.clear();
    return _cache[key] = _analyze(sentence, prev, next);
  }

  SentenceBreakdown _analyze(String s, String? prev, String? next) {
    final toks = tokenize(s);
    final seq = dict.matcher.match(toks, text: s);
    final all = analyzer.matches(s, toks, seq).where((m) => m.tokens.length >= 2 && categories.contains(m.expr.cat)).toList();
    final parse = analyzer.parseOf(s, toks);

    // 1. Score every candidate: literal check (phrasal verbs), meaning, unit probability.
    final scored = <({Match m, ContextSense r, double p, String? tr, String? en, List<String> others})>[];
    final rejected = <({Expr expr, List<int> tokens, double score, String why})>[];
    for (final m in all) {
      // "turn the kitchen [light off]": the verb of a phrasal verb stands as a noun here (after a determiner,
      // possessive, adjective or noun), so the words cannot be that phrasal verb.
      // Only the plain form counts ("light" is the verb's own form; "ran" after "the car" is still a verb).
      final v = m.tokens.first;
      if (m.expr.cat == 'phrasal_verbs' && v > 0 && parse.tags[v] == Tag.noun &&
          m.expr.phrase.split(' ').first == toks[v].lower &&
          const {Tag.det, Tag.poss, Tag.adj, Tag.noun}.contains(parse.tags[v - 1])) {
        rejected.add((expr: m.expr, tokens: m.tokens, score: 0, why: 'its verb is a noun here'));
        continue;
      }
      final cls = classifier;
      if (cls != null) {
        final p = cls.probability(m.expr.phrase, marked(s, toks, m.tokens));
        if (p < threshold) {
          rejected.add((expr: m.expr, tokens: m.tokens, score: p, why: 'literal here'));
          continue;
        }
        final r = senses.resolve(SenseQuery(
            sentence: s, tokens: toks, index: m.tokens.first, expr: m.expr, exprTokens: m.tokens, prevSentence: prev, nextSentence: next));
        var mean = _exprMeaning(r, m.expr);
        // several meanings of the expression: the sense model reads each definition against the sentence too
        final sm = senseModel;
        final ec = sm == null ? null : _exprChoices(r);
        if (sm != null && ec != null) {
          final mk = marked(s, toks, m.tokens);
          final p = [for (final c in ec) sm.probability('${m.expr.phrase}: ${c.en}', mk)];
          var b = 0;
          for (var k = 1; k < ec.length; k++) {
            if (p[k] - 0.1 * k > p[b] - 0.1 * b) b = k;
          }
          mean = (tr: ec[b].trShown, en: ec[b].en, others: [for (var k = 0; k < ec.length && k < 4; k++) if (k != b) ec[k].trShown!]);
        }
        if (mean.tr == null) {
          rejected.add((expr: m.expr, tokens: m.tokens, score: p, why: 'no Turkish meaning'));
          continue;
        }
        scored.add((m: m, r: r, p: p, tr: mean.tr, en: mean.en, others: mean.others));
        continue;
      }
      if (m.expr.cat == 'phrasal_verbs' && senses.isLiteral(m.expr, toks, m.tokens, sentence: s, prev: prev, next: next)) {
        rejected.add((expr: m.expr, tokens: m.tokens, score: 0, why: 'literal'));
        continue;
      }
      final r = senses.resolve(SenseQuery(
          sentence: s, tokens: toks, index: m.tokens.first, expr: m.expr, exprTokens: m.tokens, prevSentence: prev, nextSentence: next));
      final shared = all.any((o) => !identical(o, m) && o.tokens.any(m.tokens.contains));
      final p = analyzer.scorer.score(unitFeatures(parse, m.expr, m.tokens, variant: m.variant, conf: r.confidence.name, shared: shared));
      if (r.tr == null) {
        rejected.add((expr: m.expr, tokens: m.tokens, score: p, why: 'no meaning fits'));
        continue;
      }
      if (p < analyzer.scorer.threshold) {
        rejected.add((expr: m.expr, tokens: m.tokens, score: p, why: 'not a unit here'));
        continue;
      }
      scored.add((m: m, r: r, p: p, tr: r.tr, en: r.best?.en, others: [for (final o in r.others.take(3)) if (o.trShown != null) o.trShown!]));
    }

    // 2. The best set of non-overlapping expressions for the whole sentence. Weight: unit probability times the
    // words it explains (a longer expression that is surely a unit beats a shorter one), "sure" counts a bit more.
    double w(int k) => scored[k].p * scored[k].m.tokens.length * (classifier == null && scored[k].r.confidence == SenseConfidence.sure ? 1.2 : 1.0);
    final order = List.generate(scored.length, (k) => k)..sort((a, b) => w(b).compareTo(w(a)));
    var best = <int>[];
    var bestW = -1.0;
    void search(int at, List<int> chosen, Set<int> used, double total) {
      if (total > bestW) {
        bestW = total;
        best = [...chosen];
      }
      if (at >= order.length) return;
      var rest = 0.0;
      for (var x = at; x < order.length; x++) {
        rest += w(order[x]);
      }
      if (total + rest <= bestW) return;
      final k = order[at];
      final t = scored[k].m.tokens;
      if (!t.any(used.contains)) {
        search(at + 1, [...chosen, k], {...used, ...t}, total + w(k));
      }
      search(at + 1, chosen, used, total);
    }

    if (scored.length <= 24) {
      search(0, [], {}, 0);
    } else {
      final used = <int>{};
      for (final k in order) {
        if (!scored[k].m.tokens.any(used.contains)) {
          best.add(k);
          used.addAll(scored[k].m.tokens);
        }
      }
    }
    for (var k = 0; k < scored.length; k++) {
      if (!best.contains(k)) rejected.add((expr: scored[k].m.expr, tokens: scored[k].m.tokens, score: scored[k].p, why: 'a better reading uses its words'));
    }

    // 3. Units: the chosen expressions, then every other word with its own meaning in this sentence.
    final units = <SentenceUnit>[];
    final covered = <int>{};
    for (final k in best) {
      final x = scored[k];
      final t = [...x.m.tokens]..sort();
      covered.addAll(t);
      units.add(SentenceUnit(
        tokens: t,
        text: _text(toks, t),
        headword: x.m.expr.phrase,
        expr: x.m.expr,
        tr: x.tr,
        en: x.en,
        confidence: classifier != null ? (x.p >= 0.9 ? 'sure' : 'likely') : x.r.confidence.name,
        unitScore: x.p,
        others: x.others,
      ));
    }
    for (var i = 0; i < toks.length; i++) {
      if (covered.contains(i)) continue;
      final w = toks[i];
      if (!RegExp(r'[A-Za-z]').hasMatch(w.text)) {
        units.add(SentenceUnit(tokens: [i], text: w.text, headword: w.text));
        continue;
      }
      final r = senses.resolve(SenseQuery(sentence: s, tokens: toks, index: i, prevSentence: prev, nextSentence: next));
      final sm = senseModel;
      final ch = sm == null || r.tr == null || r.reason.contains('name') ? null : choicesOf(r);
      if (sm != null && ch != null) {
        // every definition read against the sentence; SenseEngine's order is a small prior (0.1 per place)
        final m = marked(s, toks, [i]);
        final p = [for (final c in ch) sm.probability('${c.lemma}: ${c.en}', m)];
        var b = 0;
        for (var k = 1; k < ch.length; k++) {
          if (p[k] - 0.1 * k > p[b] - 0.1 * b) b = k;
        }
        units.add(SentenceUnit(
          tokens: [i],
          text: w.text,
          headword: r.headword,
          tr: ch[b].trShown,
          en: ch[b].en,
          confidence: p[b] >= 0.8 ? 'sure' : 'likely',
          unitScore: p[b],
          others: [for (var k = 0; k < ch.length && k < 4; k++) if (k != b) ch[k].trShown!],
          scored: [for (var k = 0; k < ch.length; k++) (tr: ch[k].trShown!, en: ch[k].en!, p: p[k])],
        ));
        continue;
      }
      units.add(SentenceUnit(
        tokens: [i],
        text: w.text,
        headword: r.headword,
        tr: r.tr,
        en: r.best?.en,
        confidence: r.confidence.name,
        others: [for (final o in r.others.take(3)) if (o.trShown != null) o.trShown!],
      ));
    }
    units.sort((a, b) => a.tokens.first.compareTo(b.tokens.first));
    final g = grammar?.mark(s, toks) ?? const <GMark>[];
    return SentenceBreakdown(s, toks, units, g, rejected);
  }

  static String _text(List<Token> toks, List<int> t) {
    final b = StringBuffer(toks[t.first].text);
    for (var k = 1; k < t.length; k++) {
      b.write(t[k] == t[k - 1] + 1 ? ' ' : ' … ');
      b.write(toks[t[k]].text);
    }
    return b.toString();
  }
}
