// Dictionary sources as shown to the user (Settings > Privacy and licenses),
// with each source's real licence status (docs/lexicon_provenance/LICENSE_AUDIT.md,
// docs/lexicon_remediation/LICENSE_TEXT_CORRECTIONS.md). A licence is named only
// where it was verified; unverified sources say so.
import 'package:flutter/foundation.dart';

import '../l10n.dart';

/// The lines of the "Dictionary sources" section, in the interface language.
List<String> dictionarySourceLines() => [
      L('Kelime anlamları: Wiktionary çevirileri (CC BY-SA 4.0, yazarlar: Wiktionary katkıcıları), Murat Uysal\'ın Kindle İngilizce–Türkçe derlemesindeki Wiktionary bölümünden. Derlemenin tamamı GPL-2.0+ ile dağıtılıyor; bu bölümün lisans durumu inceleniyor.',
          'Word meanings: Wiktionary translations (CC BY-SA 4.0, authors: Wiktionary contributors), from the Wiktionary part of Murat Uysal\'s Kindle English–Turkish compilation. The compilation as a whole is distributed under GPL-2.0+; the licence status of this part is under review.'),
      L('Ek kelime anlamları: damdafayton/eng-tur-dictionary. Bu kaynağın lisansı ve verinin kökeni doğrulanamadı; bu anlamlar için bir lisans beyan edilmez ve kaynak sahibine soruluyor.',
          'Additional word meanings: damdafayton/eng-tur-dictionary. The licence of this source and the origin of its data could not be verified; no licence is stated for these meanings and the owner is being asked.'),
      L('İngilizce tanımlar, eş anlamlılar ve kök biçimler: Princeton WordNet 3.0 (WordNet Lisansı). Tam lisans bildirimi: aşağıdaki "Kullanılan kütüphanelerin lisansları" > Princeton WordNet 3.0.',
          'English definitions, synonyms and base forms: Princeton WordNet 3.0 (WordNet License). Full licence notice: "Licences of the libraries used" below > Princeton WordNet 3.0.'),
      L('Anlamların Türkçesi: KeNet Türkçe WordNet, Starlang Yazılım / Özyeğin Üniversitesi (CC BY-SA 4.0); Collaborative Interlingual Index ile eşlendi (CC BY 4.0, Francis Bond).',
          'Turkish for senses: KeNet Turkish WordNet, Starlang Software / Özyeğin University (CC BY-SA 4.0); linked through the Collaborative Interlingual Index (CC BY 4.0, Francis Bond).'),
      L('FreeDict English–Turkish 0.3 (GPL-2.0+): yalnızca birkaç ifade anlamında kalmış olabilir; bu içerik CC BY-SA altında değildir ve ayıklanması planlanıyor.',
          'FreeDict English–Turkish 0.3 (GPL-2.0+): may remain in a few expression meanings only; this content is not under CC BY-SA and is to be removed.'),
      L('Kalıplar ve deyimler: İngilizce ve Türkçe Vikisözlük, kaikki.org / wiktextract üzerinden (CC BY-SA 4.0).',
          'Expressions and idioms: English and Turkish Wiktionary via kaikki.org / wiktextract (CC BY-SA 4.0).'),
      L('Çevirili örnek cümleler: Tatoeba katkıcıları (tatoeba.org). Varsayılan lisans CC BY 2.0 FR; bazı cümlelerin lisansı farklı olabilir. Cümle yazarları henüz gösterilmiyor.',
          'Example sentences with translations: Tatoeba contributors (tatoeba.org). Default licence CC BY 2.0 FR; some sentences may carry another licence. Sentence authors are not shown yet.'),
      L('Yapay zekâ taslakları: bazı anlamlar, açıklamalar ve örnekler yapay zekâ ile hazırlandı ve henüz bir insan tarafından kontrol edilmedi. Uygulamada "doğrulanmamış" etiketiyle gösterilir.',
          'AI drafts: some meanings, explanations and examples were drafted with AI and have not been checked by a person yet. The app marks them as "unverified".'),
      L('Storilex katkıları: kullanıcılarımızın elle hazırlayıp kontrol ettiği anlamlar, örnek cümleler, cümledeki anlamlar ve deyimler (iki yönde). Katkı verenler: Hamit',
          'Storilex contributors: meanings, example sentences, meanings in context and idioms prepared and checked by hand by our users (both directions). Contributors: Hamit'),
      L('Türkçe → İngilizce sözlük: İngilizce Vikisözlük\'teki Türkçe kelimeler, kaikki.org üzerinden (CC BY-SA 4.0); eksik kelimeler KeNet\'ten ve İngilizce → Türkçe anlamların tersinden; kelime sıklığı sırası: FrequencyWords (Hermit Dave), OpenSubtitles 2018 verisinden (lisansı doğrulanamadı); örnek cümleler: Tatoeba katkıcıları (CC BY 2.0 FR).',
          'Turkish → English dictionary: Turkish entries of the English Wiktionary via kaikki.org (CC BY-SA 4.0); missing words from KeNet and from the English → Turkish meanings, reversed; word frequency rank: FrequencyWords (Hermit Dave), from OpenSubtitles 2018 data (licence not verified); example sentences: Tatoeba contributors (CC BY 2.0 FR).'),
      L('Kategori listeleri bu uygulama için yapay zekâ yardımıyla hazırlandı (CC BY-SA 4.0).',
          'Category lists written for this app with the help of AI (CC BY-SA 4.0).'),
      L('Değişiklikler: kaynak metinler kısaltıldı, birleştirildi, sıralandı ve temizlendi.',
          'Changes: source texts were shortened, merged, reordered and cleaned.'),
      L('Sözlük veritabanı bu kaynaklardan uyarlanmıştır. Açık lisanslı bölümler kendi lisanslarıyla paylaşılır (çoğunlukla CC BY-SA 4.0); lisansı doğrulanamadı denen bölümler için bir lisans beyan edilmez. Lisans metinleri: creativecommons.org/licenses/by-sa/4.0 · gnu.org/licenses/gpl-3.0',
          'The dictionary database is adapted from these sources. Openly licensed parts are shared under their own licences (mostly CC BY-SA 4.0); no licence is stated for the parts marked as not verified. Licence texts: creativecommons.org/licenses/by-sa/4.0 · gnu.org/licenses/gpl-3.0'),
    ];

/// The source line above a Turkish → English meaning that does not come from
/// the Wiktionary data. "fd" was written by tools/tr_en/add_reverse.py for
/// meanings reversed from the English → Turkish word meanings (Wiktionary and
/// damdafayton since 2026-11-17), not FreeDict; "rv" is the corrected tag.
String? trSenseSourceLabel(String? source) => switch (source) {
      null => null,
      'wn' => L('Kaynak: KeNet / WordNet', 'Source: KeNet / WordNet'),
      'st' => L('Kaynak: Storilex katkıları', 'Source: Storilex contributors'),
      'fd' || 'rv' => L('Kaynak: İngilizce → Türkçe anlamların tersi', 'Source: reversed English → Turkish meanings'),
      _ => L('Kaynak: belirtilmemiş', 'Source: not stated'),
    };

/// Princeton WordNet 3.0 licence, which has to appear on all copies
/// (wordnet/LICENSE of the WordNet 3.0 release).
const wordNetLicence = '''WordNet Release 3.0

This software and database is being provided to you, the LICENSEE, by Princeton University under the following license. By obtaining, using and/or copying this software and database, you agree that you have read, understood, and will comply with these terms and conditions.:

Permission to use, copy, modify and distribute this software and database and its documentation for any purpose and without fee or royalty is hereby granted, provided that you agree to comply with the following copyright notice and statements, including the disclaimer, and that the same appear on ALL copies of the software, database and documentation, including modifications that you make for internal use or for distribution.

WordNet 3.0 Copyright 2006 by Princeton University. All rights reserved.

THIS SOFTWARE AND DATABASE IS PROVIDED "AS IS" AND PRINCETON UNIVERSITY MAKES NO REPRESENTATIONS OR WARRANTIES, EXPRESS OR IMPLIED. BY WAY OF EXAMPLE, BUT NOT LIMITATION, PRINCETON UNIVERSITY MAKES NO REPRESENTATIONS OR WARRANTIES OF MERCHANTABILITY OR FITNESS FOR ANY PARTICULAR PURPOSE OR THAT THE USE OF THE LICENSED SOFTWARE, DATABASE OR DOCUMENTATION WILL NOT INFRINGE ANY THIRD PARTY PATENTS, COPYRIGHTS, TRADEMARKS OR OTHER RIGHTS.

The name of Princeton University or Princeton may not be used in advertising or publicity pertaining to distribution of the software and/or database. Title to copyright in this software, database and any associated documentation shall at all times remain with Princeton University and LICENSEE agrees to preserve same.''';

/// Licence notices of the dictionary data, shown with the library licences
/// (showLicensePage). Only verified notices are listed.
const dataLicenceNotices = <(String, String)>[
  ('Princeton WordNet 3.0', wordNetLicence),
  ('KeNet Turkish WordNet',
      'KeNet Turkish WordNet, Starlang Software / Özyeğin University. Data licensed under the Creative Commons Attribution-ShareAlike 4.0 International License: https://creativecommons.org/licenses/by-sa/4.0/ (source: github.com/StarlangSoftware/TurkishWordNet, README "Licensing").'),
  ('Collaborative Interlingual Index',
      'The Collaborative Interlingual Index licensed under CC BY 4.0 or any later version. Copyright 2015-2016: Francis Bond. https://creativecommons.org/licenses/by/4.0/'),
  ('Wiktionary',
      'Contains material from English and Turkish Wiktionary (wiktionary.org) by Wiktionary contributors, used under the Creative Commons Attribution-ShareAlike 4.0 International License: https://creativecommons.org/licenses/by-sa/4.0/. The material was shortened, merged and reordered.'),
  ('Tatoeba',
      'Example sentences from Tatoeba (tatoeba.org) by Tatoeba contributors. Default licence: Creative Commons Attribution 2.0 France, https://creativecommons.org/licenses/by/2.0/fr/. Individual sentences may carry another licence.'),
];

bool _dataLicencesAdded = false;

/// Adds [dataLicenceNotices] to Flutter's licence registry once.
void registerDataLicences() {
  if (_dataLicencesAdded) return;
  _dataLicencesAdded = true;
  LicenseRegistry.addLicense(() => Stream.fromIterable([
        for (final (name, text) in dataLicenceNotices) LicenseEntryWithLineBreaks([name], text),
      ]));
}
