import 'dart:io';

import 'package:path/path.dart' as p;

/// The move from the VocaBloom name to Storilex on Windows, where the name
/// shows up in places the user keeps: the data folder in AppData (named
/// after the product) and the program file their shortcuts point to.
class RenameMigration {
  static const legacyFolder = 'VocaBloom';
  static const legacyExe = 'VocaBloom.exe';
  static const exe = 'Storilex.exe';

  /// Moves the books and words from %APPDATA%\<company>\VocaBloom to the
  /// new [dir] when [dir] is still empty. Returns the folder to use: [dir],
  /// or the old one when it could not be moved (it is then used as it is).
  static Directory dataFolder(Directory dir) {
    final legacy = Directory(p.join(dir.parent.path, legacyFolder));
    if (p.equals(legacy.path, dir.path) || !legacy.existsSync()) return dir;
    try {
      if (dir.existsSync()) {
        if (dir.listSync().isNotEmpty) return dir;
        dir.deleteSync();
      }
      legacy.renameSync(dir.path);
      return dir;
    } catch (_) {
      return legacy;
    }
  }

  /// When this is the VocaBloom.exe copy an update from before the rename
  /// left next to Storilex.exe, points the user's desktop, Start menu and
  /// taskbar shortcuts at Storilex.exe, so they still work once the next
  /// update removes the copy. Runs in the background; failures are ignored.
  static Future<void> moveShortcuts({String? running}) async {
    final exePath = running ?? Platform.resolvedExecutable;
    if (p.basename(exePath).toLowerCase() != legacyExe.toLowerCase()) return;
    final target = p.join(p.dirname(exePath), exe);
    if (!File(target).existsSync()) return;
    try {
      await Process.run('powershell', ['-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden', '-Command', shortcutScript], environment: {
        'VB_OLD': exePath,
        'VB_NEW': target,
      });
    } catch (_) {}
  }

  /// PowerShell that retargets every .lnk pointing at %VB_OLD% and renames
  /// "VocaBloom.lnk" to "Storilex.lnk" (taskbar pins keep their file name).
  static const shortcutScript = r'''
$ErrorActionPreference = 'SilentlyContinue'
$sh = New-Object -ComObject WScript.Shell
$dirs = @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('CommonDesktopDirectory'),
  [Environment]::GetFolderPath('Programs'), (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch'))
foreach ($d in $dirs) {
  if (-not $d -or -not (Test-Path $d)) { continue }
  foreach ($f in Get-ChildItem -Path $d -Filter *.lnk -Recurse) {
    $l = $sh.CreateShortcut($f.FullName)
    if ($l.TargetPath -ieq $env:VB_OLD) {
      $l.TargetPath = $env:VB_NEW
      $l.IconLocation = "$($env:VB_NEW),0"
      $l.Save()
      if ($f.Name -ieq 'VocaBloom.lnk' -and $f.FullName -notmatch 'User Pinned') {
        Rename-Item -Path $f.FullName -NewName 'Storilex.lnk'
      }
    }
  }
}
''';
}
