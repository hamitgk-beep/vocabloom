import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n.dart';
import '../../ai/grammar_chat.dart';
import '../../ai/local_ai.dart';
import '../../ai/tutor.dart';

enum AiTool {
  explain(Icons.lightbulb_outline_rounded, Color(0xFF5B3FD9)),
  correct(Icons.spellcheck_rounded, Color(0xFF0E9F6E)),
  chat(Icons.forum_outlined, Color(0xFF2563EB)),
  quiz(Icons.quiz_outlined, Color(0xFFE0752D));

  final IconData icon;
  final Color color;
  const AiTool(this.icon, this.color);

  String get title => switch (this) {
        explain => L('Cümleyi açıkla', 'Explain a sentence'),
        correct => L('Yazdığımı düzelt', 'Correct my writing'),
        chat => L('Sohbet pratiği', 'Chat practice'),
        quiz => L('Kelime testi', 'Word quiz'),
      };

  String get subtitle => switch (this) {
        explain => L('Anlamı, dilbilgisi ve kalıpları Türkçe anlatır', 'Meaning, grammar and patterns explained in Turkish'),
        correct => L('Hataları düzeltir ve nedenini söyler', 'Fixes mistakes and tells you why'),
        chat => L('Seviyene göre İngilizce konuş', 'Talk in English at your level'),
        quiz => L('Öğrendiğin kelimelerden sorular', 'Questions from the words you learn'),
      };
}

/// Answers use **bold** headings and "- " bullets; a chat line starting with
/// "💡 " is the Turkish correction hint. Drawn without a Markdown package.
Widget aiRichText(String text, TextStyle? style, {Color? hintColor}) {
  final lines = text.split('\n');
  final main = <String>[];
  String? hint;
  for (final l in lines) {
    if (l.trimLeft().startsWith('💡')) {
      hint = l.trimLeft().substring(2).trim();
    } else {
      main.add(l.startsWith('- ') ? '•  ${l.substring(2)}' : l);
    }
  }
  final parts = main.join('\n').trim().split('**');
  final body = SelectableText.rich(TextSpan(style: style, children: [
    for (var i = 0; i < parts.length; i++)
      TextSpan(text: parts[i], style: i.isOdd ? const TextStyle(fontWeight: FontWeight.w800) : null),
  ]));
  if (hint == null || hint.isEmpty) return body;
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    body,
    Builder(builder: (context) {
      final t = Theme.of(context);
      final c = hintColor ?? const Color(0xFFB45309);
      return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.tips_and_updates_outlined, size: 16, color: c),
          const SizedBox(width: 6),
          Expanded(child: Text(hint!, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurface, height: 1.4))),
        ]),
      );
    }),
  ]);
}

String aiError(Object e) => e is AiException ? e.message : L('Yanıt üretilemedi. Tekrar dene.', 'Could not produce an answer. Try again.');

class AiDisclaimer extends StatelessWidget {
  const AiDisclaimer({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(children: [
        Icon(Icons.info_outline_rounded, size: 14, color: t.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(L('Yapay zekâ yanılabilir; önemli konularda sözlükle doğrula.', 'AI can make mistakes; check important points in the dictionary.'),
              style: t.textTheme.bodySmall),
        ),
      ]),
    );
  }
}

class AiToolPage extends StatelessWidget {
  final AiTool tool;
  final LocalAi ai;
  final Tutor tutor;
  final String? initialText;
  final List<String>? quizWords;
  const AiToolPage({super.key, required this.tool, required this.ai, required this.tutor, this.initialText, this.quizWords});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          Icon(tool.icon, color: tool.color),
          const SizedBox(width: 10),
          Text(tool.title, style: theme.textTheme.titleLarge),
        ]),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: switch (tool) {
            AiTool.explain => _AskView(
                hint: L('İngilizce bir cümle yapıştır ya da yaz', 'Paste or type an English sentence'),
                button: L('Açıkla', 'Explain'),
                initial: initialText,
                run: (s) => tutor.explainSentence(s),
                color: tool.color),
            AiTool.correct => _AskView(
                hint: L('İngilizce yazdığın cümleyi ya da paragrafı gir', 'Enter a sentence or paragraph you wrote in English'),
                button: L('Düzelt', 'Correct'),
                initial: initialText,
                run: tutor.correct,
                color: tool.color),
            AiTool.chat => _ChatView(tutor: tutor),
            AiTool.quiz => _QuizView(tutor: tutor, words: quizWords),
          },
        ),
      ),
    );
  }
}

class _AskView extends StatefulWidget {
  final String hint, button;
  final String? initial;
  final Stream<String> Function(String) run;
  final Color color;
  const _AskView({required this.hint, required this.button, required this.run, required this.color, this.initial});

  @override
  State<_AskView> createState() => _AskViewState();
}

class _AskViewState extends State<_AskView> {
  late final input = TextEditingController(text: widget.initial ?? '');
  String answer = '';
  bool busy = false;
  StreamSubscription<String>? sub;

  @override
  void initState() {
    super.initState();
    if ((widget.initial ?? '').trim().isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _go());
  }

  @override
  void dispose() {
    sub?.cancel();
    input.dispose();
    super.dispose();
  }

  void _go() {
    final s = input.text.trim();
    if (s.isEmpty || busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      answer = '';
      busy = true;
    });
    sub = widget.run(s).listen((c) => setState(() => answer += c), onDone: () => setState(() => busy = false), onError: (Object e) {
      setState(() {
        busy = false;
        answer = aiError(e);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ListView(padding: const EdgeInsets.all(16), children: [
      TextField(
        controller: input,
        minLines: 3,
        maxLines: 8,
        textInputAction: TextInputAction.newline,
        decoration: InputDecoration(hintText: widget.hint),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: busy ? null : _go,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome_rounded, size: 20),
        label: Text(busy ? L('Düşünüyor…', 'Thinking…') : widget.button),
      ),
      if (answer.isNotEmpty) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.auto_awesome_rounded, size: 16, color: widget.color),
              const SizedBox(width: 6),
              Text(L('Yapay zekâ öğretmen', 'AI tutor'), style: theme.textTheme.labelLarge?.copyWith(color: widget.color, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 10),
            aiRichText(answer.trim(), theme.textTheme.bodyLarge?.copyWith(height: 1.55)),
          ]),
        ),
        if (!busy) const AiDisclaimer(),
      ],
    ]);
  }
}

class _ChatView extends StatefulWidget {
  final Tutor tutor;
  const _ChatView({required this.tutor});

  @override
  State<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<_ChatView> {
  final msgs = <(String, String)>[];
  final input = TextEditingController();
  final scroll = ScrollController();
  String level = 'B1';
  String? topic;
  bool busy = false;
  StreamSubscription<String>? sub;
  final session = TutorChatSession();

  static const topics = [('Kitaplar', 'Books'), ('Seyahat', 'Travel'), ('İş görüşmesi', 'Job interview'), ('Günlük hayat', 'Daily life')];

  @override
  void dispose() {
    sub?.cancel();
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  void _send([String? text]) {
    final s = (text ?? input.text).trim();
    if (s.isEmpty || busy) return;
    input.clear();
    setState(() {
      msgs.add(('user', s));
      msgs.add(('assistant', ''));
      busy = true;
    });
    final history = msgs.sublist(0, msgs.length - 1);
    sub = widget.tutor.chat(session, history, level: level, topic: topic).listen((c) {
      setState(() => msgs[msgs.length - 1] = ('assistant', msgs.last.$2 + c));
      _toEnd();
    }, onDone: () => setState(() => busy = false), onError: (Object e) => setState(() {
          busy = false;
          msgs[msgs.length - 1] = ('assistant', aiError(e));
        }));
    _toEnd();
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(children: [
      Expanded(
        child: ListView(controller: scroll, padding: const EdgeInsets.all(16), children: [
          if (msgs.isEmpty) ...[
            Text(L('Seviyen', 'Your level'), style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [for (final l in ['A2', 'B1', 'B2', 'C1']) ButtonSegment(value: l, label: Text(l))],
              selected: {level},
              onSelectionChanged: (s) => setState(() => level = s.first),
            ),
            const SizedBox(height: 18),
            Text(L('Bir konu seç ya da istediğini yaz', 'Pick a topic or write anything'), style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final t in topics)
                ActionChip(
                  label: Text(uiEnglish ? t.$2 : t.$1),
                  onPressed: () {
                    topic = t.$2;
                    // The learner's opening line is English practice in both interface languages.
                    _send("Let's talk about ${t.$2.toLowerCase()}.");
                  },
                ),
            ]),
            const SizedBox(height: 18),
            Text(
              L('Yapay zekâ seviyene uygun İngilizce cevap verir ve hatalarını nazikçe düzeltir. Gramer de çalışabilirsin: "Bugün modals çalışalım", "Relative clause anlat" ya da "Bana passive cümleleri sor" yaz.',
                  'The AI answers in English at your level and gently corrects your mistakes. You can also study grammar: write "Let\'s study modals", "Explain relative clauses" or "Quiz me on the passive".'),
              style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
            ),
          ],
          for (final m in msgs)
            Align(
              alignment: m.$1 == 'user' ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 520),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: m.$1 == 'user' ? cs.primary : cs.surface,
                  border: m.$1 == 'user' ? null : Border.all(color: cs.outlineVariant),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(m.$1 == 'user' ? 18 : 4),
                    bottomRight: Radius.circular(m.$1 == 'user' ? 4 : 18),
                  ),
                ),
                child: m.$2.isEmpty
                    ? AiWaiting(ai: widget.tutor.ai)
                    : aiRichText(m.$2.trim(), theme.textTheme.bodyLarge?.copyWith(color: m.$1 == 'user' ? cs.onPrimary : cs.onSurface, height: 1.45)),
              ),
            ),
          if (msgs.isNotEmpty && !busy) const AiDisclaimer(),
        ]),
      ),
      SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(color: cs.surface, border: Border(top: BorderSide(color: cs.outlineVariant))),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: input,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(hintText: L('İngilizce yaz…', 'Write in English…'), isDense: true),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filled(onPressed: busy ? null : _send, icon: const Icon(Icons.arrow_upward_rounded)),
          ]),
        ),
      ),
    ]);
  }
}

class _QuizView extends StatefulWidget {
  final Tutor tutor;
  final List<String>? words;
  const _QuizView({required this.tutor, required this.words});

  @override
  State<_QuizView> createState() => _QuizViewState();
}

class _QuizViewState extends State<_QuizView> {
  List<QuizItem>? items;
  int i = 0, right = 0;
  int? picked;
  String? error;
  String more = '';
  bool moreBusy = false;
  StreamSubscription<String>? moreSub;

  @override
  void dispose() {
    moreSub?.cancel();
    super.dispose();
  }

  void _explain(QuizItem q) {
    setState(() => moreBusy = true);
    moreSub = widget.tutor.explain(q).listen((c) => setState(() => more += c),
        onDone: () => setState(() => moreBusy = false),
        onError: (Object e) => setState(() {
              moreBusy = false;
              more = aiError(e);
            }));
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      items = null;
      error = null;
      i = 0;
      right = 0;
      picked = null;
    });
    try {
      final q = await widget.tutor.quiz(words: widget.words);
      if (mounted) setState(() => items = q);
    } catch (e) {
      if (mounted) setState(() => error = e is AiException ? e.message : L('Test hazırlanamadı. Tekrar dene.', 'Could not build the quiz. Try again.'));
    }
    if (mounted && items != null && items!.isEmpty) {
      setState(() => error = L('Test için önce birkaç kelimeyi "Öğreneceğim" listene ekle.', 'Add a few words to your "To learn" list first.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (error != null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(error!), const SizedBox(height: 12), FilledButton(onPressed: _load, child: Text(L('Tekrar dene', 'Try again')))]));
    }
    final qs = items;
    if (qs == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 14),
          Text(L('Öğrendiğin kelimelerden sorular hazırlanıyor…', 'Building questions from your words…'), style: theme.textTheme.bodyMedium),
        ]),
      );
    }
    if (i >= qs.length) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.emoji_events_rounded, size: 64, color: AiTool.quiz.color),
            const SizedBox(height: 12),
            Text('$right / ${qs.length}', style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(L('doğru cevap', 'correct answers'), style: theme.textTheme.bodyLarge),
            const SizedBox(height: 20),
            FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: Text(L('Yeni test', 'New quiz'))),
          ]),
        ),
      );
    }
    final q = qs[i];
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Text(L('Soru ${i + 1} / ${qs.length}', 'Question ${i + 1} of ${qs.length}'), style: theme.textTheme.labelLarge),
        const Spacer(),
        Text(L('$right doğru', '$right correct'), style: theme.textTheme.labelLarge?.copyWith(color: const Color(0xFF15803D))),
      ]),
      const SizedBox(height: 8),
      ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: i / qs.length, minHeight: 6)),
      const SizedBox(height: 20),
      if (q.promptTr.isNotEmpty) ...[
        Text(q.promptTr, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 6),
      ],
      Text(q.question, style: theme.textTheme.titleLarge?.copyWith(height: 1.4)),
      const SizedBox(height: 16),
      for (var k = 0; k < q.options.length; k++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: picked == null
                ? cs.surface
                : k == q.answer
                    ? const Color(0xFF16A34A).withValues(alpha: 0.14)
                    : k == picked
                        ? cs.error.withValues(alpha: 0.16)
                        : cs.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: picked != null && k == q.answer ? const Color(0xFF16A34A) : cs.outlineVariant),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: picked != null
                  ? null
                  : () => setState(() {
                        picked = k;
                        if (k == q.answer) right++;
                      }),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(children: [
                  Expanded(child: Text(q.options[k], style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600))),
                  if (picked != null && k == q.answer) const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A)),
                  if (picked == k && k != q.answer) Icon(Icons.cancel_rounded, color: cs.error),
                ]),
              ),
            ),
          ),
        ),
      if (picked != null) ...[
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(q.explanationTr, style: theme.textTheme.bodyMedium?.copyWith(height: 1.45)),
            if (more.isNotEmpty) ...[
              const Divider(height: 20),
              aiRichText(more, theme.textTheme.bodyMedium?.copyWith(height: 1.45)),
            ],
            if (more.isEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: moreBusy ? null : () => _explain(q),
                  icon: moreBusy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: Text(L('Yapay zekâ ile ayrıntılı açıkla', 'Explain in detail with AI')),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: () => setState(() {
            i++;
            picked = null;
            moreSub?.cancel();
            more = '';
            moreBusy = false;
          }),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: Text(i + 1 < qs.length ? L('Sonraki soru', 'Next question') : L('Sonucu gör', 'See result')),
        ),
      ],
    ]);
  }
}

/// What the learner sees before the first word of an answer: loading the
/// model into memory takes a while the first time, so say so.
class AiWaiting extends StatelessWidget {
  final LocalAi ai;
  const AiWaiting({super.key, required this.ai});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: ai,
      builder: (c, _) => Row(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            ai.loaded
                ? L('Yapay zekâ düşünüyor…', 'The AI is thinking…')
                : L('Yapay zekâ belleğe yükleniyor… İlk seferde 1 dakikayı bulabilir.', 'Loading the AI into memory… The first time can take a minute.'),
            style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
          ),
        ),
      ]),
    );
  }
}
