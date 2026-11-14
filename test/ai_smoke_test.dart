// Runs the real model when AI_MODEL_DIR points to a folder with <package>.gguf
// files (CI: .github/workflows/ai-smoke.yml). Skipped otherwise.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/ai/local_engine.dart';
import 'package:kelime_okur/ai/tutor.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  final modelDir = Platform.environment['AI_MODEL_DIR'];
  // "lite,plus" or "label=package,…": label.gguf is run with that package's settings
  // (used to compare candidate models, e.g. "gemma1b=lite").
  final runs = [
    for (final x in (Platform.environment['AI_PACKAGES'] ?? 'lite').split(','))
      if (x.trim().isNotEmpty) (x.split('=').first.trim(), x.split('=').last.trim())
  ];

  test('tutor answers with the downloaded models', () async {
    final d = DictDb();
    d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    for (final (label, id) in runs) {
      final src = File(p.join(modelDir!, '$label.gguf'));
      if (!src.existsSync()) continue;
      final appDir = Directory.systemTemp.createTempSync('vb_smoke');
      Directory(p.join(appDir.path, 'ai_models')).createSync();
      final u = UserDb.open(appDir);
      u.setSetting('ai_premium', '1');
      final app = AppState(d, u);
      final ai = LlamaLocalAi(u, appDir);
      app.localAi = ai;
      final tutor = Tutor.of(app);
      Link(p.join(appDir.path, 'ai_models', '$id.gguf')).createSync(src.path);
      await ai.setActive(id);
      Future<void> run(String title, Stream<String> s) async {
        final sw = Stopwatch()..start();
        final text = await s.join();
        // ignore: avoid_print
        print('\n===== [$label] $title (${sw.elapsedMilliseconds} ms, ${text.length} chars)\n$text');
        expect(text.trim(), isNotEmpty);
        expect(text, isNot(contains('<think>')));
      }

      await run('explain', tutor.explainSentence('She has given up smoking because it was bad for her health.'));
      await run('explain 2', tutor.explainSentence('If I had known you were coming, I would have baked a cake.'));
      await run('correct', tutor.correct('Yesterday I have went to the cinema with my friends and we watched a very boring film.'));
      await run('correct ok', tutor.correct('I have been living in Izmir since 2018.'));
      await run('correct turkish', tutor.correct('Yarın hava güzel olursa pikniğe gideceğiz.'));
      await run('chat open', tutor.chatReply(const [], level: 'B1', topic: 'weekend plans'));
      await run('chat', tutor.chatReply(const [
        ('assistant', 'Hi! Do you have any plans for the weekend?'),
        ('user', 'Yes, I will go to my grandmother house and we will cooking together.'),
      ], level: 'A2'));
      await ai.unload();
    }
  }, skip: modelDir == null ? 'AI_MODEL_DIR not set' : false, timeout: const Timeout(Duration(minutes: 40)));
}
