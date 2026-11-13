import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/user_db.dart';
import '../nlp/text.dart';
import '../online/ai_service.dart';
import '../online/update_check.dart';
import '../l10n.dart';
import 'word_sheet.dart';

// ------------------------------------------------------------------ words
class WordsPage extends StatelessWidget {
  final AppState app;
  const WordsPage({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(L('Kelimelerim', 'My words')),
          bottom: TabBar(tabs: [Tab(text: L('Öğreneceğim', 'To learn')), Tab(text: L('Öğrendim', 'Learned'))]),
        ),
        body: ListenableBuilder(
          listenable: app,
          builder: (context, _) => TabBarView(children: [
            _WordList(app: app, status: WordStatus.learning),
            _WordList(app: app, status: WordStatus.learned),
          ]),
        ),
      ),
    );
  }
}

class _WordList extends StatelessWidget {
  final AppState app;
  final WordStatus status;
  const _WordList({required this.app, required this.status});

  @override
  Widget build(BuildContext context) {
    final words = app.user.words(status);
    final theme = Theme.of(context);
    final color = status == WordStatus.learning ? learningColor : learnedColor;
    if (words.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            status == WordStatus.learning
                ? L('Okurken bir kelimeye dokunup "Öğreneceğim" dediğinde burada görünür ve kitapta turuncu işaretlenir.', 'When you tap a word while reading and choose "To learn", it shows up here and is marked orange in the book.')
                : L('"Öğrendim" dediğin kelimeler burada toplanır ve kitapta yeşil işaretlenir.', 'Words you mark as "Learned" are collected here and marked green in the book.'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: words.length,
      itemBuilder: (c, i) {
        final w = words[i];
        final meaning = w.meaning ?? app.shortMeaning(w.lemma);
        return Card(
          child: ListTile(
            leading: Container(width: 6, height: 40, color: color),
            title: Text(w.lemma, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (meaning != null) Text(meaning, maxLines: 2, overflow: TextOverflow.ellipsis),
              if (w.context != null)
                Text('“${w.context}”', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontStyle: FontStyle.italic, color: theme.hintColor)),
              if (w.bookTitle != null) Text(w.bookTitle!, style: theme.textTheme.bodySmall),
            ]),
            trailing: IconButton(
              tooltip: status == WordStatus.learning ? L('Öğrendim', 'Learned') : L('Tekrar öğreneceğim', 'Learn again'),
              icon: Icon(status == WordStatus.learning ? Icons.check_circle_outline : Icons.replay),
              onPressed: () => app.setWord(w.lemma, status == WordStatus.learning ? WordStatus.learned : WordStatus.learning),
            ),
            onTap: () {
              final isPhrase = w.lemma.contains(' ');
              if (isPhrase) {
                final e = app.dict.exprs.where((e) => e.phrase == w.lemma).firstOrNull;
                if (e != null) {
                  showModalBottomSheet(
                    context: context,
                    showDragHandle: true,
                    builder: (_) => Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), child: StatefulBuilder(builder: (c, set) => ExprCard(app: app, expr: e, onChanged: () => set(() {})))),
                  );
                  return;
                }
              }
              showWordSheet(context, app, w.lemma, lemma: w.lemma);
            },
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------------ categories + dictionary
class CategoriesPage extends StatefulWidget {
  final AppState app;
  const CategoriesPage({super.key, required this.app});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  final search = TextEditingController();

  void _lookup(String q) {
    q = q.trim().toLowerCase();
    if (q.isEmpty) return;
    final e = widget.app.dict.exprs.where((e) => e.phrase == q).firstOrNull;
    if (e != null && q.contains(' ')) {
      showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (_) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: StatefulBuilder(builder: (c, set) => ExprCard(app: widget.app, expr: e, onChanged: () => set(() {})))),
      );
      return;
    }
    showWordSheet(context, widget.app, q);
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final counts = <String, int>{};
    for (final e in app.dict.exprs) {
      counts[e.cat] = (counts[e.cat] ?? 0) + 1;
    }
    return Scaffold(
      appBar: AppBar(title: Text(L('Sözlük ve kategoriler', 'Dictionary and categories'))),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        TextField(
          controller: search,
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: L('Sözlükte ara (kelime veya kalıp)', 'Search the dictionary (word or expression)'),
            border: OutlineInputBorder(),
          ),
          onSubmitted: _lookup,
        ),
        const SizedBox(height: 12),
        for (final c in categories)
          Card(
            child: ListTile(
              leading: CircleAvatar(backgroundColor: c.color.withValues(alpha: 0.18), child: Icon(Icons.label, color: c.color)),
              title: Text(uiEnglish ? c.name : '${c.name} · ${c.tr}'),
              subtitle: Text(c.desc),
              trailing: Text('${counts[c.id] ?? 0}'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _CategoryList(app: app, cat: c))),
            ),
          ),
      ]),
    );
  }
}

class _CategoryList extends StatefulWidget {
  final AppState app;
  final CategoryInfo cat;
  const _CategoryList({required this.app, required this.cat});

  @override
  State<_CategoryList> createState() => _CategoryListState();
}

class _CategoryListState extends State<_CategoryList> {
  String q = '';
  late final List<Expr> all = widget.app.dict.byCategory(widget.cat.id);

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final list = q.isEmpty ? all : all.where((e) => e.phrase.contains(q) || (e.trShown?.toLowerCase().contains(q) ?? false)).toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.cat.name)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: InputDecoration(prefixIcon: Icon(Icons.search), hintText: L('Ara', 'Search'), border: OutlineInputBorder()),
            onChanged: (v) => setState(() => q = v.toLowerCase()),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (c, i) {
              final e = list[i];
              final st = app.user.statuses[e.phrase];
              return ListTile(
                title: Text(e.phrase, style: TextStyle(fontWeight: FontWeight.w600, color: widget.cat.color)),
                subtitle: Text([if (app.showTr && e.trShown != null) e.trShown!, if ((app.showEn || e.trShown == null) && e.en != null) e.en!].join('\n'), maxLines: 3),
                trailing: st == null ? null : Icon(Icons.circle, size: 12, color: st == WordStatus.learning ? learningColor : learnedColor),
                onTap: () => showModalBottomSheet(
                  context: context,
                  showDragHandle: true,
                  builder: (_) => Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      child: StatefulBuilder(builder: (c, set) => ExprCard(app: app, expr: e, onChanged: () {
                            set(() {});
                            setState(() {});
                          }))),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------------ settings
class SettingsPage extends StatefulWidget {
  final AppState app;
  const SettingsPage({super.key, required this.app});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late String providerId = AiSettings.activeId(widget.app.user) ?? 'anthropic';
  final key = TextEditingController();
  final model = TextEditingController();
  final url = TextEditingController();
  bool obscure = true;
  String? testResult;
  bool testing = false;

  @override
  void initState() {
    super.initState();
    _loadFields();
  }

  void _loadFields() {
    final u = widget.app.user;
    final p = providerById[providerId]!;
    key.text = u.getSetting('ai_key_$providerId') ?? (providerId == 'anthropic' ? u.getSetting('api_key') ?? '' : '');
    model.text = u.getSetting('ai_model_$providerId') ?? p.defaultModel;
    url.text = u.getSetting('ai_url_$providerId') ?? p.baseUrl;
    testResult = null;
  }

  void _save() {
    final u = widget.app.user;
    u.setSetting('ai_provider', providerId);
    u.setSetting('ai_key_$providerId', key.text.trim().isEmpty ? null : key.text.trim());
    u.setSetting('ai_model_$providerId', model.text.trim().isEmpty ? null : model.text.trim());
    u.setSetting('ai_url_$providerId', url.text.trim().isEmpty ? null : url.text.trim());
  }

  Future<void> _test() async {
    _save();
    final svc = AiService.fromSettings(widget.app.user);
    if (svc == null) {
      setState(() => testResult = L('Eksik bilgi var (anahtar, model veya adres).', 'Some information is missing (key, model or address).'));
      return;
    }
    setState(() {
      testing = true;
      testResult = null;
    });
    try {
      final r = await svc.translateChunk(['The weather is lovely today.']);
      setState(() => testResult = L('Çalışıyor ✓  "${r.translations.firstOrNull ?? ''}"', 'Working ✓  "${r.translations.firstOrNull ?? ''}"'));
      widget.app.analyzer.tick();
    } catch (e) {
      setState(() => testResult = L('Hata: $e', 'Error: $e'));
    } finally {
      if (mounted) setState(() => testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final u = app.user;
    final theme = Theme.of(context);
    final p = providerById[providerId]!;
    final showUrl = p.kind == ApiKind.azure || p.id == 'custom' || p.id == 'ollama' || p.id == 'openrouter';
    return Scaffold(
      appBar: AppBar(title: Text(L('Ayarlar', 'Settings'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Uygulama dili / App language', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Türkçe')),
            ButtonSegment(value: true, label: Text('English')),
          ],
          selected: {app.englishUi},
          onSelectionChanged: (s) => app.setUiEnglish(s.first),
        ),
        const SizedBox(height: 4),
        Text(L('Menüler, düğmeler ve açıklamalar bu dilde gösterilir.', 'Menus, buttons and explanations are shown in this language.'),
            style: TextStyle(color: theme.hintColor, fontSize: 13)),
        const SizedBox(height: 20),
        Text(L('Görünüm', 'Appearance'), style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<ThemeMode>(
          segments: [
            ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode), label: Text(L('Gündüz', 'Day'))),
            ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode), label: Text(L('Gece', 'Night'))),
            ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto), label: Text(L('Sistem', 'System'))),
          ],
          selected: {app.themeMode},
          onSelectionChanged: (s) => app.setTheme(s.first),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(L('Anlam dili', 'Meaning language')),
          subtitle: Text(L('Kelime panelinde Türkçe, İngilizce veya ikisi birden.', 'Turkish, English or both in the word panel.')),
          trailing: LangToggles(app: app, onChanged: () => setState(() {})),
        ),
        const Divider(height: 32),
        Text(L('Yapay zekâ (isteğe bağlı, internet gerekir)', 'AI (optional, needs internet)'), style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          L('Bağladığın servis, internet olduğu her an henüz taranmamış kitapları tarar: her cümlenin Türkçe çevirisi ve bölüm özetleri cihazına kaydedilir ve bir daha taranmaz. Yarıda kalırsa kaldığı yerden devam eder. Taranmış (resim) PDF\'lerde cihazda OCR yoksa sayfaları da okuyabilir. Kullanım ücreti kendi hesabından düşer.', 'Whenever there is an internet connection, the service you connect scans books that have not been scanned yet: a Turkish translation of every sentence and chapter summaries are saved on your device and never scanned again. If it stops halfway, it continues where it left off. For scanned (image) PDFs it can also read the pages when the device has no OCR. Usage is billed to your own account.'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: providerId,
          isExpanded: true,
          decoration: InputDecoration(labelText: L('Servis', 'Service'), border: OutlineInputBorder()),
          items: [for (final x in providers) DropdownMenuItem(value: x.id, child: Text(x.name))],
          onChanged: (v) => setState(() {
            _save();
            providerId = v!;
            _loadFields();
            u.setSetting('ai_provider', providerId);
          }),
        ),
        if (p.keyHelp.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(p.keyHelp, style: theme.textTheme.bodySmall)),
        const SizedBox(height: 12),
        if (showUrl) ...[
          TextField(
            controller: url,
            decoration: InputDecoration(
              labelText: p.kind == ApiKind.azure ? L('Uç nokta (https://<kaynak>.openai.azure.com)', 'Endpoint (https://<resource>.openai.azure.com)') : 'Adres (base URL)',
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => _save(),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: key,
          obscureText: obscure,
          decoration: InputDecoration(
            labelText: p.needsKey ? L('API anahtarı', 'API key') : L('API anahtarı (gerekmiyorsa boş bırak)', 'API key (leave empty if not needed)'),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(icon: Icon(obscure ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => obscure = !obscure)),
          ),
          onChanged: (_) => _save(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: model,
          decoration: InputDecoration(
            labelText: p.kind == ApiKind.azure ? L('Dağıtım (deployment) adı', 'Deployment name') : L('Model adı', 'Model name'),
            helperText: L('Servisin model listesinden istediğini yazabilirsin. Varsayılan: ${p.defaultModel}', 'You can enter any model from the service\'s list. Default: ${p.defaultModel}'),
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => _save(),
        ),
        const SizedBox(height: 8),
        Row(children: [
          FilledButton.tonalIcon(
            onPressed: testing ? null : _test,
            icon: testing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi_tethering),
            label: Text(L('Bağlantıyı dene', 'Test connection')),
          ),
        ]),
        if (testResult != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(testResult!)),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(L('İnternet olunca kitapları otomatik tara', 'Scan books automatically when online')),
          subtitle: Text(L('Kitaplar çevrilir, sonra sözlükte yalnızca İngilizce açıklaması olan kalıplar Türkçeye çevrilip cihaza kaydedilir. Kapalıysa kitap menüsünden elle başlatabilirsin.', 'Books are translated first; then dictionary entries that only have an English definition are translated into Turkish and saved on the device. When off, you can start it from the book menu.')),
          value: u.getSetting('auto_analyze') != '0',
          onChanged: (v) => setState(() {
            u.setSetting('auto_analyze', v ? null : '0');
            if (v) app.analyzer.tick();
          }),
        ),
        ValueListenableBuilder<String?>(
          valueListenable: app.analyzer.dictStatus,
          builder: (context, s, _) => s == null
              ? const SizedBox.shrink()
              : Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(s, style: theme.textTheme.bodySmall)),
        ),
        if (!p.vision)
          Text(L('Not: ${p.name} resimdeki yazıyı okuyamaz; taranmış PDF için cihazın kendi OCR\'ı kullanılır.', 'Note: ${p.name} cannot read text in images; the device\'s own OCR is used for scanned PDFs.'),
              style: theme.textTheme.bodySmall),
        const Divider(height: 32),
        Text(L('Hakkında', 'About'), style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(L('VocaBloom, Hamit Gök tarafından geliştirildi.', 'VocaBloom was developed by Hamit Gök.')),
        Text(appBuild == 0 ? L('Sürüm: geliştirme derlemesi', 'Version: development build') : L('Sürüm: 1.0 (derleme $appBuild)', 'Version: 1.0 (build $appBuild)'), style: theme.textTheme.bodySmall),
        const Divider(height: 32),
        Text(L('Veriler ve lisanslar', 'Data and licenses'), style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          L('Tüm kitapların, kelime listen ve ayarların yalnızca bu cihazda saklanır. API anahtarları da yalnızca cihazda tutulur ve sadece seçtiğin servise gönderilir.\n\nSözlük kaynakları:\n', 'All your books, your word list and your settings are stored only on this device. API keys are also kept only on the device and are sent only to the service you choose.\n\nDictionary sources:\n') +
          '• FreeDict English–Turkish (GPL-2.0+)\n'
          '• Princeton WordNet 3.0 (WordNet License)\n'
          '• KeNet Turkish WordNet, Starlang / Özyeğin University (CC BY-SA 4.0)\n'
          '• Collaborative Interlingual Index (CC BY 4.0)\n'
          '• Wiktionary expressions via kaikki.org (CC BY-SA 4.0)\n' +
          L('• Kategori listeleri bu uygulama için hazırlandı (CC BY-SA 4.0).', '• Category lists written for this app (CC BY-SA 4.0).'),
        ),
      ]),
    );
  }
}
