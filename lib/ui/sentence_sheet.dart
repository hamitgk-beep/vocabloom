import 'dart:convert';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/sentence_translation.dart';
import '../data/user_db.dart';
import '../nlp/text.dart';
import 'ai/ai_ask_box.dart';
import '../online/ai_service.dart';
import 'context_sense_card.dart';
import 'hover_meaning.dart';
import 'meaning_parts.dart';
import 'panel.dart';
import 'paragraph_view.dart';
import '../l10n.dart';
import 'theme.dart';
import 'word_sheet.dart';
import '../tts/speech.dart';
import '../tts/voice_ui.dart';

/// Sentence breakdown: translation, tenses, expressions and word meanings.
Future<void> showSentenceSheet(BuildContext context, AppState app, Para para, ParaAnalysis a, int ti, {int? bookId, String? bookTitle}) {
  final ctx = buildContext(app, para, a, ti, bookId: bookId, bookTitle: bookTitle);
  final first = ctx.sentenceTokens.isEmpty ? 0 : a.tokens.indexWhere((t) => t.start == ctx.sentenceTokens.first.start);
  final last = first + ctx.sentenceTokens.length - 1;
  final matches = a.matches.where((m) => m.tokens.every((t) => t >= first && t <= last)).toList();
  return showPanel(context, (c, sc) => SentencePanel(app: app, ctx: ctx, para: para, matches: matches, scroll: sc), left: true);
}

class SentencePanel extends StatefulWidget {
  final AppState app;
  final WordContext ctx;
  final Para para;
  final List<Match> matches;
  final ScrollController? scroll;
  const SentencePanel({super.key, required this.app, required this.ctx, required this.para, required this.matches, this.scroll});

  @override
  State<SentencePanel> createState() => _SentencePanelState();
}

class _SentencePanelState extends State<SentencePanel> {
  String? onlineTr;
  String? onlineExplain;
  String? onlineExplainEn;
  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    // Saved earlier. The paid AI is asked only when the learner taps
    // "Explain in detail": opening the panel never spends their quota.
    final saved = widget.app.user.sentenceAi(widget.ctx.sentence);
    if (saved != null) {
      onlineTr = usableTranslation(widget.ctx.sentence, saved.$1) ? saved.$1 : null;
      final exp = saved.$2 == null ? null : jsonDecode(saved.$2!) as Map;
      onlineExplain = exp?['tr'] as String?;
      onlineExplainEn = exp?['en'] as String?;
    }
  }

  Future<void> _explain() async {
    final svc = AiService.fromSettings(widget.app.user);
    if (svc == null) {
      setState(() => error = L('Çevrimiçi açıklama için Ayarlar > Yapay zekâ bölümünden bir servis bağlayın.', 'Connect a service under Settings > AI for an online explanation.'));
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    // The answer belongs to the sentence asked about: it is saved under that
    // sentence and shown only while the panel still shows it.
    final asked = widget.ctx.sentence;
    try {
      final r = await svc.explainSentence(asked, widget.para.text);
      final ok = usableTranslation(asked, r.translation);
      widget.app.user.setSentenceAi(asked, ok ? r.translation : '', jsonEncode({'tr': r.explanation, 'en': r.explanationEn}), engine: svc.engineId);
      if (!mounted || widget.ctx.sentence != asked) return;
      setState(() {
        onlineTr = ok ? r.translation : null;
        onlineExplain = r.explanation;
        onlineExplainEn = r.explanationEn.isEmpty ? null : r.explanationEn;
      });
    } catch (e) {
      if (mounted) setState(() => error = L('Bağlantı kurulamadı: ${errorText(e)}', 'Could not connect: ${errorText(e)}'));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final theme = Theme.of(context);
    final ctx = widget.ctx;
    final tenses = app.tenses.detect(ctx.sentenceTokens);
    // The verified translation of the book first, then the AI's answer for
    // this very sentence; both were saved for exactly this English.
    final tr = ctx.sentenceTr?.first ?? onlineTr;
    final showTr = app.showTr, showEn = app.showEn;
    final hasAi = AiService.fromSettings(app.user) != null;

    // each expression once
    final exprs = <Match>[];
    final seen = <String>{};
    for (final m in widget.matches) {
      if (seen.add('${m.expr.cat}|${m.expr.phrase}')) exprs.add(m);
    }

    final contentWords = <int>[];
    final seenW = <String>{};
    for (var i = 0; i < ctx.sentenceTokens.length; i++) {
      final t = ctx.sentenceTokens[i];
      if (stopWords.contains(t.lower) || t.lower.length < 3) continue;
      if (seenW.add(app.primaryLemma(t.lower))) contentWords.add(i);
    }

    final explainTr = showTr ? onlineExplain : null;
    final explainEn = showEn ? onlineExplainEn : null;

    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
        // The title row stays free: the close button sits in that corner.
        Padding(
          padding: const EdgeInsets.only(right: 40),
          child: Text(
            L('Cümle analizi', 'Sentence analysis'),
            style: TextStyle(fontFamily: readingFont, fontSize: 26, fontWeight: FontWeight.w700, height: 1.15, color: theme.colorScheme.onSurface),
          ),
        ),
        const SizedBox(height: 14),
        BookSentenceCard(key: ValueKey('sentence-card-${tr != null}-$loading'), app: app, ctx: ctx, highlight: const {}, tr: onlineTr, translating: loading, large: true),
        if (Speech.supported)
          Padding(
            key: const ValueKey('sentence-listen'),
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                SpeakButton(ctx.sentence, label: L('Dinle', 'Listen'), tooltip: L('Cümleyi dinle', 'Listen to the sentence')),
                SpeakButton(ctx.sentence, speed: 0.75, label: L('Yavaş dinle', 'Listen slowly')),
              ],
            ),
          ),
        const SizedBox(height: 10),
        LangToggles(app: app, onChanged: () => setState(() {})),
        if (error != null) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(error!, style: TextStyle(color: theme.colorScheme.error)),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: loading ? null : _explain, icon: const Icon(Icons.refresh), label: Text(L('Tekrar dene', 'Try again'))),
          ),
        ],
        // ---------------- explanation: Turkish first, English small under it
        if (explainTr != null || explainEn != null) ...[
          PanelHeading(L('AÇIKLAMA', 'EXPLANATION')),
          PanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (explainTr != null)
                  LangLine(
                    en: false,
                    child: SelectableText(explainTr, style: panelTrStyle(theme, size: 15, weight: FontWeight.w500)),
                  ),
                if (explainTr != null && explainEn != null) const LangDivider(),
                if (explainEn != null) LangLine(en: true, child: SelectableText(explainEn, style: panelEnStyle(theme, size: 14))),
              ],
            ),
          ),
        ],
        if (onlineExplain == null && !loading && hasAi)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: PanelPill(icon: Icons.auto_awesome, label: L('Ayrıntılı açıkla', 'Explain in detail'), onPressed: _explain),
            ),
          ),
        const SizedBox(height: 4),
        AiAskBox(
          key: ValueKey('ai-ask-s-${ctx.sentence}'),
          app: app,
          title: L('Bu cümleyi yapay zekâya sor', 'Ask the AI about this sentence'),
          suggestions: [
            L('Cümleyi Türkçeye çevir ve açıkla', 'Translate and explain the sentence'),
            L('Gramer yapısını anlat', 'Explain its grammar'),
            L('Benzer bir örnek ver', 'Give a similar example'),
          ],
          about: 'Cümle: "${ctx.sentence}"${tr == null ? '' : '\nTürkçesi: $tr'}${ctx.bookTitle == null ? '' : '\nKitap: ${ctx.bookTitle}'}',
        ),
        // ---------------- tense and structure
        PanelHeading(L('ZAMAN VE YAPI', 'TENSE AND STRUCTURE')),
        PanelCard(
          child: tenses.isEmpty
              ? Text(L('Belirgin bir fiil yapısı bulunamadı.', 'No clear verb structure was found.'), style: TextStyle(color: theme.hintColor))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var k = 0; k < tenses.length; k++) ...[
                      if (k > 0) Divider(height: 20, color: theme.colorScheme.outlineVariant),
                      Text(
                        showTr ? (uiEnglish ? '${tenses[k].en} · ${tenses[k].tr}' : '${tenses[k].tr} · ${tenses[k].en}') : tenses[k].en,
                        style: panelTrStyle(theme, size: 16, weight: FontWeight.w700),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '"${tenses[k].words}"',
                                style: panelEnStyle(theme, size: 14).copyWith(fontWeight: FontWeight.w600),
                              ),
                              if (showTr || uiEnglish)
                                TextSpan(
                                  text: '  ${tenses[k].explain}',
                                  style: TextStyle(fontSize: 14, height: 1.4, color: theme.colorScheme.onSurfaceVariant),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
        // ---------------- expressions
        PanelHeading(L('BU CÜMLEDEKİ KALIPLAR', 'EXPRESSIONS IN THIS SENTENCE')),
        if (exprs.isEmpty)
          PanelCard(
            child: Text(L('Bu cümlede listelerimizdeki bir kalıp bulunamadı.', 'No expression from our lists was found in this sentence.'), style: TextStyle(color: theme.hintColor)),
          ),
        for (final m in exprs) ExprCard(app: app, expr: m.expr, ctx: ctx, onChanged: () => setState(() {})),
        // ---------------- words: Turkish first, never English alone
        PanelHeading(L('KELİMELER', 'WORDS')),
        PanelCard(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
          child: Column(children: [for (var k = 0; k < contentWords.length; k++) _wordRow(context, contentWords[k], divider: k > 0)]),
        ),
      ],
    );
  }

  /// One word of the sentence: the word and its part of speech, its first
  /// Turkish meaning big, the English definition small; opens the word panel.
  Widget _wordRow(BuildContext context, int i, {required bool divider}) {
    final app = widget.app;
    final ctx = widget.ctx;
    final theme = Theme.of(context);
    final t = ctx.sentenceTokens[i];
    final m = hoverMeaning(app, ctx.sentenceTokens, const [], i, text: widget.para.text);
    final head = m?.head ?? app.primaryLemma(t.lower);
    final own = app.dict.ownSenses(head);
    final ownEn = own.isEmpty ? '' : own.first.en;
    final en = app.showEn ? (ownEn.isNotEmpty ? ownEn : (m == null ? app.dict.lookup(head).senses.firstOrNull?.gloss : null)) : null;
    final st = app.statusOf(t);
    return InkWell(
      key: ValueKey('sentence-word-${t.lower}'),
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        await showWordSheet(context, app, t.text, ctx: WordContext(ctx.sentence, ctx.sentenceTokens, i, const [], ctx.sentenceTr, ctx.bookId, ctx.bookTitle));
        setState(() {});
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 11, 8, 11),
        decoration: BoxDecoration(
          border: divider ? Border(top: BorderSide(color: theme.colorScheme.outlineVariant)) : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 12),
              child: CircleAvatar(
                radius: 5,
                backgroundColor: switch (st) {
                  WordStatus.learning => learningColor,
                  WordStatus.learned => learnedColor,
                  _ => theme.colorScheme.outlineVariant,
                },
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: head == t.lower ? t.text : '${t.text} → $head',
                          style: TextStyle(fontFamily: readingFont, fontSize: 16.5, fontWeight: FontWeight.w700, color: theme.colorScheme.onSurface),
                        ),
                        if (m?.pos case final p? when p.isNotEmpty)
                          TextSpan(
                            text: '   $p',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.primary),
                          ),
                      ],
                    ),
                  ),
                  if (app.showTr && m != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(m.tr, style: panelTrStyle(theme, size: 15.5, weight: FontWeight.w700)),
                    ),
                  if (en != null && en.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(en, maxLines: 2, overflow: TextOverflow.ellipsis, style: panelEnStyle(theme, size: 13)),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
