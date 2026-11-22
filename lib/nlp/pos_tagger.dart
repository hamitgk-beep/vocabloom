/// EXPERIMENTAL (Task 5E), off by default: a part-of-speech tagger for English
/// that runs in plain Dart, without Python or native code.
///
/// An averaged perceptron (the Collins / Honnibal tagger, the same features
/// as NLTK's PerceptronTagger). Its weights are made on a developer machine by
/// tools/nlp_research/pos_perceptron.py from UD English-EWT (CC BY-SA 4.0) and
/// are NOT part of the app: [PosTagger.load] reads them from a file, and when
/// there is no file (or it cannot be read) there is no tagger and the sense
/// engine works exactly as before.
library;

import 'dart:convert';
import 'dart:io';

import 'text.dart';

class PosTagger {
  final Map<String, Map<String, double>> _w;
  final Map<String, String> _tagdict;
  final List<String> _classes;

  PosTagger(this._w, this._tagdict, List<String> classes) : _classes = [...classes]..sort();

  /// The tagger in [path] (gzipped JSON: weights, tagdict, classes), or null
  /// when the file is missing or unreadable. Never throws.
  static PosTagger? load(String path) {
    try {
      final f = File(path);
      if (!f.existsSync()) return null;
      final j = jsonDecode(utf8.decode(gzip.decode(f.readAsBytesSync()))) as Map<String, dynamic>;
      final w = <String, Map<String, double>>{
        for (final e in (j['weights'] as Map<String, dynamic>).entries)
          e.key: {for (final x in (e.value as Map<String, dynamic>).entries) x.key: (x.value as num).toDouble()},
      };
      return PosTagger(w, (j['tagdict'] as Map<String, dynamic>).cast<String, String>(), (j['classes'] as List).cast<String>());
    } catch (_) {
      return null;
    }
  }

  static const _start = ['-START-', '-START2-'], _end = ['-END-', '-END2-'];

  static String _norm(String w) {
    if (w.contains('-') && !w.startsWith('-')) return '!HYPHEN';
    if (RegExp(r'^\d{4}$').hasMatch(w)) return '!YEAR';
    if (w.isNotEmpty && RegExp(r'^\d').hasMatch(w)) return '!DIGITS';
    return w.toLowerCase();
  }

  static String _suf(String s) => s.length <= 3 ? s : s.substring(s.length - 3);

  /// Universal POS tags (NOUN, VERB, ADJ, ADV, PROPN …), one per word.
  List<String> tag(List<String> words) {
    final ctx = [..._start, for (final w in words) _norm(w), ..._end];
    var prev = _start[0], prev2 = _start[1];
    final out = <String>[];
    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      var t = _tagdict[word];
      if (t == null) {
        final k = i + 2;
        final feats = [
          'bias',
          'i suffix ${_suf(word)}',
          'i pref1 ${word.isEmpty ? '' : word[0]}',
          'i-1 tag $prev',
          'i-2 tag $prev2',
          'i tag+i-2 tag $prev $prev2',
          'i word ${ctx[k]}',
          'i-1 tag+i word $prev ${ctx[k]}',
          'i-1 word ${ctx[k - 1]}',
          'i-1 suffix ${_suf(ctx[k - 1])}',
          'i-2 word ${ctx[k - 2]}',
          'i+1 word ${ctx[k + 1]}',
          'i+1 suffix ${_suf(ctx[k + 1])}',
          'i+2 word ${ctx[k + 2]}',
        ];
        final scores = <String, double>{};
        for (final f in feats) {
          final ws = _w[f];
          if (ws == null) continue;
          ws.forEach((label, v) => scores[label] = (scores[label] ?? 0) + v);
        }
        // the best score; ties go to the alphabetically last label, as in NLTK
        String? best;
        var bs = double.negativeInfinity;
        for (final c in _classes) {
          final s = scores[c] ?? 0;
          if (s >= bs) {
            bs = s;
            best = c;
          }
        }
        t = best ?? 'NOUN';
      }
      out.add(t);
      prev2 = prev;
      prev = t;
    }
    return out;
  }

  final _cache = <String, List<String>>{};

  /// The tag of token [i] as n, v, a or r (null for other tags), for the
  /// tokens of one sentence. Remembers the last sentences it tagged.
  String? posAt(List<Token> toks, int i) {
    final key = toks.map((t) => t.text).join('\u0001');
    var tags = _cache[key];
    if (tags == null) {
      tags = tag([for (final t in toks) t.text]);
      if (_cache.length > 64) _cache.remove(_cache.keys.first);
      _cache[key] = tags;
    }
    return switch (tags[i]) { 'NOUN' => 'n', 'VERB' => 'v', 'ADJ' => 'a', 'ADV' => 'r', _ => null };
  }
}
