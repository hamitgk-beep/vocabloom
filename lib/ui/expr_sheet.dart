import 'dart:convert';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/user_db.dart';
import '../nlp/text.dart';
import '../online/ai_service.dart';
import '../nlp/word_family.dart';
import 'panel.dart';
import 'tap_text.dart';
import '../l10n.dart';
import 'word_sheet.dart';

/// Opens the whole expression (phrasal verb, idiom, collocation ...) that the
/// tapped word belongs to.
/// [ctx] is null when opened from a list (dictionary, word list) instead of a book.
Future<void> showExprSheet(BuildContext context, AppState app, Expr expr, WordContext? ctx, [List<String>? words]) {
  panelApp = app;
  return showPanel(context, (c, sc) => ExprPanel(app: app, expr: expr, ctx: ctx, words: words ?? expr.phrase.split(' '), scroll: sc));
}

class ExprPanel extends StatefulWidget {
  final AppState app;
  final Expr expr;
  final WordContext? ctx;
  final List<String> words; // the words of the expression as written in the book
  final ScrollController? scroll;
  const ExprPanel({super.key, required this.app, required this.expr, this.ctx, required this.words, this.scroll});

  @override
  State<ExprPanel> createState() => _ExprPanelState();
}

class _ExprPanelState extends State<ExprPanel> {
  List<ExprSense>? senses;
  bool fromAi = false;
  bool loading = false;
  String? error;

  AppState get app => widget.app;
  Expr get expr => widget.expr;
  String get _key => '${expr.phrase}|${expr.cat}';

  @override
  void initState() {
    super.initState();
    // Saved AI answer first, then the built-in library. Nothing waits for the
    // internet: the AI is only asked when the user presses the button.
    final cached = app.user.exprDetail(_key);
    final builtIn = cached == null ? app.dict.exprDetail(expr.phrase, expr.cat) : null;
    final js = cached ?? builtIn;
    if (js != null) {
      senses = [for (final s in (jsonDecode(js) as List)) ExprSense.fromJson((s as Map).cast<String, dynamic>())];
      fromAi = cached != null;
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
      final r = await svc.exprDetail(expr.phrase, expr.cat, sentence: widget.ctx?.sentence);
      if (r.isNotEmpty) app.user.setExprDetail(_key, jsonEncode([for (final s in r) s.toJson()]));
      if (mounted) {
        setState(() {
          senses = r;
          fromAi = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  /// The plain meaning of the expression's main word, e.g. "disagree:
  /// aynı fikirde olmamak" for "disagree with".
  Widget? _headWord() {
    if (expr.cat != 'phrasal_verbs' && expr.cat != 'collocations' && expr.cat != 'prepositional_phrases') return null;
    final words = expr.phrase.split(' ');
    final w = words.firstWhere((w) => w.length > 2 && !stopWords.contains(w), orElse: () => '');
    if (w.isEmpty) return null;
    final lemma = app.primaryLemma(w);
    final info = app.dict.lookup(lemma);
    // A phrasal verb starts with a verb: use the verb senses.
    final pos = expr.cat == 'phrasal_verbs' ? 'v' : (info.senses.firstOrNull?.pos ?? 'n');
    final sense = info.senses.where((s) => s.pos == pos).firstOrNull ?? info.senses.firstOrNull;
    final trM = app.showTr ? trFor(app.dict, lemma, pos) : null;
    final enM = app.showEn || trM == null ? sense?.gloss : null;
    if (trM == null && enM == null) return null;
    final theme = Theme.of(context);
    final rest = words.where((x) => x != w).join(' ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(L('Kelimelerin düz anlamı', 'Plain meaning of the words'), style: theme.textTheme.labelLarge?.copyWith(color: theme.hintColor)),
        const SizedBox(height: 2),
        Text(rest.isEmpty ? lemma : '$lemma (+ $rest)', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        if (enM != null && enM != trM) TapText(enM, style: enStyle(theme)),
        if (trM != null) Text(trM, style: trStyle(theme)),
      ]),
    );
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
                context: widget.ctx?.sentence, book: widget.ctx?.bookTitle, meaning: expr.trShown ?? expr.en);
            setState(() {});
          },
        ),
        LangToggles(app: app, onChanged: () => setState(() {})),
      ]),
      if (widget.ctx != null) ...[
        section(L('Bu cümlede', 'In this sentence')),
        SentenceText(widget.ctx!.sentence, null, highlight: widget.words.map((w) => w.toLowerCase()).toSet()),
        if (tr && widget.ctx!.sentenceTr != null) ...[
          const SizedBox(height: 6),
          Text(widget.ctx!.sentenceTr!.first, style: trStyle(theme, const TextStyle(fontStyle: FontStyle.italic), false)),
        ],
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
            Text('${i + 1}. ${en ? s.titleEn : s.titleTr}',
                style: (en ? enStyle(theme) : trStyle(theme)).copyWith(fontWeight: FontWeight.w700, fontSize: 16)),
            if (en && tr) Text(s.titleTr, style: trStyle(theme, const TextStyle(fontSize: 16))),
            if (s.inSentence)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(tr ? L('Bu cümledeki anlamı', 'Meaning in this sentence') : 'Meaning in this sentence',
                    style: theme.textTheme.labelSmall?.copyWith(color: color)),
              ),
            const SizedBox(height: 4),
            if (en) TapText(s.explainEn, style: enStyle(theme)),
            if (tr) Text(s.explainTr, style: trStyle(theme)),
            for (final ex in s.examples) ...[
              const SizedBox(height: 6),
              if (en || !tr) TapText('• ${ex.$1}', style: enStyle(theme, const TextStyle(fontStyle: FontStyle.italic), false)),
              if (tr) Padding(padding: EdgeInsets.only(left: en ? 12 : 0), child: Text(en ? ex.$2 : '• ${ex.$2}', style: trStyle(theme, null, false))),
            ],
          ]),
        ));
      }
      children.add(Text(
          fromAi ? L('Kaynak: yapay zekâ (cihaza kaydedildi)', 'Source: AI (saved on device)') : L('Kaynak: dahili sözlük', 'Source: built-in dictionary'),
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)));
    } else {
      // Offline: the plain meaning of the main word first, because dictionaries
      // often list only the special sense ("disagree with" = upset the stomach).
      final head = _headWord();
      // Without a Turkish meaning for the expression, the plain meaning leads.
      if (head != null && expr.trShown == null) children.add(head);
      final defs = (expr.en ?? '').split('; ').where((d) => d.trim().isNotEmpty).toList();
      if (defs.isNotEmpty || expr.trShown != null) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 4),
          child: Text(head == null || expr.trShown != null ? L('Kalıbın anlamı', 'Meaning of the expression') : L('Kalıp olarak özel anlamı', 'Special meaning as an expression'),
              style: theme.textTheme.labelLarge?.copyWith(color: color)),
        ));
      }
      if (tr && expr.trShown != null) {
        children.add(Text(expr.trShown!, style: trStyle(theme, const TextStyle(fontSize: 16))));
      }
      // No Turkish yet for the expression: its words one by one, so nothing is English only.
      if (tr && expr.trShown == null && head == null) {
        final g = wordGloss(app.dict, expr.phrase);
        if (g != null) children.add(Text(L('Kelime kelime: $g', 'Word by word: $g'), style: trStyle(theme)));
      }
      if (tr && expr.aiExp != null) children.add(Text(expr.aiExp!, style: trStyle(theme, null, false)));
      final defsTr = (expr.enTr ?? '').split('; ').where((d) => d.trim().isNotEmpty).toList();
      for (var i = 0; i < defs.length; i++) {
        final t = i < defsTr.length && defsTr.length == defs.length ? defsTr[i] : null;
        if (!en && tr && t == null && defsTr.isNotEmpty) continue;
        if (en || t == null) children.add(Padding(padding: const EdgeInsets.only(top: 2), child: TapText('${i + 1}. ${defs[i]}', style: enStyle(theme))));
        if (tr && t != null) children.add(Padding(padding: EdgeInsets.only(top: en ? 0 : 2, left: en ? 14 : 0), child: Text(en ? t : '${i + 1}. $t', style: trStyle(theme))));
      }
      // Turkish definitions in one piece when their number does not match the English ones.
      if (tr && defsTr.isNotEmpty && defsTr.length != defs.length) {
        children.add(Padding(padding: const EdgeInsets.only(top: 2), child: Text(defsTr.join('; '), style: trStyle(theme))));
      }
      if (tr && expr.trShown == null && defsTr.isEmpty && defs.isNotEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(L('Bu kalıbın Türkçe açıklaması henüz hazır değil; günlük sözlük güncellemeleriyle gelecek.',
                  'The Turkish explanation of this expression is not ready yet; it will come with a daily dictionary update.'),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor, fontStyle: FontStyle.italic)),
        ));
      }
      // The example only with its Turkish, unless English is on.
      if (expr.ex != null && (en || expr.exTr != null)) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 8),
          child: TapText('• ${expr.ex}', style: enStyle(theme, const TextStyle(fontStyle: FontStyle.italic), false)),
        ));
        if (tr && expr.exTr != null) {
          children.add(Padding(padding: const EdgeInsets.only(left: 12), child: Text(expr.exTr!, style: trStyle(theme, null, false))));
        }
      }
      if (head != null && expr.trShown != null) children.add(Padding(padding: const EdgeInsets.only(top: 12), child: head));
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
      } else if (error == null && AiService.fromSettings(app.user) != null) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
                onPressed: _load, icon: const Icon(Icons.auto_awesome), label: Text(L('Yapay zekâ ile ayrıntılı göster', 'Show details with AI'))),
          ),
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

    // Real sentences with translations (Tatoeba), offline.
    final exs = app.dict.examples('${expr.phrase}|${expr.cat}');
    if (exs.isNotEmpty) {
      children.add(section(L('Çevirili örnek cümleler', 'Example sentences with translations')));
      for (final (e, t) in exs) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TapText('• $e', style: enStyle(theme, const TextStyle(fontStyle: FontStyle.italic), false)),
            if (tr) Padding(padding: const EdgeInsets.only(left: 12), child: Text(t, style: trStyle(theme, null, false))),
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
