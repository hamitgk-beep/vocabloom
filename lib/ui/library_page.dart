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
  const LibraryPage({super.key, required this.app, this.onTab});

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
      final id = widget.app.user.insertBook(book);
      final words = book.chapters.fold<int>(0, (s, c) => s + c.paragraphs.fold<int>(0, (s2, p) => s2 + p.$2.split(' ').length));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            L(
              '"${book.title}" eklendi: ${book.chapters.length} bölüm, ~$words kelime.',
              '"${book.title}" added: ${book.chapters.length} chapters, ~$words words.',
            ),
          ),
        ),
      );
      widget.app.analyzer.tick(onlyBook: id);
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
    final st = widget.app.user.statuses.values;
    final learning = st.where((s) => s == WordStatus.learning).length;
    final learned = st.where((s) => s == WordStatus.learned).length;
    final width = MediaQuery.sizeOf(context).width;
    final phone = width < 720;
    final pad = phone ? 20.0 : 32.0;
    final addButton = phone
        ? RoundIconButton(
            key: const ValueKey('add-book'),
            icon: importing ? Icons.hourglass_top_rounded : Icons.add_rounded,
            gold: true,
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
    final hero = _HeroCard(app: widget.app, books: books.length, learning: learning, learned: learned, wide: !phone);
    // Up to five books to pick up again: the ones read last, or simply the newest.
    final cont = recent.where((b) => _progress(b) > 0 || b.lastPage > 0).take(5).toList();
    if (cont.isEmpty && recent.isNotEmpty) cont.add(recent.first);
    final continueList = cont.isEmpty
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionTitle(L('Okumaya devam et', 'Continue reading')),
              if (phone)
                SizedBox(
                  height: 178,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    itemCount: cont.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (_, i) => _ContinueCard(book: cont[i], cover: _cover(cont[i]), onTap: () => _open(cont[i])),
                  ),
                )
              else
                for (final b in cont.take(2))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ContinueRow(book: b, cover: _cover(b), onTap: () => _open(b)),
                  ),
            ],
          );
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ValueListenableBuilder(
          valueListenable: widget.app.analyzer.status,
          builder: (context, progress, _) => CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(pad, phone ? 12 : 24, pad, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (phone)
                        Row(
                          children: [
                            const BrandMark(size: 36),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'VocaBloom',
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.fade,
                                style: theme.textTheme.titleLarge?.copyWith(fontFamily: readingFont, fontWeight: FontWeight.w600, fontSize: 21),
                              ),
                            ),
                            if (widget.onTab != null) ...[
                              RoundIconButton(
                                key: const ValueKey('nav_4'),
                                size: 38,
                                icon: Icons.explore_rounded,
                                tooltip: L('Ücretsiz kütüphane', 'Free library'),
                                onPressed: () => widget.onTab!(4),
                              ),
                              const SizedBox(width: 6),
                              RoundIconButton(
                                key: const ValueKey('nav_5'),
                                size: 38,
                                icon: Icons.insights_rounded,
                                tooltip: L('İstatistiklerim', 'My stats'),
                                onPressed: () => widget.onTab!(5),
                              ),
                              const SizedBox(width: 6),
                              RoundIconButton(
                                key: const ValueKey('nav_6'),
                                size: 38,
                                icon: Icons.tune_rounded,
                                tooltip: L('Ayarlar', 'Settings'),
                                onPressed: () => widget.onTab!(6),
                              ),
                              const SizedBox(width: 8),
                            ],
                            addButton,
                          ],
                        )
                      else
                        Row(
                          children: [
                            Expanded(child: Text(L('Kitaplığım', 'My library'), style: theme.textTheme.headlineMedium)),
                            addButton,
                          ],
                        ),
                      const SizedBox(height: 4),
                      Text(
                        L('Okurken bilmediğin kelimeleri öğren.', 'Learn the words you don\'t know while you read.'),
                        style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 16),
                      if (!phone && continueList != null && width >= 1100)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 5, child: hero),
                            const SizedBox(width: 24),
                            Expanded(
                              flex: 4,
                              child: Transform.translate(offset: const Offset(0, -14), child: continueList),
                            ),
                          ],
                        )
                      else ...[
                        hero,
                        if (continueList != null) ...[const SizedBox(height: 8), continueList],
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
                        _SectionTitle(L('Tüm kitaplar', 'All books'), trailing: '${books.length}'),
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

/// The cream summary card at the top: reading time, streak and word counts,
/// with a drawn open book.
class _HeroCard extends StatelessWidget {
  final AppState app;
  final int books, learning, learned;
  final bool wide;
  const _HeroCard({required this.app, required this.books, required this.learning, required this.learned, required this.wide});

  static String _time(int secs) {
    final m = (secs / 60).round();
    if (m < 60) return L('$m dk', '$m min');
    return L('${m ~/ 60} sa ${m % 60} dk', '${m ~/ 60} h ${m % 60} min');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    const ink = Color(0xFF231C12);
    final muted = dark ? const Color(0xFF6E6453) : const Color(0xFF7D6E55);
    final line = dark ? Colors.black.withValues(alpha: 0.09) : const Color(0x1F503714);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final week = app.stats.readingByDay(7);
    final todaySecs = week.last.$2;
    final weekSecs = week.fold<int>(0, (a, d) => a + d.$2);
    final streak = app.stats.readingStreak();
    final title = weekSecs == 0
        ? L('Okumaya başla', 'Start reading')
        : streak >= 3
        ? L('Harika gidiyorsun!', 'You\'re doing great!')
        : L('Güzel ilerliyorsun', 'Nice progress');
    Widget stat(String value, String label, {Key? key}) => Expanded(
      key: key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: t.textTheme.titleMedium?.copyWith(color: ink, fontWeight: FontWeight.w700, fontSize: 18),
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.textTheme.labelSmall?.copyWith(color: muted, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
    Widget sep() => Container(width: 1, height: 34, margin: const EdgeInsets.symmetric(horizontal: 10), color: line);
    final maxDay = week.fold<int>(1, (a, d) => d.$2 > a ? d.$2 : a);
    return Container(
      decoration: BoxDecoration(
        gradient: dark ? Brand.heroDark : Brand.heroLight,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [BoxShadow(color: dark ? Colors.black.withValues(alpha: 0.35) : const Color(0x1A785A28), blurRadius: 24, offset: const Offset(0, 6))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: wide ? 18 : -4,
            top: wide ? 8 : 2,
            child: CustomPaint(size: wide ? const Size(210, 158) : const Size(112, 84), painter: _OpenBookPainter()),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(wide ? 26 : 18, wide ? 22 : 16, wide ? 26 : 18, wide ? 20 : 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(L('Bu hafta', 'This week'), style: t.textTheme.bodySmall?.copyWith(color: muted)),
                const SizedBox(height: 2),
                Padding(
                  padding: EdgeInsets.only(right: wide ? 220 : 96),
                  child: Text(
                    title,
                    style: TextStyle(fontFamily: readingFont, fontWeight: FontWeight.w700, fontSize: wide ? 30 : 22, height: 1.15, color: ink),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  key: const ValueKey('stat-books'),
                  L('$books kitap · $learning öğreneceğim · $learned öğrendim', '$books books · $learning to learn · $learned learned'),
                  style: t.textTheme.bodySmall?.copyWith(color: muted, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 14),
                Container(
                  height: 1,
                  color: line,
                  constraints: BoxConstraints(maxWidth: wide ? 440 : double.infinity),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: wide ? 440 : double.infinity),
                  child: IntrinsicHeight(
                    child: Row(
                      children: [
                        stat(_time(todaySecs), L('Bugün', 'Today')),
                        sep(),
                        stat(_time(weekSecs), L('Bu hafta', 'This week')),
                        sep(),
                        stat(L('$streak gün', '$streak days'), L('Seri', 'Streak')),
                      ],
                    ),
                  ),
                ),
                if (wide) ...[
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 78,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final (i, d) in week.indexed)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 5),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Container(
                                    height: 8 + 44 * d.$2 / maxDay,
                                    decoration: BoxDecoration(
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(8), bottom: Radius.circular(4)),
                                      color: i == week.length - 1 ? null : line,
                                      gradient: i == week.length - 1 ? Brand.goldGradient : null,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _dayName(d.$1, today),
                                    style: t.textTheme.labelSmall?.copyWith(color: muted, fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _dayName(DateTime d, DateTime today) {
    const tr = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
    const en = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return L(tr[d.weekday - 1], en[d.weekday - 1]);
  }
}

/// An open book with a gold ribbon, drawn for the summary card.
class _OpenBookPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 200;
    canvas.save();
    canvas.scale(s);
    canvas.translate(100, 80);
    canvas.rotate(-0.17);
    canvas.translate(-100, -80);
    Path page(bool left) {
      final x = left ? 24.0 : 176.0, q = left ? 62.0 : 138.0;
      return Path()
        ..moveTo(x, 44)
        ..quadraticBezierTo(q, 26, 100, 46)
        ..lineTo(100, 124)
        ..quadraticBezierTo(q, 104, x, 122)
        ..close();
    }

    final coverPath = Path()
      ..moveTo(18, 50)
      ..quadraticBezierTo(60, 30, 100, 52)
      ..quadraticBezierTo(140, 30, 184, 50)
      ..lineTo(184, 128)
      ..quadraticBezierTo(140, 108, 100, 130)
      ..quadraticBezierTo(60, 108, 18, 128)
      ..close();
    canvas.drawShadow(coverPath, Colors.black, 6, false);
    canvas.drawPath(
      coverPath,
      Paint()..shader = const LinearGradient(colors: [Color(0xFF7A4A22), Color(0xFF4E2D12)]).createShader(const Rect.fromLTWH(18, 30, 166, 100)),
    );
    final paper = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFF9EC), Color(0xFFEADFC6)],
      ).createShader(const Rect.fromLTWH(0, 26, 200, 100));
    final edge = Paint()
      ..color = const Color(0xFFD9CBAA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (final l in [true, false]) {
      canvas.drawPath(page(l), paper);
      canvas.drawPath(page(l), edge);
    }
    final lines = Paint()
      ..color = const Color(0xCCCBBB98)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var i = 0; i < 4; i++) {
      final y = 56.0 + i * 10;
      canvas.drawPath(
        Path()
          ..moveTo(36, y)
          ..quadraticBezierTo(64, y - 12, i == 3 ? 84 : 90, y + 2),
        lines,
      );
      if (i < 3)
        canvas.drawPath(
          Path()
            ..moveTo(110, y + 2)
            ..quadraticBezierTo(136, y - 12, 164, y),
          lines,
        );
    }
    canvas.drawPath(
      Path()
        ..moveTo(120, 46)
        ..lineTo(120, 86)
        ..lineTo(126, 80)
        ..lineTo(132, 86)
        ..lineTo(132, 42)
        ..close(),
      Paint()..color = const Color(0xFFB8863A),
    );
    canvas.drawLine(
      const Offset(100, 46),
      const Offset(100, 124),
      Paint()
        ..color = const Color(0xFFBFAE88)
        ..strokeWidth = 1.4,
    );
    canvas.restore();
    final dot = Paint()..color = const Color(0xFFD6B16C);
    canvas.drawCircle(Offset(40 * s, 18 * s), 2.5 * s, dot);
    canvas.drawCircle(Offset(176 * s, 14 * s), 1.8 * s, dot);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

double _progress(Book b) => b.chapterCount <= 1 ? 0.0 : b.lastChapter / (b.chapterCount - 1);

String _where(Book b) => b.chapterCount <= 1
    ? (b.lastPage > 0 ? L('Sayfa ${b.lastPage + 1}', 'Page ${b.lastPage + 1}') : L('Başlangıç', 'Start'))
    : L('Bölüm ${b.lastChapter + 1} / ${b.chapterCount}', 'Chapter ${b.lastChapter + 1} / ${b.chapterCount}');

/// Phone: a card in the sideways "Continue reading" row.
class _ContinueCard extends StatelessWidget {
  final Book book;
  final File? cover;
  final VoidCallback onTap;
  const _ContinueCard({required this.book, required this.cover, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final pct = _progress(book);
    return SizedBox(
      width: 236,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: cs.outlineVariant),
            color: dark ? null : cs.surface,
            gradient: dark ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF2A221A), Color(0xFF33291C)]) : null,
            boxShadow: dark ? null : [const BoxShadow(color: Color(0x14785A28), blurRadius: 18, offset: Offset(0, 6))],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BookCover(title: book.title, format: book.format, width: 46, image: cover),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontSize: 15)),
                            const SizedBox(height: 3),
                            Text(_where(book), maxLines: 1, style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  LinearProgressIndicator(value: pct, minHeight: 4),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: onTap,
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 14)),
                      child: Row(
                        children: [
                          Expanded(child: Text(L('Devam et', 'Continue'))),
                          const Icon(Icons.chevron_right_rounded, size: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wide screens: one row per book next to the summary card.
class _ContinueRow extends StatelessWidget {
  final Book book;
  final File? cover;
  final VoidCallback onTap;
  const _ContinueRow({required this.book, required this.cover, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = _progress(book);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              BookCover(title: book.title, format: book.format, width: 54, image: cover),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontSize: 15)),
                    const SizedBox(height: 3),
                    Text(
                      '${_where(book)} · ${percent((pct * 100).round())}',
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: pct, minHeight: 4),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              GoldButton(label: L('Devam et', 'Continue'), icon: Icons.chevron_right_rounded, trailingIcon: true, height: 40, onPressed: onTap),
            ],
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
