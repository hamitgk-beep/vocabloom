import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/user_db.dart';
import '../nlp/text.dart';
import '../online/ai_service.dart';
import 'paragraph_view.dart';
import 'word_sheet.dart';

/// Sentence breakdown: translation, tenses, expressions and word meanings.
Future<void> showSentenceSheet(BuildContext context, AppState app, Para para, ParaAnalysis a, int ti,
    {int? bookId, String? bookTitle}) {
  final ctx = buildContext(app, para, a, ti, bookId: bookId, bookTitle: bookTitle);
  final first = ctx.sentenceTokens.isEmpty ? 0 : a.tokens.indexWhere((t) => t.start == ctx.sentenceTokens.first.start);
  final last = first + ctx.sentenceTokens.length - 1;
  final matches = a.matches.where((m) => m.tokens.every((t) => t >= first && t <= last)).toList();
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 760),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (c, sc) => SentencePanel(app: app, ctx: ctx, para: para, matches: matches, scroll: sc),
    ),
  );
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
  bool loading = false;
  String? error;

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
      setState(() {
        onlineTr = r.translation;
        onlineExplain = r.explanation;
      });
    } catch (e) {
      setState(() => error = 'Bağlantı kurulamadı: $e');
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
      const SizedBox(height: 8),
      LangToggles(app: app, onChanged: () => setState(() {})),
      section('Çeviri'),
      if (tr != null && app.showTr) SelectableText(tr, style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic, color: theme.colorScheme.secondary)),
      if (onlineExplain != null) Padding(padding: const EdgeInsets.only(top: 8), child: SelectableText(onlineExplain!)),
      if (tr == null || onlineExplain == null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            FilledButton.tonalIcon(
              onPressed: loading ? null : _explain,
              icon: loading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome),
              label: Text(tr == null ? 'Çevrimiçi çevir ve açıkla' : 'Çevrimiçi ayrıntılı açıkla'),
            ),
          ]),
        ),
      if (tr == null && onlineTr == null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Çevrimdışıyken tam cümle çevirisi yok; aşağıdaki parça parça analiz çevrimdışı çalışır.',
              style: TextStyle(color: theme.hintColor, fontSize: 13)),
        ),
      if (error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(error!, style: TextStyle(color: theme.colorScheme.error))),
      section('Zaman ve yapı'),
      if (tenses.isEmpty) Text('Belirgin bir fiil yapısı bulunamadı.', style: TextStyle(color: theme.hintColor)),
      for (final h in tenses)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text('${h.en} · ${h.tr}', style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('"${h.words}"  ${h.explain}'),
          ),
        ),
      section('Kalıplar ve kategoriler'),
      if (byCat.isEmpty) Text('Bu cümlede listelerimizdeki bir kalıp bulunamadı.', style: TextStyle(color: theme.hintColor)),
      for (final e in byCat.entries) ...[
        for (final m in e.value) ExprCard(app: app, expr: m.expr, onChanged: () => setState(() {})),
      ],
      section('Kelimeler'),
      for (final t in contentWords)
        Builder(builder: (context) {
          final lemma = app.primaryLemma(t.lower);
          final m = app.shortMeaning(lemma);
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
            subtitle: m == null ? null : Text(m, maxLines: 2, overflow: TextOverflow.ellipsis),
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
