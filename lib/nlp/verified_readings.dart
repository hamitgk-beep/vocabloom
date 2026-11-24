// Task 6A: checked readings of the bundled library stories.
//
// Every sentence of the stories that come with the app was read by the engine and the readings were checked one by
// one (tools/library_audit_6a/). This file holds the result: for a sentence, which dictionary meaning a word has
// there, and whether a multi-word match is used as that expression or as separate words. It only chooses among
// meanings the dictionary already has; it never adds Turkish.
//
// Asset: assets/library/verified_6a.json.gz
//   {"v": 1, "s": {"<sentence>": {"w": {"<token>": "<candidate id>" | "-"}, "e": {"<phrase>|<cat>|<t,t>": 1 | 0},
//                                  "m": {"<phrase>|<cat>|<t,t>": "<candidate id>"}}}}
// Token numbers count the sentence's own tokens (SenseQuery.tokens of a reader sentence). "-": no meaning in the
// dictionary fits the word there, so none is shown as the answer. "~": the fitting meaning has no Turkish of its own,
// so the engine's answer stays but is never shown as sure.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

class VerifiedReadings {
  final Map<String, Map<String, dynamic>> _s;
  VerifiedReadings(this._s);

  static const asset = 'assets/library/verified_6a.json.gz';

  int get length => _s.length;

  static VerifiedReadings fromBytes(List<int> gz) {
    final j = jsonDecode(utf8.decode(gzip.decode(gz))) as Map<String, dynamic>;
    final s = (j['s'] as Map).cast<String, dynamic>();
    return VerifiedReadings({for (final e in s.entries) e.key: (e.value as Map).cast<String, dynamic>()});
  }

  /// The bundled file, or null when it is missing or broken (the reader then works as before).
  static Future<VerifiedReadings?> load() async {
    try {
      return fromBytes((await rootBundle.load(asset)).buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  static String _key(String phrase, String cat, List<int> tokens) => '$phrase|$cat|${([...tokens]..sort()).join(',')}';

  /// The checked meaning of token [index] of [sentence]: a candidate id, '-' (no dictionary meaning fits), '~' (the
  /// fitting meaning has no Turkish), or null (not checked).
  String? word(String sentence, int index) => (_s[sentence.trim()]?['w'] as Map?)?['$index'] as String?;

  /// Whether the words [tokens] of [sentence] are used as the expression: true, false, or null (not checked).
  bool? unit(String sentence, String phrase, String cat, List<int> tokens) {
    final v = (_s[sentence.trim()]?['e'] as Map?)?[_key(phrase, cat, tokens)];
    return v == null ? null : v == 1;
  }

  /// The checked meaning of the expression there (a candidate id), or null.
  String? exprMeaning(String sentence, String phrase, String cat, List<int> tokens) =>
      (_s[sentence.trim()]?['m'] as Map?)?[_key(phrase, cat, tokens)] as String?;
}
