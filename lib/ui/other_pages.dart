import 'package:flutter/material.dart';

import '../import/importers.dart' show looksGeneratedTitle;
import '../app_state.dart';
import '../data/user_db.dart';
import '../nlp/text.dart';
import '../l10n.dart';
import 'expr_sheet.dart';
import 'panel.dart';
import 'review_page.dart';
import 'theme.dart';
import 'word_sheet.dart';

// ------------------------------------------------------------------ words
/// Word notebook: To learn / Learned / By book chips, today's review on top,
/// then the words with their meaning, sentence and book.
class WordsPage extends StatefulWidget {
  final AppState app;
  const WordsPage({super.key, required this.app});

  @override
  State<WordsPage> createState() => _WordsPageState();
}

class _WordsPageState extends State<WordsPage> {
  /// 0 To learn, 1 Learned, 2 By book.
  int view = 0;

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: app,
          builder: (context, _) {
            final st = app.user.statuses.values;
            final n1 = st.where((s) => s == WordStatus.learning).length;
            final n2 = st.where((s) => s == WordStatus.learned).length;
            Widget chip(int i, String label) {
              final on = view == i;
              return ChoiceChip(
                key: ValueKey('words-view-$i'),
                label: Text(label),
                selected: on,
                showCheckmark: false,
                onSelected: (_) => setState(() => view = i),
                labelStyle: TextStyle(fontWeight: FontWeight.w600, color: on ? (theme.brightness == Brightness.dark ? const Color(0xFF21180A) : Colors.white) : cs.onSurface),
                selectedColor: theme.brightness == Brightness.dark ? Brand.goldLight : const Color(0xFF5C3D14),
                shape: const StadiumBorder(),
                visualDensity: VisualDensity.compact,
                labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                side: BorderSide(color: on ? Colors.transparent : cs.outlineVariant),
              );
            }

            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(L('Kelimelerim', 'My words'), style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 2),
                  Text(L('Okurken topladığın kelimeler.', 'The words you collected while reading.'), style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    child: Row(children: [
                      chip(0, L('Öğreneceğim · $n1', 'To learn · $n1')),
                      const SizedBox(width: 8),
                      chip(1, L('Öğrendim · $n2', 'Learned · $n2')),
                      const SizedBox(width: 8),
                      chip(2, L('Kitaba göre', 'By book')),
                    ]),
                  ),
                ]),
              ),
              Expanded(
                child: view == 2
                    ? _WordList(app: app, status: null, header: _TodayReview(app: app))
                    : _WordList(app: app, status: view == 0 ? WordStatus.learning : WordStatus.learned, header: view == 0 ? _TodayReview(app: app) : null),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

/// "Today's review": how many words are ready, about how long, and Start.
class _TodayReview extends StatelessWidget {
  final AppState app;
  const _TodayReview({required this.app});

  @override
  Widget build(BuildContext context) {
    final due = app.review.dueCount();
    if (due == 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final bg = dark ? Brand.goldLight : const Color(0xFF5C3D14);
    final fg = dark ? const Color(0xFF21180A) : const Color(0xFFFBF3E2);
    final mins = (due * 20 / 60).ceil();
    return Container(
      key: const ValueKey('words-today-review'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(L('Bugünkü tekrar', 'Today\'s review'), style: TextStyle(fontFamily: readingFont, fontSize: 17, fontWeight: FontWeight.w600, color: fg)),
            const SizedBox(height: 2),
            Text(L('$due kelime hazır · yaklaşık $mins dakika', '$due words ready · about $mins min'), style: TextStyle(fontSize: 12.5, color: fg.withValues(alpha: 0.85))),
          ]),
        ),
        const SizedBox(width: 10),
        FilledButton.icon(
          key: const ValueKey('review-start'),
          onPressed: () => startReview(context, app),
          icon: const Icon(Icons.play_arrow_rounded, size: 20),
          label: Text(L('Başla', 'Start')),
          style: FilledButton.styleFrom(backgroundColor: fg, foregroundColor: bg, minimumSize: const Size(0, 40)),
        ),
      ]),
    );
  }
}

class _WordList extends StatelessWidget {
  final AppState app;

  /// Null: every saved word, grouped by the book it came from.
  final WordStatus? status;

  /// Shown above the list (today's review).
  final Widget? header;
  const _WordList({required this.app, required this.status, this.header});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final words = status == null ? [...app.user.words(WordStatus.learning), ...app.user.words(WordStatus.learned)] : app.user.words(status!);
    final due = status == WordStatus.learned ? const <String, DateTime>{} : app.review.nextDue();
    final items = <Widget>[?header];
    if (words.isEmpty) {
      final learning = status != WordStatus.learned;
      final color = learning ? learningColor : learnedColor;
      items.add(Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(24)),
            child: Icon(learning ? Icons.bookmark_add_rounded : Icons.verified_rounded, size: 36, color: color),
          ),
          const SizedBox(height: 16),
          Text(
            learning
                ? L('Okurken bir kelimeye dokunup "Öğreneceğim" dediğinde burada görünür ve kitapta turuncu işaretlenir.', 'When you tap a word while reading and choose "To learn", it shows up here and is marked orange in the book.')
                : L('"Öğrendim" dediğin kelimeler burada toplanır ve kitapta yeşil işaretlenir.', 'Words you mark as "Learned" are collected here and marked green in the book.'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.5),
          ),
        ]),
      ));
    } else if (status == null) {
      // By book: the books in the order their first word was saved, then the rest.
      final groups = <String, List<SavedWord>>{};
      for (final w in words) {
        final b = w.bookTitle != null && !looksGeneratedTitle(w.bookTitle!) ? w.bookTitle! : '';
        groups.putIfAbsent(b, () => []).add(w);
      }
      final keys = groups.keys.where((k) => k.isNotEmpty).toList()..sort();
      if (groups.containsKey('')) keys.add('');
      for (final k in keys) {
        items.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
          child: Row(children: [
            Icon(Icons.auto_stories_outlined, size: 17, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(k.isEmpty ? L('Kitap dışında eklenenler', 'Added outside a book') : k,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
            Text('${groups[k]!.length}', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
          ]),
        ));
        for (final w in groups[k]!) {
          items.add(_card(context, w, due[w.lemma], showBook: false));
        }
      }
    } else {
      for (final w in words) {
        items.add(_card(context, w, due[w.lemma]));
      }
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 110), children: items);
  }

  /// "review today / tomorrow / in N days" for a To learn word.
  static String _dueLabel(DateTime d) {
    final now = DateTime.now();
    final days = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
    if (days <= 0) return L('tekrar bugün', 'review today');
    if (days == 1) return L('tekrar yarın', 'review tomorrow');
    return L('tekrar $days gün sonra', 'review in $days days');
  }

  Widget _card(BuildContext context, SavedWord w, DateTime? due, {bool showBook = true}) {
    final theme = Theme.of(context);
    final learning = w.status == WordStatus.learning;
    final color = learning ? learningColor : learnedColor;
    final meaning = w.meaning ?? app.shortMeaning(w.lemma);
    return Card(
      child: InkWell(
        onTap: () {
          final isPhrase = w.lemma.contains(' ') && !app.learnTurkish;
          if (isPhrase) {
            final e = app.dict.exprs.where((e) => e.phrase == w.lemma).firstOrNull;
            if (e != null) {
              showExprSheet(context, app, e, null);
              return;
            }
          }
          showWordSheet(context, app, w.lemma, lemma: w.lemma);
        },
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 4, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Text(displayPhrase(w.lemma),
                          style: (app.learnTurkish ? trStyle : enStyle)(theme, theme.textTheme.titleMedium).copyWith(fontWeight: FontWeight.w700)),
                    ),
                    if (learning && due != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3, left: 8),
                        child: Text(_dueLabel(due), style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      ),
                  ]),
                  if (meaning != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(meaning, maxLines: 2, overflow: TextOverflow.ellipsis, style: (app.learnTurkish ? enStyle : trStyle)(theme, theme.textTheme.bodyMedium)),
                    ),
                  if (w.context != null)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.only(left: 10),
                      decoration: BoxDecoration(border: Border(left: BorderSide(color: theme.colorScheme.outlineVariant, width: 2))),
                      child: Text(w.context!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontFamily: readingFont, fontStyle: FontStyle.italic, fontSize: 13.5, height: 1.4, color: theme.colorScheme.onSurfaceVariant)),
                    ),
                  if (showBook && w.bookTitle != null && !looksGeneratedTitle(w.bookTitle!))
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(children: [
                        Icon(Icons.auto_stories_outlined, size: 13, color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Flexible(child: Text(w.bookTitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
                      ]),
                    ),
                ]),
              ),
            ),
            Center(
              child: IconButton(
                tooltip: learning ? L('Öğrendim', 'Learned') : L('Tekrar öğreneceğim', 'Learn again'),
                icon: Icon(learning ? Icons.check_circle_outline_rounded : Icons.replay_rounded, color: learning ? learnedColor : theme.colorScheme.onSurfaceVariant),
                onPressed: () => app.setWord(w.lemma, learning ? WordStatus.learned : WordStatus.learning),
              ),
            ),
            const SizedBox(width: 4),
          ]),
        ),
      ),
    );
  }
}
