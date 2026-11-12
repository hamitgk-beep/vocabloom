import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/user_db.dart';
import '../nlp/text.dart';
import '../online/claude_service.dart';
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
    final list = q.isEmpty ? all : all.where((e) => e.phrase.contains(q) || (e.tr?.toLowerCase().contains(q) ?? false)).toList();
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
                subtitle: Text([if (app.showTr && e.tr != null) e.tr!, if (app.showEn && e.en != null) e.en!].join('\n'), maxLines: 3),
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
  late final key = TextEditingController(text: widget.app.user.getSetting('api_key') ?? '');
  bool obscure = true;

  @override
  Widget build(BuildContext context) {
    final u = widget.app.user;
    final theme = Theme.of(context);
    final model = u.getSetting('api_model') ?? ClaudeService.defaultModel;
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Görünüm', style: theme.textTheme.titleMedium),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Anlam dili'),
          subtitle: const Text('Kelime panelinde Türkçe, İngilizce veya ikisi birden.'),
          trailing: LangToggles(app: widget.app, onChanged: () => setState(() {})),
        ),
        const Divider(height: 32),
        Text('Çevrimiçi analiz (isteğe bağlı)', style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        const Text(
          'İnternet varken kitap Claude yapay zekâsıyla taranır: her cümlenin Türkçe çevirisi ve her bölümün özeti çıkarılıp '
          'cihazına kaydedilir. Sonra internetsiz de görünür. Bunun için kendi Anthropic API anahtarın gerekir '
          '(console.anthropic.com); kullanım ücreti anahtarın hesabından düşer. Bir roman için yaklaşık maliyet: '
          'Opus 5.5 ile birkaç dolar, Haiku 5.5 ile birkaç sent.',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: key,
          obscureText: obscure,
          decoration: InputDecoration(
            labelText: 'Anthropic API anahtarı',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(icon: Icon(obscure ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => obscure = !obscure)),
          ),
          onChanged: (v) => u.setSetting('api_key', v.trim().isEmpty ? null : v.trim()),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: model,
          decoration: const InputDecoration(labelText: 'Model', border: OutlineInputBorder()),
          items: [for (final e in ClaudeService.models.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => setState(() => u.setSetting('api_model', v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Kitap eklerken otomatik analiz et'),
          subtitle: const Text('İnternet yoksa atlanır; kitap menüsünden sonra da başlatabilirsin.'),
          value: u.getSetting('auto_analyze') == '1',
          onChanged: (v) => setState(() => u.setSetting('auto_analyze', v ? '1' : null)),
        ),
        const Divider(height: 32),
        Text('Veriler ve lisanslar', style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        const Text(
          'Tüm kitapların, kelime listen ve ayarların yalnızca bu cihazda saklanır.\n\n'
          'Sözlük kaynakları:\n'
          '• FreeDict English–Turkish (GPL-2.0+)\n'
          '• Princeton WordNet 3.0 (WordNet lisansı)\n'
          '• KeNet Türkçe WordNet, Starlang / Özyeğin Üniversitesi (CC BY-SA 4.0)\n'
          '• Collaborative Interlingual Index (CC BY 4.0)\n'
          '• Kategori listeleri bu uygulama için hazırlandı (CC BY-SA 4.0).',
        ),
      ]),
    );
  }
}
