import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/tts/read_aloud.dart';

void main() {
  test('long sentences are read in clauses', () {
    const t = 'Although it was raining heavily all morning, she decided to walk to the old library, because she wanted to finish the book before dinner.';
    final parts = speechChunks(t, 0, t.length).map((r) => t.substring(r.$1, r.$2).trim()).toList();
    expect(parts, ['Although it was raining heavily all morning,', 'she decided to walk to the old library,', 'because she wanted to finish the book before dinner.']);
    const short = 'He came, he saw.';
    expect(speechChunks(short, 0, short.length), [(0, short.length)]);
  });
}
