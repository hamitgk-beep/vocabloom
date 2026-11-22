// The same expression under the underline, the tap and the panel, for every
// phrase filter category in the app: each category alone, its expressions
// found in a sentence, and every word of the expression gives that expression.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/ai/key_ai.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:kelime_okur/ui/paragraph_view.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late AppState app;
  setUpAll(() {
    final d = DictDb();
    d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    final u = UserDb.open(Directory.systemTemp.createTempSync('vocabloom_cat'));
    app = AppState(d, u)..localAi = KeyAi(u);
  });

  // The phrase filter categories of the reader.
  const cats = ['phrasal_verbs', 'idioms', 'collocations', 'chunks', 'binomials', 'prepositional_phrases', 'proverbs', 'conjunctions', 'discourse_markers'];

  for (final cat in cats) {
    test('category $cat: the underline, the tap and the panel use the same expression', () {
      // Only this filter is on.
      app.enabledCats..clear()..add(cat);
      final exprs = [
        for (final e in app.dict.exprs)
          if (e.cat == cat && e.pattern.length >= 2 && e.pattern.every((w) => !placeholderWords.contains(w) && w.isNotEmpty)) e,
      ].take(25).toList();
      expect(exprs, isNotEmpty, reason: 'the dictionary has $cat expressions');
      var checked = 0;
      for (final e in exprs) {
        final sentence = 'Well, ${e.phrase} here.';
        final a = analyze(app, sentence);
        final span = a.matches.where((m) => m.expr.phrase == e.phrase && m.expr.cat == cat).toList();
        if (span.isEmpty) continue; // the phrase is not in the text in its plain form
        final tokens = span.first.tokens;
        for (final i in tokens) {
          final chosen = a.expressionsAt(app, i);
          if (chosen.isEmpty) {
            // Not an expression here (e.g. a literal use): no underline and no
            // tap target, so both agree that nothing is shown.
            expect(a.shownAt(app, i).cat, isNull, reason: '${e.phrase}: token $i underlined but not tappable');
            continue;
          }
          final top = chosen.first;
          final isHere = chosen.any((m) => m.expr.phrase == e.phrase && m.tokens.join(',') == tokens.join(','));
          if (!isHere) {
            // Used literally here: the phrase is not chosen; the tap and the
            // underline still agree on whatever is chosen.
            expect(a.shownAt(app, i).cat, top.expr.cat, reason: '${e.phrase}: underline and tap differ on token $i (literal)');
            continue;
          }
          // Otherwise the tap opens the longest covering expression, which is
          // this one or a longer one, and the underline shows the same category.
          expect(top.tokens.length >= tokens.length, isTrue, reason: '${e.phrase}: token $i chose a shorter one');
          expect(a.shownAt(app, i).cat, top.expr.cat, reason: '${e.phrase}: underline and tap differ on token $i');
        }
        checked++;
      }
      expect(checked, greaterThan(0), reason: 'at least one $cat expression was found in its sentence');
    });
  }

  test('the underline follows the tap: a literal phrasal verb inside an idiom is not underlined as a phrasal verb', () {
    app.enabledCats..clear()..addAll(['phrasal_verbs', 'idioms']);
    final a = analyze(app, 'He finally made up his mind about the trip.');
    final cats = a.expressionCats(app);
    for (final i in [2, 3, 4, 5]) {
      expect(cats[i], a.expressionsAt(app, i).first.expr.cat, reason: 'token $i');
      expect(cats[i], 'idioms', reason: 'token $i: "made up his mind" is one idiom');
    }
    final b = analyze(app, 'Please turn the light off before you leave.');
    expect(b.expressionCats(app)[1], 'phrasal_verbs');
    expect(b.expressionCats(app)[4], 'phrasal_verbs');
  });

  test('a disabled category gives no underline and no tap target', () {
    final a = analyze(app, 'He finally broke the ice.');
    app.enabledCats..clear()..add('phrasal_verbs');
    expect(a.expressionsAt(app, 2), isEmpty);
    app.enabledCats..clear()..add('idioms');
    expect(a.expressionsAt(app, 2).first.expr.phrase, 'break the ice');
  });

  test('reading: an English idiom is recognised; the dictionary meaning is shown, the AI draft kept apart', () {
    app.enabledCats..clear()..add('idioms');
    const sentence = 'Talented singers are a dime a dozen in this city.';
    final a = analyze(app, sentence);
    final found = a.matches.where((m) => m.expr.phrase == 'a dime a dozen' && m.expr.cat == 'idioms').toList();
    expect(found, isNotEmpty, reason: 'the idiom is found in the sentence');
    final row = app.dict.db.select("SELECT senses FROM own_expr WHERE phrase = 'a dime a dozen' AND cat = 'idioms'");
    expect(row, isNotEmpty);
    final ownTr = ((jsonDecode(row.first.columnAt(0) as String) as List).first as Map)['tr'] as String;
    // The row is an unreviewed AI draft: the dictionary's own meaning stays (DictDb.sourcePolicy).
    final exprTr = app.dict.db.select("SELECT tr FROM expr WHERE phrase = 'a dime a dozen' AND cat = 'idioms'").first.columnAt(0);
    expect(found.first.expr.tr, exprTr, reason: 'the dictionary meaning is what the reader shows');
    expect(found.first.expr.trDraft, contains(ownTr), reason: 'the draft is kept as a suggestion');
  });
}
