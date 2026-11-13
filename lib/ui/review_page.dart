import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/review.dart';
import '../data/user_db.dart';
import '../l10n.dart';
import 'expr_sheet.dart';
import 'panel.dart';
import 'theme.dart';
import 'word_sheet.dart';

/// Opens a review session for the words that are due.
Future<void> startReview(BuildContext context, AppState app) async {
  final cards = app.review.due(limit: 20);
  if (cards.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(L('Şu an tekrar edilecek kelime yok. Okurken yeni kelimeler ekleyebilirsin.', 'Nothing to review right now. Add new words while you read.')),
    ));
    return;
  }
  await Navigator.push(context, MaterialPageRoute(fullscreenDialog: true, builder: (_) => ReviewPage(app: app, cards: cards)));
}

class ReviewPage extends StatefulWidget {
  final AppState app;
  final List<ReviewCard> cards;
  const ReviewPage({super.key, required this.app, required this.cards});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  late final List<ReviewCard> queue = [...widget.cards];
  final _again = <String>{};
  int pos = 0;
  bool shown = false;
  int done = 0, known = 0, graduated = 0;

  AppState get app => widget.app;

  void _answer(ReviewAnswer a) {
    final c = queue[pos];
    final g = app.review.answer(c.word.lemma, c.box, a);
    if (g) {
      graduated++;
      app.setWord(c.word.lemma, WordStatus.learned);
    }
    done++;
    if (a == ReviewAnswer.good) known++;
    if (a == ReviewAnswer.again && _again.add(c.word.lemma)) queue.add(ReviewCard(c.word, 0));
    setState(() {
      pos++;
      shown = false;
    });
  }

  void _openInDictionary(String lemma) {
    final e = lemma.contains(' ') ? app.dict.exprs.where((e) => e.phrase == lemma).firstOrNull : null;
    if (e != null) {
      showExprSheet(context, app, e, null);
    } else {
      showWordSheet(context, app, lemma, lemma: lemma);
    }
  }

  String _hint(ReviewAnswer a, int box) {
    if (a == ReviewAnswer.again) return L('10 dk', '10 min');
    final b = a == ReviewAnswer.good ? box + 1 : box;
    if (b >= ReviewStore.intervals.length) return L('öğrendim', 'learned');
    final d = ReviewStore.intervals[b].clamp(1, 30);
    return L('$d gün', d == 1 ? '1 day' : '$d days');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final finished = pos >= queue.length;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), tooltip: L('Kapat', 'Close'), onPressed: () => Navigator.pop(context)),
        titleSpacing: 0,
        title: finished
            ? null
            : Row(children: [
                Expanded(child: LinearProgressIndicator(value: pos / queue.length, minHeight: 8)),
                const SizedBox(width: 12),
                Text('${pos + 1}/${queue.length}', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(width: 20),
              ]),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: finished ? _summary(theme) : _card(theme, queue[pos]),
          ),
        ),
      ),
    );
  }

  Widget _card(ThemeData theme, ReviewCard c) {
    final w = c.word;
    final meaning = w.meaning ?? app.shortMeaning(w.lemma);
    final info = w.lemma.contains(' ') ? null : app.dict.lookup(w.lemma);
    final gloss = info != null && info.senses.isNotEmpty ? info.senses.first.gloss : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: GestureDetector(
            onTap: shown ? null : () => setState(() => shown = true),
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: theme.colorScheme.outlineVariant),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 24, offset: const Offset(0, 10))],
              ),
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                Row(children: [
                  _BoxDots(box: c.box),
                  const Spacer(),
                  if (w.bookTitle != null)
                    Flexible(
                      child: Text(w.bookTitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ),
                ]),
                Expanded(
              child: LayoutBuilder(
                builder: (context, box) => SingleChildScrollView(
                child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SizedBox(height: 16),
                  Text(w.lemma, style: enStyle(theme, theme.textTheme.headlineLarge).copyWith(fontWeight: FontWeight.w800)),
                  if (w.context != null) ...[
                    const SizedBox(height: 16),
                    DefaultTextStyle.merge(
                      style: TextStyle(fontFamily: readingFont, color: theme.colorScheme.onSurfaceVariant),
                      child: SentenceText(w.context!, w.lemma.split(' ').first, highlight: {w.lemma.split(' ').first}),
                    ),
                  ],
                  const SizedBox(height: 24),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: !shown
                        ? Text(L('Anlamını hatırlıyor musun? Görmek için dokun.', 'Do you remember the meaning? Tap to see it.'),
                            key: const ValueKey(0), style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))
                        : Column(key: const ValueKey(1), crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Divider(height: 1),
                            const SizedBox(height: 20),
                            if (meaning != null && app.showTr) Text(meaning, style: trStyle(theme, theme.textTheme.titleLarge)),
                            if (gloss != null && app.showEn) ...[
                              const SizedBox(height: 8),
                              Text(gloss, style: enStyle(theme, theme.textTheme.bodyLarge, false)),
                            ],
                            if (meaning == null && gloss == null)
                              Text(L('Anlam kaydedilmemiş.', 'No meaning saved.'), style: theme.textTheme.bodyMedium),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              style: TextButton.styleFrom(padding: EdgeInsets.zero),
                              onPressed: () => _openInDictionary(w.lemma),
                              icon: const Icon(Icons.menu_book_outlined, size: 18),
                              label: Text(L('Sözlükte aç', 'Open in dictionary')),
                            ),
                          ]),
                  ),
                  const SizedBox(height: 16),
                ]),
              ),
              ),
              ),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (!shown)
          FilledButton(
            onPressed: () => setState(() => shown = true),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            child: Text(L('Cevabı göster', 'Show answer')),
          )
        else
          Row(children: [
            _AnswerButton(label: L('Tekrar', 'Again'), hint: _hint(ReviewAnswer.again, c.box), color: const Color(0xFFE5484D), onTap: () => _answer(ReviewAnswer.again)),
            const SizedBox(width: 10),
            _AnswerButton(label: L('Zor', 'Hard'), hint: _hint(ReviewAnswer.hard, c.box), color: learningColor, onTap: () => _answer(ReviewAnswer.hard)),
            const SizedBox(width: 10),
            _AnswerButton(label: L('Biliyorum', 'Got it'), hint: _hint(ReviewAnswer.good, c.box), color: learnedColor, onTap: () => _answer(ReviewAnswer.good)),
          ]),
      ]),
    );
  }

  Widget _summary(ThemeData theme) {
    final streak = app.review.streak();
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const BrandMark(size: 96),
        const SizedBox(height: 24),
        Text(L('Harika iş!', 'Great job!'), style: theme.textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(L('$done kart tekrar ettin.', 'You reviewed $done cards.'), style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 28),
        Row(children: [
          _Stat(icon: Icons.local_fire_department_rounded, color: const Color(0xFFF97316), value: '$streak', label: L('gün seri', 'day streak')),
          const SizedBox(width: 10),
          _Stat(icon: Icons.check_circle_rounded, color: learnedColor, value: '$known', label: L('biliyordun', 'known')),
          const SizedBox(width: 10),
          _Stat(icon: Icons.verified_rounded, color: Brand.violet, value: '$graduated', label: L('öğrenildi', 'learned')),
        ]),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
          child: Text(L('Tamam', 'Done')),
        ),
      ]),
    );
  }
}

class _BoxDots extends StatelessWidget {
  final int box;
  const _BoxDots({required this.box});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final n = ReviewStore.intervals.length;
    return Tooltip(
      message: L('Hafıza seviyesi', 'Memory level'),
      child: Row(children: [
        for (var i = 0; i < n; i++)
          Container(
            width: 18,
            height: 5,
            margin: const EdgeInsets.only(right: 3),
            decoration: BoxDecoration(
              color: i <= box ? t.colorScheme.primary : t.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ]),
    );
  }
}

class _AnswerButton extends StatelessWidget {
  final String label, hint;
  final Color color;
  final VoidCallback onTap;
  const _AnswerButton({required this.label, required this.hint, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Expanded(
      child: Material(
        color: color.withValues(alpha: t.brightness == Brightness.dark ? 0.22 : 0.12),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
            height: 62,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(label, style: t.textTheme.titleSmall?.copyWith(color: t.brightness == Brightness.dark ? Color.lerp(color, Colors.white, 0.3) : Color.lerp(color, Colors.black, 0.25), fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(hint, style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value, label;
  const _Stat({required this.icon, required this.color, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Expanded(
      child: Panel(padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8), children: [
        Icon(icon, color: color, size: 26),
        const SizedBox(height: 6),
        Text(value, textAlign: TextAlign.center, style: t.textTheme.headlineSmall),
        Text(label, textAlign: TextAlign.center, style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}

/// "Daily review" card shown on the library and word list.
class ReviewBanner extends StatelessWidget {
  final AppState app;
  const ReviewBanner({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final due = app.review.dueCount();
        final streak = app.review.streak();
        final week = app.review.lastDays(7);
        final maxW = week.fold<int>(1, (a, b) => b > a ? b : a);
        return Panel(padding: const EdgeInsets.fromLTRB(16, 14, 16, 14), children: [
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: const Color(0xFFF97316).withValues(alpha: 0.13), borderRadius: BorderRadius.circular(13)),
              child: const Icon(Icons.local_fire_department_rounded, color: Color(0xFFF97316), size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(due == 0 ? L('Bugünlük tamam', 'All done for today') : L('$due kelime tekrar bekliyor', '$due words to review'),
                    style: t.textTheme.titleSmall?.copyWith(fontSize: 15)),
                const SizedBox(height: 2),
                Text(streak == 0 ? L('Bugün başla, seri oluştur', 'Start today and build a streak') : L('$streak günlük seri', '$streak-day streak'),
                    style: t.textTheme.bodySmall),
              ]),
            ),
            // Mini bar chart: reviews in the last 7 days.
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (var i = 0; i < week.length; i++)
                Container(
                  width: 5,
                  height: 6 + 22 * week[i] / maxW,
                  margin: const EdgeInsets.only(left: 3),
                  decoration: BoxDecoration(
                    color: week[i] > 0 ? (i == week.length - 1 ? const Color(0xFFF97316) : const Color(0xFFF97316).withValues(alpha: 0.5)) : t.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ]),
          ]),
          if (due > 0) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => startReview(context, app),
              icon: const Icon(Icons.style_rounded, size: 20),
              label: Text(L('Tekrara başla', 'Start review')),
            ),
          ],
        ]);
      },
    );
  }
}
