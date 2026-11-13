import 'dart:convert';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/user_db.dart';
import '../nlp/text.dart';
import '../online/ai_service.dart';
import 'panel.dart';
import 'paragraph_view.dart';
import 'word_sheet.dart';

/// Sentence breakdown: translation, tenses, expressions and word meanings.
Future<void> showSentenceSheet(BuildContext context, AppState app, Para para, ParaAnalysis a, int ti,
    {int? bookId, String? bookTitle}) {
  final ctx = buildContext(app, para, a, ti, bookId: bookId, bookTitle: bookTitle);
  final first = ctx.sentenceTokens.isEmpty ? 0 : a.tokens.indexWhere((t) => t.start == ctx.sentenceTokens.first.start);
  final last = first + ctx.sentenceTokens.length - 1;
  final matches = a.matches.where((m) => m.tokens.every((t) => t >= first && t <= last)).toList();
  return showPanel(context, (c, sc) => SentencePanel(app: app, ctx: ctx, para: para, matches: matches, scroll: sc));
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
    // Saved earlier, or translated now when an AI service is connected.
    final saved = widget.app.user.sentenceAi(widget.ctx.sentence);
    if (saved != null) {
      onlineTr = saved.$1;
      final exp = saved.$2 == null ? null : jsonDecode(saved.$2!) as Map;
      onlineExplain = exp?['tr'] as String?;
      onlineExplainEn = exp?['en'] as String?;
    } else if (AiService.fromSettings(widget.app.user) != null) {
      _explain();
    }
  }

  Future<void> _explain() async {
    final svc = AiService.fromSettings(widget.app.user);
    if (svc == null) {
      setState(() => error = 'Çevrimiçi açıklama için Ayarlar > Yapay zekâ bölümünden bir servis bağlayın.');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final r = await svc.explainSentence(widget.ctx.sentence, widget.para.text);
      widget.app.user.setSentenceAi(widget.ctx.sentence, r.translation, jsonEncode({'tr': r.explanation, 'en': r.explanationEn}));
      if (!mounted) return;
      setState(() {
        onlineTr = r.translation;
        onlineExplain = r.explanation;
        onlineExplainEn = r.explanationEn.isEmpty ? null : r.explanationEn;
      });
    } catch (e) {
      if (mounted) setState(() => error = 'Bağlantı kurulamadı: $e');
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
    final tr = ctx.sentenceTr?.first ?? onlineTr;
    final showTr = app.showTr, showEn = app.showEn;

    Widget section(String t) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 6),
          child: Text(t.toUpperCase(), style: theme.textTheme.labelMedium?.copyWith(letterSpacing: 1.1, color: theme.hintColor)),
        );

    // group expressions by category
    final byCat = <String, List<Match>>{};
    final seen = <String>{};
    for (final m in widget.matches) {
      if (seen.add('${m.expr.cat}|${m.expr.phrase}')) byCat.putIfAbsent(m.expr.cat, () => []).add(m);
    }

    final contentWords = <Token>[];
    final seenW = <String>{};
    for (final t in ctx.sentenceTokens) {
      if (stopWords.contains(t.lower) || t.lower.length < 3) continue;
      if (seenW.add(app.primaryLemma(t.lower))) contentWords.add(t);
    }

    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
      Text('Cümle analizi', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      SelectableText(ctx.sentence, style: const TextStyle(fontSize: 18, height: 1.5, fontFamily: 'serif')),
      // Full Turkish translation right under the English sentence.
      if (tr != null && showTr)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: SelectableText(tr, style: TextStyle(fontSize: 17, height: 1.45, color: theme.colorScheme.secondary)),
        ),
      if (tr == null && loading)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Row(children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Text('Cümle çevriliyor…'),
          ]),
        ),
      const SizedBox(height: 10),
      LangToggles(app: app, onChanged: () => setState(() {})),
      if (tr == null && !loading && AiService.fromSettings(app.user) == null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
              'Tam cümle çevirisi için Ayarlar\'dan bir yapay zekâ servisi bağla. Aşağıdaki parça parça analiz internetsiz çalışır.',
              style: TextStyle(color: theme.hintColor, fontSize: 13)),
        ),
      if (error != null) ...[
        Padding(padding: const EdgeInsets.only(top: 6), child: Text(error!, style: TextStyle(color: theme.colorScheme.error))),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(onPressed: loading ? null : _explain, icon: const Icon(Icons.refresh), label: const Text('Tekrar dene')),
        ),
      ],
      if ((showEn && onlineExplainEn != null) || (showTr && onlineExplain != null)) ...[
        section('Açıklama'),
        if (showEn && onlineExplainEn != null) SelectableText(onlineExplainEn!),
        if (showEn && onlineExplainEn != null && showTr && onlineExplain != null) const SizedBox(height: 8),
        if (showTr && onlineExplain != null) SelectableText(onlineExplain!),
      ],
      if (tr != null && onlineExplain == null && !loading && AiService.fromSettings(app.user) != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(onPressed: _explain, icon: const Icon(Icons.auto_awesome), label: const Text('Ayrıntılı açıkla')),
          ),
        ),
      section('Zaman ve yapı'),
      if (tenses.isEmpty) Text('Belirgin bir fiil yapısı bulunamadı.', style: TextStyle(color: theme.hintColor)),
      for (final h in tenses)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(showTr ? (showEn ? '${h.en} · ${h.tr}' : '${h.tr} (${h.en})') : h.en,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(showTr ? '"${h.words}"  ${h.explain}' : '"${h.words}"'),
          ),
        ),
      section('Kalıplar ve kategoriler'),
      if (byCat.isEmpty) Text('Bu cümlede listelerimizdeki bir kalıp bulunamadı.', style: TextStyle(color: theme.hintColor)),
      for (final e in byCat.entries) ...[
        for (final m in e.value) ExprCard(app: app, expr: m.expr, ctx: ctx, onChanged: () => setState(() {})),
      ],
      section('Kelimeler'),
      for (final t in contentWords)
        Builder(builder: (context) {
          final lemma = app.primaryLemma(t.lower);
          final trM = showTr ? app.shortMeaning(lemma) : null;
          final enM = showEn ? app.dict.lookup(lemma).senses.firstOrNull?.gloss : null;
          final m = [?enM, if (trM != enM) ?trM].join('\n');
          final st = app.statusOf(t);
          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              radius: 6,
              backgroundColor: switch (st) {
                WordStatus.learning => learningColor,
                WordStatus.learned => learnedColor,
                _ => theme.dividerColor,
              },
            ),
            title: Text(lemma == t.lower ? t.text : '${t.text}  →  $lemma', style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: m.isEmpty ? null : Text(m, maxLines: 3, overflow: TextOverflow.ellipsis),
            onTap: () async {
              final i = ctx.sentenceTokens.indexOf(t);
              await showWordSheet(context, app, t.text,
                  ctx: WordContext(ctx.sentence, ctx.sentenceTokens, i, const [], ctx.sentenceTr, ctx.bookId, ctx.bookTitle));
              setState(() {});
            },
          );
        }),
    ]);
  }
}
