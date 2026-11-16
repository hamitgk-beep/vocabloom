# Grammar lessons for the expression groups that used to sit in the
# "Sözlük" tab. Part C: overviews inside existing grammar categories.

TOPICS = []

TOPICS.append(dict(
    id='conjunction_types', category='conjunctions', level='A2', dict_category='conjunctions', before='because_so',
    title_tr='Bağlaç türleri: and, but, or, so ve ikili bağlaçlar', title_en='Conjunctions: Types and Pairs',
    explanation_tr=(
        "**Bağlaç nedir?** Kelimeleri, öbekleri ya da cümleleri birbirine bağlayan sözcüklerdir. Üç türü vardır.\n"
        "- **Eşit bağlayanlar (coordinating):** and (ve), but (ama), or (veya), so (bu yüzden), yet (yine de), nor (ne de). İki eşit parçayı bağlar: I was tired, **so** I went to bed. İki tam cümleyi bağlarken önüne genellikle virgül konur.\n"
        "- **Yan cümle bağlaçları (subordinating):** because, although, when, while, if, unless, until, before, after, since, as soon as. Bir yan cümleyi ana cümleye bağlar; yan cümle başta gelirse arkasına virgül konur: **Although** it was late, we kept working. Bunların Gramer'de ayrı konuları var: because / so, although / despite, unless, when / while, zaman bağlaçları.\n"
        "- **İkili bağlaçlar (correlative):** both … and (hem … hem de), either … or (ya … ya da), neither … nor (ne … ne de), not only … but also (yalnızca … değil, aynı zamanda), whether … or (… olsun ya da olmasın).\n"
        "- **neither … nor** zaten olumsuzdur, yanına not gelmez: I like **neither** tea **nor** coffee (I don't like neither değil).\n"
        "- **either … or / neither … nor** ile fiil yakındaki özneye uyar: Either my brothers or my **sister is** coming.\n"
        "- Okurken Filtreler'den **Conjunctions**'ı açarsan kitaptaki bütün bağlaçlar renkli altı çizili görünür."),
    explanation_en=(
        "**What is a conjunction?** A word that joins words, phrases or sentences. There are three kinds.\n"
        "- **Coordinating:** and, but, or, so, yet, nor. They join two equal parts: I was tired, **so** I went to bed. A comma usually comes before them when they join two full sentences.\n"
        "- **Subordinating:** because, although, when, while, if, unless, until, before, after, since, as soon as. They join a clause to the main clause; if the clause comes first, a comma follows it: **Although** it was late, we kept working. Each has its own Grammar topic: because / so, although / despite, unless, when / while, time clauses.\n"
        "- **Correlative (pairs):** both … and, either … or, neither … nor, not only … but also, whether … or.\n"
        "- **neither … nor** is already negative, so no \"not\": I like **neither** tea **nor** coffee (not I don't like neither).\n"
        "- With **either … or / neither … nor** the verb agrees with the nearer subject: Either my brothers or my **sister is** coming.\n"
        "- Turn on **Conjunctions** in the reader's Filters to see every conjunction in a book underlined in colour."),
    structure_tr=['Cümle, + and / but / or / so + cümle', 'both A and B · either A or B · neither A nor B', 'not only A but also B'],
    structure_en=['Sentence, + and / but / or / so + sentence', 'both A and B · either A or B · neither A nor B', 'not only A but also B'],
    examples=[('I wanted to go out, but it was raining.', 'Dışarı çıkmak istedim ama yağmur yağıyordu.'),
              ('She speaks both English and French.', 'Hem İngilizce hem Fransızca konuşuyor.'),
              ('We can either take the bus or walk.', 'Ya otobüse bineriz ya da yürürüz.')],
    aliases=['conjunction types', 'coordinating conjunctions', 'correlative conjunctions', 'bağlaç türleri', 'ikili bağlaçlar', 'both and', 'either or', 'neither nor', 'not only but also'],
    tr=[
        ('Yorgundum, bu yüzden erken yattım.', ['I was tired, so I went to bed early.', 'I was tired so I went to bed early.'], 'so: bu yüzden (sonuç).', 'so: result.'),
        ('Gelmek istedim ama vaktim yoktu.', ["I wanted to come, but I didn't have time.", "I wanted to come but I didn't have time.", 'I wanted to come, but I had no time.', 'I wanted to come but I had no time.'], 'but: ama (karşıtlık).', 'but: contrast.'),
        ('Çay mı kahve mi istersin?', ['Would you like tea or coffee?', 'Do you want tea or coffee?'], 'or: seçenek.', 'or: a choice.'),
        ('Hem İngilizce hem Almanca konuşuyor.', ['She speaks both English and German.', 'He speaks both English and German.'], 'both … and: hem … hem de.', 'both … and.'),
        ('Ya bugün ya da yarın arayacağım.', ['I will call either today or tomorrow.', "I'll call either today or tomorrow.", 'I will call you either today or tomorrow.', "I'll call you either today or tomorrow.", 'I will phone either today or tomorrow.', "I'll phone either today or tomorrow."], 'either … or: ya … ya da.', 'either … or.'),
        ('Ne çay ne kahve içerim.', ['I drink neither tea nor coffee.'], 'neither … nor zaten olumsuzdur, not eklenmez.', 'neither … nor is already negative; no "not".'),
        ('O yalnızca zeki değil, aynı zamanda çok çalışkan.', ['She is not only clever but also very hardworking.', 'He is not only clever but also very hardworking.', "She's not only clever but also very hardworking.", "He's not only clever but also very hardworking.", 'She is not only smart but also very hardworking.', 'He is not only smart but also very hardworking.', 'She is not only intelligent but also very hardworking.', 'He is not only intelligent but also very hardworking.'], 'not only … but also: yalnızca … değil, aynı zamanda.', 'not only … but also.'),
        ('Ne annem ne babam evdeydi.', ['Neither my mother nor my father was at home.', 'Neither my mother nor my father was home.', 'Neither my mum nor my dad was at home.', 'Neither my mom nor my dad was at home.'], 'neither … nor: fiil yakındaki özneye uyar (father → was).', 'neither … nor: the verb agrees with the nearer subject (father → was).'),
        ('Ya şimdi gidersin ya da burada kalırsın.', ['Either you go now or you stay here.', 'You either go now or stay here.', 'You can either go now or stay here.', 'Either you leave now or you stay here.'], 'either … or iki cümleyi de bağlayabilir.', 'either … or can join two clauses too.'),
        ('Çok çalıştı, yine de sınavı geçemedi.', ["He studied hard, yet he didn't pass the exam.", "She studied hard, yet she didn't pass the exam.", "He studied hard, but he didn't pass the exam.", "She studied hard, but she didn't pass the exam.", 'He studied hard, yet he failed the exam.', 'She studied hard, yet she failed the exam.'], 'yet: yine de (but gibi, biraz daha güçlü).', 'yet: like but, a little stronger.'),
        ('Hem kardeşim hem ben futbolu severiz.', ['Both my brother and I like football.', 'Both my sister and I like football.', 'Both my brother and I love football.', 'Both my sister and I love football.'], 'both A and B özne olunca fiil çoğuldur.', 'both A and B as subject takes a plural verb.'),
        ('Sıcaktı, bu yüzden pencereyi açtık.', ['It was hot, so we opened the window.', 'It was hot so we opened the window.'], 'so: bu yüzden.', 'so: result.'),
        ('Ne aradı ne de mesaj attı.', ['He neither called nor texted.', 'She neither called nor texted.', 'He neither called nor sent a message.', 'She neither called nor sent a message.', 'He neither phoned nor texted.', 'She neither phoned nor texted.'], 'neither … nor iki fiili de bağlayabilir.', 'neither … nor can join two verbs.'),
        ('Ekmek, peynir ve süt aldım.', ['I bought bread, cheese and milk.', 'I bought bread, cheese, and milk.'], 'Listede and yalnızca son öğeden önce gelir.', 'In a list, and comes only before the last item.'),
        ('Kitabı yalnızca okumadı, filmini de izledi.', ['She not only read the book but also watched the film.', 'He not only read the book but also watched the film.', 'She not only read the book but also watched the movie.', 'He not only read the book but also watched the movie.', 'Not only did she read the book, but she also watched the film.', 'Not only did he read the book, but he also watched the film.'], 'Not only cümle başına gelirse devrik yapı kullanılır: Not only did she …', 'At the start of a sentence, not only needs inversion: Not only did she …'),
        ('Gelip gelmeyeceğini bilmiyorum.', ["I don't know whether he will come or not.", "I don't know whether she will come or not.", "I don't know if he will come or not.", "I don't know if she will come or not.", "I don't know whether he'll come or not.", "I don't know whether she'll come or not.", "I don't know whether he will come.", "I don't know whether she will come."], 'whether … or not: … olup olmadığını.', 'whether … or not.'),
    ],
    gaps=[
        ('I like apples ___ oranges.', 'Elmayı ve portakalı severim.', ['and'], 'and: ve.', 'and.'),
        ('It was cold, ___ I wore a coat.', 'Soğuktu, bu yüzden mont giydim.', ['so'], 'so: bu yüzden.', 'so: result.'),
        ("She is rich, ___ she isn't happy.", 'Zengin ama mutlu değil.', ['but', 'yet'], 'but / yet: karşıtlık.', 'but / yet: contrast.'),
        ('Do you want to stay ___ go?', 'Kalmak mı istersin gitmek mi?', ['or'], 'or: seçenek.', 'or: a choice.'),
        ('___ my sister and my brother are doctors.', 'Hem kız kardeşim hem erkek kardeşim doktor.', ['Both'], 'both … and.', 'both … and.'),
        ('We can ___ walk or take a taxi.', 'Ya yürürüz ya da taksiye bineriz.', ['either'], 'either … or.', 'either … or.'),
        ('He speaks neither French ___ Spanish.', 'Ne Fransızca ne İspanyolca konuşuyor.', ['nor'], 'neither … nor (or değil).', 'neither … nor (not or).'),
        ('She is not only a singer ___ also an actress.', 'Yalnızca şarkıcı değil, aynı zamanda oyuncu.', ['but'], 'not only … but also.', 'not only … but also.'),
        ('___ Tom nor Anna came to the party.', 'Partiye ne Tom geldi ne Anna.', ['Neither'], 'neither … nor.', 'neither … nor.'),
        ('You can have either tea ___ coffee.', 'Ya çay ya kahve alabilirsin.', ['or'], 'either … or.', 'either … or.'),
        ('He was hungry, ___ he made a sandwich.', 'Acıkmıştı, bu yüzden bir sandviç yaptı.', ['so'], 'so: sonuç.', 'so: result.'),
        ("I don't know ___ he will come or not.", 'Gelip gelmeyeceğini bilmiyorum.', ['whether', 'if'], 'whether … or not.', 'whether … or not.'),
    ],
))

TOPICS.append(dict(
    id='discourse_markers', category='conjunctions', level='B1', dict_category='discourse_markers', after='transition_words',
    title_tr='Söylem belirleyiciler ve dolgu sözcükleri (well, anyway, by the way)', title_en='Discourse Markers and Fillers',
    explanation_tr=(
        "**Söylem belirleyici nedir?** Cümlenin anlamına bir şey eklemeyen ama konuşmayı ve metni yönlendiren sözcüklerdir: konu değiştirir, düşünmek için zaman kazandırır, düzeltir ya da karşı fikir getirir. Türkçedeki \"yani\", \"neyse\", \"bu arada\", \"aslında\" gibi.\n"
        "- **Konu değiştirme:** by the way (bu arada), anyway (neyse, her neyse), speaking of … (… demişken).\n"
        "- **Düşünme ve yumuşatma (dolgu):** well (şey, eee), you know (bilirsin işte), I mean (yani, demek istediğim), let me see (bir bakayım), kind of / sort of (biraz, bir bakıma).\n"
        "- **Düzeltme ve açıklama:** actually (aslında), in other words (başka bir deyişle), I mean (yani).\n"
        "- **Ekleme ve karşıtlık:** besides (üstelik), what's more (dahası), on the other hand (öte yandan).\n"
        "- **Sıralama ve sonuç:** first of all (her şeyden önce), then (sonra), finally (son olarak), after all (ne de olsa).\n"
        "- **Görüş:** to be honest (açıkçası), in my opinion (bence).\n"
        "- Genellikle cümle başında gelir ve arkasından virgül konur: **By the way**, did you call Mum? **Well**, I'm not sure.\n"
        "- Konuşmada well, you know, I mean çok sık geçer; yazıda however, in addition, therefore gibi daha resmî olanlar tercih edilir (Gramer'deki **Geçiş sözcükleri** konusuna bak).\n"
        "- Okurken Filtreler'den **Discourse Markers / Fillers**'ı açarsan kitapta bunlar renkli altı çizili görünür."),
    explanation_en=(
        "**What is a discourse marker?** A word or phrase that adds nothing to the meaning of the sentence but guides the conversation or text: it changes the topic, buys time to think, corrects or brings in another view.\n"
        "- **Changing the topic:** by the way, anyway, speaking of …\n"
        "- **Thinking and softening (fillers):** well, you know, I mean, let me see, kind of / sort of.\n"
        "- **Correcting and explaining:** actually, in other words, I mean.\n"
        "- **Adding and contrasting:** besides, what's more, on the other hand.\n"
        "- **Ordering and concluding:** first of all, then, finally, after all.\n"
        "- **Opinion:** to be honest, in my opinion.\n"
        "- They usually start the sentence and are followed by a comma: **By the way**, did you call Mum? **Well**, I'm not sure.\n"
        "- Speech uses well, you know, I mean a lot; writing prefers more formal ones such as however, in addition, therefore (see the **Transition words** topic).\n"
        "- Turn on **Discourse Markers / Fillers** in the reader's Filters to see them underlined in colour in a book."),
    structure_tr=['Belirleyici + virgül + cümle: By the way, …', 'Cümle. + Belirleyici, cümle: It was expensive. Anyway, …'],
    structure_en=['Marker + comma + sentence: By the way, …', 'Sentence. + Marker, sentence: It was expensive. Anyway, …'],
    examples=[('By the way, have you seen my keys?', 'Bu arada, anahtarlarımı gördün mü?'),
              ("Well, I'm not really sure.", 'Şey, pek emin değilim.'),
              ("It was a long day. Anyway, I'm home now.", 'Uzun bir gündü. Neyse, artık evdeyim.')],
    aliases=['discourse marker', 'discourse markers', 'fillers', 'filler words', 'söylem belirleyici', 'söylem belirleyiciler', 'dolgu sözcükleri', 'dolgu kelimeleri'],
    tr=[
        ('Bu arada, yarın toplantı var.', ['By the way, there is a meeting tomorrow.', "By the way, there's a meeting tomorrow.", 'By the way there is a meeting tomorrow.', "By the way there's a meeting tomorrow."], 'by the way: bu arada (konu değiştirir).', 'by the way: changes the topic.'),
        ('Neyse, artık gitmem lazım.', ['Anyway, I have to go now.', 'Anyway, I need to go now.', 'Anyway, I must go now.', "Anyway, I've got to go now."], 'anyway: neyse (konuyu kapatır).', 'anyway: closes a topic.'),
        ('Şey, pek emin değilim.', ["Well, I'm not really sure.", 'Well, I am not really sure.', "Well, I'm not very sure.", "Well, I'm not quite sure.", "Well, I'm not sure.", 'Well, I am not sure.'], 'well: düşünürken ya da tereddüt ederken.', 'well: while thinking or hesitating.'),
        ('Aslında ben de gelmek istemiyorum.', ["Actually, I don't want to come either.", 'Actually, I do not want to come either.', "Actually I don't want to come either.", "Actually, I don't want to go either."], 'actually: aslında. Olumsuzda "de" = either.', 'actually: in fact. In negatives "too" becomes "either".'),
        ('Film güzeldi… yani, fena değildi.', ["The film was good... I mean, it wasn't bad.", "The film was good, I mean, it wasn't bad.", "The movie was good... I mean, it wasn't bad.", "The movie was good, I mean, it wasn't bad.", 'The film was good... I mean, it was not bad.', 'The movie was good... I mean, it was not bad.'], 'I mean: yani (kendini düzeltir).', 'I mean: corrects what you said.'),
        ('Öte yandan bu iş çok iyi para veriyor.', ['On the other hand, this job pays very well.', 'On the other hand this job pays very well.', 'On the other hand, this job pays really well.'], 'on the other hand: öte yandan.', 'on the other hand: contrast.'),
        ('Her şeyden önce, geldiğiniz için teşekkürler.', ['First of all, thank you for coming.', 'First of all, thanks for coming.', 'First of all thank you for coming.', 'First of all thanks for coming.'], 'first of all: her şeyden önce.', 'first of all.'),
        ('Açıkçası bu fikri sevmedim.', ["To be honest, I don't like this idea.", "To be honest, I didn't like this idea.", "To be honest, I don't like the idea.", "To be honest, I didn't like the idea.", "Honestly, I don't like this idea.", "Honestly, I didn't like this idea."], 'to be honest: açıkçası.', 'to be honest.'),
        ('Bence haklısın.', ['In my opinion, you are right.', "In my opinion, you're right.", 'In my opinion you are right.', "In my opinion you're right.", 'I think you are right.', "I think you're right."], 'in my opinion: bence.', 'in my opinion.'),
        ('Ona kızma; ne de olsa o daha çocuk.', ["Don't be angry with him; after all, he's only a child.", "Don't be angry with him; after all, he is only a child.", "Don't be angry with him. After all, he's only a child.", "Don't be angry with her; after all, she's only a child.", "Don't be angry with her. After all, she's only a child.", "Don't be angry with him; after all, he's just a child.", "Don't get angry with him; after all, he's just a child."], 'after all: ne de olsa (bir gerekçe hatırlatır).', 'after all: reminds of a reason.'),
        ('Bu araba çok pahalı. Üstelik çok yakıt yakıyor.', ['This car is very expensive. Besides, it uses a lot of fuel.', 'This car is very expensive. Besides, it uses a lot of petrol.', 'This car is very expensive. Besides, it uses a lot of gas.', "This car is very expensive. What's more, it uses a lot of fuel.", 'This car is very expensive. Besides, it consumes a lot of fuel.'], 'besides / what\'s more: üstelik, dahası.', "besides / what's more: in addition."),
        ('Başka bir deyişle işi kaybettin.', ['In other words, you lost the job.', 'In other words, you have lost the job.', "In other words, you've lost the job.", 'In other words you lost the job.'], 'in other words: başka bir deyişle.', 'in other words.'),
        ('Bilirsin işte, biraz utangaçtır.', ["You know, he's a bit shy.", 'You know, he is a bit shy.', "You know, she's a bit shy.", 'You know, she is a bit shy.'], 'you know: bilirsin işte (dolgu).', 'you know: a filler.'),
        ('Bir bakayım… evet, saat beşte boşum.', ["Let me see... yes, I'm free at five.", 'Let me see... yes, I am free at five.', "Let me see, yes, I'm free at five.", "Let me see... yes, I'm free at 5.", "Let me see... yes, I'm free at five o'clock."], 'let me see: bir bakayım (düşünürken).', 'let me see: while thinking.'),
        ('Tatil demişken, nereye gidiyorsunuz?', ['Speaking of holidays, where are you going?', 'Speaking of holidays, where are you going to go?', 'Speaking of vacations, where are you going?', 'Talking of holidays, where are you going?', 'Speaking of the holiday, where are you going?'], 'speaking of …: … demişken.', 'speaking of …'),
        ('Son olarak, ödevlerinizi cumaya kadar teslim edin.', ['Finally, hand in your homework by Friday.', 'Finally, hand your homework in by Friday.', 'Finally, submit your homework by Friday.', 'Lastly, hand in your homework by Friday.', 'Finally, give in your homework by Friday.'], 'finally: son olarak (sıralamanın sonu).', 'finally: the last point.'),
    ],
    gaps=[
        ('By the ___, did you call your mother?', 'Bu arada, anneni aradın mı?', ['way'], 'by the way.', 'by the way.'),
        ("It was a long trip. ___, we're home now.", 'Uzun bir yolculuktu. Neyse, artık evdeyiz.', ['Anyway'], 'anyway: neyse.', 'anyway.'),
        ('___, let me think about it.', 'Şey, bir düşüneyim.', ['Well'], 'well: şey.', 'well.'),
        ("She isn't Spanish. ___, she's from Mexico.", 'İspanyol değil. Aslında Meksikalı.', ['Actually', 'In fact'], 'actually: aslında.', 'actually.'),
        ('On the other ___, the flat is very small.', 'Öte yandan daire çok küçük.', ['hand'], 'on the other hand.', 'on the other hand.'),
        ("First of ___, let's look at the numbers.", 'Her şeyden önce rakamlara bakalım.', ['all'], 'first of all.', 'first of all.'),
        ('To be ___, I forgot.', 'Açıkçası unuttum.', ['honest'], 'to be honest.', 'to be honest.'),
        ('In my ___, the book is better than the film.', 'Bence kitap filmden daha iyi.', ['opinion'], 'in my opinion.', 'in my opinion.'),
        ("Let him decide. After ___, it's his money.", 'Bırak o karar versin. Ne de olsa onun parası.', ['all'], 'after all: ne de olsa.', 'after all.'),
        ('In other ___, we have no time left.', 'Başka bir deyişle hiç vaktimiz kalmadı.', ['words'], 'in other words.', 'in other words.'),
        ("It's late, and ___, I'm tired.", 'Geç oldu, üstelik yorgunum.', ['besides'], 'besides: üstelik.', 'besides.'),
        ("I didn't like the party... I ___, the music was terrible.", 'Partiyi sevmedim… yani, müzik berbattı.', ['mean'], 'I mean: yani.', 'I mean.'),
    ],
))

TOPICS.append(dict(
    id='modals_overview', category='modals', level='A2', dict_category='modal_verbs', before='ability',
    title_tr='Kip fiillerine genel bakış (can, must, should, may …)', title_en='Modal Verbs: Overview',
    explanation_tr=(
        "**Kip fiili (modal verb) nedir?** Ana fiilin önüne gelip ona yetenek, izin, olasılık, zorunluluk ya da tavsiye anlamı katan yardımcı fiillerdir: can, could, may, might, must, shall, should, will, would. Benzer görevdekiler: have to, need to, ought to, be able to.\n"
        "- **Arkalarından yalın fiil (V1) gelir,** to almaz: I can swim (can to swim değil). İstisna: ought to, have to.\n"
        "- He / she / it ile **-s almazlar**: She can drive (she cans değil). Ana fiil de -s almaz: she can **speak** (speaks değil).\n"
        "- Olumsuz ve soruda do / does kullanılmaz: I **can't** swim. **Can** you swim? (Do you can değil.)\n"
        "- **Anlamlarına göre:** yetenek: can, could (geçmiş) · izin: can, could, may · rica: could, would · teklif: shall I …? · tavsiye: should, ought to · zorunluluk: must, have to · yasak: mustn't · gereksizlik: don't have to · olasılık: may, might, could · kesin çıkarım: must (olmalı), can't (olamaz) · gelecek, söz: will.\n"
        "- **Dikkat:** mustn't = yapmamalısın (yasak); don't have to = yapmak zorunda değilsin (gerek yok).\n"
        "- Her anlamın Gramer'de ayrı bir konusu var: yetenek, zorunluluk, rica ve izin, olasılık ve tahmin, geçmişe yönelik kipler.\n"
        "- Okurken Filtreler'den **Modal Verbs**'ü açarsan kitaptaki kip fiilleri renkli altı çizili görünür."),
    explanation_en=(
        "**What is a modal verb?** A helping verb before the main verb that adds ability, permission, possibility, obligation or advice: can, could, may, might, must, shall, should, will, would. Similar ones: have to, need to, ought to, be able to.\n"
        "- **They are followed by the base verb (V1)** without to: I can swim (not can to swim). Exceptions: ought to, have to.\n"
        "- They take **no -s** with he / she / it: She can drive (not she cans). The main verb takes no -s either: she can **speak** (not speaks).\n"
        "- Negatives and questions do not use do / does: I **can't** swim. **Can** you swim? (not Do you can).\n"
        "- **By meaning:** ability: can, could (past) · permission: can, could, may · requests: could, would · offers: shall I …? · advice: should, ought to · obligation: must, have to · prohibition: mustn't · no need: don't have to · possibility: may, might, could · certain deduction: must, can't · future, promises: will.\n"
        "- **Careful:** mustn't = it is not allowed; don't have to = it is not necessary.\n"
        "- Each meaning has its own Grammar topic: ability, obligation, requests and permission, deduction, past modals.\n"
        "- Turn on **Modal Verbs** in the reader's Filters to see them underlined in colour in a book."),
    structure_tr=['Özne + modal + V1: She can swim.', 'Özne + modal + not + V1: You shouldn\'t worry.', 'Modal + özne + V1?: May I come in?'],
    structure_en=['Subject + modal + V1: She can swim.', 'Subject + modal + not + V1: You shouldn\'t worry.', 'Modal + subject + V1?: May I come in?'],
    examples=[('You should drink more water.', 'Daha çok su içmelisin.'),
              ('May I sit here?', 'Buraya oturabilir miyim?'),
              ("You mustn't park here.", 'Buraya park etmemelisin (yasak).')],
    aliases=['modal verbs overview', 'modals overview', 'modal overview', 'kip fiillerine genel bakış', 'modal fiiller', 'modal fiil'],
    tr=[
        ('Kız kardeşim üç dil konuşabiliyor.', ['My sister can speak three languages.', 'My sister speaks three languages.'], 'can + V1: yetenek. speak -s almaz.', 'can + V1: ability. speak takes no -s.'),
        ('Daha çok sebze yemelisin.', ['You should eat more vegetables.', 'You ought to eat more vegetables.'], 'should / ought to: tavsiye.', 'should / ought to: advice.'),
        ('İçeri girebilir miyim?', ['May I come in?', 'Can I come in?', 'Could I come in?'], 'may / can / could I …?: izin isteme.', 'may / can / could I …?: asking permission.'),
        ('Burada sigara içmemelisiniz; yasak.', ["You mustn't smoke here; it's forbidden.", 'You must not smoke here; it is forbidden.', "You mustn't smoke here, it's forbidden.", "You mustn't smoke here; it's not allowed.", "You mustn't smoke here. It's forbidden.", 'You must not smoke here. It is forbidden.'], "mustn't: yasak.", "mustn't: prohibition."),
        ('Yarın erken kalkmak zorunda değilsin.', ["You don't have to get up early tomorrow.", 'You do not have to get up early tomorrow.', "You don't need to get up early tomorrow."], "don't have to: gerek yok (yasak değil).", "don't have to: not necessary (not forbidden)."),
        ('Yarın yağmur yağabilir.', ['It may rain tomorrow.', 'It might rain tomorrow.', 'It could rain tomorrow.'], 'may / might / could: olasılık.', 'may / might / could: possibility.'),
        ('Çocukken çok hızlı koşabiliyordum.', ['When I was a child, I could run very fast.', 'I could run very fast when I was a child.', 'When I was a kid, I could run very fast.', 'I could run very fast when I was a kid.', 'When I was a child I could run very fast.'], 'could: geçmişteki yetenek.', 'could: past ability.'),
        ('Pencereyi açayım mı?', ['Shall I open the window?'], 'Shall I …?: teklif.', 'Shall I …?: an offer.'),
        ('Bana yardım eder misiniz lütfen?', ['Could you help me, please?', 'Would you help me, please?', 'Can you help me, please?', 'Could you please help me?', 'Would you please help me?', 'Can you please help me?'], 'could / would you …?: kibar rica.', 'could / would you …?: a polite request.'),
        ('O çok yorgun olmalı; bütün gün çalıştı.', ['She must be very tired; she worked all day.', 'He must be very tired; he worked all day.', 'She must be very tired, she worked all day.', 'He must be very tired, he worked all day.', 'She must be very tired; she has worked all day.', 'He must be very tired; he has worked all day.', 'She must be very tired. She worked all day.', 'He must be very tired. He worked all day.'], 'must be: kesin çıkarım (olmalı).', 'must be: a confident deduction.'),
        ('Bu doğru olamaz.', ["This can't be true.", "That can't be true.", 'This cannot be true.', 'That cannot be true.', "It can't be true.", 'It cannot be true.'], "can't be: olamaz (çıkarım).", "can't be: impossible (deduction)."),
        ('Her gün üniforma giymek zorundayız.', ['We have to wear a uniform every day.', 'We must wear a uniform every day.', 'We have to wear uniforms every day.', 'We must wear uniforms every day.'], 'have to / must: zorunluluk.', 'have to / must: obligation.'),
        ('Sana yarın yardım ederim.', ['I will help you tomorrow.', "I'll help you tomorrow."], 'will: söz, gelecek.', 'will: a promise, the future.'),
        ('Doktora gitmen gerek.', ['You need to see a doctor.', 'You need to go to the doctor.', 'You should see a doctor.', 'You have to see a doctor.', 'You must see a doctor.', 'You should go to the doctor.'], 'need to: gerekmek.', 'need to: necessity.'),
        ('Yüzemiyorum.', ["I can't swim.", 'I cannot swim.'], "can't: yapamamak. cannot bitişik yazılır.", "can't: cannot is written as one word."),
        ('Biraz daha çay ister misiniz?', ['Would you like some more tea?', 'Would you like more tea?'], 'Would you like …?: kibar teklif.', 'Would you like …?: a polite offer.'),
    ],
    gaps=[
        ('She ___ play the piano very well.', 'Piyanoyu çok iyi çalabiliyor.', ['can'], 'can: yetenek.', 'can: ability.'),
        ('You ___ see a dentist about that tooth.', 'O diş için bir dişçiye görünmelisin.', ['should'], 'should: tavsiye.', 'should: advice.'),
        ('___ I use your phone, please?', 'Telefonunu kullanabilir miyim lütfen?', ['May', 'Can', 'Could'], 'May / Can / Could I …?: izin.', 'May / Can / Could I …?: permission.'),
        ("You ___ touch that wire. It's dangerous!", 'O kabloya dokunmamalısın. Tehlikeli!', ["mustn't", 'must not'], "mustn't: yasak.", "mustn't: prohibition."),
        ("It's Sunday, so I don't ___ to work.", 'Bugün pazar, bu yüzden çalışmak zorunda değilim.', ['have'], "don't have to: gerek yok.", "don't have to: not necessary."),
        ('Take an umbrella. It ___ rain later.', 'Şemsiye al. Sonra yağmur yağabilir.', ['might', 'may', 'could'], 'might / may: olasılık.', 'might / may: possibility.'),
        ('When I was five, I ___ read.', 'Beş yaşındayken okuyabiliyordum.', ['could'], 'could: geçmişteki yetenek.', 'could: past ability.'),
        ('___ I carry your bag for you?', 'Çantanı taşıyayım mı?', ['Shall'], 'Shall I …?: teklif.', 'Shall I …?: an offer.'),
        ('He has three cars. He ___ be rich.', 'Üç arabası var. Zengin olmalı.', ['must'], 'must be: kesin çıkarım.', 'must be: deduction.'),
        ("She ___ be at work; I just saw her at the gym.", 'İşte olamaz; onu az önce spor salonunda gördüm.', ["can't", 'cannot'], "can't be: olamaz.", "can't be: impossible."),
        ('___ you like a cup of coffee?', 'Bir fincan kahve ister misiniz?', ['Would'], 'Would you like …?', 'Would you like …?'),
        ('She can ___ three languages.', 'Üç dil konuşabiliyor.', ['speak'], 'can + V1 (speaks değil).', 'can + V1 (not speaks).'),
    ],
))
