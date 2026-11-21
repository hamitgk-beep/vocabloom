import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Interface language. Menus, buttons and explanations follow it; the word
/// meanings follow the separate Türkçe / English toggles.
bool uiEnglish = false;

/// Picks the Turkish or English text for the interface.
String L(String tr, String en) => uiEnglish ? en : tr;

/// Capitals for headings: in Turkish i becomes İ (Dart's toUpperCase gives I).
String upperUi(String s) => uiEnglish ? s.toUpperCase() : s.replaceAll('i', 'İ').toUpperCase();

/// A percentage the way each language writes it: "%45" in Turkish, "45%" in English.
String percent(num n) => uiEnglish ? '$n%' : '%$n';

/// Chapter names the importer made up ("Bölüm 3") follow the interface language.
String chapterName(String t) {
  final m = RegExp(r'^(?:Bölüm|Chapter) (\d+)$').firstMatch(t);
  return m == null ? t : L('Bölüm ${m[1]}', 'Chapter ${m[1]}');
}

/// The locale of the built-in Flutter texts (back button, copy / paste menu,
/// date picker, "Close" on dialogs …), so they follow the app language too.
Locale get uiLocale => Locale(uiEnglish ? 'en' : 'tr');

const uiLocales = [Locale('tr'), Locale('en')];

const uiLocalizationsDelegates = <LocalizationsDelegate<dynamic>>[
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

/// An error for the user, in the interface language: no "Exception:" prefix,
/// and network failures explained instead of shown as raw system text.
String errorText(Object e) {
  if (e is TimeoutException) return L('İstek zaman aşımına uğradı. Biraz sonra tekrar deneyin.', 'The request timed out. Try again a bit later.');
  if (e is SocketException || e is HandshakeException) {
    return L('İnternet bağlantısı yok ya da sunucuya ulaşılamadı.', 'No internet connection, or the server could not be reached.');
  }
  if (e is HttpException) return L('Sunucu isteği kabul etmedi (${e.message}).', 'The server did not accept the request (${e.message}).');
  if (e is FileSystemException) return L('Dosya okunamadı ya da yazılamadı.', 'A file could not be read or written.');
  return e.toString().replaceFirst(RegExp(r'^(Exception|ImportException|FormatException|Bad state|AiException): ?'), '');
}
