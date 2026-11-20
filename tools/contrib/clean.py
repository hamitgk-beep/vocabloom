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
         tools/contrib/hamit_2026-11-20_v3.xlsx tools/contrib/hamit_filtre_2026-11-20.xlsx
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

FIXES = {
    'hamit_2026-11-20.xlsx': dict(ctx_fix=CTX_FIX, ctx_to_phrase=CTX_TO_PHRASE, ctx_tr=CTX_TR, ctx_add=[],
                                  en_split=EN_SPLIT, tr_split=TR_SPLIT, ex_fix={i: {'en': e} for i, e in EX_EN_FIX.items()},
                                  ph_fix=PH_FIX),
    'hamit_2026-11-20_v2.xlsx': dict(ctx_fix=V2_CTX_FIX, ctx_to_phrase=set(), ctx_tr={}, ctx_add=V2_CTX_ADD,
                                     en_split=V2_EN_SPLIT, tr_split=V2_TR_SPLIT, ex_fix=V2_EX_FIX, ph_fix=V2_PH_FIX),
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
F1_SKIP_HALF = {'lift', 'flat', 'gas', 'line', 'fall', 'do'}
# Sentences made from one pattern for every row say nothing about the phrase.
F1_TEMPLATE = ('They discussed ', 'The report highlighted the importance of ')
F1_PHRASE = {"i am afraid ...": ["i am afraid", "i'm afraid"], 'may i ...?': ['may i'],
             'i would appreciate it if ...': ['i would appreciate it if']}


def lang_of(word, meaning, tr_words):
    """Turkish when the word is a known Turkish word or has Turkish letters,
    or when its meaning is written in English."""
    if word in tr_words or any(c in word for c in 'çğıöşüâî'):
        return 'tr'
    if any(c in meaning for c in 'çğıöşüâî') or any(x.strip().endswith(('mak', 'mek')) for x in meaning.split(',')):
        return 'en'
    return 'tr' if meaning.startswith('to ') else 'en'


out, srcs = sys.argv[1], sys.argv[2:]
ctx, words, examples, phrases = [], [], [], []
seen = set()  # (sheet, row contents) already read from an earlier file


def rows(wb, sheet):
    for i, r in enumerate(wb[sheet].iter_rows(min_row=2, values_only=True), 2):
        r = ['' if v is None else str(v).strip() for v in r]
        if any(r) and (sheet, tuple(r)) not in seen and not any(PLACEHOLDER.search(x) for x in r):
            seen.add((sheet, tuple(r)))
            yield i, r


for src in srcs:
    name = src.split('/')[-1]
    fx = FIXES.get(name) or dict(ctx_fix={}, ctx_to_phrase=set(), ctx_tr={}, ctx_add=[],
                                 en_split={}, tr_split={}, ex_fix={}, ph_fix={})
    wb = openpyxl.load_workbook(src, data_only=True)

    if 'Kalıplar' in wb.sheetnames and 'Cümlede anlam' not in wb.sheetnames:
        for i, r in rows(wb, 'Kalıplar'):
            cat, ph, lang, mean, forms, sep, ex, ex_tr, note = (r + [''] * 9)[:9]
            if not cat or not ph:
                continue
            fix = F1_FIX.get(i, {}) if name == 'hamit_filtre_2026-11-20.xlsx' else {}
            if fix is None:
                continue
            e = {'phrase': ph, 'lang': lang, 'meaning': mean, 'ex': ex, 'ex_tr': ex_tr, 'cat': cat}
            e.update(fix)
            if e['ex'].startswith(F1_TEMPLATE):
                e['ex'] = e['ex_tr'] = ''
            if lang == 'tr':
                phrases.append(e)
                continue
            if ' / ' in ph:
                # Two easily mixed words: each one, with the other named (like the false friends).
                a, b = [x.strip() for x in ph.split(' / ', 1)]
                ma, mb = ([x.strip() for x in e['meaning'].split(' / ', 1)] + [e['meaning']])[:2]
                tag = ('UK', 'US') if cat == 'uk_us' else ('', '')
                for w, m, o, om, t, ot in [(a, ma, b, mb, tag[0], tag[1]), (b, mb, a, ma, tag[1], tag[0])]:
                    if w.lower() in F1_SKIP_HALF:
                        continue
                    m2 = f'{m} ({t}; {ot}: {o})' if t else f'{m} (≠ {o}: {om})'
                    phrases.append(dict(e, phrase=w.lower(), meaning=m2))
                continue
            key = ph.lower().strip()
            for p2 in F1_PHRASE.get(key, [key.replace('...', '').strip(' ?').strip()]):
                phrases.append(dict(e, phrase=p2))
        continue

    # --- Meaning in context
    for i, r in rows(wb, 'Cümlede anlam'):
        sent, form, lemma, lang, mean, note = (r + [''] * 6)[:6]
        if i in fx['ctx_to_phrase']:
            phrases.append({'phrase': 'drop someone a line', 'lang': 'en', 'meaning': 'birine birkaç satır yazmak, haber vermek',
                            'ex': sent, 'ex_tr': 'Eve sağ salim vardığında bana bir haber ver.'})
            continue
        if i in fx.get('ctx_phrase', {}):
            phrases.append({'phrase': fx['ctx_phrase'][i], 'lang': 'en', 'meaning': mean, 'ex': sent, 'ex_tr': ''})
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
        'context': ctx, 'words': words, 'examples': examples, 'phrases': phrases}
json.dump(data, open(out, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print({k: len(v) for k, v in data.items() if isinstance(v, list)})
