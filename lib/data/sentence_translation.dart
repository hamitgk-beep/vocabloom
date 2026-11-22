/// Saved sentence translations of a paragraph, each tied to the English
/// sentence it translates.
///
/// Older versions saved a bare list of Turkish strings and paired it with the
/// paragraph's sentences by position. When the AI joined two sentences (or
/// numbered its answers on after a join), every later Turkish slid onto the
/// next sentence, and nothing could tell. Now every item carries its English
/// source, and a translation is shown only for exactly that sentence: when the
/// paragraph's text or its sentence boundaries change, the old items simply
/// stop matching instead of landing on the wrong sentence.
library;

import 'dart:convert';

/// The English sentence as it is compared: trimmed, spaces folded.
String sentenceKey(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Whether [tr] can be shown as the Turkish of [en]: not empty, and not the
/// English itself handed back by a translator that could not translate it.
bool usableTranslation(String en, String? tr) {
  if (tr == null) return false;
  final t = sentenceKey(tr);
  if (t.isEmpty) return false;
  return t.toLowerCase() != sentenceKey(en).toLowerCase();
}

class SentenceTranslation {
  final String en;
  final String tr;
  const SentenceTranslation(this.en, this.tr);
}

class ParaTranslations {
  /// Sentence pairs (current format). Empty for the legacy format.
  final List<SentenceTranslation> items;

  /// Saved by an older version as a bare list: kept on the device, never
  /// shown, because which sentence each item belongs to is unknown.
  final bool legacy;

  /// What made the translations, e.g. "ai:Gemini/gemini-2.5-flash".
  final String? engine;

  /// Language direction, "en>tr".
  final String dir;

  const ParaTranslations(this.items, {this.legacy = false, this.engine, this.dir = 'en>tr'});

  static const version = 2;

  /// Reads the `paras.tr` column. Null when nothing was saved.
  static ParaTranslations? decode(String? json) {
    if (json == null || json.isEmpty) return null;
    final Object? j;
    try {
      j = jsonDecode(json);
    } catch (_) {
      return const ParaTranslations([], legacy: true);
    }
    if (j is List) return const ParaTranslations([], legacy: true);
    if (j is! Map) return const ParaTranslations([], legacy: true);
    final list = j['items'];
    return ParaTranslations(
      [
        if (list is List)
          for (final e in list)
            if (e is Map) SentenceTranslation('${e['en'] ?? ''}', '${e['tr'] ?? ''}'),
      ],
      engine: j['engine'] as String?,
      dir: (j['dir'] as String?) ?? 'en>tr',
    );
  }

  String encode() => jsonEncode({
        'v': version,
        'dir': dir,
        if (engine != null) 'engine': engine,
        'items': [for (final s in items) {'en': s.en, 'tr': s.tr}],
      });

  /// The Turkish saved for exactly [sentence], or null. Never another
  /// sentence's: the English must match.
  String? forSentence(String sentence) {
    if (legacy) return null;
    final k = sentenceKey(sentence);
    for (final s in items) {
      if (sentenceKey(s.en) == k) return usableTranslation(s.en, s.tr) ? s.tr.trim() : null;
    }
    return null;
  }
}

/// Puts the AI's numbered answers onto [sentences]. Each answer must name its
/// sentence number and repeat the sentence's first words ([src]); an answer
/// whose words belong to another sentence (the model renumbered after joining
/// two sentences) is dropped, so that sentence stays empty instead of showing
/// its neighbour's Turkish.
List<String> alignNumberedTranslations(List<String> sentences, List<({int? i, String? src, String tr})> answers) {
  final out = List.filled(sentences.length, '');
  for (final a in answers) {
    final i = a.i;
    if (i == null || i < 0 || i >= sentences.length) continue;
    final src = a.src;
    if (src != null && src.trim().isNotEmpty && !_sameStart(sentences[i], src)) continue;
    if (out[i].isEmpty && usableTranslation(sentences[i], a.tr)) out[i] = a.tr.trim();
  }
  return out;
}

List<String> _words(String s) =>
    RegExp(r"[A-Za-z0-9ÇĞİÖŞÜçğıöşü]+").allMatches(s.toLowerCase()).map((m) => m.group(0)!).toList();

/// Whether [src] is the start of [sentence]: its first (up to three) words
/// are the sentence's first words.
bool _sameStart(String sentence, String src) {
  final a = _words(sentence), b = _words(src);
  if (b.isEmpty) return true;
  final k = [b.length, a.length, 3].reduce((x, y) => x < y ? x : y);
  if (k == 0) return false;
  for (var x = 0; x < k; x++) {
    if (a[x] != b[x]) return false;
  }
  return true;
}
