import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../l10n.dart';
import '../online/ai_service.dart';
import '../online/update_check.dart';
import 'update_prompt.dart';
import '../tts/speech.dart';
import '../tts/voice_ui.dart';
import 'key_guide.dart';
import 'theme.dart';

// Settings: a short main list in groups. Items with a few fixed choices use a
// drop-down on the row itself; bigger topics open their own page.

String _versionLabel() => appBuild == 0 ? L('Geliştirme derlemesi', 'Development build') : L('Sürüm ${appVersion.isEmpty ? '1.0' : appVersion}', 'Version ${appVersion.isEmpty ? '1.0' : appVersion}');

class SettingsPage extends StatelessWidget {
  final AppState app;
  const SettingsPage({super.key, required this.app});

  void _push(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final provider = AiSettings.active(app.user)?.provider;
        final meaning = app.showTr && app.showEn ? 'both' : (app.showEn ? 'en' : 'tr');
        return Scaffold(
          appBar: AppBar(toolbarHeight: 68, title: Text(L('Ayarlar', 'Settings'), style: theme.textTheme.headlineSmall)),
          body: _SettingsList(children: [
            SettingsGroup(title: L('Genel', 'General'), children: [
              SettingsDropdownTile<String>(
                key: const ValueKey('setting-native'),
                icon: Icons.language_rounded,
                color: const Color(0xFF2563EB),
                title: L('Ana dil', 'Native language'),
                subtitle: L('Menüler, açıklamalar ve anlamlar', 'Menus, explanations and meanings'),
                value: app.nativeLang,
                items: const {'tr': 'Türkçe', 'en': 'English'},
                onChanged: (v) => app.setLanguages(native: v),
              ),
              if (app.trEn != null)
                SettingsDropdownTile<String>(
                  key: const ValueKey('setting-learn'),
                  icon: Icons.school_rounded,
                  color: const Color(0xFFDB2777),
                  title: L('Öğrenilen dil', 'Language you learn'),
                  subtitle: L('Okuduğun kitapların dili', 'The language of your books'),
                  value: app.learnLang,
                  items: {'en': L('İngilizce', 'English'), 'tr': L('Türkçe', 'Turkish')},
                  onChanged: (v) => app.setLanguages(learn: v),
                ),
              SettingsDropdownTile<ThemeMode>(
                icon: Icons.contrast_rounded,
                color: const Color(0xFF7C3AED),
                title: L('Tema', 'Theme'),
                value: app.themeMode,
                items: {ThemeMode.light: L('Gündüz', 'Day'), ThemeMode.dark: L('Gece', 'Night'), ThemeMode.system: L('Sistem', 'System')},
                onChanged: app.setTheme,
              ),
              if (!app.learnTurkish)
              SettingsDropdownTile<String>(
                icon: Icons.translate_rounded,
                color: const Color(0xFF0E9F6E),
                title: L('Anlam dili', 'Meaning language'),
                subtitle: L('Kelime panelinde', 'In the word panel'),
                value: meaning,
                items: {'tr': 'Türkçe', 'en': 'English', 'both': L('İkisi birden', 'Both')},
                onChanged: (v) => app.setLang(tr: v != 'en', en: v != 'tr'),
              ),
            ]),
            SettingsGroup(title: L('Öğrenme araçları', 'Learning tools'), children: [
              ListenableBuilder(
                listenable: Speech.instance,
                builder: (context, _) {
                  final s = Speech.instance;
                  return SettingsNavTile(
                    icon: Icons.record_voice_over_rounded,
                    color: const Color(0xFFE0752D),
                    title: L('Sesli okuma', 'Read aloud'),
                    subtitle: !Speech.supported
                        ? L('Bu cihazda desteklenmiyor', 'Not supported on this device')
                        : s.ready
                            ? '${s.voice.name} · ${s.speed.toStringAsFixed(2)}×'
                            : L('Ses paketi indirilmedi', 'Voice pack not downloaded'),
                    onTap: () => _push(context, const VoiceSettingsPage()),
                  );
                },
              ),
              SettingsNavTile(
                key: const ValueKey('settings-ai'),
                icon: Icons.auto_awesome_rounded,
                color: const Color(0xFF0891B2),
                title: L('Yapay zekâ servisi', 'AI service'),
                subtitle: provider == null ? L('Bağlı değil · kendi anahtarınla çalışır', 'Not connected · works with your own key') : L('${provider.name} bağlı', '${provider.name} connected'),
                onTap: () => _push(context, AiServicePage(app: app)),
              ),
              Builder(builder: (context) {
                final n = app.user.senseFeedbackCount();
                return SettingsNavTile(
                  key: const ValueKey('settings-sense-feedback'),
                  icon: Icons.flag_outlined,
                  color: const Color(0xFFDC2626),
                  title: L('Anlam bildirimleri', 'Meaning reports'),
                  subtitle: n == 0
                      ? L('"Anlam yanlış" bildirimin yok', 'No "wrong meaning" reports')
                      : L('$n bildirim · dışa aktar', '$n reports · export'),
                  onTap: () => _exportSenseFeedback(context, app),
                );
              }),
            ]),
            SettingsGroup(title: L('Hakkında', 'About'), children: [
              SettingsNavTile(
                icon: Icons.local_florist_rounded,
                color: Brand.gold,
                title: 'Storilex',
                subtitle: _versionLabel(),
                onTap: () => _push(context, const AboutPage()),
              ),
              SettingsNavTile(
                icon: Icons.shield_outlined,
                color: const Color(0xFF475569),
                title: L('Gizlilik ve lisanslar', 'Privacy and licenses'),
                subtitle: L('Verilerin yalnızca bu cihazda', 'Your data stays on this device'),
                onTap: () => _push(context, const LicensesPage()),
              ),
            ]),
          ]),
        );
      },
    );
  }
}

/// Saves the "wrong meaning" reports as a TSV file (or copies them when the
/// device has no save dialog), for improving the dictionary.
Future<void> _exportSenseFeedback(BuildContext context, AppState app) async {
  final m = ScaffoldMessenger.of(context);
  if (app.user.senseFeedbackCount() == 0) {
    m.showSnackBar(SnackBar(content: Text(L('Henüz "Anlam yanlış" bildirimi yok.', 'No "wrong meaning" reports yet.'))));
    return;
  }
  final text = app.user.senseFeedbackTsv();
  try {
    final saved = await FilePicker.saveFile(
      dialogTitle: L('Anlam bildirimlerini kaydet', 'Save the meaning reports'),
      fileName: 'vocabloom-anlam-bildirimleri.tsv',
      bytes: Uint8List.fromList(utf8.encode(text)),
      mimeType: 'text/tab-separated-values',
    );
    if (saved != null) m.showSnackBar(SnackBar(content: Text(L('Bildirimler kaydedildi.', 'Reports saved.'))));
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: text));
    m.showSnackBar(SnackBar(content: Text(L('Dosya kaydedilemedi; bildirimler panoya kopyalandı.', 'Could not save a file; the reports were copied to the clipboard.'))));
  }
}

// ------------------------------------------------------------------ building blocks

class _SettingsList extends StatelessWidget {
  final List<Widget> children;
  const _SettingsList({required this.children});

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: children),
        ),
      );
}

/// A titled group of rows in one rounded box.
class SettingsGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const SettingsGroup({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionLabel(title),
      Material(
        color: cs.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: cs.outlineVariant)),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (final (i, c) in children.indexed) ...[
            if (i > 0) Divider(height: 1, indent: 64, color: cs.outlineVariant),
            c,
          ],
        ]),
      ),
    ]);
  }
}

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _IconBadge(this.icon, this.color);

  // One calm gold badge for every row; [color] is kept for callers.
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(color: goldSoft(t), borderRadius: BorderRadius.circular(13)),
      child: Icon(icon, color: t.colorScheme.primary, size: 19),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _Row({required this.icon, required this.color, required this.title, this.subtitle, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Row(children: [
            _IconBadge(icon, color),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ]),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ]),
        ),
      ),
    );
  }
}

/// A row that opens its own page.
class SettingsNavTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  const SettingsNavTile({super.key, required this.icon, required this.color, required this.title, this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) => _Row(
        icon: icon,
        color: color,
        title: title,
        subtitle: subtitle,
        onTap: onTap,
        trailing: Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
}

/// A row with an on/off switch.
class SettingsSwitchTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const SettingsSwitchTile({super.key, required this.icon, required this.color, required this.title, this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => _Row(
        icon: icon,
        color: color,
        title: title,
        subtitle: subtitle,
        onTap: () => onChanged(!value),
        trailing: Switch(value: value, onChanged: onChanged),
      );
}

/// A row with a drop-down of a few fixed choices.
class SettingsDropdownTile<T> extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;
  const SettingsDropdownTile(
      {super.key, required this.icon, required this.color, required this.title, this.subtitle, required this.value, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Row(
      icon: icon,
      color: color,
      title: title,
      subtitle: subtitle,
      trailing: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          borderRadius: BorderRadius.circular(14),
          icon: Icon(Icons.unfold_more_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w600),
          alignment: AlignmentDirectional.centerEnd,
          items: [for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => v == null ? null : onChanged(v),
        ),
      ),
    );
  }
}

/// A plain sub-page with a title and a list body.
class _SubPage extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SubPage({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: _SettingsList(children: [const SizedBox(height: 8), ...children]),
      );
}

// ------------------------------------------------------------------ sub-pages

class VoiceSettingsPage extends StatelessWidget {
  const VoiceSettingsPage({super.key});

  @override
  Widget build(BuildContext context) => _SubPage(title: L('Sesli okuma', 'Read aloud'), children: [
        Panel(children: const [VoiceSettings()]),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
          child: Text(L('Sesler cihazında çalışır, internet gerekmez.', 'Voices run on your device and need no internet.'),
              style: Theme.of(context).textTheme.bodySmall),
        ),
      ]);
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SubPage(title: L('Hakkında', 'About'), children: [
      Panel(children: [
        Row(children: [
          const BrandMark(size: 52),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Storilex', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              Text(_versionLabel(), style: theme.textTheme.bodySmall),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Text(
          L('Storilex ile okuduğun her kitap bir İngilizce dersine dönüşür: bilinmeyen kelimeler anında açıklanır, tekrar sistemiyle kalıcı hale gelir. Storilex, dil öğrenenlerin gelişimini desteklemek amacıyla tasarlanmış ve geliştirilmiştir.',
              'With Storilex, every book you read becomes an English lesson: unknown words are explained instantly and made permanent through spaced review. Storilex is designed and built to support language learners\' progress.'),
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
        ),
        const SizedBox(height: 12),
        Text(L('© 2026 Hamit Gök. Tüm hakları saklıdır.', '© 2026 Hamit Gök. All rights reserved.'), style: theme.textTheme.bodySmall),
        const SizedBox(height: 14),
        const CheckUpdateButton(),
      ]),
    ]);
  }
}

class LicensesPage extends StatelessWidget {
  const LicensesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium?.copyWith(height: 1.5);
    Widget item(String s) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('•  '),
            Expanded(child: Text(s, style: theme.textTheme.bodySmall?.copyWith(height: 1.45))),
          ]),
        );
    return _SubPage(title: L('Gizlilik ve lisanslar', 'Privacy and licenses'), children: [
      SectionLabel(L('Gizlilik', 'Privacy'), padding: const EdgeInsets.fromLTRB(4, 4, 4, 8)),
      Panel(children: [
        Text(
          L('Tüm kitapların, kelime listen ve ayarların yalnızca bu cihazda saklanır. API anahtarları da yalnızca cihazda tutulur ve sadece seçtiğin servise gönderilir.',
              'All your books, your word list and your settings are stored only on this device. API keys are also kept only on the device and are sent only to the service you choose.'),
          style: body,
        ),
      ]),
      SectionLabel(L('Sözlük kaynakları', 'Dictionary sources')),
      Panel(children: [
        item(L('Kelime anlamları: Wiktionary çevirileri, kaikki.org üzerinden; Murat Uysal\'ın Kindle İngilizce–Türkçe sözlüğü derlemesi (CC BY-SA 4.0)',
            'Word meanings: Wiktionary translations via kaikki.org, as compiled in Murat Uysal\'s Kindle English–Turkish dictionary (CC BY-SA 4.0)')),
        item(L('Yardımcı kelime anlamları: damdafayton/eng-tur-dictionary (MIT)', 'Helper word meanings: damdafayton/eng-tur-dictionary (MIT)')),
        item('FreeDict English–Turkish (GPL-2.0+)'),
        item('Princeton WordNet 3.0 (WordNet License)'),
        item(L('KeNet Türkçe WordNet, Starlang / Özyeğin Üniversitesi (CC BY-SA 4.0)', 'KeNet Turkish WordNet, Starlang / Özyeğin University (CC BY-SA 4.0)')),
        item('Collaborative Interlingual Index (CC BY 4.0)'),
        item(L('Kalıplar: İngilizce ve Türkçe Vikisözlük, kaikki.org üzerinden (CC BY-SA 4.0)', 'Expressions: English and Turkish Wiktionary via kaikki.org (CC BY-SA 4.0)')),
        item(L('Çevirili örnek cümleler: Tatoeba (CC BY 2.0 FR)', 'Example sentences with translations: Tatoeba (CC BY 2.0 FR)')),
        item(L('Ücretsiz kütüphane: Pratham Books / StoryWeaver hikâyeleri (CC BY 4.0, yalnız metin, global-asp/pb-source üzerinden); Project Gutenberg kamu malı kitaplar',
            'Free library: Pratham Books / StoryWeaver stories (CC BY 4.0, text only, via global-asp/pb-source); public-domain books from Project Gutenberg')),
        item(L('Türkçe → İngilizce sözlük: İngilizce Vikisözlük\'teki Türkçe kelimeler, kaikki.org üzerinden (CC BY-SA 4.0); kelime sıklığı: FrequencyWords / OpenSubtitles 2018 (CC BY-SA 4.0); örnek cümleler: Tatoeba katkıcıları (CC BY 2.0 FR)',
            'Turkish → English dictionary: Turkish entries of the English Wiktionary via kaikki.org (CC BY-SA 4.0); word frequency: FrequencyWords / OpenSubtitles 2018 (CC BY-SA 4.0); example sentences: Tatoeba contributors (CC BY 2.0 FR)')),
        item(L('Türkçe ücretsiz kütüphane: Vikikaynak\'taki kamu malı eserler (tr.wikisource.org; yazarları 1955\'ten önce ölmüş eserler ve anonim halk anlatıları); A1–B1 öyküler bu uygulama için yazıldı. Kelimenin cümledeki anlamı Tatoeba cümle çiftlerinden çıkarılır.',
            'Turkish free library: public-domain works from Turkish Wikisource (tr.wikisource.org; authors who died before 1955 and anonymous folk tales); the A1–B1 stories were written for this app. The meaning of a word in its sentence is learned from Tatoeba sentence pairs.')),
        item(L('Kategori listeleri bu uygulama için hazırlandı (CC BY-SA 4.0)', 'Category lists written for this app (CC BY-SA 4.0)')),
        item(L('Uygulamadaki sözlük veritabanı bu kaynaklardan uyarlanmıştır ve aynı lisansla (CC BY-SA 4.0) paylaşılır. Lisans metinleri: creativecommons.org/licenses/by-sa/4.0 · gnu.org/licenses/gpl-3.0',
            'The dictionary database in the app is adapted from these sources and shared under the same licence (CC BY-SA 4.0). Licence texts: creativecommons.org/licenses/by-sa/4.0 · gnu.org/licenses/gpl-3.0')),
      ]),
      SectionLabel(L('Yazı tipleri ve sesler', 'Fonts and voices')),
      Panel(children: [
        item(L('Yazı tipleri: Inter ve Literata (SIL Open Font License 1.1)', 'Fonts: Inter and Literata (SIL Open Font License 1.1)')),
        item(L('Sesler: Kokoro-82M (Apache 2.0), Piper LibriTTS-R (CC BY 4.0), EMA Lightning Türkçe (Apache 2.0), Piper Fahrettin (CC0 kayıtlar), ONNX Runtime (MIT), sherpa-onnx (Apache 2.0), eSpeak NG (GPL-3.0)', 'Voices: Kokoro-82M (Apache 2.0), Piper LibriTTS-R (CC BY 4.0), EMA Lightning Turkish (Apache 2.0), Piper Fahrettin (CC0 recordings), ONNX Runtime (MIT), sherpa-onnx (Apache 2.0), eSpeak NG (GPL-3.0)')),
      ]),
      SectionLabel(L('Yazılım', 'Software')),
      Panel(children: [
        item(L('Storilex açık kaynaklıdır (GPL-3.0): github.com/hamitgk-beep/vocabloom', 'Storilex is open source (GPL-3.0): github.com/hamitgk-beep/vocabloom')),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.description_outlined, size: 18),
            label: Text(L('Kullanılan kütüphanelerin lisansları', 'Licences of the libraries used')),
            onPressed: () => showLicensePage(context: context, applicationName: 'Storilex'),
          ),
        ),
      ]),
    ]);
  }
}

/// The online translation / summary service: provider, key, model, test.
class AiServicePage extends StatefulWidget {
  final AppState app;
  const AiServicePage({super.key, required this.app});

  @override
  State<AiServicePage> createState() => _AiServicePageState();
}

class _AiServicePageState extends State<AiServicePage> {
  late String providerId = AiSettings.activeId(widget.app.user) ?? 'gemini';
  final key = TextEditingController();
  final model = TextEditingController();
  final url = TextEditingController();
  bool obscure = true;
  String? testResult;
  bool testing = false;

  @override
  void initState() {
    super.initState();
    if (!providerById.containsKey(providerId)) providerId = providers.first.id;
    _loadFields();
  }

  @override
  void dispose() {
    key.dispose();
    model.dispose();
    url.dispose();
    super.dispose();
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
    final m = model.text.trim();
    // The default is not saved, so a later version's better default applies.
    u.setSetting('ai_model_$providerId', m.isEmpty || m == providerById[providerId]!.defaultModel ? null : m);
    u.setSetting('ai_url_$providerId', url.text.trim().isEmpty ? null : url.text.trim());
  }

  Future<void> _test() async {
    _save();
    final svc = AiService.fromSettings(widget.app.user);
    if (svc == null) {
      setState(() => testResult = L('Eksik bilgi var (anahtar, model veya adres).', 'Some information is missing (key, model or address).'));
      return;
    }
    setState(() {
      testing = true;
      testResult = null;
    });
    try {
      final r = await svc.translateChunk(['The weather is lovely today.']);
      if (!mounted) return;
      setState(() => testResult = L('Çalışıyor ✓  "${r.translations.firstOrNull ?? ''}"', 'Working ✓  "${r.translations.firstOrNull ?? ''}"'));
      widget.app.analyzer.tick();
    } catch (e) {
      if (mounted) setState(() => testResult = L('Hata: ${errorText(e)}', 'Error: ${errorText(e)}'));
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
    Widget point(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(height: 1.4))),
          ]),
        );
    return _SubPage(title: L('Yapay zekâ servisi', 'AI service'), children: [
      Panel(children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(gradient: Brand.gradient, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(L('Kendi anahtarınla yapay zekâ', 'AI with your own key'),
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ),
        ]),
        point(Icons.forum_rounded, L('Kelime, cümle, gramer ve sözlükteki "Yapay zekâya sor" düğmelerini çalıştırır.', 'Powers the "Ask the AI" buttons on words, sentences, grammar and the dictionary.')),
        point(Icons.translate_rounded, L('İnternet olunca kitaplarının cümle çevirilerini ve bölüm özetlerini hazırlayıp cihaza kaydeder.', 'When online, prepares sentence translations and chapter summaries of your books and saves them on the device.')),
        point(Icons.savings_rounded, L('Google Gemini\'nin ücretsiz planı yeterli. Ücret varsa kendi hesabından düşer.', 'Google Gemini\'s free plan is enough. Any fee is billed to your own account.')),
        point(Icons.lock_rounded, L('Anahtar yalnızca bu cihazda saklanır. Uygulamanın geri kalanı servis olmadan da çalışır.', 'The key stays on this device. The rest of the app works without the service.')),
      ]),
      SectionLabel(L('Servis', 'Service')),
      Panel(children: [
        DropdownButtonFormField<String>(
          initialValue: providerId,
          isExpanded: true,
          decoration: InputDecoration(labelText: L('Servis', 'Service')),
          items: [for (final x in providers) DropdownMenuItem(value: x.id, child: Text(x.name))],
          onChanged: (v) => setState(() {
            _save();
            providerId = v!;
            _loadFields();
            u.setSetting('ai_provider', providerId);
          }),
        ),
        if (keyGuides.containsKey(p.id))
          KeyGuideCard(providerId: p.id)
        else if (p.keyHelp.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(p.keyHelp, style: theme.textTheme.bodySmall)),
        const SizedBox(height: 12),
        if (showUrl) ...[
          TextField(
            controller: url,
            decoration: InputDecoration(
              labelText: p.kind == ApiKind.azure
                  ? L('Uç nokta (https://<kaynak>.openai.azure.com)', 'Endpoint (https://<resource>.openai.azure.com)')
                  : L('Adres (base URL)', 'Address (base URL)'),
            ),
            onChanged: (_) => _save(),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: key,
          obscureText: obscure,
          decoration: InputDecoration(
            labelText: p.needsKey ? L('API anahtarı', 'API key') : L('API anahtarı (gerekmiyorsa boş bırak)', 'API key (leave empty if not needed)'),
            suffixIcon: IconButton(icon: Icon(obscure ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => obscure = !obscure)),
          ),
          onChanged: (_) => _save(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: model,
          decoration: InputDecoration(
            labelText: p.kind == ApiKind.azure ? L('Dağıtım (deployment) adı', 'Deployment name') : L('Model adı', 'Model name'),
            helperText: L('Servisin model listesinden istediğini yazabilirsin. Varsayılan: ${p.defaultModel}', 'You can enter any model from the service\'s list. Default: ${p.defaultModel}'),
            helperMaxLines: 2,
          ),
          onChanged: (_) => _save(),
        ),
        const SizedBox(height: 14),
        Row(children: [
          FilledButton.tonalIcon(
            onPressed: testing ? null : _test,
            icon: testing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi_tethering),
            label: Text(L('Bağlantıyı dene', 'Test connection')),
          ),
        ]),
        if (testResult != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(testResult!)),
        if (!p.vision)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
                L('Not: ${p.name} resimdeki yazıyı okuyamaz; taranmış PDF için cihazın kendi OCR\'ı kullanılır.', 'Note: ${p.name} cannot read text in images; the device\'s own OCR is used for scanned PDFs.'),
                style: theme.textTheme.bodySmall),
          ),
      ]),
      SectionLabel(L('Tarama', 'Scanning')),
      Panel(padding: const EdgeInsets.fromLTRB(16, 4, 8, 4), children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(L('İnternet olunca kitapları otomatik tara', 'Scan books automatically when online')),
          subtitle: Text(L('Kitaplar çevrilir, sonra sözlükte yalnızca İngilizce açıklaması olan kalıplar Türkçeye çevrilip cihaza kaydedilir. Kapalıysa kitap menüsünden elle başlatabilirsin.',
              'Books are translated first; then dictionary entries that only have an English definition are translated into Turkish and saved on the device. When off, you can start it from the book menu.')),
          value: u.getSetting('auto_analyze') != '0',
          onChanged: (v) => setState(() {
            u.setSetting('auto_analyze', v ? null : '0');
            if (v) app.analyzer.tick();
          }),
        ),
        ValueListenableBuilder<String?>(
          valueListenable: app.analyzer.dictStatus,
          builder: (context, s, _) => s == null ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(s, style: theme.textTheme.bodySmall)),
        ),
      ]),
    ]);
  }
}
