// The learner's own AI key (often a paid one) is used only when they ask:
// opening a word panel or a review card never calls it by itself. In the
// review, an explicit "automatic AI analysis" setting still allows the
// background question, as before.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/ai/key_ai.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/review.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/online/ai_service.dart';
import 'package:kelime_okur/ui/review_page.dart';
import 'package:kelime_okur/ui/theme.dart';
import 'package:kelime_okur/ui/word_sheet.dart';
import 'package:sqlite3/sqlite3.dart';

/// A connected AI service that counts every question.
class CountingKeyAi extends KeyAi {
  CountingKeyAi(super.db);
  var calls = 0;

  @override
  String? get activeId => 'key';

  @override
  Stream<String> generate(String system, List<(String, String)> messages, {int maxTokens = 512, double temperature = 0.3}) async* {
    calls++;
    yield 'uydurma anlam';
  }
}

class CountingService extends AiService {
  CountingService() : super(AiConfig(providerById['openai']!, 'k', 'fake-model', 'http://localhost'));
  var calls = 0;

  @override
  Future<String> meaningInSentence(String word, String sentence) async {
    calls++;
    return 'uydurma';
  }
}

const unknown = 'glorpishness';
const sentence = 'The glorpishness of the hall surprised everyone.';

void main() {
  late Directory dir;
  late AppState app;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('storilex_paid_ai');
    final d = DictDb();
    d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    app = AppState(d, UserDb.open(dir));
  });

  tearDown(() {
    AiService.debugFromSettings = null;
    dir.deleteSync(recursive: true);
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(390 * 2, 1600 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: child)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('word panel: a word without Turkish does not ask the AI until tapped', (tester) async {
    final ai = CountingKeyAi(app.user);
    app.localAi = ai;
    await pump(tester, WordPanel(app: app, surface: unknown));
    expect(find.byKey(const ValueKey('ai-word-$unknown')), findsOneWidget);
    expect(ai.calls, 0, reason: 'opening the panel must not use the key');
    await tester.tap(find.text('Yapay zekâ ile açıkla').hitTestable().first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(ai.calls, 1);
    expect(find.textContaining('uydurma anlam'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  ReviewPage review() => ReviewPage(app: app, cards: [ReviewCard(SavedWord(unknown, WordStatus.learning, sentence, null, null, DateTime.now()), 0)]);

  testWidgets('review: no background AI question while automatic analysis is off', (tester) async {
    final svc = CountingService();
    AiService.debugFromSettings = (_) => svc;
    expect(app.analyzer.enabled, isFalse);
    await pump(tester, review());
    expect(svc.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('review: the learner\'s explicit automatic setting still allows it', (tester) async {
    final svc = CountingService();
    AiService.debugFromSettings = (_) => svc;
    app.user.setSetting('auto_analyze', '1');
    await pump(tester, review());
    expect(svc.calls, 1);
    expect(tester.takeException(), isNull);
  });
}
