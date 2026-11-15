import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../l10n.dart';
import 'ai_tools.dart';

/// An answer from the on-device AI model inside the reading panels (word,
/// sentence). Shown only when a model is downloaded. It starts by itself when
/// [auto] (the dictionary has nothing in Turkish), otherwise on a tap; the
/// answer is kept, so the panel opens with it next time.
class LocalAiCard extends StatefulWidget {
  final AppState app;

  /// Where the answer is kept, e.g. `word:pedicab|<sentence>`.
  final String cacheKey;
  final String title;
  final String button;
  final bool auto;
  final Stream<String> Function() run;
  const LocalAiCard({super.key, required this.app, required this.cacheKey, required this.title, required this.button, required this.run, this.auto = false});

  /// Whether a model is downloaded and chosen.
  static bool available(AppState app) => app.localAi.activeId != null;

  @override
  State<LocalAiCard> createState() => _LocalAiCardState();
}

class _LocalAiCardState extends State<LocalAiCard> {
  String text = '';
  bool running = false;
  String? error;
  StreamSubscription<String>? sub;

  String get _key => 'ai_cache:${widget.cacheKey}';

  @override
  void initState() {
    super.initState();
    text = widget.app.user.getSetting(_key) ?? '';
    if (text.isEmpty && widget.auto) WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  void _start() {
    if (!mounted || running) return;
    setState(() {
      running = true;
      text = '';
      error = null;
    });
    sub = widget.run().listen(
      (c) => setState(() => text += c),
      onError: (Object e) {
        if (mounted) setState(() => error = L('Yapay zekâ şu an yanıt veremedi. Tekrar dene.', 'The AI could not answer right now. Try again.'));
        running = false;
      },
      onDone: () {
        if (text.trim().isNotEmpty) widget.app.user.setSetting(_key, text.trim());
        if (mounted) setState(() => running = false);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (text.isEmpty && !running && error == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(onPressed: _start, icon: const Icon(Icons.auto_awesome_rounded, size: 18), label: Text(widget.button)),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.auto_awesome_rounded, size: 18, color: cs.primary),
          const SizedBox(width: 6),
          Expanded(child: Text(widget.title, style: theme.textTheme.titleSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w800))),
          if (running) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
        const SizedBox(height: 8),
        if (text.isEmpty && running)
          Text(L('Yapay zekâ düşünüyor… (cihazında çalışır, ilk seferde biraz sürebilir)', 'The AI is thinking… (it runs on your device; the first answer can take a while)'),
              style: theme.textTheme.bodySmall),
        if (text.isNotEmpty) aiRichText(text, theme.textTheme.bodyLarge?.copyWith(height: 1.5)),
        if (error != null) Text(error!, style: TextStyle(color: cs.error)),
        if (!running && (text.isNotEmpty || error != null))
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(onPressed: _start, icon: const Icon(Icons.refresh_rounded, size: 16), label: Text(L('Yeniden yaz', 'Rewrite'))),
          ),
        if (text.isNotEmpty && !running) const AiDisclaimer(),
      ]),
    );
  }
}
