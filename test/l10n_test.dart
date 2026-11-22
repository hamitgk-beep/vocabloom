// Source check for the interface language: every text a user can read has to
// go through L('Türkçe', 'English') so it follows the app language.
//
//   * Text('…'), tooltip: '…', hintText: '…', labelText: '…', helperText: '…',
//     title: '…', message: '…', semanticLabel: '…' and SnackBar contents in the
//     screens must not hold a fixed sentence or word outside L().
//   * L(tr, en): the English half must not be Turkish (copy-paste slips) and
//     the two halves must not be the same text.
//
// Names, brands and learning examples that are the same in both languages are
// listed in [allowed]. The screen-by-screen check with screenshots is in
// qa_test/language_test.dart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/ai/grammar_practice.dart';
import 'package:kelime_okur/l10n.dart';

/// Texts that are written the same in both languages.
final allowed = <RegExp>[
  RegExp(r'^(VocaBloom|Storilex)'),
  RegExp(r'^(Türkçe|English|Aa|A|BETA|Premium|Normal)$'),
  RegExp(r'^Uygulama dili / App language$'), // findable in either language
  RegExp(r'^• .*\((GPL|CC|WordNet|Apache)'), // licence lines
  // The first-launch demo shows a real word panel.
  RegExp(r'^(give up|narrow|dar, ensiz|vazgeçmek, bırakmak|giving up|He never once thought of | the sea was |stormy|although)$'),
];

/// Where users see text.
bool _isScreenFile(String p) =>
    p.startsWith('lib/ui/') || p == 'lib/main.dart' || p == 'lib/tts/voice_ui.dart';

class Lit {
  final String file;
  final int line;
  final String text;

  /// Call names (and named arguments) the literal sits in, innermost last.
  final List<String> ctx;

  /// The innermost call this literal is an argument of, and which argument.
  final int call, arg;
  Lit(this.file, this.line, this.text, this.ctx, this.call, this.arg);
}

class _Frame {
  final String name;
  final int id;
  int arg = 0;
  _Frame(this.name, this.id);
}

/// A small Dart scanner: string literals with the calls they are passed to.
List<Lit> scan(String path) {
  final s = File(path).readAsStringSync();
  final out = <Lit>[];
  final stack = <_Frame>[];
  var ids = 0;
  var i = 0;
  final n = s.length;
  final word = RegExp(r'[A-Za-z0-9_$.]');

  String identBefore(int j) {
    var k = j - 1;
    while (k >= 0 && s[k] == ' ') {
      k--;
    }
    final e = k + 1;
    while (k >= 0 && word.hasMatch(s[k])) {
      k--;
    }
    return s.substring(k + 1, e);
  }

  /// The named argument ("tooltip:") right before position j, if any.
  String namedBefore(int j) {
    final m = RegExp(r'(\w+)\s*:\s*$').firstMatch(s.substring(j - 40 < 0 ? 0 : j - 40, j));
    return m == null ? '' : '${m[1]}:';
  }

  while (i < n) {
    final c = s[i];
    if (s.startsWith('//', i)) {
      final j = s.indexOf('\n', i);
      i = j < 0 ? n : j;
      continue;
    }
    if (s.startsWith('/*', i)) {
      final j = s.indexOf('*/', i);
      i = j < 0 ? n : j + 2;
      continue;
    }
    if (c == '(' || c == '[' || c == '{') {
      stack.add(_Frame(c == '(' ? identBefore(i) : c, ids++));
      i++;
      continue;
    }
    if (c == ')' || c == ']' || c == '}') {
      if (stack.isNotEmpty) stack.removeLast();
      i++;
      continue;
    }
    if (c == ',' && stack.isNotEmpty) {
      stack.last.arg++;
      i++;
      continue;
    }
    var raw = false;
    final start = i;
    if (c == 'r' && i + 1 < n && (s[i + 1] == "'" || s[i + 1] == '"') && (i == 0 || !RegExp(r'\w').hasMatch(s[i - 1]))) {
      raw = true;
      i++;
    }
    final q0 = s[i];
    if (q0 == "'" || q0 == '"') {
      final q = s.startsWith(q0 * 3, i) ? q0 * 3 : q0;
      var j = i + q.length;
      final b = StringBuffer();
      while (j < n) {
        if (!raw && s[j] == r'\') {
          b.write(s[j + 1]);
          j += 2;
          continue;
        }
        if (!raw && s.startsWith(r'${', j)) {
          var d = 1;
          j += 2;
          while (j < n && d > 0) {
            if (s[j] == '{') d++;
            if (s[j] == '}') d--;
            j++;
          }
          b.write('{}');
          continue;
        }
        if (!raw && s[j] == r'$') {
          j++;
          while (j < n && RegExp(r'\w').hasMatch(s[j])) {
            j++;
          }
          b.write('{}');
          continue;
        }
        if (s.startsWith(q, j)) break;
        b.write(s[j]);
        j++;
      }
      final line = '\n'.allMatches(s.substring(0, start)).length + 1;
      out.add(Lit(path, line, b.toString(), [for (final f in stack) f.name, namedBefore(start)],
          stack.isEmpty ? -1 : stack.last.id, stack.isEmpty ? -1 : stack.last.arg));
      i = j + q.length;
      continue;
    }
    i++;
  }
  return out;
}

final _trLetters = RegExp(r'[çğışöüÇĞİŞÖÜ]');

/// Words a reader would see: at least one word of three letters that is not
/// a placeholder.
bool _hasWords(String t) => RegExp(r'[A-Za-zÇĞİÖŞÜçğıöşü]{3,}').hasMatch(t.replaceAll('{}', ''));

const _sinks = {'Text', 'tooltip:', 'hintText:', 'labelText:', 'helperText:', 'message:', 'semanticLabel:', 'title:', 'label:', 'SnackBar'};

void main() {
  final files = [
    for (final f in Directory('lib').listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart')) f.path.replaceAll(r'\', '/')
  ]..sort();
  final lits = [for (final f in files) ...scan(f)];

  test('screens have no fixed text outside L()', () {
    final bad = <String>[];
    for (final l in lits) {
      if (!_isScreenFile(l.file)) continue;
      if (l.ctx.contains('L') || l.ctx.contains('chapterName')) continue;
      if (!_hasWords(l.text)) continue;
      if (allowed.any((r) => r.hasMatch(l.text))) continue;
      // Only text handed to something that shows it.
      final shown = l.ctx.isNotEmpty && (_sinks.contains(l.ctx.last) || (l.ctx.length > 1 && _sinks.contains(l.ctx[l.ctx.length - 2])));
      if (!shown) continue;
      // Keys, settings names, URLs and file paths are not shown.
      if (RegExp(r'^[\w./:{}-]+$').hasMatch(l.text) && !_trLetters.hasMatch(l.text) && l.text.toLowerCase() == l.text) continue;
      bad.add('${l.file}:${l.line}  "${l.text}"');
    }
    expect(bad, isEmpty, reason: 'Wrap these in L(\'Türkçe\', \'English\'):\n${bad.join('\n')}');
  });

  test("L(): the English half is English and differs from the Turkish", () {
    final bad = <String>[];
    for (final f in files) {
      // The literal parts of each L(tr, en) call, joined per argument.
      final calls = <int, Map<int, (int, String)>>{};
      for (final l in scan(f)) {
        if (l.ctx.length < 2 || l.ctx[l.ctx.length - 2] != 'L' || l.arg > 1) continue;
        final m = calls.putIfAbsent(l.call, () => {});
        final prev = m[l.arg];
        m[l.arg] = (prev?.$1 ?? l.line, '${prev?.$2 ?? ''}${l.text}');
      }
      for (final m in calls.values) {
        final tr = m[0], en = m[1];
        if (tr == null || en == null || !_hasWords(tr.$2)) continue;
        // English half: no Turkish outside quotes and names.
        final plain = en.$2
            .replaceAll(RegExp(r'"[^"]*"|“[^”]*”'), '')
            .replaceAll(RegExp(r'Türkçe|Türk|Fahrettin|Fettah|Özyeğin|Ayşe|Gök|Yapay Zekâ'), '');
        if (_trLetters.hasMatch(plain)) bad.add('$f:${en.$1}  English text looks Turkish: "${en.$2}"');
        if (tr.$2 == en.$2 && !allowed.any((r) => r.hasMatch(tr.$2))) {
          bad.add('$f:${tr.$1}  same text in both languages: "${tr.$2}"');
        }
      }
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('every grammar lesson has its English explanation, patterns and notes', () {
    final topics = parseGrammarTopics(
        File('assets/grammar/lessons.json').readAsStringSync(), File('assets/grammar/lessons_en.json').readAsStringSync());
    final bad = <String>[];
    for (final t in topics) {
      if (t.explanationEn.isEmpty) bad.add('${t.id}: no English explanation');
      if (t.structureEn.length != t.structureTr.length) bad.add('${t.id}: ${t.structureEn.length} English patterns for ${t.structureTr.length}');
      for (final e in t.exercises) {
        if (e.noteTr.isNotEmpty && e.noteEn.isEmpty) bad.add('${e.id}: no English note');
      }
      final en = [t.explanationEn, ...t.structureEn, for (final e in t.exercises) e.noteEn]
          .join('\n')
          .replaceAll(RegExp(r'"[^"]*"'), '');
      if (RegExp(r'\b(özne|fiil|isim|cümle|zaman|için|ile)\b').hasMatch(en)) bad.add('${t.id}: Turkish words in the English text');
    }
    uiEnglish = true;
    expect(topics.first.explanation, topics.first.explanationEn);
    uiEnglish = false;
    expect(topics.first.explanation, topics.first.explanationTr);
    expect(bad, isEmpty, reason: bad.join('\n'));
  });
}
