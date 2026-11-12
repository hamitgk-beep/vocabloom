import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/user_db.dart';
import 'ai_service.dart';

/// Watches for an internet connection and analyses every book that has not
/// been analysed yet. Finished paragraphs are stored, so nothing is done twice
/// and an interrupted analysis continues where it stopped.
class AutoAnalyzer {
  final UserDb db;
  final status = ValueNotifier<Map<int, String>>({});
  Timer? _timer;
  bool _running = false;
  String? lastError;

  AutoAnalyzer(this.db);

  bool get enabled => db.getSetting('auto_analyze') != '0';

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => tick());
    Future.delayed(const Duration(seconds: 3), tick);
  }

  void dispose() => _timer?.cancel();

  void _set(int id, String? s) {
    final m = Map<int, String>.from(status.value);
    s == null ? m.remove(id) : m[id] = s;
    status.value = m;
  }

  /// Runs one pass. [force] ignores the automatic setting (menu action).
  Future<void> tick({bool force = false, int? onlyBook}) async {
    if (_running || (!enabled && !force)) return;
    final svc = AiService.fromSettings(db);
    if (svc == null) return;
    _running = true;
    try {
      if (!await svc.reachable()) return;
      final books = db.books().where((b) => onlyBook == null || b.id == onlyBook);
      for (final b in books) {
        if (db.parasMissingTranslation(b.id).isEmpty) continue;
        _set(b.id, 'Çevrimiçi analiz başlıyor…');
        try {
          await analyzeBook(svc, db, b.id, onProgress: (d, t) => _set(b.id, 'Çevrimiçi analiz: $d/$t paragraf (${svc.cfg.provider.name})'));
          lastError = null;
        } catch (e) {
          lastError = '$e';
          _set(b.id, 'Analiz durdu, internet geldiğinde devam edecek: $e');
          await Future.delayed(const Duration(seconds: 8));
          _set(b.id, null);
          return; // try again on the next tick
        }
        _set(b.id, null);
      }
    } finally {
      _running = false;
    }
  }
}
