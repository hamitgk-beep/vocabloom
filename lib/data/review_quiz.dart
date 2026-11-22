import 'dart:math';

import '../nlp/context_sense.dart';
import '../nlp/text.dart';
import 'dict_db.dart';
import 'tr_en_dict.dart';
import 'user_db.dart';

/// The right answer of a review card: the saved word's most common meaning.
class QuizAnswer {
  /// Turkish meaning, or null when neither the dictionary nor the AI service
  /// knows the Turkish of the word.
  final String? tr;

  /// Part of speech of that sense (n, v, a, r), when known.
  final String? pos;

  /// English definition of that sense, when known.
  final String? gloss;

  /// False when [tr] is the dictionary's best guess for a sense it has no
  /// Turkish for (the AI service, when set up, is asked instead).
  final bool sure;

  /// WordNet sense used in the sentence, when known (for missing-word reports).
  final int? synId;

  /// False when [tr] must not be graded as the one right option: it does not
  /// fit the card's sentence, or it rests only on an unverified AI draft. The
  /// card is then a plain flashcard (no AI request, no missing-word report).
  final bool choice;

  /// True when [tr] is the meaning saved on the card (kept as it was saved).
  final bool saved;
  const QuizAnswer(this.tr, this.pos, this.gloss, {this.sure = true, this.synId, this.choice = true, this.saved = false});
}

class QuizChoice {
  final List<String> options;
  final int correct;
  const QuizChoice(this.options, this.correct);
  String get right => options[correct];
}

/// Builds the four-choice question of a review card.
///
/// The right option is the word's most common meaning, not the one of the
/// sentence it was saved from ("through" is "boyunca", not "aktarmasız"), and
/// the three wrong options are meanings of other words of the same part of speech
/// that are not also meanings of this word.
class ReviewQuiz {
  final DictDb dict;
  final UserDb user;
  final Random rnd;
  /// Turkish dictionary, for review cards while learning Turkish.
  final TrEnDict? trEn;
  ReviewQuiz(this.dict, this.user, {Random? rnd, this.trEn}) : rnd = rnd ?? Random();

  /// Learning Turkish: the answers are English meanings.
  bool get _tr => user.lang == 'tr' && trEn != null;

  final _answers = <String, QuizAnswer>{};

  static final _split = RegExp(r'[,;]');
  static final _wordSplit = RegExp(r'[ ,;]+');

  /// Drops the remembered answer of [w] (a new AI meaning arrived).
  void forget(SavedWord w) => _answers.remove('${w.lemma}|${w.context}');

  QuizAnswer answerFor(SavedWord w) => _answers.putIfAbsent('${w.lemma}|${w.context}', () => _answerFor(w));

  QuizAnswer _answerFor(SavedWord w) {
    final lemma = w.lemma;
    if (_tr) {
      final m = w.meaning ?? trEn!.shortMeaning(lemma);
      return QuizAnswer(m == null || m.trim().isEmpty ? null : DictDb.shortTr(m), null, null);
    }
    if (lemma.contains(' ')) {
      final e = dict.exprs.where((e) => e.phrase == lemma).firstOrNull;
      // 1. The meaning saved on the card, as it was saved.
      final kept = _keptMeaning(w, e?.en == null ? const [] : [e!.en!]);
      if (kept != null) return QuizAnswer(DictDb.shortTr(kept), null, e?.en, saved: true);
      // 2. Nothing saved: the dictionary's own meaning. An unverified AI draft
      // (or an AI service meaning) is shown, but never graded as the answer.
      final tr = e?.tr ?? e?.trShown;
      return QuizAnswer(tr == null || tr.trim().isEmpty ? null : DictDb.shortTr(tr), null, e?.en, choice: e?.tr != null);
    }
    final ctx = w.context;
    // 1. The meaning saved on the card is kept, whatever the dictionary's
    // order is now. Only a meaning of the wrong kind for the sentence (a verb
    // for a noun: "akmak" for "a golf course") is not graded.
    final kept = _keptMeaning(w, [for (final s in dict.lookup(lemma).senses) s.gloss, for (final o in dict.ownSenses(lemma)) o.en]);
    if (kept != null) {
      final k = DictDb.shortTr(kept);
      final c = dict.commonMeaning(lemma);
      final clash = ctx != null && _contradicts(lemma, ctx, k, posOnly: true);
      return QuizAnswer(k, DictDb.isTrVerb(k) ? 'v' : (c.tr != null && _overlap(c.tr!, k) ? c.pos : null),
          c.tr != null && _overlap(c.tr!, k) ? c.gloss : null,
          choice: !clash, saved: true);
    }
    // 2. Nothing saved (old cards, or no reliable meaning when it was saved):
    // what was shown then is not known, so the dictionary's common meaning by
    // the source order. When the card's sentence clearly uses another meaning,
    // it is not graded as the right answer ("bank" of a river is not "banka").
    final m = dict.commonMeaning(lemma);
    final self = m.tr == null ? dict.exprs.where((e) => e.phrase == lemma && e.trShown != null).firstOrNull : null;
    // Only with no Turkish at all: the meaning the AI service gave for the sentence.
    final ai = m.tr != null || self != null || ctx == null ? null : user.contextAi(lemma, ctx);
    if (m.tr == null) {
      final st = self?.trShown;
      return QuizAnswer((st == null ? null : DictDb.shortTr(st)) ?? ai, m.pos, m.gloss, choice: self == null || self.tr != null);
    }
    final fits = ctx == null || !_contradicts(lemma, ctx, m.tr!);
    // The common meaning resting only on an AI draft is never graded.
    final drafted = dict.lookup(lemma).trFreeDict.isEmpty && dict.ownSenses(lemma).isEmpty && dict.lookup(lemma).senses.every((s) => s.tr.isEmpty);
    return QuizAnswer(m.tr, m.pos, m.gloss, choice: fits && !drafted);
  }

  /// The card's saved meaning, unless it is empty, a cross reference or an
  /// English definition ([glosses]) saved when no Turkish was known.
  static String? _keptMeaning(SavedWord w, Iterable<String> glosses) {
    final k = w.meaning?.trim();
    if (k == null || k.isEmpty || k.toLowerCase().contains('bakınız')) return null;
    if (glosses.any((g) => g.trim() == k)) return null;
    return k;
  }

  late final SenseEngine _senses = SenseEngine(dict);

  /// Whether the card's sentence clearly uses [lemma] in another meaning than
  /// [answer]: the context picker is sure (and not resting on an AI draft),
  /// its Turkish shares nothing with [answer], and [answer] is of the other
  /// kind (a verb for a noun or the other way round) or is the Turkish of
  /// another WordNet sense of the word ("banka" for the bank of a river).
  /// [posOnly]: only the first test (for a saved meaning, which is kept).
  bool _contradicts(String lemma, String sentence, String answer, {bool posOnly = false}) {
    final toks = tokenize(sentence);
    final i = dict.indexOfLemma(toks, lemma);
    if (i < 0) return false;
    final c = _senses.resolve(SenseQuery(sentence: sentence, tokens: toks, index: i, lemma: lemma));
    final b = c.best;
    // Only a sure choice: "likely" ones would turn a fifth of the cards into
    // flashcards (measured on 1,500 common words), mostly for synonyms.
    if (c.confidence != SenseConfidence.sure || !c.shown || c.cat != null || b == null || b.unverified) return false;
    if ([...b.tr, c.tr!].any((t) => _overlap(t, answer))) return false;
    final p = b.pos;
    if ((p == 'n' || p == 'v') && (p == 'v') != DictDb.isTrVerb(DictDb.shortTr(answer))) return true;
    if (posOnly) return false;
    final senses = dict.lookup(lemma).senses;
    final tied = {for (final x in senses) if (_overlap(x.tr.join(', '), answer)) 'wn:${x.synId}'};
    if (tied.isNotEmpty) return !tied.contains(b.id);
    // [answer] belongs to no sense (a FreeDict meaning): only a clear choice
    // of a rarer sense of the word counts ("saha" of a golf course, not "mecra").
    final first = senses.where((x) => DictDb.normPos(x.pos) == p).firstOrNull;
    return c.reason.startsWith('clear') && first != null && 'wn:${first.synId}' != b.id;
  }

  static bool _overlap(String a, String b) {
    Set<String> p(String t) => t.toLowerCase().split(_split).map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    return p(a).intersection(p(b)).isNotEmpty;
  }

  late final List<SavedWord> _saved = [
    for (final st in [WordStatus.learning, WordStatus.learned]) ...user.words(st),
  ]..shuffle(rnd);

  final _senseTr = <String?, List<String>>{};

  /// The question for [w], or null when its right answer is not known (the
  /// card is then shown as a plain flashcard, never with a wrong "right" answer).
  /// [right] overrides the answer (a meaning the AI service just gave).
  QuizChoice? choiceFor(SavedWord w, {String? right}) {
    final a = answerFor(w);
    if (!a.choice) return null;
    final r = right ?? a.tr;
    if (r == null || r.trim().isEmpty || r.toLowerCase().contains('bakınız')) return null;
    final rightShort = DictDb.shortTr(r);
    final verb = a.pos == 'v' || (a.pos == null && DictDb.isTrVerb(rightShort));
    // Meanings of this word itself are never wrong answers: "ders, kurs" is
    // also "course", so it must not be offered as the mistake.
    final own = w.lemma.contains(' ') || _tr ? <String>{} : dict.trWordsOf(w.lemma);
    final rightParts = rightShort.toLowerCase().split(_split).map((e) => e.trim()).toSet();
    final rightWords = rightShort.toLowerCase().split(_wordSplit).where((x) => x.length > 2).toSet();
    final seen = <String>{rightShort.toLowerCase()};
    final wrong = <String>[];

    // Same part of speech: by the dictionary when it knows it, otherwise by
    // the shape of the Turkish ("-mak/-mek" verbs).
    var checkVerb = a.pos == null && !_tr;
    bool take(String m) {
      if (wrong.length == 3) return true;
      final s = DictDb.shortTr(m);
      final k = s.toLowerCase();
      final bad = _tr ? s.isEmpty || s.length > 40 || RegExp(r'\d').hasMatch(s) : DictDb.badOption(s);
      if (bad || !seen.add(k)) return false;
      if (checkVerb && DictDb.isTrVerb(s) != verb) return false;
      final parts = k.split(_split).map((e) => e.trim());
      if (parts.any((p) => own.contains(p) || rightParts.contains(p))) return false;
      if (k.split(_wordSplit).any((x) => x.length > 2 && rightWords.contains(x))) return false;
      wrong.add(s);
      return wrong.length == 3;
    }

    // 1. The user's other saved words of the same kind (they look like real answers).
    var n = 0;
    for (final o in _saved) {
      if (o.lemma == w.lemma || o.lemma.contains(' ')) continue;
      if (++n > 80) break;
      final oa = answerFor(o);
      if (a.pos != null && oa.pos != a.pos) continue;
      if (oa.tr != null && take(oa.tr!)) break;
    }
    // 2. Learning Turkish: English meanings of other common Turkish words.
    if (_tr && wrong.length < 3) {
      for (final m in _senseTr.putIfAbsent('tr', () => trEn!.randomGlosses())..shuffle(rnd)) {
        if (take(m)) break;
      }
    }
    // 2. Dictionary meanings of the same part of speech.
    if (!_tr && wrong.length < 3) {
      final p = a.pos ?? (verb ? 'v' : 'n');
      for (final m in _senseTr.putIfAbsent(p, () => dict.randomSenseTr(p))..shuffle(rnd)) {
        if (take(m)) break;
      }
    }
    // 3. Anything else of the same kind.
    if (!_tr && wrong.length < 3) {
      checkVerb = true;
      for (final m in _senseTr.putIfAbsent(null, () => dict.randomSenseTr(null, limit: 400))..shuffle(rnd)) {
        if (take(m)) break;
      }
    }
    if (wrong.length < 3) return null;
    final options = [...wrong, rightShort]..shuffle(rnd);
    return QuizChoice(options, options.indexOf(rightShort));
  }
}
