/// Interface language. Menus, buttons and explanations follow it; the word
/// meanings follow the separate Türkçe / English toggles.
bool uiEnglish = false;

/// Picks the Turkish or English text for the interface.
String L(String tr, String en) => uiEnglish ? en : tr;

/// Chapter names the importer made up ("Bölüm 3") follow the interface language.
String chapterName(String t) {
  final m = RegExp(r'^(?:Bölüm|Chapter) (\d+)$').firstMatch(t);
  return m == null ? t : L('Bölüm ${m[1]}', 'Chapter ${m[1]}');
}
