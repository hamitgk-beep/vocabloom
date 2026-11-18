# Kullanım etiketleri (register) önerisi

## Yapı
Etiketler kelimenin tamamına değil, her anlama (sense) bağlanır. Bir kelimenin tarafsız ve aşağılayıcı anlamları ayrı anlam satırlarında kalır.

Her anlam için:
- `etiketler`: liste, şu değerlerden biri ya da birkaçı:
  `argo`, `kaba`, `asagilayici`, `tarihsel`, `bolgesel`, `cinsel`, `resmi`, `gayriresmi`, `teknik`, `eufemistik`
- `etiket_notu`: serbest metin (ör. "İngiliz argosu, eski")
- `etiket_kaynak`: `qc_notu` (otomatik) ya da `insan` (onaylanmış)
- Anlam silinmez veya sansürlenmez. Etiket yalnızca gösterimi değiştirir.

Mevcut `note` alanı korunur. Yeni alan eklenir, kaynak veri değişmez.

## Öncelikli altı kelime (merged_v3'teki anlamlar)
| kelime | anlam | mevcut not | önerilen etiket | sorun |
|---|---|---|---|---|
| faggot | 1 (eşcinsel erkek) | aşağılayıcı, küfür niteliğinde | asagilayici, kaba | Türkçe karşılık tek başına nötr okunabilir; etiket şart |
| sod | 2 (eşcinsel erkek, ibne) | aşağılayıcı, argo | asagilayici, argo, kaba | "ibne" da hakaret; etiket şart |
| sod | 3 (herif, adam) | İngiliz argosu, eski | argo, tarihsel | doğru |
| frigid | 2 (cinsel isteksiz) | resmî, eski kullanım | cinsel, tarihsel, asagilayici | "resmî" yanlış; bu kullanım resmî değil |
| creep | 3 (ürkütücü tip) | aşağılayıcı | asagilayici, gayriresmi | doğru, gayriresmi eklenebilir |
| creep | 2 (ürpertmek) | resmî değil | gayriresmi | doğru |
| screw | 3 (gardiyan) | eski ve argo | argo, tarihsel | doğru |
| screw | 6 (becermek, dolandırmak) | argo, mecazi | argo | doğru |
| screw | 7 (sevişmek, yatmak) | vulgar, kaba | cinsel, kaba, argo | uyarı gerek |
| fuss | 1 (kavga, gürültü) | küçük nedenli tartışma | gayriresmi | not açıklaması anlamla uyumlu değil; anlam değişmedi |

Tüm bu değerler öneridir. Hiçbiri uygulanmadı.

## Öncelik sırası
1. faggot, sod, frigid (aşağılayıcı ve cinsel etiketleri)
2. screw, creep, fuss
3. Kalan 1.141 hassas işaretli kayıt, kelime listesindeki sıraya göre
