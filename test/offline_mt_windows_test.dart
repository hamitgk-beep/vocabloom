// The offline translation end to end with the real model, the way a learner
// on Windows meets it: cancel a download, download it (each file checked
// against its SHA-256), the first translation, using it again without the
// internet, reopening the app, and deleting the model.
//
// It downloads about 530 MB, so it runs only when OPUS_MT_LIVE=1 (the
// Windows CI job sets it, with SHERPA_ONNX_LIB_DIR pointing at the ONNX
// Runtime the app ships). MT_LIVE_OUT names a file for a short report.
//
// MT_LIVE_PHASE splits it in two runs around a firewall rule: "online"
// (download, translate, keep the model in MT_LIVE_DIR), then "offline"
// (this process cannot reach the internet: reopen, translate, a download
// attempt fails clearly, delete). Without it ("all") everything runs once,
// with the internet replaced by a failing download only.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/mt/offline_mt.dart';

void main() {
  final live = Platform.environment['OPUS_MT_LIVE'] == '1';
  final phase = Platform.environment['MT_LIVE_PHASE'] ?? 'all';
  final fixedDir = Platform.environment['MT_LIVE_DIR'];
  final report = <String, Object?>{'os': Platform.operatingSystem, 'osVersion': Platform.operatingSystemVersion};
  late Directory dir;

  setUpAll(() {
    dir = fixedDir != null ? (Directory(fixedDir)..createSync(recursive: true)) : Directory.systemTemp.createTempSync('storilex_mt_live');
    // Off Windows (a developer's machine) the feature is only pretended on.
    if (!Platform.isWindows) OfflineMt.debugSupported = true;
    report['platformSupported'] = OfflineMt.platformSupported;
  });

  tearDownAll(() {
    final out = Platform.environment['MT_LIVE_OUT'];
    if (out != null) File(out).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(report));
    OfflineMt.debugSupported = null;
    if (fixedDir != null) return; // the next phase uses it
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  void step(String name, Object? value) {
    report[name] = value;
    // ignore: avoid_print
    print('$name: $value');
  }

  test('every step on the real model', () async {
    expect(OfflineMt.platformSupported, isTrue);
    final user = UserDb.open(dir);
    user.setWord('river', WordStatus.learning, context: 'He sat on the bank of the river.');
    user.setSentenceAi('He sat on the bank of the river.', 'Nehrin kıyısında oturdu.', null);
    final before = _learnerRows(user);

    // 1. Nothing is there and nothing is fetched until asked.
    var mt = OfflineMt.test(opusEnTr)..init(dir);
    expect(mt.installed, isFalse);
    expect(mt.active(user), isFalse);
    final free = OfflineMt.diskFree(dir.path);
    step('diskFreeBytes', free);
    if (Platform.isWindows) expect(free, isNotNull, reason: 'GetDiskFreeSpaceExW answered');

    // 2. Not enough room: refused before anything is downloaded.
    mt.freeSpace = (_) => 1000;
    expect(await mt.download(), isFalse);
    expect(mt.state.errorEn, contains('Not enough disk space'));
    expect(Directory(mt.modelDir!).existsSync(), isFalse);
    step('diskSpaceRefusal', mt.state.errorTr);
    mt.freeSpace = OfflineMt.diskFree;

    // 3. Cancel while downloading: no half file stays.
    var cancelledAt = 0;
    void cancelSoon() {
      if (mt.state.status == OfflineMtStatus.downloading && mt.state.received > 20 * 1000 * 1000 && cancelledAt == 0) {
        cancelledAt = mt.state.received;
        mt.cancel();
      }
    }

    mt.addListener(cancelSoon);
    final sw = Stopwatch()..start();
    expect(await mt.download(), isFalse);
    mt.removeListener(cancelSoon);
    expect(cancelledAt, greaterThan(0));
    expect(mt.state.status, OfflineMtStatus.notInstalled);
    final parts = Directory(mt.modelDir!).listSync(recursive: true).where((e) => e.path.endsWith('.part')).toList();
    expect(parts, isEmpty);
    expect(mt.installed, isFalse);
    step('cancel', {'atBytes': cancelledAt, 'partFilesLeft': parts.length});

    // 4. The full download, then every file checked again here.
    sw.reset();
    final ok = await mt.download();
    step('downloadSeconds', sw.elapsed.inSeconds);
    expect(ok, isTrue, reason: mt.state.errorEn);
    expect(mt.installed, isTrue);
    final hashes = <String, bool>{};
    for (final f in opusEnTr.files) {
      final file = File('${mt.modelDir}${Platform.pathSeparator}${f.path.replaceAll('/', Platform.pathSeparator)}');
      hashes[f.path] = file.lengthSync() == f.size && sha256.convert(file.readAsBytesSync()).toString() == f.sha256;
    }
    step('sha256', hashes);
    expect(hashes.values.every((v) => v), isTrue);

    // 5. Off until turned on; then the first translation. Memory is the
    // whole test process (the model runs in an isolate of it).
    step('rssBeforeModelMB', ProcessInfo.currentRss ~/ 1000000);
    expect(await mt.translate(user, 'The plane took off at noon.'), isNull);
    mt.setEnabled(user, true);
    sw.reset();
    final first = await mt.translate(user, 'The plane took off at noon.');
    step('firstTranslation', {'tr': first, 'ms': sw.elapsedMilliseconds});
    expect(first, contains('kalktı'));
    expect(user.mtCached(opusEnTr.engine, 'en>tr', 'The plane took off at noon.'), first);
    sw.reset();
    final second = await mt.translate(user, 'He sat on the bank of the river.');
    step('secondTranslation', {'tr': second, 'ms': sw.elapsedMilliseconds});
    expect(second, isNotNull);
    // A batch of sentences, as when paging through a chapter.
    final batch = [
      'Although the night was cold and the road was long, the old man kept walking.',
      'When the giant came back, he looked under the bed and behind the door.',
      '"Where are you going?" asked the wolf.',
      'She had lived in the village all her life, and she knew every path.',
      'They walked for hours; the sun went down, and still there was no house in sight.',
      'He gave up smoking last year.',
      'The farmer sold the cow for a handful of beans.',
      'By the time the soldiers reached the bridge, the river had risen.',
    ];
    final times = <int>[];
    for (final b in batch) {
      sw.reset();
      expect(await mt.translate(user, b), isNotNull, reason: b);
      times.add(sw.elapsedMilliseconds);
    }
    times.sort();
    step('batchMs', {'median': times[times.length ~/ 2], 'max': times.last, 'n': times.length});
    step('rssWithModelMB', ProcessInfo.currentRss ~/ 1000000);
    step('maxRssMB', ProcessInfo.maxRss ~/ 1000000);
    if (phase == 'online') {
      // Closed as on exit; the offline run reopens it.
      await mt.closeEngine();
      File('${dir.path}/before.json').writeAsStringSync(jsonEncode(before));
      File('${dir.path}/first.txt').writeAsStringSync(first!);
      user.db.close();
      return;
    }

    // 6. Reopening the app: the model is closed as on exit, then found on
    // disk, still on, nothing downloaded.
    await mt.closeEngine();
    user.db.close();
    final reopenedUser = UserDb.open(dir);
    var downloads = 0;
    mt = OfflineMt.test(opusEnTr)..init(dir);
    expect(mt.installed, isTrue);
    expect(mt.active(reopenedUser), isTrue);
    // 7. Without the internet: every download attempt fails, translation
    // still works (it never uses the network) and saved answers come back.
    Future<(int?, Stream<List<int>>)> noInternet(Uri u) async {
      downloads++;
      throw const SocketException('no internet');
    }

    expect(await mt.translate(reopenedUser, 'The plane took off at noon.'), first);
    sw.reset();
    final offline = await mt.translate(reopenedUser, 'She put her money in the bank.');
    step('offlineTranslation', {'tr': offline, 'ms': sw.elapsedMilliseconds});
    expect(offline, contains('banka'));
    // A download now would fail, and the model in place is not touched.
    expect(await mt.download(fetch: noInternet), isTrue, reason: 'all files are in place, nothing to fetch');
    expect(downloads, 0);

    // 8. The learner's own records are as they were: only the translation
    // cache and the on/off setting changed.
    expect(_learnerRows(reopenedUser), before);
    expect(reopenedUser.statuses['river'], WordStatus.learning);
    expect(reopenedUser.sentenceAi('He sat on the bank of the river.')?.$1, 'Nehrin kıyısında oturdu.');
    step('learnerRecordsUnchanged', true);

    // 9. Deleting: files gone, turned off, saved translations kept.
    await mt.remove(reopenedUser);
    expect(Directory(mt.modelDir!).existsSync(), isFalse);
    expect(mt.active(reopenedUser), isFalse);
    expect(await mt.translate(reopenedUser, 'A new sentence here.'), isNull);
    final again = OfflineMt.test(opusEnTr)..init(dir);
    expect(again.installed, isFalse);
    expect(reopenedUser.mtCached(opusEnTr.engine, 'en>tr', 'The plane took off at noon.'), first);
    step('deleted', true);
    reopenedUser.db.close();
  }, skip: !live ? 'set OPUS_MT_LIVE=1 (downloads about 530 MB)' : phase == 'offline' ? 'online steps ran before' : null, timeout: const Timeout(Duration(minutes: 20)));

  test('without the internet (this process blocked by the firewall)', () async {
    // The block is real: this process cannot reach the model's host.
    Object? netError;
    try {
      final c = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      final r = await (await c.getUrl(Uri.parse('https://huggingface.co/'))).close().timeout(const Duration(seconds: 20));
      step('networkStatusWhileBlocked', r.statusCode);
      c.close(force: true);
    } catch (e) {
      netError = e;
    }
    step('networkBlocked', netError == null ? false : '$netError'.split('\n').first);
    expect(netError, isNotNull, reason: 'the firewall rule must stop this process reaching the internet');

    // Reopening the app without the internet: found, on, translating.
    final user = UserDb.open(dir);
    var mt = OfflineMt.test(opusEnTr)..init(dir);
    expect(mt.installed, isTrue);
    expect(mt.active(user), isTrue);
    final first = File('${dir.path}/first.txt').readAsStringSync();
    expect(await mt.translate(user, 'The plane took off at noon.'), first, reason: 'from the cache');
    final sw = Stopwatch()..start();
    final offline = await mt.translate(user, 'She put her money in the bank.');
    step('offlineTranslation', {'tr': offline, 'ms': sw.elapsedMilliseconds});
    expect(offline, contains('banka'));

    // A download attempt now fails with a clear message, nothing broken.
    await mt.closeEngine();
    final cfg = File('${mt.modelDir}${Platform.pathSeparator}config.json');
    final keep = cfg.readAsBytesSync();
    cfg.deleteSync();
    mt = OfflineMt.test(opusEnTr)..init(dir);
    expect(mt.installed, isFalse);
    expect(await mt.download(), isFalse);
    expect(mt.state.status, OfflineMtStatus.failed);
    step('downloadWhileOffline', mt.state.errorTr);
    expect(Directory(mt.modelDir!).listSync(recursive: true).where((e) => e.path.endsWith('.part')), isEmpty);
    cfg.writeAsBytesSync(keep);
    mt = OfflineMt.test(opusEnTr)..init(dir);
    expect(mt.installed, isTrue);

    // The learner's records are as they were.
    final before = jsonDecode(File('${dir.path}/before.json').readAsStringSync()) as Map<String, dynamic>;
    expect(_learnerRows(user), before);
    expect(user.statuses['river'], WordStatus.learning);
    step('learnerRecordsUnchanged', true);

    // Deleting without the internet.
    await mt.remove(user);
    expect(Directory(mt.modelDir!).existsSync(), isFalse);
    expect(mt.active(user), isFalse);
    expect(user.mtCached(opusEnTr.engine, 'en>tr', 'The plane took off at noon.'), first);
    step('deleted', true);
    user.db.close();
  }, skip: live && phase == 'offline' ? null : 'runs as MT_LIVE_PHASE=offline after the online phase', timeout: const Timeout(Duration(minutes: 10)));
}

/// Row counts and contents of the learner's own tables (not the
/// translation cache or settings).
Map<String, Object?> _learnerRows(UserDb u) => {
      for (final t in ['words', 'books', 'paras', 'sentence_ai', 'expr_ai', 'ctx_ai', 'ai_meaning', 'wfam_ai', 'missing_tr', 'sense_feedback'])
        t: u.db.select('SELECT * FROM $t').map((r) => r.values.join('|')).join('\n'),
    };
