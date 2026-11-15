import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import '../data/user_db.dart';

/// Instant English -> Turkish translation on the phone, the way the Google
/// Translate app works offline: Google ML Kit's free on-device translation
/// model (about 30 MB, downloaded once). Android and iOS only.
class DeviceTranslate {
  DeviceTranslate._();
  static final instance = DeviceTranslate._();

  /// Tests and desktop builds have no ML Kit.
  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static const _readyKey = 'mt_tr_ready';
  final _manager = OnDeviceTranslatorModelManager();
  OnDeviceTranslator? _translator;

  /// Whether the Turkish package was downloaded (kept in settings so panels
  /// can decide at once, without a platform call).
  bool ready(UserDb user) => supported && user.getSetting(_readyKey) == '1';

  /// Downloads the English and Turkish packages. Works on mobile data too.
  Future<bool> download(UserDb user) async {
    if (!supported) return false;
    final en = await _manager.downloadModel(TranslateLanguage.english.bcpCode, isWifiRequired: false);
    final tr = await _manager.downloadModel(TranslateLanguage.turkish.bcpCode, isWifiRequired: false);
    final ok = en && tr || await _manager.isModelDownloaded(TranslateLanguage.turkish.bcpCode);
    if (ok) user.setSetting(_readyKey, '1');
    return ok;
  }

  /// Turkish of [text]; answers are kept, so a sentence is translated once.
  Future<String?> translate(UserDb user, String text) async {
    text = text.trim();
    if (!ready(user) || text.isEmpty) return null;
    final key = 'mt:$text';
    final saved = user.getSetting(key);
    if (saved != null && saved.isNotEmpty) return saved;
    _translator ??= OnDeviceTranslator(sourceLanguage: TranslateLanguage.english, targetLanguage: TranslateLanguage.turkish);
    try {
      final r = (await _translator!.translateText(text)).trim();
      if (r.isEmpty || r.toLowerCase() == text.toLowerCase()) return null;
      user.setSetting(key, r);
      return r;
    } catch (_) {
      return null;
    }
  }
}
