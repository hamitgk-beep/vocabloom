import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/user_db.dart';
import '../nlp/text.dart';
import '../online/ai_service.dart';
import '../online/update_check.dart';
import '../l10n.dart';
import 'expr_sheet.dart';
import 'panel.dart';
import 'review_page.dart';
import 'theme.dart';
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
          toolbarHeight: 68,
          title: Text(L('Kelimelerim', 'My words'), style: Theme.of(context).textTheme.headlineSmall),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: ListenableBuilder(
              listenable: app,
              builder: (context, _) {
                final st = app.user.statuses.values;
                final n1 = st.where((s) => s == WordStatus.learning).length;
                final n2 = st.where((s) => s == WordStatus.learned).length;
                final theme = Theme.of(context);
                Widget tab(String t, int n, Color c) => Tab(
                      height: 40,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Text(t),
                        const SizedBox(width: 6),
                        Text('$n', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
                      ]),
                    );
                return Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
                  child: TabBar(tabs: [
                    tab(L('Öğreneceğim', 'To learn'), n1, learningColor),
                    tab(L('Öğrendim', 'Learned'), n2, learnedColor),
                  ]),
                );
              },
            ),
          ),
        ),
        body: ListenableBuilder(
          listenable: app,
          builder: (context, _) => Column(children: [
            if (app.user.statuses.containsValue(WordStatus.learning))
              Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 6), child: ReviewBanner(app: app)),
            Expanded(
              child: TabBarView(children: [
                _WordList(app: app, status: WordStatus.learning),
                _WordList(app: app, status: WordStatus.learned),
              ]),
            ),
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
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(24)),
              child: Icon(status == WordStatus.learning ? Icons.bookmark_add_rounded : Icons.verified_rounded, size: 36, color: color),
            ),
            const SizedBox(height: 16),
            Text(
            status == WordStatus.learning
                ? L('Okurken bir kelimeye dokunup "Öğreneceğim" dediğinde burada görünür ve kitapta turuncu işaretlenir.', 'When you tap a word while reading and choose "To learn", it shows up here and is marked orange in the book.')
                : L('"Öğrendim" dediğin kelimeler burada toplanır ve kitapta yeşil işaretlenir.', 'Words you mark as "Learned" are collected here and marked green in the book.'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.5),
          ),
          ]),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: words.length,
      itemBuilder: (c, i) {
        final w = words[i];
        final meaning = w.meaning ?? app.shortMeaning(w.lemma);
        return Card(
          child: InkWell(
            onTap: () {
              final isPhrase = w.lemma.contains(' ');
              if (isPhrase) {
                final e = app.dict.exprs.where((e) => e.phrase == w.lemma).firstOrNull;
                if (e != null) {
                  showExprSheet(context, app, e, null);
                  return;
                }
              }
              showWordSheet(context, app, w.lemma, lemma: w.lemma);
            },
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(width: 4, color: color),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(w.lemma, style: enStyle(theme, theme.textTheme.titleMedium).copyWith(fontWeight: FontWeight.w700)),
                      if (meaning != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(meaning, maxLines: 2, overflow: TextOverflow.ellipsis, style: trStyle(theme, theme.textTheme.bodyMedium)),
                        ),
                      if (w.context != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('“${w.context}”',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontFamily: readingFont, fontStyle: FontStyle.italic, fontSize: 13.5, height: 1.4, color: theme.colorScheme.onSurfaceVariant)),
                        ),
                      if (w.bookTitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(children: [
                            Icon(Icons.auto_stories_outlined, size: 13, color: theme.colorScheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Flexible(child: Text(w.bookTitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
                          ]),
                        ),
                    ]),
                  ),
                ),
                Center(
                  child: IconButton(
                    tooltip: status == WordStatus.learning ? L('Öğrendim', 'Learned') : L('Tekrar öğreneceğim', 'Learn again'),
                    icon: Icon(status == WordStatus.learning ? Icons.check_circle_outline_rounded : Icons.replay_rounded,
                        color: status == WordStatus.learning ? learnedColor : theme.colorScheme.onSurfaceVariant),
                    onPressed: () => app.setWord(w.lemma, status == WordStatus.learning ? WordStatus.learned : WordStatus.learning),
                  ),
                ),
                const SizedBox(width: 4),
              ]),
            ),
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
      showExprSheet(context, widget.app, e, null);
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
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final cols = width >= 1100 ? 3 : width >= 640 ? 2 : 1;
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    return Scaffold(
      appBar: AppBar(toolbarHeight: 68, title: Text(L('Sözlük', 'Dictionary'), style: theme.textTheme.headlineSmall)),
      body: CustomScrollView(slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          sliver: SliverToBoxAdapter(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: L('Kelime veya kalıp ara', 'Search a word or expression'),
                  suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward_rounded), onPressed: () => _lookup(search.text)),
                ),
                onSubmitted: _lookup,
              ),
              SectionLabel(L('Kalıp kategorileri · $total ifade', 'Expression categories · $total entries')),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisExtent: 92, crossAxisSpacing: 10, mainAxisSpacing: 0),
            delegate: SliverChildBuilderDelegate(childCount: categories.length, (context, i) {
              final c = categories[i];
              final cc = theme.brightness == Brightness.dark ? Color.lerp(c.color, Colors.white, 0.3)! : c.color;
              return Card(
                child: InkWell(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _CategoryList(app: app, cat: c))),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
                    child: Row(children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: c.color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(12)),
                        alignment: Alignment.center,
                        child: Text(c.name.substring(0, 1), style: TextStyle(color: cc, fontWeight: FontWeight.w800, fontSize: 19)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(uiEnglish ? c.name : c.tr, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontSize: 15)),
                          const SizedBox(height: 2),
                          Text(c.desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(height: 1.3)),
                        ]),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(8)),
                        child: Text('${counts[c.id] ?? 0}', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
                      ),
                    ]),
                  ),
                ),
              );
            }),
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
      appBar: AppBar(title: Text(uiEnglish ? widget.cat.name : '${widget.cat.tr} · ${widget.cat.name}')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: L('${all.length} ifade içinde ara', 'Search ${all.length} entries')),
            onChanged: (v) => setState(() => q = v.toLowerCase()),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
            separatorBuilder: (_, _) => const Divider(indent: 16, endIndent: 16),
            itemCount: list.length,
            itemBuilder: (c, i) {
              final e = list[i];
              final st = app.user.statuses[e.phrase];
              return ListTile(
                title: Text(e.phrase, style: TextStyle(fontWeight: FontWeight.w600, color: widget.cat.color)),
                subtitle: Text([if (app.showTr && e.trShown != null) e.trShown!, if ((app.showEn || e.trShown == null) && e.en != null) e.en!].join('\n'), maxLines: 3),
                trailing: st == null ? null : Icon(Icons.circle, size: 12, color: st == WordStatus.learning ? learningColor : learnedColor),
                onTap: () async {
                  await showExprSheet(context, app, e, null);
                  if (mounted) setState(() {});
                },
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
      appBar: AppBar(toolbarHeight: 68, title: Text(L('Ayarlar', 'Settings'), style: theme.textTheme.headlineSmall)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        SectionLabel(L('Görünüm', 'Appearance'), padding: const EdgeInsets.fromLTRB(4, 4, 4, 8)),
        Panel(children: [
        Text('Uygulama dili / App language', style: theme.textTheme.titleSmall),
        const SizedBox(height: 10),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Türkçe')),
            ButtonSegment(value: true, label: Text('English')),
          ],
          selected: {app.englishUi},
          onSelectionChanged: (s) => app.setUiEnglish(s.first),
        ),
        const SizedBox(height: 6),
        Text(L('Menüler, düğmeler ve açıklamalar bu dilde gösterilir.', 'Menus, buttons and explanations are shown in this language.'),
            style: theme.textTheme.bodySmall),
        const Divider(height: 32),
        Text(L('Tema', 'Theme'), style: theme.textTheme.titleSmall),
        const SizedBox(height: 10),
        SegmentedButton<ThemeMode>(
          segments: [
            ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode), label: Text(L('Gündüz', 'Day'))),
            ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode), label: Text(L('Gece', 'Night'))),
            ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto), label: Text(L('Sistem', 'System'))),
          ],
          selected: {app.themeMode},
          onSelectionChanged: (s) => app.setTheme(s.first),
        ),
        const Divider(height: 32),
        Text(L('Anlam dili', 'Meaning language'), style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(L('Kelime panelinde Türkçe, İngilizce veya ikisi birden.', 'Turkish, English or both in the word panel.'), style: theme.textTheme.bodySmall),
        const SizedBox(height: 10),
        Align(alignment: Alignment.centerLeft, child: LangToggles(app: app, onChanged: () => setState(() {}))),
        ]),
        SectionLabel(L('Yapay zekâ · isteğe bağlı', 'AI · optional')),
        Panel(children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.auto_awesome_rounded, color: theme.colorScheme.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(L('Çeviri ve bölüm özetleri', 'Translations and chapter summaries'), style: theme.textTheme.titleSmall)),
        ]),
        const SizedBox(height: 10),
        Text(
          L('Bağladığın servis, internet olduğu her an henüz taranmamış kitapları tarar: her cümlenin Türkçe çevirisi ve bölüm özetleri cihazına kaydedilir ve bir daha taranmaz. Yarıda kalırsa kaldığı yerden devam eder. Taranmış (resim) PDF\'lerde cihazda OCR yoksa sayfaları da okuyabilir. Kullanım ücreti kendi hesabından düşer.', 'Whenever there is an internet connection, the service you connect scans books that have not been scanned yet: a Turkish translation of every sentence and chapter summaries are saved on your device and never scanned again. If it stops halfway, it continues where it left off. For scanned (image) PDFs it can also read the pages when the device has no OCR. Usage is billed to your own account.'),
          style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: providerId,
          isExpanded: true,
          decoration: InputDecoration(labelText: L('Servis', 'Service')),
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
            helperMaxLines: 2,
          ),
          onChanged: (_) => _save(),
        ),
        const SizedBox(height: 12),
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
        ]),
        SectionLabel(L('Hakkında', 'About')),
        Panel(children: [
          Row(children: [
            const BrandMark(size: 44),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('VocaBloom', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                Text(appBuild == 0 ? L('Sürüm: geliştirme derlemesi', 'Version: development build') : L('Sürüm 1.0 · derleme $appBuild', 'Version 1.0 · build $appBuild'), style: theme.textTheme.bodySmall),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Text(
            L('VocaBloom ile okuduğun her kitap bir İngilizce dersine dönüşür: bilinmeyen kelimeler anında açıklanır, tekrar sistemiyle kalıcı hale gelir. VocaBloom, dil öğrenenlerin gelişimini desteklemek amacıyla tasarlanmış ve geliştirilmiştir.',
                'With VocaBloom, every book you read becomes an English lesson: unknown words are explained instantly and made permanent through spaced review. VocaBloom is designed and built to support language learners\' progress.'),
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 10),
          Text(L('© 2026 Hamit Gök. Tüm hakları saklıdır.', '© 2026 Hamit Gök. All rights reserved.'), style: theme.textTheme.bodySmall),
        ]),
        SectionLabel(L('Veriler ve lisanslar', 'Data and licenses')),
        Panel(children: [
        Text(
          L('Tüm kitapların, kelime listen ve ayarların yalnızca bu cihazda saklanır. API anahtarları da yalnızca cihazda tutulur ve sadece seçtiğin servise gönderilir.\n\nSözlük kaynakları:\n', 'All your books, your word list and your settings are stored only on this device. API keys are also kept only on the device and are sent only to the service you choose.\n\nDictionary sources:\n') +
          '• FreeDict English–Turkish (GPL-2.0+)\n'
          '• Princeton WordNet 3.0 (WordNet License)\n'
          '• KeNet Turkish WordNet, Starlang / Özyeğin University (CC BY-SA 4.0)\n'
          '• Collaborative Interlingual Index (CC BY 4.0)\n'
          '• Wiktionary expressions via kaikki.org (CC BY-SA 4.0)\n' +
          L('• Kategori listeleri bu uygulama için hazırlandı (CC BY-SA 4.0).', '• Category lists written for this app (CC BY-SA 4.0).') +
          L('\n• Yazı tipleri: Inter ve Literata (SIL Open Font License 1.1)', '\n• Fonts: Inter and Literata (SIL Open Font License 1.1)'),
          style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
        ),
        ]),
          ]),
        ),
      ),
    );
  }
}
