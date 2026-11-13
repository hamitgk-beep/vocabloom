import 'dart:convert';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/user_db.dart';
import '../nlp/text.dart';
import '../online/ai_service.dart';
import 'panel.dart';
import '../l10n.dart';
import 'word_sheet.dart';

/// Opens the whole expression (phrasal verb, idiom, collocation ...) that the
/// tapped word belongs to.
Future<void> showExprSheet(BuildContext context, AppState app, Expr expr, WordContext ctx, List<String> words) {
  return showPanel(context, (c, sc) => ExprPanel(app: app, expr: expr, ctx: ctx, words: words, scroll: sc));
}

class ExprPanel extends StatefulWidget {
  final AppState app;
  final Expr expr;
  final WordContext ctx;
  final List<String> words; // the words of the expression as written in the book
  final ScrollController? scroll;
  const ExprPanel({super.key, required this.app, required this.expr, required this.ctx, required this.words, this.scroll});

  @override
  State<ExprPanel> createState() => _ExprPanelState();
}

class _ExprPanelState extends State<ExprPanel> {
  List<ExprSense>? senses;
  bool loading = false;
  String? error;

  AppState get app => widget.app;
  Expr get expr => widget.expr;
  String get _key => '${expr.phrase}|${expr.cat}';

  @override
  void initState() {
    super.initState();
    final cached = app.user.exprDetail(_key);
    if (cached != null) {
      senses = [for (final s in (jsonDecode(cached) as List)) ExprSense.fromJson((s as Map).cast<String, dynamic>())];
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    final svc = AiService.fromSettings(app.user);
    if (svc == null) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final r = await svc.exprDetail(expr.phrase, expr.cat, sentence: widget.ctx.sentence);
      if (r.isNotEmpty) app.user.setExprDetail(_key, jsonEncode([for (final s in r) s.toJson()]));
      if (mounted) setState(() => senses = r);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = categoryById[expr.cat]!;
    final en = app.showEn, tr = app.showTr;
    final st = app.user.statuses[expr.phrase] ?? WordStatus.none;
    final color = theme.brightness == Brightness.dark ? Color.lerp(c.color, Colors.white, 0.35)! : c.color;

    Widget section(String t) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 6),
          child: Text(t.toUpperCase(), style: theme.textTheme.labelMedium?.copyWith(letterSpacing: 1.1, color: theme.hintColor)),
        );

    final children = <Widget>[
      Text(expr.phrase, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 2),
      Text(uiEnglish || (en && !tr) ? c.name : (en ? '${c.name} · ${c.tr}' : c.tr), style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        StatusButtons(
          status: st,
          onChanged: (s) {
            app.setWord(expr.phrase, s,
                context: widget.ctx.sentence, book: widget.ctx.bookTitle, meaning: expr.trShown ?? expr.en);
            setState(() {});
          },
        ),
        LangToggles(app: app, onChanged: () => setState(() {})),
      ]),
      section(L('Bu cümlede', 'In this sentence')),
      SentenceText(widget.ctx.sentence, null, highlight: widget.words.map((w) => w.toLowerCase()).toSet()),
      if (tr && widget.ctx.sentenceTr != null) ...[
        const SizedBox(height: 6),
        Text(widget.ctx.sentenceTr!.first, style: TextStyle(fontStyle: FontStyle.italic, color: theme.colorScheme.secondary)),
      ],
      section(L('Anlamları ve örnekler', 'Meanings and examples')),
    ];

    if (senses != null && senses!.isNotEmpty) {
      for (var i = 0; i < senses!.length; i++) {
        final s = senses![i];
        children.add(Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: color, width: 4)),
            color: s.inSentence ? c.color.withValues(alpha: 0.12) : theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${i + 1}. ${en ? s.titleEn : s.titleTr}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            if (en && tr) Text(s.titleTr, style: TextStyle(fontWeight: FontWeight.w600, color: theme.colorScheme.secondary)),
            if (s.inSentence)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(tr ? L('Bu cümledeki anlamı', 'Meaning in this sentence') : 'Meaning in this sentence',
                    style: theme.textTheme.labelSmall?.copyWith(color: color)),
              ),
            const SizedBox(height: 4),
            if (en) Text(s.explainEn),
            if (tr) Text(s.explainTr, style: TextStyle(color: en ? theme.colorScheme.secondary : null)),
            for (final ex in s.examples) ...[
              const SizedBox(height: 6),
              if (en || !tr) Text('• ${ex.$1}', style: const TextStyle(fontStyle: FontStyle.italic)),
              if (tr) Padding(padding: EdgeInsets.only(left: en ? 12 : 0), child: Text(en ? ex.$2 : '• ${ex.$2}', style: TextStyle(color: theme.hintColor))),
            ],
          ]),
        ));
      }
      children.add(Text(L('Kaynak: yapay zekâ (cihaza kaydedildi)', 'Source: AI (saved on device)'), style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)));
    } else {
      // Offline: dictionary definitions.
      final defs = (expr.en ?? '').split('; ').where((d) => d.trim().isNotEmpty).toList();
      if (en) {
        for (var i = 0; i < defs.length; i++) {
          children.add(Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('${i + 1}. ${defs[i]}')));
        }
      }
      if (tr && expr.trShown != null) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(expr.trShown!, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        ));
      }
      if (tr && expr.aiExp != null) children.add(Text(expr.aiExp!));
      if (expr.ex != null) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('• ${expr.ex}', style: const TextStyle(fontStyle: FontStyle.italic)),
        ));
      }
      if (defs.isEmpty && expr.trShown == null) children.add(Text(L('Sözlükte açıklama yok.', 'No explanation in the dictionary.'), style: TextStyle(color: theme.hintColor)));
      if (loading) {
        children.add(Padding(
          padding: EdgeInsets.only(top: 12),
          child: Row(children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Text(L('Anlamlar ve örnekler hazırlanıyor…', 'Preparing meanings and examples…')),
          ]),
        ));
      } else if (AiService.fromSettings(app.user) == null) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
              L('Ayarlar\'dan bir yapay zekâ servisi bağlarsan her anlam için Türkçe açıklama ve çevirili örnek cümleler de gelir.', 'Connect an AI service in Settings to also get a Turkish explanation and translated example sentences for each meaning.'),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
        ));
      } else if (error != null) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(error!, style: TextStyle(color: theme.colorScheme.error)),
            TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: Text(L('Tekrar dene', 'Try again'))),
          ]),
        ));
      }
    }

    // The single words of the expression.
    children.add(section(L('Kalıptaki kelimeler', 'Words in the expression')));
    children.add(Wrap(spacing: 8, runSpacing: 8, children: [
      for (final w in widget.words)
        ActionChip(
          label: Text(w),
          onPressed: () => showWordSheet(context, app, w, ctx: widget.ctx),
        ),
    ]));

    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: children);
  }
}
