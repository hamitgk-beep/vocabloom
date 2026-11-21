import 'dart:convert';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/dict_db.dart';
import '../data/user_db.dart';
import '../nlp/text.dart';
import '../nlp/word_family.dart';
import '../ai/tutor.dart';
import '../online/ai_service.dart';
import '../ai/device_translate.dart';
import 'ai/ai_ask_box.dart';
import 'ai/device_translation.dart';
import 'ai/local_ai_card.dart';
import 'expr_sheet.dart';
import 'panel.dart';
import 'tap_text.dart';
import 'context_sense_card.dart';
import '../nlp/context_sense.dart';
import '../l10n.dart';
import 'paragraph_view.dart';
import 'meaning_parts.dart';
import 'theme.dart';
import 'tr_word_sheet.dart';
import '../tts/speech.dart';
import '../tts/voice_ui.dart';

/// Context in which a word was tapped (null when opened from a list).
class WordContext {
  final String sentence;
  final List<Token> sentenceTokens;
  final int indexInSentence;
  final List<Match> matches; // expressions covering the token
  final List<String>? sentenceTr;
  final int? bookId;
  final String? bookTitle;

  /// Paragraph the sentence is in, and the sentences around it (context
  /// meanings and the AI question use them).
  final int? paraId;
  final String? prevSentence;
  final String? nextSentence;
  WordContext(this.sentence, this.sentenceTokens, this.indexInSentence, this.matches, this.sentenceTr, this.bookId, this.bookTitle, {this.paraId, this.prevSentence, this.nextSentence});

  /// Id of the text for the meaning cache: book and paragraph.
  String get contentId => 'b${bookId ?? 0}:p${paraId ?? 0}';
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
  String? at(int k) => k >= 0 && k < ranges.length ? para.text.substring(ranges[k].$1, ranges[k].$2).trim() : null;
  final sentence = para.text.substring(r.$1, r.$2).trim();
  final sTr = tr != null && sIdx < tr.length && plausibleTranslation(sentence, tr[sIdx]) ? [tr[sIdx]] : null;
  return WordContext(sentence, sentTokens, idx < 0 ? 0 : idx, matches, sTr, bookId, bookTitle, paraId: para.id, prevSentence: at(sIdx - 1), nextSentence: at(sIdx + 1));
}

/// Whether a saved Turkish translation can belong to [en]: translations saved
/// by older versions could slip onto a neighbouring sentence when the AI
/// joined two sentences, and then are far longer or shorter than the English.
bool plausibleTranslation(String en, String tr) {
  if (tr.trim().isEmpty) return false;
  final a = en.trim().length, b = tr.trim().length;
  if (a < 12) return true;
  final ratio = b / a;
  return ratio >= 0.45 && ratio <= 2.2;
}

Future<void> showWordSheet(BuildContext context, AppState app, String surface, {WordContext? ctx, String? lemma}) {
  panelApp = app;
  app.stats.logLookup('word', lemma ?? surface);
  if (app.learnTurkish) {
    return showPanel(context, (c, sc) => TrWordPanel(app: app, surface: surface, ctx: ctx, lemma: lemma, scroll: sc), short: true);
  }
  return showPanel(context, (c, sc) => WordPanel(app: app, surface: surface, ctx: ctx, lemma: lemma, scroll: sc), short: true);
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
  String? corrected; // the dictionary word shown for a misspelt one
  Sense? best;

  /// The meaning chosen for the book's sentence (null when opened from a list
  /// or when the engine could not run).
  ContextSense? sense;
  List<String> bookExamples = [];

  @override
  void initState() {
    super.initState();
    final app = widget.app;
    final lower = widget.surface.toLowerCase().replaceAll('’', "'");
    final cands = app.dict.lemmatizer.lemmas(lower);
    lemma = widget.lemma ?? cands.first;
    // A past form of an irregular verb belongs to that verb ("found" -> find,
    // "fell" -> fall), unless it is a base form itself ("lay").
    final irrBase = app.dict.irregularOf[lower];
    final irr = widget.lemma == null && irrBase != null && !app.dict.irregular.containsKey(lower);
    if (irr) lemma = irrBase.first;
    // A word that is itself common beats a rare base form the suffix rules
    // produce ("never" is not a form of "neve").
    if (widget.lemma == null && !irr && lemma != lower && cands.contains(lower)) {
      int freq(String w) {
        final r = app.dict.db.select('SELECT n FROM wfreq WHERE word=?', [w]);
        return r.isEmpty ? 0 : r.first['n'] as int;
      }

      if (freq(lower) >= freq(lemma)) lemma = lower;
    }
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
    // A misspelling in the book ("overwhelmn"): show the closest dictionary
    // word instead of "not found". Not for names ("Harry" is not "hurry"):
    // a capitalised word only counts at the start of a sentence.
    final ctx0 = widget.ctx;
    final named = widget.surface.isNotEmpty && widget.surface[0] != widget.surface[0].toLowerCase() && (ctx0 == null || ctx0.indexInSentence != 0);
    if (info.isEmpty && widget.lemma == null && !named && (ctx0?.matches.isEmpty ?? true)) {
      final fix = app.dict.closestWord(lower);
      if (fix != null) {
        corrected = fix;
        lemma = fix;
        info = app.dict.lookup(fix);
      }
    }
    if (lower != lemma && cands.contains(lower)) {
      final si = app.dict.lookup(lower);
      if (!si.isEmpty) surfaceInfo = si;
    }
    final ctx = widget.ctx;
    if (ctx != null) best = app.dict.bestSense(info, ctx.sentenceTokens, ctx.indexInSentence);
    if (ctx != null) {
      sense = ContextSenseCard.resolve(app, ctx, lemma: lemma);
      // The sense list below marks the meaning the card chose.
      final id = sense?.best?.id;
      if (sense?.shown == true && sense!.cat == null && id != null && id.startsWith('wn:')) {
        final syn = int.tryParse(id.substring(3));
        for (final s in [...info.senses, ...?surfaceInfo?.senses]) {
          if (s.synId == syn) best = s;
        }
      }
    }
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
      // A noun or adjective in the sentence never gets a verb meaning
      // ("a golf course" is not "akmak"), and a verb gets a verb meaning.
      final fit = bestPos == null ? list : list.where((t) => DictDb.isTrVerb(t) == (bestPos == 'v')).toList();
      final pool = fit.isEmpty ? list : fit;
      final pick = bestPos == 'a' || bestPos == 's' ? pool.firstWhere((t) => !t.contains('kimse') && !t.contains('kişi'), orElse: () => pool.first) : pool.first;
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

  /// Turkish of the meaning chosen for this sentence, when the card shows one
  /// for this word itself (not for an expression it is part of).
  String? get _ctxTr => sense != null && sense!.shown && sense!.cat == null && sense!.headword == lemma ? sense!.tr : null;

  /// "Well, my boy ...", "So, what now?": a word that opens the sentence and
  /// is followed by a comma is used as an interjection or discourse marker.
  /// When the sense engine finds no meaning, that use is shown: the own
  /// dictionary's interjection sense, or the matched expression of the word.
  late final ({String tr, String pos, String? note})? opener = () {
    final ctx = widget.ctx;
    if (ctx == null || sense?.shown == true) return null;
    final i = ctx.indexInSentence;
    if (i < 0 || i >= ctx.sentenceTokens.length) return null;
    final t = ctx.sentenceTokens[i];
    final at = ctx.sentence.toLowerCase().replaceAll('’', "'").indexOf(t.lower);
    if (at < 0) return null;
    final before = ctx.sentence.substring(0, at);
    final after = ctx.sentence.substring(at + t.text.length).trimLeft();
    final opens = i == 0 && RegExp(r'''^[\s'"‘“(\[—–-]*$''').hasMatch(before) && after.startsWith(',');
    if (opens) {
      for (final o in own) {
        if (o.pos == 'ünlem') return (tr: o.tr, pos: 'ünlem', note: o.note.isEmpty ? null : o.note);
      }
    }
    for (final m in ctx.matches) {
      if (m.tokens.length == 1 && m.expr.phrase == lemma && m.expr.trShown != null && (opens || m.expr.cat != 'discourse_markers')) {
        return (tr: m.expr.trShown!, pos: opens ? 'ünlem' : '', note: null);
      }
    }
    return null;
  }();

  String? get _meaning => _ctxTr ?? opener?.tr ?? _trMain ?? best?.gloss;

  void _set(String key, WordStatus st) {
    widget.app.setWord(key, st, context: widget.ctx?.sentence, book: widget.ctx?.bookTitle, meaning: key == lemma ? _meaning : null);
    setState(() {});
  }

  /// The own dictionary's senses of the word (Turkish, English definition,
  /// a translated example each).
  late final List<OwnSense> own = widget.app.dict.ownSenses(lemma);
  bool familyOpen = false;

  /// Index in [own] of the meaning shown at the top, so it is not listed again.
  int? get _ownShown {
    final id = sense?.shown == true && sense!.cat == null ? sense!.best?.id : null;
    if (id != null && id.startsWith('ow:$lemma#')) return int.tryParse(id.substring(id.indexOf('#') + 1));
    final shownTr = sense?.shown == true && sense!.cat == null ? sense!.tr : null;
    if (shownTr == null) return null;
    for (var i = 0; i < own.length; i++) {
      if (own[i].tr.split(RegExp(r'[,;]')).map((x) => x.trim()).any(shownTr.split(', ').contains)) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final theme = Theme.of(context);
    final ctx = widget.ctx;
    final st = app.user.statuses[lemma] ?? WordStatus.none;

    // Irregular verb: the header keeps the tapped form ("found") and the
    // V1/V2/V3 row under it shows the whole verb with that form in bold.
    final surface = widget.surface.toLowerCase().replaceAll('’', "'");
    final verbForms = app.dict.irregular[lemma];
    final head = verbForms != null && verbForms.contains(surface) ? surface : lemma;
    final cardPos = sense?.shown == true && sense!.cat == null ? sense!.best?.pos : null;
    final pos = cardPos ?? (opener != null && opener!.pos.isNotEmpty ? opener!.pos : null) ?? (ctx == null && own.isNotEmpty ? own.first.pos : best?.pos);
    final card = ctx != null && sense != null && opener == null;

    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.only(right: 40),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(
              head,
              style: TextStyle(fontFamily: readingFont, fontSize: 34, fontWeight: FontWeight.w700, height: 1.1, color: theme.colorScheme.onSurface),
            ),
            if (Speech.supported) SpeakButton(head, key: ValueKey('say-$head'), tooltip: L('Telaffuzu dinle', 'Hear the pronunciation'), size: 26),
            if (surface != head) Text('(${widget.surface})', style: theme.textTheme.titleMedium?.copyWith(color: theme.hintColor)),
            if (pos != null && posLabel(pos).isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: goldSoft(theme), borderRadius: BorderRadius.circular(20)),
                child: Text(
                  posLabel(pos),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.primary),
                ),
              ),
          ],
        ),
      ),
      if (corrected != null)
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 2),
          child: Row(
            children: [
              Icon(Icons.spellcheck, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  L(
                    '"${widget.surface}" sözlükte yok, yazım hatası olabilir. Bunu mu demek istediniz: $corrected',
                    '"${widget.surface}" is not in the dictionary; it may be a typo. Did you mean: $corrected',
                  ),
                  style: TextStyle(color: theme.hintColor, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      if (verbForms != null) VerbFormsRow(forms: verbForms, tapped: surface),
    ];

    // ---------------- to learn / learned: right under the meaning, so the
    // short panel shows it without scrolling.
    final statusRow = Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        children: [
          Expanded(
            child: PanelPill(
              key: const ValueKey('word-learning'),
              icon: st == WordStatus.learning ? Icons.bookmark_rounded : Icons.bookmark_add_outlined,
              label: L('Öğreneceğim', 'To learn'),
              color: st == WordStatus.learning ? learningColor : null,
              fill: st == WordStatus.learning ? learningColor.withValues(alpha: 0.2) : null,
              onPressed: () => _set(lemma, st == WordStatus.learning ? WordStatus.none : WordStatus.learning),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: PanelPill(
              key: const ValueKey('word-learned'),
              icon: st == WordStatus.learned ? Icons.check_circle_rounded : Icons.check_circle_outline,
              label: L('Öğrendim', 'Learned'),
              color: st == WordStatus.learned ? learnedColor : null,
              fill: st == WordStatus.learned ? learnedColor.withValues(alpha: 0.2) : null,
              onPressed: () => _set(lemma, st == WordStatus.learned ? WordStatus.none : WordStatus.learned),
            ),
          ),
        ],
      ),
    );

    // ---------------- the meaning here, and the book's sentence
    final mainOwn = own.isEmpty ? null : own.first;
    if (card) {
      children.add(
        ContextSenseCard(
          key: ValueKey('ctx-${ctx.contentId}-${ctx.sentence.hashCode}-${ctx.indexInSentence}'),
          app: app,
          result: sense!,
          ctx: ctx,
          highlight: {widget.surface.toLowerCase(), if (sense!.cat != null) ...sense!.headword.split(' ')},
          actions: statusRow,
        ),
      );
    } else {
      // The own dictionary's first meaning is the word's main one.
      final trMain = opener?.tr ?? mainOwn?.tr ?? _trMain;
      if (trMain != null) {
        children.add(
          MeaningBox(
            key: const ValueKey('word-meaning-box'),
            label: ctx != null ? L('BU CÜMLEDEKİ ANLAMI', 'MEANING IN THIS SENTENCE') : L('ANLAMI', 'MEANING'),
            tr: trMain,
            note: opener?.note,
            en: opener != null ? null : (mainOwn != null ? mainOwn.en : best?.gloss),
          ),
        );
      } else if (LocalAiCard.available(app)) {
        children.add(
          LocalAiCard(
            key: ValueKey('ai-word-$lemma'),
            app: app,
            cacheKey: 'word:$lemma|${ctx?.sentence ?? ''}',
            title: L('Yapay zekâ: Türkçe anlamı', 'AI: meaning in Turkish'),
            button: L('Yapay zekâ ile açıkla', 'Explain with AI'),
            auto: true,
            run: () => Tutor.of(app).wordMeaning(lemma, sentence: ctx?.sentence, gloss: best?.gloss ?? info.senses.firstOrNull?.gloss, turkish: null),
          ),
        );
      } else if (!info.isEmpty) {
        children.add(DeviceTranslation(key: ValueKey('mt-$lemma'), app: app, text: lemma, style: theme.textTheme.titleLarge));
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              L('Bu kelimenin sözlükte Türkçesi yok. Aşağıdaki "Yapay zekâya sor" ile öğrenebilirsin.', 'The dictionary has no Turkish for this word. Use "Ask the AI" below.'),
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
            ),
          ),
        );
      }
      children.add(statusRow);
      if (ctx != null) {
        children.add(PanelHeading(L('KİTAPTAKİ CÜMLE', 'SENTENCE IN THE BOOK')));
        children.add(BookSentenceCard(app: app, ctx: ctx, highlight: {widget.surface.toLowerCase()}));
      }
    }

    // ---------------- expressions this word is part of here
    // (an irregular verb's own entry is the V1/V2/V3 row above; each once)
    final seen = <String>{};
    final exprs = [
      for (final m in ctx?.matches ?? const <Match>[])
        if (m.expr.cat != 'irregular_verbs' && seen.add('${m.expr.phrase}|${m.expr.cat}')) m.expr,
    ];
    if (ctx != null && exprs.isNotEmpty) {
      children.add(PanelHeading(L('BU CÜMLEDEKİ KALIPLAR', 'EXPRESSIONS IN THIS SENTENCE')));
      for (final e in exprs) {
        children.add(ExprCard(app: app, expr: e, ctx: ctx, onChanged: () => setState(() {})));
      }
    }

    // ---------------- the other meanings: Turkish first, never English alone
    final tiles = <Widget>[];
    final hasTop = card ? sense!.shown : (opener != null || _trMain != null || mainOwn != null);
    void tile(String? p, String tr, String? en, String? exEn, String? exTr) =>
        tiles.add(SenseTile(number: tiles.length + (hasTop ? 2 : 1), pos: p, tr: tr, en: en, exEn: exEn, exTr: exTr, divider: tiles.isNotEmpty));
    final openerOwn = opener == null ? -1 : own.indexWhere((o) => o.tr == opener!.tr);
    final topShown = card ? (sense!.shown && sense!.cat == null ? _ownShown : null) : (opener != null ? (openerOwn < 0 ? null : openerOwn) : (mainOwn != null ? 0 : null));
    if (own.isNotEmpty) {
      for (var i = 0; i < own.length; i++) {
        if (i == topShown) continue;
        final o = own[i];
        tile([posLabel(o.pos), if (o.note.isNotEmpty) o.note].join(' · '), o.tr, o.en, o.ex, o.ex.isEmpty ? null : o.exTr);
      }
    } else {
      // No own entry: WordNet meanings that have Turkish, then the plain list.
      final shownTr = card ? sense!.tr : _trMain;
      for (final x in info.senses.take(12)) {
        if (x.tr.isEmpty) continue;
        final t = x.tr.take(3).join(', ');
        if (t == shownTr) continue;
        tile(posLabel(x.pos), t, x.gloss, x.examples.firstOrNull, x.examplesTr.firstOrNull);
      }
      if (tiles.isEmpty) {
        for (final t in info.trFreeDict.take(8)) {
          if (t == shownTr) continue;
          tile(null, t, null, null, null);
        }
      }
    }
    if (tiles.isNotEmpty) {
      children.add(PanelHeading(hasTop ? L('DİĞER ANLAMLARI', 'OTHER MEANINGS') : L('ANLAMLARI', 'MEANINGS')));
      children.add(
        PanelCard(
          padding: const EdgeInsets.fromLTRB(14, 0, 12, 0),
          child: Column(children: tiles),
        ),
      );
    }
    if (surfaceInfo != null && surfaceInfo!.trFreeDict.isNotEmpty) {
      children.add(PanelHeading(L('"${widget.surface}" BİÇİMİ', 'THE FORM "${widget.surface}"')));
      children.add(
        PanelCard(
          child: LangLine(en: false, child: Text(surfaceInfo!.trFreeDict.take(4).join('; '), style: panelTrStyle(theme))),
        ),
      );
    }

    // ---------------- example sentences with their Turkish (when the own
    // dictionary has none for this word)
    if (own.isEmpty) {
      final exs = app.dict.examples('w:$lemma', limit: 2);
      if (exs.isNotEmpty) {
        children.add(PanelHeading(L('ÖRNEK CÜMLELER', 'EXAMPLE SENTENCES')));
        children.add(
          PanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var k = 0; k < exs.length; k++) ...[
                  if (k > 0) const SizedBox(height: 14),
                  LangLine(en: true, child: TapText(exs[k].$1, style: panelEnStyle(theme, size: 14.5))),
                  const SizedBox(height: 4),
                  LangLine(en: false, child: Text(exs[k].$2, style: panelTrStyle(theme, size: 14.5))),
                ],
              ],
            ),
          ),
        );
      }
    }

    // ---------------- another sentence from the book, only with its Turkish
    if (bookExamples.isNotEmpty && DeviceTranslate.instance.ready(app.user)) {
      final s0 = bookExamples.first;
      children.add(PanelHeading(L('KİTAPTAN BAŞKA BİR CÜMLE', 'ANOTHER SENTENCE FROM THE BOOK')));
      children.add(
        PanelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LangLine(
                en: true,
                child: TapText(s0, style: panelEnStyle(theme), highlight: {lemma, widget.surface.toLowerCase()}),
              ),
              const LangDivider(),
              LangLine(
                en: false,
                child: DeviceTranslation(key: ValueKey('mt-b-$s0'), app: app, text: s0, style: panelTrStyle(theme)),
              ),
            ],
          ),
        ),
      );
    }

    // ---------------- word family, opened on request
    children.add(
      Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Material(
          color: theme.brightness == Brightness.dark ? const Color(0x0EFFECCD) : Color.lerp(theme.colorScheme.surfaceContainerLowest, Colors.white, 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: theme.brightness == Brightness.dark ? const Color(0x1CFFE6BE) : theme.colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('word-family'),
            onTap: () => setState(() => familyOpen = !familyOpen),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              child: Row(
                children: [
                  Icon(Icons.account_tree_outlined, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(L('Kelime ailesi', 'Word Family'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  ),
                  Icon(familyOpen ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: theme.colorScheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (familyOpen) children.add(WordFamilyView(app: app, lemma: lemma, key: ValueKey(lemma)));

    // ---------------- one AI question box when there is no book sentence
    // (the sentence card has its own "Ask the AI")
    if (!card) {
      children.add(
        AiAskBox(
          key: ValueKey('ai-ask-$lemma'),
          app: app,
          title: L('Yapay zekâya sor', 'Ask the AI'),
          suggestions: [
            L('Bu kelimeyi detaylı anlat', 'Explain this word in detail'),
            if (ctx != null) L('Bu cümlede ne anlama geliyor?', 'What does it mean in this sentence?'),
            L('Başka örnek cümle ver', 'Give more example sentences'),
            L('Benzer kelimelerden farkı ne?', 'How is it different from similar words?'),
          ],
          about:
              'Kelime: $lemma\n'
              '${(best?.gloss ?? info.senses.firstOrNull?.gloss) == null ? '' : 'İngilizce tanımı: ${best?.gloss ?? info.senses.first.gloss}\n'}'
              '${_trMain == null ? '' : 'Türkçe karşılıkları: $_trMain\n'}'
              '${ctx == null ? '' : 'Okuduğu cümle: "${ctx.sentence}"'}',
        ),
      );
    }
    if (info.isEmpty && own.isEmpty && (ctx?.matches.isEmpty ?? true)) {
      children.add(Padding(padding: const EdgeInsets.all(16), child: Text(L('Bu kelime sözlükte bulunamadı.', 'This word was not found in the dictionary.'))));
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
      if (mounted) setState(() => error = L('Yapay zekâya ulaşılamadı: ${errorText(e)}', 'Could not reach the AI: ${errorText(e)}'));
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
      out.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            loading
                ? L('Kelime ailesi hazırlanıyor…', 'Preparing the word family…')
                : hasAi
                ? L('Sözlükte bu kelimenin ailesi yok.', 'The dictionary has no family for this word.')
                : L(
                    'Sözlükte bu kelimenin ailesi yok. Ayarlar\'dan bir yapay zekâ servisi bağlarsan oluşturabilirim.',
                    'The dictionary has no family for this word. Connect an AI service in Settings and I can build one.',
                  ),
          ),
        ),
      );
    } else {
      out.add(
        Container(
          margin: const EdgeInsets.only(top: 14),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(10)),
          child: Row(
            children: [
              Text(L('Kök', 'Root'), style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
              const SizedBox(width: 12),
              Text(f.root, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              if (f.rootTr != null && f.rootTr!.isNotEmpty && widget.app.showTr) ...[const SizedBox(width: 8), Flexible(child: Text('(${f.rootTr})', style: theme.textTheme.titleMedium))],
            ],
          ),
        ),
      );
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
    if (error != null)
      out.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(error!, style: TextStyle(color: theme.colorScheme.error)),
        ),
      );
    if (hasAi && ai == null && !loading && offline != null) {
      out.add(
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: OutlinedButton.icon(onPressed: _askAi, icon: const Icon(Icons.auto_awesome), label: Text(L('Yapay zekâ ile ayrıntılı göster', 'Show details with AI'))),
        ),
      );
    }
    if (f != null) {
      out.add(
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            builtIn
                ? L('Kaynak: dahili sözlük', 'Source: built-in dictionary')
                : f.fromAi
                ? L('Kaynak: yapay zekâ (cihaza kaydedildi)', 'Source: AI (saved on device)')
                : L('Kaynak: WordNet türetme bağlantıları', 'Source: WordNet derivation links'),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: out);
  }

  Widget _familyGroup(ThemeData theme, String title, List<FamilyEntry> items, {bool negative = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.labelLarge?.copyWith(color: negative ? theme.colorScheme.error : theme.colorScheme.primary)),
          const SizedBox(height: 4),
          for (final e in items) _familyEntry(theme, e, negative),
        ],
      ),
    );
  }

  Widget _familyEntry(ThemeData theme, FamilyEntry e0, bool negative) {
    var e = e0;
    if (e.exEn == null) {
      final x = widget.app.dict.examples('w:${e.word}', limit: 1);
      if (x.isNotEmpty) {
        e = FamilyEntry(e.word, e.pos, tr: e.tr, affixNote: e.affixNote, affixNoteEn: e.affixNoteEn, negative: e.negative, exEn: x.first.$1, exTr: x.first.$2);
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: e.word,
                  style: enStyle(
                    theme,
                    TextStyle(fontWeight: FontWeight.w700, fontSize: 16, decoration: e.word == widget.lemma ? TextDecoration.underline : null),
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
                if (e.tr != null && e.tr!.isNotEmpty && widget.app.showTr) TextSpan(text: '  ${e.tr}', style: trStyle(theme)),
              ],
            ),
          ),
          if (e.note != null) Text(e.note!, style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
          if (e.exEn != null && (widget.app.showEn || widget.app.showTr)) ...[
            const SizedBox(height: 4),
            TapText('“${e.exEn}”', style: enStyle(theme, const TextStyle(fontStyle: FontStyle.italic, fontSize: 14), false)),
            if (e.exTr != null && widget.app.showTr)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(e.exTr!, style: trStyle(theme, const TextStyle(fontSize: 14), false)),
              ),
          ],
        ],
      ),
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
    return Wrap(
      spacing: 6,
      children: [
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
      ],
    );
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
    // A one-word discourse marker ("well", "right") only with an example of
    // that use: opening the sentence, before a comma ("Well, ..."), not
    // "I did well".
    final single = !expr.phrase.contains(' ');
    final opener = RegExp('^\\W*${RegExp.escape(expr.phrase)},', caseSensitive: false);
    final t = app.dict.examples(key, limit: single && expr.cat == 'discourse_markers' ? 12 : 1);
    final fit = single && expr.cat == 'discourse_markers' ? t.where((x) => opener.hasMatch(x.$1)).toList() : t;
    if (fit.isNotEmpty) return (fit.first.$1, fit.first.$2);
    if (single && expr.cat == 'discourse_markers') return null;
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
    // A one-word entry's English comes from the word's first dictionary
    // sense ("well": "in a good manner"), not from this use, so it is left
    // out when the Turkish is known. Without Turkish it is always shown.
    final single = !expr.phrase.contains(' ');
    final showEn = (app.showEn && !(single && tr != null)) || tr == null;
    final st = app.user.statuses[expr.phrase] ?? WordStatus.none;
    final dark = theme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(c.color.withValues(alpha: dark ? 0.10 : 0.07), dark ? const Color(0x0EFFECCD) : theme.colorScheme.surfaceContainerLowest),
        borderRadius: BorderRadius.circular(18),
        border: Border(left: BorderSide(color: c.color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  displayPhrase(expr.phrase),
                  style: TextStyle(fontFamily: readingFont, fontWeight: FontWeight.w700, fontSize: 18, color: theme.colorScheme.onSurface),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  uiEnglish || (app.showEn && !app.showTr) ? c.name : c.tr,
                  style: TextStyle(color: c.color, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (app.showTr && tr != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: LangLine(
                en: false,
                child: Text(tr, style: panelTrStyle(theme, size: 17, weight: FontWeight.w700)),
              ),
            ),
          // No Turkish yet: at least the words one by one, never English alone.
          if (app.showTr && tr == null && _gloss != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: LangLine(
                en: false,
                child: Text(L('Kelime kelime: $_gloss', 'Word by word: $_gloss'), style: panelTrStyle(theme, size: 14.5, weight: FontWeight.w500)),
              ),
            ),
          if (showEn && expr.en != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: LangLine(en: true, child: TapText(expr.en!, style: panelEnStyle(theme, size: 13.5))),
            ),
          if (app.showTr && expr.aiExp != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(expr.aiExp!, style: panelTrStyle(theme, size: 14, weight: FontWeight.w500)),
            ),
          if (translating)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Text(L('Türkçeye çevriliyor…', 'Translating into Turkish…'), style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          if (_example case final ex?)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.only(left: 10),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: goldSoft(theme), width: 3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TapText(ex.$1, style: panelEnStyle(theme, size: 14)),
                  if (app.showTr && ex.$2 != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(ex.$2!, style: panelTrStyle(theme, size: 14, weight: FontWeight.w500)),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusButtons(
                status: st,
                onChanged: (s) {
                  app.setWord(expr.phrase, s, meaning: expr.trShown ?? expr.en);
                  widget.onChanged();
                },
              ),
              if (expr.needsAi && !translating && AiService.fromSettings(app.user) != null)
                TextButton.icon(onPressed: _translateIfNeeded, icon: const Icon(Icons.auto_awesome, size: 18), label: Text(L('Türkçeye çevir', 'Translate to Turkish'))),
              if (widget.ctx != null && expr.pattern.length > 1)
                TextButton.icon(
                  onPressed: () => showExprSheet(context, app, expr, widget.ctx!, expr.phrase.split(' ')),
                  icon: const Icon(Icons.menu_book_outlined, size: 18),
                  label: Text(L('Anlamlar ve örnekler', 'Meanings and examples')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class SentenceText extends StatelessWidget {
  final String sentence;
  final String? word;
  final Set<String>? highlight;
  final bool lockHighlight;
  const SentenceText(this.sentence, this.word, {this.highlight, this.lockHighlight = false});

  @override
  Widget build(BuildContext context) => TapText(sentence, style: const TextStyle(fontSize: 16, height: 1.45), highlight: highlight ?? {word!.toLowerCase()}, lockHighlight: lockHighlight);
}

/// "V1 find · V2 found · V3 found" under an irregular verb's header, with the
/// form the learner tapped in bold. "be" has two V2 forms (was / were).
class VerbFormsRow extends StatelessWidget {
  final List<String> forms; // V1, V2..., V3
  final String tapped;
  const VerbFormsRow({super.key, required this.forms, required this.tapped});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = enStyle(theme, theme.textTheme.titleMedium);
    final groups = [
      ('V1', [forms.first]),
      ('V2', forms.sublist(1, forms.length - 1)),
      ('V3', [forms.last]),
    ];
    final spans = <InlineSpan>[];
    for (final (label, words) in groups) {
      if (spans.isNotEmpty) spans.add(const TextSpan(text: '    '));
      spans.add(
        TextSpan(
          text: '$label ',
          style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700),
        ),
      );
      for (var i = 0; i < words.length; i++) {
        if (i > 0)
          spans.add(
            TextSpan(
              text: ' / ',
              style: base.copyWith(color: theme.hintColor),
            ),
          );
        final on = words[i] == tapped;
        spans.add(
          TextSpan(
            text: words[i],
            style: on ? base.copyWith(fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface) : base.copyWith(fontWeight: FontWeight.w400, color: theme.colorScheme.onSurfaceVariant),
          ),
        );
      }
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Text.rich(TextSpan(children: spans), key: const ValueKey('verb-forms')),
    );
  }
}
