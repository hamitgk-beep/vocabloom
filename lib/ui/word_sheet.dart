import 'dart:convert';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/dict_db.dart';
import '../data/user_db.dart';
import '../nlp/text.dart';
import '../nlp/word_family.dart';
import '../online/ai_service.dart';
import 'expr_sheet.dart';
import 'panel.dart';
import 'sense_cards.dart';
import '../l10n.dart';
import 'paragraph_view.dart';

/// Context in which a word was tapped (null when opened from a list).
class WordContext {
  final String sentence;
  final List<Token> sentenceTokens;
  final int indexInSentence;
  final List<Match> matches; // expressions covering the token
  final List<String>? sentenceTr;
  final int? bookId;
  final String? bookTitle;
  WordContext(this.sentence, this.sentenceTokens, this.indexInSentence, this.matches, this.sentenceTr, this.bookId, this.bookTitle);
}

/// Builds the context for token [ti] of paragraph [para].
WordContext buildContext(AppState app, Para para, ParaAnalysis a, int ti, {int? bookId, String? bookTitle}) {
  final t = a.tokens[ti];
  final ranges = sentenceRanges(para.text);
  var sIdx = 0;
  for (var i = 0; i < ranges.length; i++) {
    if (t.start >= ranges[i].$1 && t.start < ranges[i].$2) sIdx = i;
  }
  final r = ranges[sIdx];
  final sentTokens = a.tokens.where((x) => x.start >= r.$1 && x.end <= r.$2).toList();
  final idx = sentTokens.indexWhere((x) => x.start == t.start);
  final matches = a.matches.where((m) => m.tokens.contains(ti)).toList();
  final tr = app.user.paraTranslation(para.id);
  return WordContext(para.text.substring(r.$1, r.$2).trim(), sentTokens, idx < 0 ? 0 : idx, matches,
      tr != null && sIdx < tr.length ? [tr[sIdx]] : null, bookId, bookTitle);
}

Future<void> showWordSheet(BuildContext context, AppState app, String surface, {WordContext? ctx, String? lemma}) {
  return showPanel(context, (c, sc) => WordPanel(app: app, surface: surface, ctx: ctx, lemma: lemma, scroll: sc));
}

class WordPanel extends StatefulWidget {
  final AppState app;
  final String surface;
  final String? lemma;
  final WordContext? ctx;
  final ScrollController? scroll;
  const WordPanel({super.key, required this.app, required this.surface, this.ctx, this.lemma, this.scroll});

  @override
  State<WordPanel> createState() => _WordPanelState();
}

class _WordPanelState extends State<WordPanel> {
  late String lemma;
  late WordInfo info;
  WordInfo? surfaceInfo;
  Sense? best;
  List<String> bookExamples = [];
  int tab = 0; // 0 = meaning, 1 = word family

  @override
  void initState() {
    super.initState();
    final app = widget.app;
    final lower = widget.surface.toLowerCase().replaceAll('’', "'");
    final cands = app.dict.lemmatizer.lemmas(lower);
    lemma = widget.lemma ?? cands.first;
    info = app.dict.lookup(lemma);
    if (info.isEmpty) {
      for (final c in cands) {
        final i = app.dict.lookup(c);
        if (!i.isEmpty) {
          lemma = c;
          info = i;
          break;
        }
      }
    }
    if (lower != lemma && cands.contains(lower)) {
      final si = app.dict.lookup(lower);
      if (!si.isEmpty) surfaceInfo = si;
    }
    final ctx = widget.ctx;
    if (ctx != null) best = app.dict.bestSense(info, ctx.sentenceTokens, ctx.indexInSentence);
    if (ctx?.bookId != null) {
      final forms = <String>{lemma, '${lemma}s', '${lemma}es', '${lemma}ed', '${lemma}d', '${lemma}ing', lower};
      if (lemma.endsWith('e')) forms.add('${lemma.substring(0, lemma.length - 1)}ing');
      for (final r in app.dict.db.select('SELECT form FROM exc WHERE lemma=?', [lemma])) {
        forms.add(r['form'] as String);
      }
      bookExamples = app.user.findSentences(ctx!.bookId!, forms, exclude: ctx.sentence);
    }
  }

  /// Main Turkish meaning: the sense used in this sentence, otherwise the
  /// dictionary's first meaning ("unfortunate" -> "talihsiz, bahtsız").
  String? get _trMain {
    if (best != null && best!.tr.isNotEmpty) return best!.tr.take(3).join(', ');
    final bestPos = best?.pos;
    if (info.trFreeDict.isNotEmpty) {
      // FreeDict lists the most common meaning first; skip "... kimse" style
      // noun readings when the sentence uses the word as an adjective.
      final list = info.trFreeDict;
      final pick = bestPos == 'a' || bestPos == 's'
          ? list.firstWhere((t) => !t.contains('kimse') && !t.contains('kişi'), orElse: () => list.first)
          : list.first;
      return pick.split(RegExp(r'[,;]')).map((x) => x.trim()).where((x) => x.isNotEmpty).take(3).join(', ');
    }
    return _selfExprTr;
  }

  /// Turkish of a matched single-word expression that is this word itself
  /// (conjunctions like "though", discourse markers like "however").
  String? get _selfExprTr {
    for (final m in widget.ctx?.matches ?? const []) {
      if (m.expr.phrase == lemma && m.expr.trShown != null) return m.expr.trShown;
    }
    return null;
  }

  String? get _meaning => _trMain ?? best?.gloss;

  void _set(String key, WordStatus st) {
    widget.app.setWord(key, st,
        context: widget.ctx?.sentence, book: widget.ctx?.bookTitle, meaning: key == lemma ? _meaning : null);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final theme = Theme.of(context);
    final ctx = widget.ctx;
    final st = app.user.statuses[lemma] ?? WordStatus.none;
    final tr = app.showTr, en = app.showEn;

    final children = <Widget>[
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Flexible(child: Text(lemma, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700))),
        if (widget.surface.toLowerCase() != lemma)
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 4),
            child: Text('(${widget.surface})', style: theme.textTheme.titleMedium?.copyWith(color: theme.hintColor)),
          ),
        if (best != null)
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 6),
            child: Text(posNames[best!.pos] ?? '', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
          ),
      ]),
      if (en && best != null && ctx == null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(best!.gloss, style: enStyle(theme, theme.textTheme.titleMedium))),
      if (tr && _trMain != null)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(_trMain!, style: trStyle(theme, theme.textTheme.titleLarge)),
        ),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        StatusButtons(status: st, onChanged: (s) => _set(lemma, s)),
        const SizedBox(width: 8),
        LangToggles(app: app, onChanged: () => setState(() {})),
      ]),
      const SizedBox(height: 12),
      SegmentedButton<int>(
        segments: [
          ButtonSegment(value: 0, label: Text(L('Anlam', 'Meaning')), icon: Icon(Icons.translate)),
          ButtonSegment(value: 1, label: Text('Word Family'), icon: Icon(Icons.account_tree_outlined)),
        ],
        selected: {tab},
        showSelectedIcon: false,
        onSelectionChanged: (s) => setState(() => tab = s.first),
      ),
    ];
    if (tab == 1) {
      children.add(WordFamilyView(app: app, lemma: lemma, key: ValueKey(lemma)));
      return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: children);
    }

    // ---------------- in this sentence
    if (ctx != null) {
      children.add(_Section(L('Bu cümlede', 'In this sentence'), [
        SentenceText(ctx.sentence, widget.surface),
        if (ctx.sentenceTr != null && tr) ...[
          const SizedBox(height: 6),
          Text(ctx.sentenceTr!.first, style: trStyle(theme, const TextStyle(fontStyle: FontStyle.italic), false)),
        ],
        for (final m in ctx.matches) ExprCard(app: app, expr: m.expr, ctx: ctx, onChanged: () => setState(() {})),
        if (best != null && (en || (tr && _trMain != null && _trMain != _selfExprTr))) ...[
          const SizedBox(height: 8),
          Text(ctx.matches.any((m) => m.expr.phrase.contains(' ')) ? L('Kelimenin tek başına anlamı:', 'Meaning of the word on its own:') : L('Bu cümledeki anlamı:', 'Meaning in this sentence:'),
              style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          if (en) Text(best!.gloss, style: enStyle(theme, theme.textTheme.bodyLarge)),
          if (tr && _trMain != null) Text(_trMain!, style: trStyle(theme, theme.textTheme.titleMedium)),
          for (var k = 0; k < best!.examples.length && k < 2; k++)
            if (en || (tr && k < best!.examplesTr.length))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('• ${best!.examples[k]}', style: enStyle(theme, const TextStyle(fontStyle: FontStyle.italic), false)),
                  if (tr && k < best!.examplesTr.length)
                    Padding(padding: const EdgeInsets.only(left: 12), child: Text(best!.examplesTr[k], style: trStyle(theme, null, false))),
                ]),
              ),
        ],
      ]));
    }

    // ---------------- teacher-style explanation (built-in library)
    final wd = app.dict.wordDetail(lemma);
    List<ExprSense>? wdSenses;
    if (wd != null) {
      try {
        wdSenses = [for (final x in jsonDecode(wd.$2) as List) ExprSense.fromJson((x as Map).cast<String, dynamic>())];
      } catch (_) {}
    }
    if (wdSenses != null && wdSenses.isNotEmpty) {
      const posEn = {'v': 'verb', 'n': 'noun', 'a': 'adjective', 's': 'adjective', 'r': 'adverb'};
      children.add(_Section(L('Anlamları ve kullanımı', 'Meanings and usage'), [
        SenseCards(senses: wdSenses, en: en, tr: tr, color: theme.colorScheme.primary, highlightPos: ctx == null ? null : posEn[best?.pos]),
        Text(L('Kaynak: dahili sözlük', 'Source: built-in dictionary'), style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
      ]));
    }

    // ---------------- Turkish meanings
    if (tr && info.trFreeDict.isNotEmpty) {
      children.add(_Section(L('Türkçe karşılıklar', 'Turkish equivalents'), [
        for (var i = 0; i < info.trFreeDict.length && i < 12; i++)
          Padding(padding: const EdgeInsets.only(bottom: 3), child: Text('${i + 1}. ${info.trFreeDict[i]}', style: trStyle(theme))),
      ]));
    }
    if (surfaceInfo != null && tr && surfaceInfo!.trFreeDict.isNotEmpty) {
      children.add(_Section(L('"${widget.surface}" biçimi', 'The form "${widget.surface}"'), [
        for (final s in surfaceInfo!.trFreeDict.take(5)) Text('• $s'),
      ]));
    }

    // ---------------- senses
    // With the built-in explanation above, the WordNet list is extra detail for English readers.
    if (info.senses.isNotEmpty && (wdSenses == null || wdSenses.isEmpty || en)) {
      final byPos = <String, List<Sense>>{};
      for (final s in info.senses) {
        byPos.putIfAbsent(s.pos, () => []).add(s);
      }
      final items = <Widget>[];
      for (final e in byPos.entries) {
        final visible = [for (final s in e.value.take(8)) if (en || (tr && s.tr.isNotEmpty)) s];
        if (visible.isEmpty) continue;
        items.add(Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 2),
          child: Text(posNames[e.key] ?? e.key, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
        ));
        for (final s in visible) {
          items.add(Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: s == best ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5) : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (en) Text(s.gloss, style: enStyle(theme)),
              if (tr && s.tr.isNotEmpty) Text(s.tr.join(', '), style: trStyle(theme)),
              if (en && s.synonyms.isNotEmpty)
                Text(L('eş anlamlı: ${s.synonyms.take(5).join(', ')}', 'synonyms: ${s.synonyms.take(5).join(', ')}'), style: TextStyle(color: theme.hintColor, fontSize: 13)),
              for (var k = 0; k < s.examples.length && k < 2; k++)
                if (en || (tr && k < s.examplesTr.length)) ...[
                  Text('“${s.examples[k]}”', style: enStyle(theme, const TextStyle(fontStyle: FontStyle.italic), false)),
                  if (tr && k < s.examplesTr.length)
                    Padding(padding: const EdgeInsets.only(left: 12), child: Text(s.examplesTr[k], style: trStyle(theme, null, false))),
                ],
            ]),
          ));
        }
      }
      if (items.isNotEmpty) children.add(_Section(en ? L('Anlamlar (WordNet)', 'Meanings (WordNet)') : L('Anlamlar', 'Meanings'), items));
    }

    final exs = app.dict.examples('w:$lemma', limit: 3);
    if (exs.isNotEmpty) {
      children.add(_Section(L('Çevirili örnek cümleler', 'Example sentences with translations'), [
        for (final (e, t) in exs)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('• $e', style: enStyle(theme, const TextStyle(fontStyle: FontStyle.italic), false)),
              if (tr) Padding(padding: const EdgeInsets.only(left: 12), child: Text(t, style: trStyle(theme, null, false))),
            ]),
          ),
      ]));
    }

    if (bookExamples.isNotEmpty) {
      children.add(_Section(L('Kitaptan başka örnekler', 'More examples from the book'), [
        for (final s in bookExamples)
          Padding(padding: const EdgeInsets.only(bottom: 6), child: SentenceText(s, null, highlight: {lemma, widget.surface.toLowerCase()})),
      ]));
    }
    if (info.isEmpty && (ctx?.matches.isEmpty ?? true)) {
      children.add(Padding(padding: EdgeInsets.all(16), child: Text(L('Bu kelime sözlükte bulunamadı.', 'This word was not found in the dictionary.'))));
    }

    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: children);
  }
}

/// "Word Family" tab: root, verb / noun / adjective / adverb forms, negative
/// forms, Turkish meanings and what each affix does. Comes from the bundled
/// dictionary; with an AI service it can be completed online (saved on device).
class WordFamilyView extends StatefulWidget {
  final AppState app;
  final String lemma;
  const WordFamilyView({super.key, required this.app, required this.lemma});

  @override
  State<WordFamilyView> createState() => _WordFamilyViewState();
}

class _WordFamilyViewState extends State<WordFamilyView> {
  WordFamily? offline;
  WordFamily? ai;
  bool builtIn = false;
  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    offline = offlineFamily(widget.app.dict, widget.lemma);
    // Saved AI answer, then the built-in library; the AI is only asked on request.
    final cached = widget.app.user.familyAi(widget.lemma);
    final bundled = cached == null ? widget.app.dict.familyDetail(widget.lemma) : null;
    if (cached != null) {
      ai = WordFamily.fromJsonString(cached, fromAi: true);
    } else if (bundled != null) {
      ai = WordFamily.fromJsonString(bundled, fromAi: true);
      builtIn = true;
    }
  }

  Future<void> _askAi() async {
    final svc = AiService.fromSettings(widget.app.user);
    if (svc == null) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final f = await svc.wordFamily(widget.lemma);
      widget.app.user.setFamilyAi(widget.lemma, f.toJsonString());
      if (mounted) {
        setState(() {
          ai = f;
          builtIn = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = L('Yapay zekâya ulaşılamadı: $e', 'Could not reach the AI: $e'));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = ai ?? offline;
    final hasAi = AiService.fromSettings(widget.app.user) != null;
    final out = <Widget>[];
    if (f == null) {
      out.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(loading
            ? L('Kelime ailesi hazırlanıyor…', 'Preparing the word family…')
            : hasAi
                ? L('Sözlükte bu kelimenin ailesi yok.', 'The dictionary has no family for this word.')
                : L('Sözlükte bu kelimenin ailesi yok. Ayarlar\'dan bir yapay zekâ servisi bağlarsan oluşturabilirim.', 'The dictionary has no family for this word. Connect an AI service in Settings and I can build one.')),
      ));
    } else {
      out.add(Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Text(L('Kök', 'Root'), style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
          const SizedBox(width: 12),
          Text(f.root, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          if (f.rootTr != null && f.rootTr!.isNotEmpty) ...[
            const SizedBox(width: 8),
            Flexible(child: Text('(${f.rootTr})', style: theme.textTheme.titleMedium)),
          ],
        ]),
      ));
      final groups = [('v', L('Fiil (Verb)', 'Verb')), ('n', L('İsim (Noun)', 'Noun')), ('a', L('Sıfat (Adjective)', 'Adjective')), ('r', L('Zarf (Adverb)', 'Adverb'))];
      for (final (pos, title) in groups) {
        final items = f.byPos(pos);
        if (items.isEmpty) continue;
        out.add(_familyGroup(theme, title, items));
      }
      if (f.negatives.isNotEmpty) out.add(_familyGroup(theme, L('Olumsuz / zıt halleri', 'Negative / opposite forms'), f.negatives, negative: true));
    }
    if (loading && f != null) {
      out.add(const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()));
    }
    if (error != null) out.add(Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: TextStyle(color: theme.colorScheme.error))));
    if (hasAi && ai == null && !loading && offline != null) {
      out.add(Padding(
        padding: const EdgeInsets.only(top: 14),
        child: OutlinedButton.icon(
          onPressed: _askAi,
          icon: const Icon(Icons.auto_awesome),
          label: Text(L('Yapay zekâ ile ayrıntılı göster', 'Show details with AI')),
        ),
      ));
    }
    if (f != null) {
      out.add(Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
            builtIn
                ? L('Kaynak: dahili sözlük', 'Source: built-in dictionary')
                : f.fromAi
                    ? L('Kaynak: yapay zekâ (cihaza kaydedildi)', 'Source: AI (saved on device)')
                    : L('Kaynak: WordNet türetme bağlantıları', 'Source: WordNet derivation links'),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: out);
  }

  Widget _familyGroup(ThemeData theme, String title, List<FamilyEntry> items, {bool negative = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: theme.textTheme.labelLarge?.copyWith(color: negative ? theme.colorScheme.error : theme.colorScheme.primary)),
        const SizedBox(height: 4),
        for (final e in items)
          _familyEntry(theme, e, negative),
      ]),
    );
  }

  Widget _familyEntry(ThemeData theme, FamilyEntry e0, bool negative) {
    var e = e0;
    if (e.exEn == null) {
      final x = widget.app.dict.examples('w:${e.word}', limit: 1);
      if (x.isNotEmpty) {
        e = FamilyEntry(e.word, e.pos, tr: e.tr, affixNote: e.affixNote, affixNoteEn: e.affixNoteEn,
            negative: e.negative, exEn: x.first.$1, exTr: x.first.$2);
      }
    }
    return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: negative ? theme.colorScheme.error : theme.colorScheme.primary, width: 3)),
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(TextSpan(children: [
                TextSpan(
                  text: e.word,
                  style: enStyle(theme, TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    decoration: e.word == widget.lemma ? TextDecoration.underline : null,
                  )).copyWith(fontWeight: FontWeight.w700),
                ),
                if (e.tr != null && e.tr!.isNotEmpty && widget.app.showTr) TextSpan(text: '  ${e.tr}', style: trStyle(theme)),
              ])),
              if (e.note != null)
                Text(e.note!, style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
              if (e.exEn != null && (widget.app.showEn || widget.app.showTr)) ...[
                const SizedBox(height: 4),
                Text('“${e.exEn}”', style: enStyle(theme, const TextStyle(fontStyle: FontStyle.italic, fontSize: 14), false)),
                if (e.exTr != null && widget.app.showTr)
                  Padding(padding: const EdgeInsets.only(left: 12), child: Text(e.exTr!, style: trStyle(theme, const TextStyle(fontSize: 14), false))),
              ],
            ]),
          );
  }
}

class StatusButtons extends StatelessWidget {
  final WordStatus status;
  final ValueChanged<WordStatus> onChanged;
  const StatusButtons({super.key, required this.status, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<WordStatus>(
      segments: [
        ButtonSegment(value: WordStatus.learning, label: Text(L('Öğreneceğim', 'To learn')), icon: Icon(Icons.bookmark_add_outlined)),
        ButtonSegment(value: WordStatus.learned, label: Text(L('Öğrendim', 'Learned')), icon: Icon(Icons.check_circle_outline)),
      ],
      emptySelectionAllowed: true,
      selected: status == WordStatus.none ? {} : {status},
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) {
          if (!s.contains(WidgetState.selected)) return null;
          return status == WordStatus.learning ? learningColor.withValues(alpha: 0.35) : learnedColor.withValues(alpha: 0.35);
        }),
      ),
      onSelectionChanged: (s) => onChanged(s.isEmpty ? WordStatus.none : s.first),
    );
  }
}

class LangToggles extends StatelessWidget {
  final AppState app;
  final VoidCallback onChanged;
  const LangToggles({super.key, required this.app, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 6, children: [
      FilterChip(
        label: const Text('Türkçe'),
        selected: app.showTr,
        onSelected: (v) {
          app.setLang(tr: v);
          onChanged();
        },
      ),
      FilterChip(
        label: const Text('English'),
        selected: app.showEn,
        onSelected: (v) {
          app.setLang(en: v);
          onChanged();
        },
      ),
    ]);
  }
}

class ExprCard extends StatefulWidget {
  final AppState app;
  final Expr expr;
  final VoidCallback onChanged;
  final WordContext? ctx;
  const ExprCard({super.key, required this.app, required this.expr, required this.onChanged, this.ctx});

  @override
  State<ExprCard> createState() => _ExprCardState();
}

class _ExprCardState extends State<ExprCard> {
  bool translating = false;

  AppState get app => widget.app;
  Expr get expr => widget.expr;

  late final String? _gloss = expr.trShown == null ? wordGloss(app.dict, expr.phrase) : null;

  /// An example with its Turkish when one is known: the built-in sense
  /// examples first, then a translated Tatoeba sentence, then the list's own
  /// English example.
  late final (String, String?)? _example = () {
    final key = '${expr.phrase}|${expr.cat}';
    final cached = app.user.exprDetail(key) ?? app.dict.exprDetail(expr.phrase, expr.cat);
    if (cached != null) {
      try {
        for (final s in jsonDecode(cached) as List) {
          for (final e in ((s as Map)['examples'] as List? ?? const [])) {
            final en = '${(e as Map)['en'] ?? ''}', tr = '${e['tr'] ?? ''}';
            if (en.isNotEmpty && tr.isNotEmpty) return (en, tr);
          }
        }
      } catch (_) {}
    }
    if (expr.ex != null && expr.exTr != null) return (expr.ex!, expr.exTr);
    final t = app.dict.examples(key, limit: 1);
    if (t.isNotEmpty) return (t.first.$1, t.first.$2);
    // An English-only example only when English is shown.
    return expr.ex == null || !app.showEn ? null : (expr.ex!, null);
  }();

  /// Entries with only an English definition can be translated on request when
  /// an AI service is connected; the result is saved on the device. Nothing is
  /// fetched automatically, so the panel never waits for the internet.
  Future<void> _translateIfNeeded() async {
    if (!expr.needsAi) return;
    final svc = AiService.fromSettings(app.user);
    if (svc == null) return;
    setState(() => translating = true);
    try {
      await app.analyzer.translateExprsNow(svc, [expr]);
    } catch (_) {
      // Offline or service error: the English definition stays visible.
    } finally {
      if (mounted) setState(() => translating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = categoryById[expr.cat]!;
    final theme = Theme.of(context);
    final tr = expr.trShown;
    // Without a Turkish meaning, the English definition is always shown.
    final showEn = app.showEn || tr == null;
    final st = app.user.statuses[expr.phrase] ?? WordStatus.none;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: c.color, width: 4)),
        color: c.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(expr.phrase, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
          Text(uiEnglish || (app.showEn && !app.showTr) ? c.name : c.tr, style: TextStyle(color: c.color, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        if (showEn && expr.en != null) Text(expr.en!, style: enStyle(theme)),
        if (app.showTr && tr != null) Text(tr, style: trStyle(theme)),
        // No Turkish yet: at least the words one by one, never English alone.
        if (app.showTr && tr == null && _gloss != null)
          Text(L('Kelime kelime: $_gloss', 'Word by word: $_gloss'), style: trStyle(theme, null, false)),
        if (app.showTr && expr.aiExp != null) Text(expr.aiExp!, style: trStyle(theme, null, false)),
        if (translating)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 8),
              Text(L('Türkçeye çevriliyor…', 'Translating into Turkish…'), style: theme.textTheme.bodySmall),
            ]),
          ),
        if (_example case final ex?)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('“${ex.$1}”', style: enStyle(theme, const TextStyle(fontStyle: FontStyle.italic), false)),
              if (app.showTr && ex.$2 != null)
                Padding(padding: const EdgeInsets.only(left: 12), child: Text(ex.$2!, style: trStyle(theme, null, false))),
            ]),
          ),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          StatusButtons(
            status: st,
            onChanged: (s) {
              app.setWord(expr.phrase, s, meaning: expr.trShown ?? expr.en);
              widget.onChanged();
            },
          ),
          if (expr.needsAi && !translating && AiService.fromSettings(app.user) != null)
            TextButton.icon(
              onPressed: _translateIfNeeded,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: Text(L('Türkçeye çevir', 'Translate to Turkish')),
            ),
          if (widget.ctx != null && expr.pattern.length > 1)
            TextButton.icon(
              onPressed: () => showExprSheet(context, app, expr, widget.ctx!, expr.phrase.split(' ')),
              icon: const Icon(Icons.menu_book_outlined, size: 18),
              label: Text(L('Anlamlar ve örnekler', 'Meanings and examples')),
            ),
        ]),
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section(this.title, this.children);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(letterSpacing: 1.1, color: Theme.of(context).hintColor)),
        const Divider(height: 10),
        ...children,
      ]),
    );
  }
}

class SentenceText extends StatelessWidget {
  final String sentence;
  final String? word;
  final Set<String>? highlight;
  const SentenceText(this.sentence, this.word, {this.highlight});

  @override
  Widget build(BuildContext context) {
    final toks = tokenize(sentence);
    final spans = <TextSpan>[];
    var pos = 0;
    final hl = highlight ?? {word!.toLowerCase()};
    for (final t in toks) {
      if (t.start > pos) spans.add(TextSpan(text: sentence.substring(pos, t.start)));
      final on = hl.contains(t.lower) || (highlight != null && hl.any((h) => t.lower.startsWith(h) && t.lower.length <= h.length + 3));
      spans.add(TextSpan(text: t.text, style: on ? const TextStyle(fontWeight: FontWeight.w800, decoration: TextDecoration.underline) : null));
      pos = t.end;
    }
    if (pos < sentence.length) spans.add(TextSpan(text: sentence.substring(pos)));
    return SelectableText.rich(TextSpan(style: const TextStyle(fontSize: 16, height: 1.45), children: spans));
  }
}
