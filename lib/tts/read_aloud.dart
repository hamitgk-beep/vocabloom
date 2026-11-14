import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/user_db.dart';
import '../nlp/text.dart';
import 'speech.dart';

/// One spoken piece of the chapter (a sentence, or a clause of a long one): paragraph index and [start, end) in its text.
typedef SpokenSentence = ({int para, int start, int end});

/// Reads the open chapter aloud sentence by sentence. The next sentences are
/// synthesized while the current one plays, so reading flows without gaps.
class ReadAloud extends ChangeNotifier {
  final List<Para> Function() paras;

  /// Opens the next chapter; returns false at the end of the book.
  final Future<bool> Function() nextChapter;

  ReadAloud({required this.paras, required this.nextChapter});

  final speech = Speech.instance;
  bool active = false;
  bool paused = false;

  /// Paused because a word was being said; resumes on [toggle].
  bool _interrupted = false;
  List<SpokenSentence> _items = [];
  int _idx = 0;
  int _gen = 0;
  final _pending = <int, Future<String>>{};

  SpokenSentence? get current => active && _idx < _items.length ? _items[_idx] : null;

  /// Sentence currently read in paragraph [para], if any.
  (int, int)? rangeIn(int para) {
    final c = current;
    return c != null && c.para == para ? (c.start, c.end) : null;
  }

  List<SpokenSentence> _build(int fromPara) {
    final ps = paras();
    return [
      for (var i = fromPara; i < ps.length; i++)
        for (final r in sentenceRanges(ps[i].text))
          if (RegExp(r'[A-Za-z0-9]').hasMatch(ps[i].text.substring(r.$1, r.$2)))
            for (final c in speechChunks(ps[i].text, r.$1, r.$2)) (para: i, start: c.$1, end: c.$2),
    ];
  }

  String _text(SpokenSentence s) => paras()[s.para].text.substring(s.start, s.end).trim();

  /// Starts reading at paragraph [fromPara] of the open chapter.
  void start(int fromPara) {
    _items = _build(fromPara);
    _idx = 0;
    active = true;
    paused = false;
    _interrupted = false;
    speech.onSay = _onWordSaid;
    _restart();
  }

  void _onWordSaid() {
    if (!active || paused) return;
    _gen++;
    _discard();
    paused = true;
    _interrupted = true;
    notifyListeners();
  }

  void _discard() {
    speech.clearQueue();
    for (final f in _pending.values) {
      f.then((p) => _deleteQuietly(p), onError: (_) {});
    }
    _pending.clear();
  }

  static void _deleteQuietly(String path) {
    try {
      File(path).deleteSync();
    } catch (_) {}
  }

  Future<String> _future(int i) => _pending.putIfAbsent(i, () {
    final f = speech.synth(_text(_items[i]));
    f.ignore();
    return f;
  });

  void _restart() {
    final gen = ++_gen;
    notifyListeners();
    unawaited(_loop(gen));
  }

  Future<void> _loop(int gen) async {
    while (active && gen == _gen) {
      if (_idx >= _items.length) {
        _discard();
        if (!await nextChapter() || gen != _gen) {
          if (gen == _gen) stop();
          return;
        }
        _items = _build(0);
        _idx = 0;
        notifyListeners();
        continue;
      }
      final f = _future(_idx);
      for (var k = 1; k <= 2 && _idx + k < _items.length; k++) {
        _future(_idx + k);
      }
      notifyListeners();
      String path;
      try {
        path = await f;
      } catch (_) {
        if (gen != _gen) return;
        _pending.remove(_idx);
        _idx++;
        continue;
      }
      if (gen != _gen) {
        _deleteQuietly(path);
        return;
      }
      _pending.remove(_idx);
      await speech.playFile(path);
      if (gen != _gen) return;
      _idx++;
    }
  }

  /// Play / pause.
  Future<void> toggle() async {
    if (!active) return;
    if (paused) {
      paused = false;
      if (_interrupted) {
        _interrupted = false;
        _restart();
      } else {
        await speech.resume();
        notifyListeners();
      }
    } else {
      paused = true;
      await speech.pause();
      notifyListeners();
    }
  }

  /// Jumps [delta] sentences forward or back.
  Future<void> skip(int delta) async {
    if (!active) return;
    _gen++;
    _discard();
    await speech.stop();
    _idx = (_idx + delta).clamp(0, _items.isEmpty ? 0 : _items.length - 1);
    paused = false;
    _interrupted = false;
    _restart();
  }

  void stop() {
    if (!active) return;
    active = false;
    paused = false;
    _gen++;
    _discard();
    if (speech.onSay == _onWordSaid) speech.onSay = null;
    unawaited(speech.stop());
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}

/// Splits a long sentence [start, end) of [text] at commas, semicolons and
/// colons into clauses of at least a few words, so speech starts sooner and
/// each piece is short enough to repeat (shadowing).
List<(int, int)> speechChunks(String text, int start, int end, {int maxWords = 12, int minWords = 4}) {
  int words(int a, int b) => RegExp(r"[A-Za-z0-9']+").allMatches(text.substring(a, b)).length;
  if (words(start, end) <= maxWords) return [(start, end)];
  final out = <(int, int)>[];
  var from = start;
  for (final m in RegExp(r'[,;:\u2014]\s').allMatches(text.substring(start, end))) {
    final cut = start + m.end;
    if (words(from, cut) >= minWords && words(cut, end) >= minWords) {
      out.add((from, cut));
      from = cut;
    }
  }
  out.add((from, end));
  return out;
}
