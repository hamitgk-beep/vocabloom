# Çevrimdışı yapay zekâ öğretmeni: veri ve eğitim

Uygulamadaki "Yapay Zekâ" bölümünün üç paketi açık kaynaklı Qwen3 modelleridir (Apache 2.0, ticari kullanıma
açık). Telefonda llama.cpp ile internetsiz çalışırlar (`lib/ai/`).

| Paket | Model | Dosya | Kimler |
|---|---|---|---|
| Hafif | Qwen3 0.6B, Q6_K | ~495 MB | Herkes (ücretsiz) |
| Gelişmiş | Qwen3 1.7B, Q6_K | ~1,4 GB | Ücretli aboneler |
| Profesyonel | Qwen3 4B Instruct 2507, Q5_K_M | ~2,9 GB | Ücretli aboneler |

Abonelik henüz yok; ücretli paketler `ai_premium` ayarı veya `--dart-define=AI_PREMIUM=true` ile açılır.

## Kalite nasıl sağlanıyor

1. **Sözlük ve dilbilgisi desteği (her soruda):** Küçük model bilgi ezberlemek zorunda kalmasın diye uygulama her
   isteğe kendi sözlüğünden kelime anlamlarını, kalıpları (phrasal verb, deyim …) ve kural tabanlı zaman analizini
   ekler (`Tutor.grounding`). Model yalnızca bunları doğru ve akıcı Türkçeyle anlatır.
2. **Kitaptan sorular hatasızdır:** Sorular, şıklar ve doğru cevap sözlükten ve kelimenin kaydedildiği cümleden
   gelir; yapay zekâ yalnızca isteğe bağlı açıklamayı yazar.
3. **İnce ayar (bu klasör):** Modeller, uygulamanın kullandığı istemlerin birebir aynısıyla eğitilir.

## Eğitim verisi

| Görev | Kaynak | Cevapların doğruluğu |
|---|---|---|
| Cümle düzeltme | `errors.py`: Türklerin en sık yaptığı 66 hata kalıbı (zamanlar, edatlar, artikeller, yalancı eşdeğerler …), her biri Türkçe kural açıklamasıyla | Elle yazıldı, kesin |
| Cümle açıklama | Tatoeba'nın insan çevirili İngilizce-Türkçe cümleleri (~2.800, yetişkin/şiddet içerikli olanlar ayıklandı) + elle yazılmış 20 örnek (`data/seed_explain.jsonl`) | Öğretmen model + insan çevirisi |
| Sohbet | Elle yazılmış örnek sohbetler (`data/seed_chat.jsonl`) + öğretmen modelin yazdığı sohbetler | Öğretmen model |

## Adımlar

```bash
python3 tools/tutor/build_sft.py sentences 3000      # cümleleri seç
python3 tools/tutor/errors.py                         # düzeltme örnekleri
flutter test tools/tutor/export_prompts_test.dart     # istemleri uygulamanın ürettiği hâliyle çıkar
# İsteğe bağlı: büyük bir "öğretmen" modelle açıklama ve sohbet cevapları (ücretsiz seçenekler teacher.py içinde)
TEACHER_URL=... TEACHER_KEY=... TEACHER_MODEL=... python3 tools/tutor/teacher.py explain
TEACHER_URL=... TEACHER_KEY=... TEACHER_MODEL=... python3 tools/tutor/teacher.py chat 600
python3 tools/tutor/build_sft.py build                # data/train.jsonl, data/eval.jsonl
```

Sonra `train_tutor.ipynb` not defterini Kaggle'da veya Colab'da **ücretsiz GPU** ile çalıştırın (`PACKAGE` =
`lite`, `plus`, `pro`). Not defteri GGUF dosyasını üretir ve isterseniz Hugging Face hesabınıza yükler. Çıkan adres
`lib/ai/packages.dart` içindeki `urls` listesinin başına yazılır (ya da uygulamada `ai_url_<paket>` ayarıyla).

## Kontrol

`.github/workflows/ai-smoke.yml` her PR'da indirme adreslerini kontrol eder, Hafif ve Gelişmiş modelleri indirip
uygulamanın gerçek görevlerini çalıştırır; cevaplar iş akışı kaydında okunabilir.

## Lisanslar

- Qwen3 modelleri: Apache License 2.0
- Tatoeba cümleleri: CC BY 2.0 FR
