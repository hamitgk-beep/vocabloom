import 'dart:convert';

import 'package:flutter/material.dart';

import '../ai/device_translate.dart';
import '../online/ai_service.dart';
import '../tts/speech.dart';
import '../tts/voice_ui.dart';
import 'ai/device_translation.dart';
import 'meaning_parts.dart';
import 'theme.dart';

import '../ai/tutor.dart';
import '../app_state.dart';
import '../l10n.dart';
import '../nlp/context_sense.dart';
import '../nlp/text.dart';
import 'ai/ai_key_help.dart';
import 'ai/local_ai_card.dart';
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

  /// Shown right under the meaning, above the book's sentence (the word
  /// panel's To learn / Learned row, so a short panel shows it).
  final Widget? actions;
  const ContextSenseCard({super.key, required this.app, required this.result, required this.ctx, required this.highlight, this.actions});

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
      return app.senses.resolve(
        SenseQuery(
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
        ),
      );
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
  /// The active "wrong meaning" report for this word in this sentence (kept
  /// across restarts), and whether the simple explanation is open.
  int? feedbackId;
  late bool helpOpen;
  bool askAi = false;

  ContextSense get r => widget.result;

  @override
  void initState() {
    super.initState();
    feedbackId = widget.app.user.activeSenseFeedbackId(r.headword, widget.ctx.sentence);
    helpOpen = widget.app.user.senseHelpShown(r.headword, widget.ctx.sentence);
  }

  void _report() {
    final b = r.best;
    final id = widget.app.user.addSenseFeedback(
      word: r.headword,
      sentence: widget.ctx.sentence,
      senseId: b?.id,
      shownTr: b?.trShown,
      confidence: r.confidence.name,
      dictVersion: widget.app.senses.dictVersion,
      engineVersion: SenseEngine.version,
      book: widget.ctx.bookTitle,
    );
    // The AI drafts for this word in this sentence are no longer offered.
    widget.app.user.flagAiMeanings(r.headword, widget.ctx.sentence);
    setState(() => feedbackId = id);
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(L('Teşekkürler, kaydedildi. Bu bildirim sözlüğü geliştirmek için kullanılacak.', 'Thanks, saved. The report will be used to improve the dictionary.'))));
  }

  /// Takes the report back: the row stays in the database, marked as withdrawn.
  void _undo() {
    final id = feedbackId;
    if (id == null) return;
    widget.app.user.withdrawSenseFeedback(id);
    setState(() => feedbackId = null);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(L('Bildirim geri alındı.', 'The report was withdrawn.'))));
  }

  /// "Anlamı anlamadım": a request for a plainer explanation, not a wrong report.
  void _help() {
    widget.app.user.markSenseHelp(r.headword, widget.ctx.sentence);
    setState(() => helpOpen = true);
  }

  /// The dictionary's own plain explanation of the sense, offline.
  /// No written explanation: say plainly what the word means here, from the chosen Turkish.
  String _fromMeaning(List<String> tr) => tr.isEmpty
      ? L('Bu anlamın kısa açıklaması sözlükte yok. İstersen yapay zekâya sorabilirsin.', 'No short explanation for this meaning. You can ask the AI.')
      : L(
          'Bu cümlede “${r.headword}”, “${tr.first}” anlamında kullanılmış. Sözlükte daha uzun bir açıklama yok; istersen yapay zekâya sorabilirsin.',
          'Here “${r.headword}” means “${tr.first}”. The dictionary has no longer explanation; you can ask the AI.',
        );

  Widget _plainExplanation(ThemeData theme) {
    final b = r.best;
    final text = b == null
        ? L('Bu cümle için sözlükte bir açıklama yok. İstersen yapay zekâya sorabilirsin.', 'The dictionary has no explanation for this sentence. You can ask the AI.')
        : (b.explainTr ?? b.note ?? b.explainEn ?? _fromMeaning(b.tr));
    final ex = b != null && b.examples.isNotEmpty ? b.examples.first : null;
    final exTr = b != null && b.examplesTr.isNotEmpty ? b.examplesTr.first : null;
    return Padding(
      key: const ValueKey('ctx-sense-help-text'),
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(L('SADE AÇIKLAMA', 'PLAIN EXPLANATION'), style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.1, color: theme.hintColor)),
          const SizedBox(height: 4),
          Text(text, style: theme.textTheme.bodyMedium),
          if (ex != null) ...[
            const SizedBox(height: 6),
            Text('“$ex”', style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
            if (exTr != null) Text(exTr, style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }

  Future<void> _askAi() async {
    if (!LocalAiCard.available(widget.app) && !await showAiKeyHelp(context, widget.app)) return;
    if (!mounted || !LocalAiCard.available(widget.app)) return;
    setState(() => askAi = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final app = widget.app;
    final reported = feedbackId != null;
    final b = r.best;
    final shown = r.shown;
    final children = <Widget>[
      if (r.literalPhrase != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            L(
              'Burada "${displayPhrase(r.literalPhrase!)}" kalıp olarak değil, kelimelerin düz anlamıyla kullanılmış.',
              'Here "${displayPhrase(r.literalPhrase!)}" is not used as an expression but with the plain meaning of its words.',
            ),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
        ),
    ];

    if (shown) {
      final sure = r.confidence == SenseConfidence.sure;
      final fg = onGold(theme);
      children.add(
        MeaningBox(
          label: sure ? L('BU CÜMLEDEKİ ANLAMI', 'MEANING IN THIS SENTENCE') : L('BU CÜMLEDEKİ OLASI ANLAMI', 'POSSIBLE MEANING IN THIS SENTENCE'),
          tr: b!.trShown,
          trKey: const ValueKey('ctx-sense-tr'),
          en: b.en,
          note: b.explainTr ?? b.note,
          extra: [
            if (!sure)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 15, color: fg.withValues(alpha: 0.8)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        b.trDerived
                            ? L(
                                'Bu anlam bağlama göre tahmin edildi; Türkçesi sözlükte bu anlama ayrıca yazılmamış.',
                                'This meaning is a guess from the context; the dictionary has no Turkish written for it.',
                              )
                            : L('Bu anlam bağlama göre tahmin edildi, kesin değil.', 'This meaning is a guess from the context, not certain.'),
                        style: TextStyle(fontSize: 12.5, color: fg.withValues(alpha: 0.85)),
                      ),
                    ),
                  ],
                ),
              ),
            if (!helpOpen)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const ValueKey('ctx-sense-help'),
                  onPressed: _help,
                  style: TextButton.styleFrom(foregroundColor: fg, padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 30), visualDensity: VisualDensity.compact),
                  child: Text(
                    L('Anlamı anlamadım', "I don't understand"),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, decoration: TextDecoration.underline),
                  ),
                ),
              ),
          ],
        ),
      );
    } else {
      // A single word tapped inside an expression ("run" in "run through"):
      // its own senses do not tell what the sentence means, so no English
      // guess is put forward; the expression box below has the meaning.
      final ctx = widget.ctx;
      final phrase = widget.result.literalPhrase == null && !widget.result.headword.contains(' ')
          ? ctx.matches
                .where((m) => m.tokens.length > 1 && m.tokens.contains(ctx.indexInSentence) && !widget.app.senses.isLiteral(m.expr, ctx.sentenceTokens, m.tokens))
                .map((m) => m.expr.phrase)
                .firstOrNull
          : null;
      children.add(
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 14),
          padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
          decoration: BoxDecoration(color: goldSoft(theme), borderRadius: BorderRadius.circular(20)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                phrase != null
                    ? L('Bu kelime burada "$phrase" kalıbının parçası; anlamı aşağıdaki kalıp kutusunda.', 'Here this word is part of "$phrase"; its meaning is in the expression box below.')
                    : b != null && b.tr.isEmpty && b.en != null
                    ? L('Bu cümledeki anlamın Türkçesi sözlükte yok. Yapay zekâya sorabilirsin.', 'The dictionary has no Turkish for the meaning used here. You can ask the AI.')
                    : L('Bu cümle için anlam güvenilir biçimde seçilemedi. Sözlükteki anlamlar aşağıda.', 'No meaning could be chosen reliably for this sentence. The dictionary meanings are below.'),
                style: theme.textTheme.bodyMedium,
              ),
              if (phrase == null && b != null && b.tr.isEmpty && b.en != null) ...[const SizedBox(height: 8), LangLine(en: true, child: TapText(b.en!, style: panelEnStyle(theme, size: 14)))],
              if (!helpOpen)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(key: const ValueKey('ctx-sense-help'), onPressed: _help, child: Text(L('Anlamı anlamadım', "I don't understand"))),
                ),
            ],
          ),
        ),
      );
    }

    if (helpOpen) children.add(_plainExplanation(theme));
    if (widget.actions != null) children.add(widget.actions!);
    children.add(PanelHeading(L('KİTAPTAKİ CÜMLE', 'SENTENCE IN THE BOOK')));
    children.add(BookSentenceCard(app: app, ctx: widget.ctx, highlight: widget.highlight));
    children.add(
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          children: [
            if (shown && !reported)
              Expanded(
                child: PanelPill(key: const ValueKey('ctx-sense-wrong'), icon: Icons.flag_outlined, label: L('Anlam yanlış', 'Wrong meaning'), onPressed: _report),
              ),
            if (shown && reported)
              Expanded(
                child: PanelPill(key: const ValueKey('ctx-sense-wrong'), icon: Icons.check, label: L('Bildirildi', 'Reported')),
              ),
            if (shown) const SizedBox(width: 10),
            if (!askAi)
              Expanded(
                child: PanelPill(key: const ValueKey('ctx-sense-ai'), icon: Icons.auto_awesome_rounded, label: L('Yapay zekâya sor', 'Ask the AI'), onPressed: _askAi),
              ),
            if (askAi && !shown) const Spacer(),
          ],
        ),
      ),
    );
    if (reported) {
      children.add(
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(key: const ValueKey('ctx-sense-undo'), onPressed: _undo, icon: const Icon(Icons.undo_rounded, size: 18), label: Text(L('Bildirimi geri al', 'Withdraw report'))),
        ),
      );
    }
    if (askAi) {
      final meanings = <String>[
        if (b != null && b.trShown != null) '${b.trShown}${b.en == null ? '' : ' (${b.en})'}',
        for (final o in r.others.take(6)) '${o.trShown}${o.en == null ? '' : ' (${o.en})'}',
      ];
      final level = app.user.getSetting('grammar_level') ?? app.user.getSetting('library_level');
      final cat = r.cat ?? 'word';
      children.add(
        LocalAiCard(
          key: ValueKey('ai-ctx-${r.headword}|${widget.ctx.sentence}'),
          app: app,
          cacheKey: 'ctx:${r.headword}|${widget.ctx.sentence}',
          title: L('Yapay zekâ taslağı · doğrulanmadı', 'AI draft · not verified'),
          button: L('Yapay zekâya sor', 'Ask the AI'),
          auto: true,
          initialText: app.user.aiMeaning(widget.ctx.sentence, r.headword, cat),
          onDone: (text) => app.user.saveAiMeaning(
            sentence: widget.ctx.sentence,
            phrase: r.headword,
            cat: cat,
            lemma: r.headword,
            tr: text,
            model: app.localAi.activeId,
            dictVersion: app.senses.dictVersion,
            engineVersion: SenseEngine.version,
          ),
          run: () => Tutor.of(app).contextMeaning(
            r.headword,
            sentence: widget.ctx.sentence,
            prev: widget.ctx.prevSentence,
            next: widget.ctx.nextSentence,
            meanings: meanings,
            chosen: shown ? b!.trShown : null,
            level: level,
          ),
        ),
      );
    }

    return Column(key: const ValueKey('ctx-sense-card'), crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}

/// The book's sentence with its Turkish right under it: the reader's saved
/// translation, the sentence panel's saved one, the phone's instant
/// translation, or (with an AI service) a button that translates it.
class BookSentenceCard extends StatefulWidget {
  final AppState app;
  final WordContext ctx;
  final Set<String> highlight;

  /// The sentence panel's own translation (it asks the AI for it, with an
  /// explanation), and whether that is still on its way.
  final String? tr;
  final bool translating;

  /// The English in the reading font, bigger (the sentence panel).
  final bool large;
  const BookSentenceCard({super.key, required this.app, required this.ctx, required this.highlight, this.tr, this.translating = false, this.large = false});

  @override
  State<BookSentenceCard> createState() => _BookSentenceCardState();
}

class _BookSentenceCardState extends State<BookSentenceCard> {
  String? aiTr;
  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    aiTr = widget.app.user.sentenceAi(widget.ctx.sentence)?.$1;
  }

  Future<void> _translate() async {
    final svc = AiService.fromSettings(widget.app.user);
    if (svc == null) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final c = widget.ctx;
      final r = await svc.explainSentence(c.sentence, [c.prevSentence, c.sentence, c.nextSentence].whereType<String>().join(' '));
      widget.app.user.setSentenceAi(c.sentence, r.translation, jsonEncode({'tr': r.explanation, 'en': r.explanationEn}));
      if (mounted) setState(() => aiTr = r.translation);
    } catch (e) {
      if (mounted) setState(() => error = L('Çevrilemedi: ${errorText(e)}', 'Could not translate: ${errorText(e)}'));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final app = widget.app;
    final c = widget.ctx;
    final tr = c.sentenceTr?.first ?? widget.tr ?? aiTr;
    final hasAi = AiService.fromSettings(app.user) != null;
    Widget? trLine;
    if (tr == null && widget.translating) {
      trLine = LangLine(
        en: false,
        child: Row(
          children: [
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
            Text(L('Çevriliyor…', 'Translating…'), style: t.textTheme.bodyMedium),
          ],
        ),
      );
    } else if (tr != null) {
      trLine = LangLine(
        en: false,
        child: Text(tr, key: const ValueKey('ctx-sentence-tr'), style: panelTrStyle(t)),
        trailing: Speech.supported ? SpeakButton(tr, lang: 'tr', size: 20) : null,
      );
    } else if (DeviceTranslate.supported && (!hasAi || DeviceTranslate.instance.ready(app.user))) {
      trLine = LangLine(
        en: false,
        child: DeviceTranslation(key: ValueKey('mt-s-${c.sentence}'), app: app, text: c.sentence, style: panelTrStyle(t)),
      );
    } else if (hasAi) {
      trLine = LangLine(
        en: false,
        child: Align(
          alignment: Alignment.centerLeft,
          child: loading
              ? Row(
                  children: [
                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 8),
                    Text(L('Çevriliyor…', 'Translating…'), style: t.textTheme.bodyMedium),
                  ],
                )
              : TextButton(
                  key: const ValueKey('ctx-sentence-translate'),
                  onPressed: _translate,
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 24), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  child: Text(error ?? L('Türkçesini göster', 'Show the Turkish')),
                ),
        ),
      );
    }
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LangLine(
            en: true,
            child: TapText(
              c.sentence,
              style: widget.large ? panelEnStyle(t, size: 17.5).copyWith(fontFamily: readingFont, height: 1.5) : panelEnStyle(t),
              highlight: widget.highlight,
            ),
            trailing: Speech.supported ? SpeakButton(c.sentence, tooltip: L('Cümleyi dinle', 'Listen to the sentence'), size: 20) : null,
          ),
          if (trLine != null) ...[const LangDivider(), trLine],
        ],
      ),
    );
  }
}
