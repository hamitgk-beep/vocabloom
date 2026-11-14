/// A downloadable voice pack (one zip in the "voice-models" release).
class VoicePack {
  final String id;
  final int mb;
  final String lang; // 'en' or 'tr'
  const VoicePack(this.id, this.mb, this.lang);

  String get url => 'https://github.com/hamitgk-beep/vocabloom/releases/download/voice-models/$id.zip';
}

/// English: Kokoro-82M v1.0 (Apache 2.0), one model with many voices.
const kokoroPack = VoicePack('kokoro-en-v1', 120, 'en');

/// Turkish: Piper voices trained on CC0 recordings (NabuCasa voice-datasets).
const fahrettinPack = VoicePack('piper-tr-fahrettin', 55, 'tr');
const fettahPack = VoicePack('piper-tr-fettah', 55, 'tr');

const voicePacks = [kokoroPack, fahrettinPack, fettahPack];

/// A voice. [sid] is the speaker id inside its model.
class Voice {
  final String id;
  final int sid;
  final String name;
  final bool female;
  final bool british;
  final VoicePack pack;
  const Voice(this.id, this.sid, this.name, {required this.female, this.british = false, this.pack = kokoroPack});

  String get lang => pack.lang;
  bool get kokoro => pack == kokoroPack;

  /// Engine settings sent to the synthesis isolate (one loaded model per key).
  String get engineKey => kokoro ? '${pack.id}|${british ? 'gb' : 'us'}' : pack.id;
}

/// English voices: the clearest of the model, best first in each group.
const voices = <Voice>[
  Voice('af_heart', 3, 'Heart', female: true),
  Voice('af_bella', 2, 'Bella', female: true),
  Voice('af_nicole', 6, 'Nicole', female: true),
  Voice('af_sarah', 9, 'Sarah', female: true),
  Voice('am_michael', 16, 'Michael', female: false),
  Voice('am_fenrir', 14, 'Fenrir', female: false),
  Voice('am_puck', 18, 'Puck', female: false),
  Voice('bf_emma', 21, 'Emma', female: true, british: true),
  Voice('bf_isabella', 22, 'Isabella', female: true, british: true),
  Voice('bm_george', 26, 'George', female: false, british: true),
  Voice('bm_fable', 25, 'Fable', female: false, british: true),
];

/// Turkish voices (male; no free female Turkish voice allows commercial use yet).
const trVoices = <Voice>[
  Voice('tr_fahrettin', 0, 'Fahrettin', female: false, pack: fahrettinPack),
  Voice('tr_fettah', 0, 'Fettah', female: false, pack: fettahPack),
];

final voiceById = {for (final v in [...voices, ...trVoices]) v.id: v};
