import '../l10n.dart';

/// One piece of a Turkish word: the stem or one suffix, with what it does.
class TrPiece {
  final String text;
  final String? tr, en;
  const TrPiece(this.text, [this.tr, this.en]);
  bool get isStem => tr == null;

  /// What the piece does, in the interface language.
  String get note => L(tr ?? '', en ?? '');
}

class _Suffix {
  final Set<String> forms;
  final bool verbSide;
  final int rank;

  /// The side the word is on after this piece (a participle makes a noun).
  final bool? toVerbSide;
  final int? toRank;
  final String tr, en;
  _Suffix(String pattern, this.verbSide, this.rank, this.tr, this.en, {this.toVerbSide, this.toRank}) : forms = _expand(pattern);
}

/// "(y)AcAk" → yacak, yecek, acak, ecek. A: a/e, I: ı/i/u/ü, D: d/t, C: c/ç,
/// G: k/ğ, a part in brackets may be missing; "|" separates other shapes.
Set<String> _expand(String pattern) {
  final out = <String>{};
  for (final alt in pattern.split('|')) {
    var parts = <String>[''];
    final rx = RegExp(r'\(([^)]*)\)|([^()]+)');
    for (final m in rx.allMatches(alt)) {
      if (m.group(1) != null) {
        parts = [for (final p in parts) ...[p, p + m.group(1)!]];
      } else {
        parts = [for (final p in parts) p + m.group(2)!];
      }
    }
    for (final p in parts) {
      var vs = <String>[''];
      for (final ch in p.split('')) {
        final opts = switch (ch) {
          'A' => ['a', 'e'],
          'I' => ['ı', 'i', 'u', 'ü'],
          'D' => ['d', 't'],
          'C' => ['c', 'ç'],
          'G' => ['k', 'ğ'],
          _ => [ch],
        };
        vs = [for (final v in vs) for (final o in opts) v + o];
      }
      out.addAll(vs.where((v) => v.isNotEmpty));
    }
  }
  return out;
}

// Verb side ranks: 1 voice, 2 negative, 3 ability, 4 tense, 5 second tense, 6 person.
// Noun side ranks: 1 making a word, 2 plural, 3 possessive, 4 case, 5 -ki, 6 copula tense, 7 person.
final List<_Suffix> _suffixes = [
  _Suffix('Il|In|n', true, 1, 'edilgen (yapılan iş)', 'passive (is done)'),
  _Suffix('DIr|t', true, 1, 'ettirgen (yaptırma)', 'causative (make someone do)'),
  _Suffix('Iş', true, 1, 'işteş (birlikte / karşılıklı)', 'reciprocal (together, each other)'),
  _Suffix('mA', true, 2, 'olumsuz', 'negative (not)'),
  _Suffix('(y)Abil', true, 3, 'yeterlilik (-ebilmek)', 'can, be able to'),
  _Suffix('(y)AmA', true, 3, 'yapamama', 'cannot'),
  _Suffix('DI', true, 4, 'geçmiş zaman (görülen)', 'past tense (witnessed)'),
  _Suffix('mIş', true, 4, 'geçmiş zaman (duyulan / sonradan öğrenilen)', 'past tense (reported or inferred)'),
  _Suffix('(I)yor', true, 4, 'şimdiki zaman', 'present continuous (-ing)'),
  _Suffix('(y)AcAG', true, 4, 'gelecek zaman', 'future (will)'),
  _Suffix('Ar|Ir|r', true, 4, 'geniş zaman', 'simple present / habit'),
  _Suffix('mAz', true, 4, 'geniş zaman, olumsuz', 'simple present, negative (does not)'),
  _Suffix('mAlI', true, 4, 'gereklilik', 'must, have to'),
  _Suffix('mAktA', true, 4, 'şimdiki zaman (yazı dili)', 'present continuous (formal)'),
  _Suffix('sA', true, 4, 'şart (-se)', 'if'),
  _Suffix('(y)A', true, 4, 'istek (-e, -elim)', 'wish, let (optative)'),
  _Suffix('(y)DI', true, 5, 'hikâye (-di): geçmişte', 'was (past of the tense before)'),
  _Suffix('(y)mIş', true, 5, 'rivayet (-miş): duyulan', 'reportedly'),
  _Suffix('(y)sA', true, 5, 'şart (-se)', 'if'),
  _Suffix('(y)Im|m', true, 6, 'kişi: ben', 'person: I'),
  _Suffix('sIn|n', true, 6, 'kişi: sen', 'person: you'),
  _Suffix('(y)Iz|k', true, 6, 'kişi: biz', 'person: we'),
  _Suffix('sInIz|nIz', true, 6, 'kişi: siz', 'person: you (plural / polite)'),
  _Suffix('lAr', true, 6, 'kişi: onlar', 'person: they'),
  _Suffix('DIr', true, 6, 'kesinlik / genel doğru (-dır)', 'certainty, a stated fact (formal "is")'),
  _Suffix('(y)Ip', true, 7, 'zarf-fiil: -ip (yapıp da)', 'and then (-ip)'),
  _Suffix('(y)ArAk', true, 7, 'zarf-fiil: -arak (yaparak)', 'by doing, while (-arak)'),
  _Suffix('(y)IncA', true, 7, 'zarf-fiil: -ince (yapınca)', 'when, as soon as (-ince)'),
  _Suffix('mAdAn', true, 7, 'zarf-fiil: -meden (yapmadan)', 'without doing, before (-meden)'),
  _Suffix('(y)ken', true, 7, 'zarf-fiil: -ken (yaparken)', 'while (-ken)'),
  _Suffix('DIG', true, 4, 'sıfat-fiil: -dik (yaptığı)', 'participle: that (someone) did (-dik)', toVerbSide: false, toRank: 2),
  _Suffix('(y)An', true, 4, 'sıfat-fiil: -an (yapan)', 'participle: who does, that does (-an)', toVerbSide: false, toRank: 1),
  _Suffix('(y)AcAG', true, 4, 'sıfat-fiil: -ecek (yapacağı)', 'participle: that will (-ecek)', toVerbSide: false, toRank: 2),
  _Suffix('mAk', true, 4, 'mastar (-mek)', 'infinitive (to …)', toVerbSide: false, toRank: 3),
  _Suffix('mA', true, 4, 'isim-fiil (-me): yapma', 'verbal noun (-ing, doing)', toVerbSide: false, toRank: 1),
  _Suffix('(y)Iş', true, 4, 'isim-fiil (-iş): yapış', 'verbal noun (way of doing)', toVerbSide: false, toRank: 1),
  _Suffix('lIG|lI|sIz', false, 1, 'yapım eki (-lık, -lı, -sız)', 'makes a new word (-ness, with, without)'),
  _Suffix('CI|CIG|DAş|CA', false, 1, 'yapım eki (-cı, -cık, -daş, -ca)', 'makes a new word (-er, little, fellow, -ly)'),
  _Suffix('lAr', false, 2, 'çoğul', 'plural'),
  _Suffix('(I)m', false, 3, 'iyelik: benim', 'possessive: my'),
  _Suffix('(I)n', false, 3, 'iyelik: senin', 'possessive: your'),
  _Suffix('(s)I', false, 3, 'iyelik: onun', 'possessive: his / her / its'),
  _Suffix('(I)mIz', false, 3, 'iyelik: bizim', 'possessive: our'),
  _Suffix('(I)nIz', false, 3, 'iyelik: sizin', 'possessive: your (plural)'),
  _Suffix('lArI', false, 3, 'iyelik: onların', 'possessive: their'),
  _Suffix('(y)I|nI', false, 4, 'belirtme hâli (-ı): onu', 'object marker (the …)'),
  _Suffix('(y)A|nA', false, 4, 'yönelme hâli (-e): -e, -a doğru', 'to, toward'),
  _Suffix('DA|nDA', false, 4, 'bulunma hâli (-de)', 'in, at, on'),
  _Suffix('DAn|nDAn', false, 4, 'ayrılma hâli (-den)', 'from'),
  _Suffix('(n)In', false, 4, 'tamlayan hâli (-in): …nın', 'of, \'s'),
  _Suffix('(y)lA', false, 4, 'vasıta (-le): ile', 'with, by'),
  _Suffix('ki', false, 5, '-ki: …deki, …daki', 'the one (at …), which is (-ki)', toVerbSide: false, toRank: 2),
  _Suffix('(y)DI', false, 6, 'ek-fiil: idi (geçmiş)', 'was'),
  _Suffix('(y)mIş', false, 6, 'ek-fiil: imiş (duyulan)', 'reportedly is / was'),
  _Suffix('(y)sA', false, 6, 'ek-fiil: ise (şart)', 'if (it) is'),
  _Suffix('(y)ken', false, 6, 'ek-fiil: iken', 'while (being)'),
  _Suffix('(y)Im', false, 7, 'kişi: ben', 'person: I am'),
  _Suffix('sIn', false, 7, 'kişi: sen', 'person: you are'),
  _Suffix('(y)Iz', false, 7, 'kişi: biz', 'person: we are'),
  _Suffix('sInIz', false, 7, 'kişi: siz', 'person: you are (plural)'),
  _Suffix('m|n|k|nIz|lAr', false, 7, 'kişi eki', 'person ending'),
  _Suffix('DIr', false, 7, 'ek-fiil: -dır (kesinlik)', 'is (certainty, formal)'),
];

const _soft = {'p': 'b', 'ç': 'c', 't': 'd', 'k': 'ğ'};
const _vowels = 'aeıioöuü';

String _lower(String s) => s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

/// Splits [surface] into its stem (from [lemma]) and suffixes, each with what
/// it does ("sürmüştür" → sür + müş + tür). Null when the word is the base
/// word itself or the suffixes cannot be read. Rule based, so approximate.
List<TrPiece>? trPieces(String surface, String lemma) {
  var w = _lower(surface.split(RegExp("['’]")).join());
  final l = _lower(lemma);
  final verb = l.length > 3 && (l.endsWith('mak') || l.endsWith('mek'));
  final stem = verb ? l.substring(0, l.length - 3) : l;
  if (w == l || w == stem || stem.isEmpty) return null;
  // Where the stem ends in the surface: as is, softened (kitap → kitab-ı),
  // with its last vowel dropped (ağız → ağz-ı), or narrowed (bekle → bekli-yor).
  final starts = <(String, int)>[];
  if (w.startsWith(stem)) starts.add((w.substring(0, stem.length), stem.length));
  final last = stem[stem.length - 1];
  if (_soft.containsKey(last)) {
    final s2 = stem.substring(0, stem.length - 1) + _soft[last]!;
    if (w.startsWith(s2)) starts.add((s2, s2.length));
    if (last == 'k' && w.startsWith('${stem.substring(0, stem.length - 1)}g')) starts.add((w.substring(0, stem.length), stem.length));
  }
  if (stem.length > 3 && _vowels.contains(stem[stem.length - 2])) {
    final s3 = stem.substring(0, stem.length - 2) + last;
    if (w.startsWith(s3)) starts.add((s3, s3.length));
  }
  if (verb && 'ae'.contains(last) && w.length > stem.length && w.substring(stem.length - 1).contains('yor')) {
    final base = stem.substring(0, stem.length - 1);
    for (final v in ['ı', 'i', 'u', 'ü']) {
      if (w.startsWith('$base${v}yor')) starts.add(('$base$v', stem.length));
    }
  }
  for (final (s, n) in starts) {
    final rest = w.substring(n);
    if (rest.isEmpty) continue;
    final parse = _parse(rest, verb, 0);
    if (parse != null) return [TrPiece(surface.length >= n ? surface.substring(0, n) : s), ...parse];
  }
  return null;
}

/// The shortest reading of [rest] as suffixes in their usual order.
List<TrPiece>? _parse(String rest, bool verbSide, int rank, [int depth = 0]) {
  if (rest.isEmpty) return [];
  if (depth > 8) return null;
  List<TrPiece>? best;
  for (final s in _suffixes) {
    if (s.verbSide != verbSide || s.rank < rank || (s.rank == rank && rank > 1)) continue;
    for (final f in s.forms) {
      if (!rest.startsWith(f)) continue;
      // The narrowed vowel of -yor is part of the stem ("bekli-yor").
      final next = _parse(rest.substring(f.length), s.toVerbSide ?? verbSide, s.toRank ?? s.rank, depth + 1);
      if (next == null) continue;
      final cand = [TrPiece(f, s.tr, s.en), ...next];
      // Equal length: the shorter first piece ("yaptığ-ı-nı", not "-ın-ı").
      if (best == null || cand.length < best.length || cand.length == best.length && f.length < best.first.text.length) best = cand;
    }
  }
  return best;
}
