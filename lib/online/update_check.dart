import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Build number baked in by CI (--dart-define=BUILD_NUMBER=...); 0 for local builds.
const appBuild = int.fromEnvironment('BUILD_NUMBER');

const _release = 'https://api.github.com/repos/hamitgk-beep/vocabloom/releases/tags/latest';
const _download = 'https://github.com/hamitgk-beep/vocabloom/releases/download/latest/';

class UpdateInfo {
  final int build;
  final String url;
  const UpdateInfo(this.build, this.url);
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
  if (appBuild == 0) return null;
  final asset = _assetForPlatform();
  if (asset == null) return null;
  try {
    final r = await http.get(Uri.parse(_release), headers: {'Accept': 'application/vnd.github+json'}).timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) return null;
    final body = '${(jsonDecode(r.body) as Map)['body'] ?? ''}';
    final m = RegExp(r'build[:\s]+(\d+)', caseSensitive: false).firstMatch(body);
    final latest = int.tryParse(m?.group(1) ?? '') ?? 0;
    return latest > appBuild ? UpdateInfo(latest, '$_download$asset') : null;
  } catch (_) {
    return null;
  }
}
