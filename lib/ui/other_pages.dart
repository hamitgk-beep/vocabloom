import 'package:flutter/material.dart';


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
class WordsPage extends StatelessWidget {
  final AppState app;
  const WordsPage({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 68,
          title: Text(L('Kelimelerim', 'My words'), style: Theme.of(context).textTheme.headlineSmall),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: ListenableBuilder(
              listenable: app,
              builder: (context, _) {
                final st = app.user.statuses.values;
                final n1 = st.where((s) => s == WordStatus.learning).length;
                final n2 = st.where((s) => s == WordStatus.learned).length;
                final theme = Theme.of(context);
                Widget tab(String t, int n, Color c) => Tab(
                      height: 40,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Text(t),
                        const SizedBox(width: 6),
                        Text('$n', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
                      ]),
                    );
                return Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
                  child: TabBar(tabs: [
                    tab(L('Öğreneceğim', 'To learn'), n1, learningColor),
                    tab(L('Öğrendim', 'Learned'), n2, learnedColor),
                  ]),
                );
              },
            ),
          ),
        ),
        body: ListenableBuilder(
          listenable: app,
          builder: (context, _) => Column(children: [
            if (app.user.statuses.containsValue(WordStatus.learning))
              Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 6), child: ReviewBanner(app: app)),
            Expanded(
              child: TabBarView(children: [
                _WordList(app: app, status: WordStatus.learning),
                _WordList(app: app, status: WordStatus.learned),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _WordList extends StatelessWidget {
  final AppState app;
  final WordStatus status;
  const _WordList({required this.app, required this.status});

  @override
  Widget build(BuildContext context) {
    final words = app.user.words(status);
    final theme = Theme.of(context);
    final color = status == WordStatus.learning ? learningColor : learnedColor;
    if (words.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(24)),
              child: Icon(status == WordStatus.learning ? Icons.bookmark_add_rounded : Icons.verified_rounded, size: 36, color: color),
            ),
            const SizedBox(height: 16),
            Text(
            status == WordStatus.learning
                ? L('Okurken bir kelimeye dokunup "Öğreneceğim" dediğinde burada görünür ve kitapta turuncu işaretlenir.', 'When you tap a word while reading and choose "To learn", it shows up here and is marked orange in the book.')
                : L('"Öğrendim" dediğin kelimeler burada toplanır ve kitapta yeşil işaretlenir.', 'Words you mark as "Learned" are collected here and marked green in the book.'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.5),
          ),
          ]),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: words.length,
      itemBuilder: (c, i) {
        final w = words[i];
        final meaning = w.meaning ?? app.shortMeaning(w.lemma);
        return Card(
          child: InkWell(
            onTap: () {
              final isPhrase = w.lemma.contains(' ');
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
                      Text(displayPhrase(w.lemma), style: enStyle(theme, theme.textTheme.titleMedium).copyWith(fontWeight: FontWeight.w700)),
                      if (meaning != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(meaning, maxLines: 2, overflow: TextOverflow.ellipsis, style: trStyle(theme, theme.textTheme.bodyMedium)),
                        ),
                      if (w.context != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('“${w.context}”',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontFamily: readingFont, fontStyle: FontStyle.italic, fontSize: 13.5, height: 1.4, color: theme.colorScheme.onSurfaceVariant)),
                        ),
                      if (w.bookTitle != null)
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
                    tooltip: status == WordStatus.learning ? L('Öğrendim', 'Learned') : L('Tekrar öğreneceğim', 'Learn again'),
                    icon: Icon(status == WordStatus.learning ? Icons.check_circle_outline_rounded : Icons.replay_rounded,
                        color: status == WordStatus.learning ? learnedColor : theme.colorScheme.onSurfaceVariant),
                    onPressed: () => app.setWord(w.lemma, status == WordStatus.learning ? WordStatus.learned : WordStatus.learning),
                  ),
                ),
                const SizedBox(width: 4),
              ]),
            ),
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------------ categories + dictionary
class CategoriesPage extends StatefulWidget {
  final AppState app;
  const CategoriesPage({super.key, required this.app});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  final search = TextEditingController();

  void _lookup(String q) {
    q = q.trim().toLowerCase();
    if (q.isEmpty) return;
    final e = widget.app.dict.exprs.where((e) => e.phrase == q).firstOrNull;
    if (e != null && q.contains(' ')) {
      showExprSheet(context, widget.app, e, null);
      return;
    }
    showWordSheet(context, widget.app, q);
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final counts = <String, int>{};
    for (final e in app.dict.exprs) {
      counts[e.cat] = (counts[e.cat] ?? 0) + 1;
    }
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final cols = width >= 1100 ? 3 : width >= 640 ? 2 : 1;
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    return Scaffold(
      appBar: AppBar(toolbarHeight: 68, title: Text(L('Sözlük', 'Dictionary'), style: theme.textTheme.headlineSmall)),
      body: CustomScrollView(slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          sliver: SliverToBoxAdapter(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: L('Kelime veya kalıp ara', 'Search a word or expression'),
                  suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward_rounded), onPressed: () => _lookup(search.text)),
                ),
                onSubmitted: _lookup,
              ),
              SectionLabel(L('Kalıp kategorileri · $total ifade', 'Expression categories · $total entries')),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisExtent: 92, crossAxisSpacing: 10, mainAxisSpacing: 0),
            delegate: SliverChildBuilderDelegate(childCount: categories.length, (context, i) {
              final c = categories[i];
              final cc = theme.brightness == Brightness.dark ? Color.lerp(c.color, Colors.white, 0.3)! : c.color;
              return Card(
                child: InkWell(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _CategoryList(app: app, cat: c))),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
                    child: Row(children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: c.color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(12)),
                        alignment: Alignment.center,
                        child: Text(c.name.substring(0, 1), style: TextStyle(color: cc, fontWeight: FontWeight.w800, fontSize: 19)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(uiEnglish ? c.name : c.tr, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontSize: 15)),
                          const SizedBox(height: 2),
                          Text(c.desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(height: 1.3)),
                        ]),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(8)),
                        child: Text('${counts[c.id] ?? 0}', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
                      ),
                    ]),
                  ),
                ),
              );
            }),
          ),
        ),
      ]),
    );
  }
}

class _CategoryList extends StatefulWidget {
  final AppState app;
  final CategoryInfo cat;
  const _CategoryList({required this.app, required this.cat});

  @override
  State<_CategoryList> createState() => _CategoryListState();
}

class _CategoryListState extends State<_CategoryList> {
  String q = '';
  late final List<Expr> all = widget.app.dict.byCategory(widget.cat.id);

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final list = q.isEmpty ? all : all.where((e) => e.phrase.contains(q) || displayPhrase(e.phrase).contains(q) || (e.trShown?.toLowerCase().contains(q) ?? false)).toList();
    return Scaffold(
      appBar: AppBar(title: Text(uiEnglish ? widget.cat.name : '${widget.cat.tr} · ${widget.cat.name}')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: L('${all.length} ifade içinde ara', 'Search ${all.length} entries')),
            onChanged: (v) => setState(() => q = v.toLowerCase()),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
            separatorBuilder: (_, _) => const Divider(indent: 16, endIndent: 16),
            itemCount: list.length,
            itemBuilder: (c, i) {
              final e = list[i];
              final st = app.user.statuses[e.phrase];
              return ListTile(
                title: Text(displayPhrase(e.phrase), style: TextStyle(fontWeight: FontWeight.w600, color: widget.cat.color)),
                subtitle: Text([if (app.showTr && e.trShown != null) e.trShown!, if ((app.showEn || e.trShown == null) && e.en != null) e.en!].join('\n'), maxLines: 3),
                trailing: st == null ? null : Icon(Icons.circle, size: 12, color: st == WordStatus.learning ? learningColor : learnedColor),
                onTap: () async {
                  await showExprSheet(context, app, e, null);
                  if (mounted) setState(() {});
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}
