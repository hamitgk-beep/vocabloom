import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../data/free_library.dart';
import '../data/user_db.dart';
import '../l10n.dart';
import 'reader_page.dart';
import 'theme.dart';

/// "Ücretsiz kütüphane": free stories and classics by CEFR level. Short
/// stories come with the app; books are downloaded when first opened.
class FreeLibraryPage extends StatefulWidget {
  final AppState app;
  const FreeLibraryPage({super.key, required this.app});

  @override
  State<FreeLibraryPage> createState() => _FreeLibraryPageState();
}

class _FreeLibraryPageState extends State<FreeLibraryPage> {
  FreeLibrary? lib;
  String? level;
  String kind = 'all'; // all, story, book
  String query = '';
  final Map<String, double?> busy = {};

  @override
  void initState() {
    super.initState();
    final saved = widget.app.user.getSetting('library_level');
    if (libraryLevels.contains(saved)) level = saved;
    FreeLibrary.load().then((l) {
      if (mounted) setState(() => lib = l);
    });
  }

  void _setLevel(String? l) {
    setState(() => level = l);
    widget.app.user.setSetting('library_level', l);
  }

  Future<void> _open(LibraryItem it) async {
    if (busy.containsKey(it.id)) return;
    final m = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() => busy[it.id] = null);
    try {
      final have = widget.app.user.booksBySource()[it.id];
      final book = await addLibraryItem(widget.app.user, lib!, it,
          onProgress: (p) => mounted ? setState(() => busy[it.id] = p) : null);
      if (have == null) widget.app.analyzer.tick(onlyBook: book.id);
      if (!mounted) return;
      setState(() => busy.remove(it.id));
      await nav.push(MaterialPageRoute(builder: (_) => ReaderPage(app: widget.app, book: book)));
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => busy.remove(it.id));
      m.showSnackBar(SnackBar(
        content: Text(L('İndirilemedi: ${errorText(e)}', 'Could not download: ${errorText(e)}')),
        duration: const Duration(seconds: 6),
      ));
    }
  }

  void _info(LibraryItem it) {
    final t = Theme.of(context);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(it.title, style: t.textTheme.titleLarge),
            if (it.author != null) Text(it.author!, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 14),
            _InfoRow(L('Seviye', 'Level'), '${it.level} · ${_levelName(it.level)}'),
            _InfoRow(L('Uzunluk', 'Length'), _length(it)),
            _InfoRow(L('Lisans', 'License'), it.license == 'Public domain' ? L('Kamu malı (telifsiz)', 'Public domain') : it.license),
            _InfoRow(L('Emeği geçenler', 'Credits'), it.credit),
            if (it.isBook && it.size != null) _InfoRow(L('İndirme', 'Download'), '${(it.size! / 1024).round()} KB'),
            const SizedBox(height: 6),
            Text(
              it.isBook
                  ? L('Seviye, bu kitabın okuma listelerinde genelde verilen seviyedir; yaklaşıktır.',
                      'The level is the one reading lists usually give this book, so it is approximate.')
                  : L('Seviye, kelimelerin ne kadar yaygın olduğuna ve cümle uzunluğuna bakılarak tahmin edildi; yaklaşıktır.',
                      'The level is estimated from how common the words are and how long the sentences are, so it is approximate.'),
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => launchUrl(Uri.parse(it.source), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(L('Kaynağı aç', 'Open the source')),
            ),
          ]),
        ),
      ),
    );
  }

  /// For the list: stories by words, books by chapters.
  String _short(LibraryItem it) => it.isBook
      ? '${L('${it.chapters} bölüm', '${it.chapters} chapters')} · ${_time(it)}'
      : '${L('${_thousands(it.words)} kelime', '${_thousands(it.words)} words')} · ${_time(it)}';

  String _time(LibraryItem it) {
    final mins = it.minutes;
    return mins < 60 ? L('~$mins dk', '~$mins min') : L('~${(mins / 60).round()} saat', '~${(mins / 60).round()} h');
  }

  String _length(LibraryItem it) {
    final mins = it.minutes;
    final time = mins < 60 ? L('~$mins dk', '~$mins min') : L('~${(mins / 60).round()} saat', '~${(mins / 60).round()} h');
    final words = L('${_thousands(it.words)} kelime', '${_thousands(it.words)} words');
    if (!it.isBook) return '$words · $time';
    return '$words · ${L('${it.chapters} bölüm', '${it.chapters} chapters')} · $time';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = lib;
    final have = widget.app.user.booksBySource();
    final q = query.trim().toLowerCase();
    final shown = l == null
        ? <LibraryItem>[]
        : l.items
            .where((it) =>
                (level == null || it.level == level) &&
                (kind == 'all' || it.kind == kind) &&
                (q.isEmpty || it.title.toLowerCase().contains(q) || (it.author ?? '').toLowerCase().contains(q)))
            .toList();
    final books = shown.where((it) => it.isBook).toList();
    final stories = shown.where((it) => !it.isBook).toList();
    final width = MediaQuery.sizeOf(context).width;
    final pad = width >= 900 ? (width - 860) / 2 : 16.0;
    return Scaffold(
      appBar: AppBar(title: Text(L('Ücretsiz kütüphane', 'Free library'))),
      body: l == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(pad, 4, pad, 40),
              children: [
                Text(
                  L('Telifsiz kısa hikâyeler ve klasik kitaplar. Seviyeni seç, dokun ve oku. Hikâyeler uygulamanın içinde; kitaplar ilk açılışta indirilir.',
                      'Free short stories and classic books. Pick your level, tap and read. Stories come with the app; books are downloaded the first time you open them.'),
                  style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.45),
                ),
                const SizedBox(height: 14),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final lv in [null, ...libraryLevels])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          key: ValueKey('lib-level-${lv ?? 'all'}'),
                          label: Text(lv ?? L('Tüm seviyeler', 'All levels')),
                          selected: level == lv,
                          showCheckmark: false,
                          labelStyle: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: level == lv ? Colors.white : (lv == null ? null : cefrColor(lv)),
                          ),
                          selectedColor: lv == null ? cs.primary : cefrColor(lv),
                          onSelected: (_) => _setLevel(lv),
                        ),
                      ),
                  ]),
                ),
                if (level != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text('${level!} · ${_levelName(level!)}: ${_levelNote(level!)}',
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.4)),
                  ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(value: 'all', label: Text(L('Hepsi', 'All'))),
                        ButtonSegment(value: 'story', label: Text(L('Hikâyeler', 'Stories'))),
                        ButtonSegment(value: 'book', label: Text(L('Kitaplar', 'Books'))),
                      ],
                      selected: {kind},
                      onSelectionChanged: (s) => setState(() => kind = s.first),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                TextField(
                  decoration: InputDecoration(
                    hintText: L('Başlık veya yazar ara', 'Search title or author'),
                    prefixIcon: const Icon(Icons.search_rounded),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => query = v),
                ),
                if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Text(
                      level == 'B2' || level == 'C1'
                          ? L('Bu seviyede kısa hikâye yok; Kitaplar\'a bak.', 'No short stories at this level; see Books.')
                          : L('Eşleşen bir şey yok.', 'Nothing matches.'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                if (books.isNotEmpty) ...[
                  SectionLabel(L('Kitaplar · ${books.length}', 'Books · ${books.length}')),
                  _Group(children: [
                    for (final it in books)
                      _ItemTile(item: it, length: _short(it), book: have[it.id], progress: busy[it.id], busy: busy.containsKey(it.id),
                          onTap: () => _open(it), onInfo: () => _info(it)),
                  ]),
                ],
                if (stories.isNotEmpty) ...[
                  SectionLabel(L('Kısa hikâyeler · ${stories.length}', 'Short stories · ${stories.length}')),
                  _Group(children: [
                    for (final it in stories)
                      _ItemTile(item: it, length: _short(it), book: have[it.id], progress: busy[it.id], busy: busy.containsKey(it.id),
                          onTap: () => _open(it), onInfo: () => _info(it)),
                  ]),
                ],
                const SizedBox(height: 20),
                Text(
                  L('Hikâyeler: Pratham Books / StoryWeaver (CC BY 4.0), yalnız metin. Kitaplar: Project Gutenberg\'deki kamu malı eserler.',
                      'Stories: Pratham Books / StoryWeaver (CC BY 4.0), text only. Books: public-domain works from Project Gutenberg.'),
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
                ),
              ],
            ),
    );
  }
}

String _thousands(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(uiEnglish ? ',' : '.');
    b.write(s[i]);
  }
  return b.toString();
}

String _levelName(String l) => switch (l) {
      'A1' => L('Başlangıç', 'Beginner'),
      'A2' => L('Temel', 'Elementary'),
      'B1' => L('Orta', 'Intermediate'),
      'B2' => L('Orta üstü', 'Upper intermediate'),
      _ => L('İleri', 'Advanced'),
    };

String _levelNote(String l) => switch (l) {
      'A1' => L('çok kısa cümleler, en sık kelimeler.', 'very short sentences, the most common words.'),
      'A2' => L('kısa hikâyeler, günlük kelimeler.', 'short stories, everyday words.'),
      'B1' => L('daha uzun hikâyeler ve kolay klasikler.', 'longer stories and easy classics.'),
      'B2' => L('klasik romanlar ve öyküler.', 'classic novels and stories.'),
      _ => L('eski üsluplu, uzun ve zengin dilli romanlar.', 'long novels in older, richer English.'),
    };

class _Group extends StatelessWidget {
  final List<Widget> children;
  const _Group({required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: cs.outlineVariant)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (final (i, c) in children.indexed) ...[
          if (i > 0) Divider(height: 1, indent: 16, endIndent: 16, color: cs.outlineVariant),
          c,
        ],
      ]),
    );
  }
}

class _ItemTile extends StatelessWidget {
  final LibraryItem item;
  final String length;
  final Book? book;
  final bool busy;
  final double? progress;
  final VoidCallback onTap, onInfo;
  const _ItemTile(
      {required this.item, required this.length, required this.book, required this.busy, required this.progress, required this.onTap, required this.onInfo});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final c = cefrColor(item.level);
    final sub = [if (item.author != null) item.author!, length].join(' · ');
    Widget trailing;
    if (busy) {
      trailing = SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, value: progress));
    } else if (book != null) {
      trailing = Icon(Icons.check_circle_rounded, color: learnedColor, semanticLabel: L('Kitaplıkta', 'In your library'));
    } else {
      trailing = Icon(item.isBook ? Icons.download_rounded : Icons.add_circle_outline_rounded, color: cs.primary);
    }
    return InkWell(
      key: ValueKey('lib-${item.id}'),
      onTap: onTap,
      onLongPress: onInfo,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(12)),
            child: Text(item.level, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
          const SizedBox(width: 8),
          trailing,
          IconButton(
            tooltip: L('Bilgi', 'Info'),
            onPressed: onInfo,
            icon: Icon(Icons.info_outline_rounded, size: 20, color: cs.onSurfaceVariant),
          ),
        ]),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 120, child: Text(label, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant))),
        Expanded(child: Text(value, style: t.textTheme.bodyMedium)),
      ]),
    );
  }
}
