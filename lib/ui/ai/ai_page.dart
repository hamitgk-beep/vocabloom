import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n.dart';
import '../theme.dart';
import 'ai_tools.dart';
import 'ai_types.dart';

const _premiumGold = Color(0xFFD99A1E);

String fmtSize(int bytes) {
  final gb = bytes / (1024 * 1024 * 1024);
  if (gb >= 1) return '${gb.toStringAsFixed(gb >= 2.95 ? 0 : 1).replaceAll('.', uiEnglish ? '.' : ',')} GB';
  return '${(bytes / (1024 * 1024)).round()} MB';
}

/// The "Yapay Zekâ" tab: on-device tutor packages and what you can do with them.
class AiPage extends StatefulWidget {
  final LocalAi ai;
  final Tutor tutor;
  const AiPage({super.key, required this.ai, required this.tutor});

  @override
  State<AiPage> createState() => _AiPageState();
}

class _AiPageState extends State<AiPage> {
  Set<String> installed = {};
  int? ramMb;
  final progress = <String, AiDownload>{};
  final subs = <String, StreamSubscription<AiDownload>>{};
  final packagesKey = GlobalKey();

  LocalAi get ai => widget.ai;

  @override
  void initState() {
    super.initState();
    ai.addListener(_refresh);
    _refresh();
    ai.deviceRamMb().then((v) => mounted ? setState(() => ramMb = v) : null);
  }

  @override
  void dispose() {
    ai.removeListener(_refresh);
    for (final s in subs.values) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _refresh() async {
    final i = await ai.installed();
    if (mounted) setState(() => installed = i);
  }

  void _download(AiPackage p) {
    setState(() => progress[p.id] = AiDownload(0, p.sizeBytes));
    subs[p.id] = ai.download(p.id).listen(
      (d) => setState(() => progress[p.id] = d),
      onError: (Object e) {
        setState(() => progress.remove(p.id));
        subs.remove(p.id);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(L('İndirme yarıda kaldı. Tekrar denediğinde kaldığı yerden devam eder.', 'The download stopped. It will resume where it left off when you try again.'))));
      },
      onDone: () {
        setState(() => progress.remove(p.id));
        subs.remove(p.id);
        _refresh();
      },
    );
  }

  Future<void> _cancel(AiPackage p) async {
    await subs.remove(p.id)?.cancel();
    await ai.cancel(p.id);
    setState(() => progress.remove(p.id));
  }

  Future<void> _delete(AiPackage p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(L('${p.nameTr} paketi silinsin mi?', 'Delete the ${p.nameEn} package?')),
        content: Text(L('Cihazında ${fmtSize(p.sizeBytes)} yer açılır. İstediğin zaman yeniden indirebilirsin.', 'This frees ${fmtSize(p.sizeBytes)} on your device. You can download it again any time.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(L('Vazgeç', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(L('Sil', 'Delete'))),
        ],
      ),
    );
    if (ok == true) await ai.delete(p.id);
  }

  void _premiumInfo(AiPackage p) {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.workspace_premium_rounded, color: _premiumGold, size: 36),
        title: Text(L('VocaBloom Premium', 'VocaBloom Premium')),
        content: Text(L(
            '${p.nameTr} paketi Premium aboneliğe dahildir. Abonelik çok yakında açılacak; şimdilik ücretsiz Hafif paketi kullanabilirsin.',
            'The ${p.nameEn} package is included with Premium. Subscriptions open very soon; for now you can use the free Lite package.')),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: Text(L('Tamam', 'OK')))],
      ),
    );
  }

  void _openTool(AiTool tool) {
    if (ai.activeId == null || installed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(L('Önce aşağıdan bir yapay zekâ paketi indir.', 'Download an AI package below first.'))));
      final c = packagesKey.currentContext;
      if (c != null) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AiToolPage(tool: tool, ai: ai, tutor: widget.tutor)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = ai.packages.where((p) => p.id == ai.activeId && installed.contains(p.id)).firstOrNull;
    return Scaffold(
      appBar: AppBar(toolbarHeight: 68, title: Text(L('Yapay Zekâ', 'AI Tutor'), style: theme.textTheme.headlineSmall)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
            _Hero(active: active),
            SectionLabel(L('Neler yapabilirsin', 'What you can do')),
            _ToolGrid(enabled: active != null, onTap: _openTool),
            SectionLabel(L('Paketler', 'Packages'), padding: const EdgeInsets.fromLTRB(4, 24, 4, 4)),
            Padding(
              key: packagesKey,
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Text(
                L('Paketler bir kez indirilir ve cihazında çalışır. İnternet gerekmez, yazdıkların cihazından çıkmaz.',
                    'Packages are downloaded once and run on your device. No internet needed; what you write never leaves your device.'),
                style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
              ),
            ),
            for (final p in ai.packages)
              _PackageCard(
                p: p,
                installed: installed.contains(p.id),
                active: ai.activeId == p.id && installed.contains(p.id),
                locked: p.premium && !ai.premiumUnlocked,
                ramMb: ramMb,
                progress: progress[p.id],
                onDownload: () => _download(p),
                onCancel: () => _cancel(p),
                onDelete: () => _delete(p),
                onUse: () => ai.setActive(p.id),
                onLocked: () => _premiumInfo(p),
              ),
          ]),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final AiPackage? active;
  const _Hero({this.active});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(gradient: Brand.gradient, borderRadius: BorderRadius.circular(22)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(L('Cebindeki İngilizce öğretmeni', 'An English tutor in your pocket'),
                style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 10),
        Text(
          L('Cümleleri açıklar, yazdıklarını düzeltir, seninle İngilizce sohbet eder ve öğrendiğin kelimelerden test hazırlar. Tamamen cihazında, internetsiz çalışır.',
              'It explains sentences, corrects your writing, chats with you in English and builds quizzes from your words. Runs fully on your device, offline.'),
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.9), height: 1.45),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(active == null ? Icons.download_rounded : Icons.check_circle_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(
              active == null
                  ? L('Başlamak için bir paket indir', 'Download a package to start')
                  : L('Kullanılan paket: ${active!.nameTr}', 'Active package: ${active!.nameEn}'),
              style: theme.textTheme.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _ToolGrid extends StatelessWidget {
  final bool enabled;
  final void Function(AiTool) onTap;
  const _ToolGrid({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 560 ? 4 : 2;
      final w = (c.maxWidth - (cols - 1) * 10) / cols;
      return Wrap(spacing: 10, runSpacing: 10, children: [
        for (final t in AiTool.values)
          SizedBox(
            width: w,
            child: Material(
              color: cs.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: cs.outlineVariant)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onTap(t),
                child: Opacity(
                  opacity: enabled ? 1 : 0.55,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(color: t.color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                        child: Icon(t.icon, color: t.color, size: 22),
                      ),
                      const SizedBox(height: 10),
                      Text(t.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(t.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(height: 1.35)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
      ]);
    });
  }
}

class _PackageCard extends StatelessWidget {
  final AiPackage p;
  final bool installed, active, locked;
  final int? ramMb;
  final AiDownload? progress;
  final VoidCallback onDownload, onCancel, onDelete, onUse, onLocked;
  const _PackageCard({
    required this.p,
    required this.installed,
    required this.active,
    required this.locked,
    required this.ramMb,
    required this.progress,
    required this.onDownload,
    required this.onCancel,
    required this.onDelete,
    required this.onUse,
    required this.onLocked,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final free = p.tier == 'free';
    final badgeColor = free ? const Color(0xFF15803D) : _premiumGold;
    final heavy = ramMb != null && ramMb! < p.minRamGb * 1024 - 512;
    final pr = progress;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: active ? cs.primary : (free ? cs.outlineVariant : _premiumGold.withValues(alpha: 0.45)), width: active ? 2 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(uiEnglish ? p.nameEn : p.nameTr, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text('${fmtSize(p.sizeBytes)} · ${p.model}', style: theme.textTheme.bodySmall),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: badgeColor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(free ? Icons.lock_open_rounded : Icons.workspace_premium_rounded, size: 15, color: badgeColor),
              const SizedBox(width: 4),
              Text(free ? L('Ücretsiz', 'Free') : 'Premium',
                  style: theme.textTheme.labelMedium?.copyWith(color: badgeColor, fontWeight: FontWeight.w800)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Text(uiEnglish ? p.descEn : p.descTr, style: theme.textTheme.bodyMedium?.copyWith(height: 1.45)),
        const SizedBox(height: 12),
        for (final r in p.ratings) _RatingRow(label: uiEnglish ? r.$2 : r.$1, score: r.$3),
        const SizedBox(height: 8),
        _Note(icon: Icons.info_outline_rounded, text: uiEnglish ? p.noteEn : p.noteTr),
        _Note(
          icon: heavy ? Icons.warning_amber_rounded : Icons.smartphone_rounded,
          color: heavy ? const Color(0xFFB45309) : null,
          text: heavy
              ? L('Önerilen: en az ${p.minRamGb} GB RAM. Telefonun için ağır olabilir, yavaş çalışabilir.',
                  'Recommended: at least ${p.minRamGb} GB RAM. It may be heavy and slow on your phone.')
              : L('Önerilen: en az ${p.minRamGb} GB RAM olan telefonlar.', 'Recommended: phones with at least ${p.minRamGb} GB RAM.'),
        ),
        _Note(icon: Icons.verified_outlined, text: L('Lisans: ${p.licenseName}', 'License: ${p.licenseName}')),
        const SizedBox(height: 12),
        if (pr != null) ...[
          ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: pr.fraction, minHeight: 8)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Text('%${(pr.fraction * 100).round()} · ${fmtSize(pr.received)} / ${fmtSize(pr.total)}',
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            ),
            TextButton(onPressed: onCancel, child: Text(L('Durdur', 'Pause'))),
          ]),
        ] else if (installed)
          Row(children: [
            if (active)
              Chip(
                avatar: Icon(Icons.check_circle_rounded, color: cs.primary, size: 18),
                label: Text(L('Kullanılıyor', 'In use')),
                side: BorderSide(color: cs.primary.withValues(alpha: 0.4)),
                backgroundColor: cs.primaryContainer.withValues(alpha: 0.5),
              )
            else
              FilledButton.tonal(onPressed: onUse, child: Text(L('Bunu kullan', 'Use this'))),
            const Spacer(),
            TextButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: Text(L('Sil', 'Delete')),
              style: TextButton.styleFrom(foregroundColor: cs.error),
            ),
          ])
        else if (locked)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onLocked,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                foregroundColor: _premiumGold,
                side: const BorderSide(color: _premiumGold),
              ),
              icon: const Icon(Icons.lock_rounded, size: 18),
              label: Text(L('Premium ile kullan', 'Available with Premium')),
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onDownload,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
              icon: const Icon(Icons.download_rounded, size: 20),
              label: Text(L('İndir · ${fmtSize(p.sizeBytes)}', 'Download · ${fmtSize(p.sizeBytes)}')),
            ),
          ),
      ]),
    );
  }
}

class _RatingRow extends StatelessWidget {
  final String label;
  final int score;
  const _RatingRow({required this.label, required this.score});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Expanded(child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurface))),
        for (var i = 0; i < 5; i++)
          Container(
            width: 18,
            height: 6,
            margin: const EdgeInsets.only(left: 3),
            decoration: BoxDecoration(
              color: i < score ? cs.primary : cs.outlineVariant.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ]),
    );
  }
}

class _Note extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  const _Note({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 15, color: c)),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: c, height: 1.4))),
      ]),
    );
  }
}
