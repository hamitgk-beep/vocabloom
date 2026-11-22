import 'package:flutter/material.dart';

import '../app_state.dart';
import '../l10n.dart';
import 'panel.dart';
import 'theme.dart';

/// First launch: the learner picks their native language and the language
/// they learn, then three short screens introduce the app.
class OnboardingPage extends StatefulWidget {
  final AppState app;
  final VoidCallback onDone;
  const OnboardingPage({super.key, required this.app, required this.onDone});

  /// Only for new users: people who already have books skip it.
  static bool needed(AppState app) => app.user.getSetting('onboarded') == null && app.user.books().isEmpty;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final pc = PageController();
  int page = 0;

  /// The language step comes first; the introduction follows it.
  bool languagesChosen = false;

  void _finish() {
    widget.app.user.setSetting('onboarded', '1');
    widget.onDone();
  }

  @override
  void dispose() {
    pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!languagesChosen) {
      return _LanguageStep(app: widget.app, onNext: () => setState(() => languagesChosen = true));
    }
    final theme = Theme.of(context);
    final pages = [
      (const _BooksArt(), L('Sevdiğin kitabı İngilizce oku', 'Read the books you love in English'),
          L('EPUB, PDF, Word ve daha fazlasını ekle. Kitapların cihazında saklanır, internet olmadan da okunur.', 'Add EPUB, PDF, Word and more. Your books stay on your device and work without internet.')),
      (_TapArt(app: widget.app), L('Bilmediğin kelimeye dokun', 'Tap a word you don\'t know'),
          L('Anlamı, cümledeki kullanımı, deyimler ve öbek fiiller anında açılır. Uzun basarsan cümlenin tamamı çözümlenir.', 'Its meaning, how it is used in the sentence, idioms and phrasal verbs open at once. Long press to analyze the whole sentence.')),
      (const _ReviewArt(), L('Tekrar et, kalıcı olsun', 'Review and make it stick'),
          L('Öğreneceğin kelimeler doğru zamanda karşına çıkar. Her gün birkaç dakika ile serini büyüt.', 'The words you save come back at the right time. A few minutes a day grows your streak.')),
    ];
    final last = page == pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                child: Row(children: [
                  const Wordmark(height: 22),
                  const Spacer(),
                  if (!last) TextButton(onPressed: _finish, child: Text(L('Atla', 'Skip'))),
                ]),
              ),
              Expanded(
                child: PageView(
                  controller: pc,
                  onPageChanged: (i) => setState(() => page = i),
                  children: [
                    for (final (art, title, body) in pages)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Column(children: [
                          Expanded(child: Center(child: art)),
                          Text(title, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall?.copyWith(fontSize: 26)),
                          const SizedBox(height: 12),
                          Text(body,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.5)),
                          const SizedBox(height: 24),
                        ]),
                      ),
                  ],
                ),
              ),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: i == page ? 22 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: i == page ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ]),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                  onPressed: last ? _finish : () => pc.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic),
                  child: Text(last ? L('Başla', 'Get started') : L('İleri', 'Next')),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The first question: "My language" and "I want to learn". They are never
/// the same, so picking one sets the other. The menus follow the native
/// language here; Settings can change all three later.
class _LanguageStep extends StatelessWidget {
  final AppState app;
  final VoidCallback onNext;
  const _LanguageStep({required this.app, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // Turkish books need the Turkish-English dictionary.
    final canLearnTr = app.trEn != null;
    Widget question(String label, IconData icon, String value, ValueChanged<String> onPick, {bool trEnabled = true}) =>
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(icon, size: 20, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            showSelectedIcon: true,
            style: SegmentedButton.styleFrom(minimumSize: const Size.fromHeight(52), textStyle: theme.textTheme.titleSmall),
            segments: [
              ButtonSegment(value: 'tr', label: Text(L('Türkçe', 'Turkish')), enabled: trEnabled),
              ButtonSegment(value: 'en', label: Text(L('İngilizce', 'English'))),
            ],
            selected: {value},
            onSelectionChanged: (v) => onPick(v.first),
          ),
        ]);
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => Scaffold(
        key: const ValueKey('onboarding-languages'),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.only(top: 6), child: Wordmark(height: 22))),
                  const Spacer(),
                  Text(L('Dillerini seç', 'Choose your languages'), textAlign: TextAlign.center, style: theme.textTheme.headlineSmall?.copyWith(fontSize: 26)),
                  const SizedBox(height: 10),
                  Text(
                    L('Kelime anlamları ana dilinde gösterilir. İstediğin zaman Ayarlar > Dil bölümünden değiştirebilirsin.',
                        'Word meanings are shown in your native language. You can change this any time in Settings > Language.'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant, height: 1.5),
                  ),
                  const SizedBox(height: 32),
                  KeyedSubtree(
                    key: const ValueKey('onboarding-native'),
                    child: question(L('Ana dilim', 'My native language'), Icons.person_outline_rounded, app.nativeLang, (v) => app.setUiEnglish(v == 'en')),
                  ),
                  const SizedBox(height: 24),
                  KeyedSubtree(
                    key: const ValueKey('onboarding-learn'),
                    child: question(L('Öğrenmek istediğim dil', 'Language I want to learn'), Icons.school_outlined, app.learnLang,
                        (v) => app.setUiEnglish(v == 'tr'), trEnabled: canLearnTr || app.learnLang == 'tr'),
                  ),
                  const Spacer(flex: 2),
                  FilledButton(
                    key: const ValueKey('onboarding-languages-next'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                    onPressed: onNext,
                    child: Text(L('Devam', 'Continue')),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BooksArt extends StatelessWidget {
  const _BooksArt();

  @override
  Widget build(BuildContext context) {
    Widget cover(String t, String f, double w, double angle, Offset o, int c) => Transform.translate(
          offset: o,
          child: Transform.rotate(angle: angle, child: BookCover(title: t, format: f, width: w, colors: Brand.covers[c])),
        );
    return SizedBox(
      width: 280,
      height: 240,
      child: Stack(alignment: Alignment.center, children: [
        Container(width: 220, height: 220, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, shape: BoxShape.circle)),
        cover('Hemingway', 'pdf', 92, -0.18, const Offset(-70, 16), 1),
        cover('Wonder', 'docx', 92, 0.18, const Offset(70, 16), 2),
        cover('Pride', 'epub', 112, 0, const Offset(0, 0), 0),
      ]),
    );
  }
}

class _TapArt extends StatelessWidget {
  final AppState app;
  const _TapArt({required this.app});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final base = TextStyle(fontFamily: readingFont, fontSize: 19, height: 1.6, color: t.colorScheme.onSurface);
    return Container(
      width: 320,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: readerPaper(t),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: t.colorScheme.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text.rich(TextSpan(style: base, children: [
          const TextSpan(text: 'He never once thought of '),
          TextSpan(
            text: 'giving up',
            style: TextStyle(color: categoryById['phrasal_verbs']!.color, fontWeight: FontWeight.w600, decoration: TextDecoration.underline, decorationColor: categoryById['phrasal_verbs']!.color, decorationThickness: 2),
          ),
          const TextSpan(text: ', '),
          TextSpan(text: 'although', style: TextStyle(color: categoryById['conjunctions']!.color, fontWeight: FontWeight.w600, decoration: TextDecoration.underline, decorationColor: categoryById['conjunctions']!.color, decorationThickness: 2)),
          const TextSpan(text: ' the sea was '),
          TextSpan(text: 'stormy', style: TextStyle(backgroundColor: learningColor.withValues(alpha: 0.38))),
          const TextSpan(text: '.'),
        ])),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: t.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, 8))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('give up', style: enStyle(t, t.textTheme.titleMedium).copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              Text(L('Öbek fiiller', 'Phrasal Verbs'), style: TextStyle(color: categoryById['phrasal_verbs']!.color, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 2),
            Text('vazgeçmek, bırakmak', style: trStyle(t, t.textTheme.bodyLarge)),
          ]),
        ),
      ]),
    );
  }
}

class _ReviewArt extends StatelessWidget {
  const _ReviewArt();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    Widget card(double angle, Offset o, {Widget? child}) => Transform.translate(
          offset: o,
          child: Transform.rotate(
            angle: angle,
            child: Container(
              width: 210,
              height: 150,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: t.colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: t.colorScheme.outlineVariant),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 6))],
              ),
              child: child,
            ),
          ),
        );
    return SizedBox(
      width: 300,
      height: 250,
      child: Stack(alignment: Alignment.center, children: [
        Container(width: 220, height: 220, decoration: BoxDecoration(color: t.colorScheme.primaryContainer, shape: BoxShape.circle)),
        card(-0.12, const Offset(-18, 10)),
        card(0.05, const Offset(6, -4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('narrow', style: enStyle(t, t.textTheme.headlineSmall).copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('dar, ensiz', style: trStyle(t, t.textTheme.titleMedium)),
              const Spacer(),
              Row(children: [
                for (final c in [const Color(0xFFE5484D), learningColor, learnedColor])
                  Container(width: 40, height: 14, margin: const EdgeInsets.only(right: 6), decoration: BoxDecoration(color: c.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(5))),
              ]),
            ])),
        Positioned(
          right: 18,
          top: 20,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: const Color(0xFFF97316), borderRadius: BorderRadius.circular(14)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.local_fire_department_rounded, color: Colors.white, size: 20),
              SizedBox(width: 4),
              Text('7', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
            ]),
          ),
        ),
      ]),
    );
  }
}
