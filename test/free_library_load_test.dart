// The free library never spins forever: one broken or missing file leaves
// the other language's texts in place, and when nothing can be read the
// page says so and offers to try again.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/ai/key_ai.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/free_library.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/ui/free_library_page.dart';
import 'package:sqlite3/sqlite3.dart';

/// The app's library files from disk, minus [missing], with [broken] garbled.
class FakeBundle extends CachingAssetBundle {
  final Set<String> missing, broken;
  FakeBundle({this.missing = const {}, this.broken = const {}});

  @override
  Future<ByteData> load(String key) async {
    if (missing.contains(key)) throw FlutterError('Unable to load asset: "$key".');
    if (broken.contains(key)) return ByteData.sublistView(Uint8List.fromList('{not json'.codeUnits));
    return ByteData.sublistView(File(key).readAsBytesSync());
  }
}

const en = ('assets/library/catalog.json', 'assets/library/stories.json.gz');
const tr = ('assets/library/catalog_tr.json', 'assets/library/stories_tr.json.gz');

Future<FreeLibrary> loadWith(FakeBundle b) {
  FreeLibrary.debugReset();
  FreeLibrary.debugBundle = b;
  return FreeLibrary.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    FreeLibrary.debugBundle = null;
    FreeLibrary.debugReset();
  });

  test('both languages load', () async {
    final lib = await loadWith(FakeBundle());
    expect(lib.problems, isEmpty);
    expect(lib.items.where((it) => it.lang == 'en'), isNotEmpty);
    expect(lib.items.where((it) => it.lang == 'tr'), isNotEmpty);
  });

  test('a missing or broken Turkish file keeps the English texts, and the other way round', () async {
    var lib = await loadWith(FakeBundle(missing: {tr.$1}));
    expect(lib.items.where((it) => it.lang == 'en'), isNotEmpty);
    expect(lib.items.where((it) => it.lang == 'tr'), isEmpty);
    expect(lib.problems.single, contains('catalog_tr.json'));

    lib = await loadWith(FakeBundle(broken: {en.$1}));
    expect(lib.items.where((it) => it.lang == 'tr'), isNotEmpty);
    expect(lib.items.where((it) => it.lang == 'en'), isEmpty);

    // Without the story texts only the books (downloaded on demand) stay.
    lib = await loadWith(FakeBundle(broken: {en.$2}));
    expect(lib.items.where((it) => it.lang == 'en' && !it.isBook), isEmpty);
    expect(lib.items.where((it) => it.lang == 'en' && it.isBook), isNotEmpty);
    expect(lib.items.where((it) => it.lang == 'tr'), isNotEmpty);
  });

  testWidgets('when nothing can be read the page says so and tries again', (tester) async {
    final d = DictDb();
    d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    final u = UserDb.open(Directory.systemTemp.createTempSync('vb_libload'));
    final app = AppState(d, u)..localAi = KeyAi(u);
    FreeLibrary.debugReset();
    FreeLibrary.debugBundle = FakeBundle(missing: {en.$1, tr.$1});

    await tester.pumpWidget(MaterialApp(home: FreeLibraryPage(app: app)));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(find.byKey(const Key('free-library-failed')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // The files are back: "Try again" opens the library.
    FreeLibrary.debugBundle = FakeBundle();
    await tester.tap(find.byType(FilledButton));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 500)));
    await tester.pump();
    expect(find.byKey(const Key('free-library-failed')), findsNothing);
    expect(find.byType(ListView), findsOneWidget);
  });
}
