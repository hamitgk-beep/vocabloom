import 'dart:convert';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/user_db.dart';
import '../l10n.dart';
import 'expr_sheet.dart';
import 'panel.dart';
import 'theme.dart';
import 'word_sheet.dart';

/// The "Sözlük" tab: a dictionary of single words. Type an English word to
/// see matching words with their Turkish meaning, or a Turkish word to find
/// its English (accents optional: "kopek" finds dog). With nothing typed it
/// lists the words looked up before and a browsable word list (most common
/// words, or by first letter). Phrasal verbs, idioms and the other expression groups are
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

  /// The word list shown with nothing typed: null = most common words,
  /// otherwise words starting with this letter.
  String? letter;
  static const _page = 100;
  int shown = _page;
  List<String> _list = const [];
  String? _listKey;

  List<String> get _browse {
    final key = '${letter ?? ''}:$shown';
    if (_listKey != key) {
      _listKey = key;
      // One more than shown tells whether "Show more" has anything to add.
      _list = letter == null
          ? widget.app.dict.commonWords(limit: shown + 1)
          : widget.app.dict.searchWords(letter!, limit: shown + 1);
    }
    return _list;
  }

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
    // A Turkish word ("kitap") opens its best English match ("book").
    final dict = widget.app.dict;
    final en = dict.searchWords(t, limit: 1);
    if (en.isEmpty || en.first != t) {
      final tr = dict.searchTurkish(t, limit: 1);
      if (tr.isNotEmpty) {
        _open(tr.first.$1);
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
    final t = q.trim().toLowerCase();
    final en = typing ? app.dict.searchWords(q, limit: 40) : const <String>[];
    final trScored = typing ? app.dict.searchTurkishScored(q, limit: 40) : const <(String, String, int)>[];
    final tr = [for (final (w, m, _) in trScored) (w, m)];
    // The direction that fits the text best goes first: Turkish only when it
    // is a whole Turkish meaning ("ev" → home) and not an English word too.
    final enFirst = en.isNotEmpty && (en.first == t || trScored.isEmpty || trScored.first.$3 > 1);
    final browse = typing ? const <String>[] : _browse;
    final recent = typing ? const <String>[] : _recent;
    // Rows of the list below the search box: a section heading (String) or a
    // word with the meaning to show under it.
    final rows = <Object>[];
    void addEn() {
      if (en.isEmpty) return;
      rows.add(L('İngilizce → Türkçe', 'English → Turkish'));
      for (final w in en) {
        rows.add((w, null));
      }
    }

    void addTr() {
      if (tr.isEmpty) return;
      rows.add(L('Türkçe → İngilizce', 'Turkish → English'));
      rows.addAll(tr);
    }

    if (typing) {
      if (enFirst) {
        addEn();
        addTr();
      } else {
        addTr();
        addEn();
      }
    } else {
      for (final w in browse.take(shown)) {
        rows.add((w, null));
      }
    }
    final more = !typing && browse.length > shown;
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
                      hintText: L('İngilizce ya da Türkçe kelime ara', 'Search an English or Turkish word'),
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
                  if (typing && rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 18),
                      child: Text(
                        L('Bu kelimeyi bulamadık. Yazımını kontrol et ya da kelimenin başını yaz.',
                            'No word found. Check the spelling or type the start of the word.'),
                        style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.45),
                      ),
                    ),
                  if (!typing) ...[
                    if (recent.isNotEmpty) ...[
                      SectionLabel(L('Son baktıkların', 'Recently looked up')),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final w in recent) ActionChip(label: Text(w, style: enStyle(theme, theme.textTheme.bodyMedium)), onPressed: () => _open(w)),
                      ]),
                    ],
                    SectionLabel(letter == null ? L('En sık kullanılan kelimeler', 'Most common words') : L('$letter harfiyle başlayanlar', 'Words starting with $letter')),
                    SizedBox(
                      height: 40,
                      child: ListView(scrollDirection: Axis.horizontal, children: [
                        for (final l in [null, for (var c = 0; c < 26; c++) String.fromCharCode(65 + c)])
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(l ?? L('Sık kullanılanlar', 'Most common')),
                              selected: letter == l?.toLowerCase(),
                              showCheckmark: false,
                              onSelected: (_) => setState(() {
                                letter = l?.toLowerCase();
                                shown = _page;
                              }),
                            ),
                          ),
                      ]),
                    ),
                  ],
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              sliver: SliverList.builder(
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final r = rows[i];
                  if (r is String) return Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: SectionLabel(r));
                  final (w, m) = r as (String, String?);
                  final meaning = m ?? app.shortMeaning(w);
                  final st = app.user.statuses[w];
                  return Column(mainAxisSize: MainAxisSize.min, children: [
                    if (i > 0 && rows[i - 1] is! String) const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      title: Text(w, style: enStyle(theme, theme.textTheme.titleMedium).copyWith(fontWeight: FontWeight.w700)),
                      subtitle: meaning == null
                          ? null
                          : Text(meaning, maxLines: 2, overflow: TextOverflow.ellipsis, style: trStyle(theme, theme.textTheme.bodyMedium)),
                      trailing: st == null ? null : Icon(Icons.circle, size: 12, color: st == WordStatus.learning ? learningColor : learnedColor),
                      onTap: () => _open(w),
                    ),
                  ]);
                },
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                child: more
                    ? Center(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.expand_more_rounded),
                          label: Text(L('Daha fazla göster', 'Show more')),
                          onPressed: () => setState(() => shown += _page),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
