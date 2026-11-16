import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/tts/speech.dart';
import 'package:path/path.dart' as p;

void main() {
  test('unzipPack writes nested files and refuses paths leaving the folder', () {
    final out = Directory.systemTemp.createTempSync('unzip').path;
    final a = Archive()
      ..add(ArchiveFile.directory('pack/'))
      ..add(ArchiveFile.bytes('pack/tokens.txt', [104, 105]))
      ..add(ArchiveFile.bytes('pack/espeak-ng-data/en_dict', List.filled(70000, 7)));
    unzipPack(ZipDecoder().decodeBytes(ZipEncoder().encodeBytes(a)), out);
    expect(File(p.join(out, 'pack', 'tokens.txt')).readAsStringSync(), 'hi');
    expect(File(p.join(out, 'pack', 'espeak-ng-data', 'en_dict')).lengthSync(), 70000);
    final bad = Archive()..add(ArchiveFile.bytes('../evil.txt', [1]));
    expect(() => unzipPack(bad, out), throwsA(isA<FileSystemException>()));
  });
}
