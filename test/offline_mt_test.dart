// Offline translation on Windows (OPUS-MT): the SentencePiece tokenizer, the
// download (only after consent, size and license shown first, SHA-256
// checked, cancellable, failures reported), the cache (source, direction and
// model version), where it sits in the translation order, and an evaluation
// of idioms and words with several meanings.
//
// The real-model checks run only when OPUS_MT_DIR (the model folder) and
// ORT_LIB_DIR (a folder with libonnxruntime) are set; the model is never
// part of the repository or the app.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/mt/offline_mt.dart';
import 'package:kelime_okur/mt/opus_mt.dart';
import 'package:kelime_okur/mt/sentencepiece.dart';
import 'package:kelime_okur/ui/ai/device_translation.dart';
import 'package:kelime_okur/ui/offline_mt_page.dart';
import 'package:kelime_okur/ui/settings_page.dart';
import 'package:kelime_okur/ui/theme.dart';
import 'package:sqlite3/sqlite3.dart';

// ------------------------------------------------------- a tiny .spm file

List<int> _varint(int v) {
  final out = <int>[];
  while (v >= 0x80) {
    out.add((v & 0x7F) | 0x80);
    v >>= 7;
  }
  out.add(v);
  return out;
}

List<int> _field(int n, int wire, List<int> body) => [..._varint(n << 3 | wire), if (wire == 2) ..._varint(body.length), ...body];

Uint8List tinySpm(Map<String, double> pieces, {Map<String, int> types = const {}}) {
  final out = <int>[];
  for (final MapEntry(:key, :value) in pieces.entries) {
    final f = ByteData(4)..setFloat32(0, value, Endian.little);
    out.addAll(_field(1, 2, [
      ..._field(1, 2, utf8.encode(key)),
      ..._field(2, 5, f.buffer.asUint8List()),
      ..._field(3, 0, _varint(types[key] ?? 1)),
    ]));
  }
  // normalizer_spec: no character map, dummy prefix, remove extra spaces.
  out.addAll(_field(3, 2, [..._field(1, 2, utf8.encode('identity')), ..._field(3, 0, [1]), ..._field(4, 0, [1])]));
  return Uint8List.fromList(out);
}

// ------------------------------------------------------- a stand-in model

final _a = utf8.encode('{"config": true}');
final _b = List<int>.generate(300000, (i) => i % 251);
MtModelSpec fakeSpec({String? wrongHash}) => MtModelSpec(
      id: 'test-mt',
      repo: 'example/test-mt',
      revision: '0123456789abcdef',
      files: [
        MtFile('config.json', _a.length, sha256.convert(_a).toString()),
        MtFile('onnx/model.onnx', _b.length, wrongHash ?? sha256.convert(_b).toString()),
      ],
      license: 'CC-BY 4.0',
      licenseUrl: 'https://creativecommons.org/licenses/by/4.0/',
      attribution: 'Test model',
    );

/// Serves the two files in 16 KB pieces; [gate] holds the second file.
class FakeServer {
  final asked = <Uri>[];
  Completer<void>? gate;
  Object? error;

  Future<(int?, Stream<List<int>>)> fetch(Uri url) async {
    asked.add(url);
    if (error != null) throw error!;
    final data = url.path.endsWith('config.json') ? _a : _b;
    Stream<List<int>> pieces() async* {
      for (var i = 0; i < data.length; i += 16384) {
        if (i > 0 && gate != null) await gate!.future;
        yield data.sublist(i, i + 16384 > data.length ? data.length : i + 16384);
      }
    }

    return (data.length, pieces());
  }
}

late Directory dir;
late AppState app;

AppState openApp() {
  final d = DictDb();
  d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
  d.load();
  return AppState(d, UserDb.open(dir));
}

String _trLower(String s) => s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

void main() {
  setUp(() {
    dir = Directory.systemTemp.createTempSync('storilex_offline_mt');
    app = openApp();
    OfflineMt.debugSupported = true;
  });

  tearDown(() {
    OfflineMt.debugSupported = null;
    OfflineMt.instance.debugEngine = null;
    // Windows cannot delete an open database file: close it first.
    app.user.db.close();
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // A leftover temporary folder is harmless.
    }
  });

  group('SentencePiece', () {
    final sp = SentencePiece.fromBytes(tinySpm({
      '<unk>': 0,
      '</s>': 0,
      '▁the': -1,
      '▁cat': -2,
      '▁ca': -3,
      't': -3,
      '▁': -4,
      's': -3,
      '.': -1,
    }, types: {'<unk>': 2, '</s>': 3}));

    test('picks the most likely pieces', () {
      expect(sp.encode('The cats.'), isNot(contains('▁the'))); // case matters
      expect(sp.encode('the cats.'), ['▁the', '▁cat', 's', '.']);
    });

    test('spaces are collapsed and marked', () {
      expect(sp.normalize('  the   cat '), '▁the▁cat');
      expect(sp.encode(''), isEmpty);
    });

    test('unknown characters become one unknown piece', () {
      expect(sp.encode('the ÜÜ.'), ['▁the', '▁', 'ÜÜ', '.']);
      expect(sp.isKnown('ÜÜ'), isFalse);
      expect(sp.isKnown('</s>'), isFalse);
    });

    test('decoding joins the pieces', () {
      expect(SentencePiece.decode(['▁Merhaba', '▁dünya', '.']), 'Merhaba dünya.');
    });

    test('a file that is not a model is refused', () {
      expect(() => SentencePiece.fromBytes(Uint8List.fromList([1, 2, 3])), throwsFormatException);
    });
  });

  group('the real model (OPUS_MT_DIR, ORT_LIB_DIR)', () {
    final modelDir = Platform.environment['OPUS_MT_DIR'];
    final libDir = Platform.environment['ORT_LIB_DIR'];
    final skip = modelDir == null ? 'set OPUS_MT_DIR to the model folder' : null;

    test('the tokenizer gives the reference library\'s pieces', () {
      final sp = SentencePiece.fromBytes(File('$modelDir/source.spm').readAsBytesSync());
      final golden = jsonDecode(File('test/fixtures/opus_spm_golden.json').readAsStringSync()) as List;
      for (final e in golden) {
        expect(sp.encode(e['t'] as String), (e['p'] as List).cast<String>(), reason: e['t'] as String);
      }
    }, skip: skip);

    test('idioms and words with several meanings', () {
      final m = OpusMtModel.load(modelDir!, threads: 4, libDir: libDir);
      final cases = (jsonDecode(File('test/fixtures/mt_eval_cases.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();
      final byKind = <String, (int, int)>{};
      final report = <Map<String, Object?>>[];
      for (final c in cases) {
        final tr = m.translate(c['en'] as String) ?? '';
        final t = _trLower(tr);
        final good = (c['good'] as List).cast<String>().any((g) => t.contains(_trLower(g)));
        final bad = (c['bad'] as List).cast<String>().any((b) => t.contains(_trLower(b)));
        final right = good && !bad;
        final k = c['kind'] as String;
        final (r, n) = byKind[k] ?? (0, 0);
        byKind[k] = (r + (right ? 1 : 0), n + 1);
        report.add({'kind': k, 'en': c['en'], 'tr': tr, 'right': right, 'expected': c['opus']});
        // What the model got right must stay right; its known mistakes are
        // listed, so the panel's caption ("machine translation") is honest.
        if (c['opus'] == 'right') expect(right, isTrue, reason: '${c['en']} -> $tr');
      }
      final out = Platform.environment['MT_EVAL_OUT'];
      if (out != null) File(out).writeAsStringSync(const JsonEncoder.withIndent(' ').convert({'byKind': {for (final e in byKind.entries) e.key: {'right': e.value.$1, 'of': e.value.$2}}, 'cases': report}));
      m.close();
    }, skip: skip, timeout: const Timeout(Duration(minutes: 5)));

    test('the isolate translates and then closes', () async {
      final w = await OpusMtWorker.start(modelDir!, threads: 2, libDir: libDir);
      expect(await w.translate('The plane took off at noon.'), contains('kalktı'));
      await w.close();
    }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('download', () {
    test('the pinned model is the measured one, CC-BY 4.0, about 530 MB', () {
      const s = opusEnTr;
      expect(s.license, 'CC-BY 4.0');
      expect(s.revision, hasLength(40));
      expect(s.totalBytes, inInclusiveRange(530000000, 540000000));
      expect(s.files.every((f) => RegExp(r'^[0-9a-f]{64}$').hasMatch(f.sha256)), isTrue);
      expect(s.url(s.files.last).toString(), contains('/resolve/${s.revision}/onnx/decoder_model_int8.onnx'));
      expect(s.engine, 'opus-mt-tc-big-en-tr@ce128ea');
    });

    test('nothing is downloaded by itself', () {
      final mt = OfflineMt.test(fakeSpec())..init(dir);
      expect(mt.installed, isFalse);
      expect(mt.active(app.user), isFalse);
      expect(Directory('${dir.path}/mt').existsSync(), isFalse);
    });

    test('files are checked and moved in place, then the model is ready', () async {
      final server = FakeServer();
      final mt = OfflineMt.test(fakeSpec())..init(dir);
      expect(await mt.download(fetch: server.fetch), isTrue);
      expect(mt.state.status, OfflineMtStatus.ready);
      expect(mt.installed, isTrue);
      expect(File('${mt.modelDir}/onnx/model.onnx').lengthSync(), _b.length);
      expect(Directory(mt.modelDir!).listSync(recursive: true).where((e) => e.path.endsWith('.part')), isEmpty);
      // A restart finds it without downloading again.
      final again = OfflineMt.test(fakeSpec())..init(dir);
      expect(again.installed, isTrue);
      // Still off until the learner turns it on.
      expect(again.active(app.user), isFalse);
      again.setEnabled(app.user, true);
      expect(again.active(app.user), isTrue);
    });

    test('a file with the wrong SHA-256 is not used', () async {
      final mt = OfflineMt.test(fakeSpec(wrongHash: '0' * 64))..init(dir);
      expect(await mt.download(fetch: FakeServer().fetch), isFalse);
      expect(mt.state.status, OfflineMtStatus.failed);
      expect(mt.state.errorEn, contains('SHA-256'));
      expect(File('${mt.modelDir}/onnx/model.onnx').existsSync(), isFalse);
      expect(File('${mt.modelDir}/onnx/model.onnx.part').existsSync(), isFalse);
      expect(mt.installed, isFalse);
    });

    test('a cancelled download leaves no half file and can start again', () async {
      final server = FakeServer()..gate = Completer<void>();
      final mt = OfflineMt.test(fakeSpec())..init(dir);
      final run = mt.download(fetch: server.fetch);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(mt.state.status, OfflineMtStatus.downloading);
      mt.cancel();
      expect(await run, isFalse);
      expect(mt.state.status, OfflineMtStatus.notInstalled);
      expect(File('${mt.modelDir}/onnx/model.onnx.part').existsSync(), isFalse);
      expect(File('${mt.modelDir}/onnx/model.onnx').existsSync(), isFalse);
      // The finished, checked first file is kept.
      expect(File('${mt.modelDir}/config.json').existsSync(), isTrue);
      server.gate = null;
      expect(await mt.download(fetch: server.fetch), isTrue);
      expect(server.asked.where((u) => u.path.endsWith('config.json')), hasLength(1));
    });

    test('no connection: a clear error, nothing installed', () async {
      final mt = OfflineMt.test(fakeSpec())..init(dir);
      expect(await mt.download(fetch: (FakeServer()..error = const SocketException('offline')).fetch), isFalse);
      expect(mt.state.status, OfflineMtStatus.failed);
      expect(mt.state.errorEn, contains('connect'));
      expect(mt.installed, isFalse);
    });

    test('not enough disk space: refused with sizes, nothing downloaded', () async {
      final server = FakeServer();
      final mt = OfflineMt.test(fakeSpec())..init(dir);
      mt.freeSpace = (_) => 1000;
      expect(await mt.download(fetch: server.fetch), isFalse);
      expect(server.asked, isEmpty);
      expect(mt.state.status, OfflineMtStatus.failed);
      expect(mt.state.errorTr, contains('Diskte yeterli yer yok'));
      expect(mt.state.errorTr, contains('MB'));
      expect(mt.state.errorEn, contains('Not enough disk space'));
      expect(Directory(mt.modelDir!).existsSync(), isFalse);
      // Room for what is missing plus the margin: it goes ahead.
      mt.freeSpace = (_) => fakeSpec().totalBytes + OfflineMt.diskMargin;
      expect(await mt.download(fetch: server.fetch), isTrue);
      // Unknown free space (another system): not blocked.
      expect(OfflineMt.diskFree(dir.path), Platform.isWindows ? isNotNull : isNull);
    });

    test('the room needed counts only the files still missing', () async {
      final mt = OfflineMt.test(fakeSpec())..init(dir);
      await mt.download(fetch: FakeServer().fetch);
      File('${mt.modelDir}/onnx/model.onnx').deleteSync();
      int? asked;
      mt.freeSpace = (p) {
        asked = 1;
        return _b.length + OfflineMt.diskMargin;
      };
      expect(await mt.download(fetch: FakeServer().fetch), isTrue);
      expect(asked, 1);
    });

    test('a server error is reported', () async {
      final mt = OfflineMt.test(fakeSpec())..init(dir);
      final server = FakeServer()..error = const MtDownloadError('Sunucu dosyayı vermedi (HTTP 404).', 'The server did not send the file (HTTP 404).');
      expect(await mt.download(fetch: server.fetch), isFalse);
      expect(mt.state.errorEn, contains('404'));
    });

    test('deleting removes the files and turns it off; books and words stay', () async {
      app.user.setWord('river', WordStatus.learning);
      final mt = OfflineMt.test(fakeSpec())..init(dir);
      await mt.download(fetch: FakeServer().fetch);
      mt.setEnabled(app.user, true);
      await mt.remove(app.user);
      expect(Directory(mt.modelDir!).existsSync(), isFalse);
      expect(mt.active(app.user), isFalse);
      expect(app.user.statuses['river'], WordStatus.learning);
    });
  });

  group('translate', () {
    Future<OfflineMt> ready({MtEngine? engine}) async {
      final mt = OfflineMt.test(fakeSpec())..init(dir);
      await mt.download(fetch: FakeServer().fetch);
      mt.setEnabled(app.user, true);
      mt.debugEngine = engine;
      return mt;
    }

    test('saved with source, direction and model version; asked once', () async {
      var calls = 0;
      final mt = await ready(engine: (t) async {
        calls++;
        return 'Uçak öğlen kalktı.';
      });
      expect(await mt.translate(app.user, ' The plane took off at noon. '), 'Uçak öğlen kalktı.');
      expect(await mt.translate(app.user, 'The plane took off at noon.'), 'Uçak öğlen kalktı.');
      expect(calls, 1);
      expect(app.user.mtCached(mt.spec.engine, 'en>tr', 'The plane took off at noon.'), 'Uçak öğlen kalktı.');
      // Another model version or direction never reuses it.
      expect(app.user.mtCached('test-mt@fffffff', 'en>tr', 'The plane took off at noon.'), isNull);
      expect(app.user.mtCached(mt.spec.engine, 'tr>en', 'The plane took off at noon.'), isNull);
    });

    test('off, or not on Windows: nothing is asked', () async {
      var calls = 0;
      final mt = await ready(engine: (t) async {
        calls++;
        return 'x';
      });
      mt.setEnabled(app.user, false);
      expect(await mt.translate(app.user, 'Hello.'), isNull);
      mt.setEnabled(app.user, true);
      OfflineMt.debugSupported = false;
      expect(await mt.translate(app.user, 'Hello.'), isNull);
      expect(calls, 0);
    });

    test('a failure, an echo or a runaway answer shows nothing and is not saved', () async {
      final mt = await ready(engine: (t) async => t.startsWith('Boom') ? throw StateError('x') : t.startsWith('Echo') ? t : 'ha ' * 200);
      expect(await mt.translate(app.user, 'Boom.'), isNull);
      expect(await mt.translate(app.user, 'Echo this.'), isNull);
      expect(await mt.translate(app.user, 'Short.'), isNull);
      expect(app.user.mtCached(mt.spec.engine, 'en>tr', 'Boom.'), isNull);
    });

    test('a helper only: dictionary, word meanings and learning records stay as they were', () async {
      app.user.setWord('bank', WordStatus.learning, context: 'He sat on the bank of the river.');
      app.user.setSentenceAi('He sat on the bank of the river.', 'Nehrin kıyısında oturdu.', null);
      Map<String, String> rows() => {
            for (final t in ['words', 'books', 'paras', 'sentence_ai', 'expr_ai', 'ctx_ai', 'ai_meaning', 'wfam_ai', 'missing_tr', 'sense_feedback'])
              t: app.user.db.select('SELECT * FROM $t').map((r) => r.values.join('|')).join('\n'),
          };
      final before = rows();
      final meaning = app.dict.meaningIn('bank', 'He sat on the bank of the river.').tr;
      final mt = await ready(engine: (t) async => 'Banka nehrin yanındaydı.');
      expect(await mt.translate(app.user, 'He sat on the bank of the river.'), 'Banka nehrin yanındaydı.');
      expect(rows(), before);
      expect(app.dict.meaningIn('bank', 'He sat on the bank of the river.').tr, meaning);
      expect(app.user.sentenceAi('He sat on the bank of the river.')?.$1, 'Nehrin kıyısında oturdu.');
    });

    test('an older user database gains the cache table and keeps its rows', () {
      app.user.setSetting('keep', 'me');
      app.user.db.execute('DROP TABLE mt_cache');
      final again = UserDb.open(dir);
      expect(again.getSetting('keep'), 'me');
      again.setMtCached('e', 'en>tr', 'a', 'b');
      expect(again.mtCached('e', 'en>tr', 'a'), 'b');
      again.db.close();
    });
  });

  group('screens', () {
    Future<void> pump(WidgetTester tester, Widget w) async {
      tester.view.physicalSize = const Size(390 * 2, 900 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: w));
      await tester.pump();
    }

    testWidgets('size and license come before any download; "Cancel" downloads nothing', (tester) async {
      final server = FakeServer();
      final mt = OfflineMt.test(opusEnTr)..init(dir);
      await pump(tester, OfflineMtPage(app: app, mt: mt));
      expect(find.byKey(const ValueKey('offline-mt-size')), findsOneWidget);
      expect(find.textContaining('CC-BY 4.0'), findsWidgets);
      expect(find.textContaining('MB'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('offline-mt-download')));
      await tester.pumpAndSettle();
      final dialog = find.byKey(const ValueKey('offline-mt-consent'));
      expect(dialog, findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.textContaining('CC-BY 4.0')), findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.textContaining('MB')), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('offline-mt-consent-no')));
      await tester.pumpAndSettle();
      expect(server.asked, isEmpty);
      expect(mt.state.status, OfflineMtStatus.notInstalled);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the settings entry is only on Windows', (tester) async {
      OfflineMt.debugSupported = false;
      await pump(tester, SettingsPage(app: app));
      expect(find.byKey(const ValueKey('settings-offline-mt')), findsNothing);
      OfflineMt.debugSupported = true;
      await pump(tester, SettingsPage(app: app, key: const ValueKey('again')));
      await tester.pump();
      expect(find.byKey(const ValueKey('settings-offline-mt'), skipOffstage: false), findsOneWidget);
    });

    testWidgets('the panel line uses the model only when turned on, with no download button', (tester) async {
      final mt = OfflineMt.instance..init(dir);
      mt.debugEngine = (t) async => 'Uçak öğlen kalktı.';
      Widget line() => Scaffold(body: DeviceTranslation(app: app, text: 'The plane took off at noon.', sentence: true));
      // Not downloaded: nothing at all (and no button in the panel).
      await pump(tester, line());
      expect(find.text('Uçak öğlen kalktı.'), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      // Downloaded but off: still nothing.
      mt.debugInstalled = true;
      await tester.pump();
      expect(find.text('Uçak öğlen kalktı.'), findsNothing);
      // Turned on in Settings: the line appears, marked as machine translation.
      mt.setEnabled(app.user, true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Uçak öğlen kalktı.'), findsOneWidget);
      expect(find.textContaining('OPUS-MT'), findsOneWidget);
      expect(app.user.mtCached(mt.spec.engine, 'en>tr', 'The plane took off at noon.'), 'Uçak öğlen kalktı.');
      // Turned off again: gone.
      mt.setEnabled(app.user, false);
      await tester.pump();
      expect(find.text('Uçak öğlen kalktı.'), findsNothing);
      mt.debugInstalled = false;
      expect(tester.takeException(), isNull);
    });

    testWidgets('a single word is never translated by the model', (tester) async {
      final mt = OfflineMt.instance..init(dir);
      var calls = 0;
      mt.debugEngine = (t) async {
        calls++;
        return 'nehir';
      };
      mt.debugInstalled = true;
      mt.setEnabled(app.user, true);
      await pump(tester, Scaffold(body: DeviceTranslation(app: app, text: 'river')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('nehir'), findsNothing);
      expect(calls, 0);
      mt.setEnabled(app.user, false);
      mt.debugInstalled = false;
    });
  });
}
