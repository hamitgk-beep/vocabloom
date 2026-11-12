
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/user_db.dart';
import '../import/importers.dart';
import '../import/ocr.dart';
import '../online/ai_service.dart';
import 'reader_page.dart';

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
            '"${book.title}" eklendi: ${book.chapters.length} bölüm, ~$words kelime.',
          ),
        ),
      );
      widget.app.analyzer.tick(onlyBook: id);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('İçe aktarılamadı: $e'),
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

  @override
  Widget build(BuildContext context) {
    final books = widget.app.user.books();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('VocaBloom · Kitaplığım')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: importing ? null : _import,
        icon: importing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: Text(importing ? 'Dönüştürülüyor…' : 'Kitap ekle'),
      ),
      body: Column(
        children: [
          if (importStatus != null) ...[
            const LinearProgressIndicator(),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(importStatus!),
            ),
          ],
          Expanded(
            child: books.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.menu_book_outlined,
                            size: 72,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Henüz kitap yok',
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'EPUB, PDF, TXT, DOCX, ODT, HTML, FB2, RTF veya Markdown dosyası ekle. '
                            'Kitap uygulamanın kendi formatına çevrilir ve cihazında saklanır.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : ValueListenableBuilder(
                    valueListenable: widget.app.analyzer.status,
                    builder: (context, progress, _) => ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                      itemCount: books.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 4),
                      itemBuilder: (c, i) {
                        final b = books[i];
                        final pct = b.chapterCount <= 1
                            ? 0.0
                            : b.lastChapter / (b.chapterCount - 1);
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Text(
                                b.format.toUpperCase().substring(
                                  0,
                                  b.format.length.clamp(0, 3),
                                ),
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                            title: Text(
                              b.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  [
                                    if (b.author != null) b.author!,
                                    '${b.chapterCount} bölüm',
                                  ].join(' · '),
                                ),
                                const SizedBox(height: 4),
                                LinearProgressIndicator(value: pct),
                                if (progress[b.id] != null)
                                  Text(
                                    progress[b.id]!,
                                    style: theme.textTheme.bodySmall,
                                  ),
                              ],
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) async {
                                if (v == 'analyze') {
                                  final svc = AiService.fromSettings(
                                    widget.app.user,
                                  );
                                  final m = ScaffoldMessenger.of(context);
                                  if (svc == null) {
                                    m.showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Önce Ayarlar\'dan bir yapay zekâ servisi bağlayın.',
                                        ),
                                      ),
                                    );
                                  } else if (!await svc.reachable()) {
                                    m.showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'İnternet yok. Bağlantı gelince analiz kendiliğinden başlar.',
                                        ),
                                      ),
                                    );
                                  } else {
                                    widget.app.analyzer.tick(
                                      force: true,
                                      onlyBook: b.id,
                                    );
                                  }
                                } else if (v == 'delete') {
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (c) => AlertDialog(
                                      title: const Text('Kitap silinsin mi?'),
                                      content: Text(
                                        '"${b.title}" kitaplıktan kaldırılacak. Kelime listen korunur.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(c, false),
                                          child: const Text('Vazgeç'),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(c, true),
                                          child: const Text('Sil'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (ok == true) {
                                    widget.app.user.deleteBook(b.id);
                                    setState(() {});
                                  }
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'analyze',
                                  child: Text(
                                    'Çevrimiçi analiz et (çeviri + özet)',
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Sil'),
                                ),
                              ],
                            ),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ReaderPage(app: widget.app, book: b),
                                ),
                              );
                              setState(() {});
                            },
                          ),
                        );
                      },
                    ),
                  ),
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
