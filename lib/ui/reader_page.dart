import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../data/user_db.dart';
import '../tts/read_aloud.dart';
import '../tts/speech.dart';
import '../tts/voice_ui.dart';
import 'expr_sheet.dart';
import 'grammar_mark_sheet.dart';
import 'paragraph_view.dart';
import 'sentence_sheet.dart';
import 'reading_sheet.dart';
import 'theme.dart';
import '../l10n.dart';
import 'word_sheet.dart';
import '../nlp/text.dart' as nlp;

class ReaderPage extends StatefulWidget {
  final AppState app;
  final Book book;
  const ReaderPage({super.key, required this.app, required this.book});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  late List<Chapter> chapters;
  late int chapter;
  List<Para> paras = [];
  final scroll = ScrollController();
  final _scaffold = GlobalKey<ScaffoldState>();
  final _paraKeys = <int, GlobalKey>{};
  late final reader = ReadAloud(paras: () => paras, nextChapter: _nextChapterForSpeech);

  AppState get app => widget.app;

  @override
  void initState() {
    super.initState();
    chapters = app.user.chapters(widget.book.id);
    chapter = widget.book.lastChapter.clamp(0, chapters.length - 1);
    _load(restoreOffset: widget.book.lastParagraph.toDouble());
    scroll.addListener(_saveSoon);
    app.addListener(_onApp);
    reader.addListener(_onApp);
  }

  @override
  void dispose() {
    _save();
    app.removeListener(_onApp);
    reader.dispose();
    scroll.dispose();
    super.dispose();
  }

  void _onApp() => setState(() {});

  DateTime _lastSave = DateTime(0);
  void _saveSoon() {
    if (DateTime.now().difference(_lastSave).inSeconds >= 2) _save();
  }

  void _save() {
    _lastSave = DateTime.now();
    final off = scroll.hasClients ? scroll.offset.round() : 0;
    widget.book.lastChapter = chapter;
    widget.book.lastParagraph = off;
    app.user.saveProgress(widget.book.id, chapter, off);
  }

  void _load({double restoreOffset = 0}) {
    paras = app.user.paras(widget.book.id, chapter);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) scroll.jumpTo(restoreOffset.clamp(0, scroll.position.maxScrollExtent));
    });
  }

  void _go(int c) {
    if (c < 0 || c >= chapters.length) return;
    reader.stop();
    setState(() {
      chapter = c;
      _load();
    });
    _save();
  }

  Future<bool> _nextChapterForSpeech() async {
    if (!mounted || chapter >= chapters.length - 1) return false;
    setState(() {
      chapter++;
      _load();
    });
    _save();
    return true;
  }

  /// Index of the first paragraph whose text is on screen.
  int _firstVisiblePara() {
    final vp = context.findRenderObject();
    var best = -1;
    double bestTop = double.infinity;
    for (final e in _paraKeys.entries) {
      final ro = e.value.currentContext?.findRenderObject();
      if (ro is! RenderBox || !ro.attached || e.key >= paras.length) continue;
      final top = ro.localToGlobal(Offset.zero, ancestor: vp).dy;
      final bottom = top + ro.size.height;
      // below the app bar and not already scrolled past
      if (bottom > kToolbarHeight + 40 && top < bestTop) {
        bestTop = top;
        best = e.key;
      }
    }
    return best < 0 ? 0 : best;
  }

  /// The chapter's text on the clipboard, to paste anywhere (the reader's own
  /// text answers taps with word cards, so it cannot be selected).
  Future<void> _copyChapter() async {
    await Clipboard.setData(ClipboardData(text: '${chapters[chapter].title}\n\n${app.user.chapterText(widget.book.id, chapter)}'));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(L('Bölümün metni panoya kopyalandı.', 'The chapter text was copied to the clipboard.'))));
  }

  Future<void> _toggleReadAloud() async {
    if (reader.active) {
      reader.stop();
      return;
    }
    if (!await ensureVoicePack(context)) return;
    if (!mounted) return;
    reader.start(_firstVisiblePara());
  }

  Widget _speechBar(ThemeData theme) {
    final s = Speech.instance;
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              const SizedBox(width: 6),
              Icon(Icons.headphones_rounded, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(s.voice.name, style: theme.textTheme.titleSmall, overflow: TextOverflow.ellipsis),
              ),
              IconButton(tooltip: L('Önceki cümle', 'Previous sentence'), onPressed: () => reader.skip(-1), icon: const Icon(Icons.skip_previous_rounded)),
              IconButton.filled(
                tooltip: reader.paused ? L('Devam', 'Resume') : L('Duraklat', 'Pause'),
                onPressed: reader.toggle,
                icon: Icon(reader.paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
              ),
              IconButton(tooltip: L('Sonraki cümle', 'Next sentence'), onPressed: () => reader.skip(1), icon: const Icon(Icons.skip_next_rounded)),
              PopupMenuButton<double>(
                tooltip: L('Hız', 'Speed'),
                initialValue: s.speed,
                onSelected: (v) {
                  s.speed = v;
                  reader.skip(0);
                },
                itemBuilder: (_) => [
                  for (final v in const [0.7, 0.8, 0.9, 1.0, 1.1, 1.25]) PopupMenuItem(value: v, child: Text('$v×')),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('${s.speed.toStringAsFixed(s.speed == s.speed.roundToDouble() ? 0 : 2)}×', style: theme.textTheme.labelLarge),
                ),
              ),
              IconButton(tooltip: L('Sesli okumayı kapat', 'Stop reading aloud'), onPressed: reader.stop, icon: const Icon(Icons.close_rounded)),
            ],
          ),
        ),
      ),
    );
  }

  void _onWord(Para p, ParaAnalysis a, int i) async {
    // A word coloured by a grammar filter (a tense, a conditional …) opens the explanation.
    if (a.shownAt(app, i).mark != null) {
      await showGrammarMarkSheet(context, app, a, a.grammarAt(app, i), i, onWord: () => _openWord(p, a, i));
      if (mounted) setState(() {});
      return;
    }
    await _openWord(p, a, i);
  }

  Future<void> _openWord(Para p, ParaAnalysis a, int i) async {
    if (!mounted) return;
    final ctx = buildContext(app, p, a, i, bookId: widget.book.id, bookTitle: widget.book.title);
    // The expression the tap belongs to (the same one the underline shows).
    final multi = a.expressionsAt(app, i).where((m) => m.tokens.length > 1).toList();
    if (multi.isEmpty) {
      await showWordSheet(context, app, a.tokens[i].text, ctx: ctx);
      if (mounted) setState(() {});
      return;
    }
    var chosen = multi.first;
    final overlapping = multi.any((m) => m.tokens.join(',') != chosen.tokens.join(','));
    if (overlapping) {
      // Expressions that share the word ("make up" / "make up one's mind"):
      // the reader asks which one is meant, and allows the single word.
      final pick = await _pickPhrase([for (final m in multi) nlp.displayPhrase(m.expr.phrase)], a.tokens[i].text);
      if (!mounted || pick == null) return;
      if (pick < 0) {
        await showWordSheet(context, app, a.tokens[i].text, ctx: ctx);
        if (mounted) setState(() {});
        return;
      }
      chosen = multi[pick];
    }
    await showExprSheet(context, app, chosen.expr, ctx, [for (final t in chosen.tokens) a.tokens[t].text]);
    if (mounted) setState(() {});
  }

  /// "Bunu mu demek istedin?": the phrases that share a word, and the word alone (-1).
  Future<int?> _pickPhrase(List<String> phrases, String word) => showModalBottomSheet<int>(
        context: context,
        showDragHandle: true,
        builder: (c) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(L('Bunu mu demek istedin?', 'Did you mean?'), style: Theme.of(c).textTheme.titleMedium),
            ),
            for (var k = 0; k < phrases.length; k++)
              ListTile(key: ValueKey('phrase-choice-$k'), title: Text(phrases[k]), onTap: () => Navigator.pop(c, k)),
            ListTile(
              key: const ValueKey('phrase-choice-word'),
              leading: const Icon(Icons.text_fields_rounded),
              title: Text(L("Sadece '$word' kelimesi", "Only the word '$word'")),
              onTap: () => Navigator.pop(c, -1),
            ),
          ]),
        ),
      );

  void _onSentence(Para p, ParaAnalysis a, int i) async {
    await showSentenceSheet(context, app, p, a, i, bookId: widget.book.id, bookTitle: widget.book.title);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ch = chapters[chapter];
    final wide = MediaQuery.sizeOf(context).width > 1000;
    final filters = FilterPanel(app: app);
    final paper = pageColor(app, theme);
    return Theme(
      data: readerTheme(app, theme),
      child: Scaffold(
        key: _scaffold,
        backgroundColor: paper,
        appBar: AppBar(
          backgroundColor: paper,
          leading: const BackButton(),
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.book.title, style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis),
              Text('${chapterName(ch.title)}  ·  ${chapter + 1}/${chapters.length}', style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
            ],
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(3),
            child: LinearProgressIndicator(
              value: (chapter + 1) / chapters.length,
              minHeight: 3,
              borderRadius: BorderRadius.zero,
              backgroundColor: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          actions: [
            if (Speech.supported)
              IconButton(
                tooltip: reader.active ? L('Sesli okumayı durdur', 'Stop reading aloud') : L('Sesli oku', 'Read aloud'),
                icon: Icon(reader.active ? Icons.headset_off_rounded : Icons.headphones_rounded),
                onPressed: _toggleReadAloud,
              ),
            IconButton(tooltip: L('Okuma görünümü', 'Reading view'), icon: const Icon(Icons.text_fields_rounded), onPressed: () => showReadingSheet(context, app)),
            IconButton(tooltip: L('Bu bölümün metnini kopyala', 'Copy this chapter\'s text'), icon: const Icon(Icons.copy_all_rounded), onPressed: _copyChapter),
            IconButton(tooltip: L('Bölümler', 'Chapters'), icon: const Icon(Icons.list), onPressed: () => _scaffold.currentState!.openDrawer()),
            if (!wide)
              IconButton(
                tooltip: L('Filtreler', 'Filters'),
                icon: Badge(isLabelVisible: app.enabledCats.isNotEmpty, label: Text('${app.enabledCats.length}'), child: const Icon(Icons.filter_alt_outlined)),
                onPressed: () => _scaffold.currentState!.openEndDrawer(),
              ),
          ],
        ),
        drawer: Drawer(
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Row(
                    children: [
                      BookCover(title: widget.book.title, format: widget.book.format, width: 44),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                            Text(L('${chapters.length} bölüm', '${chapters.length} chapters'), style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    itemCount: chapters.length,
                    itemBuilder: (c, i) => ListTile(
                      selected: i == chapter,
                      selectedTileColor: theme.colorScheme.primaryContainer,
                      leading: Text(
                        '${i + 1}'.padLeft(2, '0'),
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: i == chapter ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      minLeadingWidth: 24,
                      title: Text(
                        chapterName(chapters[i].title),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: i == chapter ? FontWeight.w700 : FontWeight.w500, color: i == chapter ? theme.colorScheme.primary : null),
                      ),
                      onTap: () {
                        Navigator.pop(c);
                        _go(i);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: reader.active ? _speechBar(theme) : null,
        endDrawer: wide ? null : Drawer(width: 340, child: SafeArea(child: filters)),
        body: Row(
          children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                    itemCount: paras.length + 2,
                    itemBuilder: (c, i) {
                      if (i == 0) {
                        return ch.summary == null || !app.showTr
                            ? const SizedBox.shrink()
                            : Container(
                                margin: const EdgeInsets.only(bottom: 20),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(color: theme.colorScheme.primaryContainer.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(16)),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.auto_awesome_rounded, size: 16, color: theme.colorScheme.primary),
                                        const SizedBox(width: 6),
                                        Text(L('Bu bölümde neler anlatılıyor', 'What this chapter is about'), style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(ch.summary!, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
                                  ],
                                ),
                              );
                      }
                      if (i == paras.length + 1) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 28),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              OutlinedButton.icon(onPressed: chapter > 0 ? () => _go(chapter - 1) : null, icon: const Icon(Icons.chevron_left), label: Text(L('Önceki', 'Previous'))),
                              FilledButton.icon(
                                onPressed: chapter < chapters.length - 1 ? () => _go(chapter + 1) : null,
                                icon: const Icon(Icons.chevron_right),
                                label: Text(L('Sonraki bölüm', 'Next chapter')),
                              ),
                            ],
                          ),
                        );
                      }
                      final p = paras[i - 1];
                      return KeyedSubtree(
                        key: _paraKeys.putIfAbsent(i - 1, GlobalKey.new),
                        child: ParagraphView(key: ValueKey(p.id), app: app, para: p, onWord: _onWord, onSentence: _onSentence, speaking: reader.rangeIn(i - 1)),
                      );
                    },
                  ),
                ),
              ),
            ),
            if (wide) ...[
              const VerticalDivider(width: 1),
              SizedBox(
                width: 320,
                child: ColoredBox(color: theme.colorScheme.surface, child: filters),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class FilterPanel extends StatefulWidget {
  final AppState app;
  const FilterPanel({super.key, required this.app});

  @override
  State<FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends State<FilterPanel> {
  AppState get app => widget.app;

  /// Open groups: those with a filter on, or the first one when nothing is on.
  late final Set<int> _open = {
    for (var g = 0; g < filterGroups.length; g++)
      if (filterGroups[g].$3.any(app.enabledCats.contains)) g,
  }..addAll(app.enabledCats.isEmpty ? const {0} : const <int>{});

  Widget _group(ThemeData theme, int g) {
    final (tr, en, ids) = filterGroups[g];
    final on = ids.where(app.enabledCats.contains).length;
    final open = _open.contains(g);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: ValueKey('filter-group-$g'),
          onTap: () => setState(() => open ? _open.remove(g) : _open.add(g)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(L(tr, en), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                ),
                if (on > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(10)),
                    child: Text('$on / ${ids.length}', style: theme.textTheme.labelSmall),
                  ),
                Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded),
              ],
            ),
          ),
        ),
        if (open) ...[
          if (g == 1) Text(L('Dokununca açıklaması ve ilgili Gramer konusu açılır.', 'Tap one to see the explanation and the matching Grammar topic.'), style: theme.textTheme.bodySmall),
          Row(
            children: [
              TextButton(onPressed: () => app.setCats(ids, true), child: Text(L('Bu grubun tümü', 'All in this group'))),
              TextButton(onPressed: () => app.setCats(ids, false), child: Text(L('Hiçbiri', 'None'))),
            ],
          ),
          for (final id in ids) ...[_tile(theme, categoryById[id]!), if (id == 'g_tenses' && app.enabledCats.contains(id)) _tenseLegend(theme)],
        ],
        const Divider(height: 1),
      ],
    );
  }

  Widget _tenseLegend(ThemeData theme) => Padding(
    padding: const EdgeInsets.only(left: 40, bottom: 6),
    child: Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        for (final (i, t) in [L('şimdiki / geniş', 'present'), L('geçmiş', 'past'), L('gelecek', 'future')].indexed)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: _shade(theme, tenseToneColors[i]), shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              Text(
                t,
                style: theme.textTheme.bodySmall?.copyWith(color: _shade(theme, tenseToneColors[i]), fontWeight: FontWeight.w600),
              ),
            ],
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
        children: [
          Row(
            children: [
              Expanded(child: Text(L('Filtreler', 'Filters'), style: theme.textTheme.titleLarge?.copyWith(fontSize: 19))),
              TextButton(onPressed: () => app.setAllCats(true), child: Text(L('Tümü', 'All'))),
              TextButton(onPressed: () => app.setAllCats(false), child: Text(L('Hiçbiri', 'None'))),
            ],
          ),
          Text(L('Seçtiğin türler kitapta kendi rengiyle altı çizili gösterilir.', 'The types you pick are underlined in the book in their own color.'), style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          for (var g = 0; g < filterGroups.length; g++) _group(theme, g),
          const SizedBox(height: 8),
          Text(L('Kelime renkleri', 'Word colors'), style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          _legend(learningColor, L('Öğreneceğim listesindeki kelimeler', 'Words on your To learn list')),
          _legend(learnedColor, L('Öğrendim dediğin kelimeler', 'Words you marked as Learned')),
          const SizedBox(height: 10),
          Text(L('İpucu: kelimeye dokun = anlam; uzun bas = cümle analizi.', 'Tip: tap a word = meaning; long press = sentence analysis.'), style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  Color _shade(ThemeData theme, Color c) => theme.brightness == Brightness.dark ? Color.lerp(c, Colors.white, 0.35)! : c;

  Widget _tile(ThemeData theme, CategoryInfo c) => CheckboxListTile(
    key: ValueKey('filter-${c.id}'),
    dense: true,
    contentPadding: EdgeInsets.zero,
    value: app.enabledCats.contains(c.id),
    onChanged: (_) => app.toggleCat(c.id),
    secondary: Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(color: c.color, shape: BoxShape.circle),
    ),
    title: Text(
      uiEnglish ? c.name : c.tr,
      style: TextStyle(color: _shade(theme, c.color), fontWeight: FontWeight.w600),
    ),
    // The English name of the type is worth learning, so the Turkish
    // interface shows it after the description.
    subtitle: Text(uiEnglish ? c.desc : '${c.desc} (${c.name})'),
  );

  Widget _legend(Color c, String t) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), color: c.withValues(alpha: 0.38), child: Text(L('kelime', 'words'))),
        const SizedBox(width: 8),
        Expanded(child: Text(t)),
      ],
    ),
  );
}
