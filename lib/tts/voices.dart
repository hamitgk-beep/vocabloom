/// A downloadable voice pack (one zip in the "voice-models" release).
class VoicePack {
  final String id;
  final int mb;
  final String lang; // 'en' or 'tr'
  const VoicePack(this.id, this.mb, this.lang);

  String get url => 'https://github.com/hamitgk-beep/vocabloom/releases/download/voice-models/$id.zip';
}

/// English: Supertonic 2 (Supertone, OpenRAIL-M model / MIT code). Fast on
/// phones and natural; one model with 10 voices.
const englishPack = VoicePack('supertonic-en-v2', 80, 'en');

/// Turkish: Piper voices trained on CC0 recordings (NabuCasa voice-datasets).
const fahrettinPack = VoicePack('piper-tr-fahrettin', 55, 'tr');
const fettahPack = VoicePack('piper-tr-fettah', 55, 'tr');

const voicePacks = [englishPack, fahrettinPack, fettahPack];

/// A voice. [sid] is the speaker id inside its model.
class Voice {
  final String id;
  final int sid;
  final String name;
  final bool female;
  final VoicePack pack;
  const Voice(this.id, this.sid, this.name, {required this.female, this.pack = englishPack});

  String get lang => pack.lang;

  /// Model family: 'supertonic' or 'piper'.
  String get engine => pack == englishPack ? 'supertonic' : 'piper';
}

/// English voices (American English). Speaker ids 0-4 are the model's
/// female styles F1-F5, 5-9 the male styles M1-M5.
const voices = <Voice>[
  Voice('en_f1', 0, 'Ava', female: true),
  Voice('en_f2', 1, 'Lily', female: true),
  Voice('en_f3', 2, 'Grace', female: true),
  Voice('en_f4', 3, 'Mia', female: true),
  Voice('en_f5', 4, 'Nora', female: true),
  Voice('en_m1', 5, 'Leo', female: false),
  Voice('en_m2', 6, 'Sam', female: false),
  Voice('en_m3', 7, 'Jack', female: false),
  Voice('en_m4', 8, 'Ben', female: false),
  Voice('en_m5', 9, 'Max', female: false),
];

/// Turkish voices (male; no free female Turkish voice allows commercial use yet).
const trVoices = <Voice>[
  Voice('tr_fahrettin', 0, 'Fahrettin', female: false, pack: fahrettinPack),
  Voice('tr_fettah', 0, 'Fettah', female: false, pack: fettahPack),
];

final voiceById = {for (final v in [...voices, ...trVoices]) v.id: v};
