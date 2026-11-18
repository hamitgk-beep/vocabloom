import 'package:flutter/material.dart';

import '../ai/tutor.dart';
import '../app_state.dart';
import '../data/dict_db.dart';
import '../l10n.dart';
import '../nlp/context_sense.dart';
import '../nlp/text.dart';
import 'ai/ai_key_help.dart';
import 'ai/local_ai_card.dart';
import 'panel.dart';
import 'tap_text.dart';
import 'word_sheet.dart';

/// The meaning a tapped word or expression has in the book's sentence, at the
/// top of the word and expression panels. Shows "this sentence" when the
/// engine is sure, "possible meaning" when it is a guess, and only a short
/// note when it found nothing, so the ordinary dictionary below takes over.
class ContextSenseCard extends StatefulWidget {
  final AppState app;
  final ContextSense result;
  final WordContext ctx;

  /// Words of the sentence to highlight (the tapped word or expression).
  final Set<String> highlight;
  const ContextSenseCard({super.key, required this.app, required this.result, required this.ctx, required this.highlight});

  /// Runs the engine for a tap; null (no card) when anything goes wrong.
  static ContextSense? resolve(AppState app, WordContext ctx, {Expr? expr, List<int>? exprTokens, String? lemma}) {
    try {
      // A word inside an expression that is used literally here ("run" in
      // "cracks run through the wall"): the phrase path weighs the particle
      // too, and gives the word's own sense, so use its answer.
      if (expr == null) {
        for (final m in ctx.matches) {
          if (m.tokens.length < 2 || !m.tokens.contains(ctx.indexInSentence)) continue;
          final r = resolve(app, ctx, expr: m.expr, exprTokens: m.tokens, lemma: lemma);
          if (r != null && r.literalPhrase != null) return r;
        }
      }
      return app.senses.resolve(SenseQuery(
        sentence: ctx.sentence,
        tokens: ctx.sentenceTokens,
        index: ctx.indexInSentence,
        expr: expr,
        exprTokens: exprTokens ?? const [],
        prevSentence: ctx.prevSentence,
        nextSentence: ctx.nextSentence,
        contentId: ctx.contentId,
        lang: uiEnglish ? 'en' : 'tr',
        lemma: lemma,
      ));
    } catch (_) {
      return null;
    }
  }

  /// Runs the engine for an expression the learner tapped in [ctx]; the
  /// expression is matched again inside the sentence to get its words.
  static ContextSense? resolveExpr(AppState app, WordContext ctx, Expr expr) {
    try {
      final ms = app.dict.matcher.match(ctx.sentenceTokens).where((m) => identical(m.expr, expr) || (m.expr.phrase == expr.phrase && m.expr.cat == expr.cat)).toList();
      if (ms.isEmpty) return null;
      final m = ms.firstWhere((m) => m.tokens.contains(ctx.indexInSentence), orElse: () => ms.first);
      return resolve(app, ctx, expr: m.expr, exprTokens: m.tokens);
    } catch (_) {
      return null;
    }
  }

  @override
  State<ContextSenseCard> createState() => _ContextSenseCardState();
}

class _ContextSenseCardState extends State<ContextSenseCard> {
  bool reported = false;
  bool askAi = false;
  bool allOthers = false;

  ContextSense get r => widget.result;

  static const _catTr = {
    'phrasal_verbs': ('Phrasal verb (deyimsel fiil)', 'Phrasal verb'),
    'idioms': ('Deyim', 'Idiom'),
    'collocations': ('Eşdizim', 'Collocation'),
    'chunks': ('Kalıp', 'Chunk'),
    'prepositional_phrases': ('Edatlı kalıp', 'Prepositional phrase'),
    'binomials': ('İkili kalıp', 'Binomial'),
    'proverbs': ('Atasözü', 'Proverb'),
    'discourse_markers': ('Bağlantı ifadesi', 'Discourse marker'),
    'conjunctions': ('Bağlaç', 'Conjunction'),
  };

  String _kind() {
    final c = r.cat == null ? null : _catTr[r.cat];
    if (c != null) return L(c.$1, c.$2);
    final p = r.best?.pos;
    return p == null ? L('Kelime', 'Word') : (posNames[p] ?? L('Kelime', 'Word'));
  }

  void _report() {
    final b = r.best;
    widget.app.user.addSenseFeedback(
      word: r.headword,
      sentence: widget.ctx.sentence,
      senseId: b?.id,
      shownTr: b?.trShown,
      confidence: r.confidence.name,
      dictVersion: widget.app.senses.dictVersion,
      engineVersion: SenseEngine.version,
      book: widget.ctx.bookTitle,
    );
    setState(() => reported = true);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(L('Teşekkürler, kaydedildi. Bu bildirim sözlüğü geliştirmek için kullanılacak.',
            'Thanks, saved. The report will be used to improve the dictionary.'))));
  }

  Future<void> _askAi() async {
    if (!LocalAiCard.available(widget.app) && !await showAiKeyHelp(context, widget.app)) return;
    if (!mounted || !LocalAiCard.available(widget.app)) return;
    setState(() => askAi = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final app = widget.app;
    final tr = app.showTr, en = app.showEn;
    final b = r.best;
    final shown = r.shown;
    final label = theme.textTheme.labelMedium?.copyWith(letterSpacing: 1.1, color: theme.hintColor);
    final children = <Widget>[
      Text(displayPhrase(r.headword), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 2),
      Text('${_kind()} · ${L('Kitaptaki cümleye göre seçildi', 'Chosen from the sentence in the book')}',
          style: theme.textTheme.labelLarge?.copyWith(color: cs.primary)),
      if (r.literalPhrase != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
              L('Burada "${displayPhrase(r.literalPhrase!)}" kalıp olarak değil, kelimelerin düz anlamıyla kullanılmış.',
                  'Here "${displayPhrase(r.literalPhrase!)}" is not used as an expression but with the plain meaning of its words.'),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
        ),
      const SizedBox(height: 12),
      Text(L('KİTAPTAKİ CÜMLE', 'SENTENCE IN THE BOOK'), style: label),
      const SizedBox(height: 4),
      SentenceText(widget.ctx.sentence, null, highlight: widget.highlight),
    ];

    if (shown) {
      final sure = r.confidence == SenseConfidence.sure;
      children.addAll([
        const SizedBox(height: 14),
        Text(sure ? L('BU CÜMLEDEKİ ANLAMI', 'MEANING IN THIS SENTENCE') : L('BU CÜMLEDEKİ OLASI ANLAMI', 'POSSIBLE MEANING IN THIS SENTENCE'),
            style: label),
        const SizedBox(height: 4),
        if (tr || b!.en == null)
          Text(b!.trShown!, key: const ValueKey('ctx-sense-tr'), style: trStyle(theme, theme.textTheme.titleLarge).copyWith(fontWeight: FontWeight.w700)),
        if (en && b.en != null && b.en!.isNotEmpty) TapText(b.en!, style: enStyle(theme, theme.textTheme.bodyLarge)),
        if (tr && (b.explainTr ?? b.note) != null)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text((b.explainTr ?? b.note)!, style: trStyle(theme, null, false))),
        if (!sure)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline, size: 16, color: theme.hintColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                    b.trDerived
                        ? L('Bu anlam bağlama göre tahmin edildi; Türkçesi sözlükte bu anlama ayrıca yazılmamış.',
                            'This meaning is a guess from the context; the dictionary has no Turkish written for it.')
                        : L('Bu anlam bağlama göre tahmin edildi, kesin değil.', 'This meaning is a guess from the context, not certain.'),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
              ),
            ]),
          ),
      ]);
      final others = r.others;
      if (others.isNotEmpty) {
        final list = allOthers ? others : others.take(4).toList();
        children.addAll([
          const SizedBox(height: 14),
          Text(L('DİĞER SÖZLÜK ANLAMLARI', 'OTHER DICTIONARY MEANINGS'), style: label),
          const SizedBox(height: 4),
          for (var i = 0; i < list.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '${i + 1}. ${tr ? list[i].trShown : (list[i].en ?? list[i].trShown)}'
                '${list[i].pos != null && r.cat == null && list[i].pos != b.pos ? ' (${posNames[list[i].pos] ?? ''})' : ''}',
                style: tr ? trStyle(theme, null, false) : enStyle(theme, null, false),
              ),
            ),
          if (!allOthers && others.length > list.length)
            TextButton(onPressed: () => setState(() => allOthers = true), child: Text(L('Tümünü göster', 'Show all'))),
        ]);
      }
    } else {
      // A single word tapped inside an expression ("run" in "run through"):
      // its own senses do not tell what the sentence means, so no English
      // guess is put forward; the expression box below has the meaning.
      final ctx = widget.ctx;
      final phrase = widget.result.literalPhrase == null && !widget.result.headword.contains(' ')
          ? ctx.matches
              .where((m) =>
                  m.tokens.length > 1 &&
                  m.tokens.contains(ctx.indexInSentence) &&
                  !widget.app.senses.isLiteral(m.expr, ctx.sentenceTokens, m.tokens))
              .map((m) => m.expr.phrase)
              .firstOrNull
          : null;
      children.add(Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
            phrase != null
                ? L('Bu kelime burada "$phrase" kalıbının parçası; anlamı aşağıdaki kalıp kutusunda.',
                    'Here this word is part of "$phrase"; its meaning is in the expression box below.')
                : b != null && b.tr.isEmpty && b.en != null
                ? L('Bu cümledeki anlamın Türkçesi sözlükte yok. Sözlükteki anlamlar aşağıda; yapay zekâya da sorabilirsin.',
                    'The dictionary has no Turkish for the meaning used here. The dictionary meanings are below; you can also ask the AI.')
                : L('Bu cümle için anlam güvenilir biçimde seçilemedi. Sözlükteki anlamlar aşağıda.',
                    'No meaning could be chosen reliably for this sentence. The dictionary meanings are below.'),
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor)),
      ));
      if (phrase == null && en && b != null && b.tr.isEmpty && b.en != null) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 4),
          child: TapText(b.en!, style: enStyle(theme, theme.textTheme.bodyMedium)),
        ));
      }
    }

    children.add(Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        if (shown)
          OutlinedButton.icon(
            key: const ValueKey('ctx-sense-wrong'),
            onPressed: reported ? null : _report,
            icon: Icon(reported ? Icons.check : Icons.flag_outlined, size: 18),
            label: Text(reported ? L('Bildirildi', 'Reported') : L('Anlam yanlış', 'Wrong meaning')),
          ),
        if (!askAi)
          FilledButton.tonalIcon(
            key: const ValueKey('ctx-sense-ai'),
            onPressed: _askAi,
            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
            label: Text(L('Yapay zekâya sor', 'Ask the AI')),
          ),
      ]),
    ));
    if (askAi) {
      final meanings = <String>[
        if (b != null && b.trShown != null) '${b.trShown}${b.en == null ? '' : ' (${b.en})'}',
        for (final o in r.others.take(6)) '${o.trShown}${o.en == null ? '' : ' (${o.en})'}',
      ];
      final level = app.user.getSetting('grammar_level') ?? app.user.getSetting('library_level');
      children.add(LocalAiCard(
        key: ValueKey('ai-ctx-${r.headword}|${widget.ctx.sentence}'),
        app: app,
        cacheKey: 'ctx:${r.headword}|${widget.ctx.sentence}',
        title: L('Yapay zekâ: bu cümledeki anlamı', 'AI: meaning in this sentence'),
        button: L('Yapay zekâya sor', 'Ask the AI'),
        auto: true,
        run: () => Tutor.of(app).contextMeaning(r.headword,
            sentence: widget.ctx.sentence,
            prev: widget.ctx.prevSentence,
            next: widget.ctx.nextSentence,
            meanings: meanings,
            chosen: shown ? b!.trShown : null,
            level: level),
      ));
    }

    return Container(
      key: const ValueKey('ctx-sense-card'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}
