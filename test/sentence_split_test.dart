// Sentence boundaries: abbreviations, initials, references and numbers must
// not cut a sentence in two. The reader, the sentence panel, the saved
// translations, grammar marks and reading aloud all use these boundaries.
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/nlp/text.dart';

List<String> split(String text) => [for (final r in sentenceRanges(text)) text.substring(r.$1, r.$2).trim()];

void main() {
  group('the reported paragraphs (English Fairy Tales, notes)', () {
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

    test('"No. 28" stays inside its sentence (error A)', () {
      final s = split(singingBone);
      expect(s, contains(startsWith('--The story is clearly that of Grimm\'s "Singing Bone" (No. 28), where one brother slays the other and buries him under a bush.')));
      expect(s.where((x) => x.startsWith('28)')), isEmpty);
    });

    test('"Prof." and "ed. 1886), i. 125 … iii. 499" stay in one sentence (error B)', () {
      final s = split(singingBone);
      expect(s.last, "For numerous variants in Ballads and Folk Tales, see Prof. Child's English and Scotch Ballads (ed. 1886), i. 125, 493; iii. 499.");
      expect(s, hasLength(4));
    });

    test('"Mr. E. S. Hartland … p. 35, seq." is one sentence and the rest are whole (errors C, D)', () {
      final s = split(beanstalk);
      expect(s, [
        'Parallels.',
        '--There is a chap-book version which is very poor; it is given by Mr. E. S. Hartland, English Folk and Fairy Tales (Camelot Series), p. 35, seq.',
        "In this, when Jack arrives at the top of the Beanstalk, he is met by a fairy, who gravely informs him that the ogre had stolen all his possessions from Jack's father.",
        'The object of this was to prevent the tale becoming an encouragement to theft!',
        'I have had greater confidence in my young friends, and have deleted the fairy who did not exist in the tale as told to me.',
        'For the Beanstalk elsewhere, see Ralston, Russian Folk Tales, 293-8.',
        'Cosquin has some remarks on magical ascents (i. 14).',
      ]);
    });
  });

  group('abbreviations and references', () {
    final oneSentence = <String>[
      'Mr. Smith met Mrs. Jones and Dr. Brown at St. Paul\'s.',
      'It is Grimm\'s Kluge Else, No. 34, and is spread through the world.',
      'See Folk-Lore Journal, vii. 138-43, for the full text.',
      'The rhyme is given in Halliwell, p. 16, and pp. 20-24.',
      'He quotes Cosquin, Contes pop. de Lorraine, i. 269 seq.',
      'Melusine, t. ii. is cited in the notes.',
      'Prof. Stephens gave a variant from his own memory.',
      'The price rose to 3.5 dollars in the U.S. last year.',
      'Use a fruit, e.g. an apple, i.e. something sweet.',
      'See Vol. 2, ch. 3 and Fig. 4 for details.',
      'Gen. Grant and Capt. Smith rode out with Lt. Hale.',
      'The painting by J. M. W. Turner hangs here.',
      'Mrs. E. Burne-Jones told it from memory.',
      'cf. Jacobs, Celtic Fairy Tales, no. 5.',
      'The words were these… and then he stopped.',
    ];
    for (final s in oneSentence) {
      test('one sentence: $s', () => expect(split(s), [s]));
    }
  });

  group('real sentence ends are still found', () {
    final cases = <String, List<String>>{
      'He came home. She was asleep.': ['He came home.', 'She was asleep.'],
      'So did I. Then we left.': ['So did I.', 'Then we left.'],
      'Where are you? I am here!': ['Where are you?', 'I am here!'],
      '"Run!" she cried. "Now!"': ['"Run!"', 'she cried.', '"Now!"'],
      "'Well!' thought Alice to herself. 'What a fall!'": ["'Well!'", 'thought Alice to herself.', "'What a fall!'"],
      'It was 35, seq. In this tale the giant wins.': ['It was 35, seq.', 'In this tale the giant wins.'],
      'They bought apples, pears, etc. Then they went home.': ['They bought apples, pears, etc.', 'Then they went home.'],
      'He said no. Then he left.': ['He said no.', 'Then he left.'],
      'Wait... Who is there?': ['Wait...', 'Who is there?'],
      'The end': ['The end'],
      'It went up (see p. 4). After that it fell.': ['It went up (see p. 4).', 'After that it fell.'],
    };
    cases.forEach((text, want) {
      test(text, () => expect(split(text), want));
    });
  });

  test('ranges cover the text in order without gaps or overlaps', () {
    const t = 'One. Mr. Two went (No. 3) home! "Three?" Four… five';
    final r = sentenceRanges(t);
    expect(r.first.$1, 0);
    expect(r.last.$2, t.length);
    for (var i = 1; i < r.length; i++) {
      expect(r[i].$1, r[i - 1].$2);
    }
  });

  test('empty and blank text give one range', () {
    expect(sentenceRanges(''), [(0, 0)]);
    expect(sentenceRanges('   '), [(0, 3)]);
  });
}
