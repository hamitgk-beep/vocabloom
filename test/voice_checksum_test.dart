import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/tts/voice_checksum.dart';
import 'package:path/path.dart' as p;

/// tools/release/voice_checksums.py writes voice-models.json; the app reads
/// the SHA-256 of a pack from it and checks the downloaded zip.
void main() {
  test('the release list gives each pack its SHA-256, and a missing list or pack gives none', () async {
    final tmp = Directory.systemTemp.createTempSync('vb_voice_sha');
    final zip = File(p.join(tmp.path, 'piper-tr-fahrettin.zip'))..writeAsBytesSync(List.generate(5000, (i) => i % 251));
    final py = Platform.isWindows ? 'python' : 'python3';
    final r = await Process.run(py, ['-I', 'tools/release/voice_checksums.py', zip.path]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    final listed = jsonDecode(r.stdout as String) as Map;
    expect((listed['packs'] as Map)['piper-tr-fahrettin']['size'], 5000);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      if (req.uri.path == '/voice-models.json') {
        req.response.write(r.stdout);
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });
    final base = 'http://127.0.0.1:${server.port}';
    final want = await expectedVoiceSha('piper-tr-fahrettin', url: '$base/voice-models.json');
    expect(want, sha256.convert(zip.readAsBytesSync()).toString());
    expect(await sha256OfFile(zip.path), want);
    expect(await expectedVoiceSha('kokoro-en-fp32-v1', url: '$base/voice-models.json'), isNull);
    expect(await expectedVoiceSha('piper-tr-fahrettin', url: '$base/missing.json'), isNull);
    await server.close(force: true);
    tmp.deleteSync(recursive: true);
  });
}
