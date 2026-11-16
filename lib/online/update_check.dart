import 'dart:convert';
import 'dart:io';

import '../l10n.dart';
import 'native_fetch.dart';

/// Build number baked in by CI (--dart-define=BUILD_NUMBER=...); 0 for local builds.
const appBuild = int.fromEnvironment('BUILD_NUMBER');

/// User-facing version baked in by CI (1.1, 1.2 ... 2.0); empty for local builds.
const appVersion = String.fromEnvironment('APP_VERSION');

const _release = 'https://api.github.com/repos/hamitgk-beep/vocabloom/releases/tags/latest';
const _download = 'https://github.com/hamitgk-beep/vocabloom/releases/download/latest/';

class UpdateInfo {
  final int build;
  final String version;
  final String url;

  /// Size of the download in bytes, 0 when unknown.
  final int size;

  /// What changed since the installed build, newest first.
  final List<ReleaseNote> notes;
  const UpdateInfo(this.build, this.url, {this.version = '', this.size = 0, this.notes = const []});
}

/// One "what's new" line of a release (release_notes.json, written into the
/// release body by tools/release/release_notes.py).
class ReleaseNote {
  /// dictionary, grammar, reader, words, review, ai, voice or app.
  final String area;
  final String tr, en;

  /// The first build that has this change.
  final int build;
  const ReleaseNote(this.area, this.tr, this.en, this.build);

  String get text => uiEnglish && en.isNotEmpty ? en : tr;

  /// The area's name in the interface language ("Sözlük", "Grammar" …).
  String get areaName => switch (area) {
    'dictionary' => L('Sözlük', 'Dictionary'),
    'grammar' => L('Gramer', 'Grammar'),
    'reader' => L('Okuyucu', 'Reader'),
    'words' => L('Kelimelerim', 'My words'),
    'review' => L('Tekrar', 'Review'),
    'ai' => L('Yapay zekâ', 'AI'),
    'voice' => L('Sesli okuma', 'Reading aloud'),
    _ => L('Uygulama', 'App'),
  };
}

/// The release notes in a release [body] that are newer than [sinceBuild],
/// newest first. Empty when the body has none (older releases).
List<ReleaseNote> parseReleaseNotes(String body, {int sinceBuild = 0}) {
  final m = RegExp(r'<!--\s*vocabloom-notes\s*(\{.*?\})\s*-->', dotAll: true).firstMatch(body);
  if (m == null) return const [];
  try {
    final out = <ReleaseNote>[
      for (final e in (jsonDecode(m.group(1)!) as Map)['entries'] as List)
        if (e is Map && e['tr'] is String) ReleaseNote('${e['area'] ?? 'app'}', e['tr'] as String, '${e['en'] ?? ''}', (e['build'] as num?)?.toInt() ?? 0),
    ];
    return out.where((n) => n.build > sinceBuild).toList()..sort((a, b) => b.build.compareTo(a.build));
  } catch (_) {
    return const [];
  }
}

String? _assetForPlatform() {
  if (Platform.isAndroid) return 'VocaBloom-Android.apk';
  if (Platform.isWindows) return 'VocaBloom-Windows.zip';
  if (Platform.isMacOS) return 'VocaBloom-macOS.zip';
  if (Platform.isIOS) return 'VocaBloom-iOS-unsigned.ipa';
  return null;
}

/// Returns the newer release for this platform, or null (also when offline).
Future<UpdateInfo?> checkForUpdate() async {
  try {
    return await checkForUpdateOrThrow();
  } catch (_) {
    return null;
  }
}

/// Like [checkForUpdate] but throws when the release could not be read, so
/// a manual check in Settings can say why.
Future<UpdateInfo?> checkForUpdateOrThrow() async {
  if (appBuild == 0) return null;
  final asset = _assetForPlatform();
  if (asset == null) return null;
  final text = await fetchText(_release, headers: {'Accept': 'application/vnd.github+json'});
  final json = jsonDecode(text) as Map;
  final body = '${json['body'] ?? ''}';
  final m = RegExp(r'build[:\s]+(\d+)', caseSensitive: false).firstMatch(body);
  final latest = int.tryParse(m?.group(1) ?? '') ?? 0;
  if (latest <= appBuild) return null;
  final v = RegExp(r'S\u00fcr\u00fcm\s+([\d.]+)').firstMatch(body)?.group(1) ?? '';
  var size = 0;
  for (final a in (json['assets'] as List? ?? const [])) {
    if (a is Map && a['name'] == asset) size = (a['size'] as num?)?.toInt() ?? 0;
  }
  return UpdateInfo(
    latest,
    '$_download$asset',
    version: v,
    size: size,
    notes: parseReleaseNotes(body, sinceBuild: appBuild),
  );
}
