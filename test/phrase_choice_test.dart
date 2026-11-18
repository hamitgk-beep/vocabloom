// One rule for the expression under a tap or a highlight: the underline, the
// tap and the panel pick the same expression, and a phrasal verb split by a
// noun object is found ("look the word up in the dictionary").
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/ai/key_ai.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:kelime_okur/ui/paragraph_view.dart';
import 'package:sqlite3/sqlite3.dart';

late AppState app;

List<String> spans(String s) => [
      for (final m in app.dict.matcher.match(tokenize(s), text: s))
        if (m.tokens.length > 1) '${m.expr.phrase}${m.tokens}'
    ];

void main() {
  setUpAll(() {
    final d = DictDb();
    d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    final u = UserDb.open(Directory.systemTemp.createTempSync('vocabloom_pc'));
    app = AppState(d, u)..localAi = KeyAi(u);
    app.enabledCats.addAll(allCategories.map((c) => c.id));
  });

  test('"look the word up in the dictionary" is found: look up over the object', () {
    expect(spans('Look the word up in the dictionary.'), contains('look up[0, 3]'));
  });

  test('a preposition after another particle does not close the verb: take the bus in town', () {
    expect(spans('I take the bus in town.').where((x) => x.startsWith('take in')), isEmpty);
  });

  test('the same rule for the tap, the underline and the panel: "make up one\'s mind" wins over "make up"', () {
    final a = analyze(app, 'I made up my mind.');
    // "up" is token 2: the longest enabled expression is the one the tap opens.
    final e = a.expressionsAt(app, 2);
    expect(e.first.expr.phrase, "make up one's mind");
    expect(e.map((m) => m.expr.phrase), contains('make up'));
    // Every word of the chosen span gets the same choice, so the underline is one piece.
    for (final i in e.first.tokens) {
      expect(a.expressionsAt(app, i).first.expr.phrase, "make up one's mind", reason: 'token $i');
    }
    expect(a.shownAt(app, 2).cat, 'idioms');
  });

  test('a disabled filter gives no expression, so the word is not underlined as one', () {
    final a = analyze(app, 'I made up my mind.');
    app.enabledCats.remove('idioms');
    app.enabledCats.remove('phrasal_verbs');
    expect(a.expressionsAt(app, 2), isEmpty);
    app.enabledCats.addAll(['idioms', 'phrasal_verbs']);
  });

  test('a literal use is not chosen: "lived in Kansas" is not the phrasal verb "live in"', () {
    final a = analyze(app, 'Dorothy lived in Kansas.');
    expect(a.expressionsAt(app, 1).where((m) => m.expr.phrase == 'live in'), isEmpty);
  });

  test('ordinary sequences are not marked as phrases: put the book on the table', () {
    final a = analyze(app, 'She put the book on the table.');
    final put = a.expressionsAt(app, 1).where((m) => m.expr.phrase.startsWith('put on'));
    expect(put, isEmpty);
  });
}
