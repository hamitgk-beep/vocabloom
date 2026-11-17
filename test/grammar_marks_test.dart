// Grammar highlights in the reader: each structure is found where it is, and
// look-alikes (an -ed adjective, "if" in a question, "that" after "said") are
// left alone, so the colours do not teach something wrong.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:sqlite3/sqlite3.dart';

late AppState app;

/// "key: words" for every structure in [s].
List<String> marks(String s, [String? cat]) {
  final toks = tokenize(s);
  return [
    for (final m in app.grammar.mark(s, toks))
      if (cat == null || m.cat == cat) '${m.key}: ${m.tokens.map((i) => toks[i].text).join(' ')}',
  ];
}

void expectMarks(String s, String cat, List<String> want, {List<String> not = const []}) {
  final got = marks(s, cat);
  for (final w in want) {
    expect(got, contains(w), reason: '"$s"\n  got: $got');
  }
  for (final n in not) {
    expect(got.where((g) => g.startsWith(n) || g.endsWith(n)), isEmpty, reason: '"$s" should not have $n\n  got: $got');
  }
}

void main() {
  setUpAll(() {
    final d = DictDb();
    d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    app = AppState(d, UserDb.open(Directory.systemTemp.createTempSync('vb_gm')));
  });

  group('tenses', () {
    test('auxiliary tenses', () {
      expectMarks('She has lived here for ten years.', 'g_tenses', ['present_perfect: has lived']);
      expectMarks('They had already left when we arrived.', 'g_tenses', ['past_perfect: had left', 'simple_past: arrived']);
      expectMarks('I have been waiting for an hour.', 'g_tenses', ['present_perfect_continuous: have been waiting']);
      expectMarks('He had been working all night.', 'g_tenses', ['past_perfect_continuous: had been working']);
      expectMarks('We will finish it tomorrow.', 'g_tenses', ['future_simple: will finish']);
      expectMarks("I'll call you later.", 'g_tenses', ["future_simple: I'll call"]);
      expectMarks('This time next week I will be lying on a beach.', 'g_tenses', ['future_continuous: will be lying']);
      expectMarks('By June they will have finished the bridge.', 'g_tenses', ['future_perfect: will have finished']);
      expectMarks('It is going to rain.', 'g_tenses', ['going_to: is going to rain']);
      expectMarks('She is going to the market.', 'g_tenses', ['present_continuous: is going'], not: ['going_to']);
      expectMarks('The children were playing in the garden.', 'g_tenses', ['past_continuous: were playing']);
      expectMarks('He is reading a book.', 'g_tenses', ['present_continuous: is reading']);
      expectMarks("She's finished her homework.", 'g_tenses', ["present_perfect: She's finished"]);
      expectMarks("He's coming tomorrow.", 'g_tenses', ["present_continuous: He's coming"]);
      expectMarks('Have you ever seen a ghost?', 'g_tenses', ['present_perfect: Have seen']);
      expectMarks('Did she go home?', 'g_tenses', ['simple_past: Did go']);
      expectMarks("I didn't know that.", 'g_tenses', ["simple_past: didn't know"]);
      expectMarks('She does not like coffee.', 'g_tenses', ['simple_present: does like']);
    });

    test('passive', () {
      final p = app.grammar.mark('The palace was built in a single night.', tokenize('The palace was built in a single night.')).where((m) => m.cat == 'g_tenses');
      expect(p.single.key, 'simple_past');
      expect(p.single.en, 'Simple Past (Passive)');
      expect(p.single.lessons, contains('passive'));
      expectMarks('The letters are written by hand.', 'g_tenses', ['simple_present: are written']);
      expectMarks('The house has been sold.', 'g_tenses', ['present_perfect: has been sold']);
      expectMarks('The road is being repaired.', 'g_tenses', ['present_continuous: is being repaired']);
    });

    test('be + adjective is not passive or continuous', () {
      final tired = app.grammar.mark('She was tired.', tokenize('She was tired.'));
      expect(tired.single.en, 'Simple Past');
      expect(tired.single.tokens.length, 1);
      expectMarks('The film was interesting.', 'g_tenses', ['simple_past: was'], not: ['past_continuous']);
      expectMarks('His face was red.', 'g_tenses', ['simple_past: was']);
      expectMarks('They are married.', 'g_tenses', ['simple_present: are']);
    });

    test('simple tenses after a subject', () {
      expectMarks('He knows the way.', 'g_tenses', ['simple_present: knows']);
      expectMarks('They live in a small village.', 'g_tenses', ['simple_present: live']);
      expectMarks('Aladdin smiled.', 'g_tenses', ['simple_past: smiled']);
      expectMarks('The old man looked up.', 'g_tenses', ['simple_past: looked']);
      expectMarks('He stood up and walked to the door.', 'g_tenses', ['simple_past: stood', 'simple_past: walked']);
      expectMarks('Black smoke came from the fire.', 'g_tenses', ['simple_past: came']);
      expectMarks('Abanazar had tears in his eyes.', 'g_tenses', ['simple_past: had'], not: ['simple_present']);
      expectMarks("He put the money into Aladdin's hands.", 'g_tenses', [], not: ['simple_present: hands']);
      expectMarks("Don't ask Aladdin questions about work!", 'g_tenses', [], not: ['simple_present: questions']);
    });

    test('nouns and participles are not verbs', () {
      expectMarks('He met a man called John.', 'g_tenses', ['simple_past: met'], not: ['simple_past: called']);
      expectMarks('The broken window was never repaired.', 'g_tenses', ['simple_past: was repaired'], not: ['simple_past: broken']);
      expectMarks('Their work is important.', 'g_tenses', ['simple_present: is'], not: ['simple_present: work']);
      expectMarks('In the morning, the city walls looked golden.', 'g_tenses', ['simple_past: looked'], not: ['simple_present: walls']);
      expectMarks('I need a new coat.', 'g_tenses', ['simple_present: need']);
    });

    test('tones follow the time', () {
      final m = app.grammar.mark('I live here, I lived there and I will live in Rome.', tokenize('I live here, I lived there and I will live in Rome.'));
      expect(
        [
          for (final x in m)
            if (x.cat == 'g_tenses') x.tone,
        ],
        [0, 1, 2],
      );
    });
  });

  group('conditionals', () {
    test('the four types', () {
      expectMarks('If you heat ice, it melts.', 'g_conditionals', ['cond_0: If heat melts']);
      expectMarks('If it rains tomorrow, we will stay at home.', 'g_conditionals', ['cond_1: If rains will stay']);
      expectMarks('If I were rich, I would buy a palace.', 'g_conditionals', ['cond_2: If were would buy']);
      expectMarks('If I had a car, I could drive you there.', 'g_conditionals', ['cond_2: If had could drive']);
      expectMarks('If she had studied, she would have passed the exam.', 'g_conditionals', ['cond_3: If had studied would have passed']);
      expectMarks('I would have helped you if you had asked me.', 'g_conditionals', ['cond_3: would have helped if had asked']);
      expectMarks('If I had taken the job, I would be rich now.', 'g_conditionals', ['cond_mixed_32: If had taken would be']);
      expectMarks('Call me if you need anything.', 'g_conditionals', ['cond_1: Call if need']);
      expectMarks('Unless you hurry, you will miss the train.', 'g_conditionals', ['cond_1: Unless hurry will miss']);
      expectMarks('Had I known, I would have come.', 'g_conditionals', ['cond_3: Had known would have come']);
    });

    test('"if" that is not a condition', () {
      expectMarks('She asked if I was hungry.', 'g_conditionals', [], not: ['cond']);
      expectMarks("I don't know if he will come.", 'g_conditionals', [], not: ['cond']);
      expectMarks('He looked as if he had seen a ghost.', 'g_conditionals', [], not: ['cond']);
      expectMarks('I wonder if it is true.', 'g_conditionals', [], not: ['cond']);
    });
  });

  group('relative clauses', () {
    test('found', () {
      expectMarks('The man who lives next door is a doctor.', 'g_relative', ['rel_who: who lives']);
      expectMarks('I found the book that you lost.', 'g_relative', ['rel_that: that you lost']);
      expectMarks('My brother, who lives in London, is a teacher.', 'g_relative', ['rel_who: who lives in London']);
      expectMarks('This is the house where I was born.', 'g_relative', ['rel_where: where I was born']);
      expectMarks('The girl whose bag was stolen called the police.', 'g_relative', ['rel_whose: whose bag was stolen']);
      expectMarks('The lamp, which was old and dirty, was magic.', 'g_relative', ['rel_which: which was old and dirty']);
      expectMarks('I remember the day when we met.', 'g_relative', ['rel_when: when we met']);
      expectMarks('The box in which he kept the ring was empty.', 'g_relative', ['rel_which: in which he kept']);
    });

    test('question words and "that" are not always relative', () {
      expectMarks('Who is that woman?', 'g_relative', [], not: ['rel']);
      expectMarks('I know who did it.', 'g_relative', [], not: ['rel']);
      expectMarks('He said that he was tired.', 'g_relative', [], not: ['rel']);
      expectMarks('I think that this is wrong.', 'g_relative', [], not: ['rel']);
      expectMarks('That book is mine.', 'g_relative', [], not: ['rel']);
      expectMarks('The fact that he left surprised us.', 'g_relative', [], not: ['rel']);
      expectMarks('Which one do you want?', 'g_relative', [], not: ['rel']);
      expectMarks("He asked his Vizier: 'Who is that woman?'", 'g_relative', [], not: ['rel']);
      expectMarks('When we arrived, they left.', 'g_relative', [], not: ['rel']);
      expectMarks('If there is no Mr Glass, whose hat is this?', 'g_relative', [], not: ['rel']);
      expectMarks('He agreed so far in formal act that some protection was employed.', 'g_relative', [], not: ['rel']);
      expectMarks('Who\'s making that noise?', 'g_tenses', ["present_continuous: Who's making"], not: ['simple_present: noise']);
    });
  });

  group('gerund / infinitive', () {
    test('found', () {
      expectMarks('I enjoy reading books.', 'g_gerund_inf', ['gerund_verb: enjoy reading']);
      expectMarks('She wants to learn English.', 'g_gerund_inf', ['inf_verb: wants to learn']);
      expectMarks('He stopped smoking last year.', 'g_gerund_inf', ['gerund_verb: stopped smoking']);
      expectMarks('He stopped to listen.', 'g_gerund_inf', ['inf_verb: stopped to listen']);
      expectMarks('They asked him to wait outside.', 'g_gerund_inf', ['obj_inf: asked him to wait']);
      expectMarks('She left without saying goodbye.', 'g_gerund_inf', ['prep_gerund: without saying']);
      expectMarks('I am looking forward to seeing you.', 'g_gerund_inf', ['prep_gerund: to seeing']);
      expectMarks('Would you like to have a shop?', 'g_gerund_inf', ['inf_verb: like to have']);
      expectMarks('He finished hunting and began to go home.', 'g_gerund_inf', ['gerund_verb: finished hunting', 'inf_verb: began to go']);
    });

    test('not gerunds', () {
      expectMarks('We went home in the morning.', 'g_gerund_inf', [], not: ['prep_gerund']);
      expectMarks('He lives on the top floor of the building.', 'g_gerund_inf', [], not: ['prep_gerund']);
      expectMarks('The ship sank in towering waves.', 'g_gerund_inf', [], not: ['prep_gerund']);
      expectMarks('They burst out laughing.', 'g_gerund_inf', [], not: ['prep_gerund']);
      expectMarks('I went to the shop to buy bread.', 'g_gerund_inf', [], not: ['inf_verb']);
    });
  });

  group('comparison', () {
    test('found', () {
      expectMarks('My house is bigger than yours.', 'g_comparison', ['comparative: bigger than']);
      expectMarks('This garden is more beautiful than the palace.', 'g_comparison', ['comparative: more beautiful than']);
      expectMarks('She is the tallest girl in the class.', 'g_comparison', ['superlative: the tallest']);
      expectMarks('It was the most beautiful palace in Arabia.', 'g_comparison', ['superlative: the most beautiful']);
      expectMarks('He is as tall as his father.', 'g_comparison', ['equality: as tall as']);
      expectMarks('This is the best day of my life.', 'g_comparison', ['superlative: the best']);
      expectMarks('Things got worse.', 'g_comparison', [], not: ['superlative']);
      expectMarks('She was happier than ever.', 'g_comparison', ['comparative: happier than']);
      expectMarks('He was the happiest man in Arabia.', 'g_comparison', ['superlative: the happiest']);
    });

    test('look-alikes', () {
      expectMarks('The number of teachers is growing.', 'g_comparison', [], not: ['comparative']);
      expectMarks('I will see you later.', 'g_comparison', [], not: ['comparative']);
      expectMarks('Most people like music.', 'g_comparison', [], not: ['superlative']);
      expectMarks('She was an honest woman.', 'g_comparison', [], not: ['superlative']);
      expectMarks('He came as soon as he could.', 'g_comparison', [], not: ['equality']);
      expectMarks('Never again, he said.', 'g_comparison', [], not: ['comparative']);
    });
  });

  group('reported speech', () {
    test('found', () {
      expectMarks('He said that he was tired.', 'g_reported', ['rep_statement: said that']);
      expectMarks('She told me that she had finished.', 'g_reported', ['rep_statement: told me that']);
      expectMarks('He said he would come.', 'g_reported', ['rep_statement: said']);
      expectMarks('She asked if I was hungry.', 'g_reported', ['rep_question: asked if']);
      expectMarks('He asked me where I lived.', 'g_reported', ['rep_question: asked me where']);
      expectMarks('The teacher told us to sit down.', 'g_reported', ['rep_command: told us to sit']);
      expectMarks('Can you tell me where the station is?', 'g_reported', ['indirect_question: Can tell me where']);
      expectMarks('I wonder if it is true.', 'g_reported', ['indirect_question: wonder if']);
    });

    test('direct speech is not reported speech', () {
      expectMarks('"I am tired," he said.', 'g_reported', [], not: ['rep']);
      expectMarks('He said, "I am tired."', 'g_reported', [], not: ['rep']);
      expectMarks("'Who lives there?' he asked.", 'g_reported', [], not: ['rep']);
      expectMarks('It is said that he is rich.', 'g_reported', [], not: ['rep']);
    });

    test('backshift is explained', () {
      final m = app.grammar.mark('He said that he was tired.', tokenize('He said that he was tired.')).firstWhere((m) => m.cat == 'g_reported');
      expect(m.note?.$2, contains('Simple Present'));
    });
  });

  group('passive, past modals, used to', () {
    test('passive', () {
      expectMarks('The palace was built in a single night.', 'g_passive', ['passive: was built']);
      expectMarks('The thief was caught by the police.', 'g_passive', ['passive: was caught']);
      expectMarks('The lamp can be found in the garden.', 'g_passive', ['passive: can be found']);
      expectMarks('She was tired.', 'g_passive', [], not: ['passive']);
      expectMarks('They are married.', 'g_passive', [], not: ['passive']);
      final m = app.grammar.mark('The thief was caught by the police.', tokenize('The thief was caught by the police.')).firstWhere((m) => m.cat == 'g_passive');
      expect(m.note?.$2, contains('by the police'));
    });

    test('past modals', () {
      expectMarks('You should have told me.', 'g_past_modals', ['past_modal: should have told']);
      expectMarks('He must have left early.', 'g_past_modals', ['past_modal: must have left']);
      expectMarks("She can't have seen us.", 'g_past_modals', ["past_modal: can't have seen"]);
      expectMarks('They might have missed the train.', 'g_past_modals', ['past_modal: might have missed']);
      expectMarks('You should tell me.', 'g_past_modals', [], not: ['past_modal']);
    });

    test('used to / be used to', () {
      expectMarks('He used to play football.', 'g_used_to', ['used_to: used to play']);
      expectMarks('She is used to working at night.', 'g_used_to', ['be_used_to: is used to working']);
      expectMarks('I got used to the cold.', 'g_used_to', ['be_used_to: got used to']);
      expectMarks('This knife is used to cut bread.', 'g_used_to', ['used_for: is used to cut']);
      expectMarks('I used the money to buy a coat.', 'g_used_to', [], not: ['used']);
    });
  });

  group('causative, emphasis, tags, condition words', () {
    test('causative', () {
      expectMarks('I had my hair cut yesterday.', 'g_causative', ['causative_pp: had cut']);
      expectMarks('She got the car repaired.', 'g_causative', ['causative_pp: got repaired']);
      expectMarks('The film made him cry.', 'g_causative', ['causative_base: made him cry']);
      expectMarks('He made her dinner.', 'g_causative', [], not: ['causative']);
      expectMarks('She is used to pain.', 'g_used_to', [], not: ['used_for']);
      expectMarks('He got his friend to help.', 'g_causative', [], not: ['causative_pp']);
      expectMarks('I got him to help me.', 'g_causative', ['causative_get: got him to help']);
      expectMarks('I had a broken leg.', 'g_causative', [], not: ['causative']);
      expectMarks('Have you finished your work?', 'g_causative', [], not: ['causative']);
      expectMarks('She had a cup of tea.', 'g_causative', [], not: ['causative']);
      expectMarks('He made a cake for her.', 'g_causative', [], not: ['causative']);
      expectMarks('They have the money.', 'g_causative', [], not: ['causative']);
    });

    test('inversion and cleft', () {
      expectMarks('Never have I seen such a thing.', 'g_emphasis', ['inversion: Never have']);
      expectMarks('Not only did he lie, but he also stole.', 'g_emphasis', ['inversion: Not only did']);
      expectMarks('Little did she know what was coming.', 'g_emphasis', ['inversion: Little did']);
      expectMarks('Never mind.', 'g_emphasis', [], not: ['inversion']);
      expectMarks('Hardly anyone came to the party.', 'g_emphasis', [], not: ['inversion']);
      expectMarks('It was John who called.', 'g_emphasis', ['cleft: It was who']);
      expectMarks('It was in Paris that they met.', 'g_emphasis', ['cleft: It was that']);
      expectMarks('It was clear that he had left.', 'g_emphasis', [], not: ['cleft']);
      expectMarks('It was the best book that I have read.', 'g_emphasis', [], not: ['cleft']);
      expectMarks('What I need is a holiday.', 'g_emphasis', ['pseudo_cleft: What is']);
      expectMarks('What is your name?', 'g_emphasis', [], not: ['pseudo_cleft']);
    });

    test('question tags', () {
      expectMarks("She is late, isn't she?", 'g_tags', ["tag: isn't she"]);
      expectMarks("You didn't see him, did you?", 'g_tags', ['tag: did you']);
      expectMarks('Did you see him?', 'g_tags', [], not: ['tag']);
      expectMarks('Where is he?', 'g_tags', [], not: ['tag']);
    });

    test('other condition words', () {
      expectMarks('You can go, provided that you come back early.', 'g_conditionals', ['cond_1: can go provided that come']);
      expectMarks('As long as you work hard, you will pass.', 'g_conditionals', ['cond_1: As long as work will pass']);
      expectMarks('The river is as long as the road.', 'g_conditionals', [], not: ['cond']);
      expectMarks('He provided the food.', 'g_conditionals', [], not: ['cond']);
    });
  });

  test('every lesson link exists in the grammar topics', () {
    final topics = File('assets/grammar/lessons.json').readAsStringSync();
    const text =
        'If she had studied, she would have passed. The man who lives here said that he was tired. '
        'I enjoy reading and want to learn. It is bigger than mine. If it rains, we will stay. If I were you, I would go. '
        'She has been waiting. He will have left. The house was built. I had left before they came.';
    final all = app.grammar.mark(text, tokenize(text));
    expect(all.map((m) => m.cat).toSet().length, greaterThanOrEqualTo(6));
    for (final m in all) {
      for (final l in m.lessons) {
        expect(topics, contains('"id": "$l"'), reason: l);
      }
    }
  });
}
