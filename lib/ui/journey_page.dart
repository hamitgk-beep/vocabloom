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
    return Scaffold(
      appBar: AppBar(title: Text(L('Benim Yolculuğum', 'My journey'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
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
              if (j.weekMessage != null) ...[
                const SizedBox(height: 12),
                _Note(text: j.weekMessage!, keyName: 'journey-week'),
              ],
              SectionLabel(L('Okuma', 'Reading')),
              _Grid(tiles: [
                _Tile(L('Bugün', 'Today'), formatDuration(j.today), 'journey-today'),
                _Tile(L('Son 7 gün', 'Last 7 days'), formatDuration(j.week), 'journey-week-time'),
                _Tile(L('Son 30 gün', 'Last 30 days'), formatDuration(j.month), 'journey-month'),
                _Tile(L('Toplam', 'Total'), formatDuration(j.total), 'journey-total'),
                _Tile(L('Okuduğun gün', 'Days read'), formatNumber(j.days), 'journey-days'),
                _Tile(L('Okunan kelime (tahmini)', 'Words read (estimate)'), formatNumber(j.wordsRead), 'journey-words'),
              ]),
              SectionLabel(L('Kitaplar', 'Books')),
              _Grid(tiles: [
                _Tile(L('Kitaplıkta', 'In library'), formatNumber(j.books.length), 'journey-books'),
                _Tile(L('Başlanan', 'Started'), formatNumber(j.started), 'journey-started'),
                _Tile(L('Devam eden', 'In progress'), formatNumber(j.started - j.finished), 'journey-progress'),
                _Tile(L('Biten', 'Finished'), formatNumber(j.finished), 'journey-finished'),
              ]),
              for (final b in j.books.where((b) => b.started)) _BookRow(b: b),
              SectionLabel(L('Kelimeler', 'Words')),
              _Grid(tiles: [
                _Tile(L('Öğreneceğim', 'To learn'), formatNumber(j.learning), 'journey-learning'),
                _Tile(L('Öğrendim listesinde', 'On "Learned"'), formatNumber(j.learned), 'journey-learned'),
                _Tile(L('Tekrarla öğrenilen', 'Learned by review'), formatNumber(j.learnedByReview), 'journey-graduated'),
                _Tile(L('Tekrar zamanı gelen', 'Due for review'), formatNumber(j.due), 'journey-due'),
                _Tile(L('Toplam tekrar', 'Reviews'), formatNumber(j.reviews), 'journey-reviews'),
                _Tile(L('Tekrar başarısı', 'Review success'), j.reviewSuccess ?? L('Henüz az veri', 'Not enough yet'), 'journey-review-success'),
              ]),
              SectionLabel(L('Sözlük', 'Dictionary')),
              _Grid(tiles: [
                _Tile(L('Sorgu', 'Lookups'), formatNumber(j.lookups), 'journey-lookups'),
                _Tile(L('Son 7 gün', 'Last 7 days'), formatNumber(j.lookupsWeek), 'journey-lookups-week'),
                _Tile(L('Farklı kelime/ifade', 'Different words'), formatNumber(j.uniqueLookups), 'journey-lookups-unique'),
                _Tile(L('AI ile açıklanan', 'Explained by AI'), formatNumber(j.aiExplained), 'journey-ai'),
              ]),
              SectionLabel(L('Gramer', 'Grammar')),
              _Grammar(app: app, byTopic: j.grammar),
            ],
          ),
        ),
      ),
    );
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
  const _Tile(this.label, this.value, this.keyName);
}

/// Two to three numbers per row, depending on the width.
class _Grid extends StatelessWidget {
  final List<_Tile> tiles;
  const _Grid({required this.tiles});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 560 ? 3 : 2;
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
                Text(x.value, style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, fontSize: 20)),
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
      future: loadGrammarTopics(),
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
