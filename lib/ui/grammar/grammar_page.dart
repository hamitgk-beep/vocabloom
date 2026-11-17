import 'dart:async';

import 'package:flutter/material.dart';

import '../../ai/grammar_practice.dart';
import '../../ai/tutor.dart';
import '../ai/ai_ask_box.dart';
import '../../app_state.dart';
import '../../l10n.dart';
import '../../nlp/text.dart';
import '../ai/ai_key_help.dart';
import '../ai/ai_tools.dart';
import '../expr_sheet.dart';
import '../expression_list.dart';
import '../panel.dart';
import '../tap_text.dart';
import '../theme.dart';

const _green = Color(0xFF16A34A);

/// The English title under the Turkish one, unless it says the same thing.
String? _subtitle(GrammarTopic t) {
  final s = t.subtitle;
  if (s == null) return null;
  String norm(String x) => x.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return norm(s) == norm(t.title) || t.title.toLowerCase().startsWith(s.toLowerCase()) ? null : s;
}

Color _levelColor(String level) => cefrColor(level);

class _LevelChip extends StatelessWidget {
  final String level;
  const _LevelChip(this.level);

  @override
  Widget build(BuildContext context) {
    final c = _levelColor(level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(8)),
      child: Text(
        level,
        style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 12),
      ),
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

  /// The CEFR level the list is filtered to; null shows every level.
  late String? level = cefrLevels.contains(widget.app.user.getSetting('grammar_level'))
      ? widget.app.user.getSetting('grammar_level')
      : null;

  void _setLevel(String? v) {
    widget.app.user.setSetting('grammar_level', v);
    setState(() => level = v);
  }

  @override
  void initState() {
    super.initState();
    loadGrammarTopics().then((t) => mounted ? setState(() => topics = t) : null);
  }

  Future<void> _open(GrammarTopic t) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GrammarTopicPage(app: widget.app, topic: t),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ts = topics;
    final total = ts?.fold<int>(0, (a, t) => a + t.exercises.length) ?? 0;
    final done = ts?.fold<int>(0, (a, t) => a + progress.done(t.id).length) ?? 0;
    final shown = ts == null
        ? const <GrammarTopic>[]
        : topicsByLevel([
            for (final t in ts)
              if (level == null || t.level == level) t,
          ]);
    return Scaffold(
      appBar: AppBar(toolbarHeight: 68, title: Text(L('Gramer', 'Grammar'), style: theme.textTheme.headlineSmall)),
      body: ts == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(gradient: Brand.gradient, borderRadius: BorderRadius.circular(22)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            L('Kuralı öğren, cümleyle pekiştir', 'Learn the rule, practise with sentences'),
                            style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            L(
                              'Her konuda kısa bir Türkçe anlatım, yapı kalıpları ve örnekler var. Sonra Türkçe cümleleri İngilizceye çevirirsin; doğru mu, nasıl daha doğal söylenir, hemen görürsün.',
                              'Each topic has a short explanation, patterns and examples. Then you translate Turkish sentences into English and see at once whether they are right and how to say them more naturally.',
                            ),
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
                          Text(
                            L('$done / $total cümle tamamlandı', '$done of $total sentences done'),
                            style: theme.textTheme.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    if (nextGrammarTopic(ts, progress, level: level) case final next?)
                      _NextTopicCard(topic: next, done: progress.done(next.id).length, onTap: () => _open(next)),
                    const SizedBox(height: 14),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final l in [null, ...cefrLevels])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(l ?? L('Tüm seviyeler', 'All levels')),
                                selected: level == l,
                                showCheckmark: false,
                                labelStyle: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: level == l ? Colors.white : (l == null ? null : _levelColor(l)),
                                ),
                                selectedColor: l == null ? cs.primary : _levelColor(l),
                                onSelected: (_) => _setLevel(l),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (level != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          _levelNote(level!),
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
                        ),
                      ),
                    for (final cat in grammarCategories.entries)
                      if (shown.any((t) => t.category == cat.key)) ...[
                        SectionLabel(uiEnglish ? cat.value.$2 : cat.value.$1),
                        Material(
                          color: cs.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                            side: BorderSide(color: cs.outlineVariant),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              for (final (i, t) in shown.where((t) => t.category == cat.key).indexed) ...[
                                if (i > 0) Divider(height: 1, indent: 16, endIndent: 16, color: cs.outlineVariant),
                                _TopicTile(topic: t, done: progress.done(t.id).length, onTap: () => _open(t)),
                              ],
                            ],
                          ),
                        ),
                      ],
                  ],
                ),
              ),
            ),
    );
  }
}

String _levelNote(String level) => switch (level) {
  'A1' => L('A1 · Başlangıç: kendini tanıtma, günlük basit cümleler.', 'A1 · Beginner: introducing yourself, simple everyday sentences.'),
  'A2' => L(
    'A2 · Temel: geçmiş ve gelecek, karşılaştırma, günlük konular.',
    'A2 · Elementary: past and future, comparing, everyday topics.',
  ),
  'B1' => L(
    'B1 · Orta: deneyim anlatma, koşul cümleleri, görüş bildirme.',
    'B1 · Intermediate: telling experiences, conditionals, giving opinions.',
  ),
  'B2' => L(
    'B2 · Orta üstü: akıcı ve ayrıntılı anlatım, edilgen ve dolaylı yapılar.',
    'B2 · Upper intermediate: fluent, detailed speech, passive and indirect forms.',
  ),
  'C1' => L(
    'C1 · İleri: vurgulu ve resmî yapılar, ince anlam farkları.',
    'C1 · Advanced: emphatic and formal structures, fine shades of meaning.',
  ),
  _ => L('C2 · Ustalık: anadili gibi doğal ve esnek kullanım.', 'C2 · Proficiency: natural, flexible, near-native use.'),
};

/// The suggested next topic, shown under the hero.
class _NextTopicCard extends StatelessWidget {
  final GrammarTopic topic;
  final int done;
  final VoidCallback onTap;
  const _NextTopicCard({required this.topic, required this.done, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final c = _levelColor(topic.level);
    final n = topic.exercises.length;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Material(
        color: c.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: c.withValues(alpha: 0.35)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        L('Sıradaki konu', 'Up next'),
                        style: theme.textTheme.labelLarge?.copyWith(color: c, fontWeight: FontWeight.w800, letterSpacing: 0.3),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: Text(topic.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                          ),
                          const SizedBox(width: 8),
                          _LevelChip(topic.level),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          ?_subtitle(topic),
                          done == 0 ? L('$n cümle', '$n sentences') : L('$done/$n tamamlandı', '$done of $n done'),
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: c),
              ],
            ),
          ),
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
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(topic.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 8),
                      _LevelChip(topic.level),
                    ],
                  ),
                  if (_subtitle(topic) case final sub?) ...[const SizedBox(height: 2), Text(sub, style: theme.textTheme.bodySmall)],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      SizedBox(
                        width: 110,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(value: n == 0 ? 0 : done / n, minHeight: 5, color: complete ? _green : cs.primary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('$done/$n', style: theme.textTheme.labelMedium?.copyWith(color: complete ? _green : cs.onSurfaceVariant)),
                    ],
                  ),
                ],
              ),
            ),
            Icon(complete ? Icons.check_circle_rounded : Icons.chevron_right_rounded, color: complete ? _green : cs.onSurfaceVariant),
          ],
        ),
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
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GrammarPracticePage(app: widget.app, topic: widget.topic),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final t = widget.topic;
    final done = progress.done(t.id).length;
    final n = t.exercises.length;
    final wrong = progress.wrong(t.id).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.title),
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
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
            children: [
              Row(
                children: [
                  _LevelChip(t.level),
                  const SizedBox(width: 8),
                  if (_subtitle(t) case final sub?)
                    Flexible(
                      child: Text(sub, style: theme.textTheme.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Panel(children: [aiRichText(t.explanation, theme.textTheme.bodyLarge?.copyWith(height: 1.55))]),
              if (t.structure.isNotEmpty) ...[
                SectionLabel(L('Yapı', 'Pattern')),
                for (final s in t.structure)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
                    ),
                    child: Text(
                      s,
                      style: theme.textTheme.titleSmall?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
              if (t.examples.isNotEmpty) ...[
                SectionLabel(L('Örnekler', 'Examples')),
                Panel(
                  children: [
                    for (final (i, e) in t.examples.indexed) ...[
                      if (i > 0) const SizedBox(height: 12),
                      TapText(e.$1, style: enStyle(theme, theme.textTheme.bodyLarge)),
                      const SizedBox(height: 2),
                      Text(e.$2, style: theme.textTheme.bodyMedium),
                    ],
                  ],
                ),
              ],
              if (categoryById[t.dictCategory] case final cat?) _ExpressionsCard(app: widget.app, cat: cat),
            ],
          ),
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
                  icon: Icon(done >= n || wrong > 0 ? Icons.replay_rounded : Icons.edit_note_rounded),
                  label: Text(
                    done == 0
                        ? L('Pratiğe başla · $n cümle', 'Start practice · $n sentences')
                        : wrong > 0
                        ? L('Devam et · $wrong tekrar, $done/$n', 'Continue · $wrong to review, $done/$n')
                        : done >= n
                        ? L('Tekrar çalış', 'Practise again')
                        : L('Devam et · $done/$n', 'Continue · $done/$n'),
                  ),
                ),
              ),
            ),
    );
  }
}

/// On a lesson that explains an expression group (phrasal verbs, idioms …):
/// how many the dictionary has, a few common ones to tap, and the full list.
class _ExpressionsCard extends StatelessWidget {
  final AppState app;
  final CategoryInfo cat;
  const _ExpressionsCard({required this.app, required this.cat});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final all = app.dict.byCategory(cat.id);
    if (all.isEmpty) return const SizedBox.shrink();
    final color = theme.brightness == Brightness.dark ? Color.lerp(cat.color, Colors.white, 0.3)! : cat.color;
    final samples = app.dict.commonExprs(cat.id, limit: 8);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionLabel(L('Sözlükteki ${cat.tr.toLowerCase()} · ${all.length} ifade', '${cat.name} in the dictionary · ${all.length} entries')),
        Panel(children: [
          Text(
            L('Okurken bir ifadeye dokunduğunda anlamı ve örnekleri açılır. Sık geçen birkaçı:', 'Tap an expression while reading to see its meanings and examples. A few common ones:'),
            style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in samples)
              ActionChip(
                label: Text(displayPhrase(e.phrase), style: TextStyle(color: color, fontWeight: FontWeight.w600)),
                side: BorderSide(color: cat.color.withValues(alpha: 0.35)),
                backgroundColor: cat.color.withValues(alpha: 0.08),
                onPressed: () => showExprSheet(context, app, e, null),
              ),
          ]),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ExpressionListPage(app: app, cat: cat))),
            icon: const Icon(Icons.list_alt_rounded),
            label: Text(L('Tüm listeyi aç · ${all.length}', 'Open the full list · ${all.length}')),
          ),
        ]),
      ]),
    );
  }
}

/// Translate Turkish sentences into English and get feedback, in scored
/// rounds of [grammarRoundSize] sentences.
class GrammarPracticePage extends StatefulWidget {
  final AppState app;
  final GrammarTopic topic;

  /// The sentences of this round; by default [grammarRound].
  final List<GrammarExercise>? round;
  const GrammarPracticePage({super.key, required this.app, required this.topic, this.round});

  @override
  State<GrammarPracticePage> createState() => _GrammarPracticePageState();
}

enum _State { asking, checking, right, feedback, noModel, shown }

/// How one sentence of the round went.
enum _Result { right, hinted, wrong }

class _GrammarPracticePageState extends State<GrammarPracticePage> {
  late final progress = GrammarProgress(widget.app.user);
  late final tutor = Tutor.of(widget.app);
  final input = TextEditingController();
  late List<GrammarExercise> queue;
  final results = <GrammarExercise, _Result>{};
  int index = 0;
  _State state = _State.asking;
  String feedback = '';

  /// Why the AI could not check the answer (with a key connected).
  String? aiErr;
  StreamSubscription<String>? sub;
  List<String> hint = const [];
  int hintShown = 0;

  GrammarTopic get t => widget.topic;
  GrammarExercise get e => queue[index];

  @override
  void initState() {
    super.initState();
    queue = widget.round ?? grammarRound(t, progress);
    _newHint();
  }

  void _newHint() {
    hint = index < queue.length ? hintWords(queue[index]) : const [];
    hintShown = 0;
  }

  @override
  void dispose() {
    sub?.cancel();
    input.dispose();
    super.dispose();
  }

  void _record(bool right) {
    results[e] = !right ? _Result.wrong : (hintShown > 0 ? _Result.hinted : _Result.right);
    progress.record(t.id, e.id, right: right);
  }

  void _submit() {
    final a = input.text.trim();
    if (a.isEmpty || state != _State.asking) return;
    FocusScope.of(context).unfocus();
    if (e.isGap) {
      // Gap answers are checked against the list; no model is needed.
      final ok = matchesReference(e, a);
      _record(ok);
      setState(() {
        state = ok ? _State.right : _State.shown;
        feedback = ok ? '${L('Harika, doğru! 🎉', 'Great, that\'s right! 🎉')}\n**"${e.gapSolved}"**' : '';
      });
      return;
    }
    if (tutor.isCorrectTranslation(e, a)) {
      _record(true);
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
    sub = tutor
        .checkTranslation(t, e, a)
        .listen(
          (c) => setState(() {
            state = _State.feedback;
            feedback += c;
          }),
          onDone: () {
            // The model may accept a different but correct sentence.
            _record(feedback.isNotEmpty && !feedbackHasCorrections(feedback));
            if (mounted && state != _State.noModel) setState(() => state = _State.feedback);
          },
          onError: (Object err) {
            _record(false);
            aiErr = aiError(err);
            if (mounted) setState(() => state = _State.noModel);
          },
        );
  }

  /// "Cevabı göster": counts as wrong, so the sentence comes back later.
  void _reveal() {
    FocusScope.of(context).unfocus();
    _record(false);
    setState(() => state = _State.shown);
  }

  void _next() {
    sub?.cancel();
    input.clear();
    setState(() {
      index++;
      state = _State.asking;
      feedback = '';
      _newHint();
    });
  }

  void _again(List<GrammarExercise> round) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => GrammarPracticePage(app: widget.app, topic: t, round: round),
      ),
    );
  }

  /// What the AI is told about the exercise on the screen.
  String _aboutExercise() {
    final a = input.text.trim();
    return 'Gramer konusu: ${t.titleTr} (${t.titleEn})\n'
        'Kural: ${e.noteTr.isEmpty ? t.structureTr.join(' / ') : e.noteTr}\n'
        '${e.isGap ? 'Boşluk doldurma: "${e.gap}"\nTam hâli: "${e.gapSolved}"\n' : 'Türkçe cümle: "${e.tr}"\n'}'
        'Doğru cevaplar:\n${e.answers.map((x) => '- "$x"').join('\n')}\n'
        'Öğrencinin cevabı: ${a.isEmpty ? '(cevap vermedi, cevabı gösterdi)' : '"$a"'}\n'
        'Sonuç: ${results[e] == _Result.wrong ? 'yanlış' : 'doğru'}'
        '${feedback.trim().isEmpty ? '' : '\nUygulamanın geri bildirimi: ${feedback.trim()}'}';
  }

  void _openAi() => openAiKeySettings(context, widget.app);


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (queue.isEmpty || index >= queue.length) return _finished(theme);
    final answered = state != _State.asking && state != _State.checking;
    final wasWrong = progress.wrong(t.id).contains(e.id) && !results.containsKey(e);
    final byLetter = e.isGap && !e.answers.first.trim().contains(' ');
    return Scaffold(
      appBar: AppBar(title: Text(t.title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Text(
                    L('Cümle ${index + 1} / ${queue.length}', 'Sentence ${index + 1} of ${queue.length}'),
                    style: theme.textTheme.labelLarge,
                  ),
                  if (wasWrong) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD97706).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        L('Tekrar', 'Review'),
                        style: theme.textTheme.labelSmall?.copyWith(color: const Color(0xFFB45309), fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                  const Spacer(),
                  _LevelChip(t.level),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: index / queue.length, minHeight: 6),
              ),
              const SizedBox(height: 18),
              Text(
                e.isGap
                    ? L('Boşluğu doldur', 'Fill in the gap')
                    : L('Bu cümleyi İngilizceye çevir', 'Translate this sentence into English'),
                style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: e.isGap
                    ? _gapText(theme)
                    : Text(e.tr, style: theme.textTheme.titleLarge?.copyWith(height: 1.4, fontWeight: FontWeight.w700)),
              ),
              if (hintShown > 0) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final w in hint.take(hintShown))
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          w,
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurface),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: input,
                enabled: state == _State.asking,
                minLines: e.isGap ? 1 : 2,
                maxLines: e.isGap ? 1 : 5,
                autocorrect: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: e.isGap
                      ? L('Boşluğa gelecek kelime(ler)…', 'The missing word(s)…')
                      : L('İngilizcesini yaz…', 'Write it in English…'),
                ),
              ),
              const SizedBox(height: 12),
              if (!answered) ...[
                FilledButton.icon(
                  onPressed: state == _State.checking ? null : _submit,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  icon: state == _State.checking
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send_rounded, size: 20),
                  label: Text(state == _State.checking ? L('Kontrol ediliyor…', 'Checking…') : L('Gönder', 'Submit')),
                ),
                if (state == _State.asking)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        TextButton.icon(
                          key: const ValueKey('grammar-hint'),
                          onPressed: hintShown < hint.length ? () => setState(() => hintShown++) : null,
                          icon: const Icon(Icons.lightbulb_outline_rounded, size: 18),
                          label: Text(
                            hintShown == 0
                                ? L('İpucu', 'Hint')
                                : hintShown < hint.length
                                ? (byLetter
                                      ? L('Bir harf daha · $hintShown/${hint.length}', 'One more letter · $hintShown/${hint.length}')
                                      : L('Bir kelime daha · $hintShown/${hint.length}', 'One more word · $hintShown/${hint.length}'))
                                : (byLetter ? L('İpucu bitti', 'No more hints') : L('Tüm kelimeler gösterildi', 'All words shown')),
                          ),
                        ),
                        const Spacer(),
                        TextButton(onPressed: _reveal, child: Text(L('Cevabı göster', 'Show answer'))),
                      ],
                    ),
                  ),
              ],
              if (state == _State.right)
                _resultCard(
                  theme,
                  ok: true,
                  child: aiRichText(
                    feedback.isEmpty ? L('Harika, tamamen doğru! 🎉', 'Great, exactly right! 🎉') : feedback,
                    theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                  ),
                ),
              if (state == _State.feedback && feedback.isNotEmpty) ...[
                _resultCard(
                  theme,
                  ok: results[e] != _Result.wrong && results.containsKey(e),
                  child: aiRichText(feedback, theme.textTheme.bodyLarge?.copyWith(height: 1.5)),
                ),
                const AiDisclaimer(),
              ],
              if (state == _State.noModel || state == _State.shown)
                _resultCard(
                  theme,
                  ok: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.isGap ? L('Doğru cevap', 'Correct answer') : L('Doğru kurulumlar', 'Correct versions'),
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      if (e.isGap)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '"${e.gapSolved}"',
                            style: enStyle(theme, theme.textTheme.bodyLarge),
                          ),
                        ),
                      if (e.isGap && e.answers.length > 1)
                        Text(
                          L('Kabul edilenler: ${e.answers.join(' / ')}', 'Also accepted: ${e.answers.join(' / ')}'),
                          style: theme.textTheme.bodyMedium,
                        ),
                      if (!e.isGap)
                        for (final a in e.answers.take(3))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '•  $a',
                              style: enStyle(theme, theme.textTheme.bodyLarge),
                            ),
                          ),
                      if (e.note.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.rule_rounded, size: 18, color: cs.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Expanded(child: Text(e.note, style: theme.textTheme.bodyMedium?.copyWith(height: 1.45))),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        L('Bu cümle sonraki turlarda yeniden karşına çıkacak.', 'This sentence will come up again in a later round.'),
                        style: theme.textTheme.bodySmall?.copyWith(height: 1.4, color: cs.onSurfaceVariant),
                      ),
                      if (state == _State.noModel && widget.app.localAi.activeId != null && aiErr != null) ...[
                        const Divider(height: 24),
                        Text(aiErr!, style: theme.textTheme.bodySmall?.copyWith(height: 1.4, color: cs.error)),
                      ],
                      if (state == _State.noModel && widget.app.localAi.activeId == null) ...[
                        const Divider(height: 24),
                        Text(
                          L(
                            'Cevabındaki hataların tek tek açıklanması için Ayarlar\'dan kendi yapay zekâ anahtarını ekle (Gemini ücretsiz).',
                            'For a detailed explanation of your mistakes, add your own AI key in Settings (Gemini is free).',
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                        ),
                        const SizedBox(height: 6),
                        TextButton.icon(
                          onPressed: _openAi,
                          icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                          label: Text(L('Yapay zekâ anahtarı ekle', 'Add an AI key')),
                        ),
                      ],
                    ],
                  ),
                ),
              if (answered)
                AiAskBox(
                  key: ValueKey('ask-${e.id}'),
                  app: widget.app,
                  title: L('Yapay zekâya sor', 'Ask the AI'),
                  suggestions: [
                    if (results[e] == _Result.wrong) L('Neden yanlış?', 'Why is it wrong?'),
                    if (results[e] == _Result.wrong && !e.isGap) L('Benim cevabım da doğru değil mi?', 'Isn\'t my answer right too?'),
                    L('Kuralı kısaca anlat', 'Explain the rule briefly'),
                    L('Bir örnek daha ver', 'Give me another example'),
                  ],
                  about: _aboutExercise(),
                ),
              if (answered) ...[
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _next,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  child: Text(index + 1 < queue.length ? L('Sıradaki cümle', 'Next sentence') : L('Sonucu gör', 'See your score')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The gap sentence with the gap drawn as a blank, and its meaning.
  Widget _gapText(ThemeData theme) {
    final cs = theme.colorScheme;
    final parts = e.gap!.split(GrammarExercise.gapMark);
    final style = theme.textTheme.titleLarge?.copyWith(height: 1.5, fontWeight: FontWeight.w700);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            style: style,
            children: [
              for (final (i, p) in parts.indexed) ...[
                TextSpan(text: p),
                if (i < parts.length - 1)
                  TextSpan(
                    text: state == _State.asking || state == _State.checking || input.text.trim().isEmpty ? '  ______  ' : ' ${input.text.trim()} ',
                    style: state == _State.asking || state == _State.checking || input.text.trim().isEmpty
                        ? TextStyle(color: cs.primary, backgroundColor: cs.primaryContainer.withValues(alpha: 0.5))
                        : state == _State.right
                            ? TextStyle(color: _green, backgroundColor: _green.withValues(alpha: 0.12))
                            : TextStyle(
                                color: const Color(0xFFD97706),
                                backgroundColor: const Color(0xFFD97706).withValues(alpha: 0.12),
                                decoration: TextDecoration.lineThrough,
                                decorationColor: const Color(0xFFD97706),
                              ),
                  ),
              ],
            ],
          ),
        ),
        if (e.tr.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            e.tr,
            style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, fontStyle: FontStyle.italic),
          ),
        ],
      ],
    );
  }

  Widget _resultCard(ThemeData theme, {required bool ok, required Widget child}) {
    final cs = theme.colorScheme;
    final c = ok ? _green : const Color(0xFFD97706);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ok ? Icons.check_circle_rounded : Icons.lightbulb_rounded, color: c, size: 20),
              const SizedBox(width: 6),
              Text(
                ok ? L('Doğru', 'Correct') : L('Geri bildirim', 'Feedback'),
                style: theme.textTheme.titleSmall?.copyWith(color: c, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DefaultTextStyle.merge(
            style: TextStyle(color: cs.onSurface),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _finished(ThemeData theme) {
    final cs = theme.colorScheme;
    final n = results.length;
    final right = results.values.where((r) => r == _Result.right).length;
    final hinted = results.values.where((r) => r == _Result.hinted).length;
    final wrongNow = [
      for (final x in queue)
        if (results[x] == _Result.wrong) x,
    ];
    // A sentence right with a hint counts half.
    final score = n == 0 ? 0 : ((right + hinted * 0.5) * 100 / n).round();
    final (icon, color, title) = score >= 90
        ? (Icons.emoji_events_rounded, const Color(0xFFE0752D), L('Mükemmel!', 'Excellent!'))
        : score >= 70
        ? (Icons.star_rounded, _green, L('Çok iyi!', 'Very good!'))
        : score >= 50
        ? (Icons.thumb_up_alt_rounded, const Color(0xFF2563EB), L('İyi gidiyorsun', 'Good progress'))
        : (Icons.fitness_center_rounded, const Color(0xFFD97706), L('Biraz daha pratik', 'A bit more practice'));
    final left = t.exercises.length - progress.done(t.id).length;
    final review = progress.wrong(t.id).length;
    final newRound = L('Yeni tur · $grammarRoundSize cümle', 'New round · $grammarRoundSize sentences');
    Widget stat(String label, int v, Color c) => Expanded(
      child: Column(
        children: [
          Text(
            '$v',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: c),
          ),
          Text(label, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(t.title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Icon(icon, size: 68, color: color),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (n > 0) ...[
                const SizedBox(height: 4),
                Text(
                  L('Puanın: $score / 100', 'Your score: $score / 100'),
                  key: const ValueKey('grammar-score'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    stat(L('Doğru', 'Right'), right, _green),
                    stat(L('İpucuyla doğru', 'Right with a hint'), hinted, const Color(0xFF2563EB)),
                    stat(L('Yanlış', 'Wrong'), wrongNow.length, const Color(0xFFD97706)),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              Text(
                review > 0
                    ? L(
                        '$review yanlış cümlen sonraki turlarda önce sorulacak.',
                        'Your $review wrong sentences will be asked first in the next rounds.',
                      )
                    : left > 0
                    ? L('Bu konuda daha önce görmediğin $left cümle var.', 'There are $left sentences on this topic you have not seen yet.')
                    : L('Bu konudaki tüm cümleleri çalıştın.', 'You have practised every sentence on this topic.'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 22),
              if (wrongNow.isNotEmpty) ...[
                FilledButton.icon(
                  onPressed: () => _again(wrongNow),
                  icon: const Icon(Icons.replay_rounded),
                  label: Text(L('Yanlışları şimdi tekrar et', 'Retry the wrong ones now')),
                ),
                const SizedBox(height: 8),
              ],
              if (wrongNow.isEmpty)
                FilledButton.icon(
                  onPressed: () => _again(grammarRound(t, progress)),
                  icon: const Icon(Icons.edit_note_rounded),
                  label: Text(newRound),
                )
              else
                OutlinedButton.icon(
                  onPressed: () => _again(grammarRound(t, progress)),
                  icon: const Icon(Icons.edit_note_rounded),
                  label: Text(newRound),
                ),
              const SizedBox(height: 8),
              TextButton(onPressed: () => Navigator.pop(context), child: Text(L('Konuya dön', 'Back to the topic'))),
            ],
          ),
        ),
      ),
    );
  }
}
