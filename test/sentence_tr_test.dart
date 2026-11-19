import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/ui/word_sheet.dart';

void main() {
  test('a saved Turkish that belongs to another, longer sentence is not shown', () {
    const en = "'Well!' thought Alice to herself, 'after such a fall as this, I shall think nothing of tumbling down stairs!";
    const wrong = "'Dünyanın merkezine yaklaşmış olmalıyım herhalde. Bakalım: Bu yaklaşık dört bin mil aşağıda olur diye "
        "düşünüyorum--' (çünkü, gördüğünüz gibi, Alice okulda derslerken bu tür birkaç şey öğrenmişti ve her ne kadar bu, "
        "dinleyicisi kimse olmadığı için bilgisini göstermek için ÇOK iyi bir fırsat olmasa da, bunu içinden tekrarlamak "
        "yine de iyi bir pratikti) '--evet, bu doğru mesafeye yakın--ama o zaman acaba hangi Enlem veya Boylama ulaştım?'";
    const right = "'Vay!' diye düşündü Alice, 'böyle bir düşüşten sonra merdivenden yuvarlanmak bana hiç gelmez artık!'";
    expect(plausibleTranslation(en, wrong), isFalse);
    expect(plausibleTranslation(en, right), isTrue);
    expect(plausibleTranslation('Hi.', 'Merhaba, nasılsın?'), isTrue);
    expect(plausibleTranslation(en, ''), isFalse);
  });
}
