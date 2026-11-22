// Licence texts of the dictionary data (Task 5D, docs/lexicon_remediation/
// LICENSE_TEXT_CORRECTIONS.md): no unverified licence is claimed, the
// reversed Turkish → English meanings are not called FreeDict, and the full
// Princeton WordNet notice reaches the licence page.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/dictionary_sources.dart';
import 'package:kelime_okur/l10n.dart';

void main() {
  tearDown(() => uiEnglish = false);

  for (final english in [false, true]) {
    final lang = english ? 'English' : 'Turkish';

    group('dictionary sources ($lang)', () {
      setUp(() => uiEnglish = english);

      test('damdafayton is never shown with MIT or any other licence', () {
        final lines = dictionarySourceLines().where((l) => l.contains('damdafayton')).toList();
        expect(lines, hasLength(1));
        final l = lines.single;
        expect(l, isNot(contains('MIT')));
        for (final lic in ['CC BY', 'GPL', 'Apache', 'BSD', 'public domain', 'kamu malı']) {
          expect(l, isNot(contains(lic)), reason: lic);
        }
        expect(l, contains(english ? 'could not be verified' : 'doğrulanamadı'));
      });

      test('the database as a whole is not called CC BY-SA', () {
        final all = dictionarySourceLines().join('\n');
        expect(all, isNot(contains(english ? 'shared under the same licence' : 'aynı lisansla')));
        final bundle = dictionarySourceLines().last;
        expect(bundle, contains(english ? 'no licence is stated' : 'bir lisans beyan edilmez'));
      });

      test('the Kindle compilation itself is not called CC BY-SA', () {
        final l = dictionarySourceLines().firstWhere((l) => l.contains('Kindle'));
        expect(l, contains('GPL-2.0+'));
        expect(l, contains(english ? 'Wiktionary part' : 'Wiktionary bölümünden'));
      });

      test('FrequencyWords carries no licence name', () {
        final l = dictionarySourceLines().firstWhere((l) => l.contains('FrequencyWords'));
        final part = l.substring(l.indexOf('FrequencyWords'), l.indexOf(';', l.indexOf('FrequencyWords')));
        expect(part, isNot(contains('CC BY-SA')));
        expect(part, contains(english ? 'not verified' : 'doğrulanamadı'));
      });

      test('FreeDict is GPL and marked as not CC BY-SA', () {
        final l = dictionarySourceLines().firstWhere((l) => l.contains('FreeDict'));
        expect(l, contains('GPL-2.0+'));
        expect(l, contains(english ? 'not under CC BY-SA' : 'CC BY-SA altında değildir'));
      });

      test('AI drafts and Tatoeba authors are disclosed', () {
        final all = dictionarySourceLines().join('\n');
        expect(all, contains(english ? 'drafted with AI' : 'yapay zekâ ile hazırlandı'));
        expect(all, contains(english ? 'Sentence authors are not shown yet' : 'Cümle yazarları henüz gösterilmiyor'));
      });

      test('"fd" and "rv" meanings are not labelled FreeDict', () {
        for (final tag in ['fd', 'rv']) {
          final label = trSenseSourceLabel(tag)!;
          expect(label, isNot(contains('FreeDict')), reason: tag);
          expect(label, contains(english ? 'reversed' : 'tersi'), reason: tag);
        }
        expect(trSenseSourceLabel(null), isNull);
        expect(trSenseSourceLabel('wn'), contains('KeNet'));
        expect(trSenseSourceLabel('st'), contains('Storilex'));
        // An unknown tag never gets a made-up source.
        expect(trSenseSourceLabel('xx'), english ? 'Source: not stated' : 'Kaynak: belirtilmemiş');
      });
    });
  }

  test('the full Princeton WordNet notice is registered for the licence page', () async {
    registerDataLicences();
    registerDataLicences(); // once only
    final entries = await LicenseRegistry.licenses.toList();
    final wordnet = entries.where((e) => e.packages.contains('Princeton WordNet 3.0')).toList();
    expect(wordnet, hasLength(1));
    final text = wordnet.single.paragraphs.map((p) => p.text).join('\n');
    expect(text, contains('WordNet 3.0 Copyright 2006 by Princeton University. All rights reserved.'));
    expect(text, contains('THIS SOFTWARE AND DATABASE IS PROVIDED "AS IS"'));
    expect(text, contains('The name of Princeton University or Princeton may not be used in advertising'));
    for (final name in ['KeNet Turkish WordNet', 'Collaborative Interlingual Index', 'Wiktionary', 'Tatoeba']) {
      expect(entries.where((e) => e.packages.contains(name)), hasLength(1), reason: name);
    }
    // No notice is registered for a source whose licence is not verified.
    expect(entries.where((e) => e.packages.any((p) => p.contains('damdafayton'))), isEmpty);
  });

  test('the screens use the shared texts, not their own copies', () {
    final settings = File('lib/ui/settings_page.dart').readAsStringSync();
    expect(settings, contains('dictionarySourceLines()'));
    expect(settings, contains('registerDataLicences()'));
    expect(settings, isNot(contains('damdafayton')));
    expect(settings, isNot(contains('aynı lisansla (CC BY-SA 4.0)')));
    final sheet = File('lib/ui/tr_word_sheet.dart').readAsStringSync();
    expect(sheet, contains('trSenseSourceLabel('));
    expect(sheet, isNot(contains('Kaynak: FreeDict')));
  });
}
