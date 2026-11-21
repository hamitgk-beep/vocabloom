/// A small SentencePiece (unigram) tokenizer in Dart, enough for the
/// OPUS-MT / Marian models: it reads the `.spm` model file (a protobuf),
/// normalizes the text with the model's own character map (`nmt_nfkc`),
/// and splits it into the most likely pieces (Viterbi), the same pieces the
/// reference C++ library gives.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Piece types in the model file.
const _normal = 1, _unknown = 2, _control = 3, _userDefined = 4, _unused = 5, _byte = 6;

class SentencePiece {
  /// Piece text -> (score, type).
  final Map<String, (double, int)> _pieces;
  final _Normalizer _norm;
  final bool addDummyPrefix, removeExtraWhitespaces;
  final double _unkScore;
  final int _maxLen;

  SentencePiece._(this._pieces, this._norm, this.addDummyPrefix, this.removeExtraWhitespaces)
      : _unkScore = _pieces.values.fold(0.0, (m, p) => p.$1 < m ? p.$1 : m) - 10.0,
        _maxLen = _pieces.keys.fold(1, (m, k) => k.length > m ? k.length : m);

  /// Reads a `.spm` model file.
  factory SentencePiece.fromBytes(Uint8List bytes) {
    final pieces = <String, (double, int)>{};
    Uint8List? charsmap;
    var dummy = true, extra = true;
    final r = _Pb(bytes);
    while (!r.done) {
      final (field, wire) = r.tag();
      if (field == 1 && wire == 2) {
        final p = _Pb(r.bytes());
        String? text;
        var score = 0.0, type = _normal;
        while (!p.done) {
          final (f, w) = p.tag();
          if (f == 1 && w == 2) {
            text = utf8.decode(p.bytes());
          } else if (f == 2 && w == 5) {
            score = p.float32();
          } else if (f == 3 && w == 0) {
            type = p.varint();
          } else {
            p.skip(w);
          }
        }
        if (text != null) pieces[text] = (score, type);
      } else if (field == 3 && wire == 2) {
        final n = _Pb(r.bytes());
        while (!n.done) {
          final (f, w) = n.tag();
          if (f == 2 && w == 2) {
            charsmap = n.bytes();
          } else if (f == 3 && w == 0) {
            dummy = n.varint() != 0;
          } else if (f == 4 && w == 0) {
            extra = n.varint() != 0;
          } else {
            n.skip(w);
          }
        }
      } else {
        r.skip(wire);
      }
    }
    if (pieces.isEmpty) throw const FormatException('not a SentencePiece model');
    return SentencePiece._(pieces, _Normalizer(charsmap), dummy, extra);
  }

  /// The text as the model sees it: normalized, spaces as "▁".
  String normalize(String text) {
    var t = _norm.apply(text);
    if (removeExtraWhitespaces) t = t.trim().replaceAll(RegExp(r' {2,}'), ' ');
    if (t.isEmpty) return '';
    if (addDummyPrefix) t = ' $t';
    return t.replaceAll(' ', '▁');
  }

  /// The most likely pieces of [text].
  List<String> encode(String text) {
    final s = normalize(text);
    if (s.isEmpty) return const [];
    // Work on Unicode code points, as the reference library does.
    final cps = s.runes.toList();
    final n = cps.length;
    final best = List<double>.filled(n + 1, double.negativeInfinity);
    final from = List<int>.filled(n + 1, -1);
    final piece = List<String?>.filled(n + 1, null);
    best[0] = 0;
    for (var i = 0; i < n; i++) {
      if (best[i] == double.negativeInfinity) continue;
      var matched = false;
      final sb = StringBuffer();
      for (var j = i; j < n && j - i < _maxLen; j++) {
        sb.writeCharCode(cps[j]);
        final p = _pieces[sb.toString()];
        if (p == null) continue;
        final type = p.$2;
        if (type != _normal && type != _userDefined) continue;
        // User-defined pieces always win, as in the reference library.
        final score = best[i] + (type == _userDefined ? 0.0 : p.$1);
        if (score > best[j + 1]) {
          best[j + 1] = score;
          from[j + 1] = i;
          piece[j + 1] = null;
        }
        if (j == i) matched = true;
      }
      if (!matched) {
        // A character the model does not know: one unknown piece.
        final score = best[i] + _unkScore;
        if (score > best[i + 1]) {
          best[i + 1] = score;
          from[i + 1] = i;
          piece[i + 1] = String.fromCharCode(cps[i]);
        }
      }
    }
    final out = <String>[];
    var k = n;
    while (k > 0) {
      final i = from[k];
      out.add(piece[k] ?? String.fromCharCodes(cps.sublist(i, k)));
      k = i;
    }
    // Neighbouring unknown characters make one unknown piece, as in the
    // reference library.
    final merged = <String>[];
    for (final p in out.reversed) {
      if (merged.isNotEmpty && !isKnown(p) && !isKnown(merged.last)) {
        merged[merged.length - 1] += p;
      } else {
        merged.add(p);
      }
    }
    return merged;
  }

  /// Whether [piece] is a normal piece of the model.
  bool isKnown(String piece) {
    final p = _pieces[piece];
    return p != null && p.$2 != _unknown && p.$2 != _control && p.$2 != _unused && p.$2 != _byte;
  }

  /// Text from pieces ("▁Merhaba", "▁dünya", ".") -> "Merhaba dünya.".
  static String decode(Iterable<String> pieces) => pieces.join().replaceAll('▁', ' ').trim();
}

/// The model's precompiled character map: a double-array trie (darts-clone)
/// over UTF-8 bytes, pointing into a block of replacement strings.
class _Normalizer {
  final Uint32List? _trie;
  final Uint8List? _strings;

  _Normalizer._(this._trie, this._strings);

  factory _Normalizer(Uint8List? blob) {
    if (blob == null || blob.length < 4) return _Normalizer._(null, null);
    final bd = ByteData.sublistView(blob);
    final size = bd.getUint32(0, Endian.little);
    if (size % 4 != 0 || 4 + size > blob.length) throw const FormatException('bad character map');
    final trie = Uint32List(size ~/ 4);
    for (var i = 0; i < trie.length; i++) {
      trie[i] = bd.getUint32(4 + i * 4, Endian.little);
    }
    return _Normalizer._(trie, Uint8List.sublistView(blob, 4 + size));
  }

  static int _offset(int u) => (u >> 10) << ((u & (1 << 9)) >> 6);
  static int _label(int u) => u & ((1 << 31) | 0xFF);
  static bool _hasLeaf(int u) => (u >> 8) & 1 == 1;
  static int _value(int u) => u & ((1 << 31) - 1);

  /// The longest match at [start]: (bytes used, replacement offset), or null.
  (int, int)? _longest(Uint8List key, int start) {
    final a = _trie!;
    var pos = 0;
    var unit = a[pos];
    pos ^= _offset(unit);
    (int, int)? found;
    for (var i = start; i < key.length; i++) {
      pos ^= key[i];
      if (pos >= a.length) break;
      unit = a[pos];
      if (_label(unit) != key[i]) break;
      pos ^= _offset(unit);
      if (pos >= a.length) break;
      if (_hasLeaf(unit)) found = (i - start + 1, _value(a[pos]));
    }
    return found;
  }

  String apply(String text) {
    if (_trie == null) return text;
    final s = _strings!;
    final b = Uint8List.fromList(utf8.encode(text));
    final out = BytesBuilder(copy: false);
    var i = 0;
    while (i < b.length) {
      final m = _longest(b, i);
      if (m != null) {
        var e = m.$2;
        while (e < s.length && s[e] != 0) {
          e++;
        }
        out.add(Uint8List.sublistView(s, m.$2, e));
        i += m.$1;
      } else {
        // Copy one UTF-8 character as it is.
        var len = 1;
        final c = b[i];
        if (c >= 0xF0) {
          len = 4;
        } else if (c >= 0xE0) {
          len = 3;
        } else if (c >= 0xC0) {
          len = 2;
        }
        if (i + len > b.length) len = b.length - i;
        out.add(Uint8List.sublistView(b, i, i + len));
        i += len;
      }
    }
    return utf8.decode(out.takeBytes(), allowMalformed: true);
  }
}

/// A minimal protobuf reader.
class _Pb {
  final Uint8List b;
  final ByteData _d;
  int i = 0;
  _Pb(this.b) : _d = ByteData.sublistView(b);

  bool get done => i >= b.length;

  int varint() {
    var shift = 0, out = 0;
    while (true) {
      if (i >= b.length) throw const FormatException('truncated model file');
      final c = b[i++];
      out |= (c & 0x7F) << shift;
      if (c & 0x80 == 0) return out;
      shift += 7;
      if (shift > 63) throw const FormatException('bad varint');
    }
  }

  (int, int) tag() {
    final t = varint();
    return (t >> 3, t & 7);
  }

  Uint8List bytes() {
    final n = varint();
    if (i + n > b.length) throw const FormatException('truncated model file');
    final out = Uint8List.sublistView(b, i, i + n);
    i += n;
    return out;
  }

  double float32() {
    final v = _d.getFloat32(i, Endian.little);
    i += 4;
    return v;
  }

  void skip(int wire) {
    switch (wire) {
      case 0:
        varint();
      case 1:
        i += 8;
      case 2:
        bytes();
      case 5:
        i += 4;
      default:
        throw FormatException('unsupported protobuf wire type $wire');
    }
  }
}
