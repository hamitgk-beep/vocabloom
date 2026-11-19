import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Downloads that keep working on Windows PCs where Dart's own HTTP client
/// cannot reach GitHub: Dart ignores the Windows proxy setting and some
/// antivirus or company networks replace GitHub's certificate with their own.
/// On Windows a failed request is retried with curl.exe (Windows' own TLS and
/// certificate store) and then with PowerShell (also the system proxy).
/// Other platforms use package:http only.
class FetchException implements Exception {
  final List<String> attempts;
  FetchException(this.attempts);
  @override
  String toString() => attempts.join(' | ');
}

const _agent = 'Storilex';

/// Tests set this to skip package:http and use only the Windows fallbacks.
bool debugSkipDartHttp = false;

/// Tests set this to skip curl.exe and go straight to PowerShell.
bool debugSkipCurl = false;

/// GETs [url] as text.
Future<String> fetchText(String url, {Map<String, String> headers = const {}, Duration timeout = const Duration(seconds: 15)}) async {
  final errors = <String>[];
  if (!debugSkipDartHttp) {
    try {
      final r = await http.get(Uri.parse(url), headers: {'User-Agent': _agent, ...headers}).timeout(timeout);
      if (r.statusCode == 200) return r.body;
      errors.add('http: HTTP ${r.statusCode}');
    } catch (e) {
      errors.add('http: $e');
    }
  }
  if (!Platform.isWindows) throw FetchException(errors);
  final tmp = await Directory.systemTemp.createTemp('vocabloom_fetch_');
  try {
    final f = File(p.join(tmp.path, 'body'));
    await _windowsDownload(url, f, headers, timeout, errors);
    return await f.readAsString();
  } finally {
    tmp.delete(recursive: true).ignore();
  }
}

/// Downloads [url] into [out]. [onProgress] gets 0..1, or null when the size
/// is unknown; [expectedSize] is used when the server sends no length.
Future<void> fetchFile(String url, File out, {void Function(double? p)? onProgress, int? expectedSize}) async {
  final errors = <String>[];
  if (!debugSkipDartHttp) {
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(url))..headers['User-Agent'] = _agent).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final total = res.contentLength ?? expectedSize;
      var got = 0;
      final sink = out.openWrite();
      try {
        await for (final chunk in res.stream.timeout(const Duration(seconds: 60))) {
          sink.add(chunk);
          got += chunk.length;
          onProgress?.call(total == null || total == 0 ? null : got / total);
        }
      } finally {
        await sink.close();
      }
      if (total != null && total > 0 && got < total) throw HttpException('incomplete download ($got/$total)');
      return;
    } catch (e) {
      errors.add('http: $e');
    } finally {
      client.close();
    }
  }
  if (!Platform.isWindows) throw FetchException(errors);
  onProgress?.call(null);
  Timer? poll;
  if (onProgress != null && expectedSize != null && expectedSize > 0) {
    poll = Timer.periodic(const Duration(milliseconds: 400), (_) {
      try {
        if (out.existsSync()) onProgress((out.lengthSync() / expectedSize).clamp(0.0, 0.99));
      } catch (_) {}
    });
  }
  try {
    await _windowsDownload(url, out, const {}, const Duration(minutes: 30), errors);
  } finally {
    poll?.cancel();
  }
  onProgress?.call(1);
}

Future<void> _windowsDownload(String url, File out, Map<String, String> headers, Duration timeout, List<String> errors) async {
  if (out.existsSync()) out.deleteSync();
  // 1) curl.exe ships with Windows 10 1803+ and uses Schannel, so it trusts
  // whatever certificates Windows trusts. Revocation checks are skipped
  // because they fail behind many proxies and antivirus filters.
  if (!debugSkipCurl) {
    try {
      final r = await Process.run('curl.exe', [
        '-fsSL',
        '--ssl-no-revoke',
        '--retry',
        '2',
        '--connect-timeout',
        '20',
        '--max-time',
        '${timeout.inSeconds}',
        '-A',
        _agent,
        for (final h in headers.entries) ...['-H', '${h.key}: ${h.value}'],
        '-o',
        p.basename(out.path),
        url,
        // Run inside the target folder: curl may get a folder like
        // "Hamit Gök" in the ANSI code page and write somewhere else.
      ], workingDirectory: out.parent.path).timeout(timeout + const Duration(seconds: 30));
      if (r.exitCode == 0 && out.existsSync()) return;
      errors.add('curl: exit ${r.exitCode} ${'${r.stderr}'.trim()}');
    } catch (e) {
      errors.add('curl: $e');
    }
  }
  // 2) Windows PowerShell uses the system proxy (Internet Options).
  String q(String s) => "'${s.replaceAll("'", "''")}'";
  final hdr = headers.entries.map((h) => '${q(h.key)}=${q(h.value)}').join(';');
  final script = [
    r"$ErrorActionPreference='Stop'",
    r"$ProgressPreference='SilentlyContinue'",
    '[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12',
    r'[Net.WebRequest]::DefaultWebProxy.Credentials=[Net.CredentialCache]::DefaultNetworkCredentials',
    'Invoke-WebRequest -UseBasicParsing -UserAgent ${q(_agent)} -Headers @{$hdr} -Uri ${q(url)} -OutFile \$env:VB_OUT -TimeoutSec ${timeout.inSeconds}',
  ].join('; ');
  try {
    final r = await Process.run(
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', script],
      environment: {'VB_OUT': out.path},
    ).timeout(timeout + const Duration(seconds: 30));
    if (r.exitCode == 0 && out.existsSync()) return;
    errors.add('powershell: exit ${r.exitCode} ${'${r.stderr}'.trim()}');
  } catch (e) {
    errors.add('powershell: $e');
  }
  throw FetchException(errors);
}
