import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ai/local_ai.dart' show formatBytes;
import '../app_state.dart';
import '../l10n.dart';
import '../mt/offline_mt.dart';

/// Settings > Offline translation (Windows): the learner chooses to download
/// the OPUS-MT model after seeing its size and license, can cancel the
/// download, turn the feature off and delete the model.
class OfflineMtPage extends StatelessWidget {
  final AppState app;
  final OfflineMt mt;
  OfflineMtPage({super.key, required this.app, OfflineMt? mt}) : mt = mt ?? OfflineMt.instance;

  MtModelSpec get _spec => mt.spec;

  Future<void> _askDownload(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        key: const ValueKey('offline-mt-consent'),
        title: Text(L('Çeviri modeli indirilsin mi?', 'Download the translation model?')),
        content: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(L('Boyut: ${formatBytes(_spec.totalBytes)} (bir kez indirilir, bilgisayarında kalır).',
                'Size: ${formatBytes(_spec.totalBytes)} (downloaded once, stays on your computer).')),
            const SizedBox(height: 8),
            Text(L('Lisans: ${_spec.license}. Kaynak: ${_spec.attribution}.', 'License: ${_spec.license}. Credit: ${_spec.attribution}.')),
            const SizedBox(height: 8),
            Text(L('Ücretsizdir ve indirildikten sonra internet gerekmez. Hiçbir ücretli servis kullanılmaz.',
                'It is free and needs no internet once downloaded. No paid service is used.')),
            const SizedBox(height: 8),
            Text(L('Makine çevirisidir: deyimlerde ve çok anlamlı kelimelerde yanılabilir.', 'It is machine translation: it can be wrong with idioms and words with several meanings.'),
                style: TextStyle(color: Theme.of(c).hintColor)),
          ]),
        ),
        actions: [
          TextButton(key: const ValueKey('offline-mt-consent-no'), onPressed: () => Navigator.pop(c, false), child: Text(L('Vazgeç', 'Cancel'))),
          FilledButton(key: const ValueKey('offline-mt-consent-yes'), onPressed: () => Navigator.pop(c, true), child: Text(L('İndir', 'Download'))),
        ],
      ),
    );
    if (ok != true) return;
    if (await mt.download()) mt.setEnabled(app.user, true);
  }

  Future<void> _askRemove(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(L('Model silinsin mi?', 'Delete the model?')),
        content: Text(L('${formatBytes(_spec.totalBytes)} yer açılır. Daha önce çevrilen cümleler saklanır; kitapların ve kelimelerin etkilenmez.',
            'Frees ${formatBytes(_spec.totalBytes)}. Sentences translated before are kept; your books and words are not affected.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(L('Vazgeç', 'Cancel'))),
          FilledButton(key: const ValueKey('offline-mt-remove-yes'), onPressed: () => Navigator.pop(c, true), child: Text(L('Sil', 'Delete'))),
        ],
      ),
    );
    if (ok == true) await mt.remove(app.user);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(L('Çevrimdışı çeviri', 'Offline translation'))),
      body: ListenableBuilder(
        listenable: mt,
        builder: (context, _) {
          final s = mt.state;
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text(
              L('Cümle panelinde Türkçe çeviriyi internetsiz ve ücretsiz gösterir. Yalnızca Windows içindir; sen indirmeden hiçbir şey indirilmez.\n\nÇeviriler bir yazılım tarafından otomatik üretilir ve hata içerebilir; özellikle deyimlerde ve birden çok anlamı olan kelimelerde. Yalnızca cümlenin Türkçesini göstermek için kullanılır: sözlük anlamlarını, deyimleri ve tekrar kartlarının puanlamasını değiştirmez.',
                  'Shows the Turkish of a sentence without internet, for free. Windows only; nothing is downloaded until you choose to.\n\nThe translations are made automatically by software and may contain mistakes, especially with idioms and words that have several meanings. They are only used to show a sentence in Turkish: they never change dictionary meanings, idioms or how review cards are scored.'),
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(L('OPUS-MT · İngilizce → Türkçe', 'OPUS-MT · English → Turkish'), style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(L('Boyut: ${formatBytes(_spec.totalBytes)}', 'Size: ${formatBytes(_spec.totalBytes)}'), key: const ValueKey('offline-mt-size')),
                  Text(L('Lisans: ${_spec.license}', 'License: ${_spec.license}'), key: const ValueKey('offline-mt-license')),
                  Text(_spec.attribution, style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => launchUrl(Uri.parse(_spec.pageUrl), mode: LaunchMode.externalApplication),
                      child: Text(L('Model sayfası ve lisans', 'Model page and license')),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            ...switch (s.status) {
              OfflineMtStatus.downloading => [
                  LinearProgressIndicator(key: const ValueKey('offline-mt-progress'), value: s.fraction),
                  const SizedBox(height: 8),
                  Text('${formatBytes(s.received)} / ${formatBytes(s.total)}'),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      key: const ValueKey('offline-mt-cancel'),
                      onPressed: mt.cancel,
                      icon: const Icon(Icons.close_rounded),
                      label: Text(L('İndirmeyi iptal et', 'Cancel the download')),
                    ),
                  ),
                ],
              OfflineMtStatus.ready => [
                  SwitchListTile(
                    key: const ValueKey('offline-mt-enabled'),
                    contentPadding: EdgeInsets.zero,
                    value: mt.enabled(app.user),
                    onChanged: (v) => mt.setEnabled(app.user, v),
                    title: Text(L('Cümle çevirilerinde kullan', 'Use for sentence translations')),
                    subtitle: Text(L('Kapalıyken model diskte kalır ama kullanılmaz.', 'When off the model stays on disk but is not used.')),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey('offline-mt-remove'),
                      onPressed: () => _askRemove(context),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: Text(L('Modeli sil', 'Delete the model')),
                    ),
                  ),
                ],
              OfflineMtStatus.notInstalled || OfflineMtStatus.failed => [
                  if (s.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(s.error!, key: const ValueKey('offline-mt-error'), style: TextStyle(color: theme.colorScheme.error)),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      key: const ValueKey('offline-mt-download'),
                      onPressed: () => _askDownload(context),
                      icon: const Icon(Icons.download_rounded),
                      label: Text(s.status == OfflineMtStatus.failed
                          ? L('Tekrar dene', 'Try again')
                          : L('Modeli indir (${formatBytes(_spec.totalBytes)})', 'Download the model (${formatBytes(_spec.totalBytes)})')),
                    ),
                  ),
                ],
            },
          ]);
        },
      ),
    );
  }
}
