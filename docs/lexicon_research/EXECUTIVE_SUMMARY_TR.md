# Storilex sözlük araştırması: yönetici özeti

22 Kasım 2026 · Görev 5A · Yalnız araştırma: uygulama, sözlükler ve kullanıcı verisi değiştirilmedi.

## Kısaca
Storilex'in sözlüğü geniş, ama bazı yerlerde emin olmadığı bir anlamı "kesin" diye gösteriyor. Yeni kelime eklemek
yerine önce bunu düzeltmek kullanıcı güvenini en çok artıracak iş. Bunun için ücretli bir kaynağa gerek yok: açık ve
ticari kullanıma uygun üç bağımsız kaynak (Open English WordNet, KeNet, Vikisözlük) birbirini denetleyecek şekilde
kullanılabilir.

## 1. Önerilen kaynaklar
- **Open English WordNet 2025:** İngilizce anlamlar ve sözcük türleri. Bugün kullanılan WordNet'in bakımı süren,
  serbest lisanslı (CC BY 4.0) yeni sürümü.
- **Vikisözlük (Wiktionary):** Türkçe karşılıkların ana kaynağı. Ama bu kez her çevirinin hangi anlama ait olduğu da
  alınmalı.
- **KeNet (Türkçe WordNet):** Elle hazırlanmış Türkçe anlamlar. Vikisözlük'ten bağımsız olduğu için ikinci tanık.
- **wordfreq:** Kelime sıklığı. Bugünkü sıklık tablosunda "Tom" en sık kelime çıkıyor, çünkü örnek cümle
  sitesinden sayılmış.
- **Tatoeba:** İnsan çevirisi örnek cümleler. Her cümlenin lisansı ayrıca kaydedilmeli.
- Yalnız geliştirici bilgisayarında: **spaCy** (İngilizce), **Zemberek** (Türkçe) ve çok dilli bir benzerlik modeli.
  Bunlar uygulamaya eklenmez, yalnız öneri üretir.

## 2. Önerilmeyenler
- BabelNet, UDPipe modelleri, PARSEME'nin Türkçe kısmı: ticari kullanım yasak.
- PanLex: kendi iki resmî sayfası farklı lisans söylüyor.
- LanguageTool: Türkçe desteklemiyor.
- ConceptNet, DBnary, OMW'nin Türkçesi: Vikisözlük'ün kopyası, bağımsız kanıt değil.
- OpenSubtitles ve NLLB cümleleri: lisansı yok.
- Oxford, Cambridge, Longman, TDK: lisanslı. İçerikleri alınmaz, yalnız çalışma yöntemlerinden ders çıkarılır.

## 3. Mevcut sözlük: güçlü ve zayıf yönler
**Güçlü:** Kaynak öncelik kuralı var (onaylı katkı > güvenilir kaynak > yapay zekâ taslağı). Taslaklar etiketli ve
kapalı bölümde gösteriliyor. Tekrar kartlarında tek bir güven kuralı kullanılıyor. Her şey çevrimdışı ve hızlı:
bir anlam seçimi yaklaşık 2 milisaniye.

**Zayıf:**
- 41 bin kelimelik "kendi sözlük" bölümü incelenmemiş yapay zekâ taslağı.
- Bu taslakların ilk anlamı, ana listenin ilk anlamıyla 19 bin kelimede hiç ortak kelime paylaşmıyor. Çoğu yalnız
  farklı söyleyiş, ama içlerinde yanlışlar var.
- Ana listenin yardımcı kaynağının (damdafayton) lisans dosyası yok.
- WordNet örnek cümlelerinin hiçbirinin Türkçesi yok.

## 4. Gerçek testlerle ölçülen sonuçlar
Testler, daha önce hiç kullanılmamış ve başkalarının elle etiketlediği verilerle yapıldı. Ben (Claude) etiket
koymadım, insan değerlendirmesi de yapılmadı.
- Kelimenin kökünü bulma: İngilizcede %95,6, Türkçede %78.
- Cümledeki anlam: kullanıcının gördüğü Türkçe, %78 oranında elle yapılmış Türkçe sözlükle aynı. Bu oran,
  "her zaman ilk anlamı göster" yöntemiyle hemen hemen aynı. Yani bağlama bakma şu an ek kazanç sağlamıyor.
- "Kesin" denip yanlış çıkan: Türkçe karşılıkta 9'da 1, sözcük türünde 7'de 1.
- Sözlükte kelime olarak da geçen özel adların yarısına "kesin" bir anlam veriliyor. Çoğu zararsız
  (Iraq → Irak), ama bazıları yanlış (ürün adı "Nook" → "köşe").
- Deyimler: düz anlamıyla kullanılmış cümlelerin yarısından fazlası deyim sanılıyor.
- Bulunamayan sık İngilizce kelimeler çoğunlukla özel ad. Gerçek eksik az.

## 5. En önemli beş güvenilirlik riski
1. "Kesin" etiketi fazla cömert. Yanlış anlam emin bir dille gösteriliyor.
2. Yapay zekâ taslağı ile ana liste aynı Türkçeyi verince bu "doğrulama" sayılıyor. Ama ikisi birbirinden
   kopyalanmış olabilir; türleri farklı olsa bile kabul ediliyor (isim "stop" → "durmak").
3. Köke indirme hataları kelimeyi tamamen değiştiriyor: customer → custom, owner → own.
4. Özel adlara ve düz kullanılan deyimlere sözlük anlamı veriliyor.
5. Kaynak izi yok. Bir anlamın hangi kaynaktan geldiği satır düzeyinde bilinmiyor. Bu hem kalite hem lisans denetimini
   zorlaştırıyor.

## 6. Önerilen mimari
Yedi katman var:
1. Her kaydın kaynağını, sürümünü ve lisansını tutan bir kaynak katmanı.
2. Kök ve tür analizi.
3. Bağımsız kaynakların birbirini doğruladığı anlam doğrulama katmanı. Aynı kökenden gelen iki kaynak tek tanık
   sayılır.
4. Bağlam katmanı.
5. Kayıtları "doğrulanmış / olası / çelişkili / taslak / reddedildi" diye ayıran güven katmanı.
6. Kararları ve gerekçeleri saklayan insan inceleme katmanı.
7. Lisans ve kalite koşullarını sağlamayanı yayımlamayan yayın kapısı.

Uygulamadaki mevcut sistem yeniden yazılmıyor. Ağır işler geliştirici bilgisayarında, açık PR #99'un aday
veritabanında yapılıyor.

## 7. Öncelik sırası
1. Ölçüm kümelerini sabitle.
2. "Kesin" etiketini sıkılaştır ve köke indirme hatalarını düzelt (küçük kod değişiklikleri).
3. Her anlamın kaynağını etiketle ve lisans sorunlarını netleştir.
4. Bağımsız kaynaklarla çelişki raporu çıkar.
5. Çelişkileri senin incelemen için öne alan bir inceleme döngüsü kur.
6. Yayın kapısını kur.
7. En son yeni kelime ve deyim ekle.

## 8. Lisans açısından açık konular
- damdafayton verisi: lisans dosyası yok ve kökeni bilinmiyor; Ayarlar'da "MIT" yazıyor. Yazardan yazılı izin
  alınmalı ya da bu veri çıkarılmalı.
- FreeDict (GPL) içeriği, CC BY-SA lisanslı sözlük dosyalarında duruyor. Uyumlu olup olmadığı belirsiz; uzman görüşü
  gerekir.
- Kindle derlemesinin içeriği GPL. "Yalnız Vikisözlük kısmı alındı" ayrımı doğrulanmalı.
- Türkçe–İngilizce sözlüğün kaynak listesinde FreeDict ve WordNet yazmıyor.
- Tatoeba cümlelerinin lisansı cümle başına saklanmıyor.
- Zemberek kök sözlüğünün kökeni (TDK ile örtüşme) belirsiz.

## 9. Teslim edilenler
`docs/lexicon_research/` altında 7 rapor ve testleri yeniden çalıştırmak için 3 betik (`scripts/`). Hepsi tek commit
olarak `claude/project-thread-zgx546` dalında. PR açılmadı, hiçbir şey birleştirilmedi, sürüm yayımlanmadı.
