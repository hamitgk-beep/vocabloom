// Task 5E: the experimental part-of-speech tagger is off by default, never breaks the
// sense engine, and when it is on its tag decides the part of speech without making
// the meaning "sure" on its own. The tagger here is a tiny hand-made one, so the test
// needs no model file.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/nlp/context_sense.dart';
import 'package:kelime_okur/nlp/pos_tagger.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:sqlite3/sqlite3.dart';

/// Tags every word with [tags][word], NOUN otherwise.
class _FixedTagger extends PosTagger {
  final Map<String, String> tags;
  _FixedTagger(this.tags) : super(const {}, const {}, const ['NOUN']);
  @override
  List<String> tag(List<String> words) => [for (final w in words) tags[w.toLowerCase()] ?? 'NOUN'];
}

class _BrokenTagger extends PosTagger {
  _BrokenTagger() : super(const {}, const {}, const ['NOUN']);
  @override
  List<String> tag(List<String> words) => throw StateError('broken');
}

void main() {
  group('PosTagger', () {
    test('a missing or unreadable file gives no tagger', () {
      expect(PosTagger.load('/nonexistent/tagger.json.gz'), isNull);
      final f = File('${Directory.systemTemp.createTempSync().path}/bad.json.gz')..writeAsStringSync('not gzip');
      expect(PosTagger.load(f.path), isNull);
    });

    test('weights decide, the tag dictionary wins, ties go to the last label', () {
      final dir = Directory.systemTemp.createTempSync();
      final f = File('${dir.path}/t.json.gz')
        ..writeAsBytesSync(gzip.encode(utf8.encode(jsonEncode({
          'weights': {
            'i-1 word the': {'NOUN': 2.0, 'VERB': -1.0},
            'i-1 word we': {'VERB': 2.0},
            'bias': {'ADJ': 0.5},
          },
          'tagdict': {'the': 'DET', 'we': 'PRON'},
          'classes': ['ADJ', 'NOUN', 'VERB', 'DET', 'PRON'],
        }))));
      final t = PosTagger.load(f.path)!;
      expect(t.tag(['the', 'watch']), ['DET', 'NOUN']);
      expect(t.tag(['we', 'watch']), ['PRON', 'VERB']);
      expect(t.tag(['watch']), ['ADJ']); // only the bias
      final toks = tokenize('we watch');
      expect(t.posAt(toks, 1), 'v');
      expect(t.posAt(toks, 0), isNull); // PRON is none of n, v, a, r
    });
  });

  group('SenseEngine with a tagger', () {
    final d = DictDb()..db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();

    ContextSense at(SenseEngine e, String sentence, String word) {
      final toks = tokenize(sentence);
      final i = toks.indexWhere((t) => t.lower == word);
      return e.resolve(SenseQuery(sentence: sentence, tokens: toks, index: i));
    }

    test('off by default: the engine has no tagger', () {
      expect(SenseEngine(d).tagger, isNull);
    });

    test('the tag decides the part of speech', () {
      final verb = SenseEngine(d, tagger: _FixedTagger({'watch': 'VERB'}));
      final noun = SenseEngine(d, tagger: _FixedTagger({'watch': 'NOUN'}));
      const s = 'They watch the old clock.';
      expect(at(verb, s, 'watch').best?.pos, 'v');
      expect(at(noun, s, 'watch').best?.pos, 'n');
    });

    test('a tag that is not one of the word\'s parts of speech is ignored', () {
      final e = SenseEngine(d, tagger: _FixedTagger({'watch': 'ADP'}));
      final plain = SenseEngine(d);
      const s = 'He looked at his watch and left.';
      expect(at(e, s, 'watch').best?.id, at(plain, s, 'watch').best?.id);
    });

    test('a broken tagger never breaks the engine: the rules decide', () {
      final e = SenseEngine(d, tagger: _BrokenTagger());
      final plain = SenseEngine(d);
      const s = 'We watch the news every evening.';
      final c = at(e, s, 'watch'), p = at(plain, s, 'watch');
      expect(c.best?.id, p.best?.id);
      expect(c.confidence, p.confidence);
    });

    test('the tagger alone is no proof: it never makes a meaning sure that the rules left likely', () {
      // "the tagger" is a weak rule: across many sentences, no row turns sure only because a tagger agrees.
      const sentences = [
        ('She works hard every day.', 'hard'),
        ('He drives too fast.', 'fast'),
        ('The bank raised its interest rates again.', 'bank'),
        ('He looked at his watch and left.', 'watch'),
      ];
      for (final (s, w) in sentences) {
        final plain = at(SenseEngine(d), s, w);
        final tagged = at(SenseEngine(d, tagger: _FixedTagger({})), s, w);
        if (plain.confidence != SenseConfidence.sure && tagged.best?.pos == plain.best?.pos) {
          expect(tagged.confidence, isNot(SenseConfidence.sure), reason: '$s: ${tagged.reason}');
        }
      }
    });
  });
}
