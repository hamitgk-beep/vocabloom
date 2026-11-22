import 'dart:math';

import '../nlp/context_sense.dart';
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

  /// True when [tr] could not be confirmed for the card's sentence (the card
  /// says so, in neutral words; nothing is corrected).
  final bool unconfirmed;
  const QuizAnswer(this.tr, this.pos, this.gloss, {this.sure = true, this.synId, this.choice = true, this.saved = false, this.unconfirmed = false});
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

  /// The context picker (the app's own, so the panels and the cards decide alike).
  final SenseEngine senses;
  ReviewQuiz(this.dict, this.user, {Random? rnd, this.trEn, SenseEngine? senses})
      : rnd = rnd ?? Random(),
        senses = senses ?? SenseEngine(dict);

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
    final ctx = w.context;
    if (lemma.contains(' ')) {
      final e = dict.exprs.where((e) => e.phrase == lemma).firstOrNull;
      // 1. The meaning saved on the card, as it was saved; 2. nothing saved:
      // the dictionary's own meaning (an unverified AI draft or an AI service
      // meaning is shown, never graded).
      final kept = _keptMeaning(w, e?.en == null ? const [] : [e!.en!]);
      final tr = kept ?? e?.tr ?? e?.trShown;
      if (tr == null || tr.trim().isEmpty) return QuizAnswer(null, null, e?.en);
      // The expression as a whole: confirmed in the card's sentence (not when
      // it is used literally there); with no sentence, a checked meaning.
      final ok = ctx != null ? confirms(lemma, ctx, tr) : (e?.tr != null && dict.trLink(e!.tr!, tr) == 'same');
      return QuizAnswer(DictDb.shortTr(tr), null, e?.en, choice: ok, unconfirmed: !ok, saved: kept != null);
    }
    // 1. The meaning saved on the card is kept, whatever the dictionary's
    // order is now. 2. Nothing saved (old cards, or no reliable meaning when it
    // was saved): the dictionary's common meaning by the source order.
    // Either is graded only when it is confirmed: by the context picker for
    // the card's sentence, or, with no sentence, as a main meaning of the word.
    final kept = _keptMeaning(w, [for (final s in dict.lookup(lemma).senses) s.gloss, for (final o in dict.ownSenses(lemma)) o.en]);
    final m = dict.commonMeaning(lemma);
    if (kept != null) {
      final k = DictDb.shortTr(kept);
      final ok = ctx != null ? confirms(lemma, ctx, kept) : mainMeaning(lemma, kept);
      final common = m.tr != null && dict.trLink(m.tr!, k) == 'same';
      return QuizAnswer(k, DictDb.isTrVerb(k) ? 'v' : (common ? m.pos : null), common ? m.gloss : null,
          choice: ok, unconfirmed: !ok, saved: true);
    }
    final self = m.tr == null ? dict.exprs.where((e) => e.phrase == lemma && e.trShown != null).firstOrNull : null;
    // Only with no Turkish at all: the meaning the AI service gave for the sentence.
    final ai = m.tr != null || self != null || ctx == null ? null : user.contextAi(lemma, ctx);
    if (m.tr == null) {
      final st = self?.trShown;
      return QuizAnswer((st == null ? null : DictDb.shortTr(st)) ?? ai, m.pos, m.gloss, choice: self == null || self.tr != null);
    }
    final ok = ctx != null ? confirms(lemma, ctx, m.tr!) : mainMeaning(lemma, m.tr!);
    return QuizAnswer(m.tr, m.pos, m.gloss, choice: ok, unconfirmed: !ok);
  }

  /// A card with no sentence: whether [answer] can be asked as the meaning of
  /// [lemma]. The first meaning of one dictionary is not taken on trust for a
  /// word with several senses ("sound" is not "Øresund", "subject" is not
  /// first of all "kul"). It needs a second, independent checked source:
  ///  * a verified contribution says it, or
  ///  * it is the Turkish of one of the word's WordNet senses in KeNet (the
  ///    same Turkish or a KeNet synonym), or
  ///  * the word's own one-word entry in the expression list says it
  ///    ("still": "yine de, hâlâ"), or
  ///  * it is used in the human Turkish translations of at least two of the
  ///    word's example sentences ("su" in the sentences of "water").
  /// A word with a single sense needs only a checked meaning. An unverified
  /// AI draft alone never passes.
  bool mainMeaning(String lemma, String answer) {
    final info = dict.lookup(lemma);
    if (dict.ownTier(lemma) == SourceTier.verified && dict.ownSenses(lemma).any((o) => dict.trLink(o.tr, answer) == 'same')) return true;
    for (final s in info.senses) {
      if (s.tr.isNotEmpty && dict.sameTr(s.tr.join(', '), answer, pos: s.pos)) return true;
    }
    if (dict.exprs.any((e) => e.phrase == lemma && e.tr != null && dict.trLink(e.tr!, answer) == 'same')) return true;
    if (info.senses.length <= 1 && info.trFreeDict.any((t) => dict.trLink(t, answer) == 'same')) return true;
    return _inTranslations(lemma, answer) >= 2;
  }

  static final _trWord = RegExp(r'[a-zçğıöşüâîû]+');

  /// In how many of the word's example sentences the human Turkish translation
  /// uses [answer] (one of its parts, every word of it, in any inflected form).
  int _inTranslations(String lemma, String answer) {
    final t = trEn;
    if (t == null) return 0;
    final parts = [
      for (final p in answer.split(_split))
        if (p.trim().isNotEmpty) _trWord.allMatches(TrEnDict.lower(p)).map((m) => m.group(0)!).toList(),
    ].where((p) => p.isNotEmpty).toList();
    var n = 0;
    for (final (_, tr) in dict.examples('w:$lemma', limit: 8)) {
      final seen = <String>{};
      for (final m in _trWord.allMatches(TrEnDict.lower(tr))) {
        seen.addAll(t.lemmas(m.group(0)!));
      }
      if (parts.any((p) => p.every(seen.contains))) n++;
    }
    return n;
  }

  /// The card's saved meaning, unless it is empty, a cross reference or an
  /// English definition ([glosses]) saved when no Turkish was known.
  static String? _keptMeaning(SavedWord w, Iterable<String> glosses) {
    final k = w.meaning?.trim();
    if (k == null || k.isEmpty || k.toLowerCase().contains('bakınız')) return null;
    if (glosses.any((g) => g.trim() == k)) return null;
    return k;
  }

  /// The confidence rule of review cards is [SenseEngine.fit]: an answer is
  /// graded as the right option only when the context picker confirms it for
  /// the card's sentence. Anything else is a plain flashcard, nothing graded.
  bool confirms(String headword, String sentence, String answer) => fit(headword, sentence, answer).confirmed;

  AnswerFit fit(String headword, String sentence, String answer) => senses.fit(headword, sentence, answer);


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
