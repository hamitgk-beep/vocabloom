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
         tools/contrib/hamit_2026-11-20_v17.xlsx
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

FIXES = {
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

AUDIT_FIX = {'hamit_denetim19_2026-11-20.xlsx': (D19_EX_FIX, D19_EDITS),
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
ctx, words, examples, phrases, edits = [], [], [], [], []
seen = set()  # (sheet, row contents) already read from an earlier file


def rows(wb, sheet):
    keep, drop = {'hamit_2026-11-20_v4.xlsx': (V4_KEEP, V4_DROP), 'hamit_2026-11-20_v12.xlsx': (V12_KEEP, set()),
                  'hamit_2026-11-20_v13.xlsx': (V13_KEEP, set()), 'hamit_2026-11-20_v14.xlsx': (V14_KEEP, set())}.get(wb_name, (None, None))
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
            if fix is None or not ph:
                continue
            e = {'phrase': re.sub(r'\s*…\s*', ' sb ', ph).strip(), 'lang': 'en', 'meaning': '', 'ex': ex, 'ex_tr': ex_tr}
            e.update(fix)
            phrases.append(e)
        edits += [dict(v, phrase=k) for k, v in ph_edits.items()]
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

    if name == 'hamit_2026-11-20.xlsx':
        # "run over" is a phrasal verb; its context row also makes it a phrase.
        phrases.append({'phrase': 'run over', 'lang': 'en', 'meaning': 'taşmak',
                        'ex': 'Be careful not to let the bathwater run over.', 'ex_tr': 'Banyo suyunun taşmamasına dikkat et.'})

data = {'source': 'Storilex contributors (Hamit), ' + ', '.join(s.split('/')[-1] for s in srcs),
        'context': ctx, 'words': words, 'examples': examples, 'phrases': phrases, 'phrase_edits': edits}
json.dump(data, open(out, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print({k: len(v) for k, v in data.items() if isinstance(v, list)})
