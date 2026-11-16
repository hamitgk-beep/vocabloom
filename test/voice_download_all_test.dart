import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/tts/speech.dart';
import 'package:kelime_okur/tts/voices.dart';

/// All voice packs are fetched at start, small ones first, except the ones
/// the user deleted.
void main() {
  test('downloadAll asks for every pack, skips removed ones', () async {
    final asked = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) {
      asked.add(r.uri.pathSegments.last);
      r.response
        ..statusCode = 404
        ..close();
    });
    final base = 'http://127.0.0.1:${server.port}';
    final dir = Directory.systemTemp.createTempSync('voice_all');
    final s = Speech.instance..init(dir, UserDb.open(dir));
    await s.downloadAll(url: (pk) => '$base/${pk.id}.zip');
    expect(asked, ['piper-en-libritts-v1.zip', 'ema-tr-v1.zip', 'piper-tr-fahrettin.zip', 'kokoro-en-fp32-v1.zip']);
    expect(voicePacks.every((pk) => s.stateOf(pk) == PackState.failed), isTrue);

    await s.deletePack(emaPack);
    asked.clear();
    await s.downloadAll(url: (pk) => '$base/${pk.id}.zip');
    expect(asked, isNot(contains('ema-tr-v1.zip')));
    expect(asked, hasLength(3));

    // Downloading it again by hand brings it back into the automatic set.
    await s.download(emaPack, url: '$base/ema-tr-v1.zip');
    asked.clear();
    await s.downloadAll(url: (pk) => '$base/${pk.id}.zip');
    expect(asked, contains('ema-tr-v1.zip'));
    await server.close(force: true);
  });
}
