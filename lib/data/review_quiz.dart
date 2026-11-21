import 'dart:math';

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
  const QuizAnswer(this.tr, this.pos, this.gloss, {this.sure = true, this.synId});
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
      // An expression: its own dictionary meaning, otherwise what was saved.
      final e = dict.exprs.where((e) => e.phrase == lemma).firstOrNull;
      final tr = e?.trShown ?? (w.meaning != null && w.meaning != e?.en ? w.meaning : null);
      return QuizAnswer(tr == null || tr.trim().isEmpty ? null : DictDb.shortTr(tr), null, e?.en);
    }
    // The word's most common meaning, not the one of the sentence it was
    // saved from ("through" is "boyunca", even from "a through train").
    final m = dict.commonMeaning(lemma);
    // A one-word expression ("though", "however") has its own Turkish.
    final self = m.tr == null ? dict.exprs.where((e) => e.phrase == lemma && e.trShown != null).firstOrNull?.trShown : null;
    // Only with no Turkish at all: the meaning the AI service gave for the sentence.
    final ai = m.tr != null || self != null || w.context == null ? null : user.contextAi(lemma, w.context!);
    return QuizAnswer(m.tr ?? (self == null ? null : DictDb.shortTr(self)) ?? ai, m.pos, m.gloss);
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
