// A sentence's Turkish must always be the Turkish of that very sentence:
// never the next sentence's, never another paragraph's, chapter's or book's,
// and never the English itself. Covers the four reported cases from
// "English Fairy Tales" (notes), 60+ further sentences (references, long
// sentences, dialogue, phrasal verbs and idioms, words with several
// meanings), translations saved by older versions, changed text, a model that
// renumbers its answers after joining two sentences, the saved-answer cache,
// offline use, and late or failed answers while the learner moves on.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/sentence_translation.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:kelime_okur/online/ai_service.dart';
import 'package:kelime_okur/online/auto_analyzer.dart';
import 'package:kelime_okur/ui/context_sense_card.dart';
import 'package:kelime_okur/ui/meaning_parts.dart';
import 'package:kelime_okur/ui/sentence_sheet.dart';
import 'package:kelime_okur/ui/paragraph_view.dart';
import 'package:kelime_okur/ui/theme.dart';
import 'package:kelime_okur/ui/word_sheet.dart';
import 'package:sqlite3/sqlite3.dart';

// ---------------------------------------------------------------- the texts

/// The two reported paragraphs, as they are in the free library's book.
const singingBone = 'Parallels.--The story is clearly that of Grimm\'s "Singing Bone" (No. 28), where one brother slays '
    'the other and buries him under a bush. Years after a shepherd passing by finds a bone under the bush, and, '
    'blowing through this, hears the bone denounce the murderer. For numerous variants in Ballads and Folk Tales, '
    'see Prof. Child\'s English and Scotch Ballads (ed. 1886), i. 125, 493; iii. 499.';
const beanstalk = 'Parallels.--There is a chap-book version which is very poor; it is given by Mr. E. S. Hartland, '
    'English Folk and Fairy Tales (Camelot Series), p. 35, seq. In this, when Jack arrives at the top of the Beanstalk, '
    'he is met by a fairy, who gravely informs him that the ogre had stolen all his possessions from Jack\'s father. '
    'The object of this was to prevent the tale becoming an encouragement to theft! I have had greater confidence in '
    'my young friends, and have deleted the fairy who did not exist in the tale as told to me. For the Beanstalk '
    'elsewhere, see Ralston, Russian Folk Tales, 293-8. Cosquin has some remarks on magical ascents (i. 14).';

/// Further sentences by kind; each list becomes one paragraph.
const corpus = <String, List<String>>{
  'academic': [
    'Prof. Stephens gave a variant from his own memory in Folk-Lore Record, iii. 155, as told in Essex.',
    'Mr. Toulmin Smith gave another version in The Constitutional, July 1, 1853.',
    'It occurs also in Ireland, Kennedy, Fireside Stories, p. 9.',
    'It is Grimm\'s Kluge Else, No. 34, and is spread through the world.',
    'Mr. Clouston devotes the seventh chapter of his Book of Noodles to the Quest of the Three Noodles.',
    'See Dr. Brown\'s study, Vol. 2, ch. 3, and Fig. 4 for the details.',
    'The rhyme is given by Halliwell, pp. 20-24, cf. Jacobs, Celtic Fairy Tales, no. 5.',
    'Cosquin, Contes pop. de Lorraine, i. 269 seq., gives the Continental parallels.',
    'The painting by J. M. W. Turner was sold in the U.S. for 3.5 million dollars.',
    'Mrs. E. Burne-Jones told it from memory, e.g. the rhyme, i.e. the oldest part.',
  ],
  'long': [
    'Although the night was cold and the road was long, the old man kept walking, because he had promised his daughter that he would be home before the bells rang.',
    'When the giant came back, he looked under the bed, behind the door and inside the oven, but he could not find the boy, who was hiding in the copper.',
    'She had lived in the village all her life, and she knew every path, every stream and every stone, yet that morning everything seemed strange to her.',
    'The king, who had three sons and no daughters, decided that the one who brought him the finest carpet would be the next king.',
    'If you had listened to me, we would not be lost in this forest, and the wolves would not be howling around us now.',
    'They walked for hours; the sun went down, the stars came out, and still there was no house in sight.',
    'He opened the box slowly, and inside, wrapped in an old cloth, lay a golden key that shone like the sun.',
    'Nobody knew where the stranger had come from, nor why he carried a bag of stones wherever he went.',
    'The farmer sold the cow for a handful of beans, which his wife threw out of the window in anger.',
    'By the time the soldiers reached the bridge, the river had risen so high that the water covered the road.',
  ],
  'dialogue': [
    '"Where are you going?" asked the wolf.',
    '"To my grandmother\'s house," said the girl.',
    '"Run!" she cried.',
    '"Now!"',
    '\'Well!\' thought Alice to herself.',
    '\'What a fall!\'',
    '"Mr. Fox, is that you?" whispered Lady Mary.',
    '"I am not afraid," he said, "but I am tired."',
    '"Who has been sitting in my chair?" said the Great, Huge Bear.',
    'Wait... Who is there?',
  ],
  'phrasal': [
    'He gave up smoking last year.',
    'She looked the word up in the dictionary.',
    'They ran out of money before the end of the trip.',
    'The plane took off at noon.',
    'Please turn the light off before you leave.',
    'He came across an old letter in the attic.',
    'It is raining cats and dogs.',
    'Don\'t beat around the bush and tell me the truth.',
    'She broke the ice with a joke.',
    'The news spread like wildfire through the town.',
  ],
  'polysemy': [
    'He sat on the bank of the river.',
    'She put her money in the bank.',
    'The bat flew out of the cave.',
    'He hit the ball with a bat.',
    'The light was too bright for his eyes.',
    'The box was light enough to carry.',
    'They will run the shop together.',
    'There was a run on the bank that morning.',
    'She can\'t bear the noise.',
    'A bear came out of the woods.',
    'He will book a room for the night.',
    'The book lay open on the table.',
  ],
};

// ---------------------------------------------------------------- fakes

/// Translates by tagging the English, so every Turkish names its sentence.
String fakeTr(String en) => 'TR⟨${sentenceKey(en)}⟩';

/// The English sentence a fake Turkish was made from.
String? sourceOf(String tr) {
  final m = RegExp(r'^TR⟨(.*)⟩$').firstMatch(tr);
  return m?.group(1);
}

class FakeAi extends AiService {
  /// Joins sentence [joinAt] with the next one and then numbers its answers
  /// on, the way a model loses its place: every later answer names the
  /// number of the sentence before.
  final int? joinAt;

  /// Answers without the "src" words (older answer shape).
  final bool noSrc;
  FakeAi({this.joinAt, this.noSrc = false}) : super(AiConfig(providerById['openai']!, 'k', 'fake-model', 'http://localhost'));

  final explainCalls = <String, Completer<({String translation, String explanation, String explanationEn})>>{};

  var chunkCalls = 0;

  @override
  Future<bool> reachable() async => true;

  @override
  Future<({List<String> translations, String summary})> translateChunk(List<String> sentences) async {
    chunkCalls++;
    final items = <Map<String, Object?>>[];
    var n = 0;
    for (var i = 0; i < sentences.length; i++) {
      if (joinAt != null && i == joinAt && i + 1 < sentences.length) {
        items.add({'i': n, 'src': _src(sentences[i]), 'tr': '${fakeTr(sentences[i])} ${fakeTr(sentences[i + 1])}'});
        i++;
      } else {
        items.add({'i': n, 'src': _src(sentences[i]), 'tr': fakeTr(sentences[i])});
      }
      n++;
    }
    if (noSrc) {
      for (final e in items) {
        e.remove('src');
      }
    }
    return (translations: parseChunkTranslations(sentences, items), summary: '');
  }

  String _src(String s) => s.split(RegExp(r'\s+')).take(3).join(' ');

  @override
  Future<({String translation, String explanation, String explanationEn})> explainSentence(String sentence, String context) {
    final c = Completer<({String translation, String explanation, String explanationEn})>();
    explainCalls[sentence] = c;
    return c.future;
  }
}

// ---------------------------------------------------------------- set-up

late Directory dir;
late AppState app;

AppState openApp() {
  final d = DictDb();
  d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
  d.load();
  return AppState(d, UserDb.open(dir));
}

/// Two books; the first has the reported notes in chapter 0 and the corpus in
/// chapter 1, the second repeats a sentence of the first in another place.
late int book1, book2;

void addBooks() {
  book1 = app.user.insertBook(ImportedBook('English Fairy Tales', 'Joseph Jacobs', 'txt', [
    ImportedChapter('Notes', [('p', singingBone), ('p', beanstalk)]),
    ImportedChapter('Corpus', [for (final s in corpus.values) ('p', s.join(' '))]),
  ]));
  book2 = app.user.insertBook(ImportedBook('Other book', null, 'txt', [
    ImportedChapter('One', [('p', 'He gave up smoking last year. The plane took off at noon.')]),
    ImportedChapter('Two', [('p', 'Years after a shepherd came. Where did he go?')]),
  ]));
}

/// Every sentence of [bookId] as the reader's sentence panel sees it: for
/// each word of each sentence, the context built from a tap on that word.
List<WordContext> everyTap(int bookId) {
  final out = <WordContext>[];
  for (final ch in app.user.chapters(bookId)) {
    for (final p in app.user.paras(bookId, ch.idx)) {
      final a = analyze(app, p.text);
      for (var ti = 0; ti < a.tokens.length; ti++) {
        out.add(buildContext(app, p, a, ti, bookId: bookId, bookTitle: 'x'));
      }
    }
  }
  return out;
}

/// The checks every test makes: a Turkish shown for a sentence was made from
/// exactly that sentence.
void expectOwnTranslations(List<WordContext> taps, {bool allPresent = false}) {
  var shown = 0;
  for (final c in taps) {
    final tr = c.sentenceTr?.first;
    if (tr == null) {
      if (allPresent) fail('no Turkish for "${c.sentence}"');
      continue;
    }
    shown++;
    // A model that joined this sentence with the next one may answer both
    // together; that answer still starts with this sentence's own Turkish.
    final src = sourceOf(tr.split(' TR⟨').first);
    expect(src, sentenceKey(c.sentence), reason: 'the Turkish of "${c.sentence}" was made from "$src"');
  }
  if (allPresent) expect(shown, taps.length);
}

void main() {
  setUp(() {
    dir = Directory.systemTemp.createTempSync('storilex_sent_tr');
    app = openApp();
    addBooks();
    AiService.debugFromSettings = null;
  });

  tearDown(() {
    AiService.debugFromSettings = null;
    dir.deleteSync(recursive: true);
  });

  test('the corpus has the four reported sentences and at least 50 more', () {
    final all = [singingBone, beanstalk, for (final s in corpus.values) s.join(' ')];
    final sentences = [for (final t in all) for (final r in sentenceRanges(t)) t.substring(r.$1, r.$2).trim()];
    expect(sentences.length, greaterThanOrEqualTo(54));
  });

  group('the four reported sentences get their own Turkish', () {
    setUp(() async {
      await analyzeBook(FakeAi(), app.user, book1);
    });

    WordContext tapOn(String paragraph, String word) {
      final p = app.user.paras(book1, 0).firstWhere((p) => p.text == paragraph);
      final a = analyze(app, p.text);
      final ti = a.tokens.indexWhere((t) => t.text == word);
      return buildContext(app, p, a, ti, bookId: book1);
    }

    test('A: "where one brother slays the other and buries him under a bush."', () {
      final c = tapOn(singingBone, 'slays');
      expect(c.sentence, endsWith('where one brother slays the other and buries him under a bush.'));
      expect(sourceOf(c.sentenceTr!.first), sentenceKey(c.sentence));
      expect(c.sentenceTr!.first, isNot(contains('shepherd')));
    });

    test('B: "For numerous variants in Ballads and Folk Tales, see Prof. …"', () {
      final c = tapOn(singingBone, 'numerous');
      expect(c.sentence, startsWith('For numerous variants in Ballads and Folk Tales, see Prof. Child'));
      expect(sourceOf(c.sentenceTr!.first), sentenceKey(c.sentence));
    });

    test('C: "I have had greater confidence in my young friends, …"', () {
      final c = tapOn(beanstalk, 'confidence');
      expect(c.sentence, 'I have had greater confidence in my young friends, and have deleted the fairy who did not exist in the tale as told to me.');
      expect(c.sentenceTr!.first, fakeTr(c.sentence));
      expect(c.sentenceTr!.first, isNot(contains('Ralston')));
    });

    test('D: "For the Beanstalk elsewhere, see Ralston, Russian Folk Tales, 293-8."', () {
      final c = tapOn(beanstalk, 'Ralston');
      expect(c.sentence, 'For the Beanstalk elsewhere, see Ralston, Russian Folk Tales, 293-8.');
      expect(c.sentenceTr!.first, fakeTr(c.sentence));
      expect(c.sentenceTr!.first, isNot(contains('Cosquin')));
    });
  });

  test('every sentence of every chapter and book shows its own Turkish', () async {
    await analyzeBook(FakeAi(), app.user, book1);
    await analyzeBook(FakeAi(), app.user, book2);
    // Taps in book 1, then book 2, then back: a sentence of the other book or
    // chapter (even the same words in another place) never carries over.
    expectOwnTranslations(everyTap(book1), allPresent: true);
    expectOwnTranslations(everyTap(book2), allPresent: true);
    expectOwnTranslations(everyTap(book1), allPresent: true);
  });

  test('a model that joins two sentences and numbers on never shifts the Turkish onto the next sentence', () async {
    for (var join = 0; join < 6; join++) {
      for (final ch in app.user.chapters(book1)) {
        for (final p in app.user.paras(book1, ch.idx)) {
          app.user.db.execute('UPDATE paras SET tr=NULL WHERE id=?', [p.id]);
        }
      }
      await analyzeBook(FakeAi(joinAt: join), app.user, book1);
      final taps = everyTap(book1);
      expectOwnTranslations(taps);
      // The sentences before the join keep their Turkish.
      expect(taps.where((c) => c.sentenceTr != null), isNotEmpty);
    }
  });

  test('answers without the "src" words (a model that leaves them out) still land on their numbers', () async {
    await analyzeBook(FakeAi(noSrc: true), app.user, book1);
    expectOwnTranslations(everyTap(book1), allPresent: true);
  });

  test('translations saved by older versions (a bare list, by position) are kept but never shown', () async {
    final p = app.user.paras(book1, 0).first;
    final sentences = [for (final r in sentenceRanges(p.text)) p.text.substring(r.$1, r.$2).trim()];
    // The reported situation: every item one sentence late.
    final shifted = [for (var i = 0; i < sentences.length; i++) i + 1 < sentences.length ? fakeTr(sentences[i + 1]) : ''];
    app.user.db.execute('UPDATE paras SET tr=? WHERE id=?', ['["${shifted.join('","')}"]', p.id]);
    final a = analyze(app, p.text);
    for (var ti = 0; ti < a.tokens.length; ti++) {
      expect(buildContext(app, p, a, ti).sentenceTr, isNull);
    }
    // Still on the device, untouched.
    expect(app.user.db.select('SELECT tr FROM paras WHERE id=?', [p.id]).first['tr'], startsWith('["'));
    expect(app.user.paraTranslation(p.id)!.legacy, isTrue);
  });

  test('when the paragraph\'s text changes, the old Turkish of a changed sentence is not shown', () async {
    await analyzeBook(FakeAi(), app.user, book1);
    final p = app.user.paras(book1, 0)[1];
    final changed = p.text.replaceFirst('I have had greater confidence', 'I had more confidence');
    app.user.db.execute('UPDATE paras SET text=? WHERE id=?', [changed, p.id]);
    final p2 = app.user.paras(book1, 0)[1];
    final a = analyze(app, p2.text);
    final taps = [for (var ti = 0; ti < a.tokens.length; ti++) buildContext(app, p2, a, ti)];
    expectOwnTranslations(taps);
    final mine = taps.firstWhere((c) => c.sentence.startsWith('I had more confidence'));
    expect(mine.sentenceTr, isNull);
    expect(taps.firstWhere((c) => c.sentence.startsWith('For the Beanstalk')).sentenceTr, isNotNull);
  });

  test('translations work offline: read from the device with no AI service', () async {
    await analyzeBook(FakeAi(), app.user, book1);
    app = openApp(); // a restart, no service connected
    expect(AiService.fromSettings(app.user), isNull);
    expectOwnTranslations(everyTap(book1), allPresent: true);
  });

  group('stored format', () {
    test('items are tied to their English, with the direction and the engine', () {
      const t = ParaTranslations([SentenceTranslation('Hello there.', 'Merhaba.'), SentenceTranslation('Bye.', 'Hoşça kal.')], engine: 'ai:x/y');
      final back = ParaTranslations.decode(t.encode())!;
      expect(back.legacy, isFalse);
      expect(back.engine, 'ai:x/y');
      expect(back.dir, 'en>tr');
      expect(back.forSentence('  Hello   there. '), 'Merhaba.');
      expect(back.forSentence('Bye.'), 'Hoşça kal.');
      expect(back.forSentence('Hello.'), isNull);
    });

    test('the English handed back as "Turkish", and empty answers, are never used', () {
      const t = ParaTranslations([SentenceTranslation('499.', '499.'), SentenceTranslation('Go home.', 'go home.'), SentenceTranslation('Hi.', ' ')]);
      expect(t.forSentence('499.'), isNull);
      expect(t.forSentence('Go home.'), isNull);
      expect(t.forSentence('Hi.'), isNull);
      expect(usableTranslation('Go home.', 'Eve git.'), isTrue);
    });

    test('broken or legacy JSON is not shown', () {
      expect(ParaTranslations.decode('["a","b"]')!.forSentence('a'), isNull);
      expect(ParaTranslations.decode('{oops')!.forSentence('a'), isNull);
      expect(ParaTranslations.decode(null), isNull);
    });

    test('numbered answers: one that repeats another sentence\'s words is dropped', () {
      final s = ['The story is old.', 'Years after a shepherd came.', 'For variants see Child.'];
      final out = alignNumberedTranslations(s, [
        (i: 0, src: 'The story is', tr: 'Hikâye eski. Yıllar sonra bir çoban geldi.'),
        (i: 1, src: 'For variants see', tr: 'Varyantlar için bkz. Child.'), // renumbered
        (i: 2, src: null, tr: 'Varyantlar.'),
        (i: 9, src: null, tr: 'out of range'),
      ]);
      expect(out, ['Hikâye eski. Yıllar sonra bir çoban geldi.', '', 'Varyantlar.']);
    });

    test('a plain list of a different length is not used at all', () {
      expect(parseChunkTranslations(['A b.', 'C d.', 'E f.'], ['x', 'y']), ['', '', '']);
      expect(parseChunkTranslations(['A b.', 'C d.'], ['x', 'y']), ['x', 'y']);
    });
  });

  group('the sentence card', () {
    Future<void> pump(WidgetTester tester, WordContext c, {String? tr}) async {
      tester.view.physicalSize = const Size(420 * 2, 900 * 2);
      tester.view.devicePixelRatio = 2;
      await tester.pumpWidget(MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(body: BookSentenceCard(key: const ValueKey('card'), app: app, ctx: c, highlight: const {}, tr: tr))));
      await tester.pump();
    }

    WordContext ctxOf(String s, {List<String>? tr}) => WordContext(s, tokenize(s), 0, const [], tr, book1, 'x');

    testWidgets('with no valid translation the Turkish line is hidden, and the English is never shown as Turkish', (tester) async {
      await pump(tester, ctxOf('For the Beanstalk elsewhere, see Ralston.'));
      expect(find.byKey(const ValueKey('ctx-sentence-tr')), findsNothing);
      expect(find.byType(LangTag), findsOneWidget); // only the English line
      expect(find.text('Çeviri oluşturulamadı'), findsNothing);
      app.user.setSentenceAi('499.', '499.', null);
      await pump(tester, ctxOf('499.'));
      expect(find.byKey(const ValueKey('ctx-sentence-tr')), findsNothing);
      expect(find.byType(LangTag), findsOneWidget);
    });

    testWidgets('a saved answer (cache) is shown after a restart, only for its own sentence', (tester) async {
      app.user.setSentenceAi('He sat on the bank of the river.', 'Nehrin kıyısında oturdu.', null);
      app = openApp();
      await pump(tester, ctxOf('He sat on the bank of the river.'));
      expect(find.text('Nehrin kıyısında oturdu.'), findsOneWidget);
      await pump(tester, ctxOf('She put her money in the bank.'));
      expect(find.text('Nehrin kıyısında oturdu.'), findsNothing);
    });

    testWidgets('quick selections: a late answer for the previous sentence never shows under the new one', (tester) async {
      final ai = FakeAi();
      AiService.debugFromSettings = (_) => ai;
      const a = 'I have had greater confidence in my young friends.';
      const b = 'For the Beanstalk elsewhere, see Ralston.';
      await pump(tester, ctxOf(a));
      await tester.tap(find.byKey(const ValueKey('ctx-sentence-translate')));
      await tester.pump();
      // The learner moves on to the next sentence before the answer comes.
      await pump(tester, ctxOf(b));
      ai.explainCalls[a]!.complete((translation: 'Genç arkadaşlarıma daha çok güvendim.', explanation: '', explanationEn: ''));
      await tester.pump();
      expect(find.text('Genç arkadaşlarıma daha çok güvendim.'), findsNothing);
      expect(find.byKey(const ValueKey('ctx-sentence-translate')), findsOneWidget);
      // It was saved for its own sentence, and shows there.
      expect(app.user.sentenceAi(a)!.$1, 'Genç arkadaşlarıma daha çok güvendim.');
      await pump(tester, ctxOf(a));
      expect(find.text('Genç arkadaşlarıma daha çok güvendim.'), findsOneWidget);
    });

    testWidgets('a failed or late answer shows an error, never another sentence', (tester) async {
      final ai = FakeAi();
      AiService.debugFromSettings = (_) => ai;
      const a = 'The plane took off at noon.';
      await pump(tester, ctxOf(a));
      await tester.tap(find.byKey(const ValueKey('ctx-sentence-translate')));
      await tester.pump();
      expect(find.text('Çevriliyor…'), findsOneWidget);
      ai.explainCalls[a]!.completeError(TimeoutException('slow'));
      await tester.pump();
      expect(find.textContaining('Çevrilemedi'), findsOneWidget);
      expect(find.byKey(const ValueKey('ctx-sentence-tr')), findsNothing);
      // An answer that is just the English again counts as no translation.
      await tester.tap(find.byKey(const ValueKey('ctx-sentence-translate')));
      await tester.pump();
      ai.explainCalls[a]!.complete((translation: a, explanation: '', explanationEn: ''));
      await tester.pump();
      expect(find.byKey(const ValueKey('ctx-sentence-tr')), findsNothing);
      expect(find.byKey(const ValueKey('ctx-sentence-translate')), findsNothing);
      expect(find.byType(LangTag), findsOneWidget);
    });

    testWidgets('order: the verified book translation, then the sentence cache', (tester) async {
      const s = 'He sat on the bank of the river.';
      app.user.setSentenceAi(s, 'Önbellekteki çeviri.', null, engine: 'ai:x/y');
      await pump(tester, ctxOf(s, tr: ['Paragraf çevirisi.']), tr: 'Panelin çevirisi.');
      expect(find.text('Paragraf çevirisi.'), findsOneWidget);
      expect(find.text('Panelin çevirisi.'), findsNothing);
      await pump(tester, ctxOf(s), tr: 'Panelin çevirisi.');
      expect(find.text('Panelin çevirisi.'), findsOneWidget);
      await pump(tester, ctxOf(s));
      expect(find.text('Önbellekteki çeviri.'), findsOneWidget);
    });
  });

  group('paid AI only with the learner\'s permission', () {
    test('automatic book analysis is off unless switched on ("1"); no value and "0" are off', () async {
      final ai = FakeAi();
      AiService.debugFromSettings = (_) => ai;
      final a = AutoAnalyzer(app.user);
      expect(a.enabled, isFalse);
      await a.tick();
      expect(ai.chunkCalls, 0);
      app.user.setSetting('auto_analyze', '0');
      await a.tick();
      expect(ai.chunkCalls, 0);
      app.user.setSetting('auto_analyze', '1');
      expect(a.enabled, isTrue);
      await a.tick(onlyBook: book2);
      expect(ai.chunkCalls, greaterThan(0));
    });

    test('the book menu action still runs it when asked (force)', () async {
      final ai = FakeAi();
      AiService.debugFromSettings = (_) => ai;
      await AutoAnalyzer(app.user).tick(force: true, onlyBook: book2);
      expect(ai.chunkCalls, greaterThan(0));
    });

    testWidgets('opening the sentence panel asks the AI nothing; "Explain in detail" does', (tester) async {
      final ai = FakeAi();
      AiService.debugFromSettings = (_) => ai;
      final p = app.user.paras(book2, 0).first;
      final a = analyze(app, p.text);
      final c = buildContext(app, p, a, 0, bookId: book2);
      tester.view.physicalSize = const Size(420 * 2, 1400 * 2);
      tester.view.devicePixelRatio = 2;
      await tester.pumpWidget(MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(body: SentencePanel(app: app, ctx: c, para: p, matches: const []))));
      await tester.pump();
      expect(ai.explainCalls, isEmpty);
      await tester.tap(find.text('Ayrıntılı açıkla'));
      await tester.pump();
      expect(ai.explainCalls.keys, [c.sentence]);
      ai.explainCalls[c.sentence]!.complete((translation: 'Geçen yıl sigarayı bıraktı.', explanation: 'Geçmiş zaman.', explanationEn: 'Past simple.'));
      await tester.pump();
      expect(find.text('Geçmiş zaman.'), findsOneWidget);
      // Saved with its source sentence, direction and engine.
      final row = app.user.db.select('SELECT tr, dir, engine FROM sentence_ai WHERE sentence=?', [c.sentence]).first;
      expect(row['tr'], 'Geçen yıl sigarayı bıraktı.');
      expect(row['dir'], 'en>tr');
      expect(row['engine'], 'ai:openai/fake-model');
    });
  });

  group('sentence cache', () {
    test('older rows (no direction, no engine) are kept and still read', () {
      final old = Directory.systemTemp.createTempSync('storilex_old_db');
      final raw = sqlite3.open('${old.path}/user.db');
      raw.execute('CREATE TABLE sentence_ai(sentence TEXT PRIMARY KEY, tr TEXT, exp TEXT)');
      raw.execute("INSERT INTO sentence_ai VALUES ('Hello there.', 'Merhaba.', NULL)");
      raw.close();
      final u = UserDb.open(old);
      expect(u.sentenceAi('Hello there.')!.$1, 'Merhaba.');
      expect(u.db.select('SELECT COUNT(*) AS n FROM sentence_ai').first['n'], 1);
      old.deleteSync(recursive: true);
    });

    test('an answer is used only for its own direction', () {
      app.user.setSentenceAi('Merhaba.', 'Hello.', null, dir: 'tr>en', engine: 'ai:x/y');
      expect(app.user.sentenceAi('Merhaba.'), isNull);
      expect(app.user.sentenceAi('Merhaba.', dir: 'tr>en')!.$1, 'Hello.');
    });
  });
}
