/// A downloadable voice pack (one zip in the "voice-models" release).
class VoicePack {
  final String id;
  final int mb;
  final String lang; // 'en' or 'tr'

  /// Model family run by sherpa-onnx: 'kokoro' or 'piper'.
  final String engine;
  const VoicePack(this.id, this.mb, this.lang, this.engine);

  String get url => 'https://github.com/hamitgk-beep/vocabloom/releases/download/voice-models/$id.zip';
}

/// English, natural: Kokoro-82M v1.0 (hexgrad, Apache 2.0), full precision.
/// In tests it read 0 of 483 words wrong and sounds the most human.
const kokoroPack = VoicePack('kokoro-en-fp32-v1', 330, 'en', 'kokoro');

/// English, light: Piper trained on LibriTTS-R (CC BY 4.0). About 15x faster,
/// used on phones too slow for Kokoro, and while Kokoro is still downloading.
const lightPack = VoicePack('piper-en-libritts-v1', 70, 'en', 'piper');

/// The English voices are downloaded together, the small pack first.
const englishPack = kokoroPack;
const englishPacks = [lightPack, kokoroPack];

/// Turkish: Piper voices trained on CC0 recordings (NabuCasa voice-datasets).
const fahrettinPack = VoicePack('piper-tr-fahrettin', 55, 'tr', 'piper');
const fettahPack = VoicePack('piper-tr-fettah', 55, 'tr', 'piper');

const voicePacks = [lightPack, kokoroPack, fahrettinPack, fettahPack];

/// A voice. [sid] is the speaker id inside its model; [accent] is 'us', 'gb'
/// or 'tr'.
class Voice {
  final String id;
  final int sid;
  final String name;
  final bool female;
  final VoicePack pack;
  final String accent;
  const Voice(this.id, this.sid, this.name, {required this.female, required this.pack, this.accent = 'us'});

  String get lang => pack.lang;
  String get engine => pack.engine;

  /// Models kept loaded side by side: one per kind of use.
  String get family => pack == kokoroPack ? 'en-natural' : pack.lang == 'en' ? 'en-light' : 'tr';
}

/// Natural English voices (Kokoro speaker ids from the model's voice table),
/// the best-rated ones of each kind first.
const voices = <Voice>[
  Voice('k_af_heart', 3, 'Heart', female: true, pack: kokoroPack),
  Voice('k_af_bella', 2, 'Bella', female: true, pack: kokoroPack),
  Voice('k_af_nicole', 6, 'Nicole', female: true, pack: kokoroPack),
  Voice('k_af_sarah', 9, 'Sarah', female: true, pack: kokoroPack),
  Voice('k_am_michael', 16, 'Michael', female: false, pack: kokoroPack),
  Voice('k_am_fenrir', 14, 'Fenrir', female: false, pack: kokoroPack),
  Voice('k_am_puck', 18, 'Puck', female: false, pack: kokoroPack),
  Voice('k_bf_emma', 21, 'Emma', female: true, pack: kokoroPack, accent: 'gb'),
  Voice('k_bf_isabella', 22, 'Isabella', female: true, pack: kokoroPack, accent: 'gb'),
  Voice('k_bm_george', 26, 'George', female: false, pack: kokoroPack, accent: 'gb'),
  Voice('k_bm_fable', 25, 'Fable', female: false, pack: kokoroPack, accent: 'gb'),
  Voice('k_bm_lewis', 27, 'Lewis', female: false, pack: kokoroPack, accent: 'gb'),
];

/// Light English voices (LibriTTS-R speaker ids, picked by pitch and by how
/// often Whisper heard single words right).
const lightVoices = <Voice>[
  Voice('l_f1', 513, 'Anna', female: true, pack: lightPack),
  Voice('l_f2', 702, 'Kate', female: true, pack: lightPack),
  Voice('l_m1', 720, 'Tom', female: false, pack: lightPack),
  Voice('l_m2', 522, 'Mark', female: false, pack: lightPack),
];

/// Turkish voices (male; no free female Turkish voice allows commercial use yet).
const trVoices = <Voice>[
  Voice('tr_fahrettin', 0, 'Fahrettin', female: false, pack: fahrettinPack, accent: 'tr'),
  Voice('tr_fettah', 0, 'Fettah', female: false, pack: fettahPack, accent: 'tr'),
];

final voiceById = {for (final v in [...voices, ...lightVoices, ...trVoices]) v.id: v};
