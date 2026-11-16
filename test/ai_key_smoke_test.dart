// Asks a real AI service through the app's own code: the "Yapay zekâya sor"
// path (AiService.chat via KeyAi and Tutor.discuss). Runs only with
// AI_TEST_PROVIDER and AI_TEST_KEY set (the ai-key-smoke workflow).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/ai/key_ai.dart';
import 'package:kelime_okur/ai/tutor.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/online/ai_service.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final provider = Platform.environment['AI_TEST_PROVIDER'];
  final key = Platform.environment['AI_TEST_KEY'];
  final skip = provider == null || key == null || key.isEmpty ? 'set AI_TEST_PROVIDER and AI_TEST_KEY' : false;

  test('Yapay zekâya sor answers with a real key', () async {
    final d = DictDb();
    d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    final u = UserDb.open(Directory.systemTemp.createTempSync('vb_key'));
    u.setSetting('ai_provider', provider);
    u.setSetting('ai_key_$provider', key);
    final app = AppState(d, u)..localAi = KeyAi(u);
    // The service itself first, with its own error text and timing, on a
    // few models: the first one that answers is used for the rest.
    String? works;
    for (final m in ['gemini-flash-latest', 'gemini-flash-lite-latest', 'gemini-2.5-flash']) {
      u.setSetting('ai_model_$provider', m);
      final sw = Stopwatch()..start();
      try {
        final r = await AiService.fromSettings(u)!.chat('Kısa cevap ver.', [('user', '"apple" Türkçede ne demek?')], maxTokens: 1200);
        print('RAW $m in ${sw.elapsed.inMilliseconds} ms: $r');
        works ??= m;
      } catch (e) {
        print('RAW $m ERROR after ${sw.elapsed.inMilliseconds} ms: $e');
      }
    }
    expect(works, isNotNull);
    u.setSetting('ai_model_$provider', works);
    final tutor = Tutor.of(app);
    final about = 'Boşluk doldurma: "We ___ (not / like) horror films."\nDoğru cevaplar:\n- "don\'t like"\n- "do not like"\n'
        'Öğrencinin cevabı: "dont like"\nSonuç: yanlış';
    final history = <(String, String)>[('user', 'Neden yanlış?')];
    final a1 = await tutor.discuss(about, history).join();
    print('ANSWER 1:\n$a1\n-----');
    expect(a1.trim(), isNotEmpty);
    history
      ..add(('assistant', a1))
      ..add(('user', 'Bir örnek daha ver'));
    final a2 = await tutor.discuss(about, history).join();
    print('ANSWER 2:\n$a2\n-----');
    expect(a2.trim(), isNotEmpty);
    final w = await tutor.wordMeaning('pedicab', sentence: 'We took a pedicab to the market.').join();
    print('WORD:\n$w\n-----');
    expect(w.trim(), isNotEmpty);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 12)));
}
