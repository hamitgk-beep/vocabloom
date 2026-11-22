import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/nlp/tr_suffixes.dart';

String split(String w, String l) => trPieces(w, l)?.map((p) => p.text).join('-') ?? '-';

void main() {
  test('verbs', () {
    expect(split('sürmüştür', 'sürmek'), 'sür-müş-tür');
    expect(split('gelmiştim', 'gelmek'), 'gel-miş-ti-m');
    expect(split('geliyor', 'gelmek'), 'gel-iyor');
    expect(split('yapamadım', 'yapmak'), 'yap-ama-dı-m');
    expect(split('okuyacağız', 'okumak'), 'oku-yacağ-ız');
  });

  test('nouns', () {
    expect(split('evlerimizden', 'ev'), 'ev-ler-imiz-den');
    expect(split('kitabı', 'kitap'), 'kitab-ı');
    expect(split('İstanbul\'da', 'istanbul'), 'İstanbul-da');
    expect(split('evdekiler', 'ev'), 'ev-de-ki-ler');
  });

  test('participles take noun endings', () {
    expect(split('yaptığını', 'yapmak'), 'yap-tığ-ı-nı');
  });

  test('the base word itself has no pieces', () {
    expect(trPieces('ev', 'ev'), isNull);
  });
}
