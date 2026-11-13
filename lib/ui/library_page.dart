
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/user_db.dart';
import '../import/importers.dart';
import '../import/ocr.dart';
import '../online/ai_service.dart';
import '../l10n.dart';
import 'reader_page.dart';
import 'theme.dart';

class LibraryPage extends StatefulWidget {
  final AppState app;
  const LibraryPage({super.key, required this.app});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  bool importing = false;
  String? importStatus;

  Future<void> _import() async {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: supportedExtensions,
    );
    final path = res.isEmpty ? null : res.first.path;
    if (path == null) return;
    await importPath(path);
  }

  Future<void> importPath(String path) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      importing = true;
      importStatus = null;
    });
    try {
      final ocr = await OcrEngine.best(
        ai: AiService.fromSettings(widget.app.user),
      );
      final book = await importFile(
        path,
        ocr: ocr,
        isWord: widget.app.isWord,
        onProgress: (m) => setState(() => importStatus = m),
      );
      final id = widget.app.user.insertBook(book);
      final words = book.chapters.fold<int>(
        0,
        (s, c) =>
            s +
            c.paragraphs.fold<int>(0, (s2, p) => s2 + p.$2.split(' ').length),
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            L('"${book.title}" eklendi: ${book.chapters.length} bölüm, ~$words kelime.', '"${book.title}" added: ${book.chapters.length} chapters, ~$words words.'),
          ),
        ),
      );
      widget.app.analyzer.tick(onlyBook: id);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(L('İçe aktarılamadı: $e', 'Could not import: $e')),
          duration: const Duration(seconds: 8),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          importing = false;
          importStatus = null;
        });
      }
    }
  }

  Future<void> _onMenu(Book b, String v) async {
    if (v == 'analyze') {
      final svc = AiService.fromSettings(widget.app.user);
      final m = ScaffoldMessenger.of(context);
      if (svc == null) {
        m.showSnackBar(SnackBar(content: Text(L('Önce Ayarlar\'dan bir yapay zekâ servisi bağlayın.', 'First connect an AI service in Settings.'))));
      } else if (!await svc.reachable()) {
        m.showSnackBar(SnackBar(content: Text(L('İnternet yok. Bağlantı gelince analiz kendiliğinden başlar.', 'No internet. The analysis starts by itself when you are back online.'))));
      } else {
        widget.app.analyzer.tick(force: true, onlyBook: b.id);
      }
    } else if (v == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(L('Kitap silinsin mi?', 'Delete this book?')),
          content: Text(L('"${b.title}" kitaplıktan kaldırılacak. Kelime listen korunur.', '"${b.title}" will be removed from the library. Your word list is kept.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(L('Vazgeç', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(L('Sil', 'Delete'))),
          ],
        ),
      );
      if (ok == true) {
        widget.app.user.deleteBook(b.id);
        setState(() {});
      }
    }
  }

  Future<void> _open(Book b) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ReaderPage(app: widget.app, book: b)));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final books = widget.app.user.books();
    final theme = Theme.of(context);
    final st = widget.app.user.statuses.values;
    final learning = st.where((s) => s == WordStatus.learning).length;
    final learned = st.where((s) => s == WordStatus.learned).length;
    final width = MediaQuery.sizeOf(context).width;
    final cols = width >= 1200 ? 3 : width >= 820 ? 2 : 1;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: importing ? null : _import,
        icon: importing
            ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.onPrimary))
            : const Icon(Icons.add_rounded),
        label: Text(importing ? L('Dönüştürülüyor…', 'Converting…') : L('Kitap ekle', 'Add book')),
      ),
      body: SafeArea(
        bottom: false,
        child: ValueListenableBuilder(
          valueListenable: widget.app.analyzer.status,
          builder: (context, progress, _) => CustomScrollView(slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (width < 720) ...[
                    Row(children: [
                      const BrandMark(),
                      const SizedBox(width: 10),
                      Text('VocaBloom', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    ]),
                    const SizedBox(height: 18),
                  ],
                  Text(L('Kitaplığım', 'My library'), style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 4),
                  Text(L('Okurken bilmediğin kelimeleri öğren.', 'Learn the words you don\'t know while you read.'),
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 18),
                  _StatsStrip(books: books.length, learning: learning, learned: learned),
                  if (importStatus != null) ...[
                    const SizedBox(height: 14),
                    Panel(children: [
                      Text(importStatus!, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 10),
                      const LinearProgressIndicator(),
                    ]),
                  ],
                  if (books.isNotEmpty) ...[
                    SectionLabel(L('Okumaya devam et', 'Continue reading'), padding: const EdgeInsets.fromLTRB(2, 24, 2, 10)),
                    _ContinueCard(book: books.first, onTap: () => _open(books.first)),
                    if (books.length > 1)
                      SectionLabel(L('Tüm kitaplar', 'All books'), padding: const EdgeInsets.fromLTRB(2, 24, 2, 6)),
                  ],
                ]),
              ),
            ),
            if (books.isEmpty)
              SliverFillRemaining(hasScrollBody: false, child: _EmptyLibrary(onAdd: importing ? null : _import))
            else if (books.length > 1)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols, mainAxisExtent: 128, crossAxisSpacing: 12, mainAxisSpacing: 2),
                  delegate: SliverChildBuilderDelegate(
                    (c, i) {
                      final b = books[i + 1];
                      return _BookCard(book: b, status: progress[b.id], onTap: () => _open(b), onMenu: (v) => _onMenu(b, v));
                    },
                    childCount: books.length - 1,
                  ),
                ),
              )
            else
              const SliverToBoxAdapter(child: SizedBox(height: 110)),
          ]),
        ),
      ),
    );
  }
}

/// Small rounded app mark (a book that blooms).
class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 30});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(gradient: Brand.gradient, borderRadius: BorderRadius.circular(size * 0.3)),
        child: Icon(Icons.local_florist_rounded, color: Colors.white, size: size * 0.6),
      );
}

class _StatsStrip extends StatelessWidget {
  final int books, learning, learned;
  const _StatsStrip({required this.books, required this.learning, required this.learned});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget stat(String value, String label, Color dot) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Row(children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(color: Colors.white.withValues(alpha: 0.82))),
              ),
            ]),
          ]),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        gradient: Brand.gradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Brand.violet.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Row(children: [
        stat('$books', L('Kitap', 'Books'), Colors.white),
        stat('$learning', L('Öğreneceğim', 'To learn'), learningColor),
        stat('$learned', L('Öğrendim', 'Learned'), learnedColor),
      ]),
    );
  }
}

double _progress(Book b) => b.chapterCount <= 1 ? 0.0 : b.lastChapter / (b.chapterCount - 1);

class _ContinueCard extends StatelessWidget {
  final Book book;
  final VoidCallback onTap;
  const _ContinueCard({required this.book, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = _progress(book);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            BookCover(title: book.title, format: book.format, width: 70),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleLarge?.copyWith(fontSize: 19)),
                if (book.author != null) ...[
                  const SizedBox(height: 2),
                  Text(book.author!, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: LinearProgressIndicator(value: pct)),
                  const SizedBox(width: 10),
                  Text('%${(pct * 100).round()}', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ]),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: onTap,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                  icon: const Icon(Icons.auto_stories_rounded, size: 18),
                  label: Text(L('Bölüm ${book.lastChapter + 1} · Devam et', 'Chapter ${book.lastChapter + 1} · Continue')),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _BookCard extends StatelessWidget {
  final Book book;
  final String? status;
  final VoidCallback onTap;
  final ValueChanged<String> onMenu;
  const _BookCard({required this.book, required this.status, required this.onTap, required this.onMenu});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = book;
    final pct = _progress(b);
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          child: Row(children: [
            BookCover(title: b.title, format: b.format, width: 58),
            const SizedBox(width: 14),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(b.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text([if (b.author != null) b.author!, L('${b.chapterCount} bölüm', '${b.chapterCount} chapters')].join(' · '),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: LinearProgressIndicator(value: pct, minHeight: 5)),
                  const SizedBox(width: 8),
                  Text('%${(pct * 100).round()}', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ]),
                if (status != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(status!, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary)),
                  ),
              ]),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, color: theme.colorScheme.onSurfaceVariant),
              onSelected: onMenu,
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'analyze',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.auto_awesome_outlined),
                    title: Text(L('Çevrimiçi analiz et', 'Analyze online')),
                    subtitle: Text(L('Çeviri + bölüm özetleri', 'Translation + chapter summaries')),
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.error),
                    title: Text(L('Sil', 'Delete'), style: TextStyle(color: theme.colorScheme.error)),
                  ),
                ),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  final VoidCallback? onAdd;
  const _EmptyLibrary({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 120),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(28)),
          child: Icon(Icons.menu_book_rounded, size: 42, color: theme.colorScheme.primary),
        ),
        const SizedBox(height: 20),
        Text(L('İlk kitabını ekle', 'Add your first book'), style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(
            L('EPUB, PDF, TXT, DOCX, ODT, HTML, FB2, RTF veya Markdown dosyası ekle. Kitap uygulamanın kendi formatına çevrilir ve cihazında saklanır.', 'Add an EPUB, PDF, TXT, DOCX, ODT, HTML, FB2, RTF or Markdown file. The book is converted to the app\'s own format and stored on your device.'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.5),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add_rounded), label: Text(L('Kitap seç', 'Choose a book'))),
      ]),
    );
  }
}

/// Used by tests and the CLI flag to import without the file picker.
Future<int> importForTest(AppState app, String path) async {
  final ocr = await OcrEngine.best(ai: AiService.fromSettings(app.user));
  final ImportedBook b = await importFile(path, ocr: ocr, isWord: app.isWord);
  return app.user.insertBook(b);
}
