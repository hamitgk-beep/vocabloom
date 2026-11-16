import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/tts/speech.dart';
import 'package:kelime_okur/tts/voices.dart';

/// Windows fallback downloader (curl.exe or PowerShell, chosen by
/// VOCABLOOM_OS_DOWNLOAD) installs a real pack. Windows only.
void main() {
  final mode = Platform.environment['VOCABLOOM_OS_DOWNLOAD'];
  test('voice pack through Windows\' own downloader ($mode)', () async {
    final dir = Directory.systemTemp.createTempSync('osdl');
    final s = Speech.instance..init(dir, UserDb.open(dir));
    await s.download(fahrettinPack);
    expect(s.stateOf(fahrettinPack), PackState.ready, reason: s.errorOf(fahrettinPack));
    final log = File('${dir.path}/voice/log.txt').readAsStringSync();
    // ignore: avoid_print
    print(log);
    expect(log, contains('downloaded with'));
  }, skip: mode == null || !Platform.isWindows ? 'Windows with VOCABLOOM_OS_DOWNLOAD only' : false, timeout: const Timeout(Duration(minutes: 5)));
}
