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

  /// True while the package is being downloaded (panels show "preparing"
  /// instead of a button, and refresh when it is done).
  final downloading = ValueNotifier<bool>(false);
  Future<bool>? _running;

  /// Set before a download starts and cleared when it ends. Still set at the
  /// next start means the app closed during the download, so it is not
  /// started on its own again (the learner can still press the button).
  static const _tryKey = 'mt_tr_trying';

  /// Downloads the English and Turkish packages. Works on mobile data too.
  /// English is built in, so only Turkish is fetched.
  Future<bool> download(UserDb user) => _running ??= _download(user).whenComplete(() => _running = null);

  Future<bool> _download(UserDb user) async {
    if (!supported) return false;
    downloading.value = true;
    user.setSetting(_tryKey, '1');
    try {
      final tr = TranslateLanguage.turkish.bcpCode;
      var ok = await _manager.isModelDownloaded(tr);
      if (!ok) ok = await _manager.downloadModel(tr, isWifiRequired: false);
      if (!ok) ok = await _manager.isModelDownloaded(tr);
      if (ok) user.setSetting(_readyKey, '1');
      return ok;
    } catch (_) {
      return false;
    } finally {
      user.setSetting(_tryKey, '');
      downloading.value = false;
    }
  }

  /// Gets the package ready by itself when the app starts, so the learner
  /// never has to press a button: once, in the background. Skipped when an
  /// earlier start closed during the download.
  void prepare(UserDb user) {
    if (!supported || ready(user)) return;
    final t = user.getSetting(_tryKey);
    if (t == '1' || t == 'closed') {
      user.setSetting(_tryKey, 'closed');
      return;
    }
    download(user);
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
