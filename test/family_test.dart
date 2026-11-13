import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/nlp/word_family.dart';

void main() {
  test('family members come from their closest real base', () {
    const fam = ['differ', 'different', 'differently', 'difference', 'differential', 'differentiate', 'differentiator', 'differentiation'];
    expect(derive(fam, 'differentiate', 'v'), ('different', 'ate'));
    expect(derive(fam, 'differential', 'n'), ('different', 'al'));
    expect(derive(fam, 'differential', 'a'), ('different', 'al'));
    expect(derive(fam, 'differentiation', 'n'), ('differentiate', 'ion'));
    expect(derive(fam, 'differentiator', 'n'), ('differentiate', 'or'));
    expect(derive(fam, 'difference', 'n'), ('differ', 'ence'));
    expect(derive(fam, 'differently', 'r'), ('different', 'ly'));
    expect(derive(['work', 'worker', 'workable'], 'workable', 'a'), ('work', 'able'));
    expect(derive(['happy', 'happiness'], 'happiness', 'n'), ('happy', 'ness'));
    expect(derive(['create', 'creation', 'creative', 'creatively'], 'creatively', 'r'), ('creative', 'ly'));
    expect(derive(['create', 'creation'], 'creation', 'n'), ('create', 'ion'));
  });
  test('rough Turkish for members the dictionary lacks', () {
    expect(derivedTr('ayırdetmek', 'or', 'n'), '≈ ayırdeten kişi ya da şey');
    expect(derivedTr('ayırdetmek', 'ion', 'n'), '≈ ayırdetme');
  });
}
