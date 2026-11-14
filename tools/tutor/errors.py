#!/usr/bin/env python3
"""Typical mistakes Turkish speakers make in English, with the correct form and
the rule in Turkish. Used to build correction training data whose answers are
known to be right (no teacher model needed).

    python3 tools/tutor/errors.py            # writes data/learner_texts.tsv and data/gold_correct.jsonl

Each pattern is (wrong, right, [(wrong part, right part, reason)]). Slots in
{braces} are filled from SLOTS so every pattern yields several sentences.
"""
import json
import os
import random

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, 'data')

SLOTS = {
    'name': ['Ayşe', 'Mehmet', 'my sister', 'my brother', 'our teacher', 'my friend', 'Can', 'Elif'],
    'place': ['Istanbul', 'Ankara', 'London', 'this city', 'Izmir', 'a small town'],
    'year': ['2015', '2018', '2020', 'last year', 'March'],
    'thing': ['book', 'phone', 'bag', 'car', 'laptop', 'jacket'],
    'food': ['pizza', 'rice', 'fish', 'soup', 'pasta'],
    'subj3': ['He', 'She', 'My father', 'My mother', 'Ali', 'Zeynep'],
}

# (wrong, right, [(wrong part, right part, reason)])
PATTERNS = [
    ('I am agree with you.', 'I agree with you.',
     [('am agree', 'agree', '"agree" bir fiildir; önüne "am" gelmez. Türkçedeki "katılıyorum" yapısı İngilizcede tek fiille kurulur.')]),
    ('{subj3} go to work by bus every day.', '{subj3} goes to work by bus every day.',
     [('go', 'goes', 'Geniş zamanda (Simple Present) he/she/it öznelerinde fiile -s/-es eklenir.')]),
    ('{subj3} don\'t like {food}.', '{subj3} doesn\'t like {food}.',
     [('don\'t', 'doesn\'t', 'He/she/it öznelerinde olumsuz geniş zaman "doesn\'t" ile yapılır.')]),
    ('I am living in {place} since {year}.', 'I have been living in {place} since {year}.',
     [('am living', 'have been living', '"since" ile geçmişte başlayıp hâlâ süren durumlar Present Perfect (Continuous) ile anlatılır; Türkçedeki "-dır yaşıyorum" şimdiki zamanla çevrilmez.')]),
    ('I know {name} for ten years.', 'I have known {name} for ten years.',
     [('know', 'have known', '"for + süre" ile hâlâ devam eden durumlarda Present Perfect kullanılır.')]),
    ('Yesterday I have seen {name}.', 'Yesterday I saw {name}.',
     [('have seen', 'saw', '"yesterday, last week, ago" gibi bitmiş zaman ifadeleriyle Present Perfect değil Simple Past kullanılır.')]),
    ('I didn\'t went to school yesterday.', 'I didn\'t go to school yesterday.',
     [('didn\'t went', 'didn\'t go', '"did/didn\'t" zaten geçmişi gösterir; ardından fiilin yalın hâli (V1) gelir.')]),
    ('Did you saw my {thing}?', 'Did you see my {thing}?',
     [('saw', 'see', 'Soru cümlesinde "did" kullanılınca fiil yalın hâle (V1) döner.')]),
    ('{name} said me the truth.', '{name} told me the truth.',
     [('said me', 'told me', '"say" doğrudan kişi nesnesi almaz; kişiye söylemek için "tell someone" kullanılır.')]),
    ('Can you explain me this rule?', 'Can you explain this rule to me?',
     [('explain me this rule', 'explain this rule to me', '"explain" kişiyi doğrudan nesne olarak almaz: "explain something to someone".')]),
    ('Please open the light.', 'Please turn on the light.',
     [('open the light', 'turn on the light', 'Işık, televizyon gibi cihazlar için "aç/kapat" karşılığı "turn on / turn off"tur; "open" kapı ve pencere içindir.')]),
    ('I want to make a photo of you.', 'I want to take a photo of you.',
     [('make a photo', 'take a photo', 'Fotoğraf çekmek "take a photo" eşdizimiyle söylenir.')]),
    ('We discussed about the problem.', 'We discussed the problem.',
     [('discussed about', 'discussed', '"discuss" geçişli bir fiildir, "about" almaz (ama "talk about" doğrudur).')]),
    ('{name} is married with a doctor.', '{name} is married to a doctor.',
     [('married with', 'married to', '"evli olmak" İngilizcede "be married to someone" kalıbıyla kurulur.')]),
    ('I need some informations.', 'I need some information.',
     [('informations', 'information', '"information" sayılamayan bir isimdir; çoğul eki almaz.')]),
    ('She gave me many advices.', 'She gave me a lot of advice.',
     [('many advices', 'a lot of advice', '"advice" sayılamaz; "many" yerine "a lot of / much" kullanılır, çoğul yapılmaz.')]),
    ('The people is waiting outside.', 'The people are waiting outside.',
     [('is', 'are', '"people" çoğul anlamlıdır, çoğul fiil alır.')]),
    ('My brother is more taller than me.', 'My brother is taller than me.',
     [('more taller', 'taller', 'Tek heceli sıfatlar -er ile karşılaştırılır; "more" ile birlikte kullanılmaz.')]),
    ('This is the most good {food} in {place}.', 'This is the best {food} in {place}.',
     [('most good', 'best', '"good" düzensizdir: good, better, the best.')]),
    ('I will can help you tomorrow.', 'I will be able to help you tomorrow.',
     [('will can', 'will be able to', 'İki modal fiil yan yana gelmez; gelecekte yetenek için "will be able to" kullanılır.')]),
    ('Do you know where is the station?', 'Do you know where the station is?',
     [('where is the station', 'where the station is', 'Dolaylı sorularda (Do you know…, Can you tell me…) özne fiilden önce gelir.')]),
    ('According to me, this film is boring.', 'In my opinion, this film is boring.',
     [('According to me', 'In my opinion', '"according to" başkalarının görüşü için kullanılır; kendi görüşünüz için "In my opinion" veya "I think" denir.')]),
    ('I am very boring today.', 'I am very bored today.',
     [('boring', 'bored', '-ed sıfatları hissi (sıkıldım), -ing sıfatları sebebi (sıkıcı) anlatır.')]),
    ('I am waiting you for an hour.', 'I have been waiting for you for an hour.',
     [('am waiting you', 'have been waiting for you', '"wait" nesneyi "for" ile alır; süre bildiren "for an hour" ile Present Perfect Continuous kullanılır.')]),
    ('I have been in {place} two years ago.', 'I was in {place} two years ago.',
     [('have been', 'was', '"ago" bitmiş bir geçmiş zamanı gösterir; Simple Past kullanılır.')]),
    ('I am 25 years.', 'I am 25 years old.',
     [('25 years', '25 years old', 'Yaş söylerken "years old" denir ya da yalnızca "I am 25." denir.')]),
    ('{name} has 30 years old.', '{name} is 30 years old.',
     [('has', 'is', 'İngilizcede yaş "have" ile değil "be" ile söylenir.')]),
    ('There is many cars on the street.', 'There are many cars on the street.',
     [('There is', 'There are', 'Çoğul isimlerle "there are" kullanılır.')]),
    ('I have a question to you.', 'I have a question for you.',
     [('to you', 'for you', '"question" kişiyi "for" ile alır: a question for you.')]),
    ('I go to home after work.', 'I go home after work.',
     [('to home', 'home', '"home" yön bildirirken "to" almaz: go home, come home.')]),
    ('{subj3} is a engineer.', '{subj3} is an engineer.',
     [('a engineer', 'an engineer', 'Ünlü sesle başlayan kelimelerden önce "an" kullanılır.')]),
    ('{subj3} is teacher.', '{subj3} is a teacher.',
     [('is teacher', 'is a teacher', 'Tekil sayılabilir meslek isimlerinden önce "a/an" gerekir; Türkçede bu tanımlık yoktur.')]),
    ('I like the music very much, especially the jazz.', 'I like music very much, especially jazz.',
     [('the music', 'music', 'Genel anlamda konuşulan soyut isimler "the" almaz.'), ('the jazz', 'jazz', 'Müzik türleri genel anlamda "the" almaz.')]),
    ('I very like {food}.', 'I like {food} very much.',
     [('very like', 'like … very much', '"very" fiili nitelemez; "like something very much" ya da "really like" denir.')]),
    ('If I will have time, I will call you.', 'If I have time, I will call you.',
     [('If I will have', 'If I have', 'Birinci tip koşulda "if" tarafında gelecek zaman değil geniş zaman kullanılır.')]),
    ('If I would be rich, I would travel.', 'If I were rich, I would travel.',
     [('would be', 'were', 'İkinci tip koşulda "if" tarafında "would" kullanılmaz; "if I were" denir.')]),
    ('I look forward to see you.', 'I look forward to seeing you.',
     [('to see', 'to seeing', '"look forward to" kalıbındaki "to" bir edattır; ardından fiil -ing alır.')]),
    ('I am used to wake up early.', 'I am used to waking up early.',
     [('to wake', 'to waking', '"be used to" (alışkın olmak) kalıbından sonra -ing gelir.')]),
    ('{name} let me to use the {thing}.', '{name} let me use the {thing}.',
     [('let me to use', 'let me use', '"let someone do": "let"ten sonra "to" kullanılmaz.')]),
    ('I made him to laugh.', 'I made him laugh.',
     [('made him to laugh', 'made him laugh', '"make someone do" kalıbında "to" kullanılmaz.')]),
    ('I enjoy to read books.', 'I enjoy reading books.',
     [('enjoy to read', 'enjoy reading', '"enjoy" fiilinden sonra -ing gelir.')]),
    ('I want that you come with me.', 'I want you to come with me.',
     [('want that you come', 'want you to come', '"want" kalıbı "want someone to do something"tır; "that" yan cümlesi kullanılmaz.')]),
    ('I listen music every morning.', 'I listen to music every morning.',
     [('listen music', 'listen to music', '"listen" nesnesini "to" ile alır.')]),
    ('We arrived to {place} at night.', 'We arrived in {place} at night.',
     [('arrived to', 'arrived in', '"arrive" şehir ve ülkeler için "in", bina ve noktalar için "at" alır; "to" almaz.')]),
    ('I am good in English.', 'I am good at English.',
     [('good in', 'good at', 'Bir konuda iyi olmak "good at" ile söylenir.')]),
    ('It depends of the weather.', 'It depends on the weather.',
     [('depends of', 'depends on', '"depend" edatı "on"dır.')]),
    ('I am interesting in history.', 'I am interested in history.',
     [('interesting', 'interested', 'İlgi duyan kişi "interested", ilgi çeken şey "interesting"tir.')]),
    ('{subj3} can speaks English.', '{subj3} can speak English.',
     [('can speaks', 'can speak', 'Modal fiillerden sonra fiil her zaman yalın hâldedir; -s almaz.')]),
    ('{subj3} must to finish the report.', '{subj3} must finish the report.',
     [('must to finish', 'must finish', '"must" modaldır; ardından "to" gelmez (ama "have to" doğrudur).')]),
    ('I have went there many times.', 'I have gone there many times.',
     [('have went', 'have gone', 'Present Perfect "have + V3" ile kurulur: go – went – gone.')]),
    ('I born in {year}.', 'I was born in {year}.',
     [('I born', 'I was born', '"doğmak" İngilizcede edilgen yapıyla söylenir: be born.')]),
    ('My {thing} was stolen yesterday by somebody.', 'My {thing} was stolen yesterday.',
     [('by somebody', '', 'Edilgen cümlede yapan belli değilse "by somebody" eklenmez; doğal değildir.')]),
    ('{subj3} is working here since {year}.', '{subj3} has been working here since {year}.',
     [('is working', 'has been working', '"since" ile başlayıp süren eylemlerde Present Perfect Continuous kullanılır.')]),
    ('How many money do you have?', 'How much money do you have?',
     [('How many', 'How much', '"money" sayılamaz; "how much" ile sorulur.')]),
    ('I didn\'t understand nothing.', 'I didn\'t understand anything.',
     [('nothing', 'anything', 'İngilizcede çift olumsuz kullanılmaz; olumsuz fiilden sonra "anything" gelir.')]),
    ('Everybody are happy.', 'Everybody is happy.',
     [('are', 'is', '"everybody, everyone, nobody" tekil fiil alır.')]),
    ('I have two brother.', 'I have two brothers.',
     [('two brother', 'two brothers', 'Türkçede sayıdan sonra isim tekil kalır ama İngilizcede çoğul eki alır.')]),
    ('I am going to the school by foot.', 'I am going to school on foot.',
     [('the school', 'school', 'Okula öğrenci olarak gitmek "go to school" ile söylenir, "the" almaz.'), ('by foot', 'on foot', 'Yürüyerek gitmek "on foot" ile söylenir.')]),
    ('Can I borrow you my {thing}?', 'Can I lend you my {thing}?',
     [('borrow you', 'lend you', '"borrow" ödünç almak, "lend" ödünç vermektir.')]),
    ('I learned him English.', 'I taught him English.',
     [('learned him', 'taught him', 'Birine bir şey öğretmek "teach", kendin öğrenmek "learn"dür.')]),
    ('I will call you when I will arrive.', 'I will call you when I arrive.',
     [('when I will arrive', 'when I arrive', '"when, as soon as, before, after" ile kurulan zaman yan cümlelerinde gelecek zaman yerine geniş zaman kullanılır.')]),
    ('I have finished my homework yesterday.', 'I finished my homework yesterday.',
     [('have finished', 'finished', '"yesterday" bitmiş bir zamanı gösterir; Simple Past kullanılır.')]),
    ('She is speaking three languages.', 'She speaks three languages.',
     [('is speaking', 'speaks', 'Kalıcı durumlar ve yetenekler şimdiki zamanla değil geniş zamanla anlatılır.')]),
    ('I am knowing the answer.', 'I know the answer.',
     [('am knowing', 'know', '"know, like, want, believe" gibi durum fiilleri genellikle -ing almaz.')]),
    ('I wish I can fly.', 'I wish I could fly.',
     [('can', 'could', 'Şimdiki zamanla ilgili gerçek dışı dileklerde "wish"ten sonra bir zaman geri gidilir: can → could.')]),
    ('It is raining since this morning.', 'It has been raining since this morning.',
     [('is raining', 'has been raining', '"since this morning" hâlâ süren bir eylem bildirir; Present Perfect Continuous gerekir.')]),
]

CORRECT = [
    'I have been learning English for two years.',
    'If I had more time, I would read more books.',
    'She told me that she would come later.',
    'We went to the cinema last weekend.',
    'Could you tell me where the nearest pharmacy is?',
    'I am looking forward to hearing from you.',
    'He has lived in Izmir since he was a child.',
    'They usually have breakfast at eight.',
    'I would rather stay at home tonight.',
    'This is the most interesting book I have ever read.',
]

TURKISH = [
    ('Yarın sinemaya gidelim mi?', 'Shall we go to the cinema tomorrow?'),
    ('Bu kitabı çok sevdim.', 'I really loved this book.'),
    ('Ne zamandır burada yaşıyorsun?', 'How long have you been living here?'),
    ('Keşke daha erken gelseydin.', 'I wish you had come earlier.'),
]


def fill(text, choice):
    for k, v in choice.items():
        text = text.replace('{%s}' % k, v)
    return text


def gold_answer(right, errors, natural=None):
    lines = ['**Doğru hâli:** %s' % right, '**Hatalar:**']
    for w, r, why in errors:
        lines.append('- %s → %s: %s' % (w, r if r else '(çıkarılır)', why))
    if natural:
        lines.append('**Daha doğal:** %s' % natural)
    return '\n'.join(lines)


def build(per_pattern=3, seed=7):
    rnd = random.Random(seed)
    rows = []
    for pi, (wrong, right, errs) in enumerate(PATTERNS):
        seen = set()
        for k in range(per_pattern * 3):
            choice = {s: rnd.choice(v) for s, v in SLOTS.items()}
            w = fill(wrong, choice)
            if w in seen:
                continue
            seen.add(w)
            r = fill(right, choice)
            e = [(fill(a, choice), fill(b, choice), why) for a, b, why in errs]
            # Lower-case variants without the final full stop, as people type on phones.
            if rnd.random() < 0.25:
                w = w[0].lower() + w[1:].rstrip('.')
            rows.append(('err-%d-%d' % (pi, len(seen)), w, gold_answer(r, e)))
            if len(seen) >= per_pattern:
                break
    for i, s in enumerate(CORRECT):
        rows.append(('ok-%d' % i, s, '**Doğru hâli:** %s\n**Hatalar:** Hata yok, tebrikler!' % s))
    for i, (tr, en) in enumerate(TURKISH):
        rows.append(('tr-%d' % i, tr, None if en is None else '**Doğru hâli:** %s\n**Hatalar:** Türkçe yazdın; '
                     'İngilizcesi yukarıdaki gibidir.' % en))
    # Two mistakes in one text, so the model learns to list each.
    for i in range(40):
        (w1, r1, e1), (w2, r2, e2) = rnd.sample(PATTERNS, 2)
        choice = {s: rnd.choice(v) for s, v in SLOTS.items()}
        w = fill(w1, choice) + ' ' + fill(w2, choice)
        r = fill(r1, choice) + ' ' + fill(r2, choice)
        e = [(fill(a, choice), fill(b, choice), why) for a, b, why in e1 + e2]
        rows.append(('err2-%d' % i, w, gold_answer(r, e)))
    return rows


def main():
    os.makedirs(DATA, exist_ok=True)
    rows = build()
    with open(os.path.join(DATA, 'learner_texts.tsv'), 'w', encoding='utf-8') as f:
        for id_, text, _ in rows:
            f.write('%s\t%s\n' % (id_, text))
    with open(os.path.join(DATA, 'gold_correct.jsonl'), 'w', encoding='utf-8') as f:
        for id_, text, ans in rows:
            if ans:
                f.write(json.dumps({'id': id_, 'answer': ans}, ensure_ascii=False) + '\n')
    print('learner texts', len(rows), 'patterns', len(PATTERNS))


if __name__ == '__main__':
    main()
