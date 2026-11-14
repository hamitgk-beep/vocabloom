// Writes the tutor prompts exactly as the app builds them, so the training
// data matches what the model sees on the phone.
//
//   flutter test tools/tutor/export_prompts_test.dart
//
// Input:  tools/tutor/data/sentences.tsv   (en \t tr, from build_sft.py --sentences)
//         tools/tutor/data/learner_texts.tsv (id \t text, from errors.py)
// Output: tools/tutor/data/prompts.jsonl  {"id","task","system","user"}
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/ai/grammar_practice.dart';
import 'package:kelime_okur/ai/local_ai.dart';
import 'package:kelime_okur/ai/packages.dart';
import 'package:kelime_okur/ai/tutor.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:sqlite3/sqlite3.dart';

class _Capture extends LocalAi {
  String system = '';
  List<(String, String)> messages = const [];
  @override
  List<AiPackage> get packages => aiPackages;
  @override
  Future<Set<String>> installed() async => {};
  @override
  Map<String, AiDownload> get downloads => {};
  @override
  Stream<AiDownload> download(String id) => const Stream.empty();
  @override
  Future<void> cancel(String id) async {}
  @override
  Future<void> delete(String id) async {}
  @override
  String? get activeId => null;
  @override
  Future<void> setActive(String id) async {}
  @override
  bool get premiumUnlocked => true;
  @override
  Future<int?> deviceRamMb() async => null;
  @override
  bool get loaded => true;
  @override
  Stream<String> generate(String system, List<(String, String)> messages,
      {int maxTokens = 512, double temperature = 0.3}) {
    this.system = system;
    this.messages = messages;
    return const Stream.empty();
  }

  @override
  void stop() {}
  @override
  Future<void> unload() async {}
}

void main() {
  test('export tutor prompts', () async {
    final d = DictDb();
    d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    final app = AppState(d, UserDb.open(Directory.systemTemp.createTempSync('vb_export')));
    final cap = _Capture();
    app.localAi = cap;
    final tutor = Tutor.of(app);
    final out = File('tools/tutor/data/prompts.jsonl').openWrite();
    var n = 0;
    void write(String id, String task) {
      out.writeln(jsonEncode({'id': id, 'task': task, 'system': cap.system, 'user': cap.messages.last.$2}));
      n++;
    }

    final sentences = File('tools/tutor/data/sentences.tsv');
    if (sentences.existsSync()) {
      var i = 0;
      for (final line in sentences.readAsLinesSync()) {
        final en = line.split('\t').first.trim();
        if (en.isEmpty) continue;
        await tutor.explainSentence(en).drain<void>();
        write('explain-${i++}', 'explain');
      }
    }
    // Hand-written gold explanations (seed_explain.jsonl) get their prompts too.
    final seeds = File('tools/tutor/data/seed_explain.jsonl');
    if (seeds.existsSync()) {
      for (final line in seeds.readAsLinesSync().where((l) => l.trim().isNotEmpty)) {
        final j = jsonDecode(line) as Map<String, dynamic>;
        await tutor.explainSentence(j['sentence'] as String).drain<void>();
        write(j['id'] as String, 'explain');
      }
    }
    final texts = File('tools/tutor/data/learner_texts.tsv');
    if (texts.existsSync()) {
      for (final line in texts.readAsLinesSync()) {
        final parts = line.split('\t');
        if (parts.length < 2) continue;
        await tutor.correct(parts[1]).drain<void>();
        write(parts[0], 'correct');
      }
    }
    // Grammar practice: the system prompt; teacher.py builds the user turns the
    // same way Tutor.checkTranslation does.
    final topics = parseGrammarTopics(File('assets/grammar/lessons.json').readAsStringSync());
    final t = topics.first;
    await tutor.checkTranslation(t, t.exercises.first, 'xx').drain<void>();
    out.writeln(jsonEncode({'id': 'grade-system', 'task': 'grade', 'system': cap.system, 'user': cap.messages.last.$2}));
    n++;
    for (final level in ['A2', 'B1', 'B2']) {
      await tutor.chatReply(const [], level: level).drain<void>();
      out.writeln(jsonEncode({'id': 'chat-system-$level', 'task': 'chat', 'system': cap.system, 'user': ''}));
      n++;
    }
    await out.close();
    // ignore: avoid_print
    print('prompts: $n');
  }, timeout: const Timeout(Duration(hours: 1)));
}
