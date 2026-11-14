import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/ai/local_ai.dart';
import 'package:kelime_okur/ai/local_engine.dart';
import 'package:kelime_okur/ai/packages.dart';
import 'package:kelime_okur/ai/tutor.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:sqlite3/sqlite3.dart';

/// Records the prompts instead of running a model.
class _EchoAi extends LocalAi {
  String? lastSystem;
  List<(String, String)>? lastMessages;
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
  String? get activeId => 'pro';
  @override
  Future<void> setActive(String id) async {}
  @override
  bool get premiumUnlocked => false;
  @override
  Future<int?> deviceRamMb() async => null;
  @override
  bool get loaded => true;
  @override
  Stream<String> generate(String system, List<(String, String)> messages,
      {int maxTokens = 512, double temperature = 0.3}) {
    lastSystem = system;
    lastMessages = messages;
    return Stream.fromIterable(['ok']);
  }

  @override
  void stop() {}
  @override
  Future<void> unload() async {}
}

void main() {
  final d = DictDb();
  d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
  d.load();
  final dir = Directory.systemTemp.createTempSync('vb_ai');
  final u = UserDb.open(dir);
  final app = AppState(d, u);
  final ai = _EchoAi();
  app.localAi = ai;
  final tutor = Tutor.of(app);

  test('one premium package, size as shown, commercial licence', () {
    expect(aiPackages.map((p) => p.id), ['pro']);
    expect(aiPackages.single.premium, isTrue);
    expect(aiPackages.single.sizeBytes, lessThanOrEqualTo(3.1e9));
    for (final p in aiPackages) {
      expect(p.licenseName, 'Apache 2.0');
      expect(p.urls.first, startsWith('https://'));
      expect(p.ratings, hasLength(4));
    }
  });

  test('premium packages are locked without the flag', () async {
    final real = LlamaLocalAi(u, dir);
    expect(real.premiumUnlocked, isFalse);
    await expectLater(real.download('pro'), emitsError(isA<AiException>()));
    u.setSetting('ai_premium', '1');
    expect(real.premiumUnlocked, isTrue);
    u.setSetting('ai_premium', null);
  });

  test('grounding carries tenses, expressions and meanings', () {
    final g = tutor.grounding('She has given up smoking because it was bad for her health.');
    expect(g, contains('Present Perfect'));
    expect(g, contains('give up'));
    expect(g, contains('health'));
  });

  test('explainSentence sends the sentence and the facts', () async {
    await tutor.explainSentence('I have been waiting for you since morning.').drain<void>();
    final user = ai.lastMessages!.single.$2;
    expect(user, contains('I have been waiting'));
    expect(user, contains('Present Perfect Continuous'));
    expect(ai.lastSystem, contains('**Çeviri:**'));
  });

  test('chat keeps only the last turns', () async {
    final h = [for (var i = 0; i < 30; i++) (i.isEven ? 'user' : 'assistant', 'turn $i')];
    await tutor.chatReply(h, level: 'A2').drain<void>();
    expect(ai.lastMessages, hasLength(12));
    expect(ai.lastSystem, contains('A2'));
  });

  test('quiz answers come from the dictionary', () async {
    app.setWord('decision', WordStatus.learning, context: 'It was a difficult decision for all of us.');
    app.setWord('borrow', WordStatus.learning, context: 'Can I borrow your pen?');
    final q = await tutor.quiz(count: 5, seed: 1);
    expect(q, isNotEmpty);
    for (final item in q) {
      expect(item.options.toSet(), hasLength(item.options.length));
      expect(item.options.length, 4);
      expect(item.answer, inInclusiveRange(0, 3));
    }
  });

  test('think blocks are removed from streamed text, also when split', () {
    final f = ThinkFilter();
    final out = StringBuffer()
      ..write(f.add('<thi'))
      ..write(f.add('nk>\nhmm</th'))
      ..write(f.add('ink>\n\nMerhaba'))
      ..write(f.add(' <'))
      ..write(f.add('b>dünya'))
      ..write(f.close());
    expect(out.toString(), 'Merhaba <b>dünya');
  });

  test('chat turns alternate and start with the user', () {
    expect(alternateTurns([('assistant', 'Hi! Plans?'), ('user', 'Yes'), ('user', 'cinema')]),
        [('user', 'Hi!'), ('assistant', 'Hi! Plans?'), ('user', 'Yes\n\ncinema')]);
  });

  test('a correct text is never given invented mistakes', () async {
    final out = await Tutor.guardNoErrorForTest('I have been living in Izmir since 2018.', Stream.fromIterable([
      '**Doğru hâli:** I have been living in Izmir since 2018.\n',
      '**Hatalar:**\n- "have been living" → "have lived"',
    ])).join();
    expect(out, contains(Tutor.noErrorAnswer));
    expect(out, isNot(contains('have lived')));
    final fixed = await Tutor.guardNoErrorForTest('Yesterday I have went home.', Stream.fromIterable([
      '**Doğru hâli:** Yesterday I went home.\n**Hatalar:**\n- have went → went: ...',
    ])).join();
    expect(fixed, contains('have went → went'));
  });
}
