import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

import '../online/native_fetch.dart';

/// SHA-256 of every voice pack zip in the "voice-models" release, written by
/// the voice-models and voice-checksums workflows. A pack's id carries its
/// version (kokoro-en-fp32-v1 …): a new model gets a new id, so a pack that
/// is installed is never downloaded again.
const voiceChecksumsUrl = 'https://github.com/hamitgk-beep/vocabloom/releases/download/voice-models/voice-models.json';

/// The SHA-256 the release lists for pack [id], or null when the list is
/// missing, unreadable or does not have it (then the download is used as
/// before, without the check).
Future<String?> expectedVoiceSha(String id, {String url = voiceChecksumsUrl}) async {
  try {
    final j = jsonDecode(await fetchText(url, timeout: const Duration(seconds: 15)));
    final packs = j is Map ? j['packs'] : null;
    final pack = packs is Map ? packs[id] : null;
    final sha = pack is Map ? pack['sha256'] : null;
    return sha is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(sha) ? sha : null;
  } catch (_) {
    return null;
  }
}

/// SHA-256 of a file, read off the UI thread.
Future<String> sha256OfFile(String path) => Isolate.run(() async => (await sha256.bind(File(path).openRead()).first).toString());
