import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/import/ocr.dart';

/// Runs the platform's offline OCR on a sample image. On CI this runs on the
/// Windows runner to check the Windows.Media.Ocr PowerShell script.
void main() {
  test('offline OCR reads a sample image', () async {
    final ocr = await OcrEngine.best();
    if (ocr == null) {
      markTestSkipped('no offline OCR on this machine');
      return;
    }
    final png = File('test/fixtures/ocr_sample.png').readAsBytesSync();
    final text = (await ocr.recognize(png)).toLowerCase();
    // ignore: avoid_print
    print('${ocr.name}: $text');
    expect(text, contains('quick brown fox'));
    expect(text, contains('lazy dog'));
    expect(text, isNot(contains('Ã')), reason: 'OCR output must be decoded as UTF-8');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
