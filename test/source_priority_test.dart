// One source order for every screen (DictDb.sourcePolicy): verified contributions,
// then the sourced dictionaries (ft, WordNet, expr, exd), then unreviewed AI drafts.
// Drafts are never deleted or promoted: they stay readable as labelled suggestions.
// Every check runs on the bundled database opened read-only, and the data files
// are compared byte for byte before and after.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/ai/key_ai.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/review_quiz.dart';
import 'package:kelime_okur/data/tr_en_dict.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/nlp/context_sense.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:kelime_okur/ui/expr_sheet.dart';
import 'package:kelime_okur/ui/hover_meaning.dart';
import 'package:kelime_okur/ui/paragraph_view.dart';
import 'package:kelime_okur/ui/theme.dart';
import 'package:kelime_okur/ui/word_sheet.dart';
import 'package:sqlite3/sqlite3.dart';

const _files = ['assets/dict.db', 'assets/tr_en.db'];

String _sha(String path) => sha256.convert(File(path).readAsBytesSync()).toString();

DictDb _open({bool policy = true}) {
  DictDb.sourcePolicy = policy;
  final d = DictDb();
  d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
  d.load();
  return d;
}

List<String> _ft(DictDb d, String w) {
  final r = d.db.select('SELECT tr FROM ft WHERE word = ?', [w]);
  return r.isEmpty ? const [] : (jsonDecode(r.first.columnAt(0) as String) as List).cast<String>();
}

Expr _expr(DictDb d, String phrase, String cat) => d.exprs.firstWhere((e) => e.phrase == phrase && e.cat == cat);

String? _exprTr(DictDb d, String phrase, String cat) =>
    d.db.select('SELECT tr FROM expr WHERE phrase = ? AND cat = ?', [phrase, cat]).first.columnAt(0) as String?;

ContextSense _sense(AppState app, String sentence, String word) => app.senses.resolve(SenseQuery.find(app.dict, sentence, word));

Future<void> _pump(WidgetTester tester, Widget panel, {double width = 390}) async {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(MaterialApp(key: UniqueKey(), theme: buildTheme(Brightness.light), home: Scaffold(body: panel)));
  await tester.pump();
}

void main() {
  final before = {for (final f in _files) f: _sha(f)};
  late DictDb d;
  late AppState app;
  late UserDb user;
  late TrEnDict trEn;
  late Map<String, int> counts;

  Map<String, int> ownCounts(DictDb x) => {
        for (final r in x.db.select("SELECT 'w:' || status || ':' || reviewed AS k, COUNT(*) AS n FROM own_word GROUP BY 1 "
            "UNION ALL SELECT 'e:' || status || ':' || reviewed, COUNT(*) FROM own_expr GROUP BY 1"))
          r['k'] as String: r['n'] as int,
      };

  setUpAll(() {
    d = _open();
    counts = ownCounts(d);
    final dir = Directory.systemTemp.createTempSync('source_priority');
    user = UserDb.open(dir);
    app = AppState(d, user)..localAi = KeyAi(user);
    trEn = TrEnDict(sqlite3.open('assets/tr_en.db', mode: OpenMode.readOnly));
  });

  tearDown(() => DictDb.sourcePolicy = true);

  tearDownAll(() {
    // Nothing was written to the bundled data; own rows keep their status.
    for (final f in _files) {
      expect(_sha(f), before[f], reason: '$f must not change');
    }
    expect(ownCounts(_open()), counts);
  });

  group('data stays as it is', () {
    test('own rows keep their numbers and status; the database is read-only', () {
      expect(counts['w:ai_draft_unreviewed:0'], 41177);
      expect(counts['w:contrib:1'], 92);
      expect(counts['e:ai_draft_unreviewed:0'], 10092);
      expect(counts['e:contrib:1'], 689);
      expect(() => d.db.execute("UPDATE own_word SET reviewed = 1 WHERE word = 'still'"), throwsA(isA<SqliteException>()));
    });

    test('the policy has a version in the context cache key', () {
      final q = SenseQuery.find(d, 'He is still here.', 'still');
      expect(app.senses.cacheKey(q), contains(DictDb.policyVersion));
      DictDb.sourcePolicy = false;
      expect(app.senses.cacheKey(q), isNot(contains('src1')));
    });
  });

  group('word search and the word panel data', () {
    test('still: the dictionary meaning leads, the AI draft is only a suggestion', () {
      final i = d.lookup('still');
      expect(i.trFreeDict, _ft(d, 'still'));
      expect(i.trFreeDict.first, 'hâlâ');
      expect(i.trDraft.first, 'hareketsiz, durgun');
      expect(d.ownSenses('still'), isEmpty);
      expect(d.draftSenses('still').first.tr, 'hareketsiz, durgun');
      expect(app.shortMeaning('still'), 'hâlâ');
    });

    test('course: ft order is kept, even where the draft reads better (no quality claim)', () {
      expect(d.lookup('course').trFreeDict.first, _ft(d, 'course').first);
      expect(d.draftSenses('course').map((s) => s.tr), contains('kurs, ders'));
    });

    test('nationally: the contribution first, the kept Wiktionary meaning after it', () {
      final i = d.lookup('nationally');
      expect(i.trFreeDict, ['ulusal olarak', 'ulusça']);
      expect(i.trDraft, isEmpty);
      expect(d.ownSenses('nationally').single.tr, 'ulusal olarak');
      expect(d.draftSenses('nationally'), isEmpty);
    });

    test('a meaning the user contributed inside an AI draft row is verified', () {
      // tools/contrib/apply.py added it to the draft row with src "storilex".
      expect(d.ownSenses('book').map((s) => s.tr), ['sarı kart göstermek, ceza yazmak']);
      // It is a meaning added to the row, not the word's first one: it is kept
      // (not hidden), after the dictionary's own first meanings.
      final tr = d.lookup('book').trFreeDict;
      expect(tr.first, _ft(d, 'book').first);
      expect(tr, containsAll(_ft(d, 'book')));
      expect(tr.last, 'sarı kart göstermek, ceza yazmak');
      expect(d.commonMeaning('book').tr, contains('kitap'));
      expect(d.draftSenses('book').map((s) => s.tr), isNot(contains('sarı kart göstermek, ceza yazmak')));
    });

    test('English and Turkish search lists do not depend on the policy', () {
      const qs = ['sti', 'cour', 'class', 'as', 'nation', 'run', 'b', 'kitap', 'hâlâ', 'ders', 'banka'];
      List<Object> run(DictDb x) => [
            for (final q in qs) ...[x.searchWords(q, limit: 20), x.searchTurkish(q, limit: 20)],
            x.commonWords(limit: 50),
          ];
      final on = run(d).toString();
      final off = run(_open(policy: false)).toString();
      expect(on, off);
    });

    test('a word whose only Turkish is an AI draft still has a meaning, marked as a draft', () {
      final r = d.db.select("SELECT o.word FROM own_word o WHERE o.reviewed = 0 AND NOT EXISTS (SELECT 1 FROM ft WHERE ft.word = o.word) "
          "AND NOT EXISTS (SELECT 1 FROM sense x JOIN syn s ON s.id = x.syn_id WHERE x.lemma = o.word AND s.tr IS NOT NULL AND s.tr != '[]')");
      expect(r, hasLength(1));
      final w = r.first['word'] as String;
      expect(d.lookup(w).trFreeDict, isEmpty);
      expect(d.lookup(w).trDraft, isNotEmpty);
      expect(d.commonMeaning(w).tr, isNotNull);
    });

    test('policy off gives exactly the order before it (AI draft first)', () {
      final off = _open(policy: false);
      expect(off.lookup('still').trFreeDict.first, 'hareketsiz, durgun');
      expect(off.lookup('still').trDraft, isEmpty);
      expect(off.ownSenses('still').first.tr, 'hareketsiz, durgun');
      expect(off.lookup('nationally').trFreeDict, ['ulusça', 'ulusal olarak']);
    });
  });

  group('reader', () {
    test('mouse bubble: still gives the dictionary meaning', () {
      final toks = tokenize('He is still here.');
      final m = hoverMeaning(app, toks, const [], 2)!;
      expect(m.tr, 'hâlâ');
      expect(m.draft, isFalse);
    });

    test('mouse bubble: an expression with only an AI draft is marked', () {
      final e = d.exprs.firstWhere((e) => e.tr == null && e.trDraft != null && e.pattern.length >= 2 && e.pattern.every((w) => w.isNotEmpty));
      expect(e.trShown, e.trDraft);
      expect(e.trShownIsDraft, isTrue);
      expect(e.needsAi, isFalse, reason: 'no new AI requests for it');
    });
  });

  group('expressions', () {
    test('class (false friend): the dictionary meaning with its warning comes back', () {
      final e = _expr(d, 'class', 'false_friends');
      expect(e.tr, _exprTr(d, 'class', 'false_friends'));
      expect(e.tr, contains('≠ klas'));
      expect(e.trDraft, isNotNull);
      expect(_expr(_open(policy: false), 'class', 'false_friends').tr, isNot(contains('≠ klas')));
    });

    test('as (conjunction): the dictionary meaning, the draft kept apart', () {
      final e = _expr(d, 'as', 'conjunctions');
      expect(e.tr, '-dığı için; -iken; gibi');
      expect(e.trDraft, contains('-ken'));
    });

    test('a dime a dozen (idiom): exd or nothing in the sheet, the draft in its own section', () {
      final own = d.db.select("SELECT senses FROM own_expr WHERE phrase = 'a dime a dozen' AND cat = 'idioms'");
      final ownFirst = ((jsonDecode(own.first.columnAt(0) as String) as List).first as Map)['tr'];
      final js = d.exprDetail('a dime a dozen', 'idioms');
      expect(js == null || !js.contains(ownFirst as String), isTrue);
      expect((jsonDecode(d.exprDraftDetail('a dime a dozen', 'idioms')!) as List).first['title_tr'], ownFirst);
    });

    test('exd comes before an AI draft', () {
      final r = d.db.select('SELECT o.phrase, o.cat FROM own_expr o JOIN exd x ON x.phrase = o.phrase AND x.cat = o.cat WHERE o.reviewed = 0 LIMIT 1');
      final p = r.first['phrase'] as String, c = r.first['cat'] as String;
      final exd = d.db.select('SELECT json FROM exd WHERE phrase = ? AND cat = ?', [p, c]).first.columnAt(0) as String;
      expect(d.exprDetail(p, c), exd);
      expect(d.exprDraftDetail(p, c), isNotNull);
    });

    test('all 689 verified expressions show what they showed before', () {
      final off = _open(policy: false);
      final keys = [for (final r in d.db.select('SELECT phrase, cat FROM own_expr WHERE reviewed = 1')) (r['phrase'] as String, r['cat'] as String)];
      expect(keys, hasLength(689));
      for (final (p, c) in keys) {
        expect(_expr(d, p, c).trShown, _expr(off, p, c).trShown, reason: '$p|$c');
      }
    });
  });

  group('meaning in context', () {
    test('still in "He is still here." gets a checked meaning, not the draft', () {
      final m = d.meaningIn('still', 'He is still here.');
      expect(m.tr, isNotNull);
      expect(m.tr, isNot(contains('hareketsiz')));
    });

    test('an AI draft is a candidate, but never "sure" on its own', () {
      var drafts = 0, sureUncorroborated = 0;
      const sentences = [
        'He is still here.', 'Keep still while I take the photo.', 'The water was still and clear.',
        'She took a course in French.', 'Of course I will help you.', 'The ship changed course.',
        'Well, my boy, what now?', 'She sings well.', 'Why do you think so?', 'I know her very well.',
        'They sat on the bank of the river.', 'The bank approved the loan.', 'He ran through the plan again.',
      ];
      for (final s in sentences) {
        for (final w in tokenize(s).map((t) => t.lower).where((w) => w.length > 2).toSet()) {
          final r = _sense(app, s, w);
          if (r.ranked.any((c) => c.unverified)) drafts++;
          final b = r.best;
          if (b != null && b.unverified && r.confidence == SenseConfidence.sure) {
            final ft = d.lookup(b.lemma).trFreeDict.expand((t) => t.split(RegExp('[,;]'))).map((t) => t.trim()).toSet();
            final checked = {...ft, for (final c in r.ranked) if (!c.unverified) ...c.tr};
            if (!b.tr.take(3).any(checked.contains)) sureUncorroborated++;
          }
        }
      }
      expect(drafts, greaterThan(0), reason: 'drafts still compete');
      expect(sureUncorroborated, 0);
    });

    test('expression drafts compete with their own ids', () {
      final r = app.senses.resolve(SenseQuery.find(d, 'Talented singers are a dime a dozen in this city.', 'a dime a dozen', category: 'idioms'));
      expect(r.ranked.where((c) => c.id.startsWith('xd:')).every((c) => c.unverified), isTrue);
      expect(r.ranked.any((c) => c.id.startsWith('xd:')), isTrue);
    });
  });

  group('review cards', () {
    SavedWord saved(String lemma, String? ctx, String? meaning) => SavedWord(lemma, WordStatus.learning, ctx, null, meaning, DateTime(2026, 11, 1));

    // Hamit's rules for saved cards (option B): a filled saved meaning is
    // kept and asked; an empty one follows the source order, but is not
    // graded when the card's sentence clearly uses another meaning.
    const golf = 'American-style supermarkets and a new golf course can now be found in Ho Chi Minh City.';
    const train = 'We took a through train from London to Edinburgh.';
    List<String> row(String lemma) =>
        user.db.select('SELECT * FROM words WHERE lemma LIKE ?', ['%$lemma']).map((r) => r.toString()).toList();

    const evening = 'She took an evening course in English literature.';
    const water = 'The water was perfectly still.';
    const river = 'They sat on the bank of the river.';

    // The confidence rule (ReviewQuiz.confirms): an answer is graded only when
    // the context picker confirms it for the card's sentence. Otherwise the
    // card is a plain flashcard: no choices, nothing graded, nothing rewritten.
    // (lemma, sentence, saved meaning, answer shown, graded)
    final cases = <(String, String?, String?, String, bool)>[
      // Hamit's four examples, saved with no meaning (old cards and new ones alike).
      ('course', evening, null, 'mecra', false),
      ('still', water, null, 'hâlâ', false),
      ('bank', river, null, 'banka', false),
      ('course', golf, null, 'mecra', false),
      // The same, with the meaning an old version saved: kept, never graded as right.
      ('course', golf, 'akmak, hızla akmak', 'akmak, hızla akmak', false),
      ('course', evening, 'mecra', 'mecra', false),
      ('still', water, 'hâlâ', 'hâlâ', false),
      ('bank', river, 'banka', 'banka', false),
      // The picker has no meaning it stands behind (grammar word): not graded either.
      ('still', 'Keep still.', 'hareketsiz, durgun', 'hareketsiz, durgun', false),
      ('through', train, 'boyunca, baştan sona', 'boyunca, baştan sona', false),
      ('through', train, null, 'boyunca', false),
      // Confirmed by the picker: graded, with the saved meaning as it was saved.
      ('course', golf, 'saha, golf sahası', 'saha, golf sahası', true),
      ('course', evening, 'kurs, ders', 'kurs, ders', true),
      ('book', 'I booked a table for two.', 'rezerve etmek, ayırtmak', 'rezerve etmek, ayırtmak', true),
      ('book', 'I read a good book.', null, 'kitap, betik', true),
      ('bank', 'The bank approved the loan.', null, 'banka', true),
      // More of Hamit's examples.
      ('book', 'I booked a table for two.', null, 'kitap, betik', false),
      ('still', 'Keep still.', null, 'hâlâ', false),
      // A Turkish synonym from a checked source confirms: the picker says "arzu etmek".
      ('want', 'I want it.', null, 'istemek', true),
      // No sentence on the card: graded only when a second checked source
      // says it is a main meaning of the word.
      ('still', null, null, 'hâlâ', true), // the word's own entry in the expression list
      ('water', null, null, 'su', true), // human translations of its example sentences
      ('course', null, 'kurs, ders', 'kurs, ders', true), // KeNet
      ('course', null, null, 'mecra', false),
      ('sound', null, null, 'Øresund', false),
      ('through', null, null, 'boyunca', false),
      ('still', null, 'hareketsiz, durgun', 'hareketsiz, durgun', false),
    ];
    for (final (lemma, ctx, meaning, shown, graded) in cases) {
      test('$lemma | ${ctx ?? "no sentence"} | saved: ${meaning ?? "-"} → ${graded ? "graded" : "not graded"}', () {
        final w = saved(lemma, ctx, meaning);
        final q = ReviewQuiz(d, user, rnd: Random(1), trEn: trEn, senses: app.senses);
        final a = q.answerFor(w);
        expect(a.tr, shown);
        expect(a.saved, meaning != null);
        expect(a.choice, graded);
        expect(a.unconfirmed, !graded);
        final ch = q.choiceFor(w);
        if (graded) {
          expect(ch!.right, shown);
          expect(ch.options.toSet().length, 4);
        } else {
          expect(ch, isNull, reason: 'an unconfirmed answer is never one of four choices');
        }
      });
    }

    test('the rule is general: no word is named in it, and a draft never confirms', () {
      final src = File('lib/data/review_quiz.dart').readAsStringSync();
      final src2 = File('lib/nlp/context_sense.dart').readAsStringSync();
      final rule = src.substring(src.indexOf('bool mainMeaning('), src.indexOf('static String? _keptMeaning')) +
          src2.substring(src2.indexOf('AnswerFit fit('), src2.indexOf('bool isLiteral('));
      for (final w in ['course', 'still', 'bank', 'mecra', 'banka', 'akmak', 'hâlâ']) {
        expect(rule.contains("'$w'"), isFalse, reason: w);
      }
      final q = ReviewQuiz(d, user, rnd: Random(1), trEn: trEn, senses: app.senses);
      // The picker's own choice confirms itself; an unrelated meaning does not.
      final c = _sense(app, golf, 'course');
      expect(q.fit('course', golf, c.tr!).fit, SentenceFit.confirmed);
      expect(q.fit('course', golf, 'banka').fit, SentenceFit.other);
      expect(q.fit('still', water, 'hâlâ').why, 'grammar word');
      expect(q.fit('course', 'No such word here.', 'kurs').why, 'not in sentence');
    });

    test('saved cards are not rewritten: meaning, status and schedule stay', () {
      app.setWord('course', WordStatus.none);
      app.setWord('course', WordStatus.learning, context: golf, meaning: 'akmak, hızla akmak');
      final row0 = row('course');
      final w = user.words(WordStatus.learning).firstWhere((w) => w.lemma == 'course');
      final q = ReviewQuiz(d, user, rnd: Random(1), trEn: trEn, senses: app.senses);
      expect(q.choiceFor(w), isNull);
      expect(q.answerFor(w).tr, 'akmak, hızla akmak');
      expect(row('course'), row0);
    });

    test('an English definition saved when no Turkish was known is not a Turkish answer', () {
      final gloss = d.lookup('still').senses.first.gloss;
      final a = ReviewQuiz(d, user, rnd: Random(1), trEn: trEn, senses: app.senses).answerFor(saved('still', null, gloss));
      expect(a.saved, isFalse);
      expect(a.tr, d.commonMeaning('still').tr);
    });

    group('Turkish synonyms', () {
      test('the same Turkish, or one KeNet synset of the same part of speech; never a look-alike', () {
        expect(d.trLink('kurs, ders', 'ders'), 'same');
        expect(d.trLink('şans, talih', 'fırsat, olanak', pos: 'n'), 'synonym');
        expect(d.sameTr('banka', 'kıyı'), isFalse);
        expect(d.sameTr('mecra', 'kurs, ders'), isFalse);
        expect(d.sameTr('hâlâ', 'durgun'), isFalse);
        // Spelling alone joins nothing.
        expect(d.sameTr('kurs', 'kurşun'), isFalse);
        expect(d.sameTr('yüz', 'yüzmek'), isFalse);
      });

      test('a synonym confirms an answer only through the sense the picker chose', () {
        final q = ReviewQuiz(d, user, rnd: Random(1), trEn: trEn, senses: app.senses);
        // "istemek" is the first meaning of "want" and of "desire", whose first sense is this synset.
        final f = q.fit('want', 'I want it.', 'istemek');
        expect(f.confirmed, isTrue);
        expect(f.why, isNot('same'));
        expect(app.senses.fit('want', 'I want it.', 'istemek', synonyms: false).confirmed, isFalse);
        // A noun's meaning never confirms a verb answer.
        expect(q.fit('book', 'I read a good book.', 'ayırtmak').confirmed, isFalse);
        // "hafifletmek" is the first meaning of "relieve" and of "alleviate",
        // whose first sense is the synset the picker chose here. (The synset's
        // own Turkish in the data is another word; this checks the answer the
        // card shows, not that record.)
        const relieve = 'First of the problems attacked would be fatigue and emotional tension, since action relieves both.';
        expect(d.commonMeaning('relieve').tr, 'hafifletmek');
        final r = q.fit('relieve', relieve, 'hafifletmek');
        expect(r.confirmed, isTrue);
        expect(r.why, 'co-translation');
        expect(q.answerFor(saved('relieve', relieve, null)).choice, isTrue);
        // Bringing up children is not "kaldırmak", although "rear" can mean both.
        expect(q.fit('raise', 'They raised their children in a town surrounded by nature.', 'kaldırmak').confirmed, isFalse);
      });

      test('an AI draft the picker chose confirms only a checked meaning it repeats', () {
        final q = ReviewQuiz(d, user, rnd: Random(1), trEn: trEn, senses: app.senses);
        final c = _sense(app, 'Is it expensive?', 'expensive');
        expect(c.best!.unverified, isTrue, reason: 'the picker chose the draft here');
        expect(q.fit('expensive', 'Is it expensive?', 'pahalı').confirmed, isTrue); // ft says "pahalı" too
        expect(q.fit('expensive', 'Is it expensive?', 'tuzlu').confirmed, isFalse);
      });
    });

    group('expression cards: the expression as a whole', () {
      test('used literally in the sentence: not graded', () {
        final q = ReviewQuiz(d, user, rnd: Random(1), trEn: trEn, senses: app.senses);
        final e = d.exprs.firstWhere((e) => e.phrase == 'live in' && e.tr != null);
        final w = saved('live in', 'They lived in Kansas for ten years.', null);
        expect(q.fit('live in', w.context!, e.tr!).why, 'literal');
        expect(q.answerFor(w).choice, isFalse);
        expect(q.choiceFor(w), isNull);
      });

      test('not found in the sentence, or the picker is not sure: not graded', () {
        final q = ReviewQuiz(d, user, rnd: Random(1), trEn: trEn, senses: app.senses);
        final e = _expr(d, 'break the ice', 'idioms');
        expect(q.answerFor(saved('break the ice', 'The weather was cold.', null)).choice, isFalse);
        final f = q.fit('break the ice', 'He finally broke the ice.', e.tr!);
        expect(q.answerFor(saved('break the ice', 'He finally broke the ice.', null)).choice, f.sense!.confidence == SenseConfidence.sure);
        // No sentence: the checked dictionary meaning is asked.
        expect(q.answerFor(saved('break the ice', null, null)).choice, isTrue);
      });
    });

    group('expressions and drafts', () {
      test('a dime a dozen: the saved meaning is kept; with none, the dictionary meaning', () {
        final e = _expr(d, 'a dime a dozen', 'idioms');
        final q = ReviewQuiz(d, user, rnd: Random(1), trEn: trEn, senses: app.senses);
        expect(q.answerFor(saved('a dime a dozen', 'Talented singers are a dime a dozen in this city.', 'bol, ucuz')).tr, 'bol, ucuz');
        final a = q.answerFor(saved('a dime a dozen', null, null));
        expect(a.tr, DictDb.shortTr(e.tr!));
        expect(a.choice, isTrue);
      });

      test('an expression with only an AI draft is shown, never graded', () {
        final e = d.exprs.firstWhere((e) => e.tr == null && e.trDraft != null && e.phrase.contains(' '));
        final q = ReviewQuiz(d, user, rnd: Random(1), trEn: trEn, senses: app.senses);
        final a = q.answerFor(saved(e.phrase, null, null));
        expect(a.tr, DictDb.shortTr(e.trDraft!));
        expect(a.choice, isFalse);
        expect(q.choiceFor(saved(e.phrase, null, null)), isNull);
      });

      test('a word whose only Turkish is an AI draft is never graded', () {
        final r = d.db.select("SELECT o.word FROM own_word o WHERE o.reviewed = 0 AND NOT EXISTS (SELECT 1 FROM ft WHERE ft.word = o.word) "
            "AND NOT EXISTS (SELECT 1 FROM sense x JOIN syn s ON s.id = x.syn_id WHERE x.lemma = o.word AND s.tr IS NOT NULL AND s.tr != '[]')");
        final w = r.single['word'] as String;
        final a = ReviewQuiz(d, user, rnd: Random(1), trEn: trEn, senses: app.senses).answerFor(saved(w, null, null));
        expect(a.tr, isNotNull);
        expect(a.choice, isFalse);
      });
    });

    test('learning progress and review schedule are not touched by the quiz', () {
      app.setWord('through', WordStatus.learning, context: train);
      List<String> all() => [
            for (final t in ['words', 'review', 'activity', 'review_log', 'missing_tr', 'ctx_ai'])
              if (user.db.select("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", [t]).isNotEmpty)
                ...user.db.select('SELECT * FROM $t').map((r) => '$t ${r.toString()}'),
          ];
      final before = all();
      final sched0 = app.review.due(now: DateTime(2030)).map((c) => '${c.word.lemma}:${c.word.status}').toList();
      final q = ReviewQuiz(d, user, rnd: Random(1), trEn: trEn, senses: app.senses);
      for (final w in user.words(WordStatus.learning)) {
        q.choiceFor(w);
      }
      expect(all(), before);
      expect(app.review.due(now: DateTime(2030)).map((c) => '${c.word.lemma}:${c.word.status}').toList(), sched0);
    });

    test('wrong options never repeat any meaning of the word, drafts included', () {
      final ch = ReviewQuiz(d, user, rnd: Random(3), trEn: trEn, senses: app.senses).choiceFor(saved('still', null, null))!;
      final drafts = d.draftSenses('still').expand((s) => s.tr.split(RegExp('[,;]'))).map((t) => t.trim()).toSet();
      for (final o in ch.options.where((o) => o != ch.right)) {
        expect(o.split(RegExp('[,;]')).map((t) => t.trim()).any(drafts.contains), isFalse, reason: o);
      }
    });

  });

  group('new card: the saved meaning', () {
    const golf = 'American-style supermarkets and a new golf course can now be found in Ho Chi Minh City.';
    WordContext ctxOf(String sentence, String word) {
      final a = analyze(app, sentence);
      return buildContext(app, Para(1, 0, 'p', sentence), a, a.tokens.indexWhere((t) => t.lower == word));
    }

    Future<String?> saveFrom(WidgetTester tester, Widget panel, String key) async {
      app.setWord(key, WordStatus.none);
      // Wide: the test font is wider than the real one (expression cards' headers).
      await _pump(tester, panel, width: 900);
      await tester.ensureVisible(find.text('Öğreneceğim').first);
      await tester.tap(find.text('Öğreneceğim').first);
      await tester.pump();
      return user.words(WordStatus.learning).firstWhere((w) => w.lemma == key).meaning;
    }

    // (sentence, word, lemma, saved meaning): the sentence's meaning only when
    // the context picker is sure and it is not an AI draft; otherwise nothing.
    for (final (sentence, word, lemma, want) in [
      ('The sea was calm and the water was perfectly still.', 'still', 'still', null), // picker: grammar word
      ('She is still here.', 'still', 'still', null),
      (golf, 'course', 'course', 'saha, pist'), // sure
      ('She took an evening course in English literature.', 'course', 'course', null), // only likely
      ('We took a through train from London to Edinburgh.', 'through', 'through', null),
      ('They sat on the bank of the river.', 'bank', 'bank', null), // only likely
      ('I booked a table for two.', 'booked', 'book', 'rezerve etmek, rezerve ettirmek, rezervasyon yapmak'),
    ]) {
      testWidgets('$lemma in "$sentence"', (tester) async {
        final m = await saveFrom(tester, WordPanel(app: app, surface: word, lemma: lemma, ctx: ctxOf(sentence, word)), lemma);
        expect(m, want);
        // The new card asks what was saved; with nothing saved, the review rules for empty meanings apply.
        final w = user.words(WordStatus.learning).firstWhere((w) => w.lemma == lemma);
        final a = ReviewQuiz(d, user, rnd: Random(1), trEn: trEn, senses: app.senses).answerFor(w);
        // The same confidence rule as for old cards: graded only with a confirmed meaning.
        expect(a.choice, want != null);
        if (want != null) {
          expect(a.tr, DictDb.shortTr(want));
          expect(a.saved, isTrue);
        } else {
          expect(a.saved, isFalse);
          expect(a.unconfirmed, isTrue);
        }
      });
    }

    testWidgets('no sentence: the checked first meaning', (tester) async {
      expect(await saveFrom(tester, WordPanel(app: app, surface: 'still'), 'still'), 'hâlâ');
      expect(await saveFrom(tester, WordPanel(app: app, surface: 'book'), 'book'), contains('kitap'));
    });

    testWidgets('an idiom shown as a guess: the reader\'s tap saves its checked meaning, the card is not graded', (tester) async {
      final e = _expr(d, 'go with the flow', 'idioms');
      const s = 'Enjoy the ride down, let the wind fly through your hair, go with the flow, and wait.';
      expect(app.senses.resolve(SenseQuery.find(d, s, e.phrase)).confidence, SenseConfidence.likely);
      final m = await saveFrom(tester, ExprPanel(app: app, expr: e, ctx: ctxOf(s, 'flow'), words: const ['go', 'with', 'the', 'flow']), e.phrase);
      expect(m, _exprTr(d, e.phrase, e.cat));
      final w = user.words(WordStatus.learning).firstWhere((w) => w.lemma == e.phrase);
      expect(w.context, s);
      final a = ReviewQuiz(d, user, rnd: Random(1), trEn: trEn, senses: app.senses).answerFor(w);
      expect(a.tr, isNotNull);
      expect(a.choice, isFalse);
    });

    testWidgets('an idiom saves the dictionary meaning, never the AI draft', (tester) async {
      final e = _expr(d, 'a dime a dozen', 'idioms');
      const s = 'Talented singers are a dime a dozen in this city.';
      final m = await saveFrom(tester, ExprPanel(app: app, expr: e, ctx: ctxOf(s, 'dime'), words: const ['a', 'dime', 'a', 'dozen']), e.phrase);
      expect(m, isNotNull);
      expect(m, isNot(e.trDraft));
      expect(e.trDraft, isNot(contains(m)));
    });
  });

  group('panels', () {
    testWidgets('word panel: still shows hâlâ; the drafts are closed and labelled', (tester) async {
      await _pump(tester, WordPanel(app: app, surface: 'still'));
      expect(find.text('hâlâ'), findsWidgets);
      expect(find.textContaining('Doğrulanmamış AI önerileri'), findsOneWidget);
      // Closed: the draft meanings are not on screen until the section is opened.
      expect(find.text('hareketsiz, durgun'), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('unverified-ai-toggle')));
      await tester.tap(find.byKey(const ValueKey('unverified-ai-toggle')));
      await tester.pump();
      expect(find.text('hareketsiz, durgun'), findsOneWidget);
      expect(find.byKey(const ValueKey('unverified-ai-note')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('word panel: a verified word has no draft section', (tester) async {
      await _pump(tester, WordPanel(app: app, surface: 'nationally', lemma: 'nationally'));
      expect(find.text('ulusal olarak'), findsWidgets);
      expect(find.byKey(const ValueKey('unverified-ai-toggle')), findsNothing);
    });

    testWidgets('expression panel: class shows the dictionary meaning; drafts closed', (tester) async {
      await _pump(tester, ExprPanel(app: app, expr: _expr(d, 'class', 'false_friends'), words: const ['class']));
      expect(find.textContaining('≠ klas'), findsWidgets);
      expect(find.textContaining('Doğrulanmamış AI önerileri'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
