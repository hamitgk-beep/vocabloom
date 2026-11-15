import 'local_ai.dart';

/// Base address of the VocaBloom tuned models. While the tuned files are not
/// published yet, the original Qwen3 files (same size, same format) are used.
/// The app also reads `ai_url_<id>` from the settings, so a tuned model can be
/// switched to without a new release.
const _hf = 'https://huggingface.co';

/// The one package of the "Yapay Zekâ" section: the best model that runs well
/// on a phone. Chosen over Gemma 3 4B in side-by-side tests on the tutor tasks
/// (more accurate grammar and corrections), and its licence (Apache 2.0, Qwen
/// team) allows commercial use without extra terms. The id stays 'pro' so
/// existing downloads and settings stay valid.
const aiPackages = <AiPackage>[
  AiPackage(
    id: 'pro',
    nameTr: 'VocaBloom Yapay Zekâ Öğretmeni',
    nameEn: 'VocaBloom AI Tutor',
    tier: AiTier.free,
    sizeBytes: 2890 * 1000 * 1000,
    model: 'Qwen3 4B Instruct 2507 (Q5_K_M)',
    licenseName: 'Apache 2.0',
    urls: ['$_hf/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/main/Qwen3-4B-Instruct-2507-Q5_K_M.gguf'],
    minRamGb: 6,
    deviceTr: 'Üst seviye telefonlar ve bilgisayarlar (6 GB RAM ve üzeri)',
    deviceEn: 'High-end phones and computers (6 GB RAM or more)',
    descTr: 'İnternet bağlantısı olmadan cihazınızda çalışan İngilizce öğretmeni. Kitaptaki cümleleri Türkçe açıklar, '
        'dilbilgisi yapılarını anlatır, yazdığınız İngilizceyi gerekçeleriyle düzeltir ve günlük konuşma pratiği '
        'yaptırır. Açıklamalarını uygulamanın sözlüğüne ve dilbilgisi analizine dayandırır; çeviri tutarlılığı yüksektir.',
    descEn: 'An English tutor that runs on your device without an internet connection. It explains book sentences in '
        'Turkish, teaches grammar structures, corrects your English with reasons and gives you everyday conversation '
        'practice. It bases its explanations on the app\'s dictionary and grammar analysis; translation consistency is high.',
    noteTr: 'Yüksek doğruluk oranına sahiptir; yine de tüm yapay zekâ sistemleri gibi istisnai durumlarda yanılabilir. '
        'Daha fazla pil ve bellek kullanır.',
    noteEn: 'It has a high accuracy rate, yet like every AI system it can be wrong in exceptional cases. It uses more '
        'battery and memory.',
    ratings: [
      AiRating('Türkçe açıklama', 'Turkish explanations', 4),
      AiRating('Dilbilgisi doğruluğu', 'Grammar accuracy', 5),
      AiRating('Sohbet akıcılığı', 'Conversation fluency', 5),
      AiRating('Hız', 'Speed', 3),
    ],
    contextSize: 6144,
  ),
];
