// Runs the offline AI the way the app does on a phone: downloads the
// package, loads it with llama.cpp and asks a question. Run on an Android
// emulator by .github/workflows/android-ai.yml; the answers are in the log.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kelime_okur/ai/local_engine.dart';
import 'package:kelime_okur/ai/packages.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('the AI package downloads, loads and answers on Android', () async {
    final dir = await getApplicationSupportDirectory();
    final user = UserDb.open(dir);
    final ai = LlamaLocalAi(user, dir);
    final id = aiPackages.first.id;
    print('AI device RAM: ${await ai.deviceRamMb()} MB, cpus: ${Platform.numberOfProcessors}');

    final sw = Stopwatch()..start();
    var shown = -1;
    await for (final d in ai.download(id)) {
      final pct = ((d.fraction ?? 0) * 10).floor();
      if (pct != shown) {
        shown = pct;
        print('AI download ${pct * 10}% (${d.received ~/ 1000000} MB)');
      }
    }
    print('AI downloaded in ${sw.elapsed.inSeconds} s; installed: ${await ai.installed()}');
    await ai.setActive(id);

    for (final q in [
      'Kelime: energy\nOkuduğu cümle: "Today the city is bursting with energy."\n\nBu kelimeyi açıkla.',
      'Bana "supposed to" ile iki örnek cümle ver.',
    ]) {
      sw.reset();
      final out = StringBuffer();
      try {
        await for (final c in ai.generate('Sen Türk öğrencilere İngilizce öğreten bir öğretmensin. Kısa ve Türkçe cevap ver.', [('user', q)],
            maxTokens: 160)) {
          if (out.isEmpty) print('AI first words after ${sw.elapsed.inMilliseconds} ms (loaded: ${ai.loaded})');
          out.write(c);
        }
      } catch (e, st) {
        print('AI ERROR ${e.runtimeType}: $e\n$st');
        rethrow;
      }
      print('AI answer in ${sw.elapsed.inMilliseconds} ms:\n$out\n-----');
      expect(out.toString().trim(), isNotEmpty);
    }
    // Two questions at once, as when the word panel's meaning is still being
    // written and the learner taps a question: both must be answered.
    sw.reset();
    final both = await Future.wait([
      ai.generate('Kısa cevap ver.', [('user', '"apple" Türkçede ne demek?')], maxTokens: 40).join(),
      ai.generate('Kısa cevap ver.', [('user', '"book" Türkçede ne demek?')], maxTokens: 40).join(),
    ]);
    print('AI two at once in ${sw.elapsed.inMilliseconds} ms:\n${both.join('\n---\n')}\n-----');
    expect(both.every((a) => a.trim().isNotEmpty), isTrue);
    await ai.unload();
  }, timeout: const Timeout(Duration(minutes: 50)));
}
