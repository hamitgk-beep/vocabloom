/// Repairs words that a PDF's text layer glued together ("a pole witha rice
/// basket"). Many PDFs place each word with a position instead of a space
/// character, and PDFium sometimes misses the gap. Two fixes, both checked
/// against the dictionary so real words are never broken:
///
/// * [addGapSpaces] uses where the letters are on the page: a space goes in
///   where there is a visible gap between two letters.
/// * [splitJoinedWords] works on text alone: a token that is not a word but is
///   a preposition plus an article ("witha", "ofthe", "tothe") is split.
library;

typedef GlyphBox = ({double left, double top, double right, double bottom});

final _letter = RegExp(r"[A-Za-z]");
final _edge = RegExp(r"^[^A-Za-z0-9]+|[^A-Za-z0-9]+$");
final _possessive = RegExp(r"['’]s$", caseSensitive: false);

/// Whether a piece of text (maybe with punctuation around it) is a known word,
/// a number, or only punctuation.
bool _pieceOk(String piece, bool Function(String word) isWord) {
  var core = piece.replaceAll(_edge, '');
  if (core.isEmpty) return true;
  if (RegExp(r'^[0-9.,:/%-]+$').hasMatch(core)) return true;
  core = core.replaceAll(_possessive, '');
  if (core.isEmpty) return true;
  if (isWord(core)) return true;
  // Hyphenated compounds: every part must be known.
  if (core.contains('-')) return core.split('-').every((p) => p.isEmpty || isWord(p));
  return false;
}

/// Inserts spaces where two letters on the same line have a visible gap
/// between them and the result is made of known words while the original
/// token is not. [boxes] has one entry per character of [text] (PDF
/// coordinates, top > bottom); generated characters have empty boxes.
String addGapSpaces(String text, List<GlyphBox> boxes, bool Function(String word)? isWord) {
  if (boxes.length != text.length || text.isEmpty) return text;
  bool empty(GlyphBox b) => b.right <= b.left || b.top <= b.bottom;
  final out = StringBuffer();
  var i = 0;
  while (i < text.length) {
    if (text[i].trim().isEmpty) {
      out.write(text[i]);
      i++;
      continue;
    }
    var e = i;
    while (e < text.length && text[e].trim().isNotEmpty) {
      e++;
    }
    final token = text.substring(i, e);
    if (token.length < 3 || (isWord != null && _pieceOk(token, isWord))) {
      out.write(token);
      i = e;
      continue;
    }
    var h = 0.0;
    for (var k = i; k < e; k++) {
      final b = boxes[k];
      if (!empty(b) && b.top - b.bottom > h) h = b.top - b.bottom;
    }
    final strong = <int>[]; // cut positions (index of the first char after the gap)
    final weak = <int>[];
    if (h > 0) {
      for (var k = i + 1; k < e; k++) {
        final a = boxes[k - 1], b = boxes[k];
        if (empty(a) || empty(b)) continue;
        if (!_letter.hasMatch(text[k]) && !_letter.hasMatch(text[k - 1])) continue;
        final overlap = (a.top < b.top ? a.top : b.top) - (a.bottom > b.bottom ? a.bottom : b.bottom);
        final minH = (a.top - a.bottom) < (b.top - b.bottom) ? (a.top - a.bottom) : (b.top - b.bottom);
        if (overlap < minH * 0.3) continue; // not on the same line
        final gap = b.left - a.right;
        if (gap > h * 0.35) {
          strong.add(k);
        } else if (gap > h * 0.18) {
          weak.add(k);
        }
      }
    }
    String cut(List<int> cuts) {
      final sb = StringBuffer();
      var s = i;
      for (final c in cuts) {
        sb
          ..write(text.substring(s, c))
          ..write(' ');
        s = c;
      }
      sb.write(text.substring(s, e));
      return sb.toString();
    }

    bool allOk(String s) => isWord == null || s.split(' ').every((p) => _pieceOk(p, isWord));
    // A clear gap (about a word space) is cut when every piece is a word. A
    // smaller gap is cut only next to an article or a preposition.
    bool small(String piece) {
      final c = piece.replaceAll(_edge, '').toLowerCase();
      return _articles.contains(c) || _before.contains(c);
    }

    String? best;
    if (strong.isNotEmpty && allOk(cut(strong))) {
      best = cut(strong);
    } else if (isWord != null) {
      for (final c in ([...strong, ...weak]..sort())) {
        final s = cut([c]);
        if (allOk(s) && s.split(' ').any(small)) {
          best = s;
          break;
        }
      }
    }
    out.write(best ?? token);
    i = e;
  }
  return out.toString();
}

/// Words that most often lose the space before an article ("witha",
/// "ofthe", "inthe"). Only these, followed by a, an or the, are split.
const _before = {
  'of', 'to', 'in', 'on', 'at', 'by', 'for', 'with', 'from', 'into', 'onto', 'upon', 'and', 'or', 'but', 'as', //
  'is', 'was', 'be', 'been', 'are', 'were', 'has', 'had', 'have', 'that', 'like', 'about', 'over', 'under',
  'through', 'after', 'before', 'without', 'within', 'all', 'what', 'such', 'half', 'once', 'quite', 'rather',
  'than', 'then', 'when', 'where', 'there', 'off', 'out', 'up', 'down', 'near', 'behind', 'across', 'around',
};
const _articles = {'a', 'an', 'the'};

final _token = RegExp(r"[A-Za-z]+");

/// Splits lowercase tokens that are not words into a preposition (or another
/// very common word) and an article: "witha" -> "with a", "ofthe" -> "of the",
/// "tothe" -> "to the". Capitalized tokens are left alone because they may be
/// names, and anything the dictionary knows is kept.
String splitJoinedWords(String text, bool Function(String word) isWord) {
  return text.replaceAllMapped(_token, (m) {
    final w = m.group(0)!;
    if (w.length < 4 || w != w.toLowerCase()) return w;
    // Part of a longer token (apostrophes, digits, hyphens): leave it.
    final s = m.start, e = m.end;
    final glued = RegExp(r"[A-Za-z0-9'’\-_/@.]");
    if ((s > 0 && glued.hasMatch(text[s - 1])) || (e < text.length && glued.hasMatch(text[e]) && text[e] != '.'))
      return w;
    if (isWord(w)) return w;
    String? best;
    for (final art in _articles) {
      if (!w.endsWith(art)) continue;
      final a = w.substring(0, w.length - art.length);
      if (!_before.contains(a)) continue;
      if (best != null) return w; // "ana", "thea": more than one reading, keep it
      best = '$a $art';
    }
    return best ?? w;
  });
}
