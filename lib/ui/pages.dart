import '../data/user_db.dart';

/// The pages of a chapter, as paragraph ranges [start, end).
///
/// A book with pages of its own (a PDF) keeps them: each page of the book is
/// a page here. Other books are cut into pages of about [words] words, never
/// inside a paragraph; a picture counts like a short paragraph, and a heading
/// starts a new page when the page already has some text.
List<(int, int)> pagesOf(List<Para> ps, {int words = 230}) {
  if (ps.isEmpty) return const [(0, 0)];
  final out = <(int, int)>[];
  var start = 0;
  if (ps.any((p) => p.page != null)) {
    int? cur;
    for (var i = 0; i < ps.length; i++) {
      final pg = ps[i].page;
      if (pg != null && cur != null && pg != cur && i > start) {
        out.add((start, i));
        start = i;
      }
      cur = pg ?? cur;
    }
    out.add((start, ps.length));
    return out;
  }
  var n = 0;
  for (var i = 0; i < ps.length; i++) {
    final w = ps[i].kind == 'i' ? 110 : ' '.allMatches(ps[i].text).length + 1;
    final full = n > 0 && n + w > words;
    final heading = ps[i].kind == 'h' && n > 40;
    if (i > start && (full || heading)) {
      out.add((start, i));
      start = i;
      n = 0;
    }
    n += w;
  }
  out.add((start, ps.length));
  return out;
}

/// The page that holds paragraph [para].
int pageOfPara(List<(int, int)> pages, int para) {
  for (var i = 0; i < pages.length; i++) {
    if (para < pages[i].$2) return i;
  }
  return pages.length - 1;
}
