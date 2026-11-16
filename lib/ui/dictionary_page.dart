import 'dart:convert';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/user_db.dart';
import '../l10n.dart';
import 'expr_sheet.dart';
import 'panel.dart';
import 'theme.dart';
import 'word_sheet.dart';

/// The "Sözlük" tab: a dictionary of single words. Type to see matching
/// words with their Turkish meaning; with nothing typed it shows the words
/// looked up here before. Phrasal verbs, idioms and the other expression groups are
/// taught in the Grammar tab and highlighted from the reader's Filters.
class DictionaryPage extends StatefulWidget {
  final AppState app;
  const DictionaryPage({super.key, required this.app});

  @override
  State<DictionaryPage> createState() => _DictionaryPageState();
}

class _DictionaryPageState extends State<DictionaryPage> {
  final search = TextEditingController();
  String q = '';

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  /// Enter opens the word; a whole expression typed in still opens its panel.
  void _lookup(String text) {
    final t = text.trim().toLowerCase();
    if (t.isEmpty) return;
    if (t.contains(' ')) {
      final e = widget.app.dict.exprs.where((e) => e.phrase == t).firstOrNull;
      if (e != null) {
        showExprSheet(context, widget.app, e, null);
        return;
      }
    }
    _open(t);
  }

  static const _recentKey = 'dictionary_recent';

  /// Words opened from this page, newest first.
  List<String> get _recent {
    try {
      return (jsonDecode(widget.app.user.getSetting(_recentKey) ?? '[]') as List).cast<String>();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _open(String word) async {
    widget.app.user.setSetting(_recentKey, jsonEncode([word, ..._recent.where((w) => w != word)].take(20).toList()));
    await showWordSheet(context, widget.app, word, lemma: word);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final typing = q.trim().isNotEmpty;
    final words = typing ? app.dict.searchWords(q, limit: 60) : const <String>[];
    final recent = typing ? const <String>[] : _recent;
    return Scaffold(
      appBar: AppBar(toolbarHeight: 68, title: Text(L('Sözlük', 'Dictionary'), style: theme.textTheme.headlineSmall)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: CustomScrollView(slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TextField(
                    controller: search,
                    textInputAction: TextInputAction.search,
                    autocorrect: false,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: L('Kelime ara', 'Search a word'),
                      suffixIcon: q.isEmpty
                          ? null
                          : IconButton(
                              tooltip: L('Temizle', 'Clear'),
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => setState(() {
                                search.clear();
                                q = '';
                              }),
                            ),
                    ),
                    onChanged: (v) => setState(() => q = v),
                    onSubmitted: _lookup,
                  ),
                  if (!typing)
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(Icons.school_outlined, size: 20, color: cs.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            L(
                              'Phrasal verb\'ler, deyimler, bağlaçlar ve diğer kalıplar artık Gramer bölümünde, konu anlatımlarıyla birlikte. Okurken onları Filtreler\'den kitapta renkli işaretleyebilirsin.',
                              'Phrasal verbs, idioms, conjunctions and the other expression groups are now in Grammar, with a lesson each. While reading, turn them on in Filters to highlight them in the book.',
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                          ),
                        ),
                      ]),
                    ),
                  if (typing)
                    SectionLabel(words.isEmpty ? L('Bu harflerle başlayan kelime yok', 'No word starts with these letters') : L('Kelimeler', 'Words'))
                  else if (recent.isNotEmpty) ...[
                    SectionLabel(L('Son baktıkların', 'Recently looked up')),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final w in recent) ActionChip(label: Text(w, style: enStyle(theme, theme.textTheme.bodyMedium)), onPressed: () => _open(w)),
                    ]),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(top: 18),
                      child: Text(
                        L('Bir kelime yazmaya başla; yazdıkça eşleşen kelimeler Türkçe anlamlarıyla listelenir. Dokunduğunda okuyucudaki kelime paneli açılır.',
                            'Start typing a word; matching words appear with their Turkish meaning. Tap one to open the same word panel as in the reader.'),
                        style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.45),
                      ),
                    ),
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
              sliver: SliverList.separated(
                itemCount: words.length,
                separatorBuilder: (_, _) => const Divider(height: 1, indent: 16, endIndent: 16),
                itemBuilder: (context, i) {
                  final w = words[i];
                  final meaning = app.shortMeaning(w);
                  final st = app.user.statuses[w];
                  return ListTile(
                    title: Text(w, style: enStyle(theme, theme.textTheme.titleMedium).copyWith(fontWeight: FontWeight.w700)),
                    subtitle: meaning == null
                        ? null
                        : Text(meaning, maxLines: 2, overflow: TextOverflow.ellipsis, style: trStyle(theme, theme.textTheme.bodyMedium)),
                    trailing: st == null ? null : Icon(Icons.circle, size: 12, color: st == WordStatus.learning ? learningColor : learnedColor),
                    onTap: () => _open(w),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
