/// Reports of words whose Turkish the dictionary lacks.
///
/// The app opens a ready-filled GitHub issue (nothing is sent without the
/// user seeing and submitting it). Only the word, the WordNet sense number and
/// its English definition go in it: no book text, no personal data. The
/// dictionary-data workflow reads open issues titled [missingTitle], translates
/// those senses first and closes the issue once they are in the dictionary.
library;

const missingRepo = 'hamitgk-beep/vocabloom';
const missingTitle = '[eksik-çeviri]';
const missingLabel = 'missing-words';

/// One line per sense: `syn:<id> | <word> | <definition>`; the workflow
/// reads the `syn:` numbers.
String missingReportBody(List<({String lemma, int syn, String? gloss})> items) {
  final b = StringBuffer('Tekrar ekranında Türkçesi sözlükte olmayan anlamlar:\n\n');
  for (final it in items.take(150)) {
    final g = (it.gloss ?? '').replaceAll(RegExp(r'\s+'), ' ');
    b.writeln('- syn:${it.syn} | ${it.lemma} | ${g.length > 90 ? '${g.substring(0, 90)}…' : g}');
  }
  return b.toString();
}

Uri missingReportUrl(List<({String lemma, int syn, String? gloss})> items) {
  final words = items.map((e) => e.lemma).toSet().take(6).join(', ');
  return Uri.https('github.com', '/$missingRepo/issues/new', {
    'title': '$missingTitle $words',
    'labels': missingLabel,
    'body': missingReportBody(items),
  });
}
