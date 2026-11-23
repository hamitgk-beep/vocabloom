/// Context-aware word sense selection: which dictionary meaning a word or an
/// expression has in the sentence the learner is reading.
///
/// Everything runs offline on the bundled dictionary. A meaning is only called
/// "sure" when the sentence clearly points to it and its Turkish comes straight
/// from the dictionary; otherwise it is "likely" (a guess, shown as one) or
/// "none" (the panel shows the ordinary dictionary). A wrong meaning shown as
/// certain is worse than no meaning, so every doubt lowers the confidence.
library;

import 'dart:convert';
import 'dart:math';

import '../data/dict_db.dart';
import 'text.dart';

enum SenseConfidence { sure, likely, none }

/// One meaning the dictionary has for the word or expression.
class SenseCandidate {
  /// Stable id, kept in feedback records: "wn:85073" (WordNet synset),
  /// "ex:run through|phrasal_verbs#1" (built-in expression sense),
  /// "od:run#3" (own dictionary sense), "ft:know#0" (main meaning list).
  final String id;

  /// wordnet, expr, own or ft.
  final String source;

  /// The dictionary word the meaning belongs to ("run" for "running").
  final String lemma;

  /// n, v, a or r (null when unknown).
  final String? pos;

  /// English definition or title.
  final String? en;

  /// Turkish meanings, the most fitting first.
  final List<String> tr;

  /// The Turkish was matched to this meaning indirectly (through synonyms or
  /// the word's other meanings), not written for it: never shown as certain.
  final bool trDerived;

  final String? explainTr;
  final String? explainEn;

  /// Short Turkish usage note ("makine, program için").
  final String? note;
  final List<String> examples;
  final List<String> examplesTr;

  /// Position in the dictionary's own order (0 = most common).
  final int rank;

  /// A meaning of the head word when a multi-word match is used literally
  /// ("lived in Kansas": live + in, not the phrasal verb "live in").
  final bool literal;

  /// Synonyms (WordNet).
  final List<String> synonyms;

  /// The meaning comes from an unreviewed AI draft (own_word / own_expr with
  /// reviewed = 0). It still competes, but alone it is never proof enough for a
  /// "sure" meaning ([DictDb.sourcePolicy]).
  final bool unverified;

  double score = 0;
  final Map<String, double> parts = {};

  /// Words shared with the sentence (quality checks).
  final List<String> hits = [];

  SenseCandidate({
    required this.id,
    required this.source,
    required this.lemma,
    this.pos,
    this.en,
    this.tr = const [],
    this.trDerived = false,
    this.explainTr,
    this.explainEn,
    this.note,
    this.examples = const [],
    this.examplesTr = const [],
    this.rank = 0,
    this.literal = false,
    this.synonyms = const [],
    this.unverified = false,
  });

  SenseCandidate withTr(List<String> t, {bool derived = false}) => SenseCandidate(
        id: id, source: source, lemma: lemma, pos: pos, en: en, tr: t, trDerived: derived, explainTr: explainTr,
        explainEn: explainEn, note: note, examples: examples, examplesTr: examplesTr, rank: rank, literal: literal,
        synonyms: synonyms, unverified: unverified,
      )
        ..score = score
        ..parts.addAll(parts);

  /// The Turkish to show: up to three meanings.
  String? get trShown => tr.isEmpty ? null : tr.take(3).join(', ');

  @override
  String toString() => '$id ${pos ?? '?'} ${score.toStringAsFixed(3)} ${trShown ?? '-'} | ${en ?? ''} '
      '${parts.map((k, v) => MapEntry(k, v.toStringAsFixed(2)))} $hits';
}

/// What the engine found for one tap.
class ContextSense {
  /// The word ("know") or expression ("run through") the meaning is for.
  final String headword;

  /// Expression category ("phrasal_verbs") when the meaning is an expression's.
  final String? cat;

  /// A multi-word match that is used literally here ("lived in Kansas").
  final String? literalPhrase;
  final SenseConfidence confidence;
  final SenseCandidate? best;

  /// The other dictionary meanings, best fitting first.
  final List<SenseCandidate> others;

  /// Why: a short note for tests and quality checks (not shown to learners).
  final String reason;

  /// Every meaning considered, scored, best first (tests and quality checks).
  final List<SenseCandidate> ranked;

  const ContextSense({
    required this.headword,
    this.cat,
    this.literalPhrase,
    required this.confidence,
    this.best,
    this.others = const [],
    this.reason = '',
    this.ranked = const [],
  });

  static const empty = ContextSense(headword: '', confidence: SenseConfidence.none, reason: 'empty');

  bool get shown => confidence != SenseConfidence.none && best != null && best!.tr.isNotEmpty;

  /// The Turkish meaning shown for the sentence, or null.
  String? get tr => shown ? best!.trShown : null;

  @override
  String toString() => '$headword ${confidence.name} ${best?.trShown} [$reason]';
}

/// One tap in a sentence.
class SenseQuery {
  final String sentence;
  final List<Token> tokens;

  /// Index of the tapped token in [tokens].
  final int index;

  /// Token indexes of a multi-word expression the tap belongs to, when the
  /// expression is resolved ([expr] set).
  final Expr? expr;
  final List<int> exprTokens;
  final String? prevSentence;
  final String? nextSentence;

  /// Book / paragraph id (or any id of the text), for the cache.
  final String contentId;

  /// Language of the explanations ('tr' or 'en'), for the cache.
  final String lang;

  /// The base form the panel already chose, tried first.
  final String? lemma;

  SenseQuery({
    required this.sentence,
    required this.tokens,
    required this.index,
    this.expr,
    this.exprTokens = const [],
    this.prevSentence,
    this.nextSentence,
    this.contentId = '',
    this.lang = 'tr',
    this.lemma,
  });

  /// A query for the [occurrence]-th time (0 = first) [word] appears in
  /// [sentence]; a multi-word [word] ("run through") is matched as an
  /// expression from the dictionary.
  factory SenseQuery.find(DictDb dict, String sentence, String word, {int occurrence = 0, String? category}) {
    final toks = tokenize(sentence);
    final parts = word.toLowerCase().split(' ');
    if (parts.length > 1) {
      // Inside one sentence: a stored context of two sentences ("… could not
      // break. The ice …") does not hold the expression.
      final ms = dict.matcher
          .match(toks, text: sentence)
          .where((m) => m.expr.phrase == word.toLowerCase() && (category == null || m.expr.cat == category))
          .toList();
      if (ms.length > occurrence) {
        final m = ms[occurrence];
        return SenseQuery(sentence: sentence, tokens: toks, index: m.tokens.first, expr: m.expr, exprTokens: m.tokens);
      }
    }
    var seen = 0;
    for (var i = 0; i < toks.length; i++) {
      if (toks[i].lower == parts.first) {
        if (seen++ == occurrence) return SenseQuery(sentence: sentence, tokens: toks, index: i);
      }
    }
    return SenseQuery(sentence: sentence, tokens: toks, index: -1);
  }
}

/// How a given Turkish answer stands in a sentence, by the context picker:
/// [confirmed] the picker chose that meaning (the same Turkish or a KeNet
/// synonym of it), [other] it chose another meaning (or the expression is
/// used literally), [unknown] it chose none it can stand behind.
enum SentenceFit { confirmed, other, unknown }

/// The result of [SenseEngine.fit], with the reason (tests and quality checks).
class AnswerFit {
  final SentenceFit fit;

  /// confirmed: 'same' or 'synonym'. other: 'sure', 'likely' or 'literal'.
  /// unknown: 'not in sentence', 'grammar word', 'no Turkish', 'draft only' or 'undecided'.
  final String why;
  final ContextSense? sense;
  const AnswerFit(this.fit, this.why, [this.sense]);
  bool get confirmed => fit == SentenceFit.confirmed;
}

/// Weights of the scoring criteria (sum 1). A starting point, tuned on the
/// tests in test/context_sense_test.dart.
class SenseWeights {
  final double semantic, pos, pattern, example, frequency;
  const SenseWeights({this.semantic = 0.40, this.pos = 0.18, this.pattern = 0.18, this.example = 0.12, this.frequency = 0.12});
}

class SenseEngine {
  /// Bumped whenever the scoring changes, so cached and reported choices of an
  /// older engine are told apart.
  static const version = '4';

  final DictDb dict;
  final SenseWeights w;

  /// Dictionary version; part of every cache key, so a new dictionary never
  /// reuses an old choice.
  final String dictVersion;

  SenseEngine(this.dict, {this.w = const SenseWeights(), String? dictVersion}) : dictVersion = dictVersion ?? DictDb.version;

  // ------------------------------------------------------------------ cache
  final _cache = <String, ContextSense>{};
  static const _cacheMax = 400;
  int computed = 0; // for tests: how many queries were really computed

  String cacheKey(SenseQuery q) {
    final t = q.index >= 0 && q.index < q.tokens.length ? q.tokens[q.index] : null;
    final span = q.exprTokens.isEmpty ? '${t?.start}-${t?.end}' : q.exprTokens.map((i) => q.tokens[i].start).join(',');
    return [
      q.contentId,
      _hash(q.sentence),
      span,
      q.expr == null ? '' : '${q.expr!.phrase}|${q.expr!.cat}',
      dictVersion,
      version,
      DictDb.policyVersion,
      q.lang,
    ].join('|');
  }

  static String _hash(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16);
  }

  void clearCache() => _cache.clear();

  /// The meaning of the tapped word or expression in its sentence. Never
  /// throws: on any problem the result is "none" and the panel shows the
  /// ordinary dictionary.
  ContextSense resolve(SenseQuery q) {
    final key = cacheKey(q);
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit; // most recently used last
      return hit;
    }
    ContextSense r;
    try {
      computed++;
      r = q.expr != null ? _resolvePhrase(q) : _resolveWord(q);
      // No Turkish for the meaning chosen here: choose again among the own
      // dictionary's senses, which all have Turkish ("why" -> neden, niçin).
      if (q.expr == null && !r.shown && r.reason != 'grammar word' && _hasOwnWord) {
        _ownOnly = true;
        try {
          final o = _resolveWord(q);
          if (o.shown) r = o;
        } finally {
          _ownOnly = false;
        }
      }
    } catch (e) {
      r = ContextSense(headword: q.index >= 0 && q.index < q.tokens.length ? q.tokens[q.index].lower : '', confidence: SenseConfidence.none, reason: 'error: $e');
    }
    _cache[key] = r;
    if (_cache.length > _cacheMax) _cache.remove(_cache.keys.first);
    return r;
  }

  /// The one confidence rule for a Turkish [answer] of [headword] (a word's
  /// base form, or an expression) in [sentence]. Review cards grade an answer
  /// only when it is [SentenceFit.confirmed]; the word panel saves a meaning
  /// with a new card under the same condition. Confirmed means: the picker
  /// shows a meaning for the headword there, that meaning does not rest on an
  /// unverified AI draft, and it is the same Turkish as [answer] or a KeNet
  /// synonym of it of the same part of speech ([DictDb.sameTr]). An
  /// expression is looked at as a whole and is not confirmed when it is used
  /// literally. [synonyms] off: only the same Turkish counts (for measuring).
  AnswerFit fit(String headword, String sentence, String answer, {bool synonyms = true}) {
    final SenseQuery q;
    if (headword.contains(' ')) {
      q = SenseQuery.find(dict, sentence, headword);
      if (q.expr == null) return const AnswerFit(SentenceFit.unknown, 'not in sentence');
    } else {
      final toks = tokenize(sentence);
      final i = dict.indexOfLemma(toks, headword);
      if (i < 0) return const AnswerFit(SentenceFit.unknown, 'not in sentence');
      q = SenseQuery(sentence: sentence, tokens: toks, index: i, lemma: headword);
    }
    final c = resolve(q);
    if (q.expr != null && c.literalPhrase != null) return AnswerFit(SentenceFit.other, 'literal', c);
    final b = c.best;
    // A word that is part of an expression here ("give" in "give up") is not
    // judged as the word alone.
    if ((q.expr == null) != (c.cat == null)) return AnswerFit(SentenceFit.unknown, 'undecided', c);
    if (!c.shown || b == null) {
      final why = c.reason == 'grammar word'
          ? 'grammar word'
          : c.ranked.every((x) => x.tr.isEmpty)
              ? 'no Turkish'
              : 'undecided';
      return AnswerFit(SentenceFit.unknown, why, c);
    }
    // An expression can also be meant word by word, and the picker's "likely"
    // tells the two apart no better than chance (measured on MAGPIE): only a
    // sure choice confirms an expression.
    if (q.expr != null && c.confidence != SenseConfidence.sure) return AnswerFit(SentenceFit.unknown, 'undecided', c);
    // A checked meaning of the same part of speech with other Turkish ties
    // with the chosen one: the sentence does not settle which is meant, so it
    // grades nothing. (Measured on the review audit: counting every "close"
    // rival as a conflict mostly dropped answers that were right.)
    final tie = c.ranked.any((x) =>
        x.id != b.id &&
        !x.unverified &&
        x.tr.isNotEmpty &&
        !x.tr.any(b.tr.contains) &&
        (x.pos == null || b.pos == null || x.pos == b.pos) &&
        b.score - x.score <= _fitTie);
    if (tie) return AnswerFit(SentenceFit.unknown, 'undecided', c);
    // A noun's meaning never confirms a verb answer, or the other way round
    // (also for a draft: "durak" for the verb "stop" is no match).
    final shape = DictDb.isTrVerb(DictDb.shortTr(answer));
    if ((b.pos == 'n' || b.pos == 'v') && (b.pos == 'v') != shape) {
      return AnswerFit(SentenceFit.other, c.confidence == SenseConfidence.sure ? 'sure' : 'likely', c);
    }
    if (b.unverified) {
      // The picker chose an unverified AI draft. Alone it proves nothing; it
      // counts only when [answer] is a checked meaning of the headword and the
      // draft says the very same Turkish (two sources, then, not one).
      final same = [...b.tr, c.tr!].any((t) => dict.trLink(t, answer) == 'same');
      if (same && _checkedTr(headword, q.expr).any((t) => dict.trLink(t, answer) == 'same')) {
        return AnswerFit(SentenceFit.confirmed, 'same', c);
      }
      return AnswerFit(SentenceFit.unknown, 'draft only', c);
    }
    String? link;
    for (final t in [...b.tr, c.tr!]) {
      final l = synonyms ? dict.trLink(t, answer, pos: b.pos) : (dict.trLink(t, answer) == 'same' ? 'same' : null);
      if (l == 'same') {
        link = l;
        break;
      }
      link ??= l;
    }
    if (link == null && synonyms && q.expr == null && _coTranslated(headword, b, answer)) link = 'co-translation';
    if (link != null) return AnswerFit(SentenceFit.confirmed, link, c);
    return AnswerFit(SentenceFit.other, c.confidence == SenseConfidence.sure ? 'sure' : 'likely', c);
  }

  /// Checked (not AI draft) Turkish meanings of a word or expression.
  Iterable<String> _checkedTr(String headword, Expr? e) {
    if (e != null) return [if (e.tr != null) e.tr!];
    final info = dict.lookup(headword);
    return [...info.trFreeDict, for (final s in info.senses) ...s.tr];
  }

  /// Whether [answer] is also the main checked Turkish meaning of another
  /// English word whose main sense is the chosen WordNet synset [b]: "istemek"
  /// is the first meaning of "want" and of "desire", and that synset is the
  /// first sense of "desire", so "istemek" belongs to it as "arzu etmek" does.
  /// Only the synonym's first sense of that part of speech and its first two
  /// meanings count: "rear" also means "kaldırmak", but bringing up children
  /// is not its first sense, so "kaldırmak" is not joined to "yetiştirmek".
  bool _coTranslated(String lemma, SenseCandidate b, String answer) {
    if (!b.id.startsWith('wn:') || b.pos == null) return false;
    final id = int.tryParse(b.id.substring(3));
    final sense = dict.lookup(lemma).senses.where((x) => x.synId == id).firstOrNull;
    if (sense == null) return false;
    final verb = b.pos == 'v';
    for (final w in sense.synonyms.where((w) => !w.contains(' ') && !w.contains('_') && w.toLowerCase() != lemma).take(6)) {
      final si = dict.lookup(w.toLowerCase());
      if (si.senses.where((x) => DictDb.normPos(x.pos) == b.pos).firstOrNull?.synId != id) continue;
      final pool = si.trFreeDict.where((t) => DictDb.isTrVerb(t) == verb).take(2);
      if (pool.any((t) => dict.trLink(t, answer) == 'same')) return true;
    }
    return false;
  }

  /// Whether the expression [e], matched on [idx], is used literally here
  /// ("lived in Kansas" is live + in, not the phrasal verb "live in").
  bool isLiteral(Expr e, List<Token> toks, List<int> idx, {String? sentence, String? prev, String? next}) {
    if (idx.isEmpty || !e.phrase.contains(' ')) return false;
    final r = resolve(SenseQuery(
        sentence: sentence ?? toks.map((t) => t.text).join(' '), tokens: toks, index: idx.first, expr: e, exprTokens: idx,
        prevSentence: prev, nextSentence: next));
    return r.literalPhrase != null;
  }

  // --------------------------------------------------------------- words

  ContextSense _resolveWord(SenseQuery q) {
    if (q.index < 0 || q.index >= q.tokens.length) {
      return const ContextSense(headword: '', confidence: SenseConfidence.none, reason: 'word not in sentence');
    }
    final tok = q.tokens[q.index];
    final lower = tok.lower;
    // Grammar words (prepositions, helpers, "very", "just" …): WordNet's
    // senses do not cover how they work; the panel's own explanation does.
    if (_closed.contains(lower)) {
      return ContextSense(headword: lower, confidence: SenseConfidence.none, reason: 'grammar word');
    }
    final lemmas = _lemmaCandidates(lower, q.lemma);
    // "turn the light off": a phrasal verb split by its object, which the
    // reader does not underline.
    final sep = _separable(q.tokens, q.index, lemmas);
    if (sep != null) {
      return _resolvePhrase(SenseQuery(
          sentence: q.sentence, tokens: q.tokens, index: q.index, expr: sep.$1, exprTokens: sep.$2,
          prevSentence: q.prevSentence, nextSentence: q.nextSentence, contentId: q.contentId, lang: q.lang));
    }
    var cands = <SenseCandidate>[];
    for (var li = 0; li < lemmas.length; li++) {
      cands.addAll(_wordCandidates(lemmas[li], rankOffset: li * 3));
    }
    // The ending rules out some readings of a base form ("meaning" is the
    // verb "mean", never the adjective).
    final fits = [
      for (final c in cands)
        if (c.pos == null || (_allowedPos(lower, c.lemma)?.contains(c.pos) ?? true)) c,
    ];
    if (fits.isNotEmpty) cands = fits;
    if (cands.isEmpty) {
      return ContextSense(headword: lemmas.firstOrNull ?? lower, confidence: SenseConfidence.none, reason: 'no dictionary meaning');
    }
    final ctx = _Context.of(this, q.tokens, {q.index}, q.prevSentence, q.nextSentence);
    final breaks = clauseBreaks(q.sentence, q.tokens);
    final pos = _guessPos(q.tokens, q.index, cands.map((c) => c.pos).whereType<String>().toSet(), breaks: breaks);
    final shape = _Shape.inSentence(this, q.tokens, q.index, q.index, breaks: breaks);
    for (final c in cands) {
      _score(c, ctx, pos, shape, q.tokens, q.index, q.index);
    }
    final r = _decide(lemmas.first, null, null, cands, ctx, shape, pos);
    // "the Nook", "Apple's new phone": a capitalised word inside a sentence
    // may be a name. A common word's meaning ("köşe" for the Nook reader) is
    // then only a guess; a name's own meaning ("Irak", "ocak") stays.
    // When the dictionary itself knows the word as a name ("John" the
    // apostle beside "john" the toilet), the common meaning is not shown.
    if (r.confidence != SenseConfidence.none && r.best != null && !isNameSense(r.best!)) {
      final asName = cands.any(isNameSense);
      final t = q.index > 0 && q.index < q.tokens.length ? q.tokens[q.index].text : '';
      // after a colon or a quote a capital may start a sentence: only a word
      // the dictionary knows as a name counts there
      final named = nameLike(q.sentence, q.tokens, q.index) || (asName && t.isNotEmpty && t[0] != t[0].toLowerCase() && t != t.toUpperCase());
      if (named && (asName || r.confidence == SenseConfidence.sure)) {
        return ContextSense(
            headword: r.headword,
            confidence: asName ? SenseConfidence.none : SenseConfidence.likely,
            best: r.best,
            others: r.others,
            reason: '${asName ? 'a name' : 'maybe a name'}; ${r.reason}',
            ranked: r.ranked);
      }
    }
    return r;
  }

  static final Set<String> _closed = {
    ...stopWords, ..._preps, ..._aux, ..._dets, ..._persons.where((p) => p.length < 6),
    'very', 'rather', 'quite', 'too', 'so', 'just', 'even', 'only', 'also', 'well', 'still', 'yet', 'ever', 'never',
    'again', 'already', 'almost', 'enough', 'perhaps', 'maybe', 'please', 'than', 'then', 'because', 'although',
    'though', 'unless', 'while', 'whether', 'however', 'therefore', 'except', 'upon', 'against', 'among', 'beside',
    'besides', 'beyond', 'despite', 'via', 'per', 'whose', 'whom', 'whatever', 'whoever', 'whichever', 'nor',
    'cannot', 'ought', 'shall', 'here', 'there', 'now', 'today', 'tonight', 'yesterday', 'tomorrow', 'not', 'yes', 'oh',
  };

  static const _particles = {'up', 'down', 'off', 'out', 'away', 'back', 'on', 'over', 'in', 'around', 'about', 'through'};

  /// A phrasal verb whose particle comes after the object ("turn the light
  /// off", "look the word up"): the expression and its token indexes.
  (Expr, List<int>)? _separable(List<Token> toks, int i, List<String> lemmas) {
    for (var k = i + 2; k < toks.length && k <= i + 5; k++) {
      final p = toks[k].lower;
      if (!_particles.contains(p)) {
        // the object must be a short noun phrase
        if (k > i + 1 && (_preps.contains(p) || const {'and', 'or', 'but', 'that', 'which', 'who'}.contains(p))) return null;
        continue;
      }
      for (final l in lemmas.take(2)) {
        final e = _phrasal['$l $p'];
        if (e != null) return (e, [i, k]);
      }
      return null;
    }
    return null;
  }

  late final Map<String, Expr> _phrasal = {
    for (final e in dict.exprs)
      if (e.cat == 'phrasal_verbs' && e.pattern.length == 2) e.phrase: e,
  };

  /// Base-form candidates of a surface form, the panel's choice first
  /// ("better" → better, good, well; "saw" → see, saw).
  List<String> _lemmaCandidates(String lower, String? preferred) {
    final out = <String>[];
    void add(String l) {
      if (!out.contains(l) && _hasMeaning(l)) out.add(l);
    }

    if (preferred != null) add(preferred);
    for (final b in dict.baseForms(lower)) {
      add(b.lemma);
    }
    return out;
  }

  /// The parts of speech [lemma] can have when it is written [lower]
  /// ("training" as "train" is the verb only); null when any.
  Set<String>? _allowedPos(String lower, String lemma) =>
      dict.baseForms(lower).where((b) => b.lemma == lemma).firstOrNull?.pos;

  /// The most likely base form ([DictDb.headword]): "went" → go, "things" →
  /// thing, "only" → only.
  String lemmaOf(String lower) => dict.headword(lower);

  bool _hasMeaning(String l) => dict.hasMeaning(l);

  late final bool _hasOwn = dict.db.select("SELECT 1 FROM sqlite_master WHERE type='table' AND name='od'").isNotEmpty;

  /// The own dictionary (own_word: Turkish meaning, English definition and a
  /// translated example per sense), used when the app turns it on.
  late final bool _hasOwnWord = DictDb.useOwnDictionary &&
      dict.db.select("SELECT 1 FROM sqlite_master WHERE type='table' AND name='own_word'").isNotEmpty;

  /// While true, words are judged on the own dictionary's senses alone.
  bool _ownOnly = false;

  /// Main Turkish meanings of [lemma] (ft), cross references left out.
  List<String> mainTr(String lemma) => _mainTrCache.putIfAbsent(lemma, () {
        final r = dict.db.select('SELECT tr FROM ft WHERE word=?', [lemma]);
        if (r.isEmpty) return const [];
        try {
          return (jsonDecode(r.first.columnAt(0) as String) as List)
              .cast<String>()
              .where((t) => t.trim().isNotEmpty && !t.toLowerCase().contains('bakınız') && !DictDb.badMeaning(t))
              .toList();
        } catch (_) {
          return const [];
        }
      });
  final Map<String, List<String>> _mainTrCache = {};

  /// Every meaning the dictionary has for [lemma]: WordNet senses, the own
  /// dictionary's senses when the dictionary has them, and the main Turkish
  /// meanings when there is nothing else.
  List<SenseCandidate> _wordCandidates(String lemma, {int rankOffset = 0}) {
    if (_ownOnly) return _ownWordCandidates(lemma, rankOffset);
    final out = <SenseCandidate>[];
    final rankByPos = <String, int>{};
    for (final s in dict.lookup(lemma).senses) {
      final pos = DictDb.normPos(s.pos);
      final rank = rankByPos[pos] = (rankByPos[pos] ?? -1) + 1;
      out.add(SenseCandidate(
        id: 'wn:${s.synId}',
        source: 'wordnet',
        lemma: lemma,
        pos: pos,
        en: s.gloss,
        tr: _cleanTr(s.tr),
        examples: s.examples,
        examplesTr: s.examplesTr,
        rank: rank + rankOffset,
        synonyms: s.synonyms,
      ));
    }
    if (_hasOwn) out.addAll(_ownCandidates(lemma, rankOffset));
    // A word with Turkish meanings but no WordNet senses (function words,
    // new words): its main meanings, in the dictionary's order. AI drafts do
    // not stand in for them ([DictDb.sourcePolicy]).
    if (out.every((c) => c.unverified)) {
      final ft = mainTr(lemma);
      for (var i = 0; i < ft.length; i++) {
        out.add(SenseCandidate(id: 'ft:$lemma#$i', source: 'ft', lemma: lemma, tr: _split(ft[i]), rank: i + rankOffset));
      }
    }
    return out;
  }

  static const _posCodes = {'noun': 'n', 'verb': 'v', 'adjective': 'a', 'adj': 'a', 'adverb': 'r', 'adv': 'r', 'n': 'n', 'v': 'v', 'a': 'a', 'r': 'r', 's': 'a'};

  /// Senses of our own dictionary (table `od`: word, json list of
  /// {pos, tr, note, en, ex_tr}) once it is part of the bundled dictionary.
  List<SenseCandidate> _ownCandidates(String lemma, int rankOffset) {
    final r = dict.db.select('SELECT json FROM od WHERE word=?', [lemma]);
    if (r.isEmpty) return const [];
    final out = <SenseCandidate>[];
    try {
      // Tiered: an AI draft sense is marked, a merged idiom sense split ([DictDb.tiered]).
      final list = DictDb.tiered(jsonDecode(r.first.columnAt(0) as String) as List, dict.ownTier(lemma) != SourceTier.draft, 'w:$lemma');
      for (var k = 0; k < list.length; k++) {
        final (i, s, draft) = list[k];
        final idx = k > 0 && list[k - 1].$1 == i ? '${i}d' : '$i';
        final tr = _split('${s['tr'] ?? ''}');
        if (tr.isEmpty) continue;
        out.add(SenseCandidate(
          id: 'od:$lemma#$idx',
          source: 'own',
          lemma: lemma,
          pos: _posCodes['${s['pos']}'],
          tr: tr,
          note: (s['note'] as String?)?.trim().isEmpty ?? true ? null : s['note'] as String,
          examples: [if ('${s['en'] ?? ''}'.isNotEmpty) '${s['en']}'],
          examplesTr: [if ('${s['ex_tr'] ?? ''}'.isNotEmpty) '${s['ex_tr']}'],
          rank: i + rankOffset,
          unverified: draft,
        ));
      }
    } catch (_) {}
    return out;
  }

  static const _trPos = {'isim': 'n', 'özel isim': 'n', 'fiil': 'v', 'deyimsel fiil': 'v', 'sıfat': 'a', 'zarf': 'r'};

  /// Senses of the own dictionary (own_word), with their English definition
  /// and translated example, so a meaning WordNet has no Turkish for still
  /// gets one ("why" in "Why do you think ...?": neden, niçin).
  List<SenseCandidate> _ownWordCandidates(String lemma, int rankOffset) {
    final list = dict.ownWordTiered(lemma);
    if (list.isEmpty) return const [];
    final out = <SenseCandidate>[];
    try {
      for (var k = 0; k < list.length; k++) {
        final (i, s, draft) = list[k];
        final idx = k > 0 && list[k - 1].$1 == i ? '${i}d' : '$i';
        final tr = _split('${s['tr'] ?? ''}');
        if (tr.isEmpty) continue;
        final note = '${s['note'] ?? ''}'.trim();
        // Older rows have no "ex": their "en" is the example, not a definition.
        final en0 = '${s['en'] ?? ''}'.trim();
        final hasEx = '${s['ex'] ?? ''}'.trim().isNotEmpty;
        final ex = hasEx ? '${s['ex']}'.trim() : en0, exTr = '${s['ex_tr'] ?? ''}'.trim();
        // More checked sentences for this meaning (tools/contrib/apply.py).
        final more = [for (final m in (s['more'] as List? ?? const [])) (m as Map).cast<String, dynamic>()];
        out.add(SenseCandidate(
          id: 'ow:$lemma#$idx',
          source: 'own',
          lemma: lemma,
          pos: _trPos['${s['pos']}'],
          en: hasEx && en0.isNotEmpty ? en0 : null,
          tr: tr,
          note: note.isEmpty ? null : note,
          examples: [if (ex.isNotEmpty) ex, for (final m in more) '${m['en'] ?? ''}'],
          examplesTr: [if (ex.isNotEmpty) exTr, for (final m in more) '${m['tr'] ?? ''}'],
          rank: i + rankOffset,
          unverified: draft,
        ));
      }
    } catch (_) {}
    return out;
  }

  static List<String> _split(String s) =>
      s.split(RegExp(r'[,;]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  /// Sense Turkish without empty or broken items.
  static List<String> _cleanTr(List<String> tr) => [
        for (final t in tr)
          if (t.trim().isNotEmpty && !DictDb.badMeaning(t)) t.trim()
      ];

  // ---------------------------------------------------------- expressions

  ContextSense _resolvePhrase(SenseQuery q) {
    final e = q.expr!;
    final idx = q.exprTokens.isEmpty ? [q.index] : q.exprTokens;
    final cands = <SenseCandidate>[..._exprCandidates(e)];
    // The literal reading competes with the expression: the meaning of the
    // first content word, with the other words in their plain sense.
    final headI = idx.firstWhere((i) => !stopWords.contains(q.tokens[i].lower), orElse: () => idx.first);
    final headLemmas = _lemmaCandidates(q.tokens[headI].lower, e.pattern.isNotEmpty && e.pattern.first == q.tokens[headI].lower ? null : (e.pattern.firstOrNull));
    final multi = idx.length > 1;
    if (multi) {
      for (var li = 0; li < headLemmas.length && li < 2; li++) {
        for (final c in _wordCandidates(headLemmas[li], rankOffset: li * 3)) {
          if (e.cat == 'phrasal_verbs' && c.pos != null && c.pos != 'v') continue;
          if (c.pos != null && !(_allowedPos(q.tokens[headI].lower, c.lemma)?.contains(c.pos) ?? true)) continue;
          cands.add(SenseCandidate(
            id: c.id, source: c.source, lemma: c.lemma, pos: c.pos, en: c.en, tr: c.tr, examples: c.examples,
            examplesTr: c.examplesTr, rank: c.rank, literal: true, synonyms: c.synonyms, note: c.note, unverified: c.unverified,
          ));
        }
      }
    }
    if (cands.isEmpty) {
      return ContextSense(headword: e.phrase, cat: e.cat, confidence: SenseConfidence.none, reason: 'no meanings');
    }
    final ctx = _Context.of(this, q.tokens, idx.toSet(), q.prevSentence, q.nextSentence);
    final last = idx.reduce(max);
    final breaks = clauseBreaks(q.sentence, q.tokens);
    final shape = _Shape.inSentence(this, q.tokens, headI, last, breaks: breaks);
    final pos = e.cat == 'phrasal_verbs' ? 'v' : _guessPos(q.tokens, headI, cands.map((c) => c.pos).whereType<String>().toSet(), breaks: breaks);
    for (final c in cands) {
      _score(c, ctx, e.cat == 'phrasal_verbs' ? 'v' : (c.literal ? pos : null), shape, q.tokens, headI, c.literal ? headI : last,
          particles: c.literal ? e.pattern.skip(1).toList() : const [], phrase: c.literal ? null : e);
    }
    // "in the raw edges", "under a cloud of dust", "in the red one": the
    // expression's last noun goes on into a longer noun group, so its words
    // are meant one by one; the expression keeps only a guess.
    // Only for an expression that is a prepositional phrase: an expression
    // that is a noun group or a pair is used before a noun too ("a dog in the
    // manger attitude", "the free and easy atmosphere").
    final prepPhrase = e.cat == 'prepositional_phrases' || (e.cat != 'phrasal_verbs' && e.pattern.isNotEmpty && _preps.contains(e.pattern.first));
    final continues = multi && prepPhrase && _nounGroupGoesOn(q.tokens, last, breaks);
    if (continues) {
      for (final c in cands) {
        if (!c.literal) c.score -= 0.25;
      }
    }
    var r = _decide(e.phrase, e.cat, headLemmas.firstOrNull, cands, ctx, shape, pos);
    // Idiom or words, and the sentence cannot tell which ("tough as old
    // boots", "go with the flow"): an idiom meaning about as close as the
    // word-by-word one is shown, as a guess, rather than hidden. A guess
    // never grades a card ([fit] wants "sure" for an expression).
    if (r.literalPhrase != null && r.best != null && r.confidence != SenseConfidence.none && e.cat != 'phrasal_verbs') {
      final lead = r.best!.score;
      final near = r.ranked.where((c) => !c.literal && c.tr.isNotEmpty && lead - c.score <= _idiomOrWords).toList();
      if (near.isNotEmpty) {
        final idiom = near.first;
        return ContextSense(
            headword: e.phrase,
            cat: e.cat,
            confidence: SenseConfidence.likely,
            best: idiom,
            others: _others([for (final c in r.ranked) if (!identical(c, idiom)) c], idiom),
            reason: 'idiom or words: ${r.best!.id} ${lead.toStringAsFixed(3)}; ${idiom.id} ${idiom.score.toStringAsFixed(3)}',
            ranked: r.ranked);
      }
    }
    // An idiom made of ordinary words can also be meant word by word ("on
    // board", "oil and water"), and nothing in the sentence tells the two
    // apart reliably (MAGPIE: a third of the "sure" idioms were literal). So
    // such an idiom is shown, but never as sure, and a card keeps no meaning
    // for it without the learner's choice. Phrasal verbs are judged by their
    // own checks.
    // Finding the expression is not proof that it is meant as one, and
    // neither is a word-by-word reading with no Turkish in the dictionary:
    // "a literal case of poacher turned gamekeeper", "circling its wagons",
    // "she'll be right over" are meant word by word, and their words have no
    // Turkish here (or, "she'll", no entry at all). So the test is whether the
    // words can be read one by one, not whether the dictionary translates that
    // reading (Task 5F). Only an expression with a word that has no meaning of
    // its own cannot be literal.
    final canBeLiteral = e.cat != 'phrasal_verbs' && (cands.any((c) => c.literal) || _ordinaryWords(q.tokens, idx));
    if ((continues || canBeLiteral) && r.confidence == SenseConfidence.sure && r.cat != null) {
      return ContextSense(
          headword: r.headword,
          cat: r.cat,
          confidence: SenseConfidence.likely,
          best: r.best,
          others: r.others,
          reason: '${continues ? 'goes on' : 'can be literal'}: ${r.reason}',
          ranked: r.ranked);
    }
    return r;
  }

  /// Whether every word of a matched expression is a grammar word or has a
  /// meaning of its own in the dictionary (with or without Turkish), so the
  /// expression can also be read word by word. "she'll" counts by "she";
  /// a hyphenated word by each of its parts.
  bool _ordinaryWords(List<Token> toks, List<int> idx) {
    bool known(String w) =>
        w.isEmpty || stopWords.contains(w) || _hasMeaning(w) || dict.baseForms(w).any((b) => _hasMeaning(b.lemma));
    for (final i in idx) {
      if (i < 0 || i >= toks.length) return false;
      for (final part in toks[i].lower.split('-')) {
        if (known(part) || known(part.split(RegExp("['’]")).first)) continue;
        return false;
      }
    }
    return true;
  }

  /// How close an idiom meaning must come to the word-by-word reading to be
  /// shown instead of it (the margin [_decide] calls "close").
  static const _idiomOrWords = 0.06;

  /// Whether the word after token [last] (in the same clause) carries on the
  /// noun group that ends the expression: "of", "one", or a noun that is not
  /// a verb form. The last word of the expression must be a noun or an
  /// adjective itself.
  bool _nounGroupGoesOn(List<Token> toks, int last, List<bool>? breaks) {
    if (last + 1 >= toks.length || (breaks != null && breaks[last + 1])) return false;
    final lw = toks[last].lower, next = toks[last + 1].lower;
    final lp = dict.posOf(lw);
    if (stopWords.contains(lw) || !(lp.contains('n') || lp.contains('a'))) return false;
    if (next == 'of' || next == 'one' || next == 'ones') return true;
    if (stopWords.contains(next) || _preps.contains(next) || _aux.contains(next) || next.endsWith('ing') || next.endsWith('ed') || next.endsWith('ly')) return false;
    final np = dict.posOf(next);
    return np.contains('n') && !np.contains('v') && !np.contains('r');
  }

  /// The built-in senses of an expression (title, explanation, examples),
  /// otherwise its one dictionary meaning.
  List<SenseCandidate> _exprCandidates(Expr e) {
    final out = <SenseCandidate>[];
    // Checked senses (a verified own row, otherwise exd) as "ex:", then the AI
    // draft's senses as "xd:" ([DictDb.sourcePolicy]): drafts compete, marked.
    final drafts = <SenseCandidate>[];
    void read(String? js, bool draft) {
      if (js == null) return;
      try {
        final list = jsonDecode(js) as List;
        for (var i = 0; i < list.length; i++) {
          final s = (list[i] as Map).cast<String, dynamic>();
          final exs = [for (final x in (s['examples'] as List? ?? const [])) (x as Map).cast<String, dynamic>()];
          final title = '${s['title_tr'] ?? ''}'.trim();
          (draft ? drafts : out).add(SenseCandidate(
            id: '${draft ? 'xd' : 'ex'}:${e.phrase}|${e.cat}#$i',
            unverified: draft,
            source: 'expr',
            lemma: e.phrase,
            pos: e.cat == 'phrasal_verbs' ? 'v' : null,
            en: '${s['title_en'] ?? ''}'.trim(),
            tr: title.isEmpty ? const [] : [_lowerFirst(title)],
            explainTr: '${s['explain_tr'] ?? ''}'.trim().isEmpty ? null : '${s['explain_tr']}'.trim(),
            explainEn: '${s['explain_en'] ?? ''}'.trim().isEmpty ? null : '${s['explain_en']}'.trim(),
            examples: [for (final x in exs) '${x['en'] ?? ''}'],
            examplesTr: [for (final x in exs) '${x['tr'] ?? ''}'],
            rank: i,
          ));
        }
      } catch (_) {}
    }

    read(dict.exprDetail(e.phrase, e.cat), false);
    read(dict.exprDraftDetail(e.phrase, e.cat), true);
    // The expression's one dictionary meaning (or the user's own AI translation).
    final plain = e.tr ?? e.aiTr;
    if (out.isEmpty && (plain != null || (e.en != null && drafts.isEmpty))) {
      out.add(SenseCandidate(
        id: 'ex:${e.phrase}|${e.cat}#0',
        source: 'expr',
        lemma: e.phrase,
        pos: e.cat == 'phrasal_verbs' ? 'v' : null,
        en: e.en?.split('; ').first,
        tr: plain == null ? const [] : [plain],
        examples: [if (e.ex != null) e.ex!],
        examplesTr: [if (e.exTr != null) e.exTr!],
      ));
    }
    for (final d in drafts) {
      out.add(SenseCandidate(
        id: d.id, source: d.source, lemma: d.lemma, pos: d.pos, en: d.en, tr: d.tr, explainTr: d.explainTr,
        explainEn: d.explainEn, examples: d.examples, examplesTr: d.examplesTr, rank: d.rank + out.length, unverified: true,
      ));
    }
    return out;
  }

  static String _lowerFirst(String s) {
    if (s.isEmpty) return s;
    final f = s[0];
    final l = f == 'I' ? 'ı' : f == 'İ' ? 'i' : f.toLowerCase();
    return l + s.substring(1);
  }

  // --------------------------------------------------------------- scoring

  /// Content lemmas of an English text, without [skip] (the word itself).
  Set<String> bag(String text, {Set<String> skip = const {}}) {
    final out = <String>{};
    for (final t in tokenize(text)) {
      final w = t.lower;
      if (w.length < 3 || _stop.contains(w)) continue;
      for (final l in dict.lemmatizer.lemmas(w).take(2)) {
        if (!skip.contains(l) && !_stop.contains(l)) out.add(l);
      }
    }
    return out;
  }

  late final Map<String, int> _freq = {
    for (final r in dict.db.select('SELECT word, n FROM wfreq')) r.columnAt(0) as String: r.columnAt(1) as int,
  };

  /// How much a shared word says: rare words much, everyday words little
  /// ("loan" more than "go").
  double idf(String w) {
    final n = _freq[w];
    if (n == null) return 0.6;
    return (1.25 - log(n + 1) / ln10 / 4).clamp(0.15, 1.0);
  }

  final Map<String, Set<String>> _glossBagCache = {};

  /// Words of the first definitions of [lemma]: "river" → stream, water …
  /// (the context is widened with them, so "river bank" meets "a body of water").
  Set<String> glossBag(String lemma) => _glossBagCache.putIfAbsent(lemma, () {
        final out = <String>{};
        for (final r in dict.db.select(
            'SELECT s.gloss, s.words FROM sense x JOIN syn s ON s.id=x.syn_id WHERE x.lemma=? ORDER BY x.rank LIMIT 3',
            [lemma])) {
          out.addAll(bag(r.columnAt(0) as String, skip: {lemma}));
          try {
            for (final w in (jsonDecode(r.columnAt(1) as String) as List).cast<String>().take(4)) {
              if (!w.contains(' ') && w != lemma) out.add(w.toLowerCase());
            }
          } catch (_) {}
        }
        if (_glossBagCache.length > 6000) _glossBagCache.clear();
        return out;
      });

  final Map<String, Set<String>> _trStemCache = {};

  /// Turkish word stems of [lemma]'s main meanings ("river" → nehir, ırmak).
  Set<String> trStems(String lemma) => _trStemCache.putIfAbsent(lemma, () {
        final out = <String>{};
        final main = mainTr(lemma);
        for (final t in main.take(2)) {
          out.addAll(turkishStems(t));
        }
        if (out.isEmpty) {
          for (final s in dict.lookup(lemma).senses.take(2)) {
            for (final t in s.tr.take(2)) {
              out.addAll(turkishStems(t));
            }
          }
        }
        return out;
      });

  /// Turkish words cut to a stem, so suffixes do not hide a match
  /// ("kıyısı" / "kıyı", "nehrin" / "nehir" is not caught, which is fine).
  static Set<String> turkishStems(String text) {
    final out = <String>{};
    for (final m in RegExp(r'[a-zçğıöşüâîû]+').allMatches(text.toLowerCase().replaceAll('İ', 'i'))) {
      final w = m.group(0)!;
      if (w.length < 3 || _trStop.contains(w)) continue;
      out.add(w.length > 5 ? w.substring(0, 5) : w);
    }
    return out;
  }

  static final Set<String> _trStop = {
    've', 'ile', 'bir', 'için', 'gibi', 'olarak', 'veya', 'ya', 'da', 'de', 'bu', 'şu', 'çok', 'olan', 'olmak', 'etmek',
    'yapmak', 'kimse', 'şey', 'şeyi', 'birini', 'kullanılır', 'zaman', 'durum', 'durumunda',
  };

  static final Set<String> _stop = {
    ...stopWords,
    'would', 'could', 'should', 'will', 'can', 'may', 'might', 'must', 'shall', 'just', 'very', 'also', 'still', 'even',
    'said', 'say', 'get', 'got', 'like', 'much', 'many', 'more', 'most', 'such', 'other', 'another', 'own', 'same',
    'used', 'use', 'especially', 'usually', 'something', 'someone', 'somebody', 'anything', 'thing', 'things', 'way',
    'make', 'made', 'certain', 'etc', 'about', 'over', 'only', 'let', "let's", 'now', 'well', 'every', 'each',
    'these', 'those', 'your', 'our', 'his', 'her', 'its', 'their', 'him', 'them', 'yours', 'don', "don't", 'doesn',
    'not', 'no', 'yes', 'here', 'there', 'when', 'than', 'then', 'into', 'onto', 'upon', 'after', 'before', 'because',
  };

  static final Set<String> _persons = {
    'i', 'you', 'he', 'she', 'we', 'they', 'me', 'him', 'her', 'us', 'them', "let's", 'everyone', 'everybody', 'someone',
    'somebody', 'nobody', 'anyone', 'anybody', 'who', 'people', 'man', 'woman', 'men', 'women', 'boy', 'girl', 'child',
    'children', 'friend', 'friends', 'mother', 'father', 'sister', 'brother', 'teacher', 'student', 'doctor', 'family',
    'wife', 'husband', 'son', 'daughter', 'king', 'queen', 'baby', 'police', 'nanny', 'myself', 'yourself', 'himself',
    'herself', 'ourselves', 'themselves',
  };

  static const _pathWords = {'through', 'along', 'across', 'around', 'over', 'into', 'down', 'up', 'past', 'between'};
  static final _spatial = RegExp(r'\b(distance|space|extend|extends|stretch|between|location|lie|lies|reach|span)\b');

  static const _subjects = {'i', 'you', 'he', 'she', 'we', 'they', 'who', "let's", 'everyone', 'everybody', 'someone', 'somebody', 'nobody', 'anyone', 'anybody'};
  static const _finite = {'is', 'are', 'was', 'were', 'has', 'have', 'had', 'will', 'would', 'can', 'could', 'should', 'must', 'may', 'might', "isn't", "wasn't", "won't", "can't"};

  static final Set<String> _objPersons = {'me', 'you', 'him', 'her', 'us', 'them', 'myself', 'yourself', 'himself', 'herself'};

  static final Set<String> _dets = {
    'a', 'an', 'the', 'my', 'your', 'his', 'her', 'its', 'our', 'their', 'this', 'that', 'these', 'those', 'some', 'any',
    'no', 'every', 'each', 'another', 'all', 'both', 'one', 'two', 'three', 'many', 'much', 'more', 'few', 'several',
  };

  static final Set<String> _preps = {
    'in', 'on', 'at', 'to', 'into', 'onto', 'from', 'with', 'by', 'for', 'of', 'about', 'over', 'under', 'through',
    'across', 'along', 'around', 'up', 'down', 'off', 'out', 'away', 'back', 'behind', 'between', 'towards', 'toward',
    'after', 'before', 'until', 'till', 'against', 'during', 'without', 'within', 'near', 'past', 'like', 'as',
  };

  static final Set<String> _aux = {
    'be', 'am', 'is', 'are', 'was', 'were', 'been', 'being', 'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would',
    'can', 'could', 'should', 'shall', 'may', 'might', 'must', 'not', "n't", 'never', 'always', 'often', 'still', 'just',
    'also', 'already', 'really', 'to', "don't", "doesn't", "didn't", "won't", "can't", "isn't", "wasn't",
  };

  final Map<String, bool> _personNoun = {};

  /// Whether token [i] is written like a name: capitalised inside the
  /// sentence (not after a colon or an opening quote), and not a heading in
  /// capitals.
  static bool nameLike(String sentence, List<Token> toks, int i) {
    if (i <= 0 || i >= toks.length) return false;
    final t = toks[i].text;
    if (t.isEmpty || t[0] == t[0].toLowerCase()) return false;
    // In capitals: a short one is an abbreviation ("AP", "HR"), a long one
    // a heading ("MANAGEMENT").
    if (t == t.toUpperCase() && (t.length < 2 || t.length > 4)) return false;
    var k = toks[i].start - 1;
    while (k >= 0 && k < sentence.length && sentence[k] == ' ') {
      k--;
    }
    if (k < 0 || k >= sentence.length) return false;
    return !':"“‘(\'[-–—•*>'.contains(sentence[k]);
  }

  /// Whether a meaning is a name's own (a place, a month, a firm): WordNet
  /// writes such words with a capital, and so does their Turkish.
  static bool isNameSense(SenseCandidate c) {
    bool cap(String s) => s.isNotEmpty && s[0] != s[0].toLowerCase();
    return c.synonyms.any(cap) || (c.tr.isNotEmpty && cap(c.tr.first.trim()));
  }

  /// Whether a word names a person ("sister", "teacher", a name).
  bool isPerson(Token t, {bool sentenceStart = false}) {
    final w = t.lower;
    if (_persons.contains(w)) return true;
    // A capitalised word the dictionary does not know is a name ("Dorothy");
    // at the start of a sentence a known word is just a word ("Cracks").
    if (t.text.isNotEmpty && t.text[0] != t.text[0].toLowerCase() && !dict.lemmatizer.lemmas(w).any(_hasMeaning)) return true;
    return _personNoun.putIfAbsent(w, () {
      final l = lemmaOf(w);
      final r = dict.db.select(
          "SELECT s.gloss FROM sense x JOIN syn s ON s.id=x.syn_id WHERE x.lemma=? AND x.pos='n' ORDER BY x.rank LIMIT 1", [l]);
      if (r.isEmpty) return false;
      return RegExp(r'^(a |an |the )?(\w+ )?(person|man|woman|child|someone|one who|a member)\b').hasMatch(r.first.columnAt(0) as String);
    });
  }

  /// The [guessPos] rule (or one of [_guessPos]'s own) that decided the
  /// part of speech in the last [_guessPos] call; '-' when none did.
  String posRule = '-';

  /// Rules that decide the part of speech but are too often wrong to count
  /// as proof of it (measured on UD English-EWT dev+test: 10 % or more of
  /// their "sure" answers had another part of speech): with one of them, or
  /// none, a meaning of another part of speech must lose on the words of the
  /// sentence by [_posGap].
  static const _weakPosRules = {
    'participle', 'participleAfterBe', 'adjBeforeNoun', 'afterDegree', 'afterBe', 'nounSlot', 'adverbAfterVerb',
    'aloneAdverb', 'adjBeforeName', 'afterDet', 'verbBeforeDet', 'afterPrep',
  };
  static const _posGap = 0.08;

  /// How much more a later meaning must share with the sentence than the
  /// first meaning of its part of speech to be called sure.
  static const _firstSenseSem = 0.1;

  /// A review card is not graded when a checked meaning with other Turkish
  /// scores within this of the chosen one (a tie: the sentence does not tell).
  static const _fitTie = 0.01;

  String? _guessPos(List<Token> toks, int i, Set<String> available, {List<bool>? breaks}) {
    posRule = '-';
    final p = guessPos(toks, i, available, posOf: dict.posOf, breaks: breaks, why: (r) => posRule = r);
    if (p != null) return p;
    // Words on the far side of a comma or a full stop say nothing here.
    bool cut(int k) => breaks != null && breaks[k];
    final prev = i > 0 && !cut(i) ? toks[i - 1].lower : '';
    final prev2 = i > 1 && !cut(i) && !cut(i - 1) ? toks[i - 2].lower : '';
    final w0 = toks[i].lower;
    // "which animal it …": after which / what / whose comes a noun.
    if (available.contains('n') && const {'which', 'what', 'whose', 'whichever', 'whatever'}.contains(prev)) {
      posRule = 'afterWh';
      return 'n';
    }
    final verbForm = dict.irregularOf.containsKey(w0) || RegExp(r'(ed|ing)$').hasMatch(w0);
    // "the river bank": a noun after determiner + noun is a noun ("the
    // children came" is not: "came" is a verb form, "children" a plural).
    if (!verbForm && available.contains('n') && _dets.contains(prev2) && dict.posOf(prev).contains('n') && !prev.endsWith('s') &&
        !_persons.contains(prev)) {
      posRule = 'nounAfterDetNoun';
      return 'n';
    }
    // An adjective stands before a noun or after be / seem; otherwise a
    // word that is also a noun is a noun.
    final nextW = i + 1 < toks.length && !cut(i + 1) ? toks[i + 1].lower : '';
    if (available.contains('n') && available.contains('a') && !verbForm) {
      final np = nextW.isEmpty ? const <String>{} : dict.posOf(nextW);
      final beforeNoun = np.contains('n') && !_preps.contains(nextW) && !_objPersons.contains(nextW) && nextW != 'it';
      const linking = {'is', 'are', 'was', 'were', 'be', 'been', 'being', 'seem', 'seems', 'seemed', 'look', 'looks', 'looked', 'feel', 'felt', 'become', 'became', 'very', 'so', 'too', 'quite', 'more', 'most'};
      // Only where a noun group goes: after a determiner, a preposition or a
      // possessive ("the public", "in public"); after a verb or at the start
      // the word is as often an adjective or an adverb ("seems clear", "Glad to").
      final npSlot = _dets.contains(prev) || (_preps.contains(prev) && prev != 'to') || (i > 0 && !cut(i) && toks[i - 1].lower.endsWith("'s"));
      if (!beforeNoun && !linking.contains(prev) && npSlot) {
        posRule = 'nounSlot';
        return 'n';
      }
    }
    // "a long run": determiner + adjective + word.
    if (!verbForm && available.contains('n') && _dets.contains(prev2) && dict.posOf(prev).contains('a')) {
      posRule = 'nounAfterDetAdj';
      return 'n';
    }
    // "She runs a small company": a verb before a determiner.
    final next = nextW;
    if (available.contains('v') && (_dets.contains(next) || _objPersons.contains(next)) && !_dets.contains(prev)) {
      posRule = 'verbBeforeDet';
      return 'v';
    }
    // After a subject pronoun ("they run"). A name or a person noun before the
    // word is as often the first half of a compound ("police station", "US
    // troops", "Fallujah campaign"), so it says nothing.
    if (available.contains('v') && _subjects.contains(prev)) {
      posRule = 'afterSubject';
      return 'v';
    }
    // "Rector's next stop was …": right before a finite verb, after anything
    // but a subject, stands the subject: a noun.
    if (available.contains('n') && _finite.contains(nextW) && !_subjects.contains(prev) && !_aux.contains(prev) && prev != 'to') {
      posRule = 'beforeFinite';
      return 'n';
    }
    return null;
  }

  void _score(SenseCandidate c, _Context ctx, String? pos, _Shape shape, List<Token> toks, int head, int last,
      {List<String> particles = const [], Expr? phrase}) {
    final skip = {c.lemma, ...c.lemma.split(' ')};
    // 1. Meaning: overlap between the definition (with examples and
    // synonyms) and the sentence, the sentence widened by its words' own
    // definitions; plus Turkish overlap for meanings without English.
    final sig = <String>{
      ...bag(c.en ?? '', skip: skip),
      ...bag(c.explainEn ?? '', skip: skip),
      for (final e in c.examples) ...bag(e, skip: skip),
      for (final s in c.synonyms) if (!s.contains(' ')) s.toLowerCase(),
    };
    var raw = 0.0, wideRaw = 0.0;
    var wideN = 0;
    for (final x in sig) {
      if (ctx.words.contains(x)) {
        raw += idf(x);
        c.hits.add(x);
      } else if (ctx.wide.contains(x)) {
        wideRaw += 0.4 * idf(x);
        wideN++;
        c.hits.add('~$x');
      }
    }
    // One word shared only through a definition is often chance ("wall …
    // structure or function"); two or more are a real link.
    raw += wideN >= 2 ? wideRaw : wideRaw * 0.4;
    final trSig = <String>{
      for (final t in c.tr) ...turkishStems(t),
      ...turkishStems(c.note ?? ''),
      for (final t in c.examplesTr) ...turkishStems(t),
    };
    raw += trSig.intersection(ctx.trWords).length * 0.75;
    final sem = 1 - exp(-raw / 1.2);

    // 2. Part of speech.
    // An expression found in its own words stands where its part of speech
    // belongs: the word-by-word reading gets no head start from grammar, and
    // has to win on what the sentence is about.
    // That head start decides which meaning is shown, but it is no evidence:
    // it is kept apart ("free") and left out when [_decide] asks how sure.
    final posOwn = pos == null || c.pos == null ? 0.5 : (c.pos == pos ? 1.0 : 0.0);
    final posS = phrase != null && !c.literal ? 1.0 : posOwn;

    // 3. Shape: object or not, who does it, what follows.
    // Object and subject say something about verbs only.
    final verbish = c.pos == 'v' || phrase != null;
    final prof = verbish ? _Profile.of(this, c, phrase) : _Profile(0, 0.5, 0, 0.5, 0);
    final feats = <double>[];
    if (prof.objects > 0) feats.add(shape.hasObject == (prof.objectShare >= 0.5) ? 1.0 : (prof.objectShare - 0.5).abs() < 0.2 ? 0.5 : 0.0);
    // Who does it: examples that always have a person doing it ("we
    // rehearse") do not fit a thing as subject ("cracks"), and the other way
    // round. A clash like that is strong evidence against the meaning.
    var clash = 1.0;
    if (prof.subjects > 0 && shape.subjectKnown) {
      final f = shape.personSubject == (prof.personSubjectShare >= 0.5) ? 1.0 : 0.0;
      feats.add(f);
      final extreme = prof.personSubjectShare >= 0.8 || prof.personSubjectShare <= 0.2;
      if (extreme && f == 0) clash = prof.subjects >= 2 ? 0.75 : 0.88;
    }
    // A person as object ("know her") fits meanings about people.
    final glossPerson = RegExp(r'\b(person|someone|somebody|people|acquainted|companion)\b').hasMatch(c.en ?? '');
    if (verbish && shape.personObject) {
      // strong evidence: counted twice
      final f = glossPerson || prof.personObjectShare >= 0.5 ? 1.0 : 0.0;
      feats
        ..add(f)
        ..add(f);
    } else if (verbish && shape.hasObject && glossPerson && !RegExp(r'\b(object|thing|something)\b').hasMatch(c.en ?? '')) {
      feats.add(0.2);
    }
    var spatial = 1.0;
    if (particles.isNotEmpty) {
      // Literal reading: a definition that names the particle fits it
      // ("live in"); with a path word and a thing as subject ("cracks run
      // through the wall") a meaning about extending in space fits.
      final g = '${c.en ?? ''} ${c.examples.join(' ')}'.toLowerCase();
      final path = particles.any(_pathWords.contains) && shape.subjectKnown && !shape.personSubject;
      if (path) {
        final sp = _spatial.hasMatch(c.en ?? '');
        feats.add(sp ? 1.0 : 0.2);
        spatial = sp ? 1.15 : 0.92;
      } else {
        feats.add(particles.any((p) => RegExp('\\b$p\\b').hasMatch(g)) ? 0.8 : 0.4);
      }
    }
    if (phrase != null) {
      // The dictionary found the expression: that counts for it, unless its
      // examples always use it without an object and here one follows
      // ("live in" = live at the workplace; "lived in Kansas" is not that).
      feats.add(prof.objects > 0 && prof.objectShare < 0.2 && shape.hasObject ? 0.0 : 1.0);
    }
    final pat = feats.isEmpty ? 0.5 : feats.reduce((a, b) => a + b) / feats.length;

    // 4. Examples: the words right around the word in the dictionary's
    // examples against the sentence ("look up at the stars" / "looked up at the sky").
    var exS = 0.0;
    for (final e in c.examples) {
      exS = max(exS, _exampleSim(e, c.lemma, toks, head, last));
    }
    if (c.examples.isEmpty) exS = 0.3;

    // 5. Frequency: the dictionary's order, and for WordNet senses also the
    // place of their Turkish in the main meaning list, which follows how
    // often a meaning is met (WordNet puts the baseball "run" first).
    var rank = c.rank.toDouble();
    if (c.source == 'wordnet' && c.tr.isNotEmpty) {
      final ft = mainTr(c.lemma);
      for (var i = 0; i < ft.length && i < 4; i++) {
        if (_split(ft[i]).contains(c.tr.first)) {
          rank = min(rank, i * 1.0);
          break;
        }
      }
    }
    var fr = 1 / (1 + rank * 0.6);
    if (c.tr.isEmpty) fr *= 0.6;

    c.parts
      ..['sem'] = sem
      ..['pos'] = posS
      ..['pat'] = pat
      ..['ex'] = exS
      ..['fr'] = fr;
    c.score = (w.semantic * sem + w.pos * posS + w.pattern * pat + w.example * exS + w.frequency * fr) * clash * spatial;
    // A clear part of speech in the sentence ("a long run" is a noun) rules
    // out most of the other parts of speech.
    if (posS == 0.0) c.score *= 0.8;
    var own = (w.semantic * sem + w.pos * posOwn + w.pattern * pat + w.example * exS + w.frequency * fr) * clash * spatial;
    if (posOwn == 0.0) own *= 0.8;
    c.parts['free'] = c.score - own;
    // A meaning with Turkish of its own wins a tie over one without.
    if (c.tr.isNotEmpty) c.score += 0.02;
    // A checked source wins a tie over an unreviewed AI draft.
    if (c.unverified) c.score -= 0.01;
    if (c.literal) c.score -= 0.06; // the expression wins a near tie
  }

  /// How much an example sentence looks like the sentence around the word:
  /// the word that follows, the kind of word that follows, the content words.
  double _exampleSim(String example, String lemma, List<Token> toks, int head, int last) {
    final et = tokenize(example);
    final parts = lemma.split(' ');
    var at = -1, end = -1;
    for (var i = 0; i < et.length && at < 0; i++) {
      if (et[i].lower == parts.first || dict.lemmatizer.lemmas(et[i].lower).contains(parts.first)) {
        at = i;
        end = i;
        // the rest of a phrase, possibly with an object in between ("look it up")
        var k = 1;
        for (var j = i + 1; j < et.length && j <= i + 4 && k < parts.length; j++) {
          if (et[j].lower == parts[k]) {
            end = j;
            k++;
          }
        }
      }
    }
    if (at < 0) return 0.1;
    var s = 0.0;
    String cls(String w) => w.isEmpty
        ? 'end'
        : _dets.contains(w)
            ? 'det'
            : _objPersons.contains(w) || w == 'it'
                ? 'pron'
                : _preps.contains(w)
                    ? 'prep:$w'
                    : 'word';
    final nextS = last + 1 < toks.length ? toks[last + 1].lower : '';
    final nextE = end + 1 < et.length ? et[end + 1].lower : '';
    final cs = cls(nextS), ce = cls(nextE);
    if (nextS == nextE && nextS.isNotEmpty) {
      s += 0.5;
    } else if (cs == ce || (cs != 'end' && ce != 'end' && !cs.startsWith('prep') && !ce.startsWith('prep'))) {
      s += 0.3;
    }
    // an object between the words ("look the word up") counts as an object
    final sb = bag(example, skip: {...parts});
    final cb = <String>{
      for (var i = 0; i < toks.length; i++)
        if (i < head || i > last) ...bag(toks[i].text),
    };
    final ov = sb.intersection(cb).length;
    s += min(0.5, ov * 0.25);
    return min(1.0, s);
  }

  // -------------------------------------------------------------- deciding

  ContextSense _decide(String headword, String? cat, String? headLemma, List<SenseCandidate> cands0, _Context ctx, _Shape shape,
      String? pos) {
    final cands = [...cands0]..sort((a, b) => b.score.compareTo(a.score));
    var best = cands.first;
    // The dictionary's first meaning of the same part of speech and source:
    // a later meaning has to win on what the sentence is about, not on the
    // shape of the sentence or an example's wording, which are often chance.
    SenseCandidate? firstOfPos;
    for (final c in cands) {
      if (c.pos == best.pos && c.source == best.source && !c.literal && c.literal == best.literal && (firstOfPos == null || c.rank < firstOfPos.rank)) firstOfPos = c;
    }
    // (Not for an expression's own senses: their examples were written to
    // tell them apart, "look up at the sky" against "look up a word".)
    final notFirst = firstOfPos != null &&
        best.source != 'expr' &&
        !identical(firstOfPos, best) &&
        firstOfPos.tr.isNotEmpty &&
        !firstOfPos.tr.any(best.tr.contains) &&
        (best.parts['sem'] ?? 0) < (firstOfPos.parts['sem'] ?? 0) + _firstSenseSem;
    final isLiteral = cat != null && best.literal;
    // Turkish for a meaning that has none of its own.
    if (best.tr.isEmpty) {
      final d = _deriveTr(best, ctx);
      if (d != null) {
        best = best.withTr(d, derived: true);
      }
    }
    final rest = cands.skip(1).toList();
    if (best.tr.isEmpty) {
      return ContextSense(
        headword: isLiteral ? best.lemma : headword,
        cat: isLiteral ? null : cat,
        literalPhrase: isLiteral ? headword : null,
        confidence: SenseConfidence.none,
        best: best,
        others: _others(rest, best),
        reason: 'no Turkish for ${best.id}',
        ranked: cands,
      );
    }
    // The most fitting Turkish first: a meaning the losing senses do not share.
    final clearLosers = rest.where((c) => c.score < best.score - 0.12).toList();
    final ft = mainTr(best.lemma);
    int ftRank(String t) {
      for (var i = 0; i < ft.length; i++) {
        if (_split(ft[i]).contains(t) || ft[i] == t) return i;
      }
      return 99;
    }

    // When the sentence itself (not just frequency) set the meaning apart
    // ("runs a company", "know her"), Turkish the losing meanings share is
    // put last ("koşmak" belongs to running, "bilmek" to knowing a fact).
    double nonFreq(SenseCandidate c) => c.score - w.frequency * (c.parts['fr'] ?? 0);
    final bestNf = nonFreq(best);
    final ordered = [...best.tr]
      ..sort((a, b) {
        double v(String t) {
          var x = 1 / (1 + ftRank(t));
          final owners = clearLosers.where((c) => c.tr.contains(t));
          if (owners.isNotEmpty && bestNf - owners.map(nonFreq).reduce(max) >= 0.12) x -= 2;
          return x;
        }

        return v(b).compareTo(v(a));
      });
    best = best.withTr(ordered, derived: best.trDerived);
    final shown = best.tr.take(3).toSet();

    // How sure: a close rival with a different Turkish meaning makes it a guess.
    // An expression's head start over the word-by-word reading decides what
    // is shown, but it is not counted as evidence for the expression.
    final free = best.parts['free'] ?? 0;
    double lead(SenseCandidate c) => best.score - c.score - (c.literal && !best.literal ? free : 0);
    double leadNf(SenseCandidate c) => lead(c) - w.frequency * ((best.parts['fr'] ?? 0) - (c.parts['fr'] ?? 0));
    const margin = 0.06;
    final close = rest.where((c) => lead(c) <= margin).toList();
    final dissent = close.where((c) => c.tr.isEmpty ? lead(c) <= 0.02 : !c.tr.any(shown.contains)).toList();
    // Sure only when (a) the sentence itself, not frequency, sets this
    // meaning apart from the best rival with other Turkish, (b) it is the
    // word's main meaning and nothing close says otherwise, or (c) every
    // meaning of this part of speech has this Turkish.
    final rivals = rest.where((c) => c.tr.isNotEmpty && !c.tr.any(shown.contains)).toList();
    final gap = rivals.isEmpty ? 1.0 : leadNf(rivals.reduce((a, b) => lead(a) <= lead(b) ? a : b));
    final mainFirst = ft.isNotEmpty && _split(ft.first).any(shown.contains);
    final mainOk = mainFirst && gap >= -0.04;
    final samePos = cands.where((c) => c.tr.isNotEmpty && (pos == null || c.pos == null || c.pos == pos));
    final evidence = gap >= 0.08 || mainOk || samePos.every((c) => c.tr.any(shown.contains));
    // The part of speech: when the words around do not settle it (no cue,
    // or a cue that is often wrong), a meaning of another part of speech
    // with other Turkish has to lose on what the sentence says, not on
    // frequency or on that cue.
    final weakPos = pos == null || _weakPosRules.contains(posRule);
    final otherPos = rest.where((c) => c.pos != null && best.pos != null && c.pos != best.pos && !c.tr.any(shown.contains)).toList();
    var posUnclear = false;
    if (weakPos && otherPos.isNotEmpty) {
      // The shape of the sentence (an object follows, …) is judged for verbs
      // only, so across parts of speech it is no evidence either.
      double nf(SenseCandidate c) =>
          leadNf(c) - w.pos * ((best.parts['pos'] ?? 0.5) - (c.parts['pos'] ?? 0.5)) - w.pattern * ((best.parts['pat'] ?? 0.5) - (c.parts['pat'] ?? 0.5));
      final g = otherPos.map(nf).reduce(min);
      if (g < _posGap) posUnclear = true;
    }
    final weak = best.score < 0.3;
    // An AI draft alone is no proof: "sure" only when a checked meaning has
    // the same Turkish. The main meaning list (ft) does not count: it has no part of speech
    // (in "Rector's next stop" the noun's draft would be corroborated by the
    // verb "durmak"), and the drafts were written from it, so the two are one
    // source, not two. Only a checked meaning of the same part of speech does.
    final checked = <String>{
      for (final c in cands)
        if (!c.unverified && (c.pos == null || best.pos == null || c.pos == best.pos)) ...c.tr.expand(_split),
    };
    final uncorroborated = best.unverified && !shown.expand(_split).any(checked.contains);
    // Turkish whose form does not fit the part of speech ("elaborate" the
    // verb shown as "mufassal", the noun "stop" as "durmak") is a sign that
    // the meaning or its Turkish is mixed up.
    final trVerb = shown.where(DictDb.isTrVerb).length;
    final shapeClash = best.pos != null && shown.isNotEmpty && (best.pos == 'v' ? trVerb == 0 : trVerb == shown.length);
    final SenseConfidence conf;
    String reason;
    if (weak) {
      conf = SenseConfidence.none;
      reason = 'weak ${best.score.toStringAsFixed(2)}';
    } else if (best.trDerived || uncorroborated || dissent.isNotEmpty || !evidence || posUnclear || notFirst || shapeClash) {
      conf = SenseConfidence.likely;
      reason = best.trDerived
          ? 'derived Turkish'
          : uncorroborated
              ? 'unverified draft'
              : dissent.isNotEmpty
                  ? 'close: ${dissent.map((c) => c.id).join(',')}'
                  : !evidence
                      ? 'no clear evidence'
                      : posUnclear
                          ? 'part of speech unclear'
                          : notFirst
                              ? 'not the first meaning'
                              : 'Turkish does not fit the part of speech';
    } else {
      conf = SenseConfidence.sure;
      reason = 'clear';
    }
    return ContextSense(
      headword: isLiteral ? best.lemma : headword,
      cat: isLiteral ? null : cat,
      literalPhrase: isLiteral ? headword : null,
      confidence: conf,
      best: best,
      others: _others(rest, best),
      reason: '$reason; ${best.id} ${best.score.toStringAsFixed(3)} pos:$posRule',
      ranked: cands,
    );
  }

  /// The other meanings worth listing: with a Turkish meaning different from
  /// the chosen one, best fitting first, one line per Turkish meaning.
  List<SenseCandidate> _others(List<SenseCandidate> rest, SenseCandidate best) {
    final seen = <String>{...best.tr.take(3)};
    final out = <SenseCandidate>[];
    for (final c in rest) {
      if (c.tr.isEmpty) continue;
      final t = c.tr.where((x) => !seen.contains(x)).toList();
      if (t.isEmpty) continue;
      seen.addAll(t);
      out.add(c.withTr(t, derived: c.trDerived));
      if (out.length >= 8) break;
    }
    return out;
  }

  /// A Turkish meaning for a sense that has none: the word's main meaning
  /// that shares words with the Turkish of the sense's synonyms, definition
  /// and sentence ("river bank" → "nehir/göl kıyısı");
  /// Turkish ("stretch out" → "uzanmak"). Null when nothing fits.
  List<String>? _deriveTr(SenseCandidate c, _Context ctx) {
    final ft = mainTr(c.lemma);
    final want = <String>{...ctx.trWords};
    final synTr = <String>[];
    for (final s in c.synonyms.take(6)) {
      if (s.split(' ').length > 2) continue;
      final l = s.toLowerCase();
      for (final x in dict.lookup(l).senses.where((x) => DictDb.normPos(x.pos) == c.pos && x.tr.isNotEmpty).take(1)) {
        synTr.addAll(_cleanTr(x.tr).take(2));
      }
      for (final t in mainTr(l).take(2)) {
        if ((DictDb.isTrVerb(t)) == (c.pos == 'v')) synTr.addAll(_split(t).take(2));
      }
    }
    for (final t in synTr) {
      want.addAll(turkishStems(t));
    }
    for (final g in bag(c.en ?? '', skip: {c.lemma}).take(8)) {
      want.addAll(trStems(g));
    }
    // 1. A main meaning that shares words with the sentence ("river" → nehir).
    String? fromCtx;
    var ctxHit = 0;
    for (final item in ft) {
      for (final part in item.split(RegExp(r'[,;]'))) {
        final p = part.trim();
        if (p.isEmpty || ((DictDb.isTrVerb(p)) != (c.pos == 'v') && c.pos != null)) continue;
        final hit = turkishStems(p).intersection(ctx.trWords).length;
        if (hit > ctxHit) {
          ctxHit = hit;
          fromCtx = p;
        }
      }
    }
    if (fromCtx != null) return [fromCtx];
    // A synonym's own Turkish is not used on its own: "go" is a synonym of
    // run "stretch out", but "gitmek" would be wrong. Better no Turkish than
    // a wrong one.
    // 2. A main meaning sharing words with the synonyms' and definition's Turkish.
    String? pick;
    var bestHit = 0;
    for (final item in ft) {
      for (final part in item.split(RegExp(r'[,;]'))) {
        final p = part.trim();
        if (p.isEmpty) continue;
        if ((DictDb.isTrVerb(p)) != (c.pos == 'v') && c.pos != null) continue;
        final hit = turkishStems(p).intersection(want).length;
        if (hit > bestHit) {
          bestHit = hit;
          pick = p;
        }
      }
    }
    if (pick != null && bestHit >= 2) return [pick];
    return null;
  }
}

/// The words of the sentence the meanings are compared with.
class _Context {
  final Set<String> words; // content lemmas of the sentence
  final Set<String> wide; // words of their definitions
  final Set<String> trWords; // Turkish stems of their meanings
  _Context(this.words, this.wide, this.trWords);

  static _Context of(SenseEngine e, List<Token> toks, Set<int> skip, String? prev, String? next) {
    final words = <String>{};
    final lemmas = <String>[];
    for (var i = 0; i < toks.length; i++) {
      if (skip.contains(i)) continue;
      final w = toks[i].lower;
      if (w.length < 3 || SenseEngine._stop.contains(w)) continue;
      // Names (capitalised inside a sentence) say nothing about meaning.
      if (i > 0 && toks[i].text[0] != toks[i].lower[0]) continue;
      final ls = [e.lemmaOf(w), ...e.dict.lemmatizer.lemmas(w)];
      words.addAll(ls.take(2));
      // Only nouns and adjectives are widened with their definitions: verbs
      // like "go" have so many senses that they would match anything.
      final lp = e.dict.lemmaPos(ls.first);
      final verbForm = ls.first != w && lp.contains('v');
      if (!verbForm && (lp.contains('n') || lp.contains('a'))) lemmas.add(ls.first);
    }
    // Neighbouring sentences help a little; long texts are cut so a tap stays fast.
    for (final s in [prev, next]) {
      if (s == null) continue;
      for (final l in e.bag(s).take(10)) {
        words.add(l);
      }
    }
    final near = lemmas.take(24).toList();
    final wide = <String>{for (final l in near) ...e.glossBag(l)}..removeAll(words);
    final tr = <String>{for (final l in near) ...e.trStems(l)};
    return _Context(words, wide, tr);
  }
}

/// The shape of the sentence around the word: is there an object, who is
/// the subject.
class _Shape {
  final bool hasObject;
  final bool personObject;
  final bool subjectKnown;
  final bool personSubject;
  _Shape(this.hasObject, this.personObject, this.subjectKnown, this.personSubject);

  static _Shape inSentence(SenseEngine e, List<Token> toks, int head, int last, {List<bool>? breaks}) {
    // object: what follows the word (or the last word of the expression),
    // in the same clause ("He showered, shaved": "shaved" is no object)
    final j = last + 1;
    var obj = false, personObj = false;
    if (j < toks.length && !(breaks != null && breaks[j])) {
      final n = toks[j].lower;
      if (SenseEngine._dets.contains(n) || n == 'it' || SenseEngine._objPersons.contains(n)) {
        obj = true;
      } else if (!SenseEngine._preps.contains(n) && !SenseEngine._aux.contains(n) && !const {'and', 'or', 'but', 'when', 'while', 'if', 'because', 'so'}.contains(n)) {
        final p = e.dict.posOf(n);
        // "run well", "run fast": an adverb is not an object
        obj = (p.contains('n') && !p.contains('r')) || (p.isEmpty && toks[j].text[0] != toks[j].lower[0]);
      }
      if (obj) {
        personObj = SenseEngine._objPersons.contains(n) || e.isPerson(toks[j]) && !SenseEngine._dets.contains(n);
        if (!personObj && SenseEngine._dets.contains(n) && n != 'that' && n != 'this') {
          for (var k = j + 1; k < toks.length && k <= j + 3; k++) {
            final w = toks[k].lower;
            if (SenseEngine._dets.contains(w)) continue;
            if (SenseEngine._persons.contains(w) && !SenseEngine._objPersons.contains(w)) break;
            final pos = e.dict.posOf(w);
            if (pos.contains('n') && e.isPerson(toks[k])) personObj = true;
            if (pos.contains('n')) break;
          }
        }
      }
    }
    // An object between verb and particle ("look the word up", "turn it off").
    if (!obj && last > head + 1) obj = true;
    // subject: the word before the verb, skipping helpers ("is", "will", "not")
    var k = head - 1;
    while (k >= 0 && SenseEngine._aux.contains(toks[k].lower)) {
      k--;
    }
    var known = false, person = false;
    if (k >= 0) {
      final s = toks[k];
      known = !SenseEngine._preps.contains(s.lower) && !SenseEngine._dets.contains(s.lower);
      person = known && e.isPerson(s, sentenceStart: k == 0);
      // "Let's run through …": the speaker
      if (s.lower == "let's" || s.lower == 'let') {
        known = true;
        person = true;
      }
    }
    return _Shape(obj, personObj, known, person);
  }
}

/// What the dictionary's examples of a meaning look like.
class _Profile {
  final int objects; // examples where the object could be judged
  final double objectShare;
  final int subjects;
  final double personSubjectShare;
  final double personObjectShare;
  _Profile(this.objects, this.objectShare, this.subjects, this.personSubjectShare, this.personObjectShare);

  static final Map<String, _Profile> _cache = {};

  // The profile is read for the candidate's own word ([SenseCandidate.lemma]):
  // a WordNet meaning is shared by its synonyms ("get" and "become"), so the
  // word is part of the key. Without it a meaning looked at first for one
  // word was reused for the other, and an answer depended on what had been
  // tapped before (the reader and a review card could disagree; Task 5F).
  static _Profile of(SenseEngine e, SenseCandidate c, Expr? phrase) => _cache.putIfAbsent('${e.dictVersion}|${c.id}|${c.lemma}|${c.literal}', () {
        var objN = 0, obj = 0, subjN = 0, subj = 0, pObj = 0;
        final parts = c.lemma.split(' ');
        for (final ex in c.examples) {
          final t = tokenize(ex);
          var at = -1;
          for (var i = 0; i < t.length; i++) {
            if (t[i].lower == parts.first || e.dict.lemmatizer.lemmas(t[i].lower).contains(parts.first)) {
              at = i;
              break;
            }
          }
          if (at < 0) continue;
          var last = at;
          var k = 1;
          for (var j = at + 1; j < t.length && j <= at + 4 && k < parts.length; j++) {
            if (t[j].lower == parts[k]) {
              last = j;
              k++;
            }
          }
          // the example must end where the sentence ends or go on, not be cut
          final sh = _Shape.inSentence(e, t, at, last, breaks: clauseBreaks(ex, t));
          final endsHere = last + 1 >= t.length;
          objN++;
          if (sh.hasObject) obj++;
          if (sh.personObject) pObj++;
          if (endsHere && !sh.hasObject) {} // intransitive use, counted above
          if (sh.subjectKnown) {
            subjN++;
            if (sh.personSubject) subj++;
          }
        }
        return _Profile(objN, objN == 0 ? 0.5 : obj / objN, subjN, subjN == 0 ? 0.5 : subj / subjN, objN == 0 ? 0 : pObj / objN);
      });
}
