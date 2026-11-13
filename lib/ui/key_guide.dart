import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n.dart';

/// Where to get an API key for each AI service, and how, step by step.
class KeyGuide {
  final String url;
  final bool free; // has a free tier
  final String costTr, costEn;
  final List<String> stepsTr, stepsEn;
  const KeyGuide(this.url, this.free, this.costTr, this.costEn, this.stepsTr, this.stepsEn);
}

const keyGuides = <String, KeyGuide>{
  'gemini': KeyGuide(
    'https://aistudio.google.com/app/apikey',
    true,
    'Ücretsiz kullanım hakkı var, kart gerekmez. Başlamak için en kolayı.',
    'Has a free tier, no card needed. The easiest way to start.',
    [
      'Aşağıdaki "Siteyi aç" düğmesine bas ve Google hesabınla giriş yap.',
      '"Create API key" (API anahtarı oluştur) düğmesine bas. Proje sorarsa önerilen projeyi seç.',
      'Oluşan anahtarı (AIza ile başlar) kopyala.',
      'Buraya dönüp "API anahtarı" kutusuna yapıştır, sonra "Bağlantıyı dene"ye bas.',
    ],
    [
      'Press "Open site" below and sign in with your Google account.',
      'Press "Create API key". If it asks for a project, pick the suggested one.',
      'Copy the key (it starts with AIza).',
      'Come back, paste it into "API key", then press "Test connection".',
    ],
  ),
  'groq': KeyGuide(
    'https://console.groq.com/keys',
    true,
    'Ücretsiz kullanım hakkı var, kart gerekmez. Çok hızlıdır ama resimli PDF okuyamaz.',
    'Has a free tier, no card needed. Very fast, but cannot read image PDFs.',
    [
      '"Siteyi aç"a bas, Google hesabınla ya da e-postanla giriş yap.',
      '"Create API Key" düğmesine bas, bir isim yaz (ör. VocaBloom) ve "Submit" de.',
      'Anahtar yalnızca bir kez gösterilir (gsk_ ile başlar), hemen kopyala.',
      'Buraya dönüp "API anahtarı" kutusuna yapıştır ve "Bağlantıyı dene"ye bas.',
    ],
    [
      'Press "Open site", sign in with Google or your email.',
      'Press "Create API Key", type a name (e.g. VocaBloom) and press "Submit".',
      'The key (starts with gsk_) is shown only once, copy it right away.',
      'Come back, paste it into "API key" and press "Test connection".',
    ],
  ),
  'anthropic': KeyGuide(
    'https://console.anthropic.com/settings/keys',
    false,
    'Ücretli. Hesabına önceden kredi yüklersin (en az 5 dolar), kullandıkça düşer. Claude.ai aboneliği API\'yi kapsamaz.',
    'Paid. You add credit in advance (at least \$5) and it is used up as you go. A Claude.ai subscription does not cover the API.',
    [
      '"Siteyi aç"a bas, hesap aç ya da giriş yap.',
      'Soldaki "Billing" bölümünden kredi yükle.',
      '"API Keys" sayfasında "Create Key" de, bir isim ver ve oluştur.',
      'Anahtar yalnızca bir kez gösterilir (sk-ant- ile başlar), kopyala.',
      'Buraya dönüp "API anahtarı" kutusuna yapıştır ve "Bağlantıyı dene"ye bas.',
    ],
    [
      'Press "Open site", create an account or sign in.',
      'Add credit under "Billing" on the left.',
      'On "API Keys", press "Create Key", give it a name and create it.',
      'The key (starts with sk-ant-) is shown only once, copy it.',
      'Come back, paste it into "API key" and press "Test connection".',
    ],
  ),
  'openai': KeyGuide(
    'https://platform.openai.com/api-keys',
    false,
    'Ücretli. Önceden kredi yüklersin (en az 5 dolar). ChatGPT Plus aboneliği API\'yi kapsamaz.',
    'Paid. You add credit in advance (at least \$5). A ChatGPT Plus subscription does not cover the API.',
    [
      '"Siteyi aç"a bas, ChatGPT hesabınla giriş yap.',
      'Ayarlar → "Billing" bölümünden kredi yükle.',
      '"API keys" sayfasında "Create new secret key" de ve oluştur.',
      'Anahtar yalnızca bir kez gösterilir (sk- ile başlar), kopyala.',
      'Buraya dönüp "API anahtarı" kutusuna yapıştır ve "Bağlantıyı dene"ye bas.',
    ],
    [
      'Press "Open site" and sign in with your ChatGPT account.',
      'Add credit under Settings → "Billing".',
      'On "API keys", press "Create new secret key" and create it.',
      'The key (starts with sk-) is shown only once, copy it.',
      'Come back, paste it into "API key" and press "Test connection".',
    ],
  ),
  'deepseek': KeyGuide(
    'https://platform.deepseek.com/api_keys',
    false,
    'Ücretli ama çok ucuz. Önceden küçük bir kredi yüklersin.',
    'Paid but very cheap. You add a small credit in advance.',
    [
      '"Siteyi aç"a bas, hesap aç ya da giriş yap.',
      '"Top up" bölümünden kredi yükle.',
      '"API keys" sayfasında "Create new API key" de.',
      'Anahtarı kopyala (yalnızca bir kez gösterilir).',
      'Buraya dönüp "API anahtarı" kutusuna yapıştır ve "Bağlantıyı dene"ye bas.',
    ],
    [
      'Press "Open site", create an account or sign in.',
      'Add credit under "Top up".',
      'On "API keys", press "Create new API key".',
      'Copy the key (it is shown only once).',
      'Come back, paste it into "API key" and press "Test connection".',
    ],
  ),
  'mistral': KeyGuide(
    'https://console.mistral.ai/api-keys',
    true,
    'Ücretsiz deneme planı var (telefon doğrulaması ister). Daha fazlası ücretli.',
    'Has a free trial plan (needs phone verification). More is paid.',
    [
      '"Siteyi aç"a bas, hesap aç ya da giriş yap.',
      'Plan sorarsa ücretsiz "Experiment" planını seç ve telefonunu doğrula.',
      '"API Keys" sayfasında "Create new key" de.',
      'Anahtarı kopyala (yalnızca bir kez gösterilir).',
      'Buraya dönüp "API anahtarı" kutusuna yapıştır ve "Bağlantıyı dene"ye bas.',
    ],
    [
      'Press "Open site", create an account or sign in.',
      'If it asks for a plan, pick the free "Experiment" plan and verify your phone.',
      'On "API Keys", press "Create new key".',
      'Copy the key (it is shown only once).',
      'Come back, paste it into "API key" and press "Test connection".',
    ],
  ),
  'xai': KeyGuide(
    'https://console.x.ai',
    false,
    'Ücretli. Önceden kredi yüklersin.',
    'Paid. You add credit in advance.',
    [
      '"Siteyi aç"a bas, X hesabınla ya da e-postanla giriş yap.',
      '"Billing" bölümünden kredi yükle.',
      '"API Keys" sayfasında "Create API Key" de.',
      'Anahtarı kopyala (xai- ile başlar).',
      'Buraya dönüp "API anahtarı" kutusuna yapıştır ve "Bağlantıyı dene"ye bas.',
    ],
    [
      'Press "Open site", sign in with your X account or email.',
      'Add credit under "Billing".',
      'On "API Keys", press "Create API Key".',
      'Copy the key (starts with xai-).',
      'Come back, paste it into "API key" and press "Test connection".',
    ],
  ),
  'openrouter': KeyGuide(
    'https://openrouter.ai/keys',
    true,
    'Tek anahtarla yüzlerce model. Adı ":free" ile biten modeller ücretsiz, diğerleri için kredi yüklersin.',
    'Hundreds of models with one key. Models ending in ":free" are free; others need credit.',
    [
      '"Siteyi aç"a bas, Google hesabınla ya da e-postanla giriş yap.',
      '"Create Key" de, bir isim ver ve oluştur.',
      'Anahtarı kopyala (sk-or- ile başlar).',
      'Buraya dönüp "API anahtarı" kutusuna yapıştır.',
      'Ücretsiz kullanmak istersen "Model adı" kutusuna adı ":free" ile biten bir model yaz (openrouter.ai/models sayfasında listelenir).',
    ],
    [
      'Press "Open site", sign in with Google or your email.',
      'Press "Create Key", give it a name and create it.',
      'Copy the key (starts with sk-or-).',
      'Come back and paste it into "API key".',
      'To use it for free, enter a model whose name ends in ":free" in "Model name" (listed on openrouter.ai/models).',
    ],
  ),
  'azure': KeyGuide(
    'https://ai.azure.com',
    false,
    'Ücretli, Azure aboneliği gerekir. Şirket hesabı olanlar için uygundur.',
    'Paid, needs an Azure subscription. Best for people with a company account.',
    [
      '"Siteyi aç"a bas ve Microsoft hesabınla giriş yap.',
      'Bir proje oluştur ve bir model yayınla (ör. gpt-4o-mini, "Deploy model").',
      'Yayınladığın modelin sayfasında "Endpoint" (uç nokta) adresini ve "Key" (anahtar) değerini bul.',
      'Adresi "Uç nokta", anahtarı "API anahtarı", yayınladığın adı da "Dağıtım adı" kutusuna yaz.',
      '"Bağlantıyı dene"ye bas.',
    ],
    [
      'Press "Open site" and sign in with your Microsoft account.',
      'Create a project and deploy a model (e.g. gpt-4o-mini, "Deploy model").',
      'On the deployed model\'s page, find the "Endpoint" address and the "Key".',
      'Enter the address in "Endpoint", the key in "API key" and the deployment name in "Deployment name".',
      'Press "Test connection".',
    ],
  ),
  'ollama': KeyGuide(
    'https://ollama.com/download',
    true,
    'Tamamen ücretsiz ve internetsiz, ama yalnızca bilgisayarda çalışır ve güçlü bir bilgisayar ister. Anahtar gerekmez.',
    'Completely free and offline, but runs only on a computer and needs a strong one. No key needed.',
    [
      '"Siteyi aç"a bas, Ollama\'yı indirip kur.',
      'Komut istemini (Terminal) aç ve şunu yaz: ollama pull llama3.2',
      'İndirme bitince Ollama arka planda açık kalsın.',
      'Buraya dönüp "Bağlantıyı dene"ye bas. Anahtar kutusunu boş bırak.',
    ],
    [
      'Press "Open site", download and install Ollama.',
      'Open a command prompt (Terminal) and type: ollama pull llama3.2',
      'When the download is done, leave Ollama running in the background.',
      'Come back and press "Test connection". Leave the key empty.',
    ],
  ),
};

/// The how-to card shown under the service picker.
class KeyGuideCard extends StatelessWidget {
  final String providerId;
  const KeyGuideCard({super.key, required this.providerId});

  @override
  Widget build(BuildContext context) {
    final g = keyGuides[providerId];
    if (g == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final steps = uiEnglish ? g.stepsEn : g.stepsTr;
    final badge = g.free ? L('Ücretsiz kullanılabilir', 'Free to use') : L('Ücretli', 'Paid');
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(L('Anahtar nasıl alınır', 'How to get a key'), style: theme.textTheme.titleSmall)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: g.free ? const Color(0xFF16A34A).withValues(alpha: 0.15) : cs.secondaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(badge,
                style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700, color: g.free ? const Color(0xFF15803D) : cs.onSecondaryContainer)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(uiEnglish ? g.costEn : g.costTr, style: theme.textTheme.bodySmall?.copyWith(height: 1.4)),
        const SizedBox(height: 10),
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                child: Text('${i + 1}', style: TextStyle(color: cs.onPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(steps[i], style: theme.textTheme.bodyMedium?.copyWith(height: 1.4))),
            ]),
          ),
        const SizedBox(height: 4),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilledButton.icon(
            onPressed: () => launchUrl(Uri.parse(g.url), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text(L('Siteyi aç', 'Open site')),
          ),
          SelectableText(g.url.replaceFirst('https://', ''), style: theme.textTheme.bodySmall?.copyWith(color: cs.primary)),
        ]),
      ]),
    );
  }
}
