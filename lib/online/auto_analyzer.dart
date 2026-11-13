import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/dict_db.dart';
import '../data/user_db.dart';
import '../nlp/text.dart';
import '../l10n.dart';
import 'ai_service.dart';

/// Watches for an internet connection and analyses every book that has not
/// been analysed yet. Finished paragraphs are stored, so nothing is done twice
/// and an interrupted analysis continues where it stopped.
///
/// After the books, it translates dictionary expressions that only have an
/// English definition (expressions found in the user's books first).
class AutoAnalyzer {
  final UserDb db;
  final DictDb? dict;
  final status = ValueNotifier<Map<int, String>>({});

  /// Progress of the dictionary translation, shown in Settings.
  final dictStatus = ValueNotifier<String?>(null);
  Timer? _timer;
  bool _running = false;
  String? lastError;

  AutoAnalyzer(this.db, [this.dict]);

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
        _set(b.id, L('Çevrimiçi analiz başlıyor…', 'Starting online analysis…'));
        try {
          await analyzeBook(svc, db, b.id, onProgress: (d, t) => _set(b.id, L('Çevrimiçi analiz: $d/$t paragraf (${svc.cfg.provider.name})', 'Online analysis: $d/$t paragraphs (${svc.cfg.provider.name})')));
          lastError = null;
        } catch (e) {
          lastError = '$e';
          _set(b.id, L('Analiz durdu, internet geldiğinde devam edecek: $e', 'Analysis paused, it will continue when online: $e'));
          await Future.delayed(const Duration(seconds: 8));
          _set(b.id, null);
          return; // try again on the next tick
        }
        _set(b.id, null);
      }
      if (onlyBook == null) await _translateDictionary(svc);
    } finally {
      _running = false;
    }
  }

  final Set<int> _scannedBooks = {};
  final Set<int> _inBooks = {};

  /// Expression ids that occur in the user's books (computed once per book).
  Future<void> _scanBooks() async {
    final d = dict;
    if (d == null) return;
    for (final b in db.books()) {
      if (!_scannedBooks.add(b.id)) continue;
      for (final ch in db.chapters(b.id)) {
        await Future<void>.delayed(Duration.zero); // keep the UI responsive
        for (final p in db.paras(b.id, ch.idx)) {
          for (final m in d.matcher.match(tokenize(p.text))) {
            _inBooks.add(m.expr.id);
          }
        }
      }
    }
  }

  Future<void> _translateDictionary(AiService svc) async {
    final d = dict;
    if (d == null) return;
    await _scanBooks();
    final pending = d.exprs.where((e) => e.needsAi).toList()
      ..sort((a, b) => (_inBooks.contains(a.id) ? 0 : 1).compareTo(_inBooks.contains(b.id) ? 0 : 1));
    if (pending.isEmpty) {
      dictStatus.value = null;
      return;
    }
    final total = d.exprs.where((e) => e.en != null && e.tr == null).length;
    const batch = 40;
    for (var i = 0; i < pending.length; i += batch) {
      if (!enabled) break;
      final part = pending.sublist(i, (i + batch).clamp(0, pending.length));
      final done = total - pending.length + i;
      dictStatus.value = L('Sözlük Türkçeye çevriliyor: $done/$total (${svc.cfg.provider.name})', 'Translating the dictionary into Turkish: $done/$total (${svc.cfg.provider.name})');
      try {
        await translateExprsNow(svc, part);
      } catch (e) {
        lastError = '$e';
        dictStatus.value = L('Sözlük çevirisi durdu, sonra devam edecek: $e', 'Dictionary translation paused, it will continue later: $e');
        return;
      }
    }
    dictStatus.value = null;
  }

  /// Translates [items] with the AI and saves the result on the device.
  Future<void> translateExprsNow(AiService svc, List<Expr> items) async {
    final todo = items.where((e) => e.needsAi).toList();
    if (todo.isEmpty) return;
    final r = await svc.translateExprs([for (final e in todo) (phrase: e.phrase, cat: e.cat, en: e.en!)]);
    if (r.length != todo.length) throw Exception(L('Yapay zekâ ${todo.length} yerine ${r.length} sonuç döndürdü.', 'The AI returned ${r.length} results instead of ${todo.length}.'));
    for (var k = 0; k < todo.length; k++) {
      if (r[k].tr.isEmpty) continue;
      final e = todo[k];
      e.aiTr = r[k].tr;
      e.aiExp = r[k].exp.isEmpty ? null : r[k].exp;
      db.setExprAi(e.phrase, e.cat, e.aiTr!, e.aiExp);
    }
  }
}
