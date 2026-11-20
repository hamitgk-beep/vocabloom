"""Turns a filled-in dictionary sheet (tools/contrib/*.xlsx, the template
sozluk-veri-sablonu.xlsx) into tools/contrib/storilex_contrib.json, which
tools/contrib/apply.py adds to the dictionaries.

The corrections found when the sheet was checked are applied here, so the
original file stays as it was sent:
  - rows that held several different meanings are split, one meaning a row;
  - three wrong meanings are fixed (göze almak, run over, salon takımı);
  - the "meaning in context" sentences get a translation, so they can also be
    shown as examples.

usage: python3 tools/contrib/clean.py tools/contrib/hamit_2026-11-20.xlsx tools/contrib/storilex_contrib.json
"""
import json
import sys

import openpyxl

src, out = sys.argv[1], sys.argv[2]
wb = openpyxl.load_workbook(src, data_only=True)


def rows(sheet):
    for i, r in enumerate(wb[sheet].iter_rows(min_row=2, values_only=True), 2):
        r = ['' if v is None else str(v).strip() for v in r]
        if any(r):
            yield i, r


POS = {'isim': 'noun', 'fiil': 'verb', 'sıfat': 'adj', 'zarf': 'adv', 'zamir': 'pron', 'edat': 'postp',
       'bağlaç': 'conj', 'ünlem': 'intj', 'sayı': 'num', 'deyim': 'phrase', 'kalıp': 'phrase'}

# --- Meaning in context -----------------------------------------------------
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

ctx = []
phrases = []
for i, r in rows('Cümlede anlam'):
    sent, form, lemma, lang, mean, note = (r + [''] * 6)[:6]
    if i in CTX_TO_PHRASE:
        phrases.append({'phrase': 'drop someone a line', 'lang': 'en', 'meaning': 'birine birkaç satır yazmak, haber vermek',
                        'ex': sent, 'ex_tr': 'Eve sağ salim vardığında bana bir haber ver.'})
        continue
    if i in CTX_FIX:
        s2, f2, l2, m2 = CTX_FIX[i]
        sent, form, lemma, mean = s2 or sent, f2 or form, l2 or lemma, m2 or mean
    ctx.append({'sentence': sent, 'form': form, 'lemma': lemma, 'lang': lang or ('en' if lemma.isascii() else 'tr'),
                'meaning': mean, 'translation': CTX_TR.get(i, '')})

# --- Words, both directions -------------------------------------------------
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

words = []
for sheet, lang, split in [('TR-EN kelimeler', 'tr', TR_SPLIT), ('EN-TR kelimeler', 'en', EN_SPLIT)]:
    for i, r in rows(sheet):
        w, pos, rank, mean, note, extra = (r + [''] * 6)[:6]
        parts = split.get(i, [(pos, mean, note)])
        for p, m, n in parts:
            words.append({'word': w, 'lang': lang, 'pos': POS.get(p, p), 'meaning': m, 'note': n})

# --- Examples ---------------------------------------------------------------
EX_EN_FIX = {
    37: 'Our guests are coming to our place for dinner tomorrow.',
    45: 'I always read twenty pages of a book before I go to sleep.',
    80: 'The new fast train cut the journey between the two cities to two hours.',
}
TR_WORDS = {w['word'] for w in words if w['lang'] == 'tr'} | {c['lemma'] for c in ctx if c['lang'] == 'tr'}


def lang_of(word, meaning):
    """Turkish when the word is a known Turkish word or has Turkish letters,
    or when its meaning is written in English."""
    if word in TR_WORDS or any(c in word for c in 'çğıöşüâî'):
        return 'tr'
    if any(c in meaning for c in 'çğıöşüâî') or any(x.strip().endswith(('mak', 'mek')) for x in meaning.split(',')):
        return 'en'
    return 'tr' if meaning.startswith('to ') else 'en'


examples = []
for i, r in rows('Örnek cümleler'):
    w, sense, tr, en, level = (r + [''] * 5)[:5]
    examples.append({'word': w, 'lang': lang_of(w, sense),
                     'meaning': sense, 'tr': tr, 'en': EX_EN_FIX.get(i, en), 'level': level})

# --- Phrases ----------------------------------------------------------------
PH_FIX = {
    10: {'meaning': 'to dare, to risk'},
    27: {'ex': 'Bu konunun üstüne düşersen kısa sürede çözersin.'},
    49: {'phrase': 'gözünü kırpmamak'},
    51: {'meaning': 'to be unable to sleep, to be wide awake'},
}
for i, r in rows('Deyim ve kalıplar'):
    ph, lang, mean, ex, ex_tr = (r + [''] * 5)[:5]
    e = {'phrase': ph, 'lang': lang, 'meaning': mean, 'ex': ex, 'ex_tr': ex_tr}
    e.update(PH_FIX.get(i, {}))
    phrases.append(e)

# "run over" is a phrasal verb; its context row also makes it a phrase.
phrases.append({'phrase': 'run over', 'lang': 'en', 'meaning': 'taşmak', 'ex': 'Be careful not to let the bathwater run over.',
                'ex_tr': 'Banyo suyunun taşmamasına dikkat et.'})

data = {'source': 'Storilex contributors (Hamit), ' + src.split('/')[-1],
        'context': ctx, 'words': words, 'examples': examples, 'phrases': phrases}
json.dump(data, open(out, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print({k: len(v) for k, v in data.items() if isinstance(v, list)})
