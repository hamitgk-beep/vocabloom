import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../l10n.dart';
import '../settings_page.dart';

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
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(L('Yapay zekâya sormak için bir anahtar ekle', 'Add a key to ask the AI'),
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(
              L('VocaBloom ücretsizdir; yapay zekâ cevapları senin kendi API anahtarınla gelir. Google Gemini\'nin ücretsiz planı yeterli: '
                  'aistudio.google.com adresinde "Get API key" ile anahtar al, Ayarlar > Yapay zekâ servisi bölümüne yapıştır. '
                  'Anahtar yalnızca bu telefonda saklanır.',
                  'VocaBloom is free; AI answers come with your own API key. Google Gemini\'s free plan is enough: '
                  'get a key with "Get API key" at aistudio.google.com and paste it in Settings > AI service. '
                  'The key is kept only on this phone.'),
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('ai-key-open'),
              onPressed: () {
                Navigator.of(c).pop();
                openAiKeySettings(context, app);
              },
              icon: const Icon(Icons.key_rounded),
              label: Text(L('Anahtar ekle', 'Add a key')),
            ),
          ]),
        ),
      );
    },
  );
  return app.localAi.activeId != null;
}
