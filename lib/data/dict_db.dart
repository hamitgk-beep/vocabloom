import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../l10n.dart';
import '../nlp/text.dart';
import 'contrib_verified.dart';

class Sense {
  final int synId;
  final String pos;
  final String gloss;
  final List<String> examples;
  final List<String> synonyms;
  final List<String> tr;
  /// Turkish of [examples], same order; may be shorter or empty.
  final List<String> examplesTr;
  Sense(this.synId, this.pos, this.gloss, this.examples, this.synonyms, this.tr, [this.examplesTr = const []]);
}

class WordInfo {
  final String lemma;

  /// Turkish meanings from checked sources only, most trusted first: verified
  /// contributions, then the kept Wiktionary part (keep_tr) and the main list (ft).
  final List<String> trFreeDict;
  final List<Sense> senses;

  /// Turkish of unreviewed AI drafts (own_word, reviewed = 0). Never part of
  /// [trFreeDict]; shown only as labelled suggestions (see [DictDb.sourcePolicy]).
  final List<String> trDraft;
  WordInfo(this.lemma, this.trFreeDict, this.senses, [this.trDraft = const []]);
  bool get isEmpty => trFreeDict.isEmpty && senses.isEmpty && trDraft.isEmpty;
}

/// A dictionary word a written word can stand for ([DictDb.baseForms]), and
/// the parts of speech ('n', 'v', 'a', 'r') that reading allows; null: any.
class BaseForm {
  final String lemma;
  final Set<String>? pos;
  const BaseForm(this.lemma, this.pos);

  @override
  String toString() => pos == null ? lemma : '$lemma(${pos!.join()})';
}

/// How far a meaning can be trusted. One order for every screen:
/// verified contribution > trusted source (ft, WordNet, expr, exd) > AI draft.
enum SourceTier { verified, trusted, draft }

Map<String, String> get posNames => uiEnglish
    ? const {'n': 'noun', 'v': 'verb', 'a': 'adjective', 'r': 'adverb'}
    : const {'n': 'isim', 'v': 'fiil', 'a': 'sıfat', 'r': 'zarf'};

/// Read-only bundled dictionary. Turkish word meanings (`ft`, read as
/// [WordInfo.trFreeDict]) come from Wiktionary and damdafayton/eng-tur-dictionary
/// (tools/main_meanings.py); WordNet gives English senses and base forms.
class DictDb {
  static const _version = '36';

  /// Version of the bundled dictionary; part of the context-meaning cache
  /// keys and of the "wrong meaning" reports.
  static const version = _version;

  /// A Turkish meaning damaged when it was built: a label glued inside a
  /// word ("de(sigortacılık)ns", "tıp(kısaltma)ı").
  static bool badMeaning(String tr) => RegExp(r'[a-zçğıöşü]\([^)]*\)[a-zçğıöşü]').hasMatch(tr.toLowerCase());
  late final Database db;
  late final Lemmatizer lemmatizer;
  late final PhraseMatcher matcher;
  late final List<Expr> exprs;
  final Map<int, Expr> exprById = {};

  static Future<DictDb> open(Directory dir) async {
    final file = File(p.join(dir.path, 'dict_v$_version.db'));
    // Remove copies of older dictionary versions.
    for (final f in dir.listSync().whereType<File>()) {
      final n = p.basename(f.path);
      if (n.startsWith('dict_v') && n.endsWith('.db') && f.path != file.path) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
    if (!file.existsSync() || file.lengthSync() < 1000000) {
      final data = await rootBundle.load('assets/dict.db');
      await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
    }
    final d = DictDb();
    d.db = sqlite3.open(file.path, mode: OpenMode.readOnly);
    d.load();
    return d;
  }

  /// Irregular verbs: base form -> [V1, V2..., V3] ("be" -> be, was, were, been).
  final Map<String, List<String>> irregular = {};

  /// V2/V3 form -> base forms of the irregular verbs it belongs to ("found" -> find).
  final Map<String, List<String>> irregularOf = {};

  void load({bool ownEnabled = useOwnDictionary}) {
    _ownOn = ownEnabled;
    irregular.clear();
    irregularOf.clear();
    final known = <String>{};
    for (final r in db.select('SELECT DISTINCT lemma FROM sense')) {
      known.add(r.columnAt(0) as String);
    }
    for (final r in db.select('SELECT word FROM ft')) {
      known.add(r.columnAt(0) as String);
    }
    final exc = <String, List<String>>{};
    for (final r in db.select('SELECT form, lemma, pos FROM exc')) {
      exc.putIfAbsent(r.columnAt(0) as String, () => []).add(r.columnAt(1) as String);
      _excPos.putIfAbsent(r.columnAt(0) as String, () => []).add((r.columnAt(1) as String, r.columnAt(2) as String?));
    }
    lemmatizer = Lemmatizer(known, exc);
    exprs = [];
    final forms = <int, List<String>>{};
    final cols = {for (final r in db.select('PRAGMA table_info(expr)')) r['name'] as String};
    final hasEx = cols.contains('ex'), hasEnTr = cols.contains('entr');
    // Own expression meanings (own_expr): a verified row replaces the Turkish gloss;
    // an unreviewed AI draft only fills [Expr.trDraft] ([sourcePolicy]).
    final ownExpr = <String, String>{};
    final draftExpr = <String>{};
    if (ownEnabled && db.select("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'own_expr'").isNotEmpty) {
      final rev = db.select('PRAGMA table_info(own_expr)').any((r) => r['name'] == 'reviewed');
      for (final r in db.select('SELECT phrase, cat, senses${rev ? ', reviewed, status' : ''} FROM own_expr')) {
        final k = '${r.columnAt(0)}|${r.columnAt(1)}';
        ownExpr[k] = r.columnAt(2) as String;
        if (rev && !verifiedRow(r['reviewed'], r['status'])) draftExpr.add(k);
      }
    }
    for (final r in db.select('SELECT id, phrase, cat, tr, en, forms${hasEx ? ', ex' : ''}${hasEnTr ? ', entr, extr' : ''} FROM expr')) {
      var trOwn = r['tr'] as String?;
      String? trDraft;
      final key = '${r['phrase']}|${r['cat']}';
      final own = ownExpr[key];
      if (own != null) {
        final senses = tiered(jsonDecode(own) as List, !draftExpr.contains(key), 'e:$key');
        List<String> trs(bool draft) => [
              for (final x in senses)
                if (x.$3 == draft) (x.$2['tr'] as String? ?? '').trim(),
            ].where((x) => x.isNotEmpty).toList();
        final t = trs(false), d = trs(true);
        if (t.isNotEmpty) trOwn = t.join(', ');
        if (d.isNotEmpty) trDraft = d.join(', ');
      }
      if (trOwn != null && trOwn.trim().isEmpty) trOwn = null;
      final e = Expr(r['id'] as int, r['phrase'] as String, r['cat'] as String, trOwn,
          r['en'] as String?, patternOf(r['phrase'] as String),
          ex: hasEx ? r['ex'] as String? : null, enTr: hasEnTr ? r['entr'] as String? : null, exTr: hasEnTr ? r['extr'] as String? : null)
        ..trDraft = trDraft;
      if (e.pattern.isEmpty) continue;
      exprs.add(e);
      exprById[e.id] = e;
      final f = r['forms'] as String?;
      if (f != null) forms[e.id] = (jsonDecode(f) as List).cast<String>();
      if (f != null && e.cat == 'irregular_verbs') {
        final vf = forms[e.id]!;
        if (vf.length >= 3) {
          irregular[e.phrase] = vf;
          for (final x in vf.skip(1)) {
            if (x != e.phrase) irregularOf.putIfAbsent(x, () => []).add(e.phrase);
          }
        }
      }
    }
    matcher = PhraseMatcher(lemmatizer, exprs, forms)..posOf = posOf;
  }

  late final bool _hasExTr = db.select('PRAGMA table_info(syn)').any((r) => r['name'] == 'extr');

  /// Source priority: verified contributions, then the sourced dictionaries
  /// (ft, WordNet, expr, exd), then unreviewed AI drafts. Drafts are never
  /// deleted, promoted or written anywhere; they are only kept out of the main
  /// meanings. False brings back the order before this policy, where any own row
  /// (draft or not) replaced ft, expr and exd. Only tests change it, before
  /// opening a [DictDb].
  static bool sourcePolicy = true;

  /// Version of [sourcePolicy]; part of the context-meaning cache key, so a
  /// meaning chosen under the old order is not reused.
  static String get policyVersion => sourcePolicy ? 'src1' : 'src0';

  /// A row of own_word / own_expr is a verified contribution: the user checked it.
  static bool verifiedRow(Object? reviewed, Object? status) => reviewed == 1 && status != 'ai_draft_unreviewed';

  /// The senses of an own row with their tier: (index in the row, sense, is an AI
  /// draft). A verified row is verified throughout. In an AI draft row a sense is
  /// verified only when it is marked src "storilex" AND matches a contribution
  /// record ([contribVerified], tools/contrib/verified_senses.py); the label alone
  /// is not enough. An idiom whose AI wording got the contributed one added
  /// ("draft, contributed") is split: the contributed parts verified, the rest a
  /// draft. "api_review" is an AI check, not a person's: a draft. [key] is
  /// "w:word" or "e:phrase|cat".
  static List<(int, Map<String, dynamic>, bool)> tiered(List senses, bool rowVerified, String key) {
    final out = <(int, Map<String, dynamic>, bool)>[];
    for (var i = 0; i < senses.length; i++) {
      final s = (senses[i] as Map).cast<String, dynamic>();
      if (!sourcePolicy || rowVerified) {
        out.add((i, s, false));
        continue;
      }
      final v = s['src'] == 'storilex' ? contribVerified['$key#$i'] : null;
      if (v == null || v.$1 != s['tr']) {
        out.add((i, s, true));
        continue;
      }
      out.add((i, {...s, 'tr': v.$2}, false));
      String n(String t) => t.trim().toLowerCase();
      final mine = {for (final t in v.$2.split(RegExp('[,;]'))) n(t)};
      final rest = [for (final t in '${s['tr']}'.split(RegExp('[,;]'))) if (t.trim().isNotEmpty && !mine.contains(n(t))) t.trim()];
      if (rest.isNotEmpty) out.add((i, {...s, 'tr': rest.join(', '), 'src': null, 'more': null}, true));
    }
    return out;
  }

  late final bool _ownHasReview = _hasOwnWord &&
      db.select('PRAGMA table_info(own_word)').any((r) => r['name'] == 'reviewed');

  final Map<String, SourceTier?> _tierCache = {};

  /// Tier of [lemma]'s own_word row: verified, draft, or null (no row).
  SourceTier? ownTier(String lemma) => _tierCache.putIfAbsent(lemma, () {
        if (!useOwnDictionary || !_hasOwnWord) return null;
        if (!_ownHasReview) {
          return db.select('SELECT 1 FROM own_word WHERE word = ?', [lemma]).isEmpty ? null : SourceTier.verified;
        }
        final r = db.select('SELECT reviewed, status FROM own_word WHERE word = ?', [lemma]);
        if (r.isEmpty) return null;
        return verifiedRow(r.first['reviewed'], r.first['status']) ? SourceTier.verified : SourceTier.draft;
      });

  /// [tiered] senses of [lemma]'s own_word row (empty without a row).
  List<(int, Map<String, dynamic>, bool)> ownWordTiered(String lemma) {
    if (!useOwnDictionary || !_hasOwnWord) return const [];
    final r = db.select('SELECT senses FROM own_word WHERE word = ?', [lemma]);
    if (r.isEmpty) return const [];
    try {
      return tiered(jsonDecode(r.first.columnAt(0) as String) as List, ownTier(lemma) != SourceTier.draft, 'w:$lemma');
    } catch (_) {
      return const [];
    }
  }

  /// Off until the own-dictionary tables have been checked on a copy of the database.
  /// While it is off, the app shows exactly the meanings it shows today.
  static const bool useOwnDictionary = true;

  late final bool _hasOwnWord = db
      .select("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'own_word'")
      .isNotEmpty;

  /// [ownEnabled] defaults to [useOwnDictionary] (false in the app). Only tests pass it.
  WordInfo lookup(String lemma, {bool ownEnabled = useOwnDictionary}) {
    // [sourcePolicy] on: a verified own row first, then keep_tr (the Wiktionary part
    // that stays) and ft; an AI draft row never replaces them and goes to trDraft.
    // Off (the order before): keep_tr and the own senses of any row, ft only without them.
    var tr = <String>[];
    var draft = <String>[];
    var added = <String>[];
    var verified = false;
    if (ownEnabled && _hasOwnWord) {
      final own = db.select('SELECT senses, keep_tr${_ownHasReview ? ', reviewed, status' : ''} FROM own_word WHERE word = ?', [lemma]);
      if (own.isNotEmpty) {
        final keep = (jsonDecode(own.first.columnAt(1) as String) as List).cast<String>();
        final rowOk = !_ownHasReview || verifiedRow(own.first['reviewed'], own.first['status']);
        final all = [
          for (final s in tiered(jsonDecode(own.first.columnAt(0) as String) as List, rowOk, 'w:$lemma'))
            if ('${s.$2['tr'] ?? ''}'.trim().isNotEmpty) s,
        ];
        final checked = [for (final s in all) if (!s.$3) '${s.$2['tr']}'];
        if (!sourcePolicy) {
          tr = [...keep, ...checked];
        } else {
          draft = [for (final s in all) if (s.$3) '${s.$2['tr']}'];
          verified = checked.isNotEmpty;
          if (rowOk) {
            tr = [...checked, ...keep.where((t) => !checked.contains(t))];
          } else {
            // A draft row's checked senses are meanings users added to it
            // ("book": "sarı kart göstermek"): kept, after the dictionary's
            // own first meanings rather than in their place.
            tr = keep;
            added = checked;
          }
        }
      }
    }
    if (tr.isEmpty || (sourcePolicy && (verified || draft.isNotEmpty))) {
      final ft = db.select('SELECT tr FROM ft WHERE word = ?', [lemma]);
      final ftTr = ft.isEmpty ? <String>[] : (jsonDecode(ft.first.columnAt(0) as String) as List).cast<String>();
      tr = [...tr, ...ftTr.where((t) => !tr.contains(t))];
    }
    tr = [...tr, ...added.where((t) => !tr.contains(t))];
    final senses = <Sense>[];
    for (final r in db.select(
        'SELECT s.id, s.pos, s.gloss, s.examples, s.words, s.tr${_hasExTr ? ', s.extr' : ''} FROM sense x JOIN syn s ON s.id = x.syn_id '
        'WHERE x.lemma = ? ORDER BY x.rank, s.pos',
        [lemma])) {
      senses.add(Sense(
        r['id'] as int,
        r['pos'] as String,
        r['gloss'] as String,
        (jsonDecode(r['examples'] as String) as List).cast<String>(),
        (jsonDecode(r['words'] as String) as List).cast<String>().where((w) => w != lemma).toList(),
        r['tr'] == null ? const [] : (jsonDecode(r['tr'] as String) as List).cast<String>(),
        !_hasExTr || r['extr'] == null ? const [] : (jsonDecode(r['extr'] as String) as List).cast<String>(),
      ));
    }
    return WordInfo(lemma, tr, senses, draft);
  }

  /// The own dictionary's senses of [lemma] in its order: part of speech
  /// (Turkish label: isim, fiil …), Turkish meaning, usage note, English
  /// definition (empty on older rows) and an example with its Turkish.
  /// Empty when it has none.
  /// Under [sourcePolicy] only verified contributions: an AI draft's senses are
  /// read with [draftSenses] instead.
  List<OwnSense> ownSenses(String lemma) => _ownSenses(lemma, draft: false);

  /// The unreviewed AI draft senses of [lemma] (empty when the row is verified,
  /// missing, or [sourcePolicy] is off). Shown only in a closed, labelled section.
  List<OwnSense> draftSenses(String lemma) => _ownSenses(lemma, draft: true);

  List<OwnSense> _ownSenses(String lemma, {required bool draft}) {
    try {
      return [
        for (final (_, x, d) in ownWordTiered(lemma))
          if ('${x['tr'] ?? ''}'.trim().isNotEmpty && d == draft)
            // Older rows have no "ex": their "en" is the example, not a definition.
            '${x['ex'] ?? ''}'.trim().isEmpty
                ? OwnSense('${x['pos'] ?? ''}'.trim(), '${x['tr']}'.trim(), '${x['note'] ?? ''}'.trim(), '',
                    '${x['en'] ?? ''}'.trim(), '${x['ex_tr'] ?? ''}'.trim())
                : OwnSense('${x['pos'] ?? ''}'.trim(), '${x['tr']}'.trim(), '${x['note'] ?? ''}'.trim(),
                    '${x['en'] ?? ''}'.trim(), '${x['ex']}'.trim(), '${x['ex_tr'] ?? ''}'.trim()),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Lesk-style choice of the sense that best fits the sentence.
  final Map<String, Set<String>> _posCache = {};

  /// Parts of speech WordNet knows for [word] (any inflected form).
  late final bool _hasExd =
      db.select("SELECT 1 FROM sqlite_master WHERE type='table' AND name='exd'").isNotEmpty;

  bool _ownOn = useOwnDictionary;
  late final bool _hasOwnExpr =
      db.select("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'own_expr'").isNotEmpty;

  /// Own senses as the expression sheet reads them. An own sense has a Turkish meaning, a Turkish
  /// usage note and an English example with its translation. When the row has the newer shape
  /// (ex = English example, en = short English definition) the definition is shown; otherwise the
  /// old shape (en = example) gives only the example. Nothing is invented: missing parts stay empty.
  String _ownExprDetail(String raw) {
    final out = <Map<String, Object>>[];
    for (final x in jsonDecode(raw) as List) {
      final m = (x as Map).cast<String, dynamic>();
      final tr = (m['tr'] as String? ?? '').trim();
      if (tr.isEmpty) continue;
      final ex = (m['ex'] as String? ?? '').trim();
      final en = (m['en'] as String? ?? '').trim();
      final hasEx = ex.isNotEmpty;
      final definition = hasEx ? en : '';
      final example = hasEx ? ex : en;
      out.add({
        'title_en': definition.isNotEmpty ? definition : tr,
        'title_tr': tr,
        'explain_en': '',
        'explain_tr': '',
        'in_sentence': false,
        'examples': [
          if (example.isNotEmpty) {'en': example, 'tr': (m['ex_tr'] as String? ?? '').trim()},
        ],
      });
    }
    return jsonEncode(out);
  }

  /// Built-in senses of an expression (Turkish + English, with translated
  /// examples), as JSON in the same shape the AI service returns. Null when
  /// this dictionary has none for it.
  ///
  /// Under [sourcePolicy] only a verified own row comes before exd; an AI draft is
  /// never returned here (see [exprDraftDetail]).
  String? exprDetail(String phrase, String cat) {
    // Own meanings first (own_expr), in the same shape as the built-in library.
    final own = _ownExprRow(phrase, cat);
    if (own != null && own.$2 == null) return _ownExprDetail(own.$1);
    final r = _hasExd ? db.select('SELECT json FROM exd WHERE phrase=? AND cat=?', [phrase, cat]) : const <Row>[];
    final exd = r.isEmpty ? null : r.first.columnAt(0) as String;
    // A draft row with meanings the user contributed: those first, then exd.
    final mine = own == null ? const [] : [for (final s in tiered(jsonDecode(own.$1) as List, false, 'e:$phrase|$cat')) if (!s.$3) s.$2];
    if (mine.isEmpty) return exd;
    final head = jsonDecode(_ownExprDetail(jsonEncode(mine))) as List;
    final titles = {for (final x in head) '${(x as Map)['title_tr']}'};
    return jsonEncode([
      ...head,
      if (exd != null)
        for (final x in jsonDecode(exd) as List)
          if (!titles.contains('${(x as Map)['title_tr']}')) x,
    ]);
  }

  /// The unreviewed AI draft senses of an expression, in the [exprDetail] shape, or
  /// null. Shown only in a closed, labelled section; never a verified meaning.
  String? exprDraftDetail(String phrase, String cat) {
    final own = _ownExprRow(phrase, cat);
    if (own == null || own.$2 == null) return null;
    final d = [for (final s in tiered(jsonDecode(own.$1) as List, false, 'e:$phrase|$cat')) if (s.$3) s.$2];
    return d.isEmpty ? null : _ownExprDetail(jsonEncode(d));
  }

  late final bool _ownExprHasReview =
      _hasOwnExpr && db.select('PRAGMA table_info(own_expr)').any((r) => r['name'] == 'reviewed');

  /// (senses JSON, `true` when it is an AI draft row under [sourcePolicy], null
  /// when the whole row counts) of the expression's own row, or null.
  (String, bool?)? _ownExprRow(String phrase, String cat) {
    if (!_ownOn || !_hasOwnExpr) return null;
    final r = db.select('SELECT senses${_ownExprHasReview ? ', reviewed, status' : ''} FROM own_expr WHERE phrase=? AND cat=?', [phrase, cat]);
    if (r.isEmpty) return null;
    final draft = sourcePolicy && _ownExprHasReview && !verifiedRow(r.first['reviewed'], r.first['status']);
    return (r.first.columnAt(0) as String, draft ? true : null);
  }

  late final bool _hasExs =
      db.select("SELECT 1 FROM sqlite_master WHERE type='table' AND name='exs'").isNotEmpty;

  /// Example sentences with Turkish translations (Tatoeba) for an expression
  /// ("phrase|cat") or a word ("w:lemma").
  List<(String, String)> examples(String key, {int limit = 4}) {
    if (!_hasExs) return const [];
    return [
      for (final r in db.select('SELECT en, tr FROM exs WHERE key=? LIMIT ?', [key, limit]))
        (r.columnAt(0) as String, r.columnAt(1) as String)
    ];
  }

  late final bool _hasWd =
      db.select("SELECT 1 FROM sqlite_master WHERE type='table' AND name='wd'").isNotEmpty;

  /// Built-in teacher-style explanation of [lemma]: (main Turkish, senses JSON), or null.
  (String, String)? wordDetail(String lemma) {
    if (!_hasWd) return null;
    final r = db.select('SELECT tr, json FROM wd WHERE word=?', [lemma]);
    return r.isEmpty ? null : (r.first.columnAt(0) as String, r.first.columnAt(1) as String);
  }

  late final bool _hasWfd =
      db.select("SELECT 1 FROM sqlite_master WHERE type='table' AND name='wfd'").isNotEmpty;

  /// Built-in detailed word family of [lemma] (same JSON as WordFamily.toJsonString).
  String? familyDetail(String lemma) {
    if (!_hasWfd) return null;
    final r = db.select('SELECT w.json FROM fam f JOIN famg g ON g.id=f.gid JOIN wfd w ON w.root=g.root WHERE f.word=?', [lemma]);
    return r.isEmpty ? null : r.first.columnAt(0) as String;
  }

  final Map<String, Set<String>> _lemmaPosCache = {};

  /// Parts of speech of a lemma itself ('n', 'v', 'a', 'r'), not of its other forms.
  Set<String> lemmaPos(String lemma) => _lemmaPosCache.putIfAbsent(lemma, () {
        final out = <String>{};
        for (final r in db.select('SELECT DISTINCT pos FROM sense WHERE lemma=?', [lemma])) {
          final p = r.columnAt(0) as String;
          out.add(p == 's' ? 'a' : p);
        }
        return out;
      });

  final Map<String, bool> _hasMeaningCache = {};

  /// Whether the dictionary has a meaning for [lemma] itself (a WordNet sense
  /// or a main Turkish meaning).
  bool hasMeaning(String lemma) => _hasMeaningCache.putIfAbsent(lemma, () {
        if (db.select('SELECT 1 FROM sense WHERE lemma=? LIMIT 1', [lemma]).isNotEmpty) return true;
        return db.select("SELECT 1 FROM ft WHERE word=? AND tr != '[]'", [lemma]).isNotEmpty;
      });

  /// How many times more often than its base form a written form must be met
  /// before it counts as a word of its own ("according" against "accord",
  /// "born" against "bear"). An ordinary plural or past form is often as
  /// common as its base ("things", "used"), so "as common" is not enough.
  static const double ownWordRatio = 3;

  static const _sRules = [
    ['ies', 'y'], ['ves', 'f'], ['ves', 'fe'], ['ses', 's'], ['xes', 'x'], ['zes', 'z'],
    ['ches', 'ch'], ['shes', 'sh'], ['men', 'man'], ['es', 'e'], ['es', ''], ['s', ''],
  ];
  static const _verbRules = [['ied', 'y'], ['ed', 'e'], ['ed', ''], ['ying', 'ie'], ['ing', 'e'], ['ing', '']];
  static const _adjRules = [['ier', 'y'], ['iest', 'y'], ['er', 'e'], ['est', 'e'], ['er', ''], ['est', '']];
  static const _directionWords = {'up', 'down', 'off', 'out', 'away', 'back', 'on', 'over', 'in', 'around', 'about', 'through'};
  static const _lyRules = [['ily', 'y'], ['ly', '']];

  final Map<String, List<BaseForm>> _baseFormCache = {};

  bool _ownNounOrVerb(String w) {
    final p = lemmaPos(w);
    return p.contains('n') || p.contains('v');
  }

  /// Whether the other degree of a comparative or superlative is a word met
  /// in text ("longer" → "longest", "biggest" → "bigger").
  bool _otherDegreeMet(String w) {
    final other = w.endsWith('est') ? '${w.substring(0, w.length - 3)}er' : w.endsWith('er') ? '${w.substring(0, w.length - 2)}est' : null;
    return other != null && (_freq[other] ?? 0) > 0;
  }

  final Map<String, List<(String, String?)>> _excPos = {};

  /// The dictionary words a written word can stand for, the most likely
  /// first, each with the parts of speech its ending allows.
  ///
  /// An ending says what the base is: "-ing" and "-ed" are put on verbs,
  /// "-s" on nouns and verbs, "-er" and "-est" on adjectives and adverbs. So
  /// "thing" is not "the", "letter" is not "let" and "writer" is not
  /// "write"; and "training" can be the verb "train" but never the noun
  /// (a train). "-ly" makes another word, so "only" is itself.
  ///
  /// The word panel, the hover bubble and the context picker all use this
  /// list, so they name the same word. ([Lemmatizer.lemmas] stays the wide
  /// list for finding expressions, grammar and saved words.)
  List<BaseForm> baseForms(String lower) => _baseFormCache.putIfAbsent(lower, () {
        var w = lower.replaceAll('’', "'");
        if (w.endsWith("'s")) w = w.substring(0, w.length - 2);
        final out = <BaseForm>[];
        void add(String l, Set<String>? pos) {
          if (l.isEmpty || !hasMeaning(l)) return;
          final i = out.indexWhere((b) => b.lemma == l);
          if (i < 0) {
            out.add(BaseForm(l, pos));
          } else if (out[i].pos != null) {
            // Reached two ways ("leaves": leaf, leave): either reading holds.
            out[i] = BaseForm(l, pos == null ? null : {...out[i].pos!, ...pos});
          }
        }

        final irregular = irregularOf[w] != null && !this.irregular.containsKey(w);
        if (irregular) {
          for (final l in irregularOf[w]!) {
            add(l, const {'v'});
          }
        }
        // Listed irregular forms, each with the part of speech it is listed
        // for ("leaves": the noun leaf; "better": the adjective good).
        for (final (l, p) in _excPos[w] ?? const <(String, String?)>[]) {
          if (l == w) continue;
          final cmp = p == 'a' || p == 'r';
          if (cmp && (stopWords.contains(l) || _directionWords.contains(l))) continue;
          add(l, p == null ? null : (cmp ? const {'a', 'r'} : {p}));
        }
        void rules(List<List<String>> rs, Set<String> allowed) {
          for (final r in rs) {
            if (w.length <= r[0].length + 1 || !w.endsWith(r[0])) continue;
            final base = w.substring(0, w.length - r[0].length) + r[1];
            final bases = [
              base,
              // stopped -> stopp -> stop
              if (r[1].isEmpty && base.length > 2 && base[base.length - 1] == base[base.length - 2]) base.substring(0, base.length - 1),
            ];
            for (final b in bases) {
              if (b.length < 2) continue;
              // "-es" with nothing put back is the plural after "o" only
              // ("goes", "heroes"); "sites" is not "sit".
              if (r[0] == 'es' && r[1].isEmpty && !b.endsWith('o')) continue;
              // Grammar and direction words are not compared ("offer" is
              // not "off", "upper" not "up").
              if (identical(rs, _adjRules) && (stopWords.contains(b) || _directionWords.contains(b))) continue;
              // A noun or verb of its own in "-er" / "-est" is a comparison
              // only if the other degree is met too: "longer" (longest),
              // but not "customer", "owner", "buffer", "opener".
              if (identical(rs, _adjRules) && _ownNounOrVerb(w) && !_otherDegreeMet(w)) continue;
              final pos = lemmaPos(b).intersection(allowed);
              if (pos.isNotEmpty) add(b, pos);
            }
          }
        }

        // Grammar words take no endings ("as" is not "a", "its" is not "it");
        // their irregular forms are listed above ("was" is "be").
        if (!stopWords.contains(w)) {
          if (!w.endsWith('ss')) rules(_sRules, const {'n', 'v'});
          rules(_verbRules, const {'v'});
          rules(_adjRules, const {'a', 'r'});
        }
        final self = hasMeaning(w);
        if (!self) {
          for (final r in _lyRules) {
            if (w.length <= r[0].length + 1 || !w.endsWith(r[0])) continue;
            final b = w.substring(0, w.length - r[0].length) + r[1];
            if (lemmaPos(b).contains('a')) add(b, null);
          }
        }
        if (self) {
          final first = out.firstOrNull;
          // A word of its own: nothing it could be a form of, or far more
          // common than that base.
          final own = first == null || (!irregular && (_freq[w] ?? 0) >= ownWordRatio * (_freq[first.lemma] ?? 0) && (_freq[w] ?? 0) > 0);
          out.removeWhere((b) => b.lemma == w);
          own ? out.insert(0, BaseForm(w, null)) : out.add(BaseForm(w, null));
        }
        return out;
      });

  /// The dictionary word a written word is shown under: the first of
  /// [baseForms], or the word itself when the dictionary knows none.
  String headword(String lower) => baseForms(lower).firstOrNull?.lemma ?? lower.replaceAll('’', "'");

  Set<String> posOf(String word) => _posCache.putIfAbsent(word, () {
        final out = <String>{};
        for (final l in lemmatizer.lemmas(word)) {
          for (final r in db.select('SELECT DISTINCT pos FROM sense WHERE lemma=?', [l])) {
            final p = r.columnAt(0) as String;
            out.add(p == 's' ? 'a' : p);
          }
        }
        return out;
      });

  /// A two-word dictionary entry the word forms with its neighbour in the
  /// sentence ("golf course", "course of action"), or null.
  WordInfo? compoundAt(List<Token> sentence, int tokenIndex, String lemma) {
    final cands = <String>[
      if (tokenIndex > 0) ...lemmatizer.lemmas(sentence[tokenIndex - 1].lower).map((l) => '$l $lemma'),
      if (tokenIndex > 0) '${sentence[tokenIndex - 1].lower} $lemma',
      if (tokenIndex + 1 < sentence.length) '$lemma ${sentence[tokenIndex + 1].lower}',
    ];
    for (final c in cands) {
      if (c.split(' ').any((w) => stopWords.contains(w) || w.length < 2)) continue;
      final i = lookup(c);
      if (!i.isEmpty) return i;
    }
    return null;
  }

  Sense? bestSense(WordInfo info, List<Token> sentence, int tokenIndex) {
    if (info.senses.isEmpty) return null;
    final pos = guessPos(sentence, tokenIndex, info.senses.map((s) => s.pos == 's' ? 'a' : s.pos).toSet(), posOf: posOf);
    final ctx = <String>{};
    for (var i = 0; i < sentence.length; i++) {
      if (i == tokenIndex) continue;
      final w = sentence[i].lower;
      if (stopWords.contains(w) || w.length < 3) continue;
      ctx.addAll(lemmatizer.lemmas(w));
    }
    // "golf course": the compound's own definition tells which sense of
    // "course" this is (an area laid out for a sport, not a series of lessons).
    final comp = tokenIndex < sentence.length ? compoundAt(sentence, tokenIndex, info.lemma) : null;
    if (comp != null) {
      for (final s in comp.senses.take(2)) {
        for (final t in tokenize(s.gloss)) {
          if (stopWords.contains(t.lower) || t.lower.length < 3 || t.lower == info.lemma) continue;
          ctx.addAll(lemmatizer.lemmas(t.lower));
        }
      }
    }
    Sense? best;
    var bestScore = -1e9;
    for (var k = 0; k < info.senses.length; k++) {
      final s = info.senses[k];
      final bag = tokenize('${s.gloss} ${s.examples.join(' ')} ${s.synonyms.join(' ')}')
          .expand((t) => lemmatizer.lemmas(t.lower))
          .toSet();
      var score = bag.intersection(ctx).length * 2.0;
      if (pos != null && (s.pos == pos || (pos == 'a' && s.pos == 's'))) score += 6;
      score -= k * 0.15; // WordNet order roughly follows frequency
      if (s.tr.isNotEmpty) score += 0.3;
      if (score > bestScore) {
        bestScore = score;
        best = s;
      }
    }
    return best;
  }

  /// Index of the token in [sentence] that is a form of [lemma], or -1.
  int indexOfLemma(List<Token> sentence, String lemma) {
    for (var i = 0; i < sentence.length; i++) {
      final w = sentence[i].lower;
      if (w == lemma || lemmatizer.lemmas(w).contains(lemma)) return i;
    }
    return -1;
  }

  /// What [lemma] means in [sentence]: the WordNet sense that fits it and a
  /// Turkish meaning that is known to belong to that sense. [tr] is null when
  /// the dictionary has no Turkish for the sense used here; it never falls
  /// back to an unrelated meaning ("course" in "golf course" is not "akmak").
  ({Sense? sense, String? tr, String? pos, bool sure}) meaningIn(String lemma, String? sentence) {
    final raw = lookup(lemma);
    // Cross references ("bakınız: joust") are not meanings.
    final info = WordInfo(raw.lemma, raw.trFreeDict.where((t) => !t.toLowerCase().contains('bakınız')).toList(), raw.senses);
    final toks = sentence == null ? const <Token>[] : tokenize(sentence);
    final i = indexOfLemma(toks, lemma);
    if (i < 0) {
      // No sentence to go by: the word's most common meaning.
      final s = info.senses.firstOrNull;
      final tr = info.trFreeDict.isNotEmpty
          ? shortTr(info.trFreeDict.first)
          : info.senses.where((s) => s.tr.isNotEmpty).map((s) => s.tr.take(3).join(', ')).firstOrNull;
      // The part of speech follows the meaning shown: WordNet's first sense
      // of "fall" is the noun (autumn) but its first meaning is "düşmek".
      final sPos = s == null ? null : normPos(s.pos);
      final pos = tr == null
          ? sPos
          : isTrVerb(tr)
              ? 'v'
              : (sPos == 'v' ? null : sPos);
      return (sense: s, tr: tr, pos: pos, sure: true);
    }
    final comp = compoundAt(toks, i, lemma);
    final best = bestSense(info, toks, i);
    final pos = best == null ? null : normPos(best.pos);
    if (comp != null) {
      final ctr = comp.senses.where((s) => s.tr.isNotEmpty).map((s) => s.tr.take(2).join(', ')).firstOrNull ??
          (comp.trFreeDict.isNotEmpty ? shortTr(comp.trFreeDict.first) : null);
      if (ctr != null) return (sense: best, tr: ctr, pos: pos ?? 'n', sure: true);
    }
    if (best == null) {
      final f = info.trFreeDict.isEmpty ? null : shortTr(info.trFreeDict.first);
      return (sense: null, tr: f, pos: f != null && isTrVerb(f) ? 'v' : null, sure: true);
    }
    if (best.tr.isNotEmpty) return (sense: best, tr: best.tr.take(3).join(', '), pos: pos, sure: true);

    // The sense has no Turkish of its own. FreeDict's meanings are not tied
    // to senses, so one is matched to the sense through the Turkish of the
    // sense's synonyms ("simply" = "merely, just" -> "ancak, sadece").
    final samePos = info.trFreeDict.where((t) => isTrVerb(t) == (pos == 'v')).toList();
    final synTr = <String>{};
    final synFirst = <String>[];
    for (final w in best.synonyms.take(6)) {
      if (w.contains(' ') && w.split(' ').length > 3) continue;
      final si = lookup(w.toLowerCase());
      final mine = [
        ...si.senses.where((x) => normPos(x.pos) == pos && x.tr.isNotEmpty).map((x) => x.tr.take(3).join(', ')),
        ...si.trFreeDict.where((t) => isTrVerb(t) == (pos == 'v')),
      ];
      if (mine.isNotEmpty) synFirst.add(mine.first);
      for (final t in mine.take(4)) {
        synTr.addAll(_parts(t));
      }
    }
    if (synTr.isNotEmpty) {
      String? pick;
      var bestHit = 0;
      for (final t in samePos) {
        final hit = _parts(t).where(synTr.contains).length;
        if (hit > bestHit) {
          bestHit = hit;
          pick = t;
        }
      }
      if (pick != null) return (sense: best, tr: shortTr(pick), pos: pos, sure: true);
    }
    // The word's main sense for this part of speech: FreeDict's first meaning
    // of that part of speech is that sense.
    final first = info.senses.firstWhere((s) => normPos(s.pos) == pos);
    if (identical(first, best) && samePos.isNotEmpty) {
      return (sense: best, tr: shortTr(samePos.first), pos: pos, sure: true);
    }
    // A rarer sense: the Turkish of its synonym, otherwise the best guess
    // (marked unsure, so the AI service is asked when there is one).
    if (synFirst.isNotEmpty) return (sense: best, tr: shortTr(synFirst.first), pos: pos, sure: false);
    final guess = info.senses.where((s) => normPos(s.pos) == pos && s.tr.isNotEmpty).map((s) => s.tr.take(3).join(', ')).firstOrNull ??
        (samePos.isNotEmpty ? samePos.first : info.trFreeDict.firstOrNull);
    return (sense: best, tr: guess == null ? null : shortTr(guess), pos: pos, sure: false);
  }

  static const _ownPos = {'isim': 'n', 'özel isim': 'n', 'fiil': 'v', 'deyimsel fiil': 'v', 'sıfat': 'a', 'zarf': 'r'};

  /// The word's most common meaning, whatever sentence it was met in: the
  /// first meaning of the own dictionary (its senses are listed most common
  /// first), otherwise the dictionary's first meaning. Review cards ask this
  /// one ("through" is "boyunca", even when it was saved from "a through train").
  ({String? tr, String? pos, String? gloss}) commonMeaning(String lemma) {
    // A draft row's checked senses are user contributions added to it ("book":
    // "sarı kart göstermek"), not its most common meaning, so they do not
    // lead here; only a reviewed row's order does.
    final ownLeads = !sourcePolicy || ownTier(lemma) != SourceTier.draft;
    final own = ownLeads ? ownSenses(lemma).where((s) => !s.tr.toLowerCase().contains('bakınız')).firstOrNull : null;
    if (own != null) {
      final tr = shortTr(own.tr);
      // Prepositions, conjunctions …: no WordNet part of speech, so the
      // wrong options are picked by the shape of the Turkish (not verbs).
      final pos = _ownPos[own.pos] ?? (isTrVerb(tr) ? 'v' : null);
      return (tr: tr, pos: pos, gloss: own.en.isEmpty ? null : own.en);
    }
    final m = meaningIn(lemma, null);
    if (m.tr == null) {
      // Nothing checked has Turkish for it: the AI draft, as the only meaning there is.
      final d = draftSenses(lemma).where((s) => !s.tr.toLowerCase().contains('bakınız')).firstOrNull;
      if (d != null) {
        final tr = shortTr(d.tr);
        return (tr: tr, pos: _ownPos[d.pos] ?? (isTrVerb(tr) ? 'v' : null), gloss: d.en.isEmpty ? m.sense?.gloss : d.en);
      }
    }
    return (tr: m.tr, pos: m.pos, gloss: m.sense?.gloss);
  }

  /// Turkish word -> the KeNet synsets (id, part of speech) it is a meaning of.
  late final Map<String, List<(int, String)>> _trSyn = () {
    final m = <String, List<(int, String)>>{};
    for (final r in db.select("SELECT id, pos, tr FROM syn WHERE tr IS NOT NULL AND tr != '[]'")) {
      final e = (r['id'] as int, normPos(r['pos'] as String));
      for (final t in (jsonDecode(r['tr'] as String) as List).cast<String>()) {
        (m[t.toLowerCase().trim()] ??= []).add(e);
      }
    }
    return m;
  }();

  /// Whether the Turkish meanings [a] and [b] say the same thing: they share
  /// a part ("kurs, ders" and "ders"), or a part of each is listed as a meaning
  /// of one and the same KeNet synset ("istemek" and "arzu etmek"), which is
  /// a hand-made synonym set. [pos] (n, v, a, r) limits it to synsets of that
  /// part of speech, so a noun and a verb that only look alike are not joined.
  /// No spelling similarity is used.
  bool sameTr(String a, String b, {String? pos}) => trLink(a, b, pos: pos) != null;

  /// How [sameTr] holds: 'same' (a shared part), 'synonym' (one synset), or null.
  String? trLink(String a, String b, {String? pos}) {
    final pa = _parts(a).toSet(), pb = _parts(b).toSet();
    if (pa.intersection(pb).isNotEmpty) return 'same';
    final p = pos == null ? null : normPos(pos);
    final ids = <int>{
      for (final x in pa)
        for (final e in _trSyn[x] ?? const <(int, String)>[])
          if (p == null || e.$2 == p) e.$1,
    };
    if (ids.isEmpty) return null;
    for (final x in pb) {
      for (final e in _trSyn[x] ?? const <(int, String)>[]) {
        if (ids.contains(e.$1)) return 'synonym';
      }
    }
    return null;
  }

  static Iterable<String> _parts(String t) =>
      t.toLowerCase().split(RegExp(r'[,;]')).map((e) => e.trim()).where((e) => e.length > 1);

  static String normPos(String p) => p == 's' ? 'a' : p;

  /// Whether a Turkish meaning is a verb ("akmak, hızla akmak").
  static bool isTrVerb(String tr) {
    final first = tr.split(RegExp(r'[,;]')).first.trim().toLowerCase();
    if (_mekNouns.contains(first)) return false;
    return RegExp(r'(mak|mek)$').hasMatch(first);
  }

  /// Common Turkish nouns that end like a verb.
  static const _mekNouns = {
    'ırmak', 'ekmek', 'yemek', 'parmak', 'çakmak', 'kaymak', 'damak', 'tokmak', 'yamak', 'kaşmak', 'kıymak',
    'kaynak', 'başmak', 'çömlek', 'emek', 'kepmek', 'sırmak', 'yumak', 'tımak', 'çekmek',
  };

  /// A meaning short enough for an answer button: its first two parts.
  static String shortTr(String s) {
    final parts = s.split(RegExp(r'[,;]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return parts.isEmpty ? s.trim() : parts.take(2).join(', ');
  }

  /// Every Turkish meaning the dictionary has for [lemma], lowercased words.
  Set<String> trWordsOf(String lemma) {
    final info = lookup(lemma);
    final out = <String>{};
    // Drafts too: this set keeps wrong answer options away from any meaning of the word.
    for (final t in [...info.trFreeDict, ...info.trDraft, for (final s in info.senses) ...s.tr]) {
      for (final p in t.toLowerCase().split(RegExp(r'[,;]'))) {
        final x = p.trim();
        if (x.isNotEmpty) out.add(x);
      }
    }
    return out;
  }

  /// Clean Turkish sense meanings of one part of speech, for wrong answers:
  /// main senses of words people meet often, so the wrong options look like
  /// ordinary answers rather than rare technical terms.
  List<String> randomSenseTr(String? pos, {int limit = 200}) {
    final posSql = pos == null ? '' : pos == 'a' ? "AND s.pos IN ('a','s')" : 'AND s.pos = ?';
    List<String> run(String sql) => [
          for (final r in db.select(sql, [if (pos != null && pos != 'a') pos, limit]))
            if ((jsonDecode(r.columnAt(0) as String) as List).isNotEmpty)
              (jsonDecode(r.columnAt(0) as String) as List).cast<String>().take(2).join(', ')
        ];
    final hasFreq = db.select("SELECT 1 FROM sqlite_master WHERE type='table' AND name='wfreq'").isNotEmpty;
    final out = hasFreq
        ? run('SELECT s.tr FROM sense x JOIN syn s ON s.id = x.syn_id JOIN wfreq f ON f.word = x.lemma '
            "WHERE s.tr IS NOT NULL AND s.tr != '[]' AND x.rank < 2 AND f.n >= 100 $posSql ORDER BY random() LIMIT ?")
        : <String>[];
    if (out.length >= 20) return out;
    return out + run("SELECT s.tr FROM syn s WHERE s.tr IS NOT NULL AND s.tr != '[]' $posSql ORDER BY random() LIMIT ?");
  }

  /// Meanings that are no good as an answer option: cross references
  /// ("bakınız: keep"), numbers, names, crude words.
  static bool badOption(String tr) {
    final t = tr.trim();
    if (t.isEmpty || t.length > 40) return true;
    final l = t.toLowerCase();
    if (l.contains('bakınız') || l.contains('bkz') || l.contains('see ')) return true;
    if (RegExp(r'\d').hasMatch(t)) return true;
    if (t.split(RegExp(r'[,;]')).any((p) => RegExp(r'^[A-ZÇĞİÖŞÜ]').hasMatch(p.trim()))) return true;
    const crude = ['göt', 'kıç', 'mastürbasyon', 'orospu', 'piç', 'sikiş', 'seks', 'cinsel', 'zampara', 'fahişe', 'meme'];
    return l.split(RegExp(r'[ ,;]+')).any(crude.contains) || l.contains('mastürbasyon');
  }

  /// Single words starting with [prefix] (letters, ' and - only), the most
  /// frequent first, for the dictionary search. An exact match comes first.
  /// Text with Turkish letters (ç, ğ, ı, ö, ş, ü) is not English: no words.
  List<String> searchWords(String prefix, {int limit = 40, int offset = 0}) {
    final raw = prefix.trim().toLowerCase();
    if (RegExp('[çğıöşüâîûİ]').hasMatch(raw)) return const [];
    final q = raw.replaceAll(RegExp(r"[^a-z'\-]"), '');
    if (q.isEmpty) return const [];
    return [
      for (final r in db.select(
          'SELECT w FROM (SELECT word AS w FROM ft WHERE word GLOB ?1 '
          'UNION SELECT word FROM wfreq WHERE word GLOB ?1 AND EXISTS (SELECT 1 FROM sense s WHERE s.lemma = word)) '
          "LEFT JOIN wfreq f ON f.word = w WHERE w NOT GLOB '* *' "
          'ORDER BY (w = ?2) DESC, IFNULL(f.n, 0) DESC, w LIMIT ?3 OFFSET ?4',
          ['$q*', q, limit, offset]))
        r.columnAt(0) as String
    ];
  }

  /// Names and grammar words that top the frequency counts but make a poor
  /// start for a word list ("tom", "the", "of"); still found by search.
  static const _skipCommon = {
    'tom', 'mary', 'sami', 'boston', 'john', 'layla', 'i', 'a', 'an', 'the', 'to', 'of', 'in', 'on', 'at', 'by', 'for', 'from',
    'with', 'about', 'into', 'over', 'off', 'up', 'out', 'down', 'and', 'or', 'but', 'so', 'if', 'than', 'as', 'that', 'this',
    'these', 'those', 'it', 'he', 'she', 'we', 'you', 'they', 'me', 'him', 'her', 'us', 'them', 'my', 'your', 'his', 'our',
    'their', 'its', 'himself', 'do', 'does', 'did', 'done', 'be', 'is', 'are', 'was', 'were', 'been', 'being', 'have', 'has',
    'had', 'can', 'could', 'will', 'would', 'shall', 'should', 'may', 'might', 'must', 'not', 'no', 'what', 'how', 'why',
    'when', 'where', 'who', 'there', 'here', 'just', 'too', 'very', 'any', 'some', 'both', 'because', 'while', 'yet', 'even',
  };

  /// The single words met most often in books that have a Turkish meaning,
  /// most frequent first: what the dictionary tab lists before anything is
  /// typed (grammar words and names left out).
  List<String> commonWords({int limit = 100, int offset = 0}) {
    final out = <String>[];
    var skipped = 0;
    for (final r in db.select(
        "SELECT f.word FROM wfreq f WHERE f.word NOT GLOB '* *' AND f.word GLOB '[a-z][a-z]*' "
        "AND (EXISTS (SELECT 1 FROM ft WHERE ft.word = f.word AND ft.tr != '[]') "
        "OR EXISTS (SELECT 1 FROM sense x JOIN syn s ON s.id = x.syn_id WHERE x.lemma = f.word AND s.tr IS NOT NULL AND s.tr != '[]')) "
        'ORDER BY f.n DESC, f.word LIMIT ?',
        [offset + limit + _skipCommon.length])) {
      final w = r.columnAt(0) as String;
      if (_skipCommon.contains(w)) continue;
      if (skipped++ < offset) continue;
      out.add(w);
      if (out.length >= limit) break;
    }
    return out;
  }

  /// Lower case without Turkish accents, so "kopek" finds "köpek" and
  /// "Işık" finds "ışık".
  static String foldTr(String s) {
    const from = 'çğıöşüâîû';
    const to = 'cgiosuaiu';
    final l = s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();
    final b = StringBuffer();
    for (final ch in l.split('')) {
      final i = from.indexOf(ch);
      b.write(i < 0 ? ch : to[i]);
    }
    return b.toString();
  }

  /// (English word, Turkish meaning, folded meaning) for every single word
  /// with a Turkish meaning; built the first time someone searches in Turkish.
  late final List<(String, String, String)> _trIndex = () {
    final out = <(String, String, String)>[];
    void add(String w, String json) {
      if (w.contains(' ')) return;
      for (final m in (jsonDecode(json) as List).cast<String>()) {
        final t = m.trim();
        if (t.isNotEmpty) out.add((w, t, foldTr(t)));
      }
    }

    for (final r in db.select("SELECT word, tr FROM ft WHERE tr != '[]'")) {
      add(r.columnAt(0) as String, r.columnAt(1) as String);
    }
    for (final r in db.select("SELECT x.lemma, s.tr FROM sense x JOIN syn s ON s.id = x.syn_id "
        "WHERE s.tr IS NOT NULL AND s.tr != '[]' AND x.rank < 4")) {
      add(r.columnAt(0) as String, r.columnAt(1) as String);
    }
    return out;
  }();

  late final Map<String, int> _freq = {
    for (final r in db.select('SELECT word, n FROM wfreq')) r.columnAt(0) as String: r.columnAt(1) as int,
  };

  /// Single words the dictionary has a meaning for (Turkish or WordNet).
  late final Set<String> _headwords = {
    for (final r in db.select("SELECT word FROM ft WHERE word NOT GLOB '* *'")) r.columnAt(0) as String,
    for (final r in db.select("SELECT DISTINCT lemma FROM sense WHERE lemma NOT GLOB '* *'")) r.columnAt(0) as String,
  };

  static const _abc = 'abcdefghijklmnopqrstuvwxyz';

  static Iterable<String> _edits1(String w) sync* {
    for (var i = 0; i <= w.length; i++) {
      final a = w.substring(0, i), b = w.substring(i);
      if (b.isNotEmpty) yield a + b.substring(1); // delete
      if (b.length > 1) yield a + b[1] + b[0] + b.substring(2); // swap
      for (var k = 0; k < _abc.length; k++) {
        final c = _abc[k];
        if (b.isNotEmpty && c != b[0]) yield a + c + b.substring(1); // replace
        yield a + c + b; // insert
      }
    }
  }

  /// The dictionary word a misspelt [word] most likely stands for
  /// ("overwhelmn" → overwhelm), or null. One letter off for words of 4 to 6
  /// letters, up to two for longer ones; the most common candidate wins.
  String? closestWord(String word) {
    final w = word.toLowerCase();
    if (w.length < 4 || !RegExp(r"^[a-z]+$").hasMatch(w) || _headwords.contains(w) || _freq.containsKey(w)) {
      return null; // a real word the dictionary lacks ("gonna") is not a typo
    }
    String? pick(Iterable<String> cands) {
      String? best;
      var bestN = -1;
      for (final c in cands) {
        if (c.length < 3 || !_headwords.contains(c)) continue;
        final n = _freq[c] ?? 0;
        if (n > bestN || (n == bestN && best != null && c.compareTo(best) < 0)) {
          best = c;
          bestN = n;
        }
      }
      return best;
    }

    final one = _edits1(w).toSet();
    final p1 = pick(one);
    if (p1 != null || w.length < 7) return p1;
    // Two letters off: only common words, so a long rare word is not taken
    // for a different one.
    final p2 = pick({for (final e in one) ..._edits1(e)});
    return p2 != null && (_freq[p2] ?? 0) > 0 ? p2 : null;
  }

  /// Turkish to English: English words whose Turkish meaning is [text] or
  /// starts with it, with the meaning that matched. Words whose meaning is
  /// exactly the text come first ("kitap" → book), then the common ones.
  List<(String, String)> searchTurkish(String text, {int limit = 40}) =>
      [for (final (w, m, _) in searchTurkishScored(text, limit: limit)) (w, m)];

  /// [searchTurkish] with how well each meaning matched: 0 or 1 = the text
  /// is one of the meanings, higher = a meaning only starts with it.
  List<(String, String, int)> searchTurkishScored(String text, {int limit = 40}) {
    final q = foldTr(text.trim()).replaceAll(RegExp(r'\s+'), ' ');
    if (q.length < 2) return const [];
    final wordStart = RegExp('(^|[^a-z])${RegExp.escape(q)}');
    final best = <String, (int, String)>{};
    for (final (w, m, f) in _trIndex) {
      if (!f.contains(q)) continue;
      int? score;
      for (final part in f.split(RegExp(r'[,;()]'))) {
        final p = part.trim();
        if (p == q) {
          score = 0;
          break;
        }
        if (p.startsWith(q)) {
          final next = p.length > q.length ? p[q.length] : ' ';
          final s = next == ' ' ? 2 : 3;
          if (score == null || s < score) score = s;
        } else if (wordStart.hasMatch(p)) {
          score ??= 4;
        }
      }
      // Some meanings carry English derived words ("worrisome üzücü"): a
      // partial match on an English word is not a Turkish match.
      if (score != null && score >= 2) {
        final hit = RegExp('(?:^|[^a-z])(${RegExp.escape(q)}[a-z]*)').firstMatch(f)?.group(1);
        if (hit != null && lemmatizer.known.contains(hit)) continue;
      }
      // A meaning that is one short word ("kitap") beats a long description.
      if (score == null) continue;
      if (score == 0 && f != q) score = 1;
      final old = best[w];
      if (old == null || score < old.$1) best[w] = (score, m);
    }
    final words = best.keys.toList()
      ..sort((a, b) {
        final c = best[a]!.$1.compareTo(best[b]!.$1);
        if (c != 0) return c;
        final d = (_freq[b] ?? 0).compareTo(_freq[a] ?? 0);
        return d != 0 ? d : a.length.compareTo(b.length);
      });
    return [for (final w in words.take(limit)) (w, best[w]!.$2, best[w]!.$1)];
  }

  /// The expressions of [cat] met most often in books, most frequent first
  /// (alphabetical when the dictionary has no counts).
  List<Expr> commonExprs(String cat, {int limit = 8}) {
    final byPhrase = {for (final e in exprs) if (e.cat == cat) e.phrase: e};
    final hasFreq = db.select("SELECT 1 FROM sqlite_master WHERE type='table' AND name='exfreq'").isNotEmpty;
    final out = <Expr>[
      if (hasFreq)
        for (final r in db.select('SELECT phrase FROM exfreq WHERE cat = ? ORDER BY n DESC LIMIT ?', [cat, limit * 2]))
          ?byPhrase[r.columnAt(0) as String],
    ];
    if (out.length < limit) out.addAll(byCategory(cat).where((e) => !out.contains(e)).take(limit - out.length));
    return out.take(limit).toList();
  }

  List<Expr> byCategory(String cat) => exprs.where((e) => e.cat == cat).toList()
    ..sort((a, b) => a.phrase.compareTo(b.phrase));
}

/// One sense of the own dictionary (see [DictDb.ownSenses]).
class OwnSense {
  final String pos, tr, note, en, ex, exTr;
  const OwnSense(this.pos, this.tr, this.note, this.en, this.ex, this.exTr);
}
