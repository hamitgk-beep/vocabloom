import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/dict_db.dart';

/// Devices copy the bundled dictionary again only when DictDb.version
/// changes. A dictionary change without a new version leaves every installed
/// app on its old copy (the own dictionary then never shows up), so the
/// fingerprint of assets/dict.db is kept next to the version it belongs to.
void main() {
  test('a changed dictionary comes with a new DictDb.version', () {
    final stamp = File('test/fixtures/dict_db.stamp').readAsStringSync().trim().split(' ');
    final sha = sha256.convert(File('assets/dict.db').readAsBytesSync()).toString();
    expect(
      [stamp[0], stamp[1]],
      [DictDb.version, sha],
      reason: 'assets/dict.db or DictDb.version changed. Raise _version in lib/data/dict_db.dart when the dictionary changes, '
          'then write "<version> <sha256 of assets/dict.db>" to test/fixtures/dict_db.stamp.',
    );
  });
}
