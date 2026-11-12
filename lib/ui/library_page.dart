import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/user_db.dart';
import '../import/importers.dart';
import '../online/claude_service.dart';
import 'reader_page.dart';

/// Progress of running online analyses, by book id.
final analysisProgress = ValueNotifier<Map<int, String>>({});

Future<void> runAnalysis(AppState app, int bookId, {ScaffoldMessengerState? messenger}) async {
  final svc = ClaudeService.fromSettings(app.user);
  if (svc == null || analysisProgress.value.containsKey(bookId)) return;
  void set(String? s) {
    final m = Map<int, String>.from(analysisProgress.value);
    s == null ? m.remove(bookId) : m[bookId] = s;
    analysisProgress.value = m;
  }

  set('Çevrimiçi analiz başlıyor…');
  try {
    await analyzeBook(svc, app.user, bookId, onProgress: (d, t) => set('Çevrimiçi analiz: $d/$t paragraf'));
    messenger?.showSnackBar(const SnackBar(content: Text('Çevrimiçi analiz tamamlandı; artık internetsiz de görünür.')));
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text('Çevrimiçi analiz durdu: $e')));
  } finally {
    set(null);
  }
}

class LibraryPage extends StatefulWidget {
  final AppState app;
  const LibraryPage({super.key, required this.app});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  bool importing = false;

  Future<bool> _online() async {
    try {
      final r = await InternetAddress.lookup('api.anthropic.com').timeout(const Duration(seconds: 3));
      return r.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _import() async {
    final res = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: supportedExtensions);
    final path = res.isEmpty ? null : res.first.path;
    if (path == null) return;
    await importPath(path);
  }

  Future<void> importPath(String path) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => importing = true);
    try {
      final book = await importFile(path);
      final id = widget.app.user.insertBook(book);
      final words = book.chapters.fold<int>(0, (s, c) => s + c.paragraphs.fold<int>(0, (s2, p) => s2 + p.$2.split(' ').length));
      messenger.showSnackBar(SnackBar(content: Text('"${book.title}" eklendi: ${book.chapters.length} bölüm, ~$words kelime.')));
      if (widget.app.user.getSetting('auto_analyze') == '1' && ClaudeService.fromSettings(widget.app.user) != null && await _online()) {
        runAnalysis(widget.app, id, messenger: messenger);
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('İçe aktarılamadı: $e'), duration: const Duration(seconds: 8)));
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final books = widget.app.user.books();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Kitaplığım')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: importing ? null : _import,
        icon: importing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add),
        label: Text(importing ? 'Dönüştürülüyor…' : 'Kitap ekle'),
      ),
      body: books.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.menu_book_outlined, size: 72, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text('Henüz kitap yok', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text('EPUB, PDF, TXT, DOCX, ODT, HTML, FB2, RTF veya Markdown dosyası ekle. '
                      'Kitap uygulamanın kendi formatına çevrilir ve cihazında saklanır.',
                      textAlign: TextAlign.center),
                ]),
              ),
            )
          : ValueListenableBuilder(
              valueListenable: analysisProgress,
              builder: (context, progress, _) => ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                itemCount: books.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (c, i) {
                  final b = books[i];
                  final pct = b.chapterCount <= 1 ? 0.0 : b.lastChapter / (b.chapterCount - 1);
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(child: Text(b.format.toUpperCase().substring(0, b.format.length.clamp(0, 3)), style: const TextStyle(fontSize: 11))),
                      title: Text(b.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text([if (b.author != null) b.author!, '${b.chapterCount} bölüm'].join(' · ')),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(value: pct),
                        if (progress[b.id] != null) Text(progress[b.id]!, style: theme.textTheme.bodySmall),
                      ]),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'analyze') {
                            if (ClaudeService.fromSettings(widget.app.user) == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Önce Ayarlar\'dan çevrimiçi analiz için API anahtarı girin.')));
                            } else {
                              runAnalysis(widget.app, b.id, messenger: ScaffoldMessenger.of(context));
                            }
                          } else if (v == 'delete') {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('Kitap silinsin mi?'),
                                content: Text('"${b.title}" kitaplıktan kaldırılacak. Kelime listen korunur.'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
                                  FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sil')),
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
                          PopupMenuItem(value: 'analyze', child: Text('Çevrimiçi analiz et (çeviri + özet)')),
                          PopupMenuItem(value: 'delete', child: Text('Sil')),
                        ],
                      ),
                      onTap: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => ReaderPage(app: widget.app, book: b)));
                        setState(() {});
                      },
                    ),
                  );
                },
              ),
            ),
    );
  }
}

/// Used by tests and the CLI flag to import without the file picker.
Future<int> importForTest(AppState app, String path) async {
  final ImportedBook b = await importFile(path);
  return app.user.insertBook(b);
}
