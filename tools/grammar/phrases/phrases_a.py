# Grammar lessons for the expression groups that used to sit in the
# "Sözlük" tab (phrasal verbs, collocations, ...). Part A.
# Merged into assets/grammar/lessons*.json by tools/add_phrase_lessons.py.
#
# Translation: (Turkish, [answers], note_tr, note_en)
# Gap:         (gap sentence, Turkish meaning, [answers], note_tr, note_en)

TOPICS = []

TOPICS.append(dict(
    id='phrasal_verbs', category='phrases', level='B1', dict_category='phrasal_verbs', after='comparison',
    title_tr='Phrasal verb\'ler (öbek fiiller: give up, look after)', title_en='Phrasal Verbs',
    explanation_tr=(
        "**Phrasal verb nedir?** Bir fiilin bir ya da iki küçük kelimeyle (up, out, off, on, down, away, back …) birleşip çoğu zaman yeni bir anlam kazandığı fiillerdir: give (vermek) + up = **give up** (vazgeçmek, bırakmak).\n"
        "- Anlamı parçalardan tahmin edilemeyebilir, bu yüzden tek bir kelime gibi öğrenilir: look after (bakmak, ilgilenmek), run out of (tükenmek), put off (ertelemek).\n"
        "- **Ayrılabilenler:** nesne araya girebilir: turn off the light = turn the light off. Nesne bir zamirse (it, them, him) mutlaka araya girer: turn **it** off (turn off it değil).\n"
        "- **Ayrılmayanlar:** nesne hep sonda kalır: look after **the baby**, get over **it**.\n"
        "- **Nesnesizler:** The plane took off. (Uçak kalktı.) The car broke down. (Araba bozuldu.)\n"
        "- **Üç parçalılar:** look forward to, run out of, get along with, come up with.\n"
        "- Zaman ve kişi eki fiile gelir, parçacık değişmez: gave up, has given up, she gives up.\n"
        "- Okurken Filtreler'den **Phrasal Verbs**'ü açarsan kitaptaki bütün phrasal verb'ler renkli altı çizili görünür."),
    explanation_en=(
        "**What is a phrasal verb?** A verb joined with one or two small words (up, out, off, on, down, away, back …) that often gets a new meaning: give + up = **give up** (stop doing something).\n"
        "- The meaning often cannot be guessed from the parts, so learn it like a single word: look after (take care of), run out of (have none left), put off (postpone).\n"
        "- **Separable:** the object can go in the middle: turn off the light = turn the light off. A pronoun object (it, them, him) must go in the middle: turn **it** off (not turn off it).\n"
        "- **Inseparable:** the object always comes last: look after **the baby**, get over **it**.\n"
        "- **Without an object:** The plane took off. The car broke down.\n"
        "- **Three-part verbs:** look forward to, run out of, get along with, come up with.\n"
        "- Tense and person endings go on the verb, the particle never changes: gave up, has given up, she gives up.\n"
        "- Turn on **Phrasal Verbs** in the reader's Filters to see every phrasal verb in a book underlined in colour."),
    structure_tr=['Fiil + parçacık: give up, take off', 'Fiil + nesne + parçacık: turn the TV off / turn it off', 'Fiil + parçacık + edat + nesne: look forward to the weekend'],
    structure_en=['Verb + particle: give up, take off', 'Verb + object + particle: turn the TV off / turn it off', 'Verb + particle + preposition + object: look forward to the weekend'],
    examples=[('She gave up smoking last year.', 'Geçen yıl sigarayı bıraktı.'),
              ('Could you turn the music down, please?', 'Müziğin sesini kısar mısın lütfen?'),
              ('We ran out of milk.', 'Sütümüz bitti.')],
    aliases=['phrasal verb', 'phrasal verbs', 'phrasal', 'pharsal verb', 'pharshal verb', 'öbek fiil', 'öbek fiiller', 'deyimsel fiil'],
    tr=[
        ('Sigarayı bırakmaya karar verdim.', ['I decided to give up smoking.', 'I have decided to give up smoking.', "I've decided to give up smoking."],
         'give up + -ing: bırakmak, vazgeçmek.', 'give up + -ing: stop doing something.'),
        ('Lütfen ışığı kapat.', ['Please turn off the light.', 'Please turn the light off.', 'Please switch off the light.', 'Please switch the light off.', 'Turn off the light, please.', 'Turn the light off, please.'],
         'turn off / switch off: kapatmak. Nesne araya da girebilir.', 'turn off / switch off: the object can also go in the middle.'),
        ('Bu formu doldurup bana geri verir misin?', ['Can you fill in this form and give it back to me?', 'Could you fill in this form and give it back to me?', 'Can you fill out this form and give it back to me?', 'Could you fill out this form and give it back to me?'],
         'fill in / fill out: doldurmak. Zamir araya girer: give it back.', 'fill in / fill out; a pronoun goes in the middle: give it back.'),
        ('Kardeşime bakmam gerekiyor.', ['I have to look after my brother.', 'I need to look after my brother.', 'I have to look after my sister.', 'I need to look after my sister.', 'I have to take care of my brother.', 'I have to take care of my sister.'],
         'look after: bakmak, ilgilenmek. Ayrılmaz, nesne sonda kalır.', 'look after: take care of. It is inseparable, the object comes last.'),
        ('Toplantıyı gelecek haftaya erteledik.', ['We put off the meeting until next week.', 'We put the meeting off until next week.', 'We put off the meeting to next week.', 'We put the meeting off to next week.', 'We postponed the meeting until next week.'],
         'put off: ertelemek.', 'put off: postpone.'),
        ('Arabamız otoyolda bozuldu.', ['Our car broke down on the motorway.', 'Our car broke down on the highway.', 'Our car broke down on the freeway.'],
         'break down: bozulmak. Nesne almaz.', 'break down: stop working. It takes no object.'),
        ('Uçak tam zamanında kalktı.', ['The plane took off on time.', 'The plane took off right on time.', 'The plane took off exactly on time.'],
         'take off: (uçak) kalkmak. take → took.', 'take off: leave the ground. take → took.'),
        ('Ayakkabılarını çıkar lütfen.', ['Take off your shoes, please.', 'Please take off your shoes.', 'Take your shoes off, please.', 'Please take your shoes off.'],
         "take off: (giysi) çıkarmak. Aynı phrasal verb'ün ikinci anlamı.", 'take off: remove (clothes). The second meaning of the same phrasal verb.'),
        ('Kahvemiz bitti.', ['We have run out of coffee.', "We've run out of coffee.", 'We ran out of coffee.'],
         'run out of: tükenmek, bitmek. Üç parçalıdır.', 'run out of: have none left. It has three parts.'),
        ('Tatili dört gözle bekliyorum.', ['I am looking forward to the holiday.', "I'm looking forward to the holiday.", 'I am looking forward to the vacation.', "I'm looking forward to the vacation."],
         'look forward to + isim: dört gözle beklemek.', 'look forward to + noun.'),
        ('Seni görmeyi dört gözle bekliyorum.', ['I am looking forward to seeing you.', "I'm looking forward to seeing you.", 'I look forward to seeing you.'],
         'look forward to + -ing: buradaki to edattır, arkasından fiil -ing alır.', 'look forward to + -ing: "to" is a preposition here, so the verb takes -ing.'),
        ('Bu kelimeye sözlükte bak.', ['Look up this word in the dictionary.', 'Look this word up in the dictionary.'],
         'look up: (sözlükte, listede) aramak.', 'look up: find in a dictionary or list.'),
        ('Komşularımızla iyi geçiniyoruz.', ['We get along well with our neighbours.', 'We get on well with our neighbours.', 'We get along well with our neighbors.', 'We get on well with our neighbors.', 'We get along with our neighbours.', 'We get along with our neighbors.'],
         'get along with / get on with: biriyle iyi geçinmek.', 'get along with / get on with: have a good relationship.'),
        ('Harika bir fikir buldu.', ['He came up with a great idea.', 'She came up with a great idea.', 'He came up with a brilliant idea.', 'She came up with a brilliant idea.'],
         'come up with: (fikir, çözüm) bulmak, ortaya atmak.', 'come up with: think of an idea or a solution.'),
        ('Her sabah altıda kalkarım.', ['I get up at six every morning.', 'I get up at 6 every morning.', 'Every morning I get up at six.'],
         'get up: yataktan kalkmak. wake up ise uyanmak demektir.', 'get up: leave your bed. wake up means stop sleeping.'),
        ('Çocuklar büyüdü ve evden ayrıldı.', ['The children grew up and left home.', 'The kids grew up and left home.', 'The children have grown up and left home.', 'The kids have grown up and left home.'],
         'grow up: büyümek (çocukluktan çıkmak). grow → grew.', 'grow up: become an adult. grow → grew.'),
    ],
    gaps=[
        ("Don't give ___! You can do it.", 'Pes etme! Yapabilirsin.', ['up'], 'give up: pes etmek.', 'give up: stop trying.'),
        ("Can you turn the radio ___? It's too loud.", 'Radyonun sesini kısar mısın? Çok yüksek.', ['down'], 'turn down: sesini kısmak. Tersi turn up.', 'turn down: make quieter. The opposite is turn up.'),
        ('My grandmother looks ___ my little sister when my parents are at work.', 'Annemle babam işteyken büyükannem küçük kız kardeşime bakıyor.', ['after'], 'look after: bakmak, ilgilenmek.', 'look after: take care of.'),
        ('The plane took ___ at nine o\'clock.', 'Uçak saat dokuzda kalktı.', ['off'], 'take off: (uçak) kalkmak.', 'take off: leave the ground.'),
        ('We have run out ___ sugar.', 'Şekerimiz bitti.', ['of'], 'run out of: üç parçalı phrasal verb.', 'run out of: a three-part phrasal verb.'),
        ("I'm looking forward ___ meeting you.", 'Seninle tanışmayı dört gözle bekliyorum.', ['to'], 'look forward to + -ing.', 'look forward to + -ing.'),
        ("If you don't know the word, look it ___.", 'Kelimeyi bilmiyorsan sözlükten bak.', ['up'], 'look up; zamir araya girer: look it up.', 'look up; the pronoun goes in the middle: look it up.'),
        ('Please fill ___ this form.', 'Lütfen bu formu doldurun.', ['in', 'out'], 'fill in / fill out: doldurmak.', 'fill in / fill out: complete a form.'),
        ('She ___ up with a clever solution.', 'Akıllıca bir çözüm buldu.', ['came'], 'come up with; geçmiş zamanda come → came.', 'come up with; in the past come → came.'),
        ('Our car broke ___ on the way to the airport.', 'Arabamız havalimanına giderken bozuldu.', ['down'], 'break down: bozulmak.', 'break down: stop working.'),
        ('I ___ up at seven every day.', 'Her gün yedide kalkarım.', ['get'], 'get up: yataktan kalkmak.', 'get up: leave your bed.'),
        ('Can you pick me ___ from the station?', 'Beni istasyondan alabilir misin?', ['up'], 'pick up: (arabayla) birini almak.', 'pick up: collect someone, usually by car.'),
    ],
))

TOPICS.append(dict(
    id='collocations', category='phrases', level='B1', dict_category='collocations', after='phrasal_verbs',
    title_tr='Eşdizimler (make a decision, heavy rain)', title_en='Collocations',
    explanation_tr=(
        "**Eşdizim (collocation) nedir?** Anadili İngilizce olanların hep birlikte kullandığı kelime çiftleridir. Bir kural değil, alışkanlıktır; ama yanlış seçilen kelime cümleyi hemen yabancı gösterir.\n"
        "- **make / do:** make a decision, make a mistake, make money, make friends, make a mess · do homework, do the shopping, do a favour, do your best, do business.\n"
        "- **have / take:** have breakfast, have a shower, have a good time · take a photo, take a break, take a risk, take an exam.\n"
        "- **Sıfat + isim:** heavy rain (yoğun yağmur, strong rain değil), heavy traffic, strong coffee, high price, deep sleep.\n"
        "- **Zarf + sıfat / fiil:** highly recommended (şiddetle tavsiye edilen), deeply sorry (çok üzgün), fully aware (tamamen farkında), sleep soundly (deliksiz uyumak).\n"
        "- Türkçeden kelime kelime çevirmek çoğu zaman yanlış eşdizim üretir: \"fotoğraf çekmek\" = take a photo (pull değil), \"hata yapmak\" = make a mistake (do değil), \"para kazanmak\" = make / earn money (win değil).\n"
        "- Yeni bir isim öğrenirken hangi fiil ve sıfatla kullanıldığını da birlikte öğren.\n"
        "- Okurken Filtreler'den **Collocations**'ı açarsan kitaptaki eşdizimler renkli altı çizili görünür."),
    explanation_en=(
        "**What is a collocation?** Words that native speakers always use together. It is a habit, not a rule, but the wrong word makes a sentence sound foreign at once.\n"
        "- **make / do:** make a decision, make a mistake, make money, make friends, make a mess · do homework, do the shopping, do a favour, do your best, do business.\n"
        "- **have / take:** have breakfast, have a shower, have a good time · take a photo, take a break, take a risk, take an exam.\n"
        "- **Adjective + noun:** heavy rain (not strong rain), heavy traffic, strong coffee, high price, deep sleep.\n"
        "- **Adverb + adjective / verb:** highly recommended, deeply sorry, fully aware, sleep soundly.\n"
        "- Translating word for word from Turkish often gives the wrong partner: take a photo (not pull), make a mistake (not do), make / earn money (not win).\n"
        "- When you learn a new noun, learn the verbs and adjectives that go with it.\n"
        "- Turn on **Collocations** in the reader's Filters to see them underlined in colour in a book."),
    structure_tr=['Fiil + isim: make a decision, take a photo', 'Sıfat + isim: heavy rain, strong coffee', 'Zarf + sıfat: highly recommended, deeply sorry'],
    structure_en=['Verb + noun: make a decision, take a photo', 'Adjective + noun: heavy rain, strong coffee', 'Adverb + adjective: highly recommended, deeply sorry'],
    examples=[('I made a mistake in the exam.', 'Sınavda bir hata yaptım.'),
              ('We had a great time at the party.', 'Partide çok iyi vakit geçirdik.'),
              ('There was heavy rain all night.', 'Bütün gece yoğun yağmur vardı.')],
    aliases=['collocation', 'collocations', 'eşdizim', 'eşdizimler', 'make or do', 'make do'],
    tr=[
        ('Önemli bir karar verdim.', ['I made an important decision.', 'I have made an important decision.', "I've made an important decision."],
         'karar vermek = make a decision.', 'make a decision.'),
        ('Ödevimi henüz yapmadım.', ["I haven't done my homework yet.", 'I have not done my homework yet.'],
         'ödev yapmak = do homework (make değil).', 'do homework (not make).'),
        ('Sınavda iki hata yaptım.', ['I made two mistakes in the exam.', 'I made two mistakes on the exam.', 'I made two mistakes in the test.', 'I made two mistakes on the test.'],
         'hata yapmak = make a mistake (do değil).', 'make a mistake (not do).'),
        ('Bir fotoğrafımızı çeker misiniz?', ['Could you take a photo of us?', 'Can you take a photo of us?', 'Could you take a picture of us?', 'Can you take a picture of us?', 'Would you take a photo of us?'],
         'fotoğraf çekmek = take a photo.', 'take a photo.'),
        ('Mola verelim.', ["Let's take a break.", 'Let us take a break.', "Let's have a break."],
         'mola vermek = take / have a break.', 'take / have a break.'),
        ('Tatilde harika vakit geçirdik.', ['We had a great time on holiday.', 'We had a great time on vacation.', 'We had a wonderful time on holiday.', 'We had a wonderful time on vacation.'],
         'iyi vakit geçirmek = have a good / great time.', 'have a good / great time.'),
        ('Her sabah duş alırım.', ['I have a shower every morning.', 'I take a shower every morning.', 'Every morning I have a shower.', 'Every morning I take a shower.'],
         'duş almak = have / take a shower.', 'have / take a shower.'),
        ('Bana bir iyilik yapar mısın?', ['Can you do me a favour?', 'Could you do me a favour?', 'Can you do me a favor?', 'Could you do me a favor?', 'Will you do me a favour?', 'Will you do me a favor?'],
         'iyilik yapmak = do someone a favour.', 'do someone a favour.'),
        ('Dün gece yoğun yağmur yağdı.', ['There was heavy rain last night.', 'It rained heavily last night.', 'We had heavy rain last night.'],
         'yoğun yağmur = heavy rain (strong rain değil).', 'heavy rain (not strong rain).'),
        ('Sert kahveyi severim.', ['I like strong coffee.', 'I love strong coffee.'],
         'sert kahve = strong coffee (hard coffee değil).', 'strong coffee (not hard coffee).'),
        ('Bu restoranı şiddetle tavsiye ederim.', ['I highly recommend this restaurant.', 'I would highly recommend this restaurant.', "I'd highly recommend this restaurant.", 'I strongly recommend this restaurant.'],
         'şiddetle tavsiye etmek = highly recommend.', 'highly recommend.'),
        ('Geç kaldığım için çok üzgünüm.', ['I am deeply sorry for being late.', "I'm deeply sorry for being late.", "I'm very sorry for being late.", "I'm really sorry for being late.", "I'm so sorry for being late.", "I'm very sorry I'm late.", "I'm sorry for being late."],
         'deeply sorry: çok üzgün. very / really sorry da doğaldır.', 'deeply sorry; very / really sorry are natural too.'),
        ('Yeni okulunda arkadaş edindi mi?', ['Has he made friends at his new school?', 'Has she made friends at her new school?', 'Did he make friends at his new school?', 'Did she make friends at her new school?'],
         'arkadaş edinmek = make friends.', 'make friends.'),
        ('Elimden geleni yapacağım.', ['I will do my best.', "I'll do my best."],
         'elinden geleni yapmak = do your best.', 'do your best.'),
        ('Bu işte çok para kazanıyor.', ['She makes a lot of money in this job.', 'He makes a lot of money in this job.', 'She earns a lot of money in this job.', 'He earns a lot of money in this job.'],
         'para kazanmak = make / earn money (win değil).', 'make / earn money (not win).'),
        ('Gelecek hafta bir sınava gireceğim.', ['I am going to take an exam next week.', "I'm going to take an exam next week.", 'I will take an exam next week.', "I'll take an exam next week.", "I'm taking an exam next week.", 'I am taking an exam next week.'],
         'sınava girmek = take an exam (enter değil).', 'take an exam (not enter).'),
    ],
    gaps=[
        ("Don't worry, everybody ___ mistakes.", 'Merak etme, herkes hata yapar.', ['makes'], 'make a mistake; everybody tekil sayılır: makes.', 'make a mistake; everybody is singular: makes.'),
        ('Have you ___ your homework?', 'Ödevini yaptın mı?', ['done'], 'do homework; have + V3: done.', 'do homework; have + V3: done.'),
        ('Can I ___ a photo of you?', 'Fotoğrafını çekebilir miyim?', ['take'], 'take a photo.', 'take a photo.'),
        ('We ___ a great time at the concert.', 'Konserde harika vakit geçirdik.', ['had'], 'have a great time; geçmişte had.', 'have a great time; past: had.'),
        ('There was ___ traffic on the way home.', 'Eve dönerken yoğun trafik vardı.', ['heavy'], 'heavy traffic: yoğun trafik.', 'heavy traffic.'),
        ('I need to ___ a decision today.', 'Bugün bir karar vermem gerekiyor.', ['make'], 'make a decision.', 'make a decision.'),
        ('This hotel is ___ recommended.', 'Bu otel şiddetle tavsiye ediliyor.', ['highly'], 'highly recommended.', 'highly recommended.'),
        ('Could you ___ me a favour?', 'Bana bir iyilik yapar mısın?', ['do'], 'do someone a favour.', 'do someone a favour.'),
        ('I always drink ___ coffee in the morning.', 'Sabahları hep sert kahve içerim.', ['strong'], 'strong coffee.', 'strong coffee.'),
        ("Let's ___ a short break.", 'Kısa bir mola verelim.', ['take', 'have'], 'take / have a break.', 'take / have a break.'),
        ('She ___ friends very easily.', 'Çok kolay arkadaş edinir.', ['makes'], 'make friends; she → makes.', 'make friends; she → makes.'),
        ("I'll ___ my best to help you.", 'Sana yardım etmek için elimden geleni yapacağım.', ['do'], 'do your best.', 'do your best.'),
    ],
))

TOPICS.append(dict(
    id='prepositional_phrases', category='phrases', level='B1', dict_category='prepositional_phrases', after='collocations',
    title_tr='Edatlı öbekler (on time, by mistake, at last)', title_en='Prepositional Phrases',
    explanation_tr=(
        "**Edatlı öbek nedir?** Bir edatla (at, in, on, by, out of, under …) başlayan ve bir bütün olarak kullanılan kalıplardır. Edatın anlamından tahmin edilemedikleri için hazır öğrenilir.\n"
        "- **in:** in time (geç kalmadan, yetişerek), in fact (aslında), in a hurry (acele içinde), in charge of (-den sorumlu), in danger (tehlikede).\n"
        "- **on:** on time (tam zamanında), on purpose (bilerek, kasten), on foot (yürüyerek), on holiday (tatilde), on fire (yanıyor).\n"
        "- **at:** at last (sonunda), at least (en azından), at first (ilk başta), at once (hemen), at the moment (şu anda).\n"
        "- **by:** by mistake (yanlışlıkla), by chance (tesadüfen), by heart (ezbere), by car / by bus (arabayla, otobüsle).\n"
        "- **out of / under / for:** out of order (bozuk), out of date (eskimiş), under pressure (baskı altında), for sure (kesinlikle), for a while (bir süre).\n"
        "- **Dikkat:** on time = tam saatinde, in time = yetişerek, geç kalmadan. by car ama **on foot**.\n"
        "- Okurken Filtreler'den **Prepositional Phrases**'i açarsan kitaptaki bu kalıplar renkli altı çizili görünür."),
    explanation_en=(
        "**What is a prepositional phrase?** A fixed expression that starts with a preposition (at, in, on, by, out of, under …) and is used as a whole. You cannot guess it from the preposition, so learn it ready-made.\n"
        "- **in:** in time (early enough), in fact, in a hurry, in charge of, in danger.\n"
        "- **on:** on time (at the planned time), on purpose (deliberately), on foot, on holiday, on fire.\n"
        "- **at:** at last, at least, at first, at once (immediately), at the moment.\n"
        "- **by:** by mistake, by chance, by heart (from memory), by car / by bus.\n"
        "- **out of / under / for:** out of order (broken), out of date, under pressure, for sure, for a while.\n"
        "- **Careful:** on time = at the planned time, in time = early enough. by car but **on foot**.\n"
        "- Turn on **Prepositional Phrases** in the reader's Filters to see them underlined in colour in a book."),
    structure_tr=['Edat + isim: on time, by mistake, at last', 'Edat + isim + edat: in charge of, in front of'],
    structure_en=['Preposition + noun: on time, by mistake, at last', 'Preposition + noun + preposition: in charge of, in front of'],
    examples=[('The train arrived on time.', 'Tren tam zamanında geldi.'),
              ('I deleted the file by mistake.', 'Dosyayı yanlışlıkla sildim.'),
              ('At last, the holidays have started!', 'Sonunda tatil başladı!')],
    aliases=['prepositional phrase', 'prepositional phrases', 'edatlı öbek', 'edatlı öbekler', 'edatlı ifadeler'],
    tr=[
        ('Tren tam zamanında geldi.', ['The train arrived on time.', 'The train came on time.'],
         'on time: tam zamanında, planlanan saatte.', 'on time: at the planned time.'),
        ('Filme yetiştik.', ['We got there in time for the film.', 'We arrived in time for the film.', 'We got there in time for the movie.', 'We arrived in time for the movie.', 'We were in time for the film.', 'We were in time for the movie.'],
         'in time (for): geç kalmadan, yetişerek.', 'in time (for): early enough.'),
        ('Bunu bilerek yapmadım.', ["I didn't do it on purpose.", 'I did not do it on purpose.', "I didn't do that on purpose.", 'I did not do that on purpose.'],
         'on purpose: bilerek, kasten.', 'on purpose: deliberately.'),
        ('Yanlışlıkla senin şemsiyeni aldım.', ['I took your umbrella by mistake.', 'I took your umbrella by accident.', 'I accidentally took your umbrella.'],
         'by mistake: yanlışlıkla.', 'by mistake: in error.'),
        ('Okula yürüyerek giderim.', ['I go to school on foot.', 'I walk to school.'],
         'on foot: yürüyerek (by foot değil).', 'on foot (not by foot).'),
        ('Genellikle işe otobüsle giderim.', ['I usually go to work by bus.', 'I usually travel to work by bus.', 'I usually get to work by bus.'],
         'by bus / by car / by train: ulaşım aracıyla.', 'by bus / by car / by train.'),
        ('Sonunda evdeyiz!', ['At last we are home!', 'At last, we are home!', "At last we're home!", "At last, we're home!", "We're home at last!", 'We are home at last!'],
         'at last: sonunda (uzun bir beklemeden sonra).', 'at last: finally, after a long wait.'),
        ('En azından denedin.', ['At least you tried.', 'At least, you tried.'],
         'at least: en azından.', 'at least.'),
        ('Şu anda çok meşgulüm.', ['I am very busy at the moment.', "I'm very busy at the moment.", "At the moment I'm very busy.", "At the moment, I'm very busy.", "I'm very busy right now.", 'I am very busy right now.'],
         'at the moment: şu anda.', 'at the moment: now.'),
        ('Asansör bozuk.', ['The lift is out of order.', 'The elevator is out of order.'],
         'out of order: bozuk, çalışmıyor.', 'out of order: not working.'),
        ('Bu şiiri ezbere biliyor.', ['She knows this poem by heart.', 'He knows this poem by heart.'],
         'by heart: ezbere.', 'by heart: from memory.'),
        ('Eski bir arkadaşla tesadüfen karşılaştım.', ['I met an old friend by chance.', 'I ran into an old friend by chance.', 'I bumped into an old friend by chance.', 'By chance, I met an old friend.'],
         'by chance: tesadüfen.', 'by chance: not planned.'),
        ('Bu projeden kim sorumlu?', ['Who is in charge of this project?', "Who's in charge of this project?"],
         'in charge of: -den sorumlu.', 'in charge of: responsible for.'),
        ('Aslında onu hiç sevmedim.', ['In fact, I never liked him.', 'In fact I never liked him.', 'In fact, I never liked her.', 'In fact I never liked her.', 'In fact, I never liked it.', 'Actually, I never liked him.', 'Actually, I never liked her.', 'Actually, I never liked it.'],
         'in fact: aslında, gerçekte.', 'in fact: actually.'),
        ('Çok baskı altında çalışıyor.', ['She works under a lot of pressure.', 'He works under a lot of pressure.', 'She is working under a lot of pressure.', 'He is working under a lot of pressure.', 'She works under great pressure.', 'He works under great pressure.'],
         'under pressure: baskı altında.', 'under pressure.'),
        ('Ailemle tatildeyim.', ['I am on holiday with my family.', "I'm on holiday with my family.", 'I am on vacation with my family.', "I'm on vacation with my family."],
         'on holiday: tatilde.', 'on holiday: on vacation.'),
    ],
    gaps=[
        ('The bus was late, but we arrived ___ time for the start of the show.', 'Otobüs gecikti ama gösterinin başına yetiştik.', ['in'], 'in time: geç kalmadan, yetişerek.', 'in time: early enough.'),
        ('Our flight left exactly ___ time.', 'Uçağımız tam zamanında kalktı.', ['on'], 'on time: planlanan saatte.', 'on time: at the planned time.'),
        ('Sorry, I sent the email to you ___ mistake.', 'Özür dilerim, e-postayı yanlışlıkla sana gönderdim.', ['by'], 'by mistake: yanlışlıkla.', 'by mistake.'),
        ('He broke the window ___ purpose.', 'Camı bilerek kırdı.', ['on'], 'on purpose: bilerek.', 'on purpose.'),
        ('We walked there ___ foot.', 'Oraya yürüyerek gittik.', ['on'], 'on foot (by foot değil).', 'on foot (not by foot).'),
        ('___ last, the rain has stopped.', 'Sonunda yağmur durdu.', ['At'], 'at last: sonunda.', 'at last.'),
        ('You should sleep ___ least eight hours a night.', 'Gecede en az sekiz saat uyumalısın.', ['at'], 'at least: en az, en azından.', 'at least.'),
        ('Sorry, this machine is out ___ order.', 'Üzgünüm, bu makine bozuk.', ['of'], 'out of order: bozuk.', 'out of order: broken.'),
        ('I learned the song ___ heart.', 'Şarkıyı ezberledim.', ['by'], 'by heart: ezbere.', 'by heart.'),
        ('Ms Green is ___ charge of the sales team.', 'Satış ekibinden Bayan Green sorumlu.', ['in'], 'in charge of: -den sorumlu.', 'in charge of.'),
        ('She is always ___ a hurry.', 'Hep acele içinde.', ['in'], 'in a hurry: acele içinde.', 'in a hurry.'),
        ("I'm sorry, he isn't here ___ the moment.", 'Üzgünüm, kendisi şu anda burada değil.', ['at'], 'at the moment: şu anda.', 'at the moment.'),
    ],
))

TOPICS.append(dict(
    id='idioms', category='phrases', level='B2', dict_category='idioms', after='prepositional_phrases',
    title_tr='Deyimler (break the ice, a piece of cake)', title_en='Idioms',
    explanation_tr=(
        "**Deyim (idiom) nedir?** Kelimelerin tek tek anlamından çıkarılamayan, mecazi anlamlı kalıplardır. \"It's raining cats and dogs\" kedi köpek yağdığını değil, **bardaktan boşanırcasına yağdığını** anlatır.\n"
        "- Kelime kelime çevrilmez; Türkçede aynı anlamı veren deyim aranır: break the ice = buzları eritmek, a piece of cake = çocuk oyuncağı, cost an arm and a leg = dudak uçuklatacak kadar pahalı olmak.\n"
        "- **Kalıp sabittir:** kelimelerin seçimi ve sırası değişmez (break the ice, break the snow değil). Ama fiil zamana göre çekimlenir: She **broke** the ice. It **cost** an arm and a leg.\n"
        "- İçindeki iyelik sözcükleri özneye uyar: make up **my** mind, make up **her** mind.\n"
        "- Çoğu günlük konuşmada kullanılır, resmî yazıda daha az geçer.\n"
        "- Sık kullanılanlar: under the weather (keyifsiz, hafif hasta), hit the books (ders çalışmaya oturmak), call it a day (bugünlük paydos etmek), once in a blue moon (kırk yılda bir), let the cat out of the bag (sırrı ağzından kaçırmak), keep an eye on (göz kulak olmak), get cold feet (son anda cesaretini kaybetmek), on cloud nine (havalara uçmak), make ends meet (iki yakasını bir araya getirmek).\n"
        "- Okurken Filtreler'den **Idioms**'u açarsan kitaptaki deyimler renkli altı çizili görünür."),
    explanation_en=(
        "**What is an idiom?** A fixed expression with a figurative meaning that you cannot work out from the single words. \"It's raining cats and dogs\" means **it is raining very heavily**.\n"
        "- Do not translate word for word; look for a Turkish idiom with the same meaning: break the ice = buzları eritmek, a piece of cake = çocuk oyuncağı.\n"
        "- **The words are fixed:** you cannot change or reorder them (break the ice, not break the snow). But the verb changes with the tense: She **broke** the ice. It **cost** an arm and a leg.\n"
        "- Possessive words follow the subject: make up **my** mind, make up **her** mind.\n"
        "- Most idioms belong to everyday speech and are less common in formal writing.\n"
        "- Common ones: under the weather (slightly ill), hit the books (study hard), call it a day (stop working for today), once in a blue moon (very rarely), let the cat out of the bag (tell a secret by accident), keep an eye on (watch), get cold feet (lose courage at the last moment), on cloud nine (very happy), make ends meet (have just enough money to live).\n"
        "- Turn on **Idioms** in the reader's Filters to see them underlined in colour in a book."),
    structure_tr=['Sabit kalıp; fiil zamana göre çekimlenir: break the ice → broke the ice', 'İyelik özneye uyar: make up my / your / her mind'],
    structure_en=['Fixed words; the verb changes with the tense: break the ice → broke the ice', 'Possessives follow the subject: make up my / your / her mind'],
    examples=[('The exam was a piece of cake.', 'Sınav çocuk oyuncağıydı.'),
              ("I'm feeling a bit under the weather today.", 'Bugün biraz keyifsizim.'),
              ('We only eat out once in a blue moon.', 'Kırk yılda bir dışarıda yemek yeriz.')],
    aliases=['idiom', 'idioms', 'idoms', 'deyim', 'deyimler'],
    tr=[
        ('Sınav çocuk oyuncağıydı.', ['The exam was a piece of cake.', 'The test was a piece of cake.'],
         'a piece of cake: çok kolay, çocuk oyuncağı.', 'a piece of cake: very easy.'),
        ('Bardaktan boşanırcasına yağmur yağıyor.', ['It is raining cats and dogs.', "It's raining cats and dogs."],
         'rain cats and dogs: çok şiddetli yağmak.', 'rain cats and dogs: rain very heavily.'),
        ('Bugün biraz keyifsizim.', ["I'm feeling a bit under the weather today.", 'I am feeling a bit under the weather today.', "I'm a bit under the weather today.", 'I am a bit under the weather today.', 'I feel a bit under the weather today.'],
         'under the weather: keyifsiz, hafif hasta.', 'under the weather: slightly ill.'),
        ('Bu araba dudak uçuklatacak kadar pahalıydı.', ['This car cost an arm and a leg.', 'The car cost an arm and a leg.'],
         'cost an arm and a leg: çok pahalı olmak. cost → cost.', 'cost an arm and a leg: be very expensive. cost → cost.'),
        ('Buzları eritmek için bir şaka yaptı.', ['He told a joke to break the ice.', 'She told a joke to break the ice.', 'He made a joke to break the ice.', 'She made a joke to break the ice.'],
         'break the ice: buzları eritmek, ortamı yumuşatmak.', 'break the ice: make people feel relaxed.'),
        ('Bugünlük paydos edelim.', ["Let's call it a day.", 'Let us call it a day.'],
         'call it a day: o günlük işi bırakmak.', 'call it a day: stop working for today.'),
        ('Sınavdan önce ders çalışmaya oturmam lazım.', ['I need to hit the books before the exam.', 'I have to hit the books before the exam.', 'I must hit the books before the exam.'],
         'hit the books: sıkı ders çalışmak.', 'hit the books: study hard.'),
        ('Kırk yılda bir sinemaya gideriz.', ['We go to the cinema once in a blue moon.', 'We go to the movies once in a blue moon.', 'We only go to the cinema once in a blue moon.', 'We only go to the movies once in a blue moon.'],
         'once in a blue moon: çok nadiren, kırk yılda bir.', 'once in a blue moon: very rarely.'),
        ('Sırrı ağzından kaçırdı.', ['He let the cat out of the bag.', 'She let the cat out of the bag.'],
         'let the cat out of the bag: sırrı ağzından kaçırmak.', 'let the cat out of the bag: tell a secret by accident.'),
        ('Ben yokken çantama göz kulak olur musun?', ["Can you keep an eye on my bag while I'm away?", "Could you keep an eye on my bag while I'm away?", 'Can you keep an eye on my bag while I am away?', 'Could you keep an eye on my bag while I am away?', "Will you keep an eye on my bag while I'm away?", "Can you keep an eye on my bag while I'm gone?", "Could you keep an eye on my bag while I'm gone?"],
         'keep an eye on: göz kulak olmak.', 'keep an eye on: watch, look after.'),
        ('Düğünden önce son anda cesaretini kaybetti.', ['He got cold feet before the wedding.', 'She got cold feet before the wedding.'],
         'get cold feet: son anda korkup vazgeçmek.', 'get cold feet: lose courage at the last moment.'),
        ('İşi alınca havalara uçtu.', ['When she got the job, she was on cloud nine.', 'When he got the job, he was on cloud nine.', 'She was on cloud nine when she got the job.', 'He was on cloud nine when he got the job.'],
         'on cloud nine: havalara uçmak, çok mutlu olmak.', 'on cloud nine: extremely happy.'),
        ('Henüz karar vermedim.', ["I haven't made up my mind yet.", 'I have not made up my mind yet.', "I haven't made my mind up yet."],
         'make up your mind: karar vermek. İyelik özneye uyar: my mind.', 'make up your mind: decide. The possessive follows the subject: my mind.'),
        ('Tam üstüne bastın.', ['You hit the nail on the head.', "You've hit the nail on the head.", 'You have hit the nail on the head.'],
         'hit the nail on the head: tam isabet, tam doğrusunu söylemek.', 'hit the nail on the head: say exactly the right thing.'),
        ('İki yakalarını bir araya getirmekte zorlanıyorlar.', ['They are struggling to make ends meet.', "They're struggling to make ends meet.", 'They find it hard to make ends meet.', 'They have trouble making ends meet.', 'They find it difficult to make ends meet.'],
         'make ends meet: geçinebilmek, iki yakasını bir araya getirmek.', 'make ends meet: have just enough money to live.'),
        ('Bol şans! Sahnede harika olacaksın.', ["Break a leg! You'll be great on stage.", 'Break a leg! You will be great on stage.', "Break a leg, you'll be great on stage.", 'Break a leg, you will be great on stage.'],
         'break a leg: bol şans (özellikle sahneye çıkacak birine).', 'break a leg: good luck (especially before a performance).'),
    ],
    gaps=[
        ("Don't worry, the test will be a piece of ___.", 'Merak etme, sınav çocuk oyuncağı olacak.', ['cake'], 'a piece of cake: çok kolay.', 'a piece of cake: very easy.'),
        ("Take an umbrella; it's raining cats and ___.", 'Şemsiye al, bardaktan boşanırcasına yağıyor.', ['dogs'], 'rain cats and dogs.', 'rain cats and dogs.'),
        ("I'm not coming to work today; I'm a bit under the ___.", 'Bugün işe gelmiyorum, biraz rahatsızım.', ['weather'], 'under the weather: hafif hasta.', 'under the weather: slightly ill.'),
        ('That new phone cost an arm and a ___.', 'O yeni telefon dudak uçuklatacak kadar pahalıydı.', ['leg'], 'cost an arm and a leg.', 'cost an arm and a leg.'),
        ('She told a funny story to break the ___.', 'Buzları eritmek için komik bir hikâye anlattı.', ['ice'], 'break the ice.', 'break the ice.'),
        ("It's late. Let's ___ it a day.", 'Geç oldu. Bugünlük paydos edelim.', ['call'], 'call it a day.', 'call it a day.'),
        ('We see our cousins once in a blue ___.', 'Kuzenlerimizi kırk yılda bir görürüz.', ['moon'], 'once in a blue moon.', 'once in a blue moon.'),
        ('Who let the ___ out of the bag about the party?', 'Partiyi ağzından kim kaçırdı?', ['cat'], 'let the cat out of the bag.', 'let the cat out of the bag.'),
        ('Please keep an ___ on the children.', 'Lütfen çocuklara göz kulak ol.', ['eye'], 'keep an eye on.', 'keep an eye on.'),
        ('He was going to ask her out, but he got cold ___.', 'Ona çıkma teklif edecekti ama son anda cesaretini kaybetti.', ['feet'], 'get cold feet.', 'get cold feet.'),
        ("I can't make up my ___: the red one or the blue one?", 'Karar veremiyorum: kırmızı mı mavi mi?', ['mind'], 'make up your mind: karar vermek.', 'make up your mind: decide.'),
        ('You hit the ___ on the head!', 'Tam üstüne bastın!', ['nail'], 'hit the nail on the head.', 'hit the nail on the head.'),
    ],
))
