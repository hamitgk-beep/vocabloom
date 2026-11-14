import 'dart:async';

import 'package:flutter/material.dart';

import '../../ai/grammar_practice.dart';
import '../../ai/tutor.dart';
import '../../app_state.dart';
import '../../l10n.dart';
import '../ai/ai_page.dart';
import '../ai/ai_tools.dart';
import '../tap_text.dart';
import '../theme.dart';

const _green = Color(0xFF16A34A);

Color _levelColor(String level) => switch (level) {
      'A1' || 'A2' => const Color(0xFF0E9F6E),
      'B1' => const Color(0xFF2563EB),
      'B2' => const Color(0xFF7C3AED),
      _ => const Color(0xFFE0752D),
    };

class _LevelChip extends StatelessWidget {
  final String level;
  const _LevelChip(this.level);

  @override
  Widget build(BuildContext context) {
    final c = _levelColor(level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(8)),
      child: Text(level, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 12)),
    );
  }
}

/// The "Gramer" tab: lessons grouped by category, each with practice.
class GrammarPage extends StatefulWidget {
  final AppState app;
  const GrammarPage({super.key, required this.app});

  @override
  State<GrammarPage> createState() => _GrammarPageState();
}

class _GrammarPageState extends State<GrammarPage> {
  List<GrammarTopic>? topics;
  late final progress = GrammarProgress(widget.app.user);

  @override
  void initState() {
    super.initState();
    loadGrammarTopics().then((t) => mounted ? setState(() => topics = t) : null);
  }

  Future<void> _open(GrammarTopic t) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GrammarTopicPage(app: widget.app, topic: t)));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ts = topics;
    final total = ts?.fold<int>(0, (a, t) => a + t.exercises.length) ?? 0;
    final done = ts?.fold<int>(0, (a, t) => a + progress.done(t.id).length) ?? 0;
    return Scaffold(
      appBar: AppBar(toolbarHeight: 68, title: Text(L('Gramer', 'Grammar'), style: theme.textTheme.headlineSmall)),
      body: ts == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(gradient: Brand.gradient, borderRadius: BorderRadius.circular(22)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(L('Kuralı öğren, cümleyle pekiştir', 'Learn the rule, practise with sentences'),
                          style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text(
                        L('Her konuda kısa bir Türkçe anlatım, yapı kalıpları ve örnekler var. Sonra Türkçe cümleleri İngilizceye çevirirsin; doğru mu, nasıl daha doğal söylenir, hemen görürsün.',
                            'Each topic has a short explanation in Turkish, patterns and examples. Then you translate Turkish sentences into English and see at once whether they are right and how to say them more naturally.'),
                        style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.9), height: 1.45),
                      ),
                      const SizedBox(height: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: total == 0 ? 0 : done / total,
                          minHeight: 6,
                          backgroundColor: Colors.white.withValues(alpha: 0.2),
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(L('$done / $total cümle tamamlandı', '$done of $total sentences done'),
                          style: theme.textTheme.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                  for (final cat in grammarCategories.entries)
                    if (ts.any((t) => t.category == cat.key)) ...[
                      SectionLabel(uiEnglish ? cat.value.$2 : cat.value.$1),
                      Material(
                        color: cs.surface,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: cs.outlineVariant)),
                        clipBehavior: Clip.antiAlias,
                        child: Column(children: [
                          for (final (i, t) in ts.where((t) => t.category == cat.key).indexed) ...[
                            if (i > 0) Divider(height: 1, indent: 16, endIndent: 16, color: cs.outlineVariant),
                            _TopicTile(topic: t, done: progress.done(t.id).length, onTap: () => _open(t)),
                          ],
                        ]),
                      ),
                    ],
                ]),
              ),
            ),
    );
  }
}

class _TopicTile extends StatelessWidget {
  final GrammarTopic topic;
  final int done;
  final VoidCallback onTap;
  const _TopicTile({required this.topic, required this.done, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final n = topic.exercises.length;
    final complete = n > 0 && done >= n;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(topic.titleTr, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                const SizedBox(width: 8),
                _LevelChip(topic.level),
              ]),
              const SizedBox(height: 2),
              Text(topic.titleEn, style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              Row(children: [
                SizedBox(
                  width: 110,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(value: n == 0 ? 0 : done / n, minHeight: 5, color: complete ? _green : cs.primary),
                  ),
                ),
                const SizedBox(width: 8),
                Text('$done/$n', style: theme.textTheme.labelMedium?.copyWith(color: complete ? _green : cs.onSurfaceVariant)),
              ]),
            ]),
          ),
          Icon(complete ? Icons.check_circle_rounded : Icons.chevron_right_rounded, color: complete ? _green : cs.onSurfaceVariant),
        ]),
      ),
    );
  }
}

/// One lesson: explanation, patterns, examples, then practice.
class GrammarTopicPage extends StatefulWidget {
  final AppState app;
  final GrammarTopic topic;
  const GrammarTopicPage({super.key, required this.app, required this.topic});

  @override
  State<GrammarTopicPage> createState() => _GrammarTopicPageState();
}

class _GrammarTopicPageState extends State<GrammarTopicPage> {
  late final progress = GrammarProgress(widget.app.user);

  @override
  void initState() {
    super.initState();
    panelApp = widget.app;
  }

  Future<void> _practice() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GrammarPracticePage(app: widget.app, topic: widget.topic)));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final t = widget.topic;
    final done = progress.done(t.id).length;
    final n = t.exercises.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.titleTr),
        actions: [
          if (done > 0)
            PopupMenuButton<String>(
              onSelected: (_) => setState(() => progress.reset(t.id)),
              itemBuilder: (_) => [PopupMenuItem(value: 'reset', child: Text(L('İlerlemeyi sıfırla', 'Reset progress')))],
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 110), children: [
            Row(children: [
              _LevelChip(t.level),
              const SizedBox(width: 8),
              Text(t.titleEn, style: theme.textTheme.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
            const SizedBox(height: 14),
            Panel(children: [aiRichText(t.explanationTr, theme.textTheme.bodyLarge?.copyWith(height: 1.55))]),
            if (t.structureTr.isNotEmpty) ...[
              SectionLabel(L('Yapı', 'Pattern')),
              for (final s in t.structureTr)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
                  ),
                  child: Text(s, style: theme.textTheme.titleSmall?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w700)),
                ),
            ],
            if (t.examples.isNotEmpty) ...[
              SectionLabel(L('Örnekler', 'Examples')),
              Panel(children: [
                for (final (i, e) in t.examples.indexed) ...[
                  if (i > 0) const SizedBox(height: 12),
                  TapText(e.$1, style: theme.textTheme.bodyLarge?.copyWith(color: cs.primary, fontWeight: FontWeight.w600, fontStyle: FontStyle.italic)),
                  const SizedBox(height: 2),
                  Text(e.$2, style: theme.textTheme.bodyMedium),
                ],
              ]),
            ],
          ]),
        ),
      ),
      bottomNavigationBar: n == 0
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _practice,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                  icon: Icon(done >= n ? Icons.replay_rounded : Icons.edit_note_rounded),
                  label: Text(done == 0
                      ? L('Pratiğe başla · $n cümle', 'Start practice · $n sentences')
                      : done >= n
                          ? L('Tekrar çalış', 'Practise again')
                          : L('Devam et · $done/$n', 'Continue · $done/$n')),
                ),
              ),
            ),
    );
  }
}

/// Translate Turkish sentences into English and get feedback.
class GrammarPracticePage extends StatefulWidget {
  final AppState app;
  final GrammarTopic topic;
  const GrammarPracticePage({super.key, required this.app, required this.topic});

  @override
  State<GrammarPracticePage> createState() => _GrammarPracticePageState();
}

enum _State { asking, checking, right, feedback, noModel }

class _GrammarPracticePageState extends State<GrammarPracticePage> {
  late final progress = GrammarProgress(widget.app.user);
  late final tutor = Tutor.of(widget.app);
  final input = TextEditingController();
  late List<GrammarExercise> queue;
  int index = 0;
  _State state = _State.asking;
  String feedback = '';
  StreamSubscription<String>? sub;

  GrammarTopic get t => widget.topic;
  GrammarExercise get e => queue[index];

  @override
  void initState() {
    super.initState();
    final done = progress.done(t.id);
    if (done.length >= t.exercises.length) progress.reset(t.id);
    final d = progress.done(t.id);
    queue = [...t.exercises.where((x) => !d.contains(x.id)), ...t.exercises.where((x) => d.contains(x.id))];
  }

  @override
  void dispose() {
    sub?.cancel();
    input.dispose();
    super.dispose();
  }

  void _submit() {
    final a = input.text.trim();
    if (a.isEmpty || state != _State.asking) return;
    FocusScope.of(context).unfocus();
    if (tutor.isCorrectTranslation(e, a)) {
      progress.markDone(t.id, e.id);
      setState(() {
        state = _State.right;
        feedback = '';
      });
      sub = tutor.checkTranslation(t, e, a).listen((c) => setState(() => feedback += c));
      return;
    }
    setState(() {
      state = _State.checking;
      feedback = '';
    });
    sub = tutor.checkTranslation(t, e, a).listen(
      (c) => setState(() {
        state = _State.feedback;
        feedback += c;
      }),
      onDone: () {
        progress.markDone(t.id, e.id);
        if (mounted && state != _State.noModel) setState(() => state = _State.feedback);
      },
      onError: (Object err) {
        progress.markDone(t.id, e.id);
        if (mounted) setState(() => state = _State.noModel);
      },
    );
  }

  void _next() {
    sub?.cancel();
    input.clear();
    setState(() {
      index++;
      state = _State.asking;
      feedback = '';
    });
  }

  void _openAi() {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AiPage(ai: widget.app.localAi, tutor: tutor)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (index >= queue.length) return _finished(theme);
    final answered = state != _State.asking && state != _State.checking;
    return Scaffold(
      appBar: AppBar(title: Text(t.titleTr)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              Text(L('Cümle ${index + 1} / ${queue.length}', 'Sentence ${index + 1} of ${queue.length}'), style: theme.textTheme.labelLarge),
              const Spacer(),
              _LevelChip(t.level),
            ]),
            const SizedBox(height: 8),
            ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: index / queue.length, minHeight: 6)),
            const SizedBox(height: 18),
            Text(L('Bu cümleyi İngilizceye çevir', 'Translate this sentence into English'),
                style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: cs.outlineVariant)),
              child: Text(e.tr, style: theme.textTheme.titleLarge?.copyWith(height: 1.4, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: input,
              enabled: state == _State.asking,
              minLines: 2,
              maxLines: 5,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(hintText: L('İngilizcesini yaz…', 'Write it in English…')),
            ),
            const SizedBox(height: 12),
            if (!answered)
              FilledButton.icon(
                onPressed: state == _State.checking ? null : _submit,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                icon: state == _State.checking
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded, size: 20),
                label: Text(state == _State.checking ? L('Kontrol ediliyor…', 'Checking…') : L('Gönder', 'Submit')),
              ),
            if (state == _State.right) _resultCard(theme, ok: true, child: aiRichText(feedback.isEmpty ? L('Harika, tamamen doğru! 🎉', 'Great, exactly right! 🎉') : feedback, theme.textTheme.bodyLarge?.copyWith(height: 1.5))),
            if (state == _State.feedback && feedback.isNotEmpty) ...[
              _resultCard(theme, ok: false, child: aiRichText(feedback, theme.textTheme.bodyLarge?.copyWith(height: 1.5))),
              const AiDisclaimer(),
            ],
            if (state == _State.noModel)
              _resultCard(
                theme,
                ok: false,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(L('Doğru kurulumlar', 'Correct versions'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  for (final a in e.answers.take(3))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('•  $a', style: theme.textTheme.bodyLarge?.copyWith(color: cs.primary, fontWeight: FontWeight.w600)),
                    ),
                  if (e.noteTr.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.rule_rounded, size: 18, color: cs.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(child: Text(e.noteTr, style: theme.textTheme.bodyMedium?.copyWith(height: 1.45))),
                    ]),
                  ],
                  const Divider(height: 24),
                  Text(
                    L('Cevabındaki hataların tek tek açıklanması için yapay zekâ modeli gerekir.', 'A detailed explanation of your mistakes needs the AI model.'),
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                  ),
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: _openAi,
                    icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: Text(L('Yapay zekâ modelini indir', 'Download the AI model')),
                  ),
                ]),
              ),
            if (answered) ...[
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _next,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                child: Text(index + 1 < queue.length ? L('Sıradaki cümle', 'Next sentence') : L('Konuyu bitir', 'Finish topic')),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _resultCard(ThemeData theme, {required bool ok, required Widget child}) {
    final cs = theme.colorScheme;
    final c = ok ? _green : const Color(0xFFD97706);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(18), border: Border.all(color: c.withValues(alpha: 0.45))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(ok ? Icons.check_circle_rounded : Icons.lightbulb_rounded, color: c, size: 20),
          const SizedBox(width: 6),
          Text(ok ? L('Doğru', 'Correct') : L('Geri bildirim', 'Feedback'), style: theme.textTheme.titleSmall?.copyWith(color: c, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 8),
        DefaultTextStyle.merge(style: TextStyle(color: cs.onSurface), child: child),
      ]),
    );
  }

  Widget _finished(ThemeData theme) {
    return Scaffold(
      appBar: AppBar(title: Text(t.titleTr)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.emoji_events_rounded, size: 72, color: Color(0xFFE0752D)),
            const SizedBox(height: 14),
            Text(L('Konu tamamlandı!', 'Topic complete!'), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(L('${queue.length} cümlenin hepsini çalıştın.', 'You practised all ${queue.length} sentences.'), style: theme.textTheme.bodyLarge),
            const SizedBox(height: 22),
            FilledButton(onPressed: () => Navigator.pop(context), child: Text(L('Konulara dön', 'Back to topics'))),
          ]),
        ),
      ),
    );
  }
}

