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
    // few models: time to the first words (streaming) and to the end.
    String? works;
    for (final m in [null, 'gemini-flash-latest', 'gemini-2.5-flash']) {
      // null: the app's default model.
      u.setSetting('ai_model_$provider', m);
      final svc = AiService(AiConfig(providerById[provider]!, key!, m ?? providerById[provider]!.defaultModel, ''));
      final sw = Stopwatch()..start();
      int? firstMs;
      try {
        final buf = StringBuffer();
        await for (final p in svc.chatStream('Kısa cevap ver.', [('user', '"apple" Türkçede ne demek? Bir örnek cümle ver.')], maxTokens: 1200)) {
          firstMs ??= sw.elapsedMilliseconds;
          buf.write(p);
        }
        print('STREAM $m first words ${firstMs}ms, done ${sw.elapsedMilliseconds}ms: $buf');
        if (buf.toString().trim().isNotEmpty) works ??= m ?? 'default';
      } catch (e) {
        print('STREAM $m ERROR after ${sw.elapsed.inMilliseconds} ms: $e');
      }
    }
    expect(works, 'default', reason: 'the default model must answer');
    u.setSetting('ai_model_$provider', null);
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
    for (final m in [null, 'gemini-flash-latest']) {
      u.setSetting('ai_model_$provider', m);
      final sw = Stopwatch()..start();
      int? firstMs;
      final buf = StringBuffer();
      await for (final p in tutor.discuss('Kelime: "pedicab"\nCümle: "We took a pedicab to the market."', [('user', 'Bu kelimeyi detaylı anlat')])) {
        firstMs ??= sw.elapsedMilliseconds;
        buf.write(p);
      }
      print('ASK $m first words ${firstMs}ms, done ${sw.elapsedMilliseconds}ms:\n$buf\n-----');
      expect(firstMs, lessThan(15000), reason: 'the first words must show quickly');
    }
    u.setSetting('ai_model_$provider', null);
    final w = await tutor.wordMeaning('pedicab', sentence: 'We took a pedicab to the market.').join();
    print('WORD:\n$w\n-----');
    expect(w.trim(), isNotEmpty);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 12)));
}
