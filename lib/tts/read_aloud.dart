import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../data/user_db.dart';
import '../nlp/text.dart';
import 'speech.dart';
import 'wav.dart';

/// One spoken piece of the chapter (a sentence, or a clause of a long one): paragraph index and [start, end) in its text.
typedef SpokenSentence = ({int para, int start, int end});

/// Reads the open chapter aloud sentence by sentence. The next sentences are
/// made while the current ones play and are joined into one clip with a
/// natural pause (a breath) between sentences, so reading flows like a person
/// reading, without the player stopping and starting at every sentence.
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

  /// Completes when playback may go on (set while paused between pieces).
  Completer<void>? _held;

  void _release() {
    final h = _held;
    _held = null;
    if (h != null && !h.isCompleted) h.complete();
  }

  SpokenSentence? get current => active && _idx < _items.length ? _items[_idx] : null;

  /// How far the reading is through the chapter, 0 to 1.
  double get chapterProgress {
    final c = current;
    final n = paras().length;
    return c == null || n == 0 ? 0 : ((c.para + 1) / n).clamp(0.0, 1.0);
  }

  /// Sentence currently read in paragraph [para], if any.
  (int, int)? rangeIn(int para) {
    final c = current;
    return c != null && c.para == para ? (c.start, c.end) : null;
  }

  List<SpokenSentence> _build(int fromPara) {
    final ps = paras();
    return [
      for (var i = fromPara; i < ps.length; i++)
        if (ps[i].kind != 'i')
        for (final r in sentenceRanges(ps[i].text))
          if (RegExp(r'[A-Za-z0-9]').hasMatch(ps[i].text.substring(r.$1, r.$2)))
            for (final c in speechChunks(ps[i].text, r.$1, r.$2, maxWords: 22)) (para: i, start: c.$1, end: c.$2),
    ];
  }

  /// Reading starts (or restarts) at [_idx] and nothing is made yet: a long
  /// first sentence is said in clauses so the voice starts quickly.
  void _splitColdStart() {
    if (_idx >= _items.length || _pending.containsKey(_idx)) return;
    final it = _items[_idx];
    final parts = speechChunks(paras()[it.para].text, it.start, it.end);
    if (parts.length < 2) return;
    _items.replaceRange(_idx, _idx + 1, [for (final c in parts) (para: it.para, start: c.$1, end: c.$2)]);
  }

  double _pauseAfter(int i) {
    final paraEnd = i + 1 >= _items.length || _items[i + 1].para != _items[i].para;
    return pauseAfter(_text(_items[i]), paragraphEnd: paraEnd);
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
    speech.onBackground = _onBackground;
    _restart();
  }

  /// Screen locked or app left: pause, and go on from here on return.
  void _onBackground() {
    if (active && !paused) unawaited(toggle());
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

  /// [urgent]: the listener waits for this piece now.
  Future<String> _future(int i, {bool urgent = false}) => _pending.putIfAbsent(i, () {
    final f = speech.synth(_text(_items[i]), v: speech.voiceFor(speech.bookLang), urgent: urgent);
    f.ignore();
    return f;
  });

  void _restart() {
    final gen = ++_gen;
    _release();
    notifyListeners();
    unawaited(_loop(gen));
  }

  Future<void> _loop(int gen) async {
    var batch = 1; // pieces joined into the next clip: 1 at first, then more
    while (active && gen == _gen) {
      if (_idx >= _items.length) {
        _discard();
        if (!await nextChapter() || gen != _gen) {
          if (gen == _gen) stop();
          return;
        }
        _items = _build(0);
        _idx = 0;
        batch = 1;
        notifyListeners();
        continue;
      }
      final cold = !_pending.containsKey(_idx);
      if (cold) {
        _splitColdStart();
        batch = 1;
      }
      final from = _idx, to = (from + batch).clamp(0, _items.length);
      final futures = [for (var i = from; i < to; i++) _future(i, urgent: cold && i == from)];
      // Meanwhile make the next clip's pieces.
      for (var i = to; i < to + (batch * 2).clamp(1, 6) && i < _items.length; i++) {
        _future(i);
      }
      notifyListeners();
      final paths = <String>[], idxs = <int>[];
      for (var k = 0; k < futures.length; k++) {
        try {
          paths.add(await futures[k]);
          idxs.add(from + k);
        } catch (_) {
          if (gen != _gen) return;
        }
        _pending.remove(from + k);
      }
      if (gen != _gen) {
        paths.forEach(_deleteQuietly);
        return;
      }
      if (paths.isEmpty) {
        _idx = to;
        continue;
      }
      final clip = p.join(Directory.systemTemp.path, 'vocabloom_read_${pid}_${_clipNo++}.wav');
      List<double> starts;
      try {
        final pauses = [for (final i in idxs) _pauseAfter(i)];
        // The next clip starts with a little lead-in silence of its own.
        pauses[pauses.length - 1] = (pauses.last - 0.12).clamp(0.05, 1.0);
        starts = await compute(_join, (paths, pauses, clip));
      } catch (_) {
        _idx = to;
        continue;
      } finally {
        paths.forEach(_deleteQuietly);
      }
      if (gen != _gen) {
        _deleteQuietly(clip);
        return;
      }
      if (paused) {
        // Paused while this clip was being made: wait to play it.
        await (_held ??= Completer<void>()).future;
        if (gen != _gen) {
          _deleteQuietly(clip);
          return;
        }
      }
      // Follow the clip's position, so the highlighted sentence is the one heard.
      final sub = speech.position.listen((pos) {
        if (gen != _gen) return;
        final t = pos.inMilliseconds / 1000;
        var k = 0;
        while (k + 1 < starts.length && starts[k + 1] <= t) {
          k++;
        }
        if (_idx != idxs[k]) {
          _idx = idxs[k];
          notifyListeners();
        }
      });
      try {
        await speech.playFile(clip);
      } finally {
        await sub.cancel();
      }
      if (gen != _gen) return;
      _idx = to;
      batch = (batch * 2).clamp(1, 6);
    }
  }

  int _clipNo = 0;

  static List<double> _join((List<String>, List<double>, String) a) => joinWavs(a.$1, a.$2, a.$3);

  /// Play / pause.
  Future<void> toggle() async {
    if (!active) return;
    if (paused) {
      paused = false;
      if (_interrupted) {
        _interrupted = false;
        _restart();
      } else if (_held != null) {
        _release();
        notifyListeners();
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
    _release();
    _discard();
    if (speech.onSay == _onWordSaid) speech.onSay = null;
    if (speech.onBackground == _onBackground) speech.onBackground = null;
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
