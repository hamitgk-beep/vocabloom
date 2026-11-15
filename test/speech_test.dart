import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/tts/speech.dart';
import 'package:kelime_okur/tts/voices.dart';

/// Downloads the voice packs from VOCABLOOM_VOICE_BASE (a folder URL holding
/// the zips), unpacks them and synthesizes English and Turkish speech.
/// Skipped unless the variable is set (the packs are ~450 MB).
void main() {
  final base = Platform.environment['VOCABLOOM_VOICE_BASE'];
  test('voice packs download + offline synthesis', () async {
    final dir = Directory.systemTemp.createTempSync('voice');
    final s = Speech.instance..init(dir, UserDb.open(dir));
    for (final pk in voicePacks) {
      expect(s.isReady(pk), isFalse);
      await s.download(pk, url: '$base/${pk.id}.zip');
      expect(s.stateOf(pk), PackState.ready, reason: s.errorOf(pk));
    }
    final cases = {
      voices.first: ['and', 'grow', 'Hermione', 'Although it was raining heavily all morning, she decided to walk to the old library.'],
      voiceById['k_bm_george']!: ['though', 'It was the best of times, it was the worst of times.'],
      lightVoices.first: ['and', 'It was the best of times, it was the worst of times.'],
      voiceById['tr_ema']!: ['rağmen', 'Öğrenmek için her gün biraz okumalısın.', 'Saat 3\'te 25 kişi geldi'],
      voiceById['tr_fahrettin']!: ['rağmen'],
    };
    await s.warmUp();
    for (final e in cases.entries) {
      for (final text in e.value) {
        final sw = Stopwatch()..start();
        final path = await s.synth(text, v: e.key);
        final bytes = File(path).lengthSync();
        // 16-bit mono at 22-24 kHz: at least ~0.3 s of audio
        expect(bytes, greaterThan(13000), reason: '${e.key.id} "$text"');
        // ignore: avoid_print
        print('${e.key.id} "$text": ${sw.elapsedMilliseconds} ms, $bytes bytes');
        File(path).deleteSync();
      }
    }
  }, skip: base == null ? 'set VOCABLOOM_VOICE_BASE' : false, timeout: const Timeout(Duration(minutes: 10)));
}
