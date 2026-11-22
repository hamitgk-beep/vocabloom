import 'package:flutter/material.dart';

import '../ai/grammar_practice.dart';
import '../app_state.dart';
import '../data/stats.dart';
import '../data/user_db.dart';
import '../l10n.dart';
import 'theme.dart';

/// "My journey": personal numbers from what is stored on this device. Nothing is
/// sent anywhere, and nothing is shown that the app did not measure.
class JourneyPage extends StatelessWidget {
  final AppState app;
  const JourneyPage({super.key, required this.app});

  static Future<void> open(BuildContext context, AppState app) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => JourneyPage(app: app)));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final j = Journey.of(app);
    final days = app.stats.readingByDay(14);
    final looks = app.stats.lookupsByDay(14);
    return Scaffold(
      appBar: AppBar(title: Text(L('İstatistikler', 'Statistics'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: ListView(
            key: const ValueKey('journey-list'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(
                L('Bu sayılar yalnızca bu cihazda tutulur. Okuma süresi, sözlük sorguları, tekrar ve gramer cevapları ${_date(j.since)} tarihinden beri ölçülüyor.',
                    'These numbers stay on this device. Reading time, lookups, reviews and grammar answers are measured since ${_date(j.since)}.'),
                key: const ValueKey('journey-since'),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              // The headline numbers, always open.
              _Grid(big: true, tiles: [
                _Tile(L('Bugün okuma', 'Read today'), formatDuration(j.today), 'journey-today', Icons.today_rounded),
                _Tile(L('Toplam okuma', 'Total reading'), formatDuration(j.total), 'journey-total', Icons.schedule_rounded),
                _Tile(L('Okunan kelime (tahmini)', 'Words read (estimate)'), formatNumber(j.wordsRead), 'journey-words', Icons.menu_book_rounded),
                _Tile(L('Öğrendim listesinde', 'On "Learned"'), formatNumber(j.learned), 'journey-learned', Icons.check_circle_rounded),
              ]),
              if (j.weekMessage != null) ...[
                const SizedBox(height: 12),
                _Note(text: j.weekMessage!, keyName: 'journey-week'),
              ],
              _Section(app: app, id: 'reading', title: L('Okuma', 'Reading'), children: [
                _BarChart(
                  key: const ValueKey('journey-chart-reading'),
                  title: L('Son 14 gün (dakika)', 'Last 14 days (minutes)'),
                  values: [for (final d in days) (d.$1, d.$2 ~/ 60)],
                ),
                const SizedBox(height: 10),
                _Grid(tiles: [
                  _Tile(L('Son 7 gün', 'Last 7 days'), formatDuration(j.week), 'journey-week-time'),
                  _Tile(L('Son 30 gün', 'Last 30 days'), formatDuration(j.month), 'journey-month'),
                  _Tile(L('Okuduğun gün', 'Days read'), formatNumber(j.days), 'journey-days'),
                ]),
              ]),
              _Section(app: app, id: 'books', title: L('Kitaplar', 'Books'), children: [
                _Grid(tiles: [
                  _Tile(L('Kitaplıkta', 'In library'), formatNumber(j.books.length), 'journey-books'),
                  _Tile(L('Başlanan', 'Started'), formatNumber(j.started), 'journey-started'),
                  _Tile(L('Devam eden', 'In progress'), formatNumber(j.started - j.finished), 'journey-progress'),
                  _Tile(L('Biten', 'Finished'), formatNumber(j.finished), 'journey-finished'),
                ]),
                for (final b in j.books.where((b) => b.started)) _BookRow(b: b),
              ]),
              _Section(app: app, id: 'words', title: L('Kelimeler', 'Words'), children: [
                _Grid(tiles: [
                  _Tile(L('Öğreneceğim', 'To learn'), formatNumber(j.learning), 'journey-learning'),
                  _Tile(L('Tekrarla öğrenilen', 'Learned by review'), formatNumber(j.learnedByReview), 'journey-graduated'),
                  _Tile(L('Tekrar zamanı gelen', 'Due for review'), formatNumber(j.due), 'journey-due'),
                  _Tile(L('Toplam tekrar', 'Reviews'), formatNumber(j.reviews), 'journey-reviews'),
                  _Tile(L('Tekrar başarısı', 'Review success'), j.reviewSuccess ?? L('Henüz az veri', 'Not enough yet'), 'journey-review-success'),
                ]),
              ]),
              _Section(app: app, id: 'dictionary', title: L('Sözlük', 'Dictionary'), children: [
                _BarChart(
                  key: const ValueKey('journey-chart-lookups'),
                  title: L('Son 14 gün (sorgu)', 'Last 14 days (lookups)'),
                  values: looks,
                ),
                const SizedBox(height: 10),
                _Grid(tiles: [
                  _Tile(L('Sorgu', 'Lookups'), formatNumber(j.lookups), 'journey-lookups'),
                  _Tile(L('Son 7 gün', 'Last 7 days'), formatNumber(j.lookupsWeek), 'journey-lookups-week'),
                  _Tile(L('Farklı kelime/ifade', 'Different words'), formatNumber(j.uniqueLookups), 'journey-lookups-unique'),
                  _Tile(L('AI\'a sorulan anlam', 'Asked the AI'), formatNumber(j.aiExplained), 'journey-ai'),
                ]),
              ]),
              _Section(app: app, id: 'grammar', title: L('Gramer', 'Grammar'), children: [
                _Grammar(app: app, byTopic: j.grammar),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// A section the learner can fold; the folded ones are remembered on the device.
class _Section extends StatefulWidget {
  final AppState app;
  final String id, title;
  final List<Widget> children;
  const _Section({required this.app, required this.id, required this.title, required this.children});

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  static const _key = 'journey_closed';
  Set<String> get _closed => {...?widget.app.user.getSetting(_key)?.split(',').where((x) => x.isNotEmpty)};
  late bool open = !_closed.contains(widget.id);

  void _toggle() {
    setState(() => open = !open);
    final c = _closed;
    open ? c.remove(widget.id) : c.add(widget.id);
    widget.app.user.setSetting(_key, c.join(','));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 14),
      InkWell(
        key: ValueKey('journey-section-${widget.id}'),
        borderRadius: BorderRadius.circular(10),
        onTap: _toggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(children: [
            Expanded(
              child: Text(widget.title.toUpperCase(),
                  style: t.textTheme.labelMedium?.copyWith(letterSpacing: 1.0, color: t.colorScheme.onSurfaceVariant)),
            ),
            Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: t.colorScheme.onSurfaceVariant),
          ]),
        ),
      ),
      if (open) ...widget.children,
    ]);
  }
}

/// Bars for the last days; the day of the month below each bar.
class _BarChart extends StatelessWidget {
  final String title;
  final List<(DateTime, int)> values;
  const _BarChart({super.key, required this.title, required this.values});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final top = values.fold(0, (a, v) => v.$2 > a ? v.$2 : a);
    return Panel(padding: const EdgeInsets.fromLTRB(14, 12, 14, 10), children: [
      Row(children: [
        Expanded(child: Text(title, style: t.textTheme.titleSmall)),
        Text(L('en çok: $top', 'max: $top'), style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
      ]),
      const SizedBox(height: 10),
      SizedBox(
        height: 110,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final v in values)
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Tooltip(
                  message: '${_date(v.$1)}: ${v.$2}',
                  child: Container(
                    height: top == 0 ? 2 : 2 + 84 * v.$2 / top,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: v.$2 == 0 ? t.colorScheme.outlineVariant : t.colorScheme.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text('${v.$1.day}', style: t.textTheme.labelSmall?.copyWith(fontSize: 10, color: t.colorScheme.onSurfaceVariant)),
              ]),
            ),
        ]),
      ),
    ]);
  }
}

/// The numbers behind the journey screen, read once when it opens.
class Journey {
  final DateTime since;
  final int today, week, month, total, days, wordsRead;
  final List<BookJourney> books;
  final int learning, learned, learnedByReview, due, reviews;
  final String? reviewSuccess;
  final int lookups, lookupsWeek, uniqueLookups, aiExplained;
  final Map<String, (int, int)> grammar;
  final String? weekMessage;

  Journey._(this.since, this.today, this.week, this.month, this.total, this.days, this.wordsRead, this.books, this.learning,
      this.learned, this.learnedByReview, this.due, this.reviews, this.reviewSuccess, this.lookups, this.lookupsWeek,
      this.uniqueLookups, this.aiExplained, this.grammar, this.weekMessage);

  int get started => books.where((b) => b.started).length;
  int get finished => books.where((b) => b.finished).length;

  factory Journey.of(AppState app, {DateTime? now}) {
    final s = app.stats;
    final n = now ?? DateTime.now();
    final day = DateTime(n.year, n.month, n.day);
    final weekFrom = day.subtract(const Duration(days: 6));
    final week = s.readingSeconds(from: weekFrom);
    final lastWeek = s.readingSeconds(from: weekFrom.subtract(const Duration(days: 7)), before: weekFrom);
    final st = app.user.statuses.values;
    final (answered, ok) = s.reviewSuccess();
    return Journey._(
      s.since,
      s.readingSeconds(from: day),
      week,
      s.readingSeconds(from: day.subtract(const Duration(days: 29))),
      s.readingSeconds(),
      s.readingDays(),
      s.wordsRead(),
      [for (final b in app.user.books()) BookJourney.of(s, b)],
      st.where((x) => x == WordStatus.learning).length,
      st.where((x) => x == WordStatus.learned).length,
      s.learnedByReview(),
      app.review.dueCount(),
      s.reviewsTotal(),
      // A percentage from a handful of answers says little.
      answered >= 10 ? percent((ok * 100 / answered).round()) : null,
      s.lookups(),
      s.lookups(from: weekFrom),
      s.uniqueLookups(),
      s.aiExplained(),
      s.grammarByTopic(),
      compareWeeks(week, lastWeek),
    );
  }

  /// A comparison with the week before, only when both weeks have reading time.
  static String? compareWeeks(int thisWeek, int lastWeek) {
    if (thisWeek <= 0 || lastWeek <= 0) return null;
    final diff = ((thisWeek - lastWeek) / 60).round();
    if (diff == 0) return L('Son 7 günde önceki haftayla aynı süre okudun.', 'In the last 7 days you read as long as the week before.');
    final d = formatDuration(diff.abs() * 60);
    return diff > 0
        ? L('Son 7 günde önceki haftadan $d daha fazla okudun.', 'In the last 7 days you read $d more than the week before.')
        : L('Son 7 günde önceki haftadan $d daha az okudun.', 'In the last 7 days you read $d less than the week before.');
  }
}

class BookJourney {
  final Book book;
  final int words, read, seconds;
  final String? lastDay;
  BookJourney(this.book, this.words, this.read, this.seconds, this.lastDay);

  factory BookJourney.of(StatsStore s, Book b) =>
      BookJourney(b, s.bookWords(b.id), s.wordsRead(bookId: b.id), s.readingSeconds(bookId: b.id), s.lastReadDay(b.id));

  bool get started => read > 0 || seconds > 0 || book.lastChapter > 0 || book.lastParagraph > 0;

  /// Finished when nearly all of its text was reached in the reader.
  bool get finished => words > 0 && read >= words * 0.95;

  double get progress => words == 0 ? 0 : (read / words).clamp(0, 1).toDouble();
}

String formatDuration(int seconds) {
  final m = seconds ~/ 60;
  final h = m ~/ 60, mm = m % 60;
  if (h == 0) return L('$mm dk', '$mm min');
  if (mm == 0) return L('$h sa', '$h h');
  return L('$h sa $mm dk', '$h h $mm min');
}

String formatNumber(int n) {
  final s = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(uiEnglish ? ',' : '.');
    out.write(s[i]);
  }
  return out.toString();
}

String _date(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

class _Tile {
  final String label, value, keyName;
  final IconData? icon;
  const _Tile(this.label, this.value, this.keyName, [this.icon]);
}

/// Two to three numbers per row, depending on the width.
class _Grid extends StatelessWidget {
  final List<_Tile> tiles;
  final bool big;
  const _Grid({required this.tiles, this.big = false});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return LayoutBuilder(builder: (context, c) {
      final cols = big ? (c.maxWidth >= 720 ? 4 : 2) : (c.maxWidth >= 560 ? 3 : 2);
      final w = (c.maxWidth - 10 * (cols - 1)) / cols;
      return Wrap(spacing: 10, runSpacing: 10, children: [
        for (final x in tiles)
          SizedBox(
            width: w,
            child: Container(
              key: ValueKey(x.keyName),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: t.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: t.colorScheme.outlineVariant),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (x.icon != null) ...[
                  Icon(x.icon, size: 20, color: t.colorScheme.primary),
                  const SizedBox(height: 6),
                ],
                Text(x.value, style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, fontSize: big ? 24 : 20)),
                const SizedBox(height: 2),
                Text(x.label, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              ]),
            ),
          ),
      ]);
    });
  }
}

class _Note extends StatelessWidget {
  final String text, keyName;
  const _Note({required this.text, required this.keyName});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      key: ValueKey(keyName),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.colorScheme.primaryContainer.withValues(alpha: t.brightness == Brightness.dark ? 0.35 : 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        Icon(Icons.insights_rounded, color: t.colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: t.textTheme.bodyMedium)),
      ]),
    );
  }
}

class _BookRow extends StatelessWidget {
  final BookJourney b;
  const _BookRow({required this.b});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final sub = [
      L('${formatNumber(b.read)} / ${formatNumber(b.words)} kelime', '${formatNumber(b.read)} / ${formatNumber(b.words)} words'),
      formatDuration(b.seconds),
      if (b.lastDay != null) L('son: ${b.lastDay}', 'last: ${b.lastDay}'),
    ].join('  ·  ');
    return Padding(
      key: ValueKey('journey-book-${b.book.id}'),
      padding: const EdgeInsets.only(top: 10),
      child: Panel(padding: const EdgeInsets.all(14), children: [
        Row(children: [
          Expanded(child: Text(b.book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall)),
          if (b.finished) Icon(Icons.check_circle_rounded, size: 18, color: t.colorScheme.primary),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: LinearProgressIndicator(value: b.progress)),
          const SizedBox(width: 10),
          Text(percent((b.progress * 100).round()), style: t.textTheme.labelMedium),
        ]),
        const SizedBox(height: 6),
        Text(sub, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}

/// Grammar answers by topic, with the real topic names from the lessons.
class _Grammar extends StatelessWidget {
  final AppState app;
  final Map<String, (int, int)> byTopic;
  const _Grammar({required this.app, required this.byTopic});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final answered = byTopic.values.fold(0, (a, x) => a + x.$1);
    final right = byTopic.values.fold(0, (a, x) => a + x.$2);
    return FutureBuilder<List<GrammarTopic>>(
      future: loadAllGrammarTopics(),
      builder: (context, snap) {
        final topics = {for (final x in snap.data ?? const <GrammarTopic>[]) x.id: x};
        final progress = GrammarProgress(app.user);
        final done = topics.values.fold(0, (a, x) => a + progress.done(x.id).length);
        // Topics with enough answers to say something, best first.
        final rated = [
          for (final e in byTopic.entries)
            if (e.value.$1 >= 5) (e.key, e.value.$2 / e.value.$1, e.value.$1),
        ]..sort((a, b) => b.$2.compareTo(a.$2));
        String name(String id) => topics[id] == null ? id : L(topics[id]!.titleTr, topics[id]!.titleEn);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Grid(tiles: [
            _Tile(L('Çözülen alıştırma', 'Exercises done'), formatNumber(done), 'journey-grammar-done'),
            _Tile(L('Cevaplanan soru', 'Answers'), formatNumber(answered), 'journey-grammar-answers'),
            _Tile(L('Doğru', 'Right'), answered >= 10 ? percent((right * 100 / answered).round()) : L('Henüz az veri', 'Not enough yet'),
                'journey-grammar-right'),
          ]),
          if (rated.isNotEmpty) ...[
            const SizedBox(height: 10),
            Panel(padding: const EdgeInsets.all(14), children: [
              for (final r in rated)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(child: Text(name(r.$1), style: t.textTheme.bodyMedium)),
                    Text('${percent((r.$2 * 100).round())}  ·  ${r.$3}', style: t.textTheme.labelMedium),
                  ]),
                ),
            ]),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                L('Konu başarısı en az 5 cevaptan sonra görünür.', 'Topic results appear after at least 5 answers.'),
                style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
              ),
            ),
        ]);
      },
    );
  }
}
