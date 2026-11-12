import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/dict_db.dart';
import '../data/user_db.dart';
import '../nlp/text.dart';
import 'paragraph_view.dart';

/// Context in which a word was tapped (null when opened from a list).
class WordContext {
  final String sentence;
  final List<Token> sentenceTokens;
  final int indexInSentence;
  final List<Match> matches; // expressions covering the token
  final List<String>? sentenceTr;
  final int? bookId;
  final String? bookTitle;
  WordContext(this.sentence, this.sentenceTokens, this.indexInSentence, this.matches, this.sentenceTr, this.bookId, this.bookTitle);
}

/// Builds the context for token [ti] of paragraph [para].
WordContext buildContext(AppState app, Para para, ParaAnalysis a, int ti, {int? bookId, String? bookTitle}) {
  final t = a.tokens[ti];
  final ranges = sentenceRanges(para.text);
  var sIdx = 0;
  for (var i = 0; i < ranges.length; i++) {
    if (t.start >= ranges[i].$1 && t.start < ranges[i].$2) sIdx = i;
  }
  final r = ranges[sIdx];
  final sentTokens = a.tokens.where((x) => x.start >= r.$1 && x.end <= r.$2).toList();
  final idx = sentTokens.indexWhere((x) => x.start == t.start);
  final matches = a.matches.where((m) => m.tokens.contains(ti)).toList();
  final tr = app.user.paraTranslation(para.id);
  return WordContext(para.text.substring(r.$1, r.$2).trim(), sentTokens, idx < 0 ? 0 : idx, matches,
      tr != null && sIdx < tr.length ? [tr[sIdx]] : null, bookId, bookTitle);
}

Future<void> showWordSheet(BuildContext context, AppState app, String surface, {WordContext? ctx, String? lemma}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 760),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (c, sc) => WordPanel(app: app, surface: surface, ctx: ctx, lemma: lemma, scroll: sc),
    ),
  );
}

class WordPanel extends StatefulWidget {
  final AppState app;
  final String surface;
  final String? lemma;
  final WordContext? ctx;
  final ScrollController? scroll;
  const WordPanel({super.key, required this.app, required this.surface, this.ctx, this.lemma, this.scroll});

  @override
  State<WordPanel> createState() => _WordPanelState();
}

class _WordPanelState extends State<WordPanel> {
  late String lemma;
  late WordInfo info;
  WordInfo? surfaceInfo;
  Sense? best;
  List<String> bookExamples = [];

  @override
  void initState() {
    super.initState();
    final app = widget.app;
    final lower = widget.surface.toLowerCase().replaceAll('’', "'");
    final cands = app.dict.lemmatizer.lemmas(lower);
    lemma = widget.lemma ?? cands.first;
    info = app.dict.lookup(lemma);
    if (info.isEmpty) {
      for (final c in cands) {
        final i = app.dict.lookup(c);
        if (!i.isEmpty) {
          lemma = c;
          info = i;
          break;
        }
      }
    }
    if (lower != lemma && cands.contains(lower)) {
      final si = app.dict.lookup(lower);
      if (!si.isEmpty) surfaceInfo = si;
    }
    final ctx = widget.ctx;
    if (ctx != null) best = app.dict.bestSense(info, ctx.sentenceTokens, ctx.indexInSentence);
    if (ctx?.bookId != null) {
      final forms = <String>{lemma, '${lemma}s', '${lemma}es', '${lemma}ed', '${lemma}d', '${lemma}ing', lower};
      if (lemma.endsWith('e')) forms.add('${lemma.substring(0, lemma.length - 1)}ing');
      for (final r in app.dict.db.select('SELECT form FROM exc WHERE lemma=?', [lemma])) {
        forms.add(r['form'] as String);
      }
      bookExamples = app.user.findSentences(ctx!.bookId!, forms, exclude: ctx.sentence);
    }
  }

  String? get _meaning {
    if (best != null && best!.tr.isNotEmpty) return best!.tr.take(3).join(', ');
    if (info.trFreeDict.isNotEmpty) return info.trFreeDict.first;
    return best?.gloss;
  }

  void _set(String key, WordStatus st) {
    widget.app.setWord(key, st,
        context: widget.ctx?.sentence, book: widget.ctx?.bookTitle, meaning: key == lemma ? _meaning : null);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final theme = Theme.of(context);
    final ctx = widget.ctx;
    final st = app.user.statuses[lemma] ?? WordStatus.none;
    final tr = app.showTr, en = app.showEn;

    final children = <Widget>[
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Flexible(child: Text(lemma, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700))),
        if (widget.surface.toLowerCase() != lemma)
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 4),
            child: Text('(${widget.surface})', style: theme.textTheme.titleMedium?.copyWith(color: theme.hintColor)),
          ),
        if (best != null)
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 6),
            child: Text(posNames[best!.pos] ?? '', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
          ),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        StatusButtons(status: st, onChanged: (s) => _set(lemma, s)),
        const SizedBox(width: 8),
        LangToggles(app: app, onChanged: () => setState(() {})),
      ]),
    ];

    // ---------------- in this sentence
    if (ctx != null) {
      children.add(_Section('Bu cümlede', [
        _SentenceText(ctx.sentence, widget.surface),
        if (ctx.sentenceTr != null && tr) ...[
          const SizedBox(height: 6),
          Text(ctx.sentenceTr!.first, style: TextStyle(fontStyle: FontStyle.italic, color: theme.colorScheme.secondary)),
        ],
        for (final m in ctx.matches) ExprCard(app: app, expr: m.expr, onChanged: () => setState(() {})),
        if (best != null) ...[
          const SizedBox(height: 8),
          Text(ctx.matches.any((m) => m.expr.phrase.contains(' ')) ? 'Kelimenin tek başına anlamı:' : 'Büyük olasılıkla bu anlamda:',
              style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          if (tr && best!.tr.isNotEmpty) Text(best!.tr.join(', '), style: theme.textTheme.titleMedium),
          if (tr && best!.tr.isEmpty && info.trFreeDict.isNotEmpty)
            Text(info.trFreeDict.first, style: theme.textTheme.titleMedium),
          if (en) Text(best!.gloss, style: theme.textTheme.bodyLarge),
          for (final e in best!.examples.take(2))
            Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $e', style: const TextStyle(fontStyle: FontStyle.italic))),
        ],
      ]));
    }

    // ---------------- Turkish meanings
    if (tr && info.trFreeDict.isNotEmpty) {
      children.add(_Section('Türkçe karşılıklar', [
        for (var i = 0; i < info.trFreeDict.length && i < 12; i++)
          Padding(padding: const EdgeInsets.only(bottom: 3), child: Text('${i + 1}. ${info.trFreeDict[i]}')),
      ]));
    }
    if (surfaceInfo != null && tr && surfaceInfo!.trFreeDict.isNotEmpty) {
      children.add(_Section('"${widget.surface}" biçimi', [
        for (final s in surfaceInfo!.trFreeDict.take(5)) Text('• $s'),
      ]));
    }

    // ---------------- senses
    if (info.senses.isNotEmpty) {
      final byPos = <String, List<Sense>>{};
      for (final s in info.senses) {
        byPos.putIfAbsent(s.pos, () => []).add(s);
      }
      final items = <Widget>[];
      for (final e in byPos.entries) {
        items.add(Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 2),
          child: Text(posNames[e.key] ?? e.key, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
        ));
        for (final s in e.value.take(8)) {
          if (!en && s.tr.isEmpty) continue;
          items.add(Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: s == best ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5) : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (tr && s.tr.isNotEmpty) Text(s.tr.join(', '), style: const TextStyle(fontWeight: FontWeight.w600)),
              if (en) Text(s.gloss),
              if (en && s.synonyms.isNotEmpty)
                Text('eş anlamlı: ${s.synonyms.take(5).join(', ')}', style: TextStyle(color: theme.hintColor, fontSize: 13)),
              for (final ex in s.examples.take(2)) Text('“$ex”', style: const TextStyle(fontStyle: FontStyle.italic)),
            ]),
          ));
        }
      }
      children.add(_Section(en ? 'Anlamlar (WordNet)' : 'Anlamlar', items));
    }

    if (bookExamples.isNotEmpty) {
      children.add(_Section('Kitaptan başka örnekler', [
        for (final s in bookExamples)
          Padding(padding: const EdgeInsets.only(bottom: 6), child: _SentenceText(s, null, highlight: {lemma, widget.surface.toLowerCase()})),
      ]));
    }
    if (info.isEmpty && (ctx?.matches.isEmpty ?? true)) {
      children.add(const Padding(padding: EdgeInsets.all(16), child: Text('Bu kelime sözlükte bulunamadı.')));
    }

    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: children);
  }
}

class StatusButtons extends StatelessWidget {
  final WordStatus status;
  final ValueChanged<WordStatus> onChanged;
  const StatusButtons({super.key, required this.status, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<WordStatus>(
      segments: const [
        ButtonSegment(value: WordStatus.learning, label: Text('Öğreneceğim'), icon: Icon(Icons.bookmark_add_outlined)),
        ButtonSegment(value: WordStatus.learned, label: Text('Öğrendim'), icon: Icon(Icons.check_circle_outline)),
      ],
      emptySelectionAllowed: true,
      selected: status == WordStatus.none ? {} : {status},
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) {
          if (!s.contains(WidgetState.selected)) return null;
          return status == WordStatus.learning ? learningColor.withValues(alpha: 0.35) : learnedColor.withValues(alpha: 0.35);
        }),
      ),
      onSelectionChanged: (s) => onChanged(s.isEmpty ? WordStatus.none : s.first),
    );
  }
}

class LangToggles extends StatelessWidget {
  final AppState app;
  final VoidCallback onChanged;
  const LangToggles({super.key, required this.app, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 6, children: [
      FilterChip(
        label: const Text('Türkçe'),
        selected: app.showTr,
        onSelected: (v) {
          app.setLang(tr: v);
          onChanged();
        },
      ),
      FilterChip(
        label: const Text('English'),
        selected: app.showEn,
        onSelected: (v) {
          app.setLang(en: v);
          onChanged();
        },
      ),
    ]);
  }
}

class ExprCard extends StatelessWidget {
  final AppState app;
  final Expr expr;
  final VoidCallback onChanged;
  const ExprCard({super.key, required this.app, required this.expr, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = categoryById[expr.cat]!;
    final st = app.user.statuses[expr.phrase] ?? WordStatus.none;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: c.color, width: 4)),
        color: c.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(expr.phrase, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
          Text(app.showEn && !app.showTr ? c.name : c.tr, style: TextStyle(color: c.color, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        if (app.showTr && expr.tr != null) Text(expr.tr!),
        if (app.showEn && expr.en != null) Text(expr.en!, style: TextStyle(color: Theme.of(context).hintColor)),
        const SizedBox(height: 6),
        StatusButtons(
          status: st,
          onChanged: (s) {
            app.setWord(expr.phrase, s, meaning: expr.tr ?? expr.en);
            onChanged();
          },
        ),
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section(this.title, this.children);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(letterSpacing: 1.1, color: Theme.of(context).hintColor)),
        const Divider(height: 10),
        ...children,
      ]),
    );
  }
}

class _SentenceText extends StatelessWidget {
  final String sentence;
  final String? word;
  final Set<String>? highlight;
  const _SentenceText(this.sentence, this.word, {this.highlight});

  @override
  Widget build(BuildContext context) {
    final toks = tokenize(sentence);
    final spans = <TextSpan>[];
    var pos = 0;
    final hl = highlight ?? {word!.toLowerCase()};
    for (final t in toks) {
      if (t.start > pos) spans.add(TextSpan(text: sentence.substring(pos, t.start)));
      final on = hl.contains(t.lower) || (highlight != null && hl.any((h) => t.lower.startsWith(h) && t.lower.length <= h.length + 3));
      spans.add(TextSpan(text: t.text, style: on ? const TextStyle(fontWeight: FontWeight.w800, decoration: TextDecoration.underline) : null));
      pos = t.end;
    }
    if (pos < sentence.length) spans.add(TextSpan(text: sentence.substring(pos)));
    return SelectableText.rich(TextSpan(style: const TextStyle(fontSize: 16, height: 1.45), children: spans));
  }
}
