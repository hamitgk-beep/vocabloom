import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/l10n.dart';
import 'package:kelime_okur/online/update_check.dart';

/// The release job writes the body with tools/release/release_notes.py; the
/// app reads the "what's new" list back out of it.
void main() {
  final tmp = Directory.systemTemp.createTempSync('vb_notes');

  Future<String> body(int build, {String prev = '', List<String> commits = const []}) async {
    File('${tmp.path}/prev.md').writeAsStringSync(prev);
    File('${tmp.path}/commits.txt').writeAsStringSync(commits.join('\n'));
    final r = await Process.run('python3', [
      'tools/release/release_notes.py', '--version', '1.$build', '--build', '$build',
      '--prev-body', '${tmp.path}/prev.md', '--commits', '${tmp.path}/commits.txt',
    ]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    return r.stdout as String;
  }

  test('new entries get the build that ships them, older ones keep theirs', () async {
    final first = await body(100, commits: ['Dictionary: 1424 new Turkish meanings', 'Fix a bug (#50)']);
    // Old app versions read the build and version from the first line.
    expect(first, startsWith('Sürüm 1.100 · Build: 100.'));
    expect(first, contains('## Yenilikler'));
    final notes = parseReleaseNotes(first);
    expect(notes, isNotEmpty);
    expect(notes.every((n) => n.build == 100), isTrue);
    final dict = notes.where((n) => n.area == 'dictionary' && n.tr.contains('1.424 yeni Türkçe anlam'));
    expect(dict, hasLength(1));

    final second = await body(101, prev: first, commits: ['Dictionary: 900 new Turkish meanings']);
    final all = parseReleaseNotes(second);
    expect(all.first.build, 101);
    expect(all.where((n) => n.tr.contains('1.424')).single.build, 100);
    // Someone on build 100 sees only what build 101 adds.
    final fresh = parseReleaseNotes(second, sinceBuild: 100);
    expect(fresh.map((n) => n.tr), ['Sözlüğe 900 yeni Türkçe anlam eklendi.']);
  });

  test('notes follow the interface language; old release bodies have none', () {
    const n = ReleaseNote('grammar', 'Yeni konular', 'New topics', 5);
    uiEnglish = true;
    expect((n.text, n.areaName), ('New topics', 'Grammar'));
    uiEnglish = false;
    expect((n.text, n.areaName), ('Yeni konular', 'Gramer'));
    expect(parseReleaseNotes("Sürüm 1.3 · Build: 90. Windows: zip'i aç"), isEmpty);
  });
}
