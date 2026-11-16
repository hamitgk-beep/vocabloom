import 'dart:async';

import '../data/user_db.dart';
import '../online/ai_service.dart';
import 'local_ai.dart';

/// The tutor's AI: the service the learner connected in Settings with their
/// own API key (Gemini has a free plan). Without a key there is no AI, and
/// the "Yapay zekâya sor" buttons explain how to add one.
class KeyAi extends LocalAi {
  final UserDb db;
  KeyAi(this.db);

  AiService? get service => AiService.fromSettings(db);

  /// The Gemini model that answers quickly on the free plan.
  static const fastGemini = 'gemini-flash-lite-latest';

  @override
  List<AiPackage> get packages => const [];
  @override
  Future<Set<String>> installed() async => const {};
  @override
  Map<String, AiDownload> get downloads => const {};
  @override
  Stream<AiDownload> download(String id) => const Stream.empty();
  @override
  Future<void> cancel(String id) async {}
  @override
  Future<void> delete(String id) async {}

  /// 'key' while a service is connected, so `activeId != null` means "AI available".
  @override
  String? get activeId => service == null ? null : 'key';
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
      {int maxTokens = 512, double temperature = 0.3}) async* {
    final svc = service;
    if (svc == null) {
      throw const AiException('Yapay zekâ için Ayarlar > Yapay zekâ servisi bölümünden kendi API anahtarını ekle.',
          'To use the AI, add your own API key in Settings > AI service.');
    }
    final turns = alternateTurns(messages);
    // Online models write longer than the old offline one: give them room
    // so an answer is not cut off.
    final budget = maxTokens < 1200 ? 1200 : maxTokens;
    final c = svc.cfg;
    final canFallBack = c.provider.kind == ApiKind.gemini && c.model != fastGemini;
    var got = false;
    try {
      await for (final piece in _answer(svc, system, turns, budget, firstWait: canFallBack ? fallbackAfter : waitLimit)) {
        got = true;
        yield piece;
      }
    } on TimeoutException {
      if (got || !canFallBack) throw _tooLong;
      // A slow or busy Gemini model: the quick lite one answers in about a second.
      try {
        yield* _answer(AiService(AiConfig(c.provider, c.key, fastGemini, c.baseUrl)), system, turns, budget, firstWait: waitLimit);
      } on TimeoutException {
        throw _tooLong;
      }
      return;
    }
    if (!got) {
      throw const AiException('Yapay zekâ bu kez boş bir yanıt verdi. Tekrar dene.', 'The AI gave an empty answer this time. Try again.');
    }
  }

  static const _tooLong = AiException('Yapay zekâ servisi çok uzun süre yanıt vermedi. İnternet bağlantını kontrol edip tekrar dene.',
      'The AI service did not answer for too long. Check your internet connection and try again.');

  /// No first words after this long: switch to the quick Gemini model.
  static const fallbackAfter = Duration(seconds: 12);

  /// The longest wait for the first or the next words.
  static const waitLimit = Duration(seconds: 45);

  /// The answer's pieces without any `<think>…</think>` block in front;
  /// a [TimeoutException] when the service goes quiet.
  Stream<String> _answer(AiService svc, String system, List<(String, String)> turns, int budget, {required Duration firstWait}) async* {
    final it = StreamIterator(svc.chatStream(system, turns, maxTokens: budget));
    var head = '';
    var inHead = true;
    var first = true;
    try {
      while (await it.moveNext().timeout(first ? firstWait : waitLimit)) {
        first = false;
        var piece = it.current;
        if (inHead) {
          // Hold back the start until it is clear whether it is reasoning.
          head += piece;
          final t = head.trimLeft();
          if (t.startsWith('<think>')) {
            final end = t.indexOf('</think>');
            if (end < 0) continue;
            piece = t.substring(end + 8).trimLeft();
          } else if ('<think>'.startsWith(t)) {
            continue;
          } else {
            piece = t;
          }
          inHead = false;
          if (piece.isEmpty) continue;
        }
        yield piece;
      }
      if (inHead && head.trim().isNotEmpty && !head.trimLeft().startsWith('<think>')) yield head.trimLeft();
    } finally {
      await it.cancel();
    }
  }

  @override
  void stop() {}
  @override
  Future<void> unload() async {}
}

/// Removes `<think>…</think>` blocks some reasoning models put in front.
String stripThinking(String s) => s.replaceAll(RegExp(r'<think>[\s\S]*?</think>\s*'), '');

/// Turns that start with the user and alternate user/assistant, as strict chat
/// APIs (Anthropic, Gemini) require: same-role neighbours are joined, and a
/// conversation the assistant opened gets a short user turn in front.
List<(String, String)> alternateTurns(List<(String, String)> messages) {
  final out = <(String, String)>[];
  for (final (role, text) in messages) {
    final r = role == 'assistant' ? 'assistant' : 'user';
    if (out.isNotEmpty && out.last.$1 == r) {
      out[out.length - 1] = (r, '${out.last.$2}\n\n$text');
    } else {
      out.add((r, text));
    }
  }
  if (out.isNotEmpty && out.first.$1 == 'assistant') out.insert(0, ('user', 'Hi!'));
  return out;
}
