// The offline translation end to end with the real model, the way a learner
// on Windows meets it: cancel a download, download it (each file checked
// against its SHA-256), the first translation, using it again without the
// internet, reopening the app, and deleting the model.
//
// It downloads about 530 MB, so it runs only when OPUS_MT_LIVE=1 (the
// Windows CI job sets it, with SHERPA_ONNX_LIB_DIR pointing at the ONNX
// Runtime the app ships). MT_LIVE_OUT names a file for a short report.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/mt/offline_mt.dart';

void main() {
  final live = Platform.environment['OPUS_MT_LIVE'] == '1';
  final report = <String, Object?>{'os': Platform.operatingSystem, 'osVersion': Platform.operatingSystemVersion};
  late Directory dir;

  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('storilex_mt_live');
    // Off Windows (a developer's machine) the feature is only pretended on.
    if (!Platform.isWindows) OfflineMt.debugSupported = true;
    report['platformSupported'] = OfflineMt.platformSupported;
  });

  tearDownAll(() {
    final out = Platform.environment['MT_LIVE_OUT'];
    if (out != null) File(out).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(report));
    OfflineMt.debugSupported = null;
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

    // 5. Off until turned on; then the first translation.
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

    // 6. Reopening the app: found on disk, still on, nothing downloaded.
    mt.debugEngine = null;
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
  }, skip: live ? null : 'set OPUS_MT_LIVE=1 (downloads about 530 MB)', timeout: const Timeout(Duration(minutes: 20)));
}

/// Row counts and contents of the learner's own tables (not the
/// translation cache or settings).
Map<String, Object?> _learnerRows(UserDb u) => {
      for (final t in ['words', 'books', 'paras', 'sentence_ai', 'expr_ai', 'ctx_ai', 'ai_meaning', 'wfam_ai', 'missing_tr', 'sense_feedback'])
        t: u.db.select('SELECT * FROM $t').map((r) => r.values.join('|')).join('\n'),
    };
