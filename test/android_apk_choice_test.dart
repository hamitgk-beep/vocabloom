import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/online/update_check.dart';

/// The release has one APK per processor type besides the universal one;
/// the app downloads the one for its own processor.
void main() {
  test('the APK matches the processor the Dart VM reports', () {
    expect(androidAbiAsset('3.14.0 (stable) (Mon Nov 3 2026) on "android_arm64"'), 'Storilex-Android-arm64-v8a.apk');
    expect(androidAbiAsset('3.14.0 (stable) (Mon Nov 3 2026) on "android_arm"'), 'Storilex-Android-armeabi-v7a.apk');
    // No own APK (emulators, Chromebooks): the universal APK is used.
    expect(androidAbiAsset('3.14.0 (stable) (Mon Nov 3 2026) on "android_x64"'), isNull);
    expect(androidAbiAsset('3.14.0 (stable) (Mon Nov 3 2026) on "windows_x64"'), isNull);
  });

  test('the update size reads as megabytes', () {
    expect(const UpdateInfo(1, '', size: 145000000).downloadSizeText, '138 MB');
    expect(const UpdateInfo(1, '', size: 5 * 1024 * 1024).downloadSizeText, '5.0 MB');
    expect(const UpdateInfo(1, '').downloadSizeText, '');
  });
}
