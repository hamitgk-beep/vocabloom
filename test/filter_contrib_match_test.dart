// The phrases of the new filters (tools/contrib filter sheet) are found in a
// text: an inflected verb, a single word, a fixed comparison.
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final d = DictDb()..db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
  d.load();
  List<String> found(String s, String cat) => [
        for (final m in d.matcher.match(tokenize(s), text: s))
          if (m.expr.cat == cat) m.expr.phrase
      ];

  test('each new filter finds its phrase', () {
    expect(found('She was interested in history.', 'dependent_prepositions'), contains('interested in'));
    expect(found('It depended on the weather.', 'dependent_prepositions'), contains('depend on'));
    expect(found('The cold weather affected the crops.', 'confusables'), contains('affect'));
    expect(found('He was as busy as a bee.', 'similes'), contains('as busy as a bee'));
    expect(found('Could you please close the window?', 'polite_phrases'), contains('could you please'));
    expect(found('The lorry arrived early.', 'uk_us'), contains('lorry'));
    expect(found('We hung out after class.', 'informal_slang'), contains('hang out'));
    // Second sheet: a slot for the person, "be" in any form, a proverb.
    expect(found('They accused him of lying.', 'dependent_prepositions'), contains('accuse someone of'));
    expect(found('The village is famous for its olive oil.', 'dependent_prepositions'), contains('be famous for'));
    expect(found('Well, better late than never.', 'proverbs'), contains('better late than never'));
    // Third sheet: everyday chunks and discourse markers.
    expect(found('Hey Tom, long time no see!', 'chunks'), contains('long time no see'));
    expect(found("I'll get back to you tomorrow.", 'chunks'), contains("i'll get back to you"));
    expect(found('To be honest, I did not like the film.', 'discourse_markers'), contains('to be honest'));
    // Sheets 4-6: a possessive slot, a gap inside a conjunction, a slot before the preposition, a UK word.
    expect(found('Keep your chin up; tomorrow may be easier.', 'idioms'), contains("keep one's chin up"));
    expect(found('No sooner had we left than the alarm sounded.', 'conjunctions'), contains('no sooner sth than'));
    expect(found('I apologized to my neighbor for the noise.', 'dependent_prepositions'), contains('apologize to someone for'));
    expect(found('We stopped at a petrol station in England.', 'uk_us'), contains('petrol station'));
    expect(found('What is more, it is close to the station.', 'discourse_markers'), contains('what is more'));
    // Sheets 7-10: collocations, a possessive slot, a UK word.
    expect(found('The bright poster caught my attention.', 'collocations'), contains("catch one's attention"));
    expect(found('We placed an order for new filters.', 'collocations'), contains('place an order'));
    expect(found('We grilled aubergine with olive oil.', 'uk_us'), contains('aubergine'));
    // Sheet 13: an adjective + noun found after any determiner, an adverb + adjective.
    expect(found('She gave him her faint smile.', 'collocations'), contains('faint smile'));
    expect(found('I was utterly exhausted after the trip.', 'collocations'), contains('utterly exhausted'));
    // Audit 14: a phrase that is matched in ordinary sentences with another meaning is gone.
    expect(found('He looked at the money.', 'prepositional_phrases'), isNot(contains('at the money')));
    expect(found('The shelf was well out of reach.', 'phrasal_verbs'), isNot(contains('well out')));
    expect(found('Let me have a go at it first.', 'idioms'), contains('have a go at it'));
    // Audit 15: "get the best of" with its "of", so "the best price" is not it.
    expect(found("Don't let your fear get the best of you.", 'idioms'), contains('get the best of'));
    expect(found('We got the best price in town.', 'idioms'), isNot(contains('get the best of')));
    expect(found('The guard gave the visitor the once over.', 'idioms'), contains('give sb the once over'));
  });
}
