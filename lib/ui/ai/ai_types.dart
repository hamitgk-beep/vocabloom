// TEMPORARY mirror of the engine's types (lib/ai/local_ai.dart, lib/ai/tutor.dart).
// When the engine lands on main, this file is deleted and the imports in
// lib/ui/ai/* point at lib/ai/ instead. Keep the shapes identical.
import 'package:flutter/foundation.dart';

class AiPackage {
  final String id;
  final String tier; // 'free' | 'plus' | 'pro'
  final String nameTr, nameEn;
  final String descTr, descEn;
  final String noteTr, noteEn;
  final List<(String, String, int)> ratings; // labelTr, labelEn, 1..5
  final int sizeBytes;
  final String model;
  final String licenseName;
  final bool premium;
  final int minRamGb;
  const AiPackage({
    required this.id,
    required this.tier,
    required this.nameTr,
    required this.nameEn,
    required this.descTr,
    required this.descEn,
    required this.noteTr,
    required this.noteEn,
    required this.ratings,
    required this.sizeBytes,
    required this.model,
    required this.licenseName,
    required this.premium,
    required this.minRamGb,
  });
}

class AiDownload {
  final int received, total;
  const AiDownload(this.received, this.total);
  double get fraction => total <= 0 ? 0 : received / total;
}

abstract class LocalAi extends ChangeNotifier {
  List<AiPackage> get packages;
  Future<Set<String>> installed();
  Stream<AiDownload> download(String id);
  Future<void> cancel(String id);
  Future<void> delete(String id);
  String? get activeId;
  Future<void> setActive(String id);
  bool get premiumUnlocked;
  Future<int?> deviceRamMb();
  Stream<String> generate(String system, List<(String, String)> messages, {int maxTokens = 512});
}

class QuizItem {
  final String question;
  final List<String> options;
  final int answer;
  final String explanationTr;
  const QuizItem(this.question, this.options, this.answer, this.explanationTr);
}

abstract class Tutor {
  Stream<String> explainSentence(String sentence, {String? bookTitle});
  Stream<String> correct(String userText);
  Stream<String> chatReply(List<(String, String)> history, {String level = 'B1', String? topic});
  Future<List<QuizItem>> quiz(List<String> words, {int count = 5});
}
