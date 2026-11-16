# Grammar lessons for the expression groups that used to sit in the
# "Sözlük" tab. Part B. Same format as grammar_phrases_a.py.

TOPICS = []

TOPICS.append(dict(
    id='proverbs', category='phrases', level='B2', dict_category='proverbs', after='idioms',
    title_tr='Atasözleri ve deyişler (Practice makes perfect)', title_en='Proverbs and Sayings',
    explanation_tr=(
        "**Atasözü (proverb) nedir?** Kuşaktan kuşağa aktarılan, bir öğüt ya da genel bir doğru anlatan kısa sözlerdir. Deyimden farkı: deyim cümlenin bir parçasıdır (break the ice), atasözü ise kendi başına tam bir cümledir (Practice makes perfect.).\n"
        "- Kelime kelime çevrilmez; Türkçede aynı öğüdü veren atasözü aranır: Better late than never = Geç olsun, güç olmasın. Every cloud has a silver lining = Her işte bir hayır vardır. Don't count your chickens before they hatch = Dereyi görmeden paçaları sıvama.\n"
        "- Çoğunlukla **geniş zamanla** (Simple Present) ya da **emir kipiyle** söylenir ve kelimeleri değiştirilmez.\n"
        "- Konuşmada çoğu zaman yalnızca ilk yarısı söylenir: \"Well, when in Rome …\" (Roma'dayken Romalılar gibi davran).\n"
        "- Sık kullanılanlar: Actions speak louder than words (Söz değil, iş önemli), Practice makes perfect (İşleye işleye demir ışıldar), No pain, no gain (Emek olmadan yemek olmaz), Where there's a will, there's a way (İsteyen dağları deler), Two heads are better than one (Akıl akıldan üstündür), Don't judge a book by its cover (Görünüşe aldanma), There's no smoke without fire (Ateş olmayan yerden duman çıkmaz).\n"
        "- Okurken Filtreler'den **Proverbs & Sayings**'i açarsan kitaptaki atasözleri renkli altı çizili görünür."),
    explanation_en=(
        "**What is a proverb?** A short saying passed down the generations that gives advice or states a general truth. An idiom is part of a sentence (break the ice); a proverb is a full sentence on its own (Practice makes perfect.).\n"
        "- Do not translate word for word; find the Turkish proverb with the same advice: Better late than never = Geç olsun, güç olmasın. Every cloud has a silver lining = Her işte bir hayır vardır.\n"
        "- Proverbs are mostly in the **Simple Present** or the **imperative**, and their words never change.\n"
        "- In speech people often say only the first half: \"Well, when in Rome …\".\n"
        "- Common ones: Actions speak louder than words, Practice makes perfect, No pain, no gain, Where there's a will, there's a way, Two heads are better than one, Don't judge a book by its cover, There's no smoke without fire.\n"
        "- Turn on **Proverbs & Sayings** in the reader's Filters to see them underlined in colour in a book."),
    structure_tr=['Kendi başına tam cümle, çoğunlukla geniş zaman: Practice makes perfect.', 'Emir kipiyle öğüt: Don\'t judge a book by its cover.'],
    structure_en=['A full sentence, usually Simple Present: Practice makes perfect.', 'Advice in the imperative: Don\'t judge a book by its cover.'],
    examples=[('Practice makes perfect, so keep reading every day.', 'İşleye işleye demir ışıldar, o yüzden her gün okumaya devam et.'),
              ('You finally came! Better late than never.', 'Sonunda geldin! Geç olsun, güç olmasın.')],
    aliases=['proverb', 'proverbs', 'sayings', 'proverbs and sayings', 'atasözü', 'atasözleri', 'deyişler'],
    tr=[
        ('Geç olsun, güç olmasın.', ['Better late than never.'], 'Better late than never: geç kalmak hiç yapmamaktan iyidir.', 'Better late than never.'),
        ('İşleye işleye demir ışıldar.', ['Practice makes perfect.'], 'Practice makes perfect: pratik yaptıkça ustalaşırsın.', 'Practice makes perfect.'),
        ('Emek olmadan yemek olmaz.', ['No pain, no gain.'], 'No pain, no gain: zahmetsiz kazanç olmaz.', 'No pain, no gain.'),
        ('İsteyen dağları deler.', ["Where there's a will, there's a way.", 'Where there is a will, there is a way.'], 'Where there\'s a will, there\'s a way: gerçekten isteyen yolunu bulur.', "Where there's a will, there's a way."),
        ('Söz değil, iş önemlidir.', ['Actions speak louder than words.'], 'Actions speak louder than words: davranışlar sözlerden çok şey anlatır.', 'Actions speak louder than words.'),
        ('Görünüşe aldanma.', ["Don't judge a book by its cover.", 'Do not judge a book by its cover.'], 'Emir kipiyle bir öğüt: kitabı kapağına göre yargılama.', 'Advice in the imperative.'),
        ('Dereyi görmeden paçaları sıvama.', ["Don't count your chickens before they hatch.", 'Do not count your chickens before they hatch.', "Don't count your chickens before they've hatched."], 'Kelimesi kelimesine: civcivleri yumurtadan çıkmadan sayma.', 'Literally: do not count the chicks before they come out of the eggs.'),
        ('Her işte bir hayır vardır.', ['Every cloud has a silver lining.'], 'Kelimesi kelimesine: her bulutun gümüş bir kenarı vardır.', 'Literally: every cloud has a silver edge.'),
        ('Akıl akıldan üstündür.', ['Two heads are better than one.'], 'Two heads are better than one: iki kafa birden iyidir.', 'Two heads are better than one.'),
        ('Damlaya damlaya göl olur.', ['Every little helps.', 'Little by little, the bird builds its nest.', 'Many a little makes a mickle.', 'Little strokes fell great oaks.'], 'En yaygın karşılığı: Every little helps.', 'The most common English equivalent is "Every little helps."'),
        ('Sakla samanı, gelir zamanı.', ['Waste not, want not.'], 'Waste not, want not: israf etmeyen muhtaç kalmaz.', 'Waste not, want not.'),
        ('Ne ekersen onu biçersin.', ['You reap what you sow.', 'As you sow, so shall you reap.', 'You reap what you sow!'], 'reap: biçmek, sow: ekmek.', 'reap: harvest; sow: plant.'),
        ('Ateş olmayan yerden duman çıkmaz.', ["There's no smoke without fire.", 'There is no smoke without fire.', "Where there's smoke, there's fire.", 'Where there is smoke, there is fire.'], 'Bir söylentinin mutlaka bir nedeni vardır.', 'A rumour always has some reason behind it.'),
        ('Bugünün işini yarına bırakma.', ["Don't put off until tomorrow what you can do today.", "Don't put off till tomorrow what you can do today.", 'Never put off until tomorrow what you can do today.', 'Never put off till tomorrow what you can do today.'], 'put off: ertelemek.', 'put off: postpone.'),
        ('Üzüm üzüme baka baka kararır.', ['Birds of a feather flock together.'], 'Benzer insanlar bir araya gelir.', 'Similar people come together.'),
        ('Bulunduğun yerin âdetlerine uy.', ['When in Rome, do as the Romans do.'], 'Kelimesi kelimesine: Roma\'dayken Romalılar gibi davran.', 'Follow the customs of the place you are in.'),
    ],
    gaps=[
        ('Practice makes ___.', 'İşleye işleye demir ışıldar.', ['perfect'], 'Practice makes perfect.', 'Practice makes perfect.'),
        ('Better late than ___.', 'Geç olsun, güç olmasın.', ['never'], 'Better late than never.', 'Better late than never.'),
        ('No pain, no ___.', 'Emek olmadan yemek olmaz.', ['gain'], 'gain: kazanç.', 'gain: profit, reward.'),
        ('Actions speak louder than ___.', 'Söz değil, iş önemlidir.', ['words'], 'Actions speak louder than words.', 'Actions speak louder than words.'),
        ("Don't judge a book by its ___.", 'Görünüşe aldanma.', ['cover'], 'cover: kapak.', 'cover.'),
        ("Where there's a will, there's a ___.", 'İsteyen dağları deler.', ['way'], 'will: irade, istek; way: yol.', 'will: determination; way: a means.'),
        ('Every cloud has a silver ___.', 'Her işte bir hayır vardır.', ['lining'], 'silver lining: gümüş kenar, umut ışığı.', 'silver lining: a hopeful side.'),
        ('Two heads are better than ___.', 'Akıl akıldan üstündür.', ['one'], 'Two heads are better than one.', 'Two heads are better than one.'),
        ("Don't count your ___ before they hatch.", 'Dereyi görmeden paçaları sıvama.', ['chickens'], 'chickens: tavuklar, civcivler.', 'chickens.'),
        ("There's no smoke without ___.", 'Ateş olmayan yerden duman çıkmaz.', ['fire'], 'There\'s no smoke without fire.', "There's no smoke without fire."),
        ('Birds of a feather flock ___.', 'Üzüm üzüme baka baka kararır.', ['together'], 'flock together: sürü hâlinde bir araya gelmek.', 'flock together: gather in a group.'),
        ('When in ___, do as the Romans do.', 'Bulunduğun yerin âdetlerine uy.', ['Rome'], 'When in Rome, do as the Romans do.', 'When in Rome, do as the Romans do.'),
    ],
))

TOPICS.append(dict(
    id='chunks', category='phrases', level='A2', dict_category='chunks', after='proverbs',
    title_tr='Kalıp ifadeler (It depends, Never mind)', title_en='Chunks (Ready-made Expressions)',
    explanation_tr=(
        "**Chunk (kalıp ifade) nedir?** Günlük konuşmada bütün olarak, hazır bir paket gibi kullanılan ifadelerdir. Dil bilgisini düşünmeden ağızdan çıkarlar; akıcı konuşmanın sırrı büyük ölçüde budur.\n"
        "- **Cevap ve tepki:** It depends. (Duruma göre değişir.) Never mind. (Boş ver, önemli değil.) It's up to you. (Sen bilirsin.) I'm afraid not. (Maalesef hayır.) No wonder! (Şaşmamalı!) Fair enough. (Makul, haklısın.)\n"
        "- **Rica ve teklif:** Would you mind …ing? (… sakıncası var mı?) How about …? (… ne dersin?) Do you fancy …? (Canın … ister mi?) Let me know. (Bana haber ver.)\n"
        "- **Fikir bildirme:** As far as I know (bildiğim kadarıyla), If I were you (yerinde olsam), To be honest (açıkçası), It's not worth it (değmez).\n"
        "- **Cümle başları:** I was wondering if … (Acaba … diye düşünüyordum), The thing is … (Mesele şu ki …).\n"
        "- İçlerindeki dil bilgisi açıklanabilir (If I **were** you, Would you mind **opening**), ama en kolayı onları bütün olarak ezberleyip sık kullanmaktır.\n"
        "- Okurken Filtreler'den **Chunks**'ı açarsan kitaptaki kalıp ifadeler renkli altı çizili görünür."),
    explanation_en=(
        "**What is a chunk?** An expression used as a whole, like a ready-made package, in everyday speech. People say chunks without thinking about grammar, and they are a big part of sounding fluent.\n"
        "- **Answers and reactions:** It depends. Never mind. It's up to you. I'm afraid not. No wonder! Fair enough.\n"
        "- **Requests and offers:** Would you mind …ing? How about …? Do you fancy …? Let me know.\n"
        "- **Giving an opinion:** As far as I know, If I were you, To be honest, It's not worth it.\n"
        "- **Sentence starters:** I was wondering if …, The thing is …\n"
        "- The grammar inside them can be explained (If I **were** you, Would you mind **opening**), but the easiest way is to learn them whole and use them often.\n"
        "- Turn on **Chunks** in the reader's Filters to see them underlined in colour in a book."),
    structure_tr=['Hazır cevap: It depends. / Never mind. / It\'s up to you.', 'Would you mind + V-ing?', 'How about + V-ing / isim?', 'If I were you, I would + V1'],
    structure_en=['Ready-made answer: It depends. / Never mind. / It\'s up to you.', 'Would you mind + V-ing?', 'How about + V-ing / noun?', 'If I were you, I would + V1'],
    examples=[('"Are you coming?" "It depends on the weather."', '"Geliyor musun?" "Havaya bağlı."'),
              ('Would you mind closing the window?', 'Pencereyi kapatır mısınız?'),
              ("If I were you, I'd take the job.", 'Yerinde olsam o işi kabul ederdim.')],
    aliases=['chunk', 'chunks', 'kalıp ifade', 'kalıp ifadeler', 'hazır ifadeler', 'günlük ifadeler'],
    tr=[
        ('Duruma göre değişir.', ['It depends.'], 'It depends: duruma bağlı.', 'It depends.'),
        ('Boş ver, önemli değil.', ["Never mind, it's not important.", "Never mind, it isn't important.", 'Never mind, it is not important.', "Never mind, it doesn't matter.", 'Never mind, it does not matter.'], 'Never mind: boş ver.', 'Never mind.'),
        ('Sen bilirsin.', ["It's up to you.", 'It is up to you.'], 'It\'s up to you: karar senin.', "It's up to you: you decide."),
        ('Pencereyi açmamın sakıncası var mı?', ['Would you mind if I opened the window?', 'Do you mind if I open the window?', 'Would you mind if I open the window?'], 'Do you mind if I …? / Would you mind if I …?: izin isteme.', 'Do you mind if I …? / Would you mind if I …? asks for permission.'),
        ('Kapıyı kapatır mısınız?', ['Would you mind closing the door?', 'Could you close the door?', 'Would you close the door?', 'Can you close the door?', 'Could you shut the door?', 'Would you mind shutting the door?'], 'Would you mind + -ing: kibar rica.', 'Would you mind + -ing: a polite request.'),
        ('Yerinde olsam ona söylerdim.', ['If I were you, I would tell her.', "If I were you, I'd tell her.", 'If I were you, I would tell him.', "If I were you, I'd tell him.", 'If I were you I would tell her.', "If I were you I'd tell her.", 'If I were you I would tell him.', "If I were you I'd tell him."], 'If I were you: yerinde olsam (was değil were).', 'If I were you (were, not was).'),
        ('Bildiğim kadarıyla dükkân pazartesileri kapalı.', ['As far as I know, the shop is closed on Mondays.', 'As far as I know the shop is closed on Mondays.', 'As far as I know, the store is closed on Mondays.', 'As far as I know the store is closed on Mondays.'], 'As far as I know: bildiğim kadarıyla.', 'As far as I know.'),
        ('Açıkçası filmi beğenmedim.', ["To be honest, I didn't like the film.", "To be honest, I didn't like the movie.", "To be honest I didn't like the film.", "To be honest I didn't like the movie.", "Honestly, I didn't like the film.", "Honestly, I didn't like the movie."], 'To be honest: açıkçası.', 'To be honest.'),
        ('Pizza yemeye ne dersin?', ['How about eating pizza?', 'How about having pizza?', 'How about some pizza?', 'How about pizza?', 'What about having pizza?', 'What about pizza?'], 'How about + -ing / isim: öneri.', 'How about + -ing / noun: a suggestion.'),
        ('Karar verince bana haber ver.', ['Let me know when you decide.', 'Let me know when you make a decision.', 'Let me know when you have decided.', "Let me know when you've decided."], 'Let me know: bana haber ver.', 'Let me know.'),
        ('Değmez.', ["It's not worth it.", "It isn't worth it.", 'It is not worth it.'], 'It\'s not worth it: değmez.', "It's not worth it."),
        ('Yorgun olmana şaşmamalı, bütün gece çalıştın.', ["No wonder you're tired; you worked all night.", 'No wonder you are tired; you worked all night.', "No wonder you're tired, you worked all night.", 'No wonder you are tired, you worked all night.', "No wonder you're tired. You worked all night."], 'No wonder: şaşmamalı, belli.', 'No wonder: it is not surprising.'),
        ('Maalesef hayır.', ["I'm afraid not.", 'I am afraid not.'], 'I\'m afraid not: kibar bir "hayır".', "I'm afraid not: a polite no."),
        ('Acaba bana yardım edebilir misin diye düşünüyordum.', ['I was wondering if you could help me.', 'I was wondering whether you could help me.'], 'I was wondering if …: çok kibar rica.', 'I was wondering if …: a very polite request.'),
        ('Mesele şu ki hiç param yok.', ['The thing is, I have no money.', "The thing is, I don't have any money.", "The thing is, I haven't got any money.", 'The thing is I have no money.', "The thing is I don't have any money."], 'The thing is: mesele şu ki.', 'The thing is: the problem is.'),
        ('Canın sinemaya gitmek ister mi?', ['Do you fancy going to the cinema?', 'Do you fancy going to the movies?', 'Would you like to go to the cinema?', 'Would you like to go to the movies?', 'Do you want to go to the cinema?', 'Do you want to go to the movies?'], 'Do you fancy + -ing: canın ister mi.', 'Do you fancy + -ing: would you like to.'),
    ],
    gaps=[
        ('"Will you come?" "It ___ on my work."', '"Gelecek misin?" "İşime bağlı."', ['depends'], 'It depends on …: -e bağlı.', 'It depends on …'),
        ("Never ___, I'll do it myself.", 'Boş ver, kendim yaparım.', ['mind'], 'Never mind.', 'Never mind.'),
        ("It's up ___ you. You choose.", 'Sen bilirsin. Sen seç.', ['to'], "It's up to you.", "It's up to you."),
        ('Would you mind ___ the music down?', 'Müziğin sesini kısar mısın?', ['turning'], 'mind + -ing.', 'mind + -ing.'),
        ("If I ___ you, I'd see a doctor.", 'Yerinde olsam doktora giderdim.', ['were'], 'If I were you (was değil).', 'If I were you (not was).'),
        ('As far as I ___, she lives in London.', 'Bildiğim kadarıyla Londra\'da yaşıyor.', ['know'], 'As far as I know.', 'As far as I know.'),
        ("To be ___, I don't like coffee.", 'Açıkçası kahveyi sevmem.', ['honest'], 'To be honest.', 'To be honest.'),
        ('How about ___ a walk?', 'Yürüyüşe çıkmaya ne dersin?', ['taking', 'going for'], 'How about + -ing.', 'How about + -ing.'),
        ('Let me ___ if you need anything.', 'Bir şeye ihtiyacın olursa bana haber ver.', ['know'], 'Let me know.', 'Let me know.'),
        ("Don't buy it. It's not ___ it.", 'Alma onu. Değmez.', ['worth'], "It's not worth it.", "It's not worth it."),
        ("No ___ he's hungry; he hasn't eaten all day.", 'Aç olmasına şaşmamalı, bütün gün bir şey yemedi.', ['wonder'], 'No wonder.', 'No wonder.'),
        ('I was ___ if you could lend me your car.', 'Acaba arabanı bana ödünç verebilir misin diye düşünüyordum.', ['wondering'], 'I was wondering if …', 'I was wondering if …'),
    ],
))

TOPICS.append(dict(
    id='binomials', category='phrases', level='B2', dict_category='binomials', after='chunks',
    title_tr='İkili kalıplar (safe and sound, sooner or later)', title_en='Binomials',
    explanation_tr=(
        "**İkili kalıp (binomial) nedir?** Genellikle and, or ya da but ile bağlanan ve **sırası hiç değişmeyen** kelime çiftleridir. Türkçedeki \"er geç\", \"aşağı yukarı\", \"az çok\" gibi.\n"
        "- **Sıra sabittir:** salt and pepper (pepper and salt değil), black and white, ladies and gentlemen. Ters sırada söylemek kulağa yanlış gelir. Türkçede sıra farklı olabilir: knife and fork = çatal bıçak.\n"
        "- Bazıları gerçek anlamlıdır: salt and pepper (tuz ve biber), bread and butter (tereyağlı ekmek).\n"
        "- Bazıları mecazi anlam taşır: safe and sound (sağ salim), sick and tired (bıkmış usanmış), sooner or later (er ya da geç), more or less (aşağı yukarı), now and then (ara sıra), pros and cons (artılar ve eksiler), ups and downs (iniş çıkışlar), peace and quiet (huzur ve sükûnet), by and large (genel olarak), first and foremost (her şeyden önce).\n"
        "- Aynı kelimenin tekrarıyla yapılanlar: step by step (adım adım), little by little (azar azar), side by side (yan yana), face to face (yüz yüze).\n"
        "- Okurken Filtreler'den **Binomials**'ı açarsan kitaptaki ikili kalıplar renkli altı çizili görünür."),
    explanation_en=(
        "**What is a binomial?** A pair of words, usually joined by and, or or but, whose **order never changes**.\n"
        "- **The order is fixed:** salt and pepper (not pepper and salt), black and white, ladies and gentlemen. The other order sounds wrong. Turkish may use another order: knife and fork = çatal bıçak.\n"
        "- Some are literal: salt and pepper, bread and butter.\n"
        "- Some have a figurative meaning: safe and sound (unharmed), sick and tired (fed up), sooner or later (eventually), more or less (roughly), now and then (sometimes), pros and cons (advantages and disadvantages), ups and downs (good and bad times), peace and quiet, by and large (in general), first and foremost (most importantly).\n"
        "- Some repeat the same word: step by step, little by little, side by side, face to face.\n"
        "- Turn on **Binomials** in the reader's Filters to see them underlined in colour in a book."),
    structure_tr=['Kelime + and/or/but + kelime, sıra sabit: safe and sound, sooner or later', 'Tekrar: step by step, face to face'],
    structure_en=['Word + and/or/but + word, fixed order: safe and sound, sooner or later', 'Repetition: step by step, face to face'],
    examples=[('The children came home safe and sound.', 'Çocuklar eve sağ salim döndü.'),
              ('Sooner or later, you will have to tell him.', 'Er ya da geç ona söylemek zorunda kalacaksın.')],
    aliases=['binomial', 'binomials', 'ikili kalıp', 'ikili kalıplar', 'kelime çiftleri'],
    tr=[
        ('Çocuklar eve sağ salim döndü.', ['The children came home safe and sound.', 'The children got home safe and sound.', 'The kids came home safe and sound.', 'The kids got home safe and sound.', 'The children returned home safe and sound.'], 'safe and sound: sağ salim.', 'safe and sound: unharmed.'),
        ('Er ya da geç gerçeği öğrenecek.', ['Sooner or later he will learn the truth.', 'Sooner or later, he will learn the truth.', 'Sooner or later she will learn the truth.', 'Sooner or later, she will learn the truth.', "Sooner or later he'll find out the truth.", "Sooner or later, he'll find out the truth.", "Sooner or later she'll find out the truth.", "Sooner or later, she'll find out the truth."], 'sooner or later: er ya da geç (later or sooner değil).', 'sooner or later (not later or sooner).'),
        ('Bu işten bıktım usandım.', ['I am sick and tired of this job.', "I'm sick and tired of this job."], 'sick and tired of: -den bıkmış usanmış.', 'sick and tired of: fed up with.'),
        ('Proje aşağı yukarı bitti.', ['The project is more or less finished.', 'The project is more or less done.', 'The project is more or less complete.'], 'more or less: aşağı yukarı, hemen hemen.', 'more or less: almost.'),
        ('Ara sıra onu ararım.', ['I call him now and then.', 'I call her now and then.', 'I phone him now and then.', 'I phone her now and then.', 'Now and then I call him.', 'Now and then I call her.', 'I call him every now and then.', 'I call her every now and then.'], 'now and then: ara sıra.', 'now and then: sometimes.'),
        ('Bu planın artılarını ve eksilerini konuşalım.', ["Let's discuss the pros and cons of this plan.", "Let's talk about the pros and cons of this plan.", 'Let us discuss the pros and cons of this plan.'], 'pros and cons: artılar ve eksiler.', 'pros and cons: advantages and disadvantages.'),
        ('Her ilişkinin iniş çıkışları vardır.', ['Every relationship has its ups and downs.', 'Every relationship has ups and downs.'], 'ups and downs: iniş çıkışlar.', 'ups and downs: good and bad times.'),
        ('Biraz huzur ve sükûnet istiyorum.', ['I want some peace and quiet.', 'I need some peace and quiet.', "I'd like some peace and quiet.", 'I would like some peace and quiet.'], 'peace and quiet: huzur ve sükûnet.', 'peace and quiet.'),
        ('Hanımefendiler, beyefendiler, hoş geldiniz!', ['Ladies and gentlemen, welcome!', 'Welcome, ladies and gentlemen!'], 'ladies and gentlemen: sıra hep böyledir.', 'ladies and gentlemen: always in this order.'),
        ('Tuzu ve biberi uzatır mısın?', ['Can you pass the salt and pepper?', 'Could you pass the salt and pepper?', 'Can you pass me the salt and pepper?', 'Could you pass me the salt and pepper?', 'Would you pass the salt and pepper?'], 'salt and pepper (pepper and salt değil).', 'salt and pepper (not pepper and salt).'),
        ('Adım adım öğreneceğiz.', ['We will learn step by step.', "We'll learn step by step.", 'We will learn it step by step.', "We'll learn it step by step."], 'step by step: adım adım.', 'step by step.'),
        ('İngilizcem azar azar gelişiyor.', ['Little by little, my English is improving.', 'Little by little my English is improving.', 'My English is improving little by little.', 'My English is getting better little by little.', 'Little by little, my English is getting better.'], 'little by little: azar azar, yavaş yavaş.', 'little by little: slowly.'),
        ('Yan yana oturduk.', ['We sat side by side.', 'We were sitting side by side.'], 'side by side: yan yana.', 'side by side.'),
        ('Bunu yüz yüze konuşmalıyız.', ['We should talk about this face to face.', 'We need to talk about this face to face.', 'We should discuss this face to face.', 'We must talk about this face to face.'], 'face to face: yüz yüze (by değil to).', 'face to face (to, not by).'),
        ('Her şeyden önce hepinize teşekkür etmek istiyorum.', ['First and foremost, I want to thank you all.', 'First and foremost, I would like to thank you all.', "First and foremost, I'd like to thank you all.", 'First and foremost, I want to thank all of you.', "First and foremost, I'd like to thank all of you.", 'First and foremost, I would like to thank all of you.'], 'first and foremost: her şeyden önce.', 'first and foremost: most importantly.'),
        ('Genel olarak toplantı iyi geçti.', ['By and large, the meeting went well.', 'By and large the meeting went well.'], 'by and large: genel olarak.', 'by and large: in general.'),
    ],
    gaps=[
        ('They arrived safe and ___.', 'Sağ salim vardılar.', ['sound'], 'safe and sound.', 'safe and sound.'),
        ("Sooner or ___ you'll have to decide.", 'Er ya da geç karar vermek zorunda kalacaksın.', ['later'], 'sooner or later.', 'sooner or later.'),
        ("I'm sick and ___ of waiting.", 'Beklemekten bıktım usandım.', ['tired'], 'sick and tired of.', 'sick and tired of.'),
        ('The work is more or ___ done.', 'İş aşağı yukarı bitti.', ['less'], 'more or less.', 'more or less.'),
        ('We meet every now and ___.', 'Ara sıra buluşuruz.', ['then'], '(every) now and then.', '(every) now and then.'),
        ('What are the pros and ___ of living in a big city?', 'Büyük şehirde yaşamanın artıları ve eksileri neler?', ['cons'], 'pros and cons.', 'pros and cons.'),
        ('Life is full of ups and ___.', 'Hayat iniş çıkışlarla dolu.', ['downs'], 'ups and downs.', 'ups and downs.'),
        ('Ladies and ___, please take your seats.', 'Hanımefendiler, beyefendiler, lütfen yerlerinize oturun.', ['gentlemen'], 'ladies and gentlemen.', 'ladies and gentlemen.'),
        ('Could you pass the salt and ___?', 'Tuzu ve biberi uzatır mısın?', ['pepper'], 'salt and pepper.', 'salt and pepper.'),
        ("Let's do it step by ___.", 'Adım adım yapalım.', ['step'], 'step by step.', 'step by step.'),
        ('I just want some peace and ___.', 'Sadece biraz huzur ve sükûnet istiyorum.', ['quiet'], 'peace and quiet.', 'peace and quiet.'),
        ('We need to meet face to ___.', 'Yüz yüze görüşmemiz gerekiyor.', ['face'], 'face to face.', 'face to face.'),
    ],
))

TOPICS.append(dict(
    id='false_friends', category='phrases', level='A2', dict_category='false_friends', after='binomials',
    title_tr='Yalancı eşdeğerler (sympathetic ≠ sempatik)', title_en='False Friends',
    explanation_tr=(
        "**Yalancı eşdeğer (false friend) nedir?** Türkçedeki bir kelimeye benzediği için aynı anlama geldiği sanılan ama başka bir şey anlatan İngilizce kelimelerdir. Çoğu Fransızcadan iki dile de geçip farklı anlamlar kazanmıştır.\n"
        "- **sympathetic** = anlayışlı, halden anlayan. Sempatik = **nice, likeable**.\n"
        "- **actual** = gerçek, asıl. Aktüel, güncel = **current**. **actually** = aslında.\n"
        "- **sensible** = mantıklı, akıllıca. Hassas = **sensitive**.\n"
        "- **eventually** = sonunda, en sonunda. Muhtemelen = **possibly, probably**.\n"
        "- **fabric** = kumaş. Fabrika = **factory**.\n"
        "- **novel** = roman. **library** = kütüphane (kitapçı = **bookshop**). **lecture** = ders, konferans.\n"
        "- **agenda** = gündem. Ajanda = **diary, planner**.\n"
        "- **chef** = şef aşçı. İş yerindeki şef = **boss, manager**.\n"
        "- Okurken Filtreler'den **False Friends**'i açarsan kitapta bu kelimeler renkli altı çizili görünür."),
    explanation_en=(
        "**What is a false friend?** An English word that looks like a Turkish word, so learners think it means the same, but it means something else. Many came into both languages from French and changed their meaning.\n"
        "- **sympathetic** = understanding, kind. Turkish \"sempatik\" = **nice, likeable**.\n"
        "- **actual** = real. Turkish \"aktüel\" = **current**. **actually** = in fact.\n"
        "- **sensible** = reasonable. Turkish \"hassas\" = **sensitive**.\n"
        "- **eventually** = in the end. Turkish \"eventüel\" = **possibly**.\n"
        "- **fabric** = cloth. Turkish \"fabrika\" = **factory**.\n"
        "- **novel** = a long story book. **library** = a place to borrow books (a shop is a **bookshop**). **lecture** = a talk or class.\n"
        "- **agenda** = list of topics for a meeting. Turkish \"ajanda\" = **diary, planner**.\n"
        "- **chef** = head cook. A boss at work is a **boss** or **manager**.\n"
        "- Turn on **False Friends** in the reader's Filters to see these words underlined in colour in a book."),
    structure_tr=['Benzer görünen kelime ≠ aynı anlam: sympathetic = anlayışlı', 'Türkçedeki anlam için başka kelime: sempatik = nice'],
    structure_en=['A similar-looking word ≠ the same meaning: sympathetic = understanding', 'Another word for the Turkish meaning: sempatik = nice'],
    examples=[('My boss was very sympathetic when I was ill.', 'Hastayken patronum çok anlayışlı davrandı.'),
              ('Eventually, we found the hotel.', 'Sonunda oteli bulduk.'),
              ('She is a very nice girl.', 'Çok sempatik bir kız.')],
    aliases=['false friend', 'false friends', 'yalancı eşdeğer', 'yalancı eşdeğerler', 'yalancı arkadaşlar'],
    tr=[
        ('Çok sempatik bir adam.', ['He is a very nice man.', "He's a very nice man.", 'He is a very likeable man.', "He's a very likeable man.", 'He is a very pleasant man.', "He's a very pleasant man."], 'sempatik = nice / likeable (sympathetic değil).', 'sempatik = nice / likeable (not sympathetic).'),
        ('Hastayken öğretmenim çok anlayışlıydı.', ['My teacher was very sympathetic when I was ill.', 'My teacher was very sympathetic when I was sick.', 'When I was ill, my teacher was very sympathetic.', 'When I was sick, my teacher was very sympathetic.', 'My teacher was very understanding when I was ill.', 'My teacher was very understanding when I was sick.'], 'anlayışlı = sympathetic / understanding.', 'sympathetic / understanding.'),
        ('Aslında ben öğretmen değilim.', ["Actually, I'm not a teacher.", 'Actually, I am not a teacher.', "Actually I'm not a teacher.", 'Actually I am not a teacher.', "In fact, I'm not a teacher."], 'actually = aslında (güncel değil).', 'actually = in fact (not "currently").'),
        ('Bu mantıklı bir karar.', ['This is a sensible decision.', "It's a sensible decision.", 'It is a sensible decision.', "That's a sensible decision.", 'That is a sensible decision.'], 'mantıklı = sensible.', 'sensible = reasonable.'),
        ('O çok hassas bir çocuk.', ['He is a very sensitive child.', 'She is a very sensitive child.', "He's a very sensitive child.", "She's a very sensitive child.", 'He is a very sensitive kid.', 'She is a very sensitive kid.'], 'hassas = sensitive (sensible değil).', 'hassas = sensitive (not sensible).'),
        ('Sonunda evi bulduk.', ['Eventually, we found the house.', 'Eventually we found the house.', 'We eventually found the house.', 'Finally, we found the house.', 'We finally found the house.', 'In the end, we found the house.'], 'eventually = sonunda.', 'eventually = in the end.'),
        ('Babam bir fabrikada çalışıyor.', ['My father works in a factory.', 'My father works at a factory.', 'My dad works in a factory.', 'My dad works at a factory.'], 'fabrika = factory (fabric değil).', 'fabrika = factory (not fabric).'),
        ('Bu kumaş çok yumuşak.', ['This fabric is very soft.', 'This material is very soft.', 'This cloth is very soft.'], 'kumaş = fabric.', 'fabric = cloth.'),
        ('Yeni bir roman okuyorum.', ['I am reading a new novel.', "I'm reading a new novel."], 'roman = novel.', 'novel = a long story book.'),
        ('Bugün kütüphaneye gideceğim.', ['I am going to the library today.', "I'm going to the library today.", 'I will go to the library today.', "I'll go to the library today.", "I'm going to go to the library today."], 'kütüphane = library (kitapçı = bookshop).', 'library (a shop is a bookshop).'),
        ('Profesörün dersi çok ilginçti.', ["The professor's lecture was very interesting.", 'The lecture by the professor was very interesting.'], 'lecture = ders, konferans (okuma değil).', 'lecture = a talk or class (not reading).'),
        ('Toplantının gündeminde ne var?', ['What is on the agenda for the meeting?', "What's on the agenda for the meeting?", "What is on the meeting's agenda?", "What's on the meeting's agenda?", 'What is on the agenda of the meeting?', "What's on the agenda of the meeting?"], 'gündem = agenda.', 'agenda = list of meeting topics.'),
        ('Ajandama not aldım.', ['I wrote it in my diary.', 'I made a note in my diary.', 'I wrote it in my planner.', 'I made a note in my planner.', 'I noted it in my diary.', 'I noted it in my planner.'], 'ajanda = diary / planner (agenda değil).', 'ajanda = diary / planner (not agenda).'),
        ('Gerçek fiyat çok daha yüksek.', ['The actual price is much higher.', 'The real price is much higher.'], 'actual = gerçek (aktüel değil).', 'actual = real (not current).'),
        ('Bu restoranın şefi İtalyan.', ['The chef of this restaurant is Italian.', "This restaurant's chef is Italian.", 'The chef at this restaurant is Italian.'], 'chef = şef aşçı.', 'chef = head cook.'),
        ('Patronum bugün ofiste değil.', ['My boss is not in the office today.', "My boss isn't in the office today.", 'My boss is not at the office today.', "My boss isn't at the office today."], 'iş yerindeki şef = boss (chef değil).', 'the head at work = boss (not chef).'),
    ],
    gaps=[
        ('She is a very ___ person; everybody likes her.', 'Çok sempatik biri, herkes onu sever.', ['nice', 'likeable', 'pleasant'], 'sempatik = nice.', 'nice / likeable.'),
        ('Thank you for being so ___ when my father died.', 'Babam öldüğünde bu kadar anlayışlı olduğun için teşekkür ederim.', ['sympathetic', 'understanding'], 'anlayışlı = sympathetic.', 'sympathetic = understanding.'),
        ("It's a ___ idea to take an umbrella.", 'Şemsiye almak mantıklı bir fikir.', ['sensible', 'good'], 'mantıklı = sensible.', 'sensible = reasonable.'),
        ('My skin is very ___ to the sun.', 'Cildim güneşe karşı çok hassas.', ['sensitive'], 'hassas = sensitive.', 'sensitive.'),
        ('After hours of waiting, the bus ___ arrived.', 'Saatlerce bekledikten sonra otobüs sonunda geldi.', ['eventually', 'finally'], 'eventually = sonunda.', 'eventually = in the end.'),
        ("___, I've never been to London.", 'Aslında hiç Londra\'ya gitmedim.', ['Actually', 'In fact'], 'actually = aslında.', 'actually = in fact.'),
        ('They make cars in that ___.', 'O fabrikada araba üretiyorlar.', ['factory'], 'fabrika = factory.', 'factory.'),
        ('This dress is made of a light ___.', 'Bu elbise hafif bir kumaştan yapılmış.', ['fabric', 'material'], 'kumaş = fabric.', 'fabric = cloth.'),
        ('Have you read his latest ___?', 'Onun son romanını okudun mu?', ['novel', 'book'], 'roman = novel.', 'novel.'),
        ('You can borrow books from the ___.', 'Kütüphaneden kitap ödünç alabilirsin.', ['library'], 'kütüphane = library.', 'library.'),
        ('The first item on the ___ is the budget.', 'Gündemin ilk maddesi bütçe.', ['agenda'], 'gündem = agenda.', 'agenda.'),
        ('My ___ gave me a day off.', 'Patronum bana bir gün izin verdi.', ['boss', 'manager'], 'patron, şef = boss.', 'boss.'),
    ],
))
