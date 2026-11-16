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

  /// How long one answer may take.
  static const answerTimeout = Duration(seconds: 90);

  AiService? get service => AiService.fromSettings(db);

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
    final String text;
    try {
      // Online models think more and write longer than the old offline one:
      // give them room so an answer is not cut off.
      text = await svc.chat(system, alternateTurns(messages), maxTokens: maxTokens < 1200 ? 1200 : maxTokens).timeout(answerTimeout);
    } on TimeoutException {
      throw const AiException('Yapay zekâ servisi çok uzun süre yanıt vermedi. İnternet bağlantını kontrol edip tekrar dene.',
          'The AI service did not answer for too long. Check your internet connection and try again.');
    }
    final answer = stripThinking(text).trim();
    if (answer.isEmpty) {
      throw const AiException('Yapay zekâ bu kez boş bir yanıt verdi. Tekrar dene.', 'The AI gave an empty answer this time. Try again.');
    }
    yield answer;
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
