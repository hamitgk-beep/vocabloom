import 'dart:convert';
import 'dart:io';

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
  const UpdateInfo(this.build, this.url, {this.version = '', this.size = 0});
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
  return UpdateInfo(latest, '$_download$asset', version: v, size: size);
}
