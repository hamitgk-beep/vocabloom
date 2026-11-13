import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/user_db.dart';
import '../nlp/text.dart';
import '../online/ai_service.dart';
import '../online/update_check.dart';
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
          title: const Text('Kelimelerim'),
          bottom: const TabBar(tabs: [Tab(text: 'Öğreneceğim'), Tab(text: 'Öğrendim')]),
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
                ? 'Okurken bir kelimeye dokunup "Öğreneceğim" dediğinde burada görünür ve kitapta turuncu işaretlenir.'
                : '"Öğrendim" dediğin kelimeler burada toplanır ve kitapta yeşil işaretlenir.',
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
              tooltip: status == WordStatus.learning ? 'Öğrendim' : 'Tekrar öğreneceğim',
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
      appBar: AppBar(title: const Text('Sözlük ve kategoriler')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        TextField(
          controller: search,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Sözlükte ara (kelime veya kalıp)',
            border: OutlineInputBorder(),
          ),
          onSubmitted: _lookup,
        ),
        const SizedBox(height: 12),
        for (final c in categories)
          Card(
            child: ListTile(
              leading: CircleAvatar(backgroundColor: c.color.withValues(alpha: 0.18), child: Icon(Icons.label, color: c.color)),
              title: Text('${c.name} · ${c.tr}'),
              subtitle: Text(c.description),
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
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Ara', border: OutlineInputBorder()),
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
      setState(() => testResult = 'Eksik bilgi var (anahtar, model veya adres).');
      return;
    }
    setState(() {
      testing = true;
      testResult = null;
    });
    try {
      final r = await svc.translateChunk(['The weather is lovely today.']);
      setState(() => testResult = 'Çalışıyor ✓  "${r.translations.firstOrNull ?? ''}"');
      widget.app.analyzer.tick();
    } catch (e) {
      setState(() => testResult = 'Hata: $e');
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
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Görünüm', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode), label: Text('Gündüz')),
            ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode), label: Text('Gece')),
            ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto), label: Text('Sistem')),
          ],
          selected: {app.themeMode},
          onSelectionChanged: (s) => app.setTheme(s.first),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Anlam dili'),
          subtitle: const Text('Kelime panelinde Türkçe, İngilizce veya ikisi birden.'),
          trailing: LangToggles(app: app, onChanged: () => setState(() {})),
        ),
        const Divider(height: 32),
        Text('Yapay zekâ (isteğe bağlı, internet gerekir)', style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        const Text(
          'Bağladığın servis, internet olduğu her an henüz taranmamış kitapları tarar: her cümlenin Türkçe çevirisi ve '
          'bölüm özetleri cihazına kaydedilir ve bir daha taranmaz. Yarıda kalırsa kaldığı yerden devam eder. '
          'Taranmış (resim) PDF\'lerde cihazda OCR yoksa sayfaları da okuyabilir. Kullanım ücreti kendi hesabından düşer.',
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: providerId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Servis', border: OutlineInputBorder()),
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
              labelText: p.kind == ApiKind.azure ? 'Uç nokta (https://<kaynak>.openai.azure.com)' : 'Adres (base URL)',
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
            labelText: p.needsKey ? 'API anahtarı' : 'API anahtarı (gerekmiyorsa boş bırak)',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(icon: Icon(obscure ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => obscure = !obscure)),
          ),
          onChanged: (_) => _save(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: model,
          decoration: InputDecoration(
            labelText: p.kind == ApiKind.azure ? 'Dağıtım (deployment) adı' : 'Model adı',
            helperText: 'Servisin model listesinden istediğini yazabilirsin. Varsayılan: ${p.defaultModel}',
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => _save(),
        ),
        const SizedBox(height: 8),
        Row(children: [
          FilledButton.tonalIcon(
            onPressed: testing ? null : _test,
            icon: testing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi_tethering),
            label: const Text('Bağlantıyı dene'),
          ),
        ]),
        if (testResult != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(testResult!)),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('İnternet olunca kitapları otomatik tara'),
          subtitle: const Text('Kitaplar çevrilir, sonra sözlükte yalnızca İngilizce açıklaması olan kalıplar Türkçeye '
              'çevrilip cihaza kaydedilir. Kapalıysa kitap menüsünden elle başlatabilirsin.'),
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
          Text('Not: ${p.name} resimdeki yazıyı okuyamaz; taranmış PDF için cihazın kendi OCR\'ı kullanılır.',
              style: theme.textTheme.bodySmall),
        const Divider(height: 32),
        Text('Hakkında', style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        const Text('VocaBloom, Hamit Gök tarafından geliştirildi.'),
        Text(appBuild == 0 ? 'Sürüm: geliştirme derlemesi' : 'Sürüm: 1.0 (derleme $appBuild)', style: theme.textTheme.bodySmall),
        const Divider(height: 32),
        Text('Veriler ve lisanslar', style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        const Text(
          'Tüm kitapların, kelime listen ve ayarların yalnızca bu cihazda saklanır. API anahtarları da yalnızca cihazda '
          'tutulur ve sadece seçtiğin servise gönderilir.\n\n'
          'Sözlük kaynakları:\n'
          '• FreeDict English–Turkish (GPL-2.0+)\n'
          '• Princeton WordNet 3.0 (WordNet lisansı)\n'
          '• KeNet Türkçe WordNet, Starlang / Özyeğin Üniversitesi (CC BY-SA 4.0)\n'
          '• Collaborative Interlingual Index (CC BY 4.0)\n'
          '• Wiktionary kalıpları, kaikki.org üzerinden (CC BY-SA 4.0)\n'
          '• Kategori listeleri bu uygulama için hazırlandı (CC BY-SA 4.0).',
        ),
      ]),
    );
  }
}
