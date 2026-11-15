/// On-device, offline AI tutor: package catalog types and the engine
/// interface the "Yapay Zekâ" screens program against.
///
/// The implementation lives in `local_engine.dart` (llama.cpp through
/// llamadart); the task prompts live in `tutor.dart`.
library;

import 'package:flutter/foundation.dart';

import '../l10n.dart';

/// Who may download a package.
enum AiTier { free, plus, pro }

/// One quality rating shown on a package card (1 to 5).
class AiRating {
  final String labelTr, labelEn;
  final int score;
  const AiRating(this.labelTr, this.labelEn, this.score);
  String get label => uiEnglish ? labelEn : labelTr;
}

/// A downloadable model package.
class AiPackage {
  final String id;
  final String nameTr, nameEn;
  final AiTier tier;

  /// Approximate download size, for display before the download starts.
  /// The real size comes from the server and is shown in [AiDownload.total].
  final int sizeBytes;

  /// Human readable base model, e.g. "Qwen3 1.7B (Q4_K_M)".
  final String model;
  final String licenseName;

  /// Where the GGUF file is downloaded from. Several mirrors may be given;
  /// they are tried in order.
  final List<String> urls;

  /// Optional lowercase hex SHA-256 of the file. When set, the file is checked
  /// after the download.
  final String? sha256;

  /// Smallest device memory (RAM) the package is recommended for.
  final int minRamGb;

  /// Recommended phone level, e.g. "Orta seviye ve üstü".
  final String deviceTr, deviceEn;

  /// One professional paragraph describing the package.
  final String descTr, descEn;

  /// Accuracy notice ("Yanıtlar zaman zaman hatalı olabilir …").
  final String noteTr, noteEn;

  final List<AiRating> ratings;

  /// Context window the engine opens for this model.
  final int contextSize;

  /// Whether the model has a thinking mode that must be switched off.
  final bool hybridThinking;

  const AiPackage({
    required this.id,
    required this.nameTr,
    required this.nameEn,
    required this.tier,
    required this.sizeBytes,
    required this.model,
    required this.licenseName,
    required this.urls,
    this.sha256,
    required this.minRamGb,
    required this.deviceTr,
    required this.deviceEn,
    required this.descTr,
    required this.descEn,
    required this.noteTr,
    required this.noteEn,
    required this.ratings,
    this.contextSize = 4096,
    this.hybridThinking = false,
  });

  bool get premium => tier != AiTier.free;
  String get name => uiEnglish ? nameEn : nameTr;
  String get device => uiEnglish ? deviceEn : deviceTr;
  String get desc => uiEnglish ? descEn : descTr;
  String get note => uiEnglish ? noteEn : noteTr;

  /// "1,1 GB" / "450 MB".
  String get sizeLabel => formatBytes(sizeBytes);
}

String formatBytes(int b) {
  final sep = uiEnglish ? '.' : ',';
  if (b >= 1000 * 1000 * 1000) {
    return '${(b / 1e9).toStringAsFixed(1).replaceAll('.', sep)} GB';
  }
  return '${(b / 1e6).round()} MB';
}

/// Download progress of one package.
class AiDownload {
  final String id;
  final int received;

  /// Total size in bytes; 0 while unknown.
  final int total;
  final bool done;
  const AiDownload(this.id, this.received, this.total, {this.done = false});
  double? get fraction => total <= 0 ? null : (received / total).clamp(0.0, 1.0);
}

/// Why a package cannot be downloaded or used.
class AiException implements Exception {
  final String messageTr, messageEn;
  const AiException(this.messageTr, this.messageEn);
  String get message => uiEnglish ? messageEn : messageTr;
  @override
  String toString() => message;
}

/// The offline AI engine. One instance per app ([AppState.localAi]).
abstract class LocalAi extends ChangeNotifier {
  List<AiPackage> get packages;

  /// Ids of the fully downloaded packages.
  Future<Set<String>> installed();

  /// Progress of the running downloads, by package id (for rebuilding a
  /// screen that was closed while downloading).
  Map<String, AiDownload> get downloads;

  /// Starts or resumes a download. Throws [AiException] for a premium package
  /// while [premiumUnlocked] is false. The stream ends with `done: true`;
  /// it errors on failure (the partial file is kept for resuming).
  Stream<AiDownload> download(String id);

  /// Stops a download and keeps the partial file.
  Future<void> cancel(String id);

  /// Deletes the package (and any partial file).
  Future<void> delete(String id);

  /// The package used for generation; null until one is installed and chosen.
  String? get activeId;
  Future<void> setActive(String id);

  /// Paid packages are open. There are no subscriptions yet, so this is a
  /// flag: the setting `ai_premium` = '1' or `--dart-define=AI_PREMIUM=true`.
  bool get premiumUnlocked;

  /// Device memory in MB; null when unknown.
  Future<int?> deviceRamMb();

  /// Whether a model is loaded in memory right now.
  bool get loaded;

  /// Whether the model is being loaded into memory right now.
  bool get loading => false;

  /// Streams the reply of the active package. `messages` are (role, text)
  /// with role 'user' or 'assistant'. Cancel the subscription to stop.
  Stream<String> generate(String system, List<(String, String)> messages,
      {int maxTokens = 512, double temperature = 0.3});

  /// Stops the running generation.
  void stop();

  /// Frees the model from memory (it is loaded again on the next request).
  Future<void> unload();
}
