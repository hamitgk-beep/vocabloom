import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../ai/tutor.dart';
import '../../l10n.dart';
import 'ai_tools.dart';
import 'local_ai_card.dart';

/// "Yapay zekâya sor": a small chat with the on-device model about what is on
/// the screen (a grammar exercise just answered, a tapped word). Shown only
/// when a model is downloaded. [about] gives the model the facts.
class AiAskBox extends StatefulWidget {
  final AppState app;
  final String about;
  final List<String> suggestions;
  final String title;
  const AiAskBox({super.key, required this.app, required this.about, required this.suggestions, required this.title});

  @override
  State<AiAskBox> createState() => _AiAskBoxState();
}

class _AiAskBoxState extends State<AiAskBox> {
  final input = TextEditingController();
  final history = <(String, String)>[];
  bool open = false, running = false;
  String? error;
  StreamSubscription<String>? sub;

  @override
  void dispose() {
    sub?.cancel();
    input.dispose();
    super.dispose();
  }

  void _ask(String q) {
    q = q.trim();
    if (q.isEmpty || running) return;
    FocusScope.of(context).unfocus();
    input.clear();
    setState(() {
      open = true;
      running = true;
      error = null;
      history.add(('user', q));
    });
    final asked = List.of(history);
    var answer = '';
    history.add(('assistant', ''));
    sub = Tutor.of(widget.app).discuss(widget.about, asked).listen(
      (c) {
        if (!mounted) return;
        setState(() {
          answer += c;
          history[history.length - 1] = ('assistant', answer);
        });
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          running = false;
          if (answer.isEmpty) history.removeLast();
          error = aiError(e);
        });
      },
      onDone: () {
        if (mounted) setState(() => running = false);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!LocalAiCard.available(widget.app)) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (!open) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const ValueKey('ai-ask'),
            onPressed: () => setState(() => open = true),
            icon: const Icon(Icons.forum_rounded, size: 18),
            label: Text(widget.title),
          ),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.forum_rounded, size: 18, color: cs.primary),
          const SizedBox(width: 6),
          Expanded(child: Text(widget.title, style: theme.textTheme.titleSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w800))),
          if (running) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
        for (final (role, text) in history)
          Align(
            alignment: role == 'user' ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              constraints: const BoxConstraints(maxWidth: 520),
              decoration: BoxDecoration(
                color: role == 'user' ? cs.primary : cs.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: role == 'user'
                  ? Text(text, style: TextStyle(color: cs.onPrimary))
                  : text.isEmpty
                      ? AiWaiting(ai: widget.app.localAi)
                      : aiRichText(text, theme.textTheme.bodyMedium?.copyWith(height: 1.45)),
            ),
          ),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(error!, style: TextStyle(color: cs.error))),
        if (history.isEmpty || !running) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in widget.suggestions) ActionChip(label: Text(s), onPressed: running ? null : () => _ask(s)),
          ]),
        ],
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              key: const ValueKey('ai-ask-input'),
              controller: input,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.send,
              onSubmitted: _ask,
              decoration: InputDecoration(
                isDense: true,
                hintText: L('Sorunu yaz…', 'Type your question…'),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          IconButton(onPressed: running ? null : () => _ask(input.text), icon: const Icon(Icons.send_rounded)),
        ]),
        if (history.isNotEmpty && !running) const AiDisclaimer(),
      ]),
    );
  }
}
