import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/tr_en_dict.dart';
import '../data/user_db.dart';
import '../l10n.dart';
import '../nlp/tr_suffixes.dart';
import '../tts/speech.dart';
import '../tts/voice_ui.dart';
import 'meaning_parts.dart';
import 'panel.dart' show enColor;
import 'theme.dart';
import 'word_sheet.dart' show WordContext;

/// Word panel for Turkish books: the tapped Turkish word, its base word, the
/// English meanings from the open Turkish -> English dictionary, Tatoeba
/// example sentences and the learning buttons.
class TrWordPanel extends StatefulWidget {
  final AppState app;
  final String surface;
  final String? lemma;
  final WordContext? ctx;
  final ScrollController? scroll;
  const TrWordPanel({super.key, required this.app, required this.surface, this.lemma, this.ctx, this.scroll});

  @override
  State<TrWordPanel> createState() => _TrWordPanelState();
}

/// Part of speech as Wiktionary names it, in the interface language.
String trPosLabel(String pos) {
  const tr = {
    'noun': 'isim', 'verb': 'fiil', 'adj': 'sıfat', 'adv': 'zarf', 'pron': 'zamir', 'postp': 'edat', 'conj': 'bağlaç',
    'intj': 'ünlem', 'num': 'sayı', 'det': 'belirleyici', 'particle': 'edat', 'name': 'özel isim', 'phrase': 'deyim',
    'proverb': 'atasözü', 'suffix': 'ek',
  };
  const en = {
    'noun': 'noun', 'verb': 'verb', 'adj': 'adjective', 'adv': 'adverb', 'pron': 'pronoun', 'postp': 'postposition',
    'conj': 'conjunction', 'intj': 'interjection', 'num': 'numeral', 'det': 'determiner', 'particle': 'particle',
    'name': 'proper noun', 'phrase': 'phrase', 'proverb': 'proverb', 'suffix': 'suffix',
  };
  return (uiEnglish ? en[pos] : tr[pos]) ?? pos;
}

class _TrWordPanelState extends State<TrWordPanel> {
  late final List<String> cands;
  late String lemma;
  TrEntry? entry;

  bool _allExamples = false;

  /// The meaning (index over all glosses) the words around the tapped word
  /// point to, or null.
  int? inContext;

  /// Base words of the sentence the word was tapped in.
  late final List<String> _ctxLemmas = [
    for (final t in widget.ctx?.sentenceTokens ?? const [])
      if (widget.app.trEn!.lemmas(t.lower) case final l when l.isNotEmpty) l.first,
  ];

  void _load(String l) {
    lemma = l;
    entry = widget.app.trEn!.entry(l);
    inContext = _ctxLemmas.isEmpty ? null : widget.app.trEn!.meaningInContext(l, _ctxLemmas);
  }

  @override
  void initState() {
    super.initState();
    final d = widget.app.trEn!;
    cands = widget.lemma != null ? [widget.lemma!] : d.lemmas(widget.surface);
    _load(cands.isEmpty ? TrEnDict.lower(widget.surface) : cands.first);
    if (Speech.supported) Speech.instance.prefetch(lemma, lang: 'tr');
  }

  void _pick(String l) => setState(() => _load(l));

  /// The meaning to save with the word: the one of this sentence when known.
  String? get _meaning => _contextGloss ?? widget.app.trEn!.shortMeaning(lemma);

  String? get _contextGloss {
    final g = inContext, e = entry;
    if (g == null || e == null) return null;
    final all = [for (final s in e.senses) ...s.glosses];
    return g < all.length ? all[g] : null;
  }

  void _set(WordStatus st) {
    widget.app.setWord(lemma, st, context: widget.ctx?.sentence, book: widget.ctx?.bookTitle, meaning: _meaning);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final theme = Theme.of(context);
    final st = app.user.statuses[lemma] ?? WordStatus.none;
    final surface = TrEnDict.lower(widget.surface);
    final e = entry;
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.only(right: 40),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(lemma, style: TextStyle(fontFamily: readingFont, fontSize: 34, fontWeight: FontWeight.w700, height: 1.1, color: theme.colorScheme.onSurface)),
            if (Speech.supported) SpeakButton(lemma, lang: 'tr', key: ValueKey('say-tr-$lemma'), tooltip: L('Telaffuzu dinle', 'Hear the pronunciation'), autoPlay: Speech.instance.autoWord, size: 26),
            if (surface != lemma) Text('(${widget.surface})', style: theme.textTheme.titleMedium?.copyWith(color: theme.hintColor)),
          ],
        ),
      ),
      if (cands.length > 1)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            Text(L('Şu kelimeden de olabilir:', 'Could also come from:'), style: TextStyle(color: theme.hintColor, fontSize: 13.5)),
            for (final c in cands)
              ChoiceChip(
                key: ValueKey('tr-lemma-$c'),
                label: Text(c),
                selected: c == lemma,
                onSelected: (_) => _pick(c),
                visualDensity: VisualDensity.compact,
              ),
          ]),
        ),
      const SizedBox(height: 14),
    ];

    // The word's parts: stem and suffixes, each with what it does.
    final pieces = trPieces(widget.surface, lemma);
    if (pieces != null) {
      children.add(Container(
        key: const ValueKey('tr-pieces'),
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(L('Kelimenin ekleri', 'Word parts'), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(pieces.map((p) => p.text).join(' + '),
              style: TextStyle(fontFamily: readingFont, fontSize: 20, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
          const SizedBox(height: 4),
          for (final p in pieces.skip(1))
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '-${p.text}  ', style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: p.note),
              ]), style: TextStyle(fontSize: 14, height: 1.35, color: theme.colorScheme.onSurfaceVariant)),
            ),
          const SizedBox(height: 4),
          Text(L('Ekler kurallara göre ayrıldı; yaklaşıktır.', 'Split by rule, so approximate.'), style: TextStyle(fontSize: 11.5, color: theme.hintColor)),
        ]),
      ));
    }

    final ctxGloss = _contextGloss;
    if (ctxGloss != null) {
      children.add(Container(
        key: const ValueKey('tr-in-context'),
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(color: goldSoft(theme), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(L('Bu cümlede', 'In this sentence'), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: theme.colorScheme.primary)),
          const SizedBox(height: 4),
          Text(ctxGloss, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.3, color: theme.colorScheme.onSurface)),
        ]),
      ));
    }

    if (e == null) {
      children.add(Text(
        L('"${widget.surface}" Türkçe-İngilizce sözlükte bulunamadı.', '"${widget.surface}" is not in the Turkish-English dictionary.'),
        style: TextStyle(color: theme.hintColor, fontSize: 15),
      ));
    } else {
      var gi = 0;
      for (final s in e.senses) {
        final first = gi;
        gi += s.glosses.length;
        // The meaning of this sentence (else the first one) stands out.
        bool strong(int i) => inContext == null ? i == 0 : first + i == inContext;
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (s.source != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(s.source == 'wn' ? L('Kaynak: KeNet / WordNet', 'Source: KeNet / WordNet') : L('Kaynak: FreeDict', 'Source: FreeDict'),
                    style: TextStyle(fontSize: 11.5, color: theme.hintColor)),
              ),
            if (s.pos.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: goldSoft(theme), borderRadius: BorderRadius.circular(20)),
                child: Text(trPosLabel(s.pos), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.primary)),
              ),
            for (var i = 0; i < s.glosses.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Padding(padding: EdgeInsets.only(top: 2, right: 8), child: LangTag.en()),
                  Expanded(
                    child: Text(s.glosses[i],
                        style: TextStyle(fontSize: strong(i) ? 18 : 15.5, fontWeight: strong(i) ? FontWeight.w700 : FontWeight.w400, color: theme.colorScheme.onSurface, height: 1.3)),
                  ),
                ]),
              ),
          ]),
        ));
      }
      if (e.examples.isNotEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 6),
          child: Text(L('Örnek cümleler', 'Example sentences'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        ));
        final shownEx = _allExamples ? e.examples : e.examples.take(3);
        for (final x in shownEx) {
          children.add(Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(12)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(x.tr, style: TextStyle(fontFamily: readingFont, fontSize: 16.5, height: 1.35, color: theme.colorScheme.onSurface)),
                  const SizedBox(height: 4),
                  Text(x.en, style: TextStyle(fontSize: 14.5, height: 1.3, color: enColor(theme))),
                ]),
              ),
              if (Speech.supported) SpeakButton(x.tr, lang: 'tr', size: 20, tooltip: L('Cümleyi dinle', 'Listen to the sentence')),
            ]),
          ));
        }
        if (!_allExamples && e.examples.length > 3) {
          children.add(Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('tr-more-examples'),
              icon: const Icon(Icons.expand_more_rounded),
              label: Text(L('${e.examples.length - 3} örnek daha', '${e.examples.length - 3} more examples')),
              onPressed: () => setState(() => _allExamples = true),
            ),
          ));
        }
        children.add(Text(L('Örnekler: Tatoeba (CC BY 2.0 FR)', 'Examples: Tatoeba (CC BY 2.0 FR)'), style: TextStyle(fontSize: 11.5, color: theme.hintColor)));
      }
    }

    children.add(Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(children: [
        Expanded(
          child: PanelPill(
            key: const ValueKey('word-learning'),
            icon: st == WordStatus.learning ? Icons.bookmark_rounded : Icons.bookmark_add_outlined,
            label: L('Öğreneceğim', 'To learn'),
            color: st == WordStatus.learning ? learningColor : null,
            fill: st == WordStatus.learning ? learningColor.withValues(alpha: 0.2) : null,
            onPressed: () => _set(st == WordStatus.learning ? WordStatus.none : WordStatus.learning),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: PanelPill(
            key: const ValueKey('word-learned'),
            icon: st == WordStatus.learned ? Icons.check_circle_rounded : Icons.check_circle_outline,
            label: L('Öğrendim', 'Learned'),
            color: st == WordStatus.learned ? learnedColor : null,
            fill: st == WordStatus.learned ? learnedColor.withValues(alpha: 0.2) : null,
            onPressed: () => _set(st == WordStatus.learned ? WordStatus.none : WordStatus.learned),
          ),
        ),
      ]),
    ));

    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: children);
  }
}
