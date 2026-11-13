import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;

import '../online/ai_service.dart';

/// Turns a page image (PNG) into text.
abstract class OcrEngine {
  String get name;
  Future<String> recognize(Uint8List png);

  /// The best engine available on this device. Offline engines come first;
  /// the AI service (if configured and reachable) is used as a fallback.
  static Future<OcrEngine?> best({AiService? ai}) async {
    final local = await _local();
    if (local != null) return ai == null || !ai.cfg.provider.vision ? local : _Chain(local, ai);
    if (ai != null && ai.cfg.provider.vision && await ai.reachable()) return _AiOcr(ai);
    return null;
  }

  static Future<OcrEngine?> _local() async {
    if (Platform.isAndroid || Platform.isIOS) return _MlKitOcr();
    if (Platform.isWindows) return _WindowsOcr();
    // Linux / macOS: Tesseract when it is installed.
    try {
      final r = await Process.run('tesseract', ['--version']);
      if (r.exitCode == 0) return _TesseractOcr();
    } catch (_) {}
    return null;
  }
}

Future<File> _tempPng(Uint8List png) async {
  final dir = await Directory.systemTemp.createTemp('kelime_ocr');
  final f = File(p.join(dir.path, 'page.png'));
  await f.writeAsBytes(png, flush: true);
  return f;
}

/// Google ML Kit, runs fully on the phone (Android / iOS).
class _MlKitOcr extends OcrEngine {
  @override
  String get name => 'ML Kit (cihaz üzerinde)';
  @override
  Future<String> recognize(Uint8List png) async {
    final f = await _tempPng(png);
    final rec = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final r = await rec.processImage(InputImage.fromFilePath(f.path));
      // One block is roughly one paragraph.
      return r.blocks.map((b) => b.lines.map((l) => l.text).join('\n')).join('\n\n');
    } finally {
      await rec.close();
      await f.parent.delete(recursive: true);
    }
  }
}

/// Windows 10/11 built-in OCR (Windows.Media.Ocr), called through PowerShell.
class _WindowsOcr extends OcrEngine {
  @override
  String get name => 'Windows OCR (çevrimdışı)';

  static const _script = r'''
param([string]$path)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
$null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.SoftwareBitmap, Windows.Graphics, ContentType = WindowsRuntime]
$null = [Windows.Storage.Streams.IRandomAccessStream, Windows.Storage.Streams, ContentType = WindowsRuntime]
$null = [Windows.Media.Ocr.OcrResult, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Globalization.Language, Windows.Globalization, ContentType = WindowsRuntime]
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
  $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($op, $type) {
  $t = $asTaskGeneric.MakeGenericMethod($type).Invoke($null, @($op))
  $t.Wait(-1) | Out-Null
  $t.Result
}
$file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($path)) ([Windows.Storage.StorageFile])
$stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
$decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
$bitmap = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
$engine = $null
foreach ($tag in @('en-US', 'en-GB', 'en')) {
  if ($engine -eq $null) {
    try { $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage([Windows.Globalization.Language]::new($tag)) } catch { }
  }
}
if ($engine -eq $null) { $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages() }
if ($engine -eq $null) { Write-Error 'NO_OCR_LANGUAGE'; exit 2 }
$result = Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$prevBottom = -1
foreach ($line in $result.Lines) {
  $top = [double]::MaxValue; $h = 0
  foreach ($w in $line.Words) {
    if ($w.BoundingRect.Y -lt $top) { $top = $w.BoundingRect.Y }
    if ($w.BoundingRect.Height -gt $h) { $h = $w.BoundingRect.Height }
  }
  if ($prevBottom -ge 0 -and ($top - $prevBottom) -gt ($h * 0.9)) { '' }
  $line.Text
  $prevBottom = $top + $h
}
''';

  @override
  Future<String> recognize(Uint8List png) async {
    final f = await _tempPng(png);
    final script = File(p.join(f.parent.path, 'ocr.ps1'));
    await script.writeAsString(_script);
    try {
      final r = await Process.run('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script.path, f.path],
          stdoutEncoding: const SystemEncoding(), runInShell: false);
      if (r.exitCode != 0) {
        final err = '${r.stderr}';
        if (err.contains('NO_OCR_LANGUAGE')) {
          throw Exception('Windows OCR için dil paketi yok. Ayarlar > Saat ve dil > Dil bölümünden İngilizce ekleyin.');
        }
        throw Exception('Windows OCR çalışmadı: $err');
      }
      return '${r.stdout}';
    } finally {
      await f.parent.delete(recursive: true);
    }
  }
}

/// Tesseract command line (Linux, macOS with Homebrew).
class _TesseractOcr extends OcrEngine {
  @override
  String get name => 'Tesseract (çevrimdışı)';
  @override
  Future<String> recognize(Uint8List png) async {
    final f = await _tempPng(png);
    try {
      final r = await Process.run('tesseract', [f.path, 'stdout', '-l', 'eng', '--psm', '3']);
      if (r.exitCode != 0) throw Exception('Tesseract hatası: ${r.stderr}');
      return '${r.stdout}';
    } finally {
      await f.parent.delete(recursive: true);
    }
  }
}

class _AiOcr extends OcrEngine {
  final AiService ai;
  _AiOcr(this.ai);
  @override
  String get name => 'Yapay zekâ (${ai.cfg.provider.name})';
  @override
  Future<String> recognize(Uint8List png) => ai.ocrPage(png);
}

/// Local engine first; if it fails, the AI service.
class _Chain extends OcrEngine {
  final OcrEngine first;
  final AiService ai;
  _Chain(this.first, this.ai);
  @override
  String get name => first.name;
  @override
  Future<String> recognize(Uint8List png) async {
    try {
      return await first.recognize(png);
    } catch (_) {
      if (await ai.reachable()) return ai.ocrPage(png);
      rethrow;
    }
  }
}
