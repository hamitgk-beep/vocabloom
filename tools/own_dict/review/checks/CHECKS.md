# Ücretsiz kalite kontrolleri (API yok)

Bu kontroller yeni bir API çağrısı yapmadan, mevcut dosyalar üzerinde çalıştırıldı.

## 1. Register (argo, kaba, aşağılayıcı)
- `register_reconciled.tsv`: yeni anlamlarda hassas not taşıyan 1.141 kelime/kalıp, 4 eski listede olup yeni anlamda işareti olmayan kayıt (blacky, dike, nail, lord).
- QC'nin 1.173 sayısı kelime değil, anlam (sense) bazında bayrak sayısıdır. Kelime bazında 1.075'tir. Liste ise 1.076 kayıt içeriyor. Aradaki fark: çok anlamlı kelimeler, 4 eski kayıt ve 3 yeni bayrak.
- Hiçbir kayıt silinmedi, sansürlenmedi. Kullanım etiketi önerileri için dosyanın son sütununa bakın.

## 2. Şüpheli listesinde yanlış kategori
- ah, interpretation, isobar, mildness: "manuel_kontrol" yerine "supheli" olarak düzeltildi (`priority_queue.tsv`).

## 3. 670 anlam kaybı riski ve 184 şüpheli kelime (API yok)
- `semantic_670_184.tsv`: her kelimenin eski ilk üç anlamı için kalan/kaybolan durumu. KeNet (Excel'deki WordNet Türkçe) eş anlamlıları da sayıldı.
- 670 kelimenin tamamında eski anlamlarla kök eşleşmesi yok, çünkü bu kategoriye ancak hiçbir eşleşme olmayanlar girdi. KeNet yalnızca 63 / 44 / 36 kez (1., 2., 3. anlam) kurtarıyor.
- Büyük çoğunluk biçim farkı (ör. "-in, -ın" ile "(edat) -in; -nin") ve eş anlamlı ifade farkı. Bunlar hata sayılmadı, ama ücretsiz bir yöntemle doğrulanamıyor; insan incelemesi gerekiyor.
- Gerçek riskler, öncelikli inceleme: faggot (yeni anlam "eşcinsel erkek", aşağılayıcı kaynak), sod (yeni anlamda "eşcinsel" yanlış), frigid (cinsel anlam değişimi), screw, fuss, creep.

## 4. Dokuz Damdafayton kelimesi
- `damdafayton9.tsv`: hiçbiri silinmedi. 5 tanesi yazım adayı olarak işaretli (accoutrements, cap-a-pie, dieselize, monarchical, nonaggression). 4 tanesinin geçerliliği doğrulanmalı.

## 5. Excel dışındaki 37 kalıp
- `extra37_check.tsv`: 31 kalıp geçerli görünüyor, tutuldu. 6 kalıp incelenmeli: hard ever (geçersiz İngilizce), find quarrel in a straw (bozuk Türkçe), hone in on (home in on ile tekrar), stride along ve walk up (zayıf çeviri), at stool (etiket).

## 6. Veri tutarlılığı
- Hedef 42.154 kelime; uygulamada 42.154; bizde kendi anlamı 33.979 (+8 geçersiz). 8.176 kelimede yalnızca Wiktionary anlamı var, bunlar korunuyor.
- Hedef 16.098 kalıp = Excel "Kalıplar" satır sayısı. Uygulamada 16.135 var; fark 37 = yukarıdaki liste.
