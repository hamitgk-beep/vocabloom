import 'local_ai.dart';

/// Base address of the VocaBloom tuned models. While the tuned files are not
/// published yet, the original Qwen3 files (same size, same format) are used.
/// The app also reads `ai_url_<id>` from the settings, so a tuned model can be
/// switched to without a new release.
const _hf = 'https://huggingface.co';

/// The three packages shown in the "Yapay Zekâ" section.
///
/// All three are Qwen3 models (Alibaba Qwen team), Apache License 2.0, which
/// allows commercial use. Sizes are those of the GGUF files.
const aiPackages = <AiPackage>[
  AiPackage(
    id: 'lite',
    nameTr: 'Hafif',
    nameEn: 'Lite',
    tier: AiTier.free,
    sizeBytes: 495 * 1000 * 1000,
    model: 'Qwen3 0.6B (Q6_K)',
    licenseName: 'Apache 2.0',
    urls: ['$_hf/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q6_K.gguf'],
    minRamGb: 3,
    deviceTr: 'Giriş seviyesi ve üstü telefonlar (3 GB RAM ve üzeri)',
    deviceEn: 'Entry-level phones and above (3 GB RAM or more)',
    descTr: 'Kısa cümle düzeltmeleri, kelime soruları ve basit sohbet pratiği için tasarlanmış, düşük kaynak tüketen '
        'temel paket. Dilbilgisi açıklamalarında uygulamanın yerleşik sözlüğünden ve dilbilgisi analizinden destek alır.',
    descEn: 'A light basic package for short sentence corrections, word quizzes and simple conversation practice. '
        'For grammar explanations it is supported by the app\'s built-in dictionary and grammar analysis.',
    noteTr: 'Yanıtlar zaman zaman hatalı veya eksik olabilir. Türkçe açıklamalar sade tutulur; önemli konularda '
        'sözlük kayıtlarıyla doğrulamanız önerilir.',
    noteEn: 'Answers may occasionally be wrong or incomplete. Turkish explanations are kept simple; please check '
        'important points against the dictionary entries.',
    ratings: [
      AiRating('Türkçe açıklama', 'Turkish explanations', 2),
      AiRating('Dilbilgisi doğruluğu', 'Grammar accuracy', 2),
      AiRating('Sohbet akıcılığı', 'Conversation fluency', 2),
      AiRating('Hız', 'Speed', 5),
    ],
    contextSize: 4096,
    hybridThinking: true,
  ),
  AiPackage(
    id: 'plus',
    nameTr: 'Gelişmiş',
    nameEn: 'Advanced',
    tier: AiTier.plus,
    sizeBytes: 1420 * 1000 * 1000,
    model: 'Qwen3 1.7B (Q6_K)',
    licenseName: 'Apache 2.0',
    urls: ['$_hf/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q6_K.gguf'],
    minRamGb: 4,
    deviceTr: 'Orta seviye ve üstü telefonlar (4 GB RAM ve üzeri)',
    deviceEn: 'Mid-range phones and above (4 GB RAM or more)',
    descTr: 'Cümle ve dilbilgisi açıklamaları, yazdığınız metinlerin gerekçeli düzeltilmesi ve günlük konuşma pratiği '
        'için dengeli paket. Çeviri tutarlılığı iyi düzeydedir.',
    descEn: 'A balanced package for sentence and grammar explanations, corrections of your writing with reasons, '
        'and everyday conversation practice. Translation consistency is good.',
    noteTr: 'Çoğu yanıt güvenilirdir; ancak nadir kalıplarda ve deyimlerde hata yapabilir. Kritik konularda '
        'sözlükle karşılaştırmanız önerilir.',
    noteEn: 'Most answers are reliable, but it can make mistakes with rare patterns and idioms. Please compare '
        'critical points with the dictionary.',
    ratings: [
      AiRating('Türkçe açıklama', 'Turkish explanations', 3),
      AiRating('Dilbilgisi doğruluğu', 'Grammar accuracy', 4),
      AiRating('Sohbet akıcılığı', 'Conversation fluency', 3),
      AiRating('Hız', 'Speed', 4),
    ],
    contextSize: 4096,
    hybridThinking: true,
  ),
  AiPackage(
    id: 'pro',
    nameTr: 'Profesyonel',
    nameEn: 'Professional',
    tier: AiTier.pro,
    sizeBytes: 2890 * 1000 * 1000,
    model: 'Qwen3 4B Instruct 2507 (Q5_K_M)',
    licenseName: 'Apache 2.0',
    urls: ['$_hf/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/main/Qwen3-4B-Instruct-2507-Q5_K_M.gguf'],
    minRamGb: 6,
    deviceTr: 'Üst seviye telefonlar ve bilgisayarlar (6 GB RAM ve üzeri)',
    deviceEn: 'High-end phones and computers (6 GB RAM or more)',
    descTr: 'Ayrıntılı dilbilgisi anlatımı, doğal ve akıcı sohbet, üslup önerileri ve kitaplarınızdan zengin soru '
        'üretimi için en yüksek kaliteli paket. Türkçe ifade gücü ve çeviri tutarlılığı yüksektir.',
    descEn: 'The highest-quality package for detailed grammar teaching, natural conversation, style suggestions and '
        'rich quizzes from your books. Turkish fluency and translation consistency are high.',
    noteTr: 'Yüksek doğruluk oranına sahiptir; yine de tüm yapay zekâ sistemleri gibi istisnai durumlarda yanılabilir. '
        'Daha fazla pil ve bellek kullanır.',
    noteEn: 'It has a high accuracy rate, yet like every AI system it can be wrong in exceptional cases. It uses more '
        'battery and memory.',
    ratings: [
      AiRating('Türkçe açıklama', 'Turkish explanations', 4),
      AiRating('Dilbilgisi doğruluğu', 'Grammar accuracy', 5),
      AiRating('Sohbet akıcılığı', 'Conversation fluency', 5),
      AiRating('Hız', 'Speed', 2),
    ],
    contextSize: 6144,
  ),
];
