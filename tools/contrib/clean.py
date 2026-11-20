"""Turns the filled-in dictionary sheets (tools/contrib/*.xlsx, made from the
template sozluk-veri-sablonu.xlsx) into tools/contrib/storilex_contrib.json,
which tools/contrib/apply.py adds to the dictionaries.

The corrections found when a sheet was checked are applied here, so the files
stay as they were sent (the tables below, one set a file):
  - rows that held several different meanings are split, one meaning a row;
  - wrong meanings and unnatural sentences are fixed;
  - the "meaning in context" sentences of the first file get a translation,
    so they can also be shown as examples.
A filter sheet (filtre-kalip-sablonu.xlsx) adds phrases with the filter they
belong to ("cat"). A later file repeats rows of the earlier ones; a row that is the same as in an
earlier file is read only once, with that file's corrections.

usage: python3 tools/contrib/clean.py tools/contrib/storilex_contrib.json \
         tools/contrib/hamit_2026-11-20.xlsx tools/contrib/hamit_2026-11-20_v2.xlsx \
         tools/contrib/hamit_2026-11-20_v3.xlsx tools/contrib/hamit_2026-11-20_v4.xlsx \
         tools/contrib/hamit_2026-11-20_v5.xlsx tools/contrib/hamit_filtre_2026-11-20.xlsx \
         tools/contrib/hamit_filtre2_2026-11-20.xlsx tools/contrib/hamit_filtre3_2026-11-20.xlsx \
         tools/contrib/hamit_2026-11-20_v6.xlsx tools/contrib/hamit_filtre4_2026-11-20.xlsx tools/contrib/hamit_filtre5_2026-11-20.xlsx \
         tools/contrib/hamit_filtre6_2026-11-20.xlsx tools/contrib/hamit_2026-11-20_v7.xlsx \
         tools/contrib/hamit_2026-11-20_v8.xlsx tools/contrib/hamit_filtre7_2026-11-20.xlsx tools/contrib/hamit_filtre8_2026-11-20.xlsx \
         tools/contrib/hamit_filtre9_2026-11-20.xlsx tools/contrib/hamit_filtre10_2026-11-20.xlsx \
         tools/contrib/hamit_2026-11-20_v9.xlsx tools/contrib/hamit_filtre11_2026-11-20.xlsx tools/contrib/hamit_filtre12_2026-11-20.xlsx \
         tools/contrib/hamit_2026-11-20_v10.xlsx tools/contrib/hamit_filtre13_2026-11-20.xlsx \
         tools/contrib/hamit_denetim14_2026-11-20.xlsx tools/contrib/hamit_denetim15_2026-11-20.xlsx \
         tools/contrib/hamit_2026-11-20_v11.xlsx tools/contrib/hamit_denetim16_2026-11-20.xlsx \
         tools/contrib/hamit_2026-11-20_v12.xlsx tools/contrib/hamit_filtre17_2026-11-20.xlsx \
         tools/contrib/hamit_2026-11-20_v13.xlsx tools/contrib/hamit_filtre18_2026-11-20.xlsx \
         tools/contrib/hamit_2026-11-20_v14.xlsx tools/contrib/hamit_2026-11-20_v15.xlsx \
         tools/contrib/hamit_denetim19_2026-11-20.xlsx tools/contrib/hamit_2026-11-20_v16.xlsx \
         tools/contrib/hamit_2026-11-20_v17.xlsx tools/contrib/hamit_denetim20_2026-11-20.xlsx \
         tools/contrib/hamit_2026-11-20_v18.xlsx tools/contrib/hamit_denetim21_2026-11-20.xlsx \
         tools/contrib/hamit_2026-11-20_v19.xlsx tools/contrib/hamit_denetim22_2026-11-20.xlsx \
         tools/contrib/hamit_2026-11-20_v20.xlsx tools/contrib/hamit_denetim23_2026-11-20.xlsx \
         tools/contrib/hamit_obek1_2026-11-20.xlsx tools/contrib/hamit_deyim1_2026-11-20.xlsx \
         tools/contrib/hamit_obek2_2026-11-20.xlsx tools/contrib/hamit_obek3_2026-11-20.xlsx tools/contrib/hamit_obek4_2026-11-20.xlsx \
         tools/contrib/hamit_deyim2_2026-11-20.xlsx tools/contrib/hamit_obek5_2026-11-20.xlsx \
         tools/contrib/hamit_deyim3_2026-11-20.xlsx \
         tools/contrib/hamit_deyim4_2026-11-20.xlsx tools/contrib/hamit_obek6_2026-11-20.xlsx tools/contrib/hamit_obek7_2026-11-20.xlsx \
         tools/contrib/hamit_obek8_2026-11-20.xlsx tools/contrib/hamit_obek9_2026-11-20.xlsx tools/contrib/hamit_obek10_2026-11-20.xlsx \
         tools/contrib/hamit_obek11_2026-11-20.xlsx
"""
import json
import re
import sys

import openpyxl

POS = {'isim': 'noun', 'fiil': 'verb', 'sıfat': 'adj', 'zarf': 'adv', 'zamir': 'pron', 'edat': 'postp',
       'bağlaç': 'conj', 'ünlem': 'intj', 'sayı': 'num', 'deyim': 'phrase', 'kalıp': 'phrase'}

# --- First file, hamit_2026-11-20.xlsx --------------------------------------
# Sentence fixes: row -> (sentence, form, lemma, meaning)
CTX_FIX = {
    9: ('Korkusu yüzüne vurmuştu.', 'vurmuştu', 'vurmak', 'to show on (one\'s face)'),
    38: ('Bu salon kırk kişiyi rahatlıkla alır.', 'alır', 'almak', 'to hold, to accommodate'),
    39: ('Odayı birdenbire yoğun bir kahve kokusu aldı.', 'aldı', 'almak', 'to fill, to pervade'),
    50: (None, None, None, 'to put up (on a shelf)'),
    58: ('Be careful not to let the bathwater run over.', 'run over', 'run over', 'taşmak'),
    101: (None, None, None, 'tam, tam olarak'),
}
# "drop me a line" is a set phrase: it goes to the phrases instead.
CTX_TO_PHRASE = {97}
# Translations of the context sentences, so they can be examples too.
CTX_TR = {
    2: 'The programme that was broadcast lasted about ten years.',
    3: 'He drives the car very fast.',
    4: 'Oraya varmak iki saat sürdü.',
    5: 'The child hit the ball in his hand hard against the ground in the garden.',
    6: 'Towards morning the winter cold really struck our faces.',
    7: 'The sea waves were crashing hard against the rocks.',
    8: 'Sunlight falls directly on my desk.',
    9: 'His fear showed on his face.',
    10: 'He accidentally broke the glass of water on the table with his elbow.',
    11: 'With these words he deeply hurt his best friend\'s feelings.',
    12: 'He avoided the accident by suddenly swerving to the right.',
    13: 'The cold medicine brought his fever down a little.',
    14: 'This year the company clearly broke its sales record.',
    15: 'The old man slowly stood up, leaning on his walking stick.',
    16: 'The Ankara train will depart from platform one shortly.',
    17: 'This old rule was completely abolished last year.',
    18: 'I am used to getting out of bed at six in the morning.',
    19: 'He tried to do such a heavy job all by himself.',
    20: 'He quietly opened the door with the key and went in.',
    21: 'He turned on the television and started watching the evening news.',
    22: 'With the arrival of spring, all the flowers in the garden bloomed.',
    23: 'This light blue shirt really brightens up your face.',
    24: 'The municipal crews finally reopened the closed village road.',
    25: 'His legs ached a lot from standing all day.',
    26: 'When the light turned red, all the vehicles stopped at the line.',
    27: 'The old wall clock stopped during the night because its battery ran out.',
    28: 'This jacket fitted his shoulders perfectly and looked very smart on him.',
    29: 'In the meeting we dwelt especially on the budget cuts.',
    30: 'She slowly put the heavy bag down on the table.',
    31: 'He gave up smoking completely to look after his health.',
    32: 'I dropped my brother off at school by car this morning.',
    33: 'I left the hardest question in the exam until the end.',
    34: 'His grandfather left him a small shop in the city centre.',
    35: 'He pulled the thickest novel out of the bookcase.',
    36: 'I bought fresh bread and milk at the market and went home.',
    37: 'On her birthday she got a very nice present from her friend.',
    38: 'This hall easily holds forty people.',
    39: 'Suddenly a strong smell of coffee filled the room.',
    40: 'He looked out of the window for a long time.',
    41: 'While we were on holiday, our neighbour looked after our cat carefully.',
    42: 'An experienced lawyer is handling this case.',
    43: 'Our balcony faces south.',
    44: 'The doctor examined the patient\'s throat and wrote a prescription.',
    45: 'She put the old letters at the very bottom of the drawer.',
    46: 'If you add a little more salt to the soup, it will taste better.',
    47: 'They named their newborn baby after his grandfather.',
    48: 'We decided to set out early tomorrow morning.',
    49: 'The company management set this rule last month.',
    50: 'She put the thick winter sweaters up on the top shelf.',
    51: 'As soon as he came in, he took off his wet shoes.',
    52: 'This autumn the writer published a new book of stories.',
    53: 'Many famous artists came from this small town.',
    54: 'The bill turned out to be much higher than we expected.',
    55: 'İşten önce her sabah beş kilometre koşar.',
    56: 'Şehir merkezinde küçük bir aile fırını işletiyor.',
    57: 'Yerel otobüs hafta içi on beş dakikada bir kalkıyor.',
    58: 'Banyo suyunun taşmamasına dikkat et.',
    59: 'Tedarikçiyle sözleşmemiz aralık ayına kadar geçerli.',
    60: 'Lütfen ağır kutuyu ön kapının yanına bırakın.',
    61: 'Alarmını saat altıya kurmayı unutma.',
    62: 'Güneş yedi sularında dağların arkasında batar.',
    63: 'Yönetmen proje için kesin bir son tarih belirledi.',
    64: 'Roman on dokuzuncu yüzyıl İstanbul\'unda geçiyor.',
    65: 'Ben ayakkabılarımı bağlarken çantamı tutar mısın?',
    66: 'Yeni konferans salonu beş yüz kişiye kadar alabiliyor.',
    67: 'Yıllık toplantıyı önümüzdeki salı yapacaklar.',
    68: 'Aramanızı aktarırken lütfen hatta bekleyin.',
    69: 'Eski tahta köprü ağır kamyonları taşıyamaz.',
    70: 'Bir sonraki trafik ışığında sola dönmeye karar verdi.',
    71: 'Sonbaharda yapraklar parlak sarı ve turuncuya döner.',
    72: 'Bebek uyuyor, lütfen müziğin sesini kıs.',
    73: 'Hava gece birden soğudu.',
    74: 'Anahtarı kilitte çevirip kapıyı açtı.',
    75: 'Açık pencereden hafif bir esinti yavaşça esti.',
    76: 'Rahat okuyabilmemiz için lütfen ışığı aç.',
    77: 'Kuru dallarla kamp ateşi yakmaya çalıştık.',
    78: 'Sıcak yaz günlerinde açık renkler giymeyi tercih ediyor.',
    79: 'Pazar sabahları trafik genellikle oldukça sakin olur.',
    80: 'Akşam yemeği için pencere kenarında bir masa ayırtmaya karar verdik.',
    81: 'Az önce çok ilginç bir tarih kitabı okumayı bitirdim.',
    82: 'Hakem geç kalan bir müdahale yüzünden oyuncuya sarı kart göstermek zorunda kaldı.',
    83: 'Boyanın rengini duvara uydurduğundan emin ol.',
    84: 'Final maçı binlerce taraftar çekti.',
    85: 'Doğum günü mumlarını yakmak için bir kibrit çaktı.',
    86: 'Berrak mavi gökyüzü sakin gölde yansıdı.',
    87: 'Açıklaması o kadar netti ki herkes anladı.',
    88: 'Tatlıyı servis etmeden önce masayı toplamamız gerekiyor.',
    89: 'Yoğun sis nihayet öğleye doğru dağılmaya başladı.',
    90: 'Kural dışı park ettiği için yüklü bir para cezası ödemek zorunda kaldı.',
    91: 'Bugün hava parkta yürüyüş için güzel görünüyor.',
    92: 'Bu atkı çok ince ipek kumaştan yapılmış.',
    93: 'Kendi seçimlerinin sorumluluğunu taşımak zorundasın.',
    94: 'Sabahın erken saatlerindeki inşaat gürültüsüne katlanamıyorum.',
    95: 'Ormanda nehrin yakınında büyük, kahverengi bir ayı gördük.',
    96: 'Ağaç her yaz sonu tatlı kırmızı elmalar verir.',
    98: 'O kırılgan cam vazoyu düşürmemeye dikkat et.',
    99: 'Çölde güneş battıktan sonra sıcaklık genellikle hızla düşer.',
    100: 'Alnına tek bir yağmur damlası düştüğünü hissetti.',
    101: 'Tren merkez istasyona tam vaktinde vardı.',
    102: 'Ders sırasında soru sormaya her türlü hakkın var.',
    103: 'Köşeden sağa dön ve iki sokak dümdüz yürü.',
    104: 'Teklifi kabul ederek doğru karar verdiğini düşünüyorum.',
}
# row -> the meanings it is split into: [(part of speech, meaning, note), ...]
EN_SPLIT = {
    7: [('fiil', 'akmak', 'sıvı için'), ('fiil', 'çalışmak', 'makine, sistem için')],
    14: [('fiil', 'dönmek', 'yön değiştirmek'), ('fiil', 'çevirmek', 'bir şeyi döndürmek')],
    31: [('fiil', 'düşürmek', 'elinden kaçırmak'), ('fiil', 'düşmek, azalmak', 'aşağı inmek, değeri azalmak')],
    35: [('zarf', 'sağa', 'sağ tarafa'), ('zarf', 'tam, tam olarak', 'right on time: tam vaktinde')],
    39: [('fiil', 'oynamak', 'oyun oynamak'), ('fiil', 'çalmak', 'müzik aleti çalmak')],
    44: [('isim', 'yay', 'esnek metal sarmal'), ('isim', 'pınar, kaynak', 'yerden çıkan su')],
    53: [('sıfat', 'zor', 'kolay olmayan'), ('sıfat', 'sert, katı', 'yumuşak olmayan')],
    60: [('sıfat', 'kaba, kötü kalpli', 'kötü niyetli'), ('sıfat', 'cimri', 'eli sıkı')],
    66: [('fiil', 'fark etmek', 'dikkat etmek'), ('fiil', 'belirtmek', 'söz etmek')],
    67: [('isim', 'sipariş', 'ısmarlanan şey'), ('isim', 'düzen, sıra', 'tertip'), ('isim', 'emir', 'buyruk')],
    68: [('fiil', 'sipariş vermek', 'ısmarlamak'), ('fiil', 'emretmek', 'buyurmak')],
    69: [('isim', 'parça, bölüm', 'bütünün bir kısmı'), ('isim', 'rol', 'oyunda, filmde')],
    70: [('fiil', 'geçmek', 'bir yerden ilerlemek'), ('fiil', 'uzatmak, vermek', 'elden ele vermek')],
    75: [('isim', 'posta', 'mektup, koli'), ('isim', 'görev, makam', 'iş yerindeki konum'), ('isim', 'direk', 'dikili kazık')],
    76: [('fiil', 'postalamak', 'postayla göndermek'), ('fiil', 'paylaşmak', 'internette yayınlamak')],
    82: [('fiil', 'kaldırmak', 'yukarı çıkarmak'), ('fiil', 'artırmak', 'miktarı yükseltmek'), ('fiil', 'yetiştirmek', 'çocuk büyütmek')],
    84: [('isim', 'sebep, neden', 'gerekçe'), ('isim', 'akıl', 'düşünme yetisi')],
    85: [('isim', 'kayıt', 'saklanan bilgi'), ('isim', 'rekor', 'en iyi derece'), ('isim', 'plak', 'müzik kaydı')],
    88: [('isim', 'geri kalan', 'artakalan kısım'), ('isim', 'dinlenme', 'mola')],
    89: [('fiil', 'dönmek', 'geri gelmek'), ('fiil', 'iade etmek', 'geri vermek')],
    96: [('fiil', 'kurtarmak', 'tehlikeden korumak'), ('fiil', 'biriktirmek', 'para saklamak'), ('fiil', 'kaydetmek', 'dosya, bilgisayar')],
    98: [('isim', 'duyu', 'algılama yetisi'), ('isim', 'anlam', 'bir sözün anlamı'), ('isim', 'sağduyu', 'mantık')],
    99: [('fiil', 'hizmet etmek', 'görev yapmak'), ('fiil', 'servis yapmak', 'yemek sunmak')],
    101: [('isim', 'işaret, belirti', 'iz, gösterge'), ('isim', 'tabela, levha', 'yol, dükkân tabelası')],
}
TR_SPLIT = {
    64: [('fiil', 'to wait', 'birinin gelmesini beklemek'), ('fiil', 'to expect', 'bir şeyin olmasını ummak')],
}
EX_EN_FIX = {
    37: 'Our guests are coming to our place for dinner tomorrow.',
    45: 'I always read twenty pages of a book before I go to sleep.',
    80: 'The new fast train cut the journey between the two cities to two hours.',
}
PH_FIX = {
    10: {'meaning': 'to dare, to risk'},
    27: {'ex': 'Bu konunun üstüne düşersen kısa sürede çözersin.'},
    49: {'phrase': 'gözünü kırpmamak'},
    51: {'meaning': 'to be unable to sleep, to be wide awake'},
}

# --- Second file, hamit_2026-11-20_v2.xlsx (600 rows a sheet) ----------------
V2_CTX_FIX = {
    144: ('Trafik sabah saatlerinde bile rahatça akıyordu.', None, None, 'to flow smoothly (traffic)'),
    149: ('Satıcı fiyatta biraz daha indirim yaptı.', 'yaptı', 'yapmak', 'to give (a discount)'),
    182: ('Yarışmacı son turda rakiplerinden birine tur bindirdi.', 'bindirdi', 'bindirmek', 'to lap (a rival in a race: tur bindirmek)'),
    232: (None, None, 'yayılmak', None),
    233: (None, None, 'yayılmak', None),
    322: ('Takım son dakikada attığı golle skoru ikiye çıkardı.', 'çıkardı', 'çıkarmak', 'to bring (a score) up to'),
    337: ('Bozuk prize dokununca elini elektrik çarptı.', None, None, None),
    341: ('Hangisini seçtiğin fark etmez, ikisi de aynı kalitede.', 'fark etmez', None, 'to make a difference, to matter'),
    413: (None, None, None, 'acil olmak, sıkıştırmak (zaman)'),
    451: ('The president addressed the nation on national television.', 'nation', 'nation', 'millet, ulus'),
    541: (None, None, None, 'üfleyerek söndürmek'),
}
# New sentences: (sentence, form, lemma, lang, meaning)
V2_CTX_ADD = [
    ('The state pays for the schools in this region.', 'state', 'state', 'en', 'devlet'),
]
V2_EN_SPLIT = {
    298: [('isim', 'açı', 'geometride, köşede'), ('isim', 'bakış açısı', 'bir konuya yaklaşım')],
    322: [('isim', 'madde', 'sözleşme, yasa maddesi'), ('isim', 'eşya, parça', 'nesne')],
    350: [('sıfat', 'tuhaf, rahatsız edici', 'ortam, sessizlik için'), ('sıfat', 'sakar, beceriksiz', 'hareketleri için'), ('sıfat', 'mahcup', 'utanmış')],
    352: [('isim', 'kelepir', 'uygun fiyatlı alışveriş'), ('isim', 'pazarlık, anlaşma', 'karşılıklı uzlaşma')],
    356: [('isim', 'ışın, ışık demeti', 'ışık'), ('isim', 'kiriş', 'yapı direği')],
    366: [('fiil', 'bağlamak', 'birleştirmek, sarmak'), ('fiil', 'ciltlemek', 'kitap için')],
    380: [('fiil', 'rahatsız etmek', 'sıkıntı vermek'), ('fiil', 'zahmet etmek', 'uğraşmak')],
    382: [('isim', 'dal', 'ağaç kolu'), ('isim', 'şube', 'kurum birimi')],
    387: [('sıfat', 'harika', 'çok başarılı'), ('sıfat', 'zeki, parlak', 'insan için'), ('sıfat', 'parlak, ışıl ışıl', 'ışık için')],
    412: [('fiil', 'iddia etmek', 'ileri sürmek'), ('fiil', 'talep etmek', 'hak istemek')],
    421: [('isim', 'rahatlık, konfor', 'huzur'), ('isim', 'teselli', 'avuntu')],
    493: [('isim', 'eylem, iş', 'yapılan hareket'), ('isim', 'tapu', 'mülkiyet belgesi')],
    504: [('fiil', 'bağlı olmak', 'duruma göre değişmek'), ('fiil', 'güvenmek', 'depend on: birine güvenmek')],
    529: [('fiil', 'görevden almak', 'işten çıkarmak'), ('fiil', 'reddetmek, önemsememek', 'bir fikri')],
    537: [('sıfat', 'yurt içi, yerli', 'ülke içi'), ('sıfat', 'ev içi, evcil', 'ev ile ilgili')],
    545: [('sıfat', 'sıkıcı', 'ilgi çekmeyen'), ('sıfat', 'donuk, mat', 'renk, ışık için'), ('sıfat', 'kör', 'bıçak için')],
    568: [('fiil', 'işe almak, çalıştırmak', 'iş vermek'), ('fiil', 'kullanmak', 'yöntem, araç')],
    574: [('fiil', 'ilgisini çekmek', 'dikkatini tutmak'), ('fiil', 'katılmak', 'engage in')],
    597: [('fiil', 'incelemek', 'gözden geçirmek'), ('fiil', 'muayene etmek', 'doktor için')],
    604: [('fiil', 'çok yormak, bitkin düşürmek', 'yorgunluk'), ('fiil', 'tüketmek', 'kaynağı bitirmek')],
}
V2_TR_SPLIT = {
    556: [('sıfat', 'neighbouring', 'bitişik')],
}
# Examples: row -> the columns that change
V2_EX_FIX = {
    216: {'meaning': 'teşekkür etmek, emeğini anmak'},
    255: {'meaning': 'seyirci, izleyiciler', 'tr': 'Oyun bittiğinde seyirciler oyuncuları dakikalarca alkışladı.'},
    279: {'tr': 'Ekibimiz en zorlu teknik projeleri bile tamamlayabilecek kapasitededir.'},
    299: {'meaning': 'teyit etmek, doğrulamak', 'tr': 'Uçuş saatini havaalanına gitmeden önce internetten teyit ettim.'},
    392: {'en': 'The referee treated both teams fairly throughout the match.'},
    397: {'meaning': 'yüzmek, süzülmek (su yüzeyinde)'},
    414: {'meaning': 'belirlemek, tespit etmek'},
    430: {'tr': 'Bu yaz tatilinde Karadeniz yaylalarını gezmeye niyetliyiz.'},
    437: {'meaning': 'meraklı, istekli', 'tr': 'Küçük yaşlardan beri astronomiye büyük bir ilgisi vardı.'},
    450: {'tr': 'Bu otel yüksek hizmet kalitesini yıllardır sürdürüyor.',
          'en': 'This hotel has maintained its high quality of service for years.'},
    465: {'tr': 'Trenin hafif hareketi uykumu getirdi.', 'en': 'The gentle motion of the train made me sleepy.'},
    469: {'meaning': 'ana dili olarak konuşan',
          'tr': 'Ana dili olarak konuşan biri kadar akıcı konuşabilmek için bol bol dinleme pratiği yapıyor.'},
    474: {'en': 'I noticed in the morning that the first flowers had opened on the tree in the garden.'},
    515: {'tr': 'Öğretmen öğrencinin yaratıcı kompozisyonunu tüm sınıfın önünde övdü.',
          'en': "The teacher praised the student's creative essay in front of the whole class."},
    523: {'tr': 'Düzenli bakım arızaların oluşmasını önler.', 'en': 'Regular maintenance prevents malfunctions.'},
    528: {'tr': 'Güvenlik her zaman birinci önceliğimizdir.', 'en': 'Safety is always our first priority.'},
    529: {'meaning': 'özel, kişisel', 'tr': 'Bu konuşma tamamen özel, lütfen kimseye anlatma.',
          'en': "This conversation is completely private, so please don't tell anyone."},
}
V2_PH_FIX = {
    312: {'meaning': 'to forgo what one is owed, to forgive wholeheartedly',
          'ex': 'Ayrılırken komşusu ona olan bütün hakkını helal etti.',
          'ex_tr': 'As he left, his neighbour wholeheartedly forgave anything he was owed.'},
    334: {'ex': 'Ne kadar uyarsak da laf dinlemiyor.', 'ex_tr': "However much we warn him, he won't listen."},
    372: {'ex_tr': 'Sınavlar gelecek hafta başlıyor, bu yüzden bu gece sıkı çalışmam gerek.'},
    414: {'ex_tr': 'Yardım etmeye varım ama bütün ödevini yapmaya gelince sınırı çizerim.'},
}

# --- Third file, hamit_2026-11-20_v3.xlsx ("1000 yeni kayıt") -------------------
# Most of its rows are numbered stand-ins ("phrase_499", "TR sent 5 for s4."):
# PLACEHOLDER leaves them out. Of the real rows:
V3_CTX_FIX = {
    26: ('Motorun bujilerinden biri bozulduğu için araç zor çalıştı.', 'çalıştı', 'çalışmak', 'to start (an engine)'),
}
# English context rows whose word is a phrasal verb: they go to the phrases with
# their sentence, so the verb alone ("bring") does not get the phrase's meaning.
V3_CTX_PHRASE = {
    502: 'bring about', 503: 'brush off', 504: 'iron out', 505: 'wipe out', 506: 'rule out', 507: 'phase out',
    508: 'single out', 509: 'boil down to', 510: 'piece together', 511: 'fall back on', 512: 'fade away',
    513: 'step down', 514: 'set out', 515: 'ward off', 516: 'gloss over', 517: 'band together',
}
V3_EX_FIX = {
    4: {'en': 'This technology broke new ground in medical science.'},
}

# --- Fourth file, hamit_2026-11-20_v4.xlsx ("1000 gerçek kayıt") -----------------
# Most of it is made from patterns: 20 verbs with 50 sentences each ("CEO yeniden
# yeni politikayı onayladı."), word pairs ("yavaş hedef: slow goal"), 900 phrases
# in one sentence ("They focused on the X to improve overall efficiency."). Only
# these rows are read:
V4_KEEP = {
    'Cümlede anlam': set(), 'Örnek cümleler': set(),
    'TR-EN kelimeler': set(range(2, 192)), 'EN-TR kelimeler': set(range(2, 192)),
    'Deyim ve kalıplar': set(range(902, 1002)),
}
# Word families: the made-up verb of a noun ("science: bilim yapmak", "nation: ulusallaşmak").
V4_DROP = {22, 46, 50, 54, 58, 62, 66, 70, 74, 78, 102, 106, 118, 126, 130, 134, 138, 142, 146, 154, 158}

# --- Fifth file, hamit_2026-11-20_v5.xlsx ("300 gerçek kayıt") ---------------------
V5_CTX_FIX = {
    41: (None, None, None, 'soğutmak, itici gelmek'),
}
V5_EX_FIX = {
    2: {'en': 'Tolerating different views is the basis of a healthy society.'},
    43: {'tr': 'Şirket, geciken teslimat için müşterilerin zararını telafi edecek.'},
}

# Sixth dictionary file (hamit_2026-11-20_v6.xlsx).
V6_CTX_FIX = {
    13: ('Yerdeki ağır koliyi tek başına kaldırmaya çalışırken belini incitti.', None, None, None),
}
V6_TR_SPLIT = {
    14: [('sıfat', 'abstaining, neutral (in a vote)', 'oy vermekten veya karar bildirmekten kaçınan')],
    39: [('isim', 'compassion', '')],
}
V6_EN_SPLIT = {
    51: [],  # mere ≠ önemsiz
}

V10_CTX_FIX = {
    8: ('Soğuk havada ince giyinince fena halde soğuk almış.', None, None, None),
    18: ('Yeni yapılan bina birkaç yıl içinde ancak oturur.', None, None, None),
    67: ('Both teams played defensively, and they eventually drew the match.', None, None, None),
}
V10_EX_FIX = {
    5: {'en': 'When the weather got cold, we let the dog in from the yard.'},
    8: {'tr': 'Soğuk havada ince giyinince fena halde soğuk almış.'},
    13: {'en': 'The taxes were automatically deducted from his account.'},
    18: {'tr': 'Yeni yapılan bina birkaç yıl içinde ancak oturur.'},
    27: {'en': 'Someone knocked on the door again and again at the crack of dawn.'},
    67: {'en': 'Both teams played defensively, and they eventually drew the match.'},
    89: {'en': 'We put you to a lot of trouble by having you carry such heavy packages.'},
}
V10_EN_SPLIT = {16: [('fiil', 'anlamına gelmek', 'ifade etmek')], 17: [('fiil', 'kastetmek, niyetlenmek', 'öyle demek istemek')],
                18: [('sıfat', 'cimri, kaba', 'kötü niyetli')], 19: [('isim', 'ortalama', 'matematiksel orta')],
                23: [('fiil', 'ücret talep etmek', 'fiyat istemek')], 24: [('fiil', 'hücum etmek', 'hızla üzerine gitmek')]}
V9_EX_FIX = {26: {'en': 'The board of directors promised they would act transparently in the hiring process.'}}
V8_EX_FIX = {51: {'tr': 'Romanın kapağı eski bir İstanbul fotoğrafıyla süslenmişti.'}}

# --- Dictionary v11 (hamit_2026-11-20_v11.xlsx) ----------------------------------
# One part of speech a row ("sıkı" adjective, "sıkı çalışmak" adverb); "idare"
# in "idare etmek" is the verb's meaning (make do, put up with); "soup up" is a
# phrasal verb, not a meaning of "soup"; a few translations made natural.
# Meanings the dictionary has in other words take its wording, so the example
# joins that sense: energy "enerji" / "güç, canlılık", forecast "tahmin", kaza
# "replacement of missed salah or fasting".
V11_KAZA = 'replacement of missed salah or fasting'
V11_MAKE_DO, V11_PUT_UP = 'to make do, to economize', 'to put up with, to tolerate'
V11_CTX_FIX = {
    8: ('Çocukluğumuzdan beri çok sıkı dostuz.', None, None, None),
    12: (None, None, None, V11_KAZA),
    14: (None, None, 'idare etmek', V11_MAKE_DO),
    42: (None, None, None, 'enerji'), 43: (None, None, None, 'güç, canlılık, dinçlik'),
    45: (None, None, None, 'tahmin, öngörü'),
    16: (None, None, 'idare etmek', V11_PUT_UP),
    32: ('Kahvaltıda yarım ekmek yedim.', None, None, None),
    44: (None, None, None, 'tahmin etmek, öngörmek'),
    46: (None, None, None, 'öngörü, tahmin (satış vb.)'),
    54: (None, None, None, 'güçlendirmek, modifiye etmek'),
    56: (None, None, None, 'klişe duygusallık, bayağılık'),
}
V11_EX_FIX = {
    5: {'en': 'He got out of going to school by pretending to be sick.'},
    8: {'tr': 'Çocukluğumuzdan beri çok sıkı dostuz.', 'en': 'We have been very close friends since childhood.'},
    12: {'en': 'He later made up the fasts he had missed because of his illness.', 'meaning': V11_KAZA},
    42: {'meaning': 'enerji'}, 43: {'meaning': 'güç, canlılık, dinçlik'}, 45: {'meaning': 'tahmin, öngörü'},
    14: {'word': 'idare etmek', 'meaning': V11_MAKE_DO, 'en': 'In hard times we have to economize a little on kitchen expenses.'},
    16: {'word': 'idare etmek', 'meaning': V11_PUT_UP},
    21: {'en': 'The force of the wind grew so much toward morning that roofs were blown off.'},
    29: {'en': 'The company took an important step toward eco-friendly production.'},
    32: {'tr': 'Kahvaltıda yarım ekmek yedim.', 'en': 'I ate half a loaf of bread at breakfast.'},
    44: {'meaning': 'tahmin etmek, öngörmek'},
    46: {'meaning': 'öngörü, tahmin (satış vb.)'},
    50: {'tr': 'Taşınırken kırılgan bardakları eski gazete kâğıdına sardık.'},
    54: None,
    56: {'meaning': 'klişe duygusallık, bayağılık'},
}
V11_TR_SPLIT = {6: [('sıfat', 'tight', 'bol olmayan')], 7: [('sıfat', 'strict, rigorous', 'esnemeyen kural')],
                8: [('sıfat', 'close, intimate', 'samimi ilişki')], 9: [('zarf', 'hard, intensely', 'büyük çabayla')],
                12: [('isim', V11_KAZA, '')], 14: [], 15: [('isim', 'oil lamp (idare lambası)', 'eski aydınlatma aracı')], 16: [],
                30: [('sıfat', 'absurd, ridiculous', 'akla yatkın olmayan')], 31: [('isim', 'buckshot, pellet', 'tüfek mermisi')],
                32: [('sıfat', 'half', 'bütünün yarısı')], 33: [('sıfat', 'incomplete, unfinished', 'bitmemiş olan')]}
V11_EN_SPLIT = {10: [('isim', 'enerji', '')], 11: [('isim', 'güç, canlılık, dinçlik', '')], 13: [('isim', 'tahmin, öngörü', '')],
                12: [('fiil', 'tahmin etmek, öngörmek', 'geleceği öngörmek')],
                14: [('isim', 'öngörü, tahmin (satış vb.)', 'ekonomik beklenti')], 15: [('sıfat', 'sarhoş', 'alkol etkisinde')],
                16: [('isim', 'ayyaş', 'sürekli alkol alan kişi')], 21: [('isim', 'çorba', 'sıvı yiyecek')], 22: [],
                24: [('isim', 'klişe duygusallık, bayağılık', 'sıfatı: cheesy')]}

# --- Dictionary v12 (hamit_2026-11-20_v12.xlsx) ----------------------------------
# v11 again with its fixes (already applied from v11) and new words: only the
# new words are read. Not taken: "al" as "hile" (old, and the sentence reads as
# the colour), "felt" as "hissetti" (a form of "feel", not a meaning of its own),
# "a determined time" (the word is "predetermined").
_NEW_ROWS = set(range(34, 56)) | {72, 73} | set(range(82, 106)) | set(range(107, 110))
V12_KEEP = {'Cümlede anlam': _NEW_ROWS - {93}, 'Örnek cümleler': _NEW_ROWS - {93},
            'TR-EN kelimeler': set(range(34, 56)), 'EN-TR kelimeler': {17, 18} | set(range(27, 51)) - {38} | {52, 53, 54},
            'Deyim ve kalıplar': set(range(2, 32))}
V12_EXTREME, V12_INITIAL = 'extreme, radical (views)', 'initial, early'
V12_MODERN, V12_INCIDENT = 'son teknoloji, yeni', 'olay, çatışma (sınırda, ülkeler arasında)'
V12_CTX_FIX = {37: (None, None, None, V12_EXTREME), 52: (None, None, None, V12_INITIAL),
               91: (None, None, None, V12_MODERN), 97: (None, None, None, V12_INCIDENT)}
V12_EX_FIX = {
    37: {'meaning': V12_EXTREME, 'en': 'His extreme views sometimes push people away from him.'},
    38: {'en': "Mr Ahmet is the company's longest-serving and most experienced manager."},
    39: {'en': 'My husband is going to be a little late from work today, apparently.'},
    52: {'meaning': V12_INITIAL},
    87: {'tr': 'Eli kazanmak için kupa dokuzluğunu yere koydu.'},
    91: {'meaning': V12_MODERN}, 97: {'meaning': V12_INCIDENT},
}
V12_TR_SPLIT = {37: [('sıfat', V12_EXTREME, 'düşüncede ileri giden')], 52: [('sıfat', V12_INITIAL, 'en başta olan')]}
V12_EN_SPLIT = {36: [('sıfat', V12_MODERN, 'gelişmiş donanımlı')], 42: [('isim', V12_INCIDENT, 'ciddi sorun')],
                48: [('ünlem', 'günaydın', 'selamlama (kısa)')]}
V12_PH_FIX = {8: {'ex_tr': 'Reading and translating these old manuscripts one by one is painstakingly slow work.'}}

# --- Dictionary v13 (hamit_2026-11-20_v13.xlsx) ----------------------------------
# v12's words again in other sentences (left out: they would be the same meaning
# twice) and new words: en, öyle, ise, ilk/aşırı as adverbs, yüce, güney, hizmet,
# çavuş, don, piç; suffering, dollar, religious, explosion, lion; one idiom.
_V13_ROWS = {4, 5, 6, 7, 8, 11, 12, 13, 21} | set(range(30, 44))
V13_KEEP = {'Cümlede anlam': _V13_ROWS | set(range(72, 81)), 'Örnek cümleler': _V13_ROWS | set(range(72, 81)),
            'TR-EN kelimeler': _V13_ROWS, 'EN-TR kelimeler': set(range(30, 39)), 'Deyim ve kalıplar': {2}}
V13_PIC_RASCAL, V13_PIC_SPROUT, V13_LION = 'bastard (an objectionable person)', 'a sprout that appears near the main plant', 'sosyete yıldızı, ilgi odağı'
V13_EX_FIX = {
    6: {'en': "If you look at me like that, I can't tell what you mean."},
    13: {'en': "If you ask me, I'd accept; as for the manager, I don't know."},
    39: {'en': "While packing his suitcase, he didn't forget a few pairs of clean underpants."},
    73: {'tr': "New York'a uçmadan önce bütün eurolarını ABD dolarına çevirdi."},
    42: {'meaning': V13_PIC_RASCAL}, 43: {'meaning': V13_PIC_SPROUT}, 80: {'meaning': V13_LION,
         'tr': 'Ünlü bir yazar olarak başkentte edebiyat dünyasının gözdesi gibi ağırlandı.'},
}
# Senses the dictionary has in other words take its wording (piç, lion).
V13_TR_SPLIT = {41: [('isim', 'bastard, illegitimate child', 'kaba')], 42: [('isim', V13_PIC_RASCAL, '')],
                43: [('isim', V13_PIC_SPROUT, '')]}
V13_EN_SPLIT = {38: [('isim', V13_LION, '')]}

# --- Dictionary v14 (hamit_2026-11-20_v14.xlsx) ----------------------------------
# Earlier words again (left out) and new ones. "şanı" is "şan" (fame), not "san"
# (title); "onca" as "ona göre" is old and its sentence is not Turkish.
_V14_ROWS = (set(range(16, 32)) - {23}) | {33, 35, 41} | set(range(44, 58))
V14_KEEP = {'Cümlede anlam': _V14_ROWS, 'Örnek cümleler': _V14_ROWS, 'TR-EN kelimeler': set(range(16, 32)) - {20, 23},
            'EN-TR kelimeler': {5, 11} | set(range(14, 28)), 'Deyim ve kalıplar': {2, 3, 4, 5, 6, 8}}
V14_CTX_FIX = {20: (None, None, 'şan', 'fame, glory')}
V14_EX_FIX = {
    16: {'en': 'We were walking calmly along the road when, all of a sudden, heavy rain started.'},
    20: {'word': 'şan', 'meaning': 'fame, glory'},
    24: {'en': 'Every evening the sun sets slowly behind the mountains on the western horizon.'},
    35: {'tr': 'İşlerinin kalitesine odaklanmak yerine paranın peşinden koşuyorlar.'},
}
V14_TR_SPLIT = {22: [('sıfat', 'so much, all that', 'miktarın fazlalığı')]}
V14_PH_FIX = {4: {'ex_tr': "I've finally had enough of the neighbour's endless construction noise."}}

# --- Dictionary v15 (hamit_2026-11-20_v15.xlsx) ----------------------------------
# New words only this time. Left out: "milyar" as "tons of" ("daha milyar tane
# hata" is not said); blind "farksız" is not a meaning of it.
V15_BLIND = 'körü körüne, sorgusuz'
# Meanings the dictionary has in other words take its wording, so each example
# goes under the sense it shows (pool "havuz" is "yüzme havuzu", not "ortak havuz").
V15_SAME = {34: (7, 'yüzme havuzu'), 35: (8, 'gölcük, birikinti'), 36: (9, 'ortak havuz, kaynak'),
            40: (13, 'lif, doku yönü'), 43: (16, 'mantık (bilim dalı), mantık bilimi'), 44: (17, 'mantıklı gerekçe, akla yatkınlık'),
            46: (19, 'sipariş üzerine yapılmış, özel'), 51: (24, 'yer almak, sayılmak')}
V15_EX_FIX = {
    4: {'en': 'He has been living like a lord for years on the money his father left him.'},
    8: None,
    10: {'en': 'He is a true man of his word; he always stands by what he says.'},
    17: {'en': 'In winter the days are very short in northern countries.'},
    55: {'meaning': V15_BLIND},
    **{i: {'meaning': m} for i, (_, m) in V15_SAME.items()},
}

# --- Dictionary v16 (hamit_2026-11-20_v16.xlsx) ----------------------------------
# All new. "aşağılık" in row 5 is the adjective (inferior), not "inferiority";
# "geçer" in row 19 is "in use", not "popular"; "rezil" is not "crappy".
# Meanings the dictionary already has take its wording; "tahliye" and "alay" are nouns.
V16_MEANING = {5: 'Less of worth, lower of value.', 7: 'just, first', 13: 'evacuation', 14: 'setting (a prisoner) free',
               19: 'current, in use', 23: 'awful, disgraceful'}
V16_EX_FIX = {
    5: {'meaning': V16_MEANING[5], 'en': 'In the past, this social class was regarded as inferior.'},
    6: {'en': 'I love sweets, especially chocolate cake.'},
    7: {'meaning': V16_MEANING[7]},
    13: {'meaning': V16_MEANING[13], 'pos': 'noun'},
    14: {'meaning': V16_MEANING[14]},
    26: {'pos': 'noun'},
    10: {'en': 'The old castle on the hill dominated the whole plain.'},
    15: {'en': "Our little one doesn't want to go to kindergarten today."},
    19: {'meaning': V16_MEANING[19], 'en': 'This old payment method is not really in use in the market anymore.'},
    23: {'meaning': V16_MEANING[23], 'en': 'I had never stayed in such an awful hotel in my life before.'},
    34: {'tr': 'Dondurucu kuzey rüzgârları bu bölgeye soğuk hava getirir.'},
}
V16_PH_FIX = {6: {'ex_tr': 'Your mother waited anxiously for you to come home.'}}

# --- Dictionary v17 (hamit_2026-11-20_v17.xlsx, sent as "v15") -------------------
# "evvel" in "-madan evvel" is "before" (a postposition); "abla" for a woman one
# does not know takes the wording the dictionary has. The other meanings are the
# dictionary's own ones that had no example yet.
V17_MEANING = {7: 'before', 9: 'term of address for a woman, younger than teyze (“auntie”)'}
V17_EX_FIX = {
    5: {'en': 'Knowing two foreign languages was a big plus in her job application.'},
    6: {'en': 'The engineers measured the elevation of the land before starting construction.'},
    9: {'en': 'The woman who ran the neighbourhood grocery used to hand out sweets to the children every morning.'},
    11: {'en': 'The doctor said the ultrasound showed some small stones in his kidneys.'},
    18: {'tr': 'Halıdaki o çıkmak bilmeyen lekeyi temizlemek için güçlü bir kimyasal temizleyici kullandı.'},
    20: {'tr': 'Dürüstlüğüne kesinlikle kefil olabilirim; onu on yıldır tanıyorum.'},
    7: {'pos': 'postp'},
    28: {'tr': 'Her hafta bozulduğu için o güvenilmez eski arabayı satmak zorunda kaldılar.'},
}
for _i, _m in V17_MEANING.items():
    V17_EX_FIX.setdefault(_i, {})['meaning'] = _m
V17_PH_FIX = {
    13: {'ex_tr': 'Piyasadaki son eğilimlerle ilgili derin analiziniz gerçekten tam isabet oldu.'},
    15: {'ex': "I'm keeping my fingers crossed that the weather stays clear tomorrow.",
         'ex_tr': 'Yarın havanın açık kalmasını umuyorum, şans dileyelim.'},
}

# --- Dictionary v18 (hamit_2026-11-20_v18.xlsx, sent as "v16") -------------------
# Examples for meanings the dictionary has; word-for-word English rewritten
# ("in the youth of his life", "spun the wet clay wheel", "a poem related to
# rotation"). "hold the fort", "harp on" and "feet of clay" also go to the phrase.
V18_EX_FIX = {
    4: {'en': 'That young athlete achieved great success while still in the springtime of his life.'},
    5: {'en': 'The climbers got all their safety equipment ready to climb a steep rock face.'},
    7: {'en': 'The TV channel showed the big final match that evening as a live broadcast.'},
    12: {'en': 'The gardener took a small cutting from the stem to propagate his favourite geranium.'},
    16: {'en': "This transaction, made under power of attorney, cannot be used without the principal's approval."},
    17: {'en': 'Early in the morning the old hunter walked towards the forest with his trusty double-barrelled shotgun over his shoulder.'},
    18: {'en': 'The restless horse suddenly kicked out with both hind legs at the man standing behind it.'},
    19: {'en': 'Thanks to this year\'s profits, the company made it a double celebration for all its employees.'},
    23: {'en': 'Police teams patrolled the quiet neighbourhood all night to keep it safe.'},
    24: {'en': "In literature class we read a devriye, a Bektashi poem about the soul's cycle of creation."},
    30: {'en': 'The tailor put a little starch on the fabric so that the collars and cuffs of the shirts would stay stiff.'},
    34: {'en': "I'll hold the fort here at the office while you go out for a quick lunch.", 'tr': 'Sen hızlıca öğle yemeğine çıkarken ben burada ofiste işlere bakarım.'},
    36: {'tr': 'Efsanevi korsan hazinesi ıssız adanın öbür ucuna gizlice gömülmüştü.'},
    38: {'en': 'He suffered terrible back pain last year because of a slipped disc.', 'tr': 'Geçen yıl kayan bir omurga diski yüzünden korkunç sırt ağrıları çekti.'},
    40: {'tr': 'Yerli halk, kurak çöldeki uzun kaktüslerden tatlı hint inciri topladı.'},
    44: {'en': 'The spring weather here is very moody; it can pour with rain and then suddenly turn sunny on the same day.'},
    50: {'en': 'The company used a cash bonus as a carrot to motivate the struggling sales team.',
         'tr': 'Şirket, zorlanan satış ekibini motive etmek için nakit primi bir ödül vaadi olarak kullandı.'},
    58: {'tr': 'Karizmatik başrol oyuncusunun bütün tiyatro seyircisini anında büyüleyen çekici bir kişiliği var.'},
    61: {'en': 'The skilled potter carefully shaped a delicate ceramic bowl on his wheel.',
         'tr': 'Yetenekli çömlekçi, çarkında zarif bir seramik kâseyi özenle şekillendirdi.'},
}
V18_CTX_FIX = {i: (f['en'], None, None, None) for i, f in V18_EX_FIX.items() if 'en' in f and i >= 31}
V18_PH_FIX = {
    2: {'ex_tr': 'I guessed the answers to those last three very hard questions on the exam completely at random.'},
    4: {'ex_tr': 'The weather was lovely today, so we seized the chance and went straight to the sea.'},
    7: {'ex': 'Gençliğinde yaptığı bu büyük hata bütün hayatı boyunca kulağına küpe oldu.'},
    11: {'ex_tr': 'Sadece yardım sözü verme; unutma, ayinesi iştir kişinin lafa bakılmaz.'},
    12: {'ex': "She had to burn the midnight oil to finish her master's thesis on time.",
         'ex_tr': 'Yüksek lisans tezini zamanında bitirmek için gece geç saatlere kadar çalışmak zorunda kaldı.'},
    15: {'ex': 'Our customer support team always goes the extra mile to help users.',
         'ex_tr': 'Müşteri destek ekibimiz kullanıcılara yardım etmek için her zaman fazladan çaba gösterir.'},
    16: {'phrase': "steal one's thunder", 'ex': 'She announced her engagement at my birthday party and completely stole my thunder.',
         'ex_tr': 'Doğum günü partimde nişanlandığını duyurdu ve beni tamamen gölgede bıraktı.'},
    17: {'ex': 'He often exaggerates, so when he tells you a story, take it with a grain of salt.',
         'ex_tr': 'Sık sık abartır; sana bir hikâye anlattığında ona ihtiyatla yaklaş.'},
}

# --- Dictionary v19 (hamit_2026-11-20_v19.xlsx) ----------------------------------
# Rows 24-43 (sacred ... toe) and the second copies of rows 44-55 and of the
# idioms are earlier rows again, and the word sheets hold the template's sample
# rows: all left out. English made idiomatic ("so harmonic", "works perfectly
# compatible", "hurt his waist").
V19_KEEP = {'Cümlede anlam': set(range(2, 24)) | set(range(44, 64)), 'Örnek cümleler': set(range(2, 24)) | set(range(44, 56)),
            'TR-EN kelimeler': set(), 'EN-TR kelimeler': set(), 'Deyim ve kalıplar': set(range(2, 32)) | set(range(43, 49))}
V19_CTX_FIX = {18: ('Sıcakta unutulan sütün kesik olduğunu kokusundan anladı.', 'kesik', None, None)}
V19_EX_FIX = {
    2: {'en': 'The enemy unit entered the city in a sudden attack early in the morning.'},
    4: {'en': 'Thanks to that one clever move, he won the chess game.'},
    5: {'en': 'The voices of the singers in the choir are in such harmony that it is wonderful to listen to them.'},
    6: {'en': "This new software is fully compatible with my old computer's operating system."},
    7: {'en': 'Our new colleague fits in very well with the team and never causes any problems.'},
    13: {'en': 'The company got very good returns from the investments it made this year.'},
    14: {'en': 'In the harshest months of winter, the temperature here usually stays below zero.'},
    16: {'en': "When he couldn't find the original photos, he looked for their negatives to make new prints."},
    17: {'en': "On the way to the hospital, the patient's breathing had become short and broken."},
    18: {'tr': 'Sıcakta unutulan sütün kesik olduğunu kokusundan anladı.',
         'en': 'She could tell from the smell that the milk left in the heat had curdled.'},
    19: {'en': "He has been crazy about the neighbourhood baker's daughter for months; he can't take his eyes off her."},
    22: {'en': 'He badly hurt his lower back lifting the heavy box the wrong way.'},
    44: {'en': 'During the military exercise, a new-generation missile was fired towards the sea.'},
    55: {'en': 'This spicy dish is a flavour found only in our region.'},
}
V19_EDITS = {
    # "one can" stands for any subject ("she could"); "pull someone's leg" is
    # "pull one's leg", which is there.
    'bite off more than one can chew': {'action': 'rename', 'to': 'bite off more than sb can chew'},
    "pull someone's leg": {'action': 'merge', 'to': "pull one's leg"},
    'bite off more than you can chew': {'action': 'merge', 'to': 'bite off more than sb can chew'},
}
V19_PH_FIX = {
    5: {'ex_tr': 'The editor checked every tiny detail of the book before publication to avoid any mistakes.'},
    8: {'ex': 'When he saw the huge scratch on his new car, he hit the roof.'},
    13: {'ex_tr': "I'm really fed up with this never-ending construction noise."},
    17: {'ex_tr': 'Arguing at the table for hours without finding a solution is just a waste of breath.'},
    22: {'ex': 'Yeni komşunun kızını görür görmez abayı yaktı.'},
    25: {'ex_tr': "The two siblings didn't speak to each other for days over a trivial matter."},
    30: {'ex': "By taking on three complex projects at once, she has bitten off more than she can chew.",
         'ex_tr': 'Aynı anda üç karmaşık proje alarak boyundan büyük bir işe kalkıştı.'},
    31: {'ex': "We've been working for ten hours straight; let's call it a day.", 'ex_tr': 'On saattir aralıksız çalışıyoruz; hadi paydos edelim.'},
    47: {'ex_tr': 'Kesin rakamları şu an ezbere söyleyemem.'},
}

# --- Dictionary v20 (hamit_2026-11-20_v20.xlsx, sent as "v22") -------------------
# Examples for the last Turkish meanings that had none. Word-for-word English
# rewritten ("engaged in honoring them", "the apoplexy illness", "made a small
# discount for"). The "v23" file sent with it holds the same rows again (and
# the template's sample rows), so it is not read.
V20_EX_FIX = {
    6: {'en': "He wasn't so foolish as not to realize that people only liked him for his money."},
    8: {'en': 'The French Revolution spread the ideas of equality and freedom all over the world.'},
    10: {'en': 'The engineers started safety checks at the construction site early in the morning.'},
    13: {'en': 'On a stormy night, the captain was steering his ship safely across the vast ocean.'},
    14: {'en': 'Okyanus is the most hardworking student in the class and loves painting more than anyone.'},
    15: {'en': 'The market seller adjusted the scales and weighed out exactly one batman of wheat.'},
    17: {'en': 'Early in the morning, the dewdrops on the leaves were glittering in the sun.'},
    18: {'en': 'After that huge argument, only a drop of hope was left in her.'},
    19: {'en': 'The old man can no longer walk because of the stroke he had last year.'},
    20: {'en': 'After dinner, the host offered the guests some of his homemade dessert.'},
    21: {'en': 'While we were shopping at the market, the seller gave the local customers a small discount.'},
    22: {'en': 'The villagers welcomed the strangers warmly and treated them as honoured guests in the best room.'},
    23: {'en': 'The child pulled from the rubble was still alive despite going without water for days.'},
    26: {'en': 'In his latest essay, the author wrote in very pure, clear Turkish.'},
    29: {'en': 'He had dreamed of sailing around the world since he was a child.'},
}
V20_PH_FIX = {
    2: {'ex': 'Borcu yüzünden eski patronundan köşe bucak kaçıyor.', 'ex_tr': 'Because of his debt, he avoids his old boss at all costs.'},
    4: {'ex_tr': 'The angry crowd broke through the barricades and poured into the square as if it had broken loose.'},
    5: {'ex_tr': 'Defending their homeland at the front, the soldiers fought for days, putting their lives on the line.'},
    18: {'ex': "I'm exhausted after a twelve-hour shift, so I'm going to hit the sack.",
         'ex_tr': 'On iki saatlik mesainin ardından bitkinim, bu yüzden yatmaya gidiyorum.'},
}

FIXES = {
    'hamit_2026-11-20_v20.xlsx': dict(ctx_fix={}, ctx_to_phrase=set(), ctx_tr={}, ctx_add=[],
                                      en_split={}, tr_split={}, ex_fix=V20_EX_FIX, ph_fix=V20_PH_FIX),
    'hamit_2026-11-20_v19.xlsx': dict(ctx_fix=V19_CTX_FIX, ctx_to_phrase=set(), ctx_tr={}, ctx_add=[],
                                      en_split={}, tr_split={}, ex_fix=V19_EX_FIX, ph_fix=V19_PH_FIX),
    'hamit_2026-11-20_v18.xlsx': dict(ctx_fix=V18_CTX_FIX, ctx_to_phrase=set(), ctx_add=[],
                                      ctx_phrase={34: 'hold the fort', 46: 'harp on', 56: 'feet of clay'},
                                      ctx_tr={34: V18_EX_FIX[34]['tr'],
                                              46: 'Katı patronum geçen hafta yaptığım küçük bir yazım hatasının üzerinde durmaya devam ediyor.',
                                              56: 'En büyük tarihi kahramanların bile çoğu zaman gizli zaafları vardır ve korkunç kişisel hatalar yaparlar.'},
                                      en_split={}, tr_split={}, ex_fix=V18_EX_FIX, ph_fix=V18_PH_FIX),
    'hamit_2026-11-20_v17.xlsx': dict(ctx_fix={i: (None, None, None, m) for i, m in V17_MEANING.items()},
                                      ctx_to_phrase=set(), ctx_add=[], ctx_tr={},
                                      en_split={}, tr_split={}, ex_fix=V17_EX_FIX, ph_fix=V17_PH_FIX),
    'hamit_2026-11-20_v16.xlsx': dict(ctx_fix={i: (None, None, None, m) for i, m in V16_MEANING.items()}, ctx_to_phrase=set(), ctx_tr={}, ctx_add=[],
                                      en_split={}, tr_split={}, ex_fix=V16_EX_FIX, ph_fix=V16_PH_FIX),
    'hamit_2026-11-20_v15.xlsx': dict(ctx_fix={55: (None, None, None, V15_BLIND), **{i: (None, None, None, m) for i, (_, m) in V15_SAME.items()}}, ctx_to_phrase=set(), ctx_tr={}, ctx_add=[],
                                      ctx_drop={8}, en_split={28: [('sıfat', V15_BLIND, 'sorgulamayan')],
                                                **{r: [('fiil' if r == 24 else 'sıfat' if r == 19 else 'isim', m, '')] for r, m in V15_SAME.values()}}, tr_split={8: []},
                                      ex_fix=V15_EX_FIX, ph_fix={}),
    'hamit_2026-11-20_v14.xlsx': dict(ctx_fix=V14_CTX_FIX, ctx_to_phrase=set(), ctx_tr={}, ctx_add=[],
                                      en_split={}, tr_split=V14_TR_SPLIT, ex_fix=V14_EX_FIX, ph_fix=V14_PH_FIX),
    'hamit_2026-11-20_v13.xlsx': dict(ctx_fix={42: (None, None, None, V13_PIC_RASCAL), 43: (None, None, None, V13_PIC_SPROUT),
                                               80: (None, None, None, V13_LION)}, ctx_to_phrase=set(), ctx_tr={}, ctx_add=[],
                                      en_split=V13_EN_SPLIT, tr_split=V13_TR_SPLIT, ex_fix=V13_EX_FIX, ph_fix={}),
    'hamit_2026-11-20_v12.xlsx': dict(ctx_fix=V12_CTX_FIX, ctx_to_phrase=set(), ctx_tr={}, ctx_add=[],
                                      en_split=V12_EN_SPLIT, tr_split=V12_TR_SPLIT, ex_fix=V12_EX_FIX, ph_fix=V12_PH_FIX),
    'hamit_2026-11-20_v11.xlsx': dict(ctx_fix=V11_CTX_FIX, ctx_to_phrase=set(), ctx_add=[], ctx_phrase={54: 'soup up'},
                                      ctx_tr={54: 'Hafta sonları yarışmak için eski arabasını güçlendirmeye karar verdi.'},
                                      en_split=V11_EN_SPLIT, tr_split=V11_TR_SPLIT, ex_fix=V11_EX_FIX, ph_fix={}),
    'hamit_2026-11-20_v10.xlsx': dict(ctx_fix=V10_CTX_FIX, ctx_to_phrase=set(), ctx_tr={}, ctx_add=[],
                                      en_split=V10_EN_SPLIT, tr_split={}, ex_fix=V10_EX_FIX, ph_fix={}),
    'hamit_2026-11-20_v9.xlsx': dict(ctx_fix={}, ctx_to_phrase=set(), ctx_tr={}, ctx_add=[],
                                     en_split={}, tr_split={}, ex_fix=V9_EX_FIX, ph_fix={}),
    'hamit_2026-11-20_v8.xlsx': dict(ctx_fix={}, ctx_to_phrase=set(), ctx_tr={}, ctx_add=[],
                                     en_split={}, tr_split={}, ex_fix=V8_EX_FIX, ph_fix={}),
    'hamit_2026-11-20.xlsx': dict(ctx_fix=CTX_FIX, ctx_to_phrase=CTX_TO_PHRASE, ctx_tr=CTX_TR, ctx_add=[],
                                  en_split=EN_SPLIT, tr_split=TR_SPLIT, ex_fix={i: {'en': e} for i, e in EX_EN_FIX.items()},
                                  ph_fix=PH_FIX),
    'hamit_2026-11-20_v2.xlsx': dict(ctx_fix=V2_CTX_FIX, ctx_to_phrase=set(), ctx_tr={}, ctx_add=V2_CTX_ADD,
                                     en_split=V2_EN_SPLIT, tr_split=V2_TR_SPLIT, ex_fix=V2_EX_FIX, ph_fix=V2_PH_FIX),
    'hamit_2026-11-20_v5.xlsx': dict(ctx_fix=V5_CTX_FIX, ctx_to_phrase=set(), ctx_tr={}, ctx_add=[],
                                     en_split={}, tr_split={}, ex_fix=V5_EX_FIX, ph_fix={}),
    'hamit_2026-11-20_v6.xlsx': dict(ctx_fix=V6_CTX_FIX, ctx_to_phrase=set(), ctx_tr={}, ctx_add=[],
                                     en_split=V6_EN_SPLIT, tr_split=V6_TR_SPLIT, ex_fix={}, ph_fix={}),
    'hamit_2026-11-20_v3.xlsx': dict(ctx_fix=V3_CTX_FIX, ctx_to_phrase=set(), ctx_tr={}, ctx_add=[], ctx_phrase=V3_CTX_PHRASE,
                                     en_split={}, tr_split={}, ex_fix=V3_EX_FIX, ph_fix={}),
}
# Numbered stand-in rows: word_5, phrase_499, form499, "TR sent 5 for s4.", "New EN contextual sentence 3."
PLACEHOLDER = re.compile(r'_\d+\b|\b(?:form|fiil|verb|base|meaning|word|phrase|desc)\d+\b|\bsent \d+|contextual sentence \d+'
                         r'|TR cümle \d+|\bEx (?:tr|en) \d+|\bmeaning \d+')

# --- Filter sheets (filtre-kalip-sablonu.xlsx): one phrase a row with its filter
# Row -> the columns that change; None drops the row.
F1_FIX = {
    7: {'ex_tr': 'Eskiden çok sigara içerdi.'},
    8: {'ex_tr': 'Eskiden çok içki içerdi.'},
    52: {'ex': 'He is a close friend of mine.', 'ex_tr': 'O benim yakın arkadaşım.'},
    54: {'meaning': 'büyük dikkat, dikkatle'},
    58: {'ex': 'She is a close relative of ours.', 'ex_tr': 'O bizim yakın akrabamız.'},
    66: {'ex': 'She is a bright student.', 'ex_tr': 'Zeki bir öğrenci.'},
    70: {'ex': 'He is a bright child.', 'ex_tr': 'Zeki bir çocuk.'},
    91: {'meaning': 'geniş kitlelere hitap etme'},
    140: {'meaning': 'göz gözü görmez, çok kötü gören'},
    165: None,  # beat: too many other meanings to mark every "beat"
    166: None,  # catch up: a phrasal verb, already in that filter
    201: {'meaning': 'almak (gidip), teslim almak'},
    204: {'meaning': 'tükenmek, bitmek'},
}
# "a / b" rows: halves that are left out, because the word has other common meanings.
F1_SKIP_HALF = {'lift', 'flat', 'gas', 'line', 'fall', 'do', 'schedule'}
# Filter sheets 4-6: "your" in an idiom is any possessive ("keep one's chin up");
# a phrase given twice keeps one row; "once" alone is mostly "bir kez".
F4_FIX = {24: {'phrases': ['what is more', "what's more"]}}
F5_FIX = {2: {'phrase': "keep one's chin up"}, 3: {'phrase': "wrap one's head around"}, 4: None,
          7: {'phrase': "get a taste of one's own medicine"}, 12: {'phrase': "put all one's eggs in one basket"},
          16: {'phrase': "worth one's weight in gold"}}
# Sheets 7-10: words that mean something else in most texts (till, chips, marks, take,
# first floor) are left out; "someone's" is a possessive.
F7_FIX = {61: {'meaning': 'sözünü tutmamak, sözünden dönmek', 'ex_tr': 'Çocuklarına verdiği sözü asla bozmaz.'},
          80: {'phrase': "catch one's attention"}, 225: None, 226: None, 228: None, 232: None, 237: None,
          248: None, 250: None, 273: None}
F8_FIX = {153: None, 154: None, 158: None,
          194: {'meaning': 'ahlaki; kıssadan hisse (≠ Türkçe moral: morale)'}}
F9_FIX = {31: None, 62: None, 64: None, 65: None}
F10_FIX = {134: {'cat': 'informal_slang'}, 135: {'cat': 'informal_slang'}}
F11_FIX = {15: {'phrase': "lose one's way"}}
F12_FIX = {160: None, 162: None, 163: None}  # verb + any adverb, not a fixed pair
F6_FIX = {52: {'meaning': 'olursa ve olduğunda; gerçekleşirse'}, 62: None, 136: None, 138: None}
# Second filter sheet (hamit_filtre2_2026-11-20.xlsx).
# False friends: the meaning in the form the filter shows, "meaning (≠ the look-alike)".
F2_FIX = {
    240: {'meaning': 'aslında (≠ aktüel/güncel)'},
    241: {'meaning': 'sonunda, eninde sonunda (≠ eventüel/muhtemel)'},
    242: None,  # currently: not a false friend
    243: {'meaning': 'farkına varmak, anlamak (≠ realize etmek: gerçekleştirmek, daha az)'},
    244: None,  # "actually existing" is not a phrase
    245: {'meaning': 'mantıklı, akıllıca (≠ hassas: sensitive)'},
    246: {'meaning': 'hassas, duyarlı (≠ mantıklı: sensible)'},
    247: {'meaning': 'anlayışlı, hâlden anlayan (≠ sempatik: nice)'},
    248: None,  # comprehensive: not a false friend
    249: {'meaning': 'orkestra şefi; iletken (≠ kondüktör: biletçi, daha az)'},
    250: {'meaning': 'dergi (≠ mağaza: shop)'},
    251: {'meaning': 'kumaş (≠ fabrika: factory)'},
    252: None,  # factory: the Turkish word means the same
    253: {'meaning': 'aşçıbaşı (≠ iş yerindeki şef: boss)'},
    254: {'meaning': 'müşteri, destekçi (≠ patron: boss)'},
    255: {'meaning': 'ders, konferans (≠ lektür: okuma)'},
    256: {'meaning': 'yüksekokul, üniversite (≠ kolej: özel lise)'},
    257: {'meaning': 'İngiltere\'de paralı özel okul, ABD\'de devlet okulu'},
    258: None,  # ordinary: not a false friend
    259: {'meaning': 'tartışma, ağız kavgası; sav (≠ yalnızca argüman)'},
    260: None,  # application: the Turkish word means the same
    261: {'meaning': 'gündem (≠ ajanda: diary, planner)'},
    262: {'meaning': 'özet (makale); soyut (≠ yalnızca abstre)'},
    263: {'meaning': 'roman; yeni, alışılmamış (sıfat)'},
    264: {'meaning': 'devam etmek, yeniden başlamak (≠ résumé: özgeçmiş)'},
    280: None,  # look up: "(sözlükte) bakmak" is already its meaning
}
# Sentences made from one pattern for every row say nothing about the phrase.
F1_TEMPLATE = ('They discussed ', 'The report highlighted the importance of ')
F1_PHRASE = {"i am afraid ...": ["i am afraid", "i'm afraid"], 'may i ...?': ['may i'],
             'i would appreciate it if ...': ['i would appreciate it if']}



# --- Audit sheet 14 (hamit_denetim14_2026-11-20.xlsx) --------------------------
# Examples: "buy to let" is used before a noun ("a buy-to-let flat").
# The others are written so that the phrase is found in them: "does not look",
# "she is used to", "played for love".
D14_EX_FIX = {
    22: {'ex': 'We decided to buy to let, so the flat now pays for itself.',
         'ex_tr': 'Kiraya vermek için ev almaya karar verdik, daire artık kendi masrafını çıkarıyor.'},
    23: {'ex': 'At eighty, she does not look a day over sixty.'},
    33: {'ex': 'She is used to getting up before sunrise.', 'ex_tr': 'Güneş doğmadan kalkmaya alışkın.'},
    57: {'ex': 'We played for love, with no money at stake.', 'ex_tr': 'Ortada para olmadan, sadece eğlencesine oynadık.'},
}
# Meanings and removals, checked one by one. Kept: "from can see to can't see"
# (a real, old American saying: from dawn to dusk), "I want doesn't get" (a
# British saying to children), "be used to" (its two senses are already
# separate), "time of old" ("times of old" is matched through "time").
D14_EDITS = {
    'have a go at it': {'action': 'meaning', 'meaning': 'denemek, bir şeyi yapmaya girişmek'},
    'for love or money': {'action': 'meaning', 'meaning': 'hiçbir şekilde, ne yapsan (olumsuz cümlede)'},
    "i'm not the one": {'action': 'meaning', 'meaning': 'o kişi ben değilim; (argo) benimle uğraşma'},
    # Matched in ordinary sentences with another meaning: "looked at the money",
    # "well out of reach"; or not an English phrase ("on seen", "read the car",
    # "for the love of me" is "for the life of me").
    'at the money': {'action': 'delete'},
    'well out': {'action': 'delete'},
    'on seen': {'action': 'delete'},
    'read the car': {'action': 'delete'},
    'for the love of me': {'action': 'delete'},
    'go in the out door': {'action': 'delete'},
    'party up': {'action': 'delete'},
}

# --- Audit sheet 15 -------------------------------------------------------------
# Examples rewritten so that they read naturally and the phrase is found in them;
# none for a phrase removed below, or one whose heading is not the usual form
# ("while one is about it", "on the ready": "at the ready").
D15_EX_FIX = {
    9: {'phrase': 'get the best of'},
    10: {'phrase': 'have the best of'},
    11: {'phrase': 'at the best of times'},
    16: {'ex': 'There is enough to go around, so nobody needs to skip dinner.',
         'ex_tr': 'Herkese yetecek kadar var, kimsenin akşam yemeğini atlamasına gerek yok.'},
    25: None, 47: None,
    44: {'ex': "It's early days, so we cannot judge the results yet."},
    27: {'ex': '"Do you remember your first day at school?" "I remember like it was yesterday."',
         'ex_tr': '"Okuldaki ilk gününü hatırlıyor musun?" "Dün gibi hatırlıyorum."'},
    29: None, 30: None, 31: None, 32: None, 33: None, 34: None,
    55: {'phrase': 'put someone in mind of'},
    74: None,
    79: {'ex': 'We promised to show our visitors a good time in Istanbul.',
         'ex_tr': "İstanbul'da misafirlerimize güzel vakit geçirteceğimize söz verdik."},
    86: {'phrase': 'give sb the once over', 'ex': 'The guard gave the visitor the once over before opening the gate.'},
}
D15_EDITS = {
    # Without "of" they are found in "get the best price", "at the best hotel".
    'get the best': {'action': 'rename', 'to': 'get the best of'},
    'have the best': {'action': 'rename', 'to': 'have the best of'},
    'give the once over': {'action': 'rename', 'to': 'give sb the once over'},
    'at the best': {'action': 'delete'},  # "at best" and "at the best of times" are there
    'put in mind': {'action': 'delete'},  # "put someone in mind of" is there
    'show someone a good time': {'action': 'meaning', 'meaning': 'birine güzel vakit geçirtmek, eğlendirmek; (argo) cinsel ilişkiye girmek'},
    'meet up with': {'action': 'meaning', 'meaning': 'buluşmak, bir araya gelmek'},
    'there must be something in the water': {'action': 'meaning', 'meaning': '(şaka) herkeste aynı şey oluyor, suda bir şey var herhalde'},
    # Ordinary grammar, found everywhere with no meaning of its own.
    'at that place': {'action': 'delete'}, 'for each one': {'action': 'delete'},
    'for each person': {'action': 'delete'}, 'from each one': {'action': 'delete'},
    'of each person': {'action': 'delete'}, 'to each one': {'action': 'delete'},
    # "I'll tell you the truth": "to tell you the truth" is the phrase.
    'tell you the truth': {'action': 'delete'},
}
# --- Audit sheet 16 -------------------------------------------------------------
# "their" in a heading is any possessive ("gave the director his flowers").
D16_EX_FIX = {
    71: {'ex': 'He likes to order everyone about in the office.', 'ex_tr': 'Ofiste herkese emir yağdırmayı sever.'},
    89: {'phrase': "give someone one's flowers", 'ex': 'We should give our teachers their flowers while they are still with us.',
         'ex_tr': 'Öğretmenlerimizin hakkını, onlar hâlâ aramızdayken teslim etmeliyiz.'},
}
D16_EDITS = {
    'give someone their flowers': {'action': 'rename', 'to': "give someone one's flowers"},
    'while one is about it': {'action': 'rename', 'to': "while you're at it"},
    'on the ready': {'action': 'delete'},  # "at the ready" is there
    'from good hands': {'action': 'delete'},
    'son of the morning': {'action': 'meaning', 'meaning': "sabah yıldızı; Şeytan (Lucifer, Kitab-ı Mukaddes'te)"},
    'on a promise': {'action': 'meaning', 'meaning': '(İngiliz argo) birinden birlikte olma sözü almış olmak'},
    'go out like a light': {'action': 'meaning', 'meaning': 'hemen uyuyakalmak, ölü gibi uyumak'},
    'stupid is as stupid does': {'action': 'meaning', 'meaning': 'insanı aptal yapan davranışlarıdır'},
}
# --- Filter sheet 17: new phrases for the thin filters, the filter named in Turkish.
F17_CAT = {'Kip fiilleri': 'modal_verbs', 'Benzetmeler': 'similes', 'Gündelik dil / argo': 'informal_slang',
           'Kibar kalıplar': 'polite_phrases', 'Karıştırılan kelimeler': 'confusables', 'Sahte eş anlamlılar': 'false_friends'}
# "low-key" and "high-key" are the slang words ("low-key obsessed", "low-key tired");
# "would rather" is also "would rather go"; "I'm down" is found in "I'm down here".
F17_FIX = {
    12: {'phrase': 'would rather', 'meaning': '-meyi tercih etmek; (not ile) -memeyi tercih etmek'},
    22: {'phrase': 'low-key', 'meaning': '(argo) içten içe, biraz; sessiz sedasız'},
    23: {'phrase': 'high-key', 'meaning': '(argo) açık açık, fena hâlde'},
    28: None,
}

# --- Filter sheet 18: adjective + noun collocations of story language. The
# examples all follow one pattern ("The X changed their plans.", "The negative
# response reassured the residents.") and are left out; the collocations come
# without them. Left out too: free combinations with no pull between the words
# ("unexpected" + any noun, "empty room", "wooden door", "reaction time").
F18_DROP = {'hidden secret', 'empty room', 'quiet room', 'small window', 'open window', 'high window', 'narrow window',
            'long letter', 'wooden door', 'wide river', 'deep river'}
F18_MEANING = {'twisted plot': 'dolambaçlı, beklenmedik dönüşlü olay örgüsü', 'obvious choice': 'akla en yatkın seçim',
               'obvious question': 'akla ilk gelen soru', 'morning fog': 'sabah sisi',
               'poor judgment': 'kötü muhakeme, yanlış karar', 'good judgment': 'sağduyu, iyi muhakeme',
               'sound judgment': 'sağlam muhakeme', 'hasty judgment': 'aceleci karar, peşin hüküm',
               'fair judgment': 'adil değerlendirme'}

# --- Audit sheet 19 -------------------------------------------------------------
# The review sheet's notes from row 40 on belong to other phrases than the row
# they sit on, so only rows 2-39 are acted on.
D19_EX_FIX = {
    77: {'phrase': 'put sth on the line', 'ex': "\u201cDon't put everything we've worked for on the line,\u201d his brother warned."},
    88: {'ex': 'He was taken ill during the long ferry crossing.', 'ex_tr': 'Uzun feribot yolculuğu sırasında rahatsızlandı.'},
}
D19_EDITS = {
    **{p: {'action': 'delete'} for p in ('under it', 'under that', 'for the lose', "i'm not telling you", 'do you have a girlfriend',
                                         'milk can', 'in glass', 'for real life', 'in one case', 'nervous hit', 'crazy up',
                                         'leave with the one what brought you')},
    'put on the line': {'action': 'rename', 'to': 'put sth on the line'},  # "put his job on the line"
    'stuff you': {'action': 'meaning', 'meaning': 'canın cehenneme, defol (kaba)'},
    'behind its time': {'action': 'meaning', 'meaning': 'zamanının gerisinde, modası geçmiş'},
    'body english': {'action': 'meaning', 'meaning': '(sporda) topu vücut hareketiyle yönlendirmeye çalışmak'},
}

# --- Audit sheet 20 -------------------------------------------------------------
# "take to task" needs its object ("take him to task"); "in so far" is the
# "insofar as" that is there; "drive to drink" is "drive someone to drink".
D20_EX_FIX = {
    5: {'ex': 'It was a hard season, but the team won through in the end.', 'ex_tr': 'Zor bir sezondu ama takım sonunda başarıya ulaştı.'},
    47: {'ex': 'The traffic was slow as Christmas on the narrow mountain road.'},
    126: {'phrase': 'take sb to task', 'ex': 'The editor called him in to take him to task over the missing sources.'},
}
D20_EDITS = {
    **{p: {'action': 'delete'} for p in ('in so far', 'drive to drink', 'turn together')},
    'take to task': {'action': 'rename', 'to': 'take sb to task'},
    # "someone's" is not a slot for "my"; "one's" is (sheet v18: "stole my thunder").
    "steal someone's thunder": {'action': 'rename', 'to': "steal one's thunder"},
    'woman up': {'action': 'meaning', 'meaning': 'cesaretini toplamak, güçlü durmak (kadın için; "man up" gibi)'},
    'hang by a hair': {'action': 'meaning', 'meaning': 'pamuk ipliğine bağlı olmak, büyük tehlikede olmak'},
    'in at the deep end': {'action': 'meaning', 'meaning': '(throw/jump in at the deep end) hazırlıksız zor bir işin içine atılmak'},
    'smile from ear to ear': {'action': 'meaning', 'meaning': 'ağzı kulaklarına varmak'},
    'clear as a bell': {'action': 'meaning', 'meaning': 'çok net, apaçık; (ses) pırıl pırıl'},
    'life and soul of the party': {'action': 'meaning', 'meaning': 'partinin neşe kaynağı, eğlencenin merkezi'},
    'average up': {'action': 'meaning', 'meaning': 'yükselen hisseden ek alım yaparak ortalama maliyeti yükseltmek'},
    'sing up': {'action': 'meaning', 'meaning': 'daha yüksek sesle şarkı söylemek'},
    'red up': {'action': 'meaning', 'meaning': '(bölgesel, "redd up") ortalığı toplamak, toparlamak'},
}

# --- Audit sheet 21 -------------------------------------------------------------
# A phrasal verb takes its object before the particle ("boss the volunteers about").
D21_EX_FIX = {
    22: {'ex': "Don't boss the volunteers about; they're giving up their Saturday to help us."},
    25: {'ex': '“Say uncle!” Ben shouted, pinning his brother\'s arm behind his back.',
         'ex_tr': 'Ben kardeşinin kolunu arkasına kıvırıp “Pes de!” diye bağırdı.'},
    52: {'ex': '“Stop fooling about with that ladder,” she warned.', 'ex_tr': '“O merdivenle oynamayı bırak,” diye uyardı.'},
    62: {'ex': '“The back door is open,” she said in a low voice.'},
    129: {'ex': 'The guards began to pull the frightened prisoners about before the captain intervened.'},
    146: {'ex': 'The older boys used to push the smaller children about until a teacher intervened.'},
    170: {'ex': 'The pharmacy may stock out of flu medicine before the next delivery arrives.',
          'ex_tr': 'Yeni sevkiyat gelmeden eczanede grip ilacı tükenebilir.'},
}
D21_EDITS = {
    # Headings in the form a text has them ("ran me off my feet", "before you can run").
    'run someone off their feet': {'action': 'rename', 'to': "run someone off one's feet"},
    'learn to walk before one can run': {'action': 'rename', 'to': 'learn to walk before you can run'},
    'from where one is sitting': {'action': 'rename', 'to': "from where i'm sitting"},
    'serious as a heart attack': {'action': 'meaning', 'meaning': 'son derece ciddi, hiç şakası yok'},
    'stick about': {'action': 'meaning', 'meaning': 'bir süre daha kalmak, etrafta beklemek'},
}

# --- Audit sheet 22 -------------------------------------------------------------
# Rows 54-73: seven rows hold a sentence of another phrase ("medicine up" has
# "make a name for himself"); each goes to the phrase it shows. Headings take the
# form texts have ("give the horse its head", "work his employees into the ground").
D22_EX_FIX = {
    8: {'phrase': 'within reason'},
    49: {'phrase': 'give someone the eye'},
    54: {'phrase': 'make a name for oneself'},
    55: {'phrase': 'make an example of'},
    56: {'phrase': 'make light of'},
    58: {'phrase': 'on the point of'},
    62: {'phrase': "pull one's leg"},
    70: {'phrase': 'face the music'},
    72: None,  # "a bitter pill to swallow" is not in the dictionary
    73: {'phrase': 'jump the gun'},
    115: None,  # "keep your mind about you" is another verb
    106: {'ex': 'The new teacher is not as black as she is painted; the students just exaggerate.',
          'ex_tr': 'Yeni öğretmen anlatıldığı kadar kötü değil; öğrenciler sadece abartıyor.'},
}
D22_EDITS = {
    **{p: {'action': 'rename', 'to': t} for p, t in (
        ('give someone their head', "give someone one's head"), ('do somebody wrong', 'do someone wrong'),
        ('give the glad eye', 'give someone the glad eye'), ("one can run but one can't hide", "you can run but you can't hide"),
        ('throw in at the deep end', 'throw sb in at the deep end'), ('not as black as one is painted', 'not as black as sb is painted'),
        ("have one's foot in the door", 'foot in the door'), ("have time on one's hands", "time on one's hands"),
        ('put in the ground', 'put sb in the ground'), ('work into the ground', 'work sb into the ground'),
        ('give the gate', 'give sb the gate'), ('ride fence', 'ride the fence'), ('not worth salt', "not worth one's salt"),
        ("one could do it in one's sleep", "do it in one's sleep"))},
    **{p: {'action': 'merge', 'to': t} for p, t in (
        ('think one hung the moon', 'hang the moon'), ('leave somebody high and dry', 'leave someone high and dry'),
        ('fresh up', 'freshen up'), ('upon the books', 'on the books'))},
    # Review sheet: no such phrase, or the meaning is not one ("french fact": "Fransız gerçeği").
    **{p: {'action': 'delete'} for p in (
        'french fact', 'fire into the sun', 'kiss out', 'short down', 'slow off', 'slow out', 'apple up', 'sweater up',
        'bet up', 'dark up', 'with one shoulder', 'gone north about', 'rid out', 'medicine up', 'take the ride')},
    'fool away': {'action': 'meaning', 'meaning': '(vakit, para) boşa harcamak, çarçur etmek'},
}

# --- Audit sheet 23 -------------------------------------------------------------
# Rows 203-214 wrote "someone's" into the sentence itself; they get a real owner and
# the heading takes "one's", which matches any. Row 209: "too spicy to my taste"
# is not English ("for my taste"), so it gets a sentence where "to my taste" is.
D23_EX_FIX = {
    2: {'phrase': 'within reason', 'ex': 'You can ask for changes within reason, but the deadline cannot move.'},
    64: {'phrase': 'behind closed doors', 'ex': 'The committee met behind closed doors to discuss the confidential report.'},
    120: {'phrase': 'all of a sudden'},
    203: {'ex': '"I did not mean to hurt your feelings," he said after the awkward silence.',
          'ex_tr': "Mahcup sessizlikten sonra 'Duygularını incitmek istemedim' dedi."},
    204: {'ex': 'The teacher promised to take his part only after hearing both sides.',
          'ex_tr': 'Öğretmen ancak iki tarafı da dinledikten sonra onun tarafını tutacağına söz verdi.'},
    209: {'ex': 'The new flat was not quite to my taste, so we kept looking.',
          'ex_tr': 'Yeni daire pek zevkime göre değildi, o yüzden aramaya devam ettik.'},
    214: {'ex': 'When the bicycle crashed, two strangers rushed to come to her aid.',
          'ex_tr': 'Bisiklet devrilince iki yabancı onun yardımına koştu.'},
}
D23_EDITS = {
    **{p: {'action': 'rename', 'to': t} for p, t in (
        ('drop like a bad habit', 'drop sb like a bad habit'), ("caught with one's pants down", "catch sb with one's pants down"),
        ("to someone's taste", "to one's taste"), ("hurt someone's feelings", "hurt one's feelings"),
        ("take someone's part", "take one's part"), ("come to someone's aid", "come to one's aid"),
        ('for any price', 'at any price'))},
    **{p: {'action': 'merge', 'to': t} for p, t in (
        ('in reason', 'within reason'), ('with closed doors', 'behind closed doors'))},
    # Review sheet: not a set phrase ("rain death", "party cry") or a free adjective + noun.
    **{p: {'action': 'delete'} for p in ('rain death', 'party cry', 'heavy door', 'bright yellow')},
    **{p: {'action': 'meaning', 'meaning': m} for p, m in (
        ("catch sb with one's pants down", 'birini hazırlıksız yakalamak, rezil durumda bırakmak'),
        ('in a major key', '(müzik) majör tonda'),
        ('buy nice or buy twice', 'kaliteli al, iki kez alma; ucuz alan iki kez alır'),
        ('whatever helps you sleep at night', '(alaycı) sen öyle düşünmeye devam et, kendini nasıl rahatlatıyorsa'),
        ('ship and let ship', '(hayran dili) herkes istediği çifti desteklesin'),
        ('close the face', '(golf) sopanın yüzünü kapatmak'),
        ('page in', '(bilişim) bellekten yüklemek'),
        ('daughter out', '(soyağacı) kız soyundan tükenmek'),
        ('get the bullet', '(İngiliz, gündelik) işten atılmak, kovulmak'),
        ('have a thin time of it', '(İngiliz, eskice) zor bir dönem geçirmek'),
        ('blue and green should never be seen', '(eski moda giyim sözü) mavi ile yeşil yan yana giyilmez'),
        ('in a fog', 'kafası karışık, şaşkın; sis içinde'))},
}

# --- Phrasal verb work sheet 1 (all 1147 phrasal verbs with no example) -------------
# Hamit wrote 37 sentences and marked 43 headings "sil"; rows he left empty are skipped.
# "moderned up" and "flat the fabric down" are not how the verbs are used; the balloon
# sentence for "gas out" goes with his new meaning, which is not what "gassed out" means
# (worn out), so those three stay without a sentence. "rule off" draws a line under,
# it does not strike out: the sentence shows that.
# Fourteen sentences put a long object between verb and particle ("glass the balcony
# in to use it"); the reader only finds that split when the particle ends the clause,
# so verb and particle are put side by side.
O1_EX_FIX = {32: None, 54: None, 63: None,
             2: {'ex': "We shouldn't end off the meeting without reaching a final decision."},
             6: {'ex': 'Please key your voice down; everyone is sleeping.', 'ex_tr': 'Lütfen sesini alçalt; herkes uyuyor.'},
             7: {'ex': 'Using a field guide, the botanist quickly keyed out the rare plant.'},
             9: {'ex': 'They decided to glass in the balcony so they could use it in winter.'},
             19: {'ex': 'Every month she bottles away some money for her summer vacation.'},
             20: {'ex': 'Right after fermentation, the brewery bottles off the fresh beer.'},
             21: {'ex': 'The referee lined off the penalty area with white paint.'},
             25: {'ex': 'To make the new jacket look old, the prop designer dirtied it down.'},
             39: {'ex': 'The farmer barred off the dangerous area to keep the animals safe.'},
             42: {'ex': 'On the deck, the sailor cheesed down the heavy rope.'},
             60: {'ex': 'We should prepare ahead so that we save time while cooking.',
                  'ex_tr': 'Yemek yaparken zaman kazanmak için önceden hazırlık yapmalıyız.'},
             66: {'ex': 'The municipality grassed over the dusty area to create a new park.'},
             71: {'ex': 'The toy box was heavy, but the little girl pulled it along with great difficulty.',
                  'ex_tr': 'Oyuncak kutusu ağırdı ama küçük kız onu büyük bir zorlukla sürükledi.'},
             78: {'ex': 'After the cold swim, she toweled up quickly on the beach.'},
             44: {'ex': 'Rule off the last answer before you start the next exercise.',
                  'ex_tr': 'Bir sonraki alıştırmaya başlamadan önce son cevabın altına cetvelle çizgi çek.'}}
O1_EDITS = {
    **{p: {'action': 'delete'} for p in (
        'front off', 'front on', 'daughter out', 'bag off', 'sell away', 'gun up', 'seat out', 'blood in', 'blood out',
        'date out', 'ride by', 'sugar down', 'handle up', 'cream up', 'leg out', 'moon on', 'bridge up', 'rice out',
        'land down', 'fool along', 'farm down', 'cheese out', 'salt up', 'mess over', 'jim up', 'contract in',
        'yellow out', 'yellow up', 'couch down', 'wise off', 'jack off', 'lead out', 'mike off', 'medical out',
        'rope out', 'hell around', 'neck up', 'sex in', 'draw through', 'thin up', 'queen up', 'flag away', 'bomb around')},
    'battle out': {'action': 'rename', 'to': 'battle it out'},
    **{p: {'action': 'meaning', 'meaning': m} for p, m in (
        ('bar off', 'engelle kapatmak, çitle çevirmek'), ('rough in', 'kaba taslağını hazırlamak'),
        ('rule off', 'altına cetvelle çizgi çekip ayırmak'),
        ('single up', '(denizcilik) halatları tekleştirip kalkışa hazırlanmak; tek başına hareket etmek'),
        ('cheese down', '(denizcilik) halatı düzenli sarmak'))},
}

# --- Idiom work sheet 1 (Parti 24) ---------------------------------------------------
# Headings with "someone's" are read word for word; with "one's" any owner fits, so
# they take "one's". Verbs whose sentences put the object after the verb get "sb".
# Plural owners ("buyers' eyes") are not read as owners, so those sentences use one.
Y1_EX_FIX = {
    193: {'ex': 'The leaked emails forced her hand, and the mayor finally announced an investigation.'},
    197: {'ex': 'The director knew the blame for the failed evacuation lay at his door.',
          'ex_tr': 'Müdür, başarısız tahliyenin suçunun kendisinde olduğunu biliyordu.'},
    198: {'ex': 'The captain marked his card after the rookie ignored the signal a second time.'},
    201: {'phrase': 'save face', 'ex': 'The company apologized publicly to help the manager save face after the embarrassing error.'},
    289: {'ex': 'The accident on the icy road claimed his life only a week after his wedding.',
          'ex_tr': 'Buzlu yoldaki kaza, düğününden yalnızca bir hafta sonra onun hayatına mal oldu.'},
    195: {'ex': 'The general knew he would have their blood on his head if he ordered the attack.'},
    203: {'ex': 'If the new chain opens next door, it could take the bread out of his mouth by driving away his customers.',
          'ex_tr': 'Yeni zincir market yan tarafa açılırsa müşterilerini çekip onun ekmeğiyle oynayabilir.'},
    204: {'ex': 'The spokesman tried to throw dust in our eyes with a pile of irrelevant statistics.'},
    275: {'ex': 'His promises were not worth beans once the documents proved he had been lying.'},
    364: {'ex': 'The developer tried to pull the wool over our eyes by hiding the cracks behind fresh paint.'},
    525: {'ex': 'The choir sang outside the hospital to raise their spirits during the long winter.'},
}
Y1_EDITS = {
    **{p: {'action': 'rename', 'to': t} for p, t in (
        ("bite someone's head off", "bite one's head off"), ("force someone's hand", "force one's hand"),
        ("hang over someone's head", "hang over one's head"), ("mark someone's card", "mark one's card"),
        ("take the bread out of someone's mouth", "take the bread out of one's mouth"),
        ("lift someone's spirits", "lift one's spirits"), ("raise someone's spirits", "raise one's spirits"),
        ("pull the wool over someone's eyes", "pull the wool over one's eyes"), ("lie at someone's door", "lie at one's door"),
        ("throw dust in someone's eyes", "throw dust in one's eyes"), ("claim someone's life", "claim one's life"),
        ("have someone's blood on one's head", "have one's blood on one's head"), ('tell its own tale', "tell one's own tale"),
        ("call it as one sees it", "call it as sb sees it"),
        ('deal a bad hand', 'deal sb a bad hand'), ('deal a good hand', 'deal sb a good hand'),
        ('put on the long finger', 'put sth on the long finger'), ('call on the carpet', 'call sb on the carpet'),
        ('leave for dust', 'leave sb for dust'), ('blow out of the water', 'blow sth out of the water'),
        ('drop like a hot potato', 'drop sb like a hot potato'), ('throw off balance', 'throw sb off balance'),
        ('throw to the wolves', 'throw sb to the wolves'), ('kick upstairs', 'kick sb upstairs'),
        ('give the royal treatment', 'give sb the royal treatment'))},
    'bring someone to their knees': {'action': 'rename', 'to': "bring sb to one's knees"},
    # Review notes: the usual heading of the same idiom.
    **{p: {'action': 'merge', 'to': t} for p, t in (
        ("taste of one's own poison", "taste of one's own medicine"), ('pull the leg of', "pull one's leg"),
        ('row in the same boat', 'in the same boat'), ('catch dust', 'gather dust'), ('pull the long bow', 'draw the long bow'),
        ("put one's neck out", "stick one's neck out"), ('dog who caught the tire', 'dog that caught the car'),
        ('burn the roof', 'raise the roof'))},
    **{p: {'action': 'rename', 'to': t} for p, t in (
        ("jump in one's skin", "jump out of one's skin"), ("shake off the dust from one's feet", "shake the dust off one's feet"),
        ('dig oneself in a hole', 'dig oneself into a hole'), ('find quarrel in a straw', 'find a quarrel in a straw'),
        ('get a load', 'get a load of'), ('come up with snake eyes', 'come up snake eyes'),
        ("knock someone's wind out", 'knock the wind out of sb'), ('bite of the cherry', 'another bite at the cherry'),
        ('get the jump', 'get the jump on'))},
    **{p: {'action': 'merge', 'to': t} for p, t in (('take someone for granted', 'take sb for granted'), ("save someone's face", 'save face'))},
    # Notes marked "sil".
    **{p: {'action': 'delete'} for p in (
        'expensive drunk', 'half a head', 'keep the rent down', 'raise the line', 'three guys in a garage', 'yellow state',
        'take the meaning', 'shoot the gold', 'turn a loss', 'center part', 'forty minutes of hell', "cut away one's soul",
        'express elevator', 'secretary spread', 'fruit of the union', 'clear the throat', 'smoke the whole pack',
        'forget to take one\'s medication this morning', 'cold treatment', 'fair coin', 'open the schools', 'heavy equipment',
        'take a shit', 'take the mask off', 'baby elephant in the room', 'painting rocks', 'take roll', 'no score',
        'know someone from eve', 'smile a thousand smiles', 'sea load', 'shed find', 'suspended congress')},
}
# Meanings the notes show to be wrong; renamed headings go by their new name.
Y1_MEANING = {
    'top oneself': '(İngiliz, argo) kendini öldürmek, intihar etmek',
    'blow sth out of the water': '(bir iddiayı) tamamen çürütmek; açık ara geride bırakmak',
    "wash one's dirty laundry in public": 'kirli çamaşırlarını ortaya dökmek, özel meseleleri herkesin önünde konuşmak',
    'buy straw hats in winter': '(borsa) ucuzken alıp değerlenmesini beklemek',
    'go climb a tree': '(Amerikan, kaba) defol git, başımdan git',
}
# Usage and field labels from the notes ("(İngiliz, eskice); ...") go in front of the meaning.
Y1_LABELS = {'Amerikan', 'eskice', 'İngiliz', 'argo', 'konuşma dili', 'bölgesel', 'edebî', 'hukuk', 'alaycı', 'spor',
             'siyaset', 'mizahi', 'İrlanda', 'iş dünyası', 'Avustralya', 'denizcilik', 'beyzbol', 'internet argosu',
             'kriket', 'dinî', 'askerî', 'finans', 'tiyatro', 'astronomi', 'tıp', 'sinema', 'resmî', 'golf', 'tenis',
             'borsa', 'aşağılayıcı', 'kaba'}
Y1_LABEL_MAP = {'dinsel': 'dinî', 'cinsel argo': 'kaba'}


def y1_meaning_edits(wb, ph_edits):
    out = []
    ren = {k: v['to'] for k, v in ph_edits.items() if v and v['action'] == 'rename'}
    gone = {k for k, v in ph_edits.items() if v and v['action'] in ('delete', 'merge')}
    for r in wb['Örnek cümle önerileri'].iter_rows(min_row=2, values_only=True):
        r = ['' if v is None else str(v).strip() for v in r]
        ph, mean, note = r[0], r[2], (r + [''] * 6)[5]
        if not ph or ph in gone:
            continue
        head = ren.get(ph, ph)
        if head in Y1_MEANING:
            out.append({'phrase': head, 'action': 'meaning', 'meaning': Y1_MEANING[head]})
            continue
        m = re.match(r'\(([^)]*)\)', note)
        if not m or not mean or mean.startswith('('):
            continue
        labels = []
        for t in re.split(r'[,/;]', m.group(1)):
            t = Y1_LABEL_MAP.get(t.strip(), t.strip())
            if t in Y1_LABELS and t not in labels:
                labels.append(t)
        if labels:
            out.append({'phrase': head, 'action': 'meaning', 'meaning': f"({', '.join(labels)}) {mean}"})
    return out

# --- Phrasal verb work sheets 2-4 (rows 80-259 of the list) ---------------------------
# Forty sentences put a long object between verb and particle ("printed a new colorful
# brochure up for"), or end the particle with a preposition; verb and particle go side by
# side. Rows that show another verb ("froze over" for "freeze down") go to that verb.
O2_EX_FIX = {
    122: {'ex': 'The technician linked in the new computer to the main office network.'},
    139: {'ex': 'The strict teacher loaded down the students with too much homework.'},
}
O2_EX_FIX[138] = {'ex': 'The design is based off an ancient Greek temple.', 'ex_tr': 'Tasarım eski bir Yunan tapınağından yola çıkıyor.'}
O3_EX_FIX = {
    3: {'ex': 'The company printed up a new colorful brochure for the upcoming campaign.'},
    10: {'phrase': "cast one's mind back"},
    14: {'ex': 'From the grandstands, the excited fans rooted on their favorite team.'},
    21: {'ex': 'These days the successful tech company is shoveling in money.'},
    25: {'ex': 'She does pilates every morning to tone up her leg muscles.'},
    26: {'ex': 'The sudden loud noise triggered off the sensitive car alarm.'},
    32: {'ex': 'During the construction, the heavy trucks muddied up the dirt road.'},
    33: {'ex': "Using the city's camera system, the police traced down the stolen vehicle."},
    34: {'ex': 'On a large sheet of paper, the architect traced out the detailed floor plan.'},
    41: {'ex': 'With a huge discount, the clever salesman managed to hook in the naive customer.'},
    46: {'ex': 'On his old typewriter, the angry writer pounded out a long complaint letter.'},
    47: {'ex': 'In a heavy stone mortar, the cook pounded up the fresh garlic cloves.'},
    50: {'phrase': 'string along', 'ex': 'With false promises of high returns, he strung along the naive investors.'},
    53: {'ex': 'Right outside the bank, the police officers collared up the suspect.'},
    54: {'ex': 'To find a single piece of evidence, the forensic team combed over the crime scene.'},
    57: {'ex': 'To mark the penalty spot, the referee paced off the short distance.'},
}
O4_EX_FIX = {
    2: {'ex': 'To save money, the struggling company scaled down its operations.'},
    3: {'ex': 'During the market dip, the clever investor scaled in his purchases.'},
    5: {'phrase': 'sober up'},
    15: {'ex': 'On her bedroom wall, the teenager pinned up a large colorful poster.'},
    16: {'ex': 'Without listening, the arrogant manager waved aside my useful suggestions.'},
    17: {'ex': 'On the empty road, the stranded driver waved down a passing car for help.'},
    18: {'ex': 'After finishing his chores, he folded away the large ironing board.'},
    19: {'ex': 'With solid oak wood, the carpenter framed in the new door.'},
    22: {'phrase': 'freeze over'},
    23: {'phrase': 'freeze out'},
    33: {'ex': 'The loud guard dog frightened off the sneaky thieves in the backyard.'},
    35: {'ex': 'Very carefully, the skilled tailor sewed together the torn pieces of fabric.'},
    38: {'ex': 'The nasty fall bruised up his left knee pretty badly.'},
    41: {'ex': 'For a quick dinner, we grilled up a few fresh spicy sausages.'},
    46: {'ex': 'In one single gulp, the thirsty man tossed back the cold drink.'},
    47: {'ex': 'The angry teacher tossed down the failed exam papers on the wooden desk.'},
    48: {'ex': 'Before the unexpected guests arrived, she tossed together a quick fresh salad.'},
    51: {'ex': 'Despite the heavy protests, the stubborn politician bulled through his controversial new law.'},
    55: {'ex': 'With some fresh aromatic herbs, you can flavor up the bland potato soup.'},
    60: {'ex': 'By running five miles every morning, she melted off a lot of stubborn fat.'},
}
O2_EDITS = {
    'fancy up': {'action': 'rename', 'to': 'fancy oneself up'},
    # Rows marked "sil"; "muscle into" (zorla girmek) is common and stays.
    **{p: {'action': 'delete'} for p in ('pig off', 'pitch on', 'puzzle through', 'gay up', 'circle in', 'circle out', 'quarrel out', 'stew up', 'flute around', 'tag up', 'jerk off', 'jerk over', 'jerk up', 'hike out', 'shade off', 'shade up', 'bug up', 'rat through', 'shed out', 'freak off', 'duck off', 'harsh down', 'harsh on', 'rubber up', 'steam off', 'mug off', 'trump out', 'wire away', 'ditch out', 'hook on', 'pound off', 'range out', 'zone off', 'eagle out', 'eagle up', 'chapter out', 'grain up', 'sally out', 'chef up', 'butt on', 'butt up', 'beggar off', 'bull up', 'jog on', 'lamb down', 'melt out')},
    **{p: {'action': 'merge', 'to': t} for p, t in (('string on', 'string along'), ('freeze off', 'freeze out'))},
    **{p: {'action': 'meaning', 'meaning': m} for p, m in (
        ('score out', 'üstünü çizmek, silmek'), ('scratch together', 'zar zor denkleştirmek, azar azar biriktirmek'),
        ('screen in', 'tel örgüyle çevirmek'), ('swallow down', '(gururunu, duygusunu) yutmak, bastırmak'),
        ('peel out', 'lastik yakarak hızla kalkmak'), ('base off', '-e dayandırmak, -den yola çıkmak'),
        ('pill up', 'tiftiklenmek, tüylenmek'), ('hook in', 'kandırıp çekmek, tavlamak'),
        ('collar up', 'yakalamak, ensesinden tutmak'), ('scale in', '(finans) kademeli olarak pozisyon almak'),
        ('scale out', '(bilişim) sunucu ekleyerek genişletmek; (finans) kademeli olarak pozisyon azaltmak'),
        ('bully off', '(hokey) oyunu başlatmak'), ('string along', 'oyalamak, boş vaatlerle kandırıp durmak'),
        ('freeze out', 'dışlamak, aralarına almamak; (dışarısı) çok soğuk olmak'))},
}

# --- Idiom work sheet 2 (Parti 25) ---------------------------------------------------
# Same fixes as Parti 24: "someone's" headings take "one's", noun owners ("the boy's",
# "their predecessors'") become pronouns, and object verbs get "sb".
Y2_EX_FIX = {
    108: {'ex': 'In the old story, the schoolmaster threatened to box his ears for speaking out.'},
    114: {'ex': 'We stand on their shoulders: every discovery today builds on their work.',
          'ex_tr': 'Onların omuzlarında yükseliyoruz: bugünkü her buluş onların çalışmalarına dayanıyor.'},
    282: {'ex': 'Instead of admitting the error, Arda kept lying and dug himself into a hole.'},
    922: {'ex': 'After reading the complaints, I would not touch that contractor with a barge pole.'},
    952: {'ex': 'Every volunteer worked like a Trojan to reopen the library before winter.',
          'ex_tr': 'Her gönüllü kütüphaneyi kış gelmeden açmak için canla başla çalıştı.'},
    1368: {'ex': 'Nervous investors often zig when they should zag.',
           'ex_tr': 'Tedirgin yatırımcılar çoğu zaman yapmaları gerekenin tam tersini yapar.'},
}
Y2_EDITS = {
    **{p: {'action': 'rename', 'to': t} for p, t in (
        ("box someone's ears", "box one's ears"), ("stand on someone's shoulders", "stand on one's shoulders"),
        ("jog someone's memory", "jog one's memory"), ("stir someone's blood", "stir one's blood"),
        ("tread on someone's toes", "tread on one's toes"), ("yuck someone's yum", "yuck one's yum"),
        ('praise to the skies', 'praise sb to the skies'), ('watch like a hawk', 'watch sb like a hawk'),
        ('not touch with a barge pole', 'not touch sth with a barge pole'), ('zig when one should zag', 'zig when sb should zag'),
        ("get one's fingers onto", "get one's fingers on"), ('weigh the anchor', 'weigh anchor'),
        ('gift from the goddesses', 'gift from the gods'))},
    **{p: {'action': 'merge', 'to': t} for p, t in (
        ('sweep under the rug', 'sweep something under the rug'), ('look before one leaps', 'look before you leap'),
        ('cloud seven', 'on cloud nine'))},
    **{p: {'action': 'delete'} for p in ('short on looks', 'warm as life', 'marriage bed', 'english as apple pie')},
}

# --- Phrasal verb work sheet 5 (rows 260-319) --------------------------------------
# Eleven long objects between verb and particle; two rows show another verb.
O5_EX_FIX = {
    9: {'ex': 'Before the tow truck arrived, the police coned off the dangerous accident area.'},
    10: {'ex': 'With a pep talk, the new manager tried to ginger up the bored sales team.'},
    11: {'ex': 'At the airport entrance, the security guards patted down the suspicious passenger.'},
    12: {'ex': 'To keep the wild animals out, the wealthy owner railed in the beautiful garden.'},
    13: {'ex': 'The farmer railed off the sick sheep from the rest of the healthy flock.'},
    19: {'ex': "To improve the movie's pacing, the director edited in a new exciting scene."},
    24: {'ex': 'She managed to rake together enough money to buy that vintage dress.'},
    27: {'phrase': 'double down'},
    29: {'ex': 'The skilled carpenter buffed down the rough wooden table until it was smooth.'},
    36: {'ex': 'During the press conference, the busy journalist dashed down a few quick notes.'},
    42: {'ex': 'The smart sheepdog quickly herded together the scattered sheep into the barn.'},
    52: {'phrase': 'shove off'},
    53: {'ex': 'In the school playground, the big bully shoved around the smaller kids.'},
}
O5_EDITS = {
    # Rows marked "sil"; "fart about" and "fart around" (vakit öldürmek, oyalanmak) are common and stay.
    **{p: {'action': 'delete'} for p in (
        'stack off', 'brace about', 'brace by', 'brace in', 'wasp around', 'bud up', 'dodge up', 'bro out', 'bump across',
        'bump around', 'bump down', 'bump on', 'enlarge up', 'fart off', 'fleet up', 'puddle up', 'quest after',
        'rattle down', 'scope in', 'shove about', 'sling about', 'sling along', 'spike out', 'stance up', 'strengthen up')},
    'double down': {'action': 'meaning', 'meaning': 'üstüne gitmek, kararlılığını artırmak, riski ikiye katlamak'},
}

# --- Idiom work sheet 3 (Parti 26) ---------------------------------------------------
Y3_EX_FIX = {
    601: {'ex': 'Hurry up, time is ticking and the water is still rising.', 'ex_tr': 'Acele edin, zaman daralıyor ve su hâlâ yükseliyor.'},
}
Y3_EDITS = {
    **{p: {'action': 'rename', 'to': t} for p, t in (
        ("burn someone's ears", "burn one's ears"), ("cancel someone's christmas", "cancel one's christmas"),
        ("written all over someone's face", "written all over one's face"), ("answer someone's prayers", "answer one's prayers"),
        ("rip someone's head off", "rip one's head off"), ("make someone's head spin", "make one's head spin"),
        ("land in someone's lap", "land in one's lap"), ("dash someone's hopes", "dash one's hopes"),
        ("clip someone's wings", "clip one's wings"), ("bane of someone's existence", "bane of one's existence"),
        ("answer to someone's prayers", "answer to one's prayers"),
        ('rub up the wrong way', 'rub sb up the wrong way'), ('knock down a peg', 'knock sb down a peg'),
        ('take down a peg', 'take sb down a peg'), ('put through hoops', 'put sb through hoops'),
        ('tear to shreds', 'tear sth to shreds'), ('pip to the post', 'pip sb to the post'),
        ('the feathers fly', 'the feathers will fly'), ('crawl before one walks', 'crawl before you walk'),
        ("one's fingers itch", 'fingers itch'), ('fall foul', 'fall foul of'), ('grand scheme', 'in the grand scheme of things'))},
    **{p: {'action': 'merge', 'to': t} for p, t in (
        ('catch napping', 'catch someone napping'), ("one's fingers are all thumbs", 'all thumbs'),
        ('give the eye', 'give someone the eye'), ("say someone's prayers", "say one's prayers"))},
    "say one's prayers": {'action': 'meaning', 'meaning': 'dua etmek; (tehdit) son duanı et'},
}

# --- Idiom work sheet 4 (Parti 27) and phrasal verb sheets 6-11 (the last 518 rows) ---
# Parti 27: same heading fixes as before; "the city's finest" cannot match "the finest".
Y4_EX_FIX = {
    369: None,
    228: {'ex': 'His last investor has walked away, and now his cake is dough.', 'ex_tr': 'Son yatırımcısı da çekip gitti; artık iş işten geçti.'},
    615: {'ex': "After the company missed its third payment, the employees whispered: 'The vultures are circling.'"},
}
Y4_EDITS = {
    **{p: {'action': 'rename', 'to': t} for p, t in (
        ('get it how one lives', 'get it how sb lives'), ("one's cake is dough", 'cake is dough'),
        ('give the sack', 'give sb the sack'), ("snap at someone's heels", "snap at one's heels"),
        ('throw off the trail', 'throw sb off the trail'), ('send to the glue factory', 'send sb to the glue factory'),
        ("fix someone's wagon", "fix one's wagon"), ('tie in knots', 'tie sb in knots'), ('rip to shreds', 'rip sth to shreds'))},
    'no bones about it': {'action': 'merge', 'to': 'make no bones about'},
    **{p: {'action': 'delete'} for p in ('race of truth', 'throw an eye', 'oxygen burning', 'comfort girl')},
    'put facts on the ground': {'action': 'meaning', 'meaning': 'fiilî durum yaratmak, oldubitti oluşturmak'},
    'for the plot': {'action': 'meaning', 'meaning': '(internet argosu) sırf hikâyesi, macerası olsun diye'},
}
# Phrasal verb sheets 6-11: many rows hold a sentence of a verb the row is not about
# ("lather up": "The loud sudden noise leafed him out"); those, and sentences whose
# verb is not the heading's, are left out (None). Where the right verb only has a long
# object before its particle, the particle is moved next to the verb.
OB_EX_FIX = {
    6: {
        4: {'ex': 'The researchers sieved out the fine gold particles from the river sand.'},
        7: {'ex': 'The doctor used a special tool to suck out the poisonous snake venom.'},
        8: {'ex': 'The two tired drivers swapped over their seats to continue the long journey.'},
        9: None,
        10: {'ex': 'He regrettably trifled away his valuable youth on useless computer games.'},
        12: {'ex': 'The native tribe bartered away their valuable furs for basic metal tools.'},
        13: {'ex': 'The hungry students bashed together a quick late-night dinner from leftovers.'},
        14: None,
        15: None,
        16: None,
        18: {'ex': 'The strict headmaster boomed out his harsh instructions across the silent hall.'},
        24: {'ex': 'She brought a fresh box of chocolates to chipper up her sad friend.'},
        26: {'ex': 'He chucked off his wet muddy shoes at the front door.'},
        32: None,
        33: None,
        34: None,
        36: None,
        37: None,
        38: None,
        40: None,
        42: None,
        43: None,
        45: None,
        47: None,
        48: None,
        49: None,
        50: None,
        52: None,
        54: None,
        55: None,
        56: None,
        57: None,
        58: None,
        59: None,
        60: None,
        62: None,
        63: None,
        64: None,
        65: None,
        66: None,
        68: None,
        69: None,
        70: None,
        71: None,
        73: None,
        75: None,
        76: None,
        77: None,
        78: None,
        80: None,
        81: None,
        82: None,
        83: None,
        84: None,
        85: None,
        86: None,
        87: None,
        88: None,
        90: None,
        91: None,
        92: None,
        93: None,
        94: None,
        95: None,
        96: None,
        97: None,
        98: None,
        99: None,
        101: None,
    },
    7: {
        2: None,
        4: {'ex': 'The angry farmer shooed off the stray dogs from his green field.'},
        5: {'ex': "The experienced lawyer smacked down the opponent's weak arguments in court."},
        12: None,
        13: {'ex': 'She tacked down the old posters on the wall using small metal pins.'},
        14: {'ex': 'The politician tacked on a controversial clause to the end of the new law.'},
        15: {'ex': 'The carpenter tacked together the broken wooden frame temporarily.'},
        16: {'ex': 'The rider tacked up his beautiful black horse before the morning race.'},
        17: {'ex': 'The angry musician thumped out a loud heavy rhythm on the drums.'},
        27: None,
        33: {'phrase': 'black out', 'ex': 'The thick heavy curtains blacked out the small bedroom completely.'},
        34: {'ex': 'The massive speakers blared out the rock music across the entire stadium.'},
        35: {'ex': 'The angry protester blatted out his loud complaints through a megaphone.'},
        36: None,
        37: {'ex': 'The television station bleeped out the rude curse words from the live interview.'},
        42: {'ex': 'He used a fresh paper towel to blot up the spilled black ink.'},
        51: {'ex': 'The editor bracketed out the unnecessary long paragraph from the final article.'},
        68: {'ex': 'The builder chinked up the cracks in the stone wall with fresh cement.'},
        69: None,
        72: {'ex': 'The experienced sailors clewed down the large main sail before the terrible storm.'},
        73: None,
        81: None,
        94: {'ex': 'She dabbed out the dark coffee stain from the white carpet with a sponge.'},
        95: {'ex': 'He gently dabbed up the spilled water using a dry paper towel.'},
        98: None,
    },
    8: {
        6: None,
        10: None,
        22: None,
        25: None,
        29: None,
        31: {'ex': 'The heavy wind flattened down the tall grass in the large open field.'},
        37: None,
        45: {'ex': 'She frivolled away her entire inheritance on expensive designer clothes.'},
        46: {'ex': 'The high humidity in the air frizzed up her straight hair completely.'},
        47: {'ex': 'The lazy students fudged together a weak presentation just before the class started.'},
        49: {'ex': 'They furbished up the old wooden cabin beautifully before the summer holiday.'},
        51: {'ex': 'The old camera lens fuzzed out the background beautifully.'},
        54: {'ex': 'She garnered up enough courage to speak to the strict principal.'},
        66: {'ex': 'They grubbed up the old dead trees to plant a new colorful garden.'},
        71: {'ex': 'The tragic experiences hardened up his soft heart over the long years.'},
        72: {'ex': 'The committee hashed over the new proposals for three long hours.'},
        78: {'ex': 'The lumberjacks hewed down the giant oak tree with sharp heavy axes.'},
        80: None,
        82: {'ex': 'The persistent detective hounded down the escaped criminal across the entire country.'},
        92: {'ex': 'She jumbled together all her old winter clothes in a large cardboard box.'},
        100: {'ex': 'The survivors lashed together the broken wooden planks to build a small raft.'},
        101: {'ex': 'The skilled cowboy lassoed up the running wild horse in seconds.'},
    },
    9: {
        2: None,
        5: None,
        6: None,
        8: None,
        9: None,
        11: None,
        14: None,
        15: None,
        19: None,
        21: None,
        22: None,
        25: None,
        27: None,
        29: None,
        31: None,
        32: None,
        34: None,
        35: None,
        37: None,
        38: None,
        40: None,
        41: None,
        42: None,
        43: None,
        46: None,
        47: None,
        48: None,
        49: None,
        50: None,
        51: None,
        52: None,
        53: None,
        55: None,
        56: None,
        57: None,
        58: None,
        59: None,
        60: None,
        61: None,
        62: None,
        63: None,
        64: None,
        65: None,
        66: None,
        67: None,
        68: None,
        69: None,
        70: None,
        72: None,
        73: None,
        74: None,
        75: None,
        76: None,
        77: None,
        79: None,
        80: None,
        81: None,
        82: None,
        83: None,
        84: None,
        85: None,
        86: None,
        87: None,
        88: None,
        89: None,
        90: None,
        91: None,
        92: None,
        93: None,
        94: None,
        95: None,
        96: None,
        97: None,
        98: None,
        99: None,
        100: None,
        101: None,
    },
    10: {
        3: {'ex': 'The hungry boy scoffed down his warm dinner in just two minutes.'},
        5: {'ex': 'She scooped out the fresh avocado flesh with a silver spoon.'},
        7: {'ex': 'He scoured down the dirty kitchen counter with a hard sponge.'},
        9: {'ex': 'The busy doctor scrawled down a quick prescription on his small notepad.'},
        14: None,
        18: {'ex': 'The rough pavement scuffed up his new leather shoes terribly.'},
        25: {'ex': 'The corrupt manager siphoned off millions of dollars into a secret bank account.'},
        27: None,
        35: {'ex': 'Snakes naturally slough off their old dead skin every few months.'},
        37: {'ex': 'The workers sluiced down the dirty factory floor at the end of the day.'},
        40: {'ex': 'The noisy child slurped up his hot chicken soup in just one minute.'},
        43: {'ex': 'The eager shoppers snatched up the discounted electronic items completely.'},
        46: {'ex': 'The careful gardener snipped off the dead flower heads with sharp scissors.'},
        54: {'ex': 'The broken machine spewed out thick black smoke into the factory air.'},
        66: {'ex': 'The young sailor swabbed down the dirty wooden deck early in the morning.'},
        69: {'ex': 'The thirsty worker swilled down the cold glass of water in one gulp.'},
        77: {'ex': 'The manager teed up the important meeting perfectly for the new clients.'},
        88: {'ex': 'They togged up in elegant clothes for the royal wedding.'},
        93: {'ex': 'The heavy boots tramped down the soft wet mud completely.'},
        98: {'ex': 'The robbers trussed up the poor bank manager with heavy ropes.'},
        99: {'ex': 'She tucked up her tired little daughter warmly in her cozy bed.'},
    },
    11: {
        2: None,
        6: {'ex': 'The patient was slowly weaned off the strong pain medication.', 'ex_tr': 'Hasta güçlü ağrı kesicilerden yavaş yavaş kesildi.'},
        9: {'ex': 'The HR team winnowed down the massive applicant list to just five candidates.'},
        10: {'ex': 'The strict coach winnowed out the weak players during the tough tryouts.'},
    },
}
# Rows marked "sil"; common verbs among them stay: abound in, bog off, boogie down, confer with, cue up, dwindle down, fink out, flatten out, lark about, linger over, loll around, muck around, partition off, psych out, rig up, skim over, spew up, yack away.
OB_EDITS = {
    **{p: {'action': 'delete'} for p in (
        'moss out', 'shin out', 'spear up', 'strapped up', 'bunker out', 'bust around', 'bust on', 'cavern out',
        'hop about', 'howl on', 'noodle up', 'preach down', 'shorten down', 'blubber out', 'hoard out', 'pip out',
        'shoo in', 'snot up', 'trolley off', 'tumble up', 'whack on', 'whack out', 'begger off', 'blimp up',
        'bling out', 'bling up', 'blob off', 'bollix up', 'bollocks up', 'booger off', 'booger up', 'bop around',
        'broil up', 'buggerise about', 'bundy off', 'bundy on', 'bung on', 'butch up', 'cack on', 'chub up',
        'chump off', 'cooccur with', 'cosy along', 'crip out', 'crip up', 'crit out', 'crum up', 'crumb up',
        'dag out', 'dap up', 'doss around', 'doss off', 'doss out', 'douche down', 'dub out', 'dub up',
        'ebb down', 'ebb off', 'ebb out', 'eff off', 'fack off', 'fag out', 'faggot up', 'fiercen up',
        'flake down', 'flex off', 'flex out', 'flex up', 'footle about', 'footle around', 'freckle up', 'frig around',
        'frigg up', 'funk up', 'futt about', 'fuzzy over', 'gaff off', 'gee along', 'geeze up', 'glaze up',
        'gnash up', 'gob off', 'gobble off', 'gook up', 'goon out', 'grub out', 'hackle up', 'halter up',
        'handpick out', 'heel out', 'heft up', 'heighten up', 'horf down', 'hulk off', 'hutch up', 'jag off',
        'jell out', 'jerky up', 'kak on', 'kink out', 'kludge out', 'klunk out', 'lard down', 'lathered up',
        'lax up', 'lengthen up', 'loom ahead', 'luff up', 'lush around', 'mack down', 'mack out', 'merc up',
        'micky off', 'mong out', 'murk out', 'muster out', 'nix off', 'oink out', 'peddle out', 'plough down',
        'ratchet down', 'schmaltz up', 'scorch up', 'scour up', 'scrawl off', 'scrawl out', 'scrawl up', 'scrounge down',
        'scrum up', 'scrump up', 'scuzz up', 'shingle up', 'shuck down', 'skank up', 'sleek over', 'slick up',
        'slop out', 'slug away', 'sluice out', 'slush around', 'slush up', 'sniff up', 'snod up', 'snootle around',
        'snork down', 'snort up', 'sortie out', 'sperg out', 'spiel off', 'spout out', 'sprucen up', 'squig out',
        'stat out', 'sull up', 'swag out', 'swag up', 'swill up', 'taco out', 'tally on', 'teem in',
        'thresh about', 'tinker up', 'tog out', 'torque up', 'tosh up', 'trample out', 'trice up', 'trog off',
        'tump over', 'tweak on', 'wack out', 'waft off', 'wanton away', 'widen up', 'wonk out', 'yack on',
        'zap over', 'zap up', 'zoot up',
    )},
    'blot up': {'action': 'meaning', 'meaning': 'emdirerek almak, kurulamak'},
}

AUDIT_FIX = {'hamit_deyim4_2026-11-20.xlsx': (Y4_EX_FIX, Y4_EDITS),
             **{f'hamit_obek{n}_2026-11-20.xlsx': (OB_EX_FIX[n], OB_EDITS if n == 6 else {}) for n in range(6, 12)},
             'hamit_deyim3_2026-11-20.xlsx': (Y3_EX_FIX, Y3_EDITS),
             'hamit_obek5_2026-11-20.xlsx': (O5_EX_FIX, O5_EDITS),
             'hamit_deyim2_2026-11-20.xlsx': (Y2_EX_FIX, Y2_EDITS),
             'hamit_obek2_2026-11-20.xlsx': (O2_EX_FIX, O2_EDITS), 'hamit_obek3_2026-11-20.xlsx': (O3_EX_FIX, {}),
             'hamit_obek4_2026-11-20.xlsx': (O4_EX_FIX, {}),
             'hamit_deyim1_2026-11-20.xlsx': (Y1_EX_FIX, Y1_EDITS),
             'hamit_obek1_2026-11-20.xlsx': (O1_EX_FIX, O1_EDITS),
             'hamit_denetim23_2026-11-20.xlsx': (D23_EX_FIX, D23_EDITS),
             'hamit_denetim22_2026-11-20.xlsx': (D22_EX_FIX, D22_EDITS),
             'hamit_denetim21_2026-11-20.xlsx': (D21_EX_FIX, D21_EDITS),
             'hamit_denetim20_2026-11-20.xlsx': (D20_EX_FIX, D20_EDITS),
             'hamit_denetim19_2026-11-20.xlsx': (D19_EX_FIX, D19_EDITS),
             'hamit_denetim16_2026-11-20.xlsx': (D16_EX_FIX, D16_EDITS),
             'hamit_denetim14_2026-11-20.xlsx': (D14_EX_FIX, D14_EDITS),
             'hamit_denetim15_2026-11-20.xlsx': (D15_EX_FIX, D15_EDITS)}


def lang_of(word, meaning, tr_words):
    """Turkish when the word is a known Turkish word or has Turkish letters,
    or when its meaning is written in English."""
    if word in tr_words or any(c in word for c in 'çğıöşüâî'):
        return 'tr'
    if any(c in meaning for c in 'çğıöşüâî') or any(x.strip().endswith(('mak', 'mek')) for x in meaning.split(',')):
        return 'en'
    return 'tr' if meaning.startswith('to ') else 'en'


out, srcs = sys.argv[1], sys.argv[2:]
ctx, words, examples, phrases, edits, word_drops = [], [], [], [], [], []
seen = set()  # (sheet, row contents) already read from an earlier file


def rows(wb, sheet):
    keep, drop = {'hamit_2026-11-20_v4.xlsx': (V4_KEEP, V4_DROP), 'hamit_2026-11-20_v12.xlsx': (V12_KEEP, set()),
                  'hamit_2026-11-20_v13.xlsx': (V13_KEEP, set()), 'hamit_2026-11-20_v14.xlsx': (V14_KEEP, set()), 'hamit_2026-11-20_v19.xlsx': (V19_KEEP, set())}.get(wb_name, (None, None))
    for i, r in enumerate(wb[sheet].iter_rows(min_row=2, values_only=True), 2):
        r = ['' if v is None else str(v).strip() for v in r]
        if keep is not None and (i not in keep.get(sheet, set()) or i in drop):
            continue
        if any(r) and (sheet, tuple(r)) not in seen and not any(PLACEHOLDER.search(x) for x in r):
            seen.add((sheet, tuple(r)))
            yield i, r


for src in srcs:
    name = wb_name = src.split('/')[-1]
    fx = FIXES.get(name) or dict(ctx_fix={}, ctx_to_phrase=set(), ctx_tr={}, ctx_add=[],
                                 en_split={}, tr_split={}, ex_fix={}, ph_fix={})
    wb = openpyxl.load_workbook(src, data_only=True)

    if 'Yeni filtre ifadeleri' in wb.sheetnames:
        for i, r in rows(wb, 'Yeni filtre ifadeleri'):
            cat, ph, mean, ex, ex_tr = (r + [''] * 5)[:5]
            fix = F17_FIX.get(i, {})
            if fix is None or cat not in F17_CAT:
                continue
            e = {'phrase': ph.lower(), 'lang': 'en', 'meaning': mean, 'ex': ex, 'ex_tr': ex_tr, 'cat': F17_CAT[cat]}
            e.update(fix)
            phrases.append(e)
        continue

    if 'Yeni eşdizimler' in wb.sheetnames:
        for i, r in rows(wb, 'Yeni eşdizimler'):
            ph, mean = r[0].lower(), r[2]
            if ph in F18_DROP or ph.startswith('unexpected ') or ph.endswith('reaction time'):
                continue
            phrases.append({'phrase': ph, 'lang': 'en', 'meaning': F18_MEANING.get(ph, mean), 'ex': '', 'ex_tr': '',
                            'cat': 'collocations'})
        continue

    if 'Örnek cümle önerileri' in wb.sheetnames:
        # An audit sheet: examples for phrases that had none, and phrases to fix or remove.
        ex_fix, ph_edits = AUDIT_FIX[name]
        for i, r in rows(wb, 'Örnek cümle önerileri'):
            if wb['Örnek cümle önerileri'].cell(1, 1).value == 'Kaynak satır':
                r = r[1:]  # sheet 15 starts with the row in the full list
            ph, cat, mean, ex, ex_tr = [str(x or '').strip() for x in (r + [''] * 5)[:5]]
            fix = ex_fix.get(i, {})
            if fix is None or not ph or not (ex or fix.get('ex')):
                continue
            e = {'phrase': re.sub(r'\s*…\s*', ' sb ', ph).strip(), 'lang': 'en', 'meaning': '', 'ex': ex, 'ex_tr': ex_tr}
            e.update(fix)
            phrases.append(e)
        edits += [dict(v, phrase=k) for k, v in ph_edits.items()]
        if name in ('hamit_deyim1_2026-11-20.xlsx', 'hamit_deyim2_2026-11-20.xlsx', 'hamit_deyim3_2026-11-20.xlsx', 'hamit_deyim4_2026-11-20.xlsx'):
            edits += y1_meaning_edits(wb, ph_edits)
        continue

    if 'Kalıplar' in wb.sheetnames and 'Cümlede anlam' not in wb.sheetnames:
        for i, r in rows(wb, 'Kalıplar'):
            cat, ph, lang, mean, forms, sep, ex, ex_tr, note = (r + [''] * 9)[:9]
            if not cat or not ph:
                continue
            fix = {'hamit_filtre_2026-11-20.xlsx': F1_FIX, 'hamit_filtre2_2026-11-20.xlsx': F2_FIX, 'hamit_filtre4_2026-11-20.xlsx': F4_FIX,
                   'hamit_filtre5_2026-11-20.xlsx': F5_FIX, 'hamit_filtre6_2026-11-20.xlsx': F6_FIX,
                   'hamit_filtre7_2026-11-20.xlsx': F7_FIX, 'hamit_filtre8_2026-11-20.xlsx': F8_FIX,
                   'hamit_filtre9_2026-11-20.xlsx': F9_FIX, 'hamit_filtre10_2026-11-20.xlsx': F10_FIX,
                   'hamit_filtre11_2026-11-20.xlsx': F11_FIX, 'hamit_filtre12_2026-11-20.xlsx': F12_FIX}.get(name, {}).get(i, {})
            if cat == 'discourse_markers' and ';' in mean:
                # "bu arada; konu değiştirirken": the part after ";" says when it is used.
                mean, note = [x.strip() for x in mean.split(';', 1)]
            if fix is None:
                continue
            e = {'phrase': ph, 'lang': lang, 'meaning': mean.rstrip('.') if cat == 'chunks' else mean, 'ex': ex, 'ex_tr': ex_tr, 'cat': cat}
            alts = fix.pop('phrases', None) if fix else None
            e.update(fix)
            ph = e['phrase']
            if cat == 'collocations' and name == 'hamit_filtre13_2026-11-20.xlsx':
                # "a faint smile" is also "her faint smile": the article is not part of it.
                ph = re.sub(r'^(?:a|an) ', '', ph)
            if cat == 'dependent_prepositions':
                # "blame someone for something" is matched up to its preposition.
                ph = re.sub(r'(?: doing)? (?:something|someone|a language)$', '', ph)
            if e['ex'].startswith(F1_TEMPLATE):
                e['ex'] = e['ex_tr'] = ''
            if lang == 'tr':
                phrases.append(e)
                continue
            if ' / ' in ph:
                # Two easily mixed words: each one, with the other named (like the false friends).
                a, b = [x.strip() for x in ph.split(' / ', 1)]
                mean2 = e['meaning']
                pair = re.match(rf'{re.escape(a)}:\s*(.*?);\s*{re.escape(b)}:\s*(.*)$', mean2)
                if cat == 'uk_us' and re.search(r'\s*\(UK\b.*\)$', mean2):
                    # "kaldırım (UK: pavement; US: sidewalk)": one meaning for both words.
                    ma = mb = re.sub(r'\s*\(UK\b.*\)$', '', mean2)
                elif pair:
                    # "economic: ekonomiyle ilgili; economical: tasarruflu"
                    ma, mb = pair.group(1).strip(), pair.group(2).strip()
                else:
                    ma, mb = ([x.strip() for x in mean2.split(' / ', 1)] + [mean2])[:2]
                tag = ('UK', 'US') if cat == 'uk_us' else ('', '')
                for w, m, o, om, t, ot in [(a, ma, b, mb, tag[0], tag[1]), (b, mb, a, ma, tag[1], tag[0])]:
                    if w.lower() in F1_SKIP_HALF:
                        continue
                    m2 = f'{m} ({t}; {ot}: {o})' if t else f'{m} (≠ {o}: {om})'
                    phrases.append(dict(e, phrase=w.lower(), meaning=m2))
                continue
            key = ph.lower().strip().rstrip('.')
            # A chunk is matched by its words: "Would you mind if I...?" → "would you mind if i";
            # a gap inside ("not only ... but also") is a wildcard.
            plain = re.sub(r'[\s.!?…]+$', '', key)
            plain = re.sub(r'\s*(?:\.\.\.|…)\s*', ' sth ', plain).strip() if re.search(r'\w\s*(?:\.\.\.|…)\s*\w', plain) else plain
            plain = re.sub(r'\s+', ' ', plain.replace('...', ' ').replace('…', ' ')).strip()
            for p2 in alts or F1_PHRASE.get(key, [plain]):
                phrases.append(dict(e, phrase=p2))
        continue

    # --- Meaning in context
    for i, r in rows(wb, 'Cümlede anlam'):
        sent, form, lemma, lang, mean, note = (r + [''] * 6)[:6]
        if i in fx.get('ctx_drop', ()):
            continue
        if i in fx['ctx_to_phrase']:
            phrases.append({'phrase': 'drop someone a line', 'lang': 'en', 'meaning': 'birine birkaç satır yazmak, haber vermek',
                            'ex': sent, 'ex_tr': 'Eve sağ salim vardığında bana bir haber ver.'})
            continue
        if i in fx.get('ctx_phrase', {}) or (lang == 'en' and ' ' in lemma and i not in fx['ctx_fix']):
            phrases.append({'phrase': fx.get('ctx_phrase', {}).get(i, lemma), 'lang': 'en',
                            'meaning': (fx['ctx_fix'].get(i) or (None,) * 4)[3] or mean, 'ex': sent, 'ex_tr': fx['ctx_tr'].get(i, '')})
            continue
        if i in fx['ctx_fix']:
            s2, f2, l2, m2 = fx['ctx_fix'][i]
            sent, form, lemma, mean = s2 or sent, f2 or form, l2 or lemma, m2 or mean
        ctx.append({'sentence': sent, 'form': form, 'lemma': lemma, 'lang': lang or ('en' if lemma.isascii() else 'tr'),
                    'meaning': mean, 'translation': fx['ctx_tr'].get(i, '')})
    for sent, form, lemma, lang, mean in fx['ctx_add']:
        ctx.append({'sentence': sent, 'form': form, 'lemma': lemma, 'lang': lang, 'meaning': mean, 'translation': ''})

    # --- Words, both directions
    for sheet, lang, split in [('TR-EN kelimeler', 'tr', fx['tr_split']), ('EN-TR kelimeler', 'en', fx['en_split'])]:
        for i, r in rows(wb, sheet):
            w, pos, rank, mean, note, extra = (r + [''] * 6)[:6]
            if any(re.match(r'(?i)yanl[ıi]ş\s*:', str(x or '').strip().replace('I', 'ı')) for x in (note, extra)):
                # "yanlış:" in a note: the dictionary's meaning is wrong and is taken out.
                word_drops.append({'word': w, 'lang': lang, 'meaning': mean})
                continue
            for p, m, n in split.get(i, [(pos, mean, note)]):
                words.append({'word': w, 'lang': lang, 'pos': POS.get(p, p), 'meaning': m, 'note': n})

    # --- Examples
    tr_words = {w['word'] for w in words if w['lang'] == 'tr'} | {c['lemma'] for c in ctx if c['lang'] == 'tr'}
    for i, r in rows(wb, 'Örnek cümleler'):
        w, sense, tr, en, level = (r + [''] * 5)[:5]
        if i in fx['ex_fix'] and fx['ex_fix'][i] is None:
            continue
        e = {'word': w, 'lang': lang_of(w, sense, tr_words), 'meaning': sense, 'tr': tr, 'en': en, 'level': level}
        e.update(fx['ex_fix'].get(i, {}))
        examples.append(e)

    # --- Phrases
    for i, r in rows(wb, 'Deyim ve kalıplar'):
        ph, lang, mean, ex, ex_tr = (r + [''] * 5)[:5]
        e = {'phrase': ph, 'lang': lang, 'meaning': mean, 'ex': ex, 'ex_tr': ex_tr}
        e.update(fx['ph_fix'].get(i, {}))
        phrases.append(e)

    if name == 'hamit_2026-11-20_v20.xlsx':
        # Batman (seen with its examples): the province is in Southeastern Anatolia, not on the Black Sea.
        word_drops.append({'word': 'batman', 'lang': 'tr', 'meaning': 'Batman (a province in the Black Sea region, in northern Turkey)'})
        words.append({'word': 'batman', 'lang': 'tr', 'pos': 'name', 'meaning': 'Batman (a province in Southeastern Anatolia, Turkey)', 'note': ''})

    if name == 'hamit_2026-11-20.xlsx':
        # "run over" is a phrasal verb; its context row also makes it a phrase.
        phrases.append({'phrase': 'run over', 'lang': 'en', 'meaning': 'taşmak',
                        'ex': 'Be careful not to let the bathwater run over.', 'ex_tr': 'Banyo suyunun taşmamasına dikkat et.'})

# A heading renamed by hand: rows of any sheet that use the old one go to the new one.
edits += [dict(v, phrase=k) for k, v in V19_EDITS.items()]
_ren = {e['phrase']: e['to'] for e in edits if e['action'] in ('rename', 'merge')}
for _p in phrases:
    if _p.get('lang') == 'en' and _p['phrase'] in _ren:
        _p['phrase'] = _ren[_p['phrase']]
# A heading an audit deleted is not brought back by an older row that still has it.
_del = {e['phrase'] for e in edits if e['action'] == 'delete'}
print('rows of deleted headings dropped:', sorted({_p['phrase'] for _p in phrases if _p.get('lang') == 'en' and _p['phrase'] in _del}))
phrases = [_p for _p in phrases if not (_p.get('lang') == 'en' and _p['phrase'] in _del)]

data = {'source': 'Storilex contributors (Hamit), ' + ', '.join(s.split('/')[-1] for s in srcs),
        'context': ctx, 'words': words, 'examples': examples, 'phrases': phrases, 'phrase_edits': edits,
        'word_drops': word_drops}
json.dump(data, open(out, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print({k: len(v) for k, v in data.items() if isinstance(v, list)})
