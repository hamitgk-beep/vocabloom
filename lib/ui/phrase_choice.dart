import 'package:flutter/material.dart';

import '../l10n.dart';

/// "Bunu mu demek istedin?": the expressions that share a tapped word, and the
/// word alone. Returns the index of the phrase, -1 for the single word, or
/// null when the sheet is closed.
Future<int?> showPhraseChoice(BuildContext context, List<String> phrases, String word) => showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(L('Bunu mu demek istedin?', 'Did you mean?'), style: Theme.of(c).textTheme.titleMedium),
            ),
            for (var k = 0; k < phrases.length; k++)
              ListTile(key: ValueKey('phrase-choice-$k'), title: Text(phrases[k]), onTap: () => Navigator.pop(c, k)),
            ListTile(
              key: const ValueKey('phrase-choice-word'),
              leading: const Icon(Icons.text_fields_rounded),
              title: Text(L("Sadece '$word' kelimesi", "Only the word '$word'")),
              onTap: () => Navigator.pop(c, -1),
            ),
          ]),
        ),
      ),
    );
