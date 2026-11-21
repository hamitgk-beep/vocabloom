import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../data/user_db.dart';
import '../import/importers.dart';
import '../import/ocr.dart';
import '../online/ai_service.dart';
import '../l10n.dart';
import 'free_library_page.dart';
import 'reader_page.dart';
import 'review_page.dart';
import 'theme.dart';

/// Books in the order to continue them: those read most recently first, then
/// the rest as they were added.
List<Book> recentBooks(AppState app) {
  final books = app.user.books();
  final order = {for (final (i, id) in app.stats.recentBookIds().indexed) id: i};
  final read = books.where((b) => order.containsKey(b.id)).toList()..sort((a, b) => order[a.id]!.compareTo(order[b.id]!));
  return [...read, ...books.where((b) => !order.containsKey(b.id))];
}

class LibraryPage extends StatefulWidget {
  final AppState app;

  /// On phones: opens another page of the app (4 free library, 5 stats, 6 settings)
  /// from the buttons on the top bar. Null on wide screens, where the side menu has them.
  final ValueChanged<int>? onTab;

  /// The search field at the top: opens the dictionary.
  final VoidCallback? onSearch;
  const LibraryPage({super.key, required this.app, this.onTab, this.onSearch});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  bool importing = false;
  String? importStatus;

  Future<void> _import() async {
    final res = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: supportedExtensions);
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
      final ocr = await OcrEngine.best(ai: AiService.fromSettings(widget.app.user));
      final book = await importFile(path, ocr: ocr, isWord: widget.app.isWord, onProgress: (m) => setState(() => importStatus = m));
      final lang = UserDb.textLang(book);
      final id = widget.app.user.insertBook(book, lang: lang);
      final words = book.chapters.fold<int>(0, (s, c) => s + c.paragraphs.fold<int>(0, (s2, p) => s2 + p.$2.split(' ').length));
      // A book in the other language goes to that language's library.
      final other = lang != widget.app.user.lang;
      final otherName = lang == 'tr' ? L('Türkçe', 'Turkish') : L('İngilizce', 'English');
      messenger.showSnackBar(
        SnackBar(
          duration: Duration(seconds: other ? 8 : 4),
          content: Text(
            other
                ? L('"${book.title}" $otherName bir kitap. Ayarlar\'da öğrenilen dili $otherName yaptığında kitaplığında görünür.',
                    '"${book.title}" is in $otherName. It shows in your library when $otherName is the language you learn (Settings).')
                : L(
                    '"${book.title}" eklendi: ${book.chapters.length} bölüm, ~$words kelime.',
                    '"${book.title}" added: ${book.chapters.length} chapters, ~$words words.',
                  ),
          ),
        ),
      );
      if (lang == 'en') widget.app.analyzer.tick(onlyBook: id);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(L('İçe aktarılamadı: ${errorText(e)}', 'Could not import: ${errorText(e)}')), duration: const Duration(seconds: 8)),
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
        m.showSnackBar(
          SnackBar(
            content: Text(
              L('İnternet yok. Bağlantı gelince analiz kendiliğinden başlar.', 'No internet. The analysis starts by itself when you are back online.'),
            ),
          ),
        );
      } else {
        widget.app.analyzer.tick(force: true, onlyBook: b.id);
      }
    } else if (v == 'export') {
      final m = ScaffoldMessenger.of(context);
      final text = widget.app.user.bookText(b.id);
      final name = '${b.title.replaceAll(RegExp(r'[\\/:*?"<>|]+'), ' ').trim()}.txt';
      try {
        final saved = await FilePicker.saveFile(
          dialogTitle: L('Kitabın metnini kaydet', 'Save the book text'),
          fileName: name,
          bytes: Uint8List.fromList(utf8.encode(text)),
          mimeType: 'text/plain',
        );
        if (saved != null) {
          m.showSnackBar(SnackBar(content: Text(L('Metin kaydedildi: $name', 'Text saved: $name'))));
        }
      } catch (e) {
        // No save dialog on this device: the text goes to the clipboard instead.
        await Clipboard.setData(ClipboardData(text: text));
        m.showSnackBar(
          SnackBar(content: Text(L('Dosya kaydedilemedi; metin panoya kopyalandı.', 'Could not save a file; the text was copied to the clipboard.'))),
        );
      }
    } else if (v == 'copy') {
      await Clipboard.setData(ClipboardData(text: widget.app.user.bookText(b.id)));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(L('Kitabın tüm metni panoya kopyalandı.', 'The whole book text was copied to the clipboard.'))));
      }
    } else if (v == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(L('Kitap silinsin mi?', 'Delete this book?')),
          content: Text(
            L('"${b.title}" kitaplıktan kaldırılacak. Kelime listen korunur.', '"${b.title}" will be removed from the library. Your word list is kept.'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(L('Vazgeç', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(L('Sil', 'Delete'))),
          ],
        ),
      );
      if (ok == true) {
        widget.app.stats.forgetBook(b.id);
        widget.app.user.deleteBook(b.id);
        setState(() {});
      }
    }
  }

  /// The book's cover picture, if it has one.
  File? _cover(Book b) => widget.app.user.coverFile(b.id);

  Future<void> _openFreeLibrary() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => FreeLibraryPage(app: widget.app)));
    setState(() {});
  }

  Future<void> _open(Book b) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReaderPage(app: widget.app, book: b),
      ),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final books = widget.app.user.books();
    final recent = recentBooks(widget.app);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final phone = width < 720;
    final pad = phone ? 20.0 : 32.0;
    final addButton = phone
        ? IconButton(
            key: const ValueKey('add-book'),
            icon: Icon(importing ? Icons.hourglass_top_rounded : Icons.add_rounded, size: 27, color: cs.onSurfaceVariant),
            tooltip: L('Kitap ekle', 'Add book'),
            onPressed: importing ? null : _import,
          )
        : GoldButton(
            key: const ValueKey('add-book'),
            label: importing ? L('Dönüştürülüyor…', 'Converting…') : L('Kitap ekle', 'Add book'),
            icon: Icons.add_rounded,
            height: 46,
            onPressed: importing ? null : _import,
          );
    final search = widget.onSearch == null ? null : _SearchField(onTap: widget.onSearch!);
    final current = recent.isEmpty ? null : _CurrentBookCard(book: recent.first, cover: _cover(recent.first), onTap: () => _open(recent.first), big: !phone);
    final today = _TodayCard(app: widget.app);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ValueListenableBuilder(
          valueListenable: widget.app.analyzer.status,
          builder: (context, progress, _) => CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(pad, phone ? 4 : 24, pad, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (phone) ...[
                        // The gold wordmark stays at the top of the home page.
                        SizedBox(
                          height: 52,
                          child: Row(children: [
                            const SizedBox(width: 48),
                            const Expanded(child: Center(child: Wordmark(height: 24))),
                            addButton,
                          ]),
                        ),
                        const Padding(padding: EdgeInsets.fromLTRB(40, 2, 40, 14), child: GoldRule()),
                        ?search,
                      ] else ...[
                        Row(
                          children: [
                            Expanded(child: Text(L('Kitaplığım', 'My library'), style: theme.textTheme.headlineMedium)),
                            if (search != null) ...[SizedBox(width: 320, child: search), const SizedBox(width: 14)],
                            addButton,
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          L('Okurken bilmediğin kelimeleri öğren.', 'Learn the words you don\'t know while you read.'),
                          style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                      SizedBox(height: phone ? 12 : 20),
                      if (!phone && current != null && width >= 1100)
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(flex: 5, child: current),
                              const SizedBox(width: 18),
                              Expanded(flex: 4, child: Align(alignment: Alignment.topCenter, child: today)),
                            ],
                          ),
                        )
                      else ...[
                        today,
                        if (current != null) ...[const SizedBox(height: 12), current],
                      ],
                      if (importStatus != null) ...[
                        const SizedBox(height: 14),
                        Panel(
                          children: [
                            Text(importStatus!, style: theme.textTheme.bodyMedium),
                            const SizedBox(height: 10),
                            const LinearProgressIndicator(),
                          ],
                        ),
                      ],
                      if (books.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _SectionTitle(L('Rafım', 'My shelf'), trailing: '${books.length}'),
                      ],
                    ],
                  ),
                ),
              ),
              if (books.isEmpty)
                // Below the summary card; scrolls when the window is short.
                SliverToBoxAdapter(
                  child: _EmptyLibrary(onAdd: importing ? null : _import, onFree: _openFreeLibrary),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(pad, 0, pad, phone ? 130 : 40),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: phone ? 200 : 210,
                      childAspectRatio: 0.56,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                    ),
                    delegate: SliverChildBuilderDelegate((c, i) {
                      final b = books[i];
                      return _BookCard(book: b, cover: _cover(b), status: progress[b.id], onTap: () => _open(b), onMenu: (v) => _onMenu(b, v));
                    }, childCount: books.length),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  final String? trailing;
  const _SectionTitle(this.text, {this.trailing});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 22, 2, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: t.textTheme.titleMedium?.copyWith(fontSize: 17, color: dark ? const Color(0xFFCDBB98) : t.colorScheme.onSurface)),
          ),
          if (trailing != null) Text(trailing!, style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.primary)),
        ],
      ),
    );
  }
}

double _progress(Book b) => b.chapterCount <= 1 ? 0.0 : b.lastChapter / (b.chapterCount - 1);

String _where(Book b) => b.chapterCount <= 1
    ? (b.lastPage > 0 ? L('Sayfa ${b.lastPage + 1}', 'Page ${b.lastPage + 1}') : L('Başlangıç', 'Start'))
    : L('Bölüm ${b.lastChapter + 1} / ${b.chapterCount}', 'Chapter ${b.lastChapter + 1} / ${b.chapterCount}');

/// Daily reading goal, in minutes (home page ring and the side menu).
const readingGoalMinutes = 25;

/// Today: minutes read against the goal as a ring, the streak, and a button
/// for the words due for review.
class _TodayCard extends StatelessWidget {
  final AppState app;
  const _TodayCard({required this.app});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final mins = (app.stats.readingSeconds(from: DateTime.now()) / 60).floor();
    final streak = app.stats.readingStreak();
    final due = app.review.dueCount();
    final left = readingGoalMinutes - mins;
    return _HomeCard(
      key: const ValueKey('today-card'),
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        SizedBox(
          width: 78,
          height: 78,
          child: Stack(alignment: Alignment.center, children: [
            Positioned.fill(
              child: CircularProgressIndicator(
                value: (mins / readingGoalMinutes).clamp(0.0, 1.0),
                strokeWidth: 8,
                strokeCap: StrokeCap.round,
                backgroundColor: cs.surfaceContainerHigh,
              ),
            ),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$mins', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.1)),
              Text(L('/ $readingGoalMinutes dk', '/ $readingGoalMinutes min'), style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant)),
            ]),
          ]),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(L('Bugün', 'Today'), style: TextStyle(fontFamily: readingFont, fontSize: 17, fontWeight: FontWeight.w600, color: cs.onSurface)),
              ),
              if (streak > 0) ...[
                Icon(Icons.local_fire_department_outlined, size: 16, color: cs.primary),
                const SizedBox(width: 3),
                Text(L('$streak gün', '$streak days'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.primary)),
              ],
            ]),
            const SizedBox(height: 2),
            Text(
              left > 0
                  ? L('$left dakika daha okursan hedef tamam.', 'Read $left more minutes to reach the goal.')
                  : L('Bugünkü hedef tamam.', 'Today\'s goal is done.'),
              style: TextStyle(fontSize: 13.5, height: 1.3, color: cs.onSurfaceVariant),
            ),
            if (due > 0) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                key: const ValueKey('today-review'),
                onPressed: () => startReview(context, app),
                icon: const Icon(Icons.replay_rounded, size: 17),
                label: Text(L('$due kelime tekrar', 'Review $due words')),
                style: FilledButton.styleFrom(
                  backgroundColor: learnColor(theme),
                  foregroundColor: onLearn(theme),
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  textStyle: theme.textTheme.labelLarge?.copyWith(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// The book read last, big: cover, where you are, and a button back into it.
class _CurrentBookCard extends StatelessWidget {
  final Book book;
  final File? cover;
  final VoidCallback onTap;
  final bool big;
  const _CurrentBookCard({required this.book, required this.cover, required this.onTap, this.big = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final pct = _progress(book);
    return _HomeCard(
      key: const ValueKey('current-book'),
      padding: const EdgeInsets.all(18),
      onTap: onTap,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        BookCover(title: book.title, format: book.format, width: big ? 120 : 96, image: cover),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(L('ŞU AN OKUDUĞUN', 'READING NOW'), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 1.6, color: cs.onSurfaceVariant)),
            const SizedBox(height: 6),
            Text(book.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: readingFont, fontSize: big ? 21 : 19, fontWeight: FontWeight.w600, height: 1.2, color: cs.onSurface)),
            const SizedBox(height: 4),
            Text('${_where(book)} · ${percent((pct * 100).round())}', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: pct, minHeight: 4, borderRadius: BorderRadius.circular(2), backgroundColor: cs.surfaceContainerHigh),
            const SizedBox(height: 14),
            FilledButton.icon(
              key: const ValueKey('current-book-open'),
              onPressed: onTap,
              icon: const Icon(Icons.auto_stories_outlined, size: 18),
              label: Text(L('Okumaya dön', 'Back to the book')),
              style: FilledButton.styleFrom(
                backgroundColor: dark ? Brand.goldLight : const Color(0xFF5C3D14),
                foregroundColor: dark ? const Color(0xFF21180A) : Colors.white,
                minimumSize: const Size(0, 42),
                textStyle: theme.textTheme.labelLarge?.copyWith(fontSize: 14.5, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// A plain home page card: surface colour, thin border, soft shadow by day.
class _HomeCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  const _HomeCard({super.key, required this.child, required this.padding, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final radius = BorderRadius.circular(22);
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: dark ? Brand.dSurface : const Color(0xFFFBF7EF),
          borderRadius: radius,
          border: Border.all(color: theme.colorScheme.outlineVariant),
          boxShadow: dark ? null : const [BoxShadow(color: Color(0x10785A28), blurRadius: 18, offset: Offset(0, 6))],
        ),
        child: InkWell(borderRadius: radius, onTap: onTap, child: Padding(padding: padding, child: child)),
      ),
    );
  }
}

/// Looks like a search field; a tap opens the dictionary.
class _SearchField extends StatelessWidget {
  final VoidCallback onTap;
  const _SearchField({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return Semantics(
      button: true,
      label: L('Sözlükte kelime ara', 'Search a word in the dictionary'),
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('home-search'),
          borderRadius: BorderRadius.circular(23),
          onTap: onTap,
          child: Ink(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: dark ? Brand.dSurfaceLow : const Color(0xFFFBF7EF),
              borderRadius: BorderRadius.circular(23),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Row(children: [
              Icon(Icons.search_rounded, size: 20, color: cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  L('Kelime ara · İngilizce ya da Türkçe', 'Search a word · English or Turkish'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14.5, color: cs.onSurfaceVariant),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A book in the grid: a big cover, then its title, author and progress.
class _BookCard extends StatelessWidget {
  final Book book;
  final File? cover;
  final String? status;
  final VoidCallback onTap;
  final ValueChanged<String> onMenu;
  const _BookCard({required this.book, required this.cover, required this.status, required this.onTap, required this.onMenu});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = book;
    final pct = _progress(b);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: LayoutBuilder(
                        builder: (_, c) => BookCover(title: b.title, format: b.format, width: c.maxWidth, height: c.maxHeight, image: cover),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Material(
                        color: Colors.white.withValues(alpha: 0.9),
                        shape: const CircleBorder(),
                        child: SizedBox(
                          width: 32,
                          height: 32,
                          child: PopupMenuButton<String>(
                            padding: EdgeInsets.zero,
                            iconSize: 18,
                            icon: const Icon(Icons.more_horiz_rounded, color: Color(0xFF6B5A3E)),
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
                                value: 'export',
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.save_alt_rounded),
                                  title: Text(L('Metni kaydet (.txt)', 'Save text (.txt)')),
                                  subtitle: Text(L('Kitabın uygulamadaki hali', 'The book as the app shows it')),
                                ),
                              ),
                              PopupMenuItem(
                                value: 'copy',
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.copy_all_rounded),
                                  title: Text(L('Metni kopyala', 'Copy text')),
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
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 9),
              Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
              Text(
                [if (b.author != null) b.author!, percent((pct * 100).round())].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              if (status != null)
                Text(
                  status!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  final VoidCallback? onAdd;
  final VoidCallback onFree;
  const _EmptyLibrary({required this.onAdd, required this.onFree});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 140),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
              L(
                'EPUB, PDF, TXT, DOCX, ODT, HTML, FB2, RTF veya Markdown dosyası ekle. Kitap uygulamanın kendi formatına çevrilir ve cihazında saklanır.',
                'Add an EPUB, PDF, TXT, DOCX, ODT, HTML, FB2, RTF or Markdown file. The book is converted to the app\'s own format and stored on your device.',
              ),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.5),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add_rounded), label: Text(L('Kitap seç', 'Choose a book'))),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const ValueKey('free-library'),
            onPressed: onFree,
            icon: const Icon(Icons.local_library_outlined),
            label: Text(L('Ücretsiz hikâye ve kitaplar', 'Free stories and books')),
          ),
        ],
      ),
    );
  }
}

/// Used by tests and the CLI flag to import without the file picker.
Future<int> importForTest(AppState app, String path) async {
  final ocr = await OcrEngine.best(ai: AiService.fromSettings(app.user));
  final ImportedBook b = await importFile(path, ocr: ocr, isWord: app.isWord);
  return app.user.insertBook(b);
}
