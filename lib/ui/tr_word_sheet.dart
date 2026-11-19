import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/tr_en_dict.dart';
import '../data/user_db.dart';
import '../l10n.dart';
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

  @override
  void initState() {
    super.initState();
    final d = widget.app.trEn!;
    cands = widget.lemma != null ? [widget.lemma!] : d.lemmas(widget.surface);
    lemma = cands.isEmpty ? TrEnDict.lower(widget.surface) : cands.first;
    entry = d.entry(lemma);
    if (Speech.supported) Speech.instance.prefetch(lemma, lang: 'tr');
  }

  void _pick(String l) => setState(() {
        lemma = l;
        entry = widget.app.trEn!.entry(l);
      });

  String? get _meaning {
    final s = entry?.senses;
    if (s == null || s.isEmpty) return null;
    return s.first.glosses.take(2).join('; ');
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

    if (e == null) {
      children.add(Text(
        L('"${widget.surface}" Türkçe-İngilizce sözlükte bulunamadı.', '"${widget.surface}" is not in the Turkish-English dictionary.'),
        style: TextStyle(color: theme.hintColor, fontSize: 15),
      ));
    } else {
      for (final s in e.senses) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                        style: TextStyle(fontSize: i == 0 ? 18 : 15.5, fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w400, color: theme.colorScheme.onSurface, height: 1.3)),
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
        for (final x in e.examples) {
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
        children.add(Text('Tatoeba (CC BY 2.0 FR)', style: TextStyle(fontSize: 11.5, color: theme.hintColor)));
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
