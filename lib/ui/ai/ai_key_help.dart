import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../l10n.dart';
import '../settings_page.dart';
import '../theme.dart';

/// Opens the page where the learner adds their own AI key.
Future<void> openAiKeySettings(BuildContext context, AppState app) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AiServicePage(app: app)));

/// Explains, when no AI service is connected, how "Yapay zekâya sor" works and
/// leads to the key settings. Returns whether a service is connected afterwards.
Future<bool> showAiKeyHelp(BuildContext context, AppState app) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (c) {
      final theme = Theme.of(c);
      final cs = theme.colorScheme;
      Widget step(int n, String text) => Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                child: Text('$n', style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w800, fontSize: 12)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(text, style: theme.textTheme.bodyLarge?.copyWith(height: 1.4))),
            ]),
          );
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(gradient: Brand.gradient, borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(L('Yapay zekâya sormak için anahtar ekle', 'Add a key to ask the AI'),
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              ),
            ]),
            const SizedBox(height: 12),
            Text(
              L('Storilex ücretsizdir; yapay zekâ cevapları senin kendi API anahtarınla gelir. Google Gemini\'nin ücretsiz planı yeterli.',
                  'Storilex is free; AI answers come with your own API key. Google Gemini\'s free plan is enough.'),
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5, color: cs.onSurfaceVariant),
            ),
            step(1, L('aistudio.google.com adresinde "Get API key" ile anahtar al.', 'Get a key with "Get API key" at aistudio.google.com.')),
            step(2, L('Ayarlar > Yapay zekâ servisi bölümüne yapıştır.', 'Paste it in Settings > AI service.')),
            step(3, L('Geri dön ve sorunu sor. Anahtar yalnızca bu cihazda saklanır.', 'Come back and ask. The key stays on this device.')),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('ai-key-open'),
                onPressed: () {
                  Navigator.of(c).pop();
                  openAiKeySettings(context, app);
                },
                icon: const Icon(Icons.key_rounded),
                label: Text(L('Anahtar ekle', 'Add a key')),
              ),
            ),
          ]),
        ),
      );
    },
  );
  return app.localAi.activeId != null;
}
