#!/usr/bin/env python3
"""Hand-written grammar lessons for "Gramer pratiği" (checked by hand).
Writes assets/grammar/lessons.json. More exercises can be added with
tools/tutor/teacher.py lessons (they are merged, never replace these).

Each exercise: (Turkish, [correct English versions, main one first], rule note)."""
import json, os

T = []

def topic(id, cat, level, tr, en, explanation, structure, examples, exercises):
    T.append({'id': id, 'category': cat, 'level': level, 'title_tr': tr, 'title_en': en,
              'explanation': explanation.strip(), 'structure': structure,
              'examples': examples,
              'exercises': [{'id': '%s-%d' % (id, i + 1), 'tr': a, 'answers': b, 'note': c}
                            for i, (a, b, c) in enumerate(exercises)]})

# ------------------------------------------------------------------ tenses
topic('simple_present', 'tenses', 'A2', 'Geniş zaman', 'Simple Present', '''
**Ne zaman kullanılır?** Alışkanlıklar, tekrar eden eylemler, genel doğrular ve kalıcı durumlar için.
- Türkçedeki "-ir, -ar" (geniş zaman) ve çoğu zaman "-iyor" ile anlatılan alışkanlıklar buna karşılık gelir: "Her sabah koşuyorum" = I run every morning.
- He, she, it öznelerinde fiile **-s / -es** eklenir: she works, he watches.
- Olumsuz ve soru için **do / does** kullanılır; does kullanılınca fiil yalın kalır: She doesn't like tea. Does he work here?
- Sık kullanılan zaman zarfları: always, usually, often, sometimes, never, every day.
''', ['Özne + V1 (he/she/it: V1 + s)', 'Özne + do/does + not + V1', 'Do/Does + özne + V1?'],
[['She works at a hospital.', 'Bir hastanede çalışıyor.'], ['We usually have breakfast at eight.', 'Genellikle sekizde kahvaltı yaparız.']],
[
 ('Kardeşim her hafta sonu futbol oynar.', ['My brother plays football every weekend.', 'My sister plays football every weekend.'], 'He/she/it öznesinde fiile -s eklenir: plays.'),
 ('Babam kahve içmez, çay sever.', ["My father doesn't drink coffee; he likes tea.", "My father doesn't drink coffee, he likes tea.", 'My dad does not drink coffee; he likes tea.'], 'Üçüncü tekil şahısta olumsuz "doesn\'t + V1" ile yapılır.'),
 ('Su yüz derecede kaynar.', ['Water boils at 100 degrees.', 'Water boils at one hundred degrees.', 'Water boils at 100 degrees Celsius.'], 'Genel doğrular geniş zamanla anlatılır.'),
 ('Sen nerede yaşıyorsun?', ['Where do you live?'], 'Kalıcı durumlar geniş zamanla sorulur: Where do you live?'),
 ('Annem asla geç kalmaz.', ['My mother is never late.', 'My mother never arrives late.', 'My mum is never late.'], '"Geç kalmak" çoğunlukla "be late" ile söylenir; "never" fiilden önce, "be" fiilinden sonra gelir.'),
 ('Otobüs her sabah yedide kalkar.', ['The bus leaves at seven every morning.', 'The bus leaves every morning at seven.', 'The bus departs at seven every morning.'], 'Tarifeler ve programlar geniş zamanla anlatılır.'),
])

topic('present_continuous', 'tenses', 'A2', 'Şimdiki zaman', 'Present Continuous', '''
**Ne zaman kullanılır?** Şu anda olan, bu sıralar süren ya da yakın gelecekte planlanmış eylemler için.
- "Şu an kitap okuyorum" = I am reading a book now.
- "Bu ay yeni bir proje üzerinde çalışıyorum" = I'm working on a new project this month.
- Planlanmış yakın gelecek: "Yarın Ankara'ya gidiyorum" = I'm going to Ankara tomorrow.
- **Dikkat:** know, like, want, need, believe, understand gibi durum fiilleri genellikle -ing almaz: I know (I am knowing değil).
''', ['Özne + am/is/are + V-ing', 'Özne + am/is/are + not + V-ing', 'Am/Is/Are + özne + V-ing?'],
[["Don't call now, she's sleeping.", 'Şimdi arama, uyuyor.'], ["We're meeting Ali on Friday.", 'Cuma günü Ali ile buluşuyoruz.']],
[
 ('Şu anda ödevimi yapıyorum.', ["I'm doing my homework right now.", 'I am doing my homework now.', "I'm doing my homework at the moment."], 'Şu anda olan eylem: am + V-ing.'),
 ('Çocuklar bahçede oynuyor.', ['The children are playing in the garden.', 'The kids are playing in the garden.'], 'Çoğul özneyle "are + V-ing".'),
 ('Bu hafta çok çalışıyorum.', ["I'm working a lot this week.", "I'm working very hard this week.", 'I am working hard this week.'], 'Bu sıralar süren geçici durumlar şimdiki zamanla anlatılır.'),
 ('Yarın akşam ne yapıyorsun?', ['What are you doing tomorrow evening?', 'What are you doing tomorrow night?'], 'Yakın gelecekteki planlar Present Continuous ile sorulur.'),
 ('Neden gülüyorsun?', ['Why are you laughing?'], 'Soru: Why + are + özne + V-ing?'),
 ('Seni anlıyorum.', ['I understand you.'], '"understand" durum fiilidir, -ing almaz: I understand.'),
])

topic('simple_past', 'tenses', 'A2', 'Geçmiş zaman', 'Simple Past', '''
**Ne zaman kullanılır?** Geçmişte belli bir zamanda olup bitmiş eylemler için. Türkçedeki "-di" ekine karşılık gelir.
- Düzenli fiiller **-ed** alır: worked, visited. Düzensiz fiillerin V2 biçimi ezberlenir: go → went, see → saw.
- Olumsuz ve soruda **did** kullanılır ve fiil yalın hâle döner: I didn't go. Did you see it? (didn't went değil!)
- Zaman ifadeleri: yesterday, last week, two years ago, in 2019.
''', ['Özne + V2', 'Özne + did not + V1', 'Did + özne + V1?'],
[['We went to Izmir last summer.', 'Geçen yaz İzmir\'e gittik.'], ["I didn't see him yesterday.", 'Dün onu görmedim.']],
[
 ('Dün akşam bir film izledim.', ['I watched a film last night.', 'I watched a movie last night.', 'I watched a film yesterday evening.'], 'Bitmiş geçmiş: V2 (watched).'),
 ('Geçen yıl İspanya\'ya gittik.', ['We went to Spain last year.'], '"go" düzensizdir: went.'),
 ('Toplantıya neden gelmedin?', ["Why didn't you come to the meeting?", 'Why did you not come to the meeting?'], 'Olumsuz soru: Why didn\'t + özne + V1?'),
 ('Anahtarlarımı kaybettim ama sonra buldum.', ['I lost my keys, but then I found them.', 'I lost my keys but I found them later.'], 'lose → lost, find → found.'),
 ('O kitabı iki yıl önce okudum.', ['I read that book two years ago.'], '"ago" ile Simple Past kullanılır; read (V2) aynı yazılır, "red" okunur.'),
 ('Partiye kimse gelmedi.', ['Nobody came to the party.', 'No one came to the party.'], '"Nobody" zaten olumsuzdur; fiil olumlu kalır: Nobody came.'),
])

topic('present_perfect', 'tenses', 'B1', 'Yakın geçmiş zaman', 'Present Perfect', '''
**Ne zaman kullanılır?** Geçmişte olan ama etkisi ya da sonucu şimdiye uzanan eylemler, yaşam deneyimleri ve "hâlâ süren" durumlar için.
- Deneyim: "Hiç Japonya'ya gittin mi?" = Have you ever been to Japan?
- Yeni biten ve sonucu önemli: "Anahtarımı kaybettim (hâlâ yok)" = I've lost my key.
- Süren durum: "Onu on yıldır tanıyorum" = I've known him for ten years.
- **for** + süre (for two years), **since** + başlangıç (since 2020).
- **Dikkat:** yesterday, last year, ago gibi bitmiş zamanlarla kullanılmaz; onlarla Simple Past gerekir.
''', ['Özne + have/has + V3', 'Özne + have/has + not + V3', 'Have/Has + özne + (ever) + V3?'],
[["I've already finished my homework.", 'Ödevimi çoktan bitirdim.'], ['She has lived here since 2015.', '2015\'ten beri burada yaşıyor.']],
[
 ('Hiç sushi yedin mi?', ['Have you ever eaten sushi?', 'Have you ever had sushi?'], 'Deneyim sorusu: Have you ever + V3?'),
 ('Onu yıllardır tanıyorum.', ["I've known him for years.", "I've known her for years.", 'I have known him for years.'], '"for + süre" ile süren durum: have known.'),
 ('Henüz kararımı vermedim.', ["I haven't made my decision yet.", "I haven't decided yet.", "I haven't made up my mind yet."], '"yet" olumsuz cümlede Present Perfect ile kullanılır.'),
 ('Annem az önce aradı.', ['My mother has just called.', 'My mum has just called.', 'My mother just called.'], '"just" yeni olan eylemi gösterir: has just called.'),
 ('2018\'den beri İzmir\'de yaşıyoruz.', ["We've lived in Izmir since 2018.", "We've been living in Izmir since 2018.", 'We have lived in Izmir since 2018.'], '"since + başlangıç" ile Present Perfect gerekir; şimdiki zaman kullanılmaz.'),
 ('Bu filmi üç kez izledim.', ["I've watched this film three times.", "I've seen this film three times.", "I've seen this movie three times."], 'Şimdiye kadarki tekrar sayısı Present Perfect ile söylenir.'),
])

topic('present_perfect_continuous', 'tenses', 'B1', 'Geçmişten beri süregelen zaman', 'Present Perfect Continuous', '''
**Ne zaman kullanılır?** Geçmişte başlayıp şu ana kadar kesintisiz süren (ve çoğu zaman hâlâ devam eden) eylemlerde, özellikle sürenin vurgulandığı durumlarda.
- "İki saattir seni bekliyorum" = I've been waiting for you for two hours.
- Türkçede "-iyorum" desek de **for / since** varsa şimdiki zaman değil bu zaman kullanılır.
- "How long…?" soruları: How long have you been learning English?
- Durum fiilleri (know, have = sahip olmak) bu zamanla kullanılmaz: I've known her for years.
''', ['Özne + have/has + been + V-ing', 'How long + have/has + özne + been + V-ing?'],
[["It's been raining since this morning.", 'Sabahtan beri yağmur yağıyor.'], ["She's been working here for five years.", 'Beş yıldır burada çalışıyor.']],
[
 ('Yarım saattir seni bekliyorum.', ["I've been waiting for you for half an hour.", 'I have been waiting for you for half an hour.'], 'for + süre: have been waiting. "wait" nesneyi "for" ile alır.'),
 ('Ne zamandır İngilizce öğreniyorsun?', ['How long have you been learning English?', 'How long have you been studying English?'], 'Süre sorusu: How long have you been + V-ing?'),
 ('Sabahtan beri kar yağıyor.', ["It's been snowing since this morning.", 'It has been snowing since morning.', "It's been snowing since the morning."], 'since + başlangıç: has been snowing.'),
 ('Üç yıldır bu şirkette çalışıyor.', ["He's been working at this company for three years.", "She's been working for this company for three years.", 'He has been working at this company for three years.'], 'for three years: has been working.'),
 ('Yorgunum çünkü bütün gün ders çalışıyorum.', ["I'm tired because I've been studying all day.", 'I am tired because I have been studying all day.'], 'Şu anki sonucun (yorgunluk) sebebi olan süregelen eylem.'),
 ('Neden ağlıyordun? Gözlerin kırmızı.', ["Why have you been crying? Your eyes are red.", 'Have you been crying? Your eyes are red.'], 'İzi görünen yakın süregelen eylem: have been crying.'),
])

topic('past_perfect', 'tenses', 'B1', "Miş'li geçmişin hikâyesi", 'Past Perfect', '''
**Ne zaman kullanılır?** Geçmişteki iki olaydan **daha önce** olanı anlatmak için. Türkçedeki "-mişti" ekine karşılık gelir.
- "Vardığımızda film başlamıştı" = When we arrived, the film had started.
- Sık kullanılan bağlaçlar: when, by the time, before, after, already.
- Olaylar zaten sırayla anlatılıyorsa Past Perfect şart değildir: I came home and cooked dinner.
''', ['Özne + had + V3', 'By the time / When + Simple Past, özne + had + V3'],
[['The train had left when I got to the station.', 'İstasyona vardığımda tren gitmişti.'], ["I had never seen snow before I moved to Erzurum.", "Erzurum'a taşınmadan önce hiç kar görmemiştim."]],
[
 ('Eve vardığımda herkes uyumuştu.', ['When I got home, everyone had gone to sleep.', 'When I arrived home, everyone had fallen asleep.', 'When I got home, everybody had gone to bed.'], 'Daha önce olan: had + V3.'),
 ('Sınavdan önce kitabı iki kez okumuştum.', ['I had read the book twice before the exam.'], 'Geçmişteki bir andan önce: had read.'),
 ('Biz geldiğimizde toplantı çoktan bitmişti.', ['When we arrived, the meeting had already finished.', 'The meeting had already ended when we arrived.', 'When we came, the meeting had already finished.'], '"already" had ile V3 arasına gelir.'),
 ('Onu daha önce hiç görmemiştim.', ["I had never seen him before.", "I'd never seen her before.", 'I had never seen her before.'], '"never" had ile V3 arasına gelir.'),
 ('Cüzdanımı evde unuttuğumu fark ettim.', ['I realized that I had left my wallet at home.', 'I realised I had left my wallet at home.', 'I noticed that I had forgotten my wallet at home.'], 'Fark etmeden önce olan eylem: had left.'),
 ('Film bittiğinde patlamış mısırı bitirmiştik.', ['We had finished the popcorn by the time the film ended.', 'By the time the movie ended, we had finished the popcorn.'], 'By the time + Simple Past, had + V3.'),
])

topic('future', 'tenses', 'A2', 'Gelecek zaman: will / be going to', 'Future: will / be going to', '''
**İkisi arasındaki fark:**
- **be going to + V1:** önceden verilmiş kararlar ve planlar, ya da belirtisi görülen gelecek: "Seneye araba alacağım (karar verdim)" = I'm going to buy a car next year. "Bak, yağmur yağacak" = Look, it's going to rain.
- **will + V1:** konuşurken anlık verilen kararlar, teklifler, sözler ve tahminler: "Telefon çalıyor, ben bakarım" = The phone's ringing, I'll get it.
- **Dikkat:** will'den sonra fiil yalın gelir (will go, will to go değil). "when, before, after, as soon as" sonrasında gelecek zaman değil geniş zaman kullanılır: I'll call you when I arrive.
''', ['Özne + will + V1', 'Özne + am/is/are + going to + V1'],
[["I think it'll be sunny tomorrow.", 'Bence yarın hava güneşli olacak.'], ["We're going to visit my aunt this weekend.", 'Bu hafta sonu teyzemi ziyaret edeceğiz.']],
[
 ('Merak etme, sana yardım ederim.', ["Don't worry, I'll help you.", 'Do not worry, I will help you.'], 'Anlık teklif ve söz: will.'),
 ('Gelecek yaz Almanya\'da çalışacağım (karar verdim).', ["I'm going to work in Germany next summer.", 'I am going to work in Germany next summer.'], 'Önceden verilmiş karar: be going to.'),
 ('Gökyüzüne bak, yağmur yağacak.', ["Look at the sky, it's going to rain.", "Look at the sky. It's going to rain."], 'Belirtisi görülen gelecek: be going to.'),
 ('Eve varınca seni ararım.', ["I'll call you when I get home.", "I'll call you when I arrive home.", 'I will call you when I get home.'], '"when" sonrasında geniş zaman: when I get home (will get değil).'),
 ('Bence bu sınavı geçeceksin.', ["I think you'll pass this exam.", 'I think you will pass this exam.'], 'Görüşe dayalı tahmin: I think + will.'),
 ('Bu akşam ne pişireceksin?', ['What are you going to cook this evening?', 'What are you going to cook tonight?', 'What will you cook tonight?'], 'Plan sorusu genellikle be going to ile sorulur.'),
])

# ---------------------------------------------------------- conjunctions
topic('although_despite', 'conjunctions', 'B1', 'Although / Despite (rağmen)', 'Although / Despite', '''
**"-e rağmen" anlamını vermenin iki yolu vardır:**
- **although / even though / though + tam cümle (özne + fiil):** although it was raining. "Even though" daha güçlü vurgu katar.
- **despite / in spite of + isim veya V-ing:** despite the rain, despite being tired.
- **Sık yapılan hata:** "although" arkasına isim, "despite" arkasına tam cümle getirmek. "despite of" diye bir yapı yoktur; "in spite of" ya da "despite" denir.
- Cümle olarak kullanmak istersen: despite the fact that + tam cümle.
''', ['Although + özne + fiil, ana cümle', 'Despite / In spite of + isim / V-ing, ana cümle'],
[['Although it was cold, we went swimming.', 'Hava soğuk olmasına rağmen yüzmeye gittik.'], ['Despite the traffic, we arrived on time.', 'Trafiğe rağmen zamanında vardık.']],
[
 ('İş yüküm artmasına rağmen projeyi zamanında bitirebildim.', ['I was able to finish the project on time, although my workload increased.', 'I managed to finish the project on time despite my increased workload.', 'Although my workload increased, I was able to complete the project on time.'], 'although + tam cümle (my workload increased); despite + isim (my increased workload).'),
 ('Yorgun olmasına rağmen bize yardım etti.', ['Although he was tired, he helped us.', 'Despite being tired, she helped us.', 'Even though she was tired, she helped us.'], 'although + özne + fiil; despite + V-ing.'),
 ('Kötü havaya rağmen maç oynandı.', ['Despite the bad weather, the match was played.', 'In spite of the bad weather, the match was played.', 'The match was played despite the bad weather.'], 'İsimle "despite / in spite of" kullanılır.'),
 ('Çok çalışmasına rağmen sınavı geçemedi.', ["Although he studied hard, he couldn't pass the exam.", 'Despite studying hard, she failed the exam.', "Even though she studied a lot, she didn't pass the exam."], '"Çok çalışmak" burada "study hard" ile söylenir.'),
 ('Pahalı olmasına rağmen o telefonu aldım.', ['Although it was expensive, I bought that phone.', 'I bought that phone even though it was expensive.', 'I bought that phone although it was expensive.'], 'although + it was expensive.'),
 ('Yaşına rağmen hâlâ her gün koşuyor.', ['Despite his age, he still runs every day.', 'In spite of her age, she still runs every day.'], '"yaşı" bir isimdir: despite his age.'),
])

topic('because_so', 'conjunctions', 'A2', 'Because / So / Because of', 'Because / So / Because of', '''
**Sebep ve sonuç bağlaçları:**
- **because + tam cümle:** sebebi verir (çünkü / -dığı için). I stayed home because I was ill.
- **because of + isim:** I stayed home because of the rain.
- **so + tam cümle:** sonucu verir (bu yüzden). I was ill, so I stayed home.
- **Dikkat:** Türkçede "-dığı için" cümlenin başında gelse de İngilizcede because ile başlayan kısım genellikle sonra gelir. "because" ve "so" aynı cümlede birlikte kullanılmaz.
''', ['Ana cümle + because + özne + fiil', 'Ana cümle + because of + isim', 'Sebep cümlesi, so + sonuç cümlesi'],
[["I'm hungry because I didn't eat breakfast.", 'Açım çünkü kahvaltı etmedim.'], ['It was late, so we took a taxi.', 'Geç olmuştu, bu yüzden taksiye bindik.']],
[
 ('Hasta olduğu için okula gelmedi.', ["He didn't come to school because he was ill.", "She didn't come to school because she was sick.", 'He did not come to school because he was ill.'], 'because + tam cümle (he was ill).'),
 ('Trafik yüzünden geç kaldım.', ['I was late because of the traffic.', 'I was late due to the traffic.'], 'İsimle "because of" kullanılır.'),
 ('Hava çok sıcaktı, bu yüzden denize girdik.', ['It was very hot, so we went swimming in the sea.', 'It was very hot, so we swam in the sea.', 'It was really hot, so we went into the sea.'], 'Sonuç: so + tam cümle.'),
 ('Param yoktu, bu yüzden o ceketi alamadım.', ["I didn't have any money, so I couldn't buy that jacket.", "I had no money, so I couldn't buy that jacket."], 'so + sonuç; "alamadım" = couldn\'t buy.'),
 ('Yağmur yüzünden piknik iptal edildi.', ['The picnic was cancelled because of the rain.', 'The picnic was canceled because of the rain.'], 'because of + the rain.'),
 ('Erken yattım çünkü çok yorgundum.', ['I went to bed early because I was very tired.', 'I went to bed early because I was really tired.'], 'because + I was very tired.'),
])

topic('unless', 'conjunctions', 'B1', 'Unless (-medikçe)', 'Unless', '''
**unless = if … not.** "-medikçe, -mezse" anlamına gelir.
- "Acele etmezsen treni kaçıracaksın" = You'll miss the train unless you hurry. (= if you don't hurry)
- **Dikkat:** unless zaten olumsuzluk taşır; arkasından gelen fiil olumlu kalır: unless you hurry (unless you don't hurry değil).
- Birinci tip koşul gibi, unless tarafında gelecek zaman değil geniş zaman kullanılır.
''', ['Ana cümle (will + V1) + unless + özne + V1 (geniş zaman)', 'Unless + özne + V1, ana cümle'],
[["We'll be late unless we leave now.", 'Şimdi çıkmazsak geç kalacağız.'], ["Don't call me unless it's urgent.", 'Acil olmadıkça beni arama.']],
[
 ('Acil olmadıkça beni arama.', ["Don't call me unless it's urgent.", 'Do not call me unless it is urgent.'], 'unless + olumlu fiil: unless it\'s urgent.'),
 ('Çok çalışmazsan sınavı geçemezsin.', ["You won't pass the exam unless you study hard.", "Unless you study hard, you won't pass the exam.", "You can't pass the exam unless you study hard."], 'unless you study (= if you don\'t study).'),
 ('Yağmur yağmazsa yarın yürüyüşe çıkarız.', ["We'll go for a walk tomorrow unless it rains.", "Unless it rains, we'll go hiking tomorrow.", "We'll go for a walk tomorrow unless it rains."], 'unless tarafında geniş zaman: unless it rains.'),
 ('Davet edilmedikçe partiye gitmem.', ["I won't go to the party unless I'm invited.", "I won't go to the party unless they invite me."], 'unless + edilgen: unless I\'m invited.'),
 ('Şimdi çıkmazsak otobüsü kaçıracağız.', ["We'll miss the bus unless we leave now.", "Unless we leave now, we'll miss the bus."], 'unless we leave (gelecek zaman değil).'),
 ('Sorun olmadıkça her gün aynı saatte gelir.', ["He comes at the same time every day unless there's a problem.", "She comes at the same time every day unless there is a problem."], 'Genel durum: geniş zaman + unless.'),
])

topic('while_when', 'conjunctions', 'B1', 'When / While / As soon as', 'When / While / As soon as', '''
**Zaman bağlaçları:**
- **when:** -dığında. When I got home, I made tea.
- **while:** -iken, süren bir eylem sırasında (çoğunlukla Past Continuous ile): While I was cooking, the phone rang.
- **as soon as:** -ir -mez. As soon as I arrive, I'll call you.
- **Dikkat:** Bu bağlaçlardan sonra gelecek zaman kullanılmaz: when I arrive (when I will arrive değil).
''', ['While + özne + was/were + V-ing, özne + V2', 'As soon as + özne + V1, özne + will + V1'],
[['While I was walking home, I met an old friend.', 'Eve yürürken eski bir arkadaşla karşılaştım.'], ["I'll text you as soon as I land.", 'İner inmez sana mesaj atarım.']],
[
 ('Yemek yaparken telefon çaldı.', ['While I was cooking, the phone rang.', 'The phone rang while I was cooking.', 'The phone rang while I was making dinner.'], 'Süren eylem (was cooking) + kısa eylem (rang).'),
 ('Eve gelir gelmez duş aldım.', ['As soon as I got home, I had a shower.', 'As soon as I came home, I took a shower.'], 'as soon as = -ir -mez.'),
 ('Çocukken her yaz köye giderdik.', ['When I was a child, we used to go to the village every summer.', 'When I was a kid, we went to the village every summer.', 'When I was a child, we would go to the village every summer.'], 'when = -ken / -dığında; geçmiş alışkanlık: used to / would.'),
 ('Haberi duyunca çok şaşırdım.', ['When I heard the news, I was very surprised.', 'I was really surprised when I heard the news.'], 'when + Simple Past.'),
 ('Ben işteyken çocuklara annem bakıyor.', ['While I am at work, my mother looks after the children.', "While I'm at work, my mum takes care of the kids."], 'while = -iken; "bakmak" = look after / take care of.'),
 ('Mezun olunca yurt dışında çalışmak istiyorum.', ['When I graduate, I want to work abroad.', 'After I graduate, I want to work abroad.'], 'when + geniş zaman (graduate), gelecek zaman değil.'),
])

# ---------------------------------------------------------- conditionals
topic('first_conditional', 'conditionals', 'A2', 'Birinci tip koşul', 'First Conditional', '''
**Ne zaman kullanılır?** Gelecekte gerçekleşmesi mümkün olan koşullar ve sonuçları için.
- "Yağmur yağarsa evde kalırız" = If it rains, we'll stay at home.
- **if tarafında geniş zaman**, ana cümlede **will + V1** kullanılır.
- **Sık yapılan hata:** if tarafında will kullanmak: If it will rain… yanlıştır.
''', ['If + özne + V1 (geniş zaman), özne + will + V1'],
[["If you hurry, you'll catch the bus.", 'Acele edersen otobüse yetişirsin.'], ["If I see him, I'll tell him.", 'Onu görürsem söylerim.']],
[
 ('Vaktim olursa seni ararım.', ["If I have time, I'll call you.", 'If I have time, I will call you.'], 'if + geniş zaman (have), will + V1.'),
 ('Hava güzel olursa pikniğe gideceğiz.', ["If the weather is nice, we'll go on a picnic.", "If the weather is good, we'll have a picnic.", "We'll go on a picnic if the weather is nice."], 'if tarafında will kullanılmaz: If the weather is nice.'),
 ('Erken yatarsan yarın yorgun olmazsın.', ["If you go to bed early, you won't be tired tomorrow.", 'If you go to bed early, you will not be tired tomorrow.'], 'Olumsuz sonuç: won\'t + V1.'),
 ('Bu ilacı alırsan kendini daha iyi hissedersin.', ["If you take this medicine, you'll feel better.", 'If you take this medicine, you will feel better.'], '"İlaç almak" = take medicine.'),
 ('Acele etmezsek geç kalacağız.', ["If we don't hurry, we'll be late.", 'If we do not hurry, we will be late.'], 'if + olumsuz geniş zaman: if we don\'t hurry.'),
 ('Fiyatı düşerse o arabayı alacağım.', ["If the price goes down, I'll buy that car.", "If the price drops, I'll buy that car."], 'if + geniş zaman: goes down / drops.'),
])

topic('second_conditional', 'conditionals', 'B1', 'İkinci tip koşul', 'Second Conditional', '''
**Ne zaman kullanılır?** Şimdiki zamanda gerçek olmayan ya da olasılığı düşük, hayalî durumlar için. Türkçedeki "-se … -erdi" yapısına karşılık gelir.
- "Zengin olsaydım dünyayı gezerdim" = If I were rich, I would travel the world.
- **if tarafında Simple Past (V2)**, ana cümlede **would + V1**.
- "be" fiili için tüm öznelerde **were** kullanmak doğrudur: If I were you…
- **Dikkat:** if tarafında would kullanılmaz: If I would have… yanlıştır.
''', ['If + özne + V2 (were), özne + would + V1'],
[["If I had more time, I would learn Spanish.", 'Daha fazla zamanım olsaydı İspanyolca öğrenirdim.'], ["If I were you, I wouldn't accept that offer.", 'Yerinde olsam o teklifi kabul etmezdim.']],
[
 ('Yerinde olsam ona doğruyu söylerdim.', ['If I were you, I would tell him the truth.', "If I were you, I'd tell her the truth."], 'Tavsiye kalıbı: If I were you, I would…'),
 ('Arabam olsaydı seni havaalanına götürürdüm.', ['If I had a car, I would take you to the airport.', "If I had a car, I'd drive you to the airport."], 'if + V2 (had), would + V1.'),
 ('Daha çok param olsaydı daha büyük bir eve taşınırdık.', ['If we had more money, we would move to a bigger house.', "If we had more money, we'd move to a bigger house."], 'Şimdiki gerçek dışı durum: if + had.'),
 ('İngilizcem daha iyi olsaydı o işe başvururdum.', ['If my English were better, I would apply for that job.', "If my English was better, I'd apply for that job."], '"apply for a job" = işe başvurmak.'),
 ('Piyangoyu kazansan ne yapardın?', ['What would you do if you won the lottery?', 'If you won the lottery, what would you do?'], 'Soru: What would you do if + V2?'),
 ('Bu kadar yorgun olmasaydım seninle gelirdim.', ["If I weren't so tired, I would come with you.", "If I wasn't so tired, I'd come with you."], 'Olumsuz koşul: if I weren\'t.'),
])

topic('third_conditional', 'conditionals', 'B2', 'Üçüncü tip koşul', 'Third Conditional', '''
**Ne zaman kullanılır?** Geçmişte gerçekleşmemiş bir durumu ve onun hayalî sonucunu anlatmak için. Türkçedeki "-seydi … -ardı / -mış olurdu" yapısı.
- "Erken kalksaydım treni kaçırmazdım" = If I had got up early, I wouldn't have missed the train.
- **if tarafında Past Perfect (had + V3)**, ana cümlede **would have + V3**.
- **Dikkat:** if tarafında would have kullanılmaz: If I would have known… yanlıştır.
''', ['If + özne + had + V3, özne + would have + V3'],
[["If I had known, I would have helped you.", 'Bilseydim sana yardım ederdim.'], ["If we had left earlier, we wouldn't have missed the flight.", 'Daha erken çıksaydık uçağı kaçırmazdık.']],
[
 ('Eğer kararı daha önce verseydin, bu kadar zaman kaybetmezdik.', ["If you had made the decision earlier, we wouldn't have lost so much time.", "If you had decided earlier, we wouldn't have wasted so much time.", 'If you had made the decision sooner, we would not have lost so much time.'], 'if + had + V3 (had made), wouldn\'t have + V3 (lost / wasted).'),
 ('Senin geleceğini bilseydim pasta yapardım.', ['If I had known you were coming, I would have made a cake.', "If I had known you were coming, I'd have baked a cake."], 'if + had known, would have + V3.'),
 ('Daha çok çalışsaydı sınavı geçerdi.', ['If he had studied harder, he would have passed the exam.', "If she had studied more, she'd have passed the exam."], 'Geçmişte gerçekleşmemiş koşul: had studied.'),
 ('Alarm çalsaydı geç kalmazdım.', ["If the alarm had gone off, I wouldn't have been late.", 'If my alarm had rung, I would not have been late.'], '"Alarm çalmak" = the alarm goes off.'),
 ('Bana sorsaydın sana yardım ederdim.', ['If you had asked me, I would have helped you.', "If you'd asked me, I'd have helped you."], 'if + had asked, would have helped.'),
 ('Haritaya baksaydık kaybolmazdık.', ["If we had looked at the map, we wouldn't have got lost.", "If we had checked the map, we wouldn't have gotten lost."], '"Kaybolmak" = get lost: wouldn\'t have got lost.'),
])

# -------------------------------------------------------------- modals
topic('obligation', 'modals', 'A2', 'Must / Have to / Should', 'Must / Have to / Should', '''
**Zorunluluk ve tavsiye:**
- **must + V1:** konuşanın gerekli gördüğü zorunluluk, kesin kurallar (-meli, -malı). You must wear a seatbelt.
- **have to + V1:** dış kurallardan gelen zorunluluk (-mek zorunda). I have to work on Saturdays.
- **should + V1:** tavsiye (-meli, iyi olur). You should see a doctor.
- **don't have to:** gerek yok. **mustn't:** yasak. Bu ikisi çok farklıdır!
- Modallardan sonra "to" gelmez ve fiil -s almaz: She must go (She must to go / must goes değil). Geçmişte "must" yerine "had to" kullanılır.
''', ['Özne + must / should + V1', 'Özne + have/has to + V1', "Özne + don't have to / mustn't + V1"],
[['You should drink more water.', 'Daha çok su içmelisin.'], ["You don't have to come if you're busy.", 'Meşgulsen gelmek zorunda değilsin.']],
[
 ('Bir doktora görünmelisin.', ['You should see a doctor.', 'You should go to a doctor.'], 'Tavsiye: should + V1.'),
 ('Yarın erken kalkmak zorundayım.', ['I have to get up early tomorrow.', 'I have to wake up early tomorrow.'], 'Dışarıdan gelen zorunluluk: have to.'),
 ('Burada sigara içmemelisiniz, yasak.', ["You mustn't smoke here; it's forbidden.", "You mustn't smoke here. It's not allowed.", 'You must not smoke here, it is forbidden.'], 'Yasak: mustn\'t + V1.'),
 ('Cumartesi çalışmak zorunda değilim.', ["I don't have to work on Saturday.", "I don't have to work on Saturdays."], 'Gerek yok: don\'t have to.'),
 ('Dün akşam geç saate kadar çalışmak zorunda kaldım.', ['I had to work late last night.', 'I had to work until late last night.'], 'Geçmişte zorunluluk: had to.'),
 ('Anneme daha sık telefon etmeliyim.', ['I should call my mother more often.', 'I should phone my mum more often.'], 'should + V1; "more often" sonda.'),
])

topic('ability', 'modals', 'A2', 'Can / Could / Be able to', 'Can / Could / Be able to', '''
**Yetenek ve olasılık:**
- **can + V1:** şimdiki yetenek (-ebilmek). I can swim.
- **could + V1:** geçmişteki genel yetenek: When I was five, I could read.
- **was/were able to, managed to:** geçmişte belli bir durumda başarılan iş: I was able to finish the project on time.
- **will be able to:** gelecekte yetenek. İki modal yan yana gelmez: will can yanlıştır.
- Kibar rica: Could you help me? (Can you'dan daha kibar.)
''', ['Özne + can / could + V1', 'Özne + was/were able to + V1', 'Özne + will be able to + V1'],
[['She can speak three languages.', 'Üç dil konuşabiliyor.'], ["I'll be able to help you next week.", 'Gelecek hafta sana yardım edebileceğim.']],
[
 ('Üç yaşındayken yüzebiliyordum.', ['I could swim when I was three.', 'When I was three, I could swim.', 'I was able to swim when I was three years old.'], 'Geçmişteki genel yetenek: could.'),
 ('Pencereyi açabilir misiniz, lütfen?', ['Could you open the window, please?', 'Could you please open the window?', 'Can you open the window, please?'], 'Kibar rica: Could you…?'),
 ('Gelecek yıl araba kullanabileceğim.', ["I'll be able to drive next year.", 'I will be able to drive next year.'], 'Gelecekte yetenek: will be able to (will can değil).'),
 ('Sonunda anahtarı bulabildim.', ['I was finally able to find the key.', 'I finally managed to find the key.', 'Finally, I was able to find the key.'], 'Belli bir durumda başarı: was able to / managed to.'),
 ('Bu gürültüde seni duyamıyorum.', ["I can't hear you in this noise.", "I can't hear you with all this noise."], 'Şimdiki yetersizlik: can\'t + V1.'),
 ('Kardeşim çok iyi gitar çalabilir.', ['My brother can play the guitar very well.', 'My sister can play the guitar really well.'], 'can + V1 (-s almaz): can play.'),
])

# -------------------------------------------------------------- passive
topic('passive', 'passive', 'B1', 'Edilgen yapı', 'Passive Voice', '''
**Ne zaman kullanılır?** Eylemi kimin yaptığı bilinmediğinde, önemli olmadığında ya da asıl önemli olan eylemin kendisi olduğunda. Türkçedeki "-ıl, -ın" (yapıldı, yazılır) ekine karşılık gelir.
- Yapı: **be + V3.** Zamanı "be" fiili gösterir: is made, was built, has been sold, will be finished.
- Yapanı söylemek istersen **by** kullanılır: The book was written by Orhan Pamuk.
- **Dikkat:** "doğmak" İngilizcede edilgendir: I was born in 1995.
''', ['Özne + am/is/are + V3 (geniş zaman)', 'Özne + was/were + V3 (geçmiş)', 'Özne + has/have been + V3', 'Özne + will be + V3'],
[['This bridge was built in 1973.', 'Bu köprü 1973\'te yapıldı.'], ['English is spoken all over the world.', 'İngilizce bütün dünyada konuşulur.']],
[
 ('Bu ev 1950\'de yapıldı.', ['This house was built in 1950.'], 'Geçmiş edilgen: was + V3.'),
 ('Arabam dün gece çalındı.', ['My car was stolen last night.'], 'steal → stole → stolen: was stolen.'),
 ('Toplantı yarına ertelendi.', ['The meeting has been postponed until tomorrow.', 'The meeting was postponed to tomorrow.', 'The meeting has been put off until tomorrow.'], 'Edilgen; "ertelemek" = postpone / put off.'),
 ('Bu roman otuz dile çevrildi.', ['This novel has been translated into thirty languages.', 'This novel has been translated into 30 languages.', 'This novel was translated into thirty languages.'], '"translate into" = -e çevirmek.'),
 ('Sonuçlar gelecek hafta açıklanacak.', ['The results will be announced next week.'], 'Gelecek edilgen: will be + V3.'),
 ('1998\'de İstanbul\'da doğdum.', ['I was born in Istanbul in 1998.', 'I was born in 1998 in Istanbul.'], '"Doğmak" edilgendir: I was born.'),
])

# ------------------------------------------------------------- reported
topic('reported_speech', 'reported', 'B2', 'Dolaylı anlatım', 'Reported Speech', '''
**Ne zaman kullanılır?** Birinin söylediğini aktarırken. Aktarma fiili geçmişteyse (said, told, asked) zaman genellikle bir derece geri gider.
- am/is → was, present → past, will → would, can → could, past → past perfect.
- **say** kişi almaz (said that…), **tell** kişi alır (told me that…). said me yanlıştır.
- Soruları aktarırken soru sırası kullanılmaz: She asked me where I lived (where did I live değil). Evet/hayır soruları için **if / whether**.
''', ['Özne + said (that) + cümle (bir zaman geri)', 'Özne + told + kişi + (that) + cümle', 'Özne + asked + (kişi) + soru kelimesi / if + özne + fiil'],
[['He said that he was tired.', 'Yorgun olduğunu söyledi.'], ['She asked me if I could help her.', 'Ona yardım edip edemeyeceğimi sordu.']],
[
 ('Bana yorgun olduğunu söyledi.', ['He told me that he was tired.', 'She told me she was tired.', 'He said that he was tired.'], 'tell + kişi: told me; is → was.'),
 ('Ertesi gün geleceğini söyledi.', ['She said that she would come the next day.', 'He said he would come the following day.'], 'will → would; tomorrow → the next day.'),
 ('Bana nerede yaşadığımı sordu.', ['She asked me where I lived.', 'He asked me where I lived.'], 'Aktarılan soruda düz sıra: where I lived.'),
 ('Öğretmen bize ödevi bitirip bitirmediğimizi sordu.', ['The teacher asked us if we had finished the homework.', 'The teacher asked us whether we had finished our homework.'], 'Evet/hayır sorusu: if / whether; have finished → had finished.'),
 ('Annem bana geç kalmamamı söyledi.', ['My mother told me not to be late.', 'My mum told me not to be late.'], 'Olumsuz emir: told me not to + V1.'),
 ('Yüzme bilmediğini söyledi.', ["He said that he couldn't swim.", "She said she couldn't swim.", 'He said that he could not swim.'], 'can → could.'),
])

# -------------------------------------------------------------- clauses
topic('relative_clauses', 'clauses', 'B1', 'Sıfat cümlecikleri (who / which / that)', 'Relative Clauses', '''
**Ne zaman kullanılır?** Bir ismi niteleyen cümlecikler için. Türkçedeki "-en, -dığı" eklerine karşılık gelir.
- **who:** insanlar için. The woman who lives next door is a doctor.
- **which:** şeyler ve hayvanlar için. The car which I bought is red.
- **that:** her ikisi için de kullanılabilir (günlük dilde çok yaygın).
- **where:** yerler için. This is the café where we met.
- **whose:** sahiplik. The man whose car was stolen.
- Cümleciğin nesnesi olan kişi/şey için who/which/that düşürülebilir: The book (that) you gave me.
''', ['İsim + who/that + fiil …', 'İsim + (which/that) + özne + fiil …', 'Yer + where + özne + fiil'],
[['The man who called you is my uncle.', 'Seni arayan adam amcam.'], ['This is the book I told you about.', 'Bu sana bahsettiğim kitap.']],
[
 ('Yan dairede oturan kadın bir doktor.', ['The woman who lives next door is a doctor.', 'The woman who lives in the next flat is a doctor.', 'The woman that lives next door is a doctor.'], 'İnsan için who: the woman who lives…'),
 ('Bana verdiğin kitabı çok sevdim.', ['I really liked the book you gave me.', 'I loved the book that you gave me.', 'I really liked the book which you gave me.'], 'Nesne konumunda which/that düşebilir: the book (that) you gave me.'),
 ('Bu, ilk tanıştığımız kafe.', ['This is the café where we first met.', 'This is the cafe where we met for the first time.'], 'Yer için where.'),
 ('Arabası çalınan adam polisi aradı.', ['The man whose car was stolen called the police.'], 'Sahiplik: whose.'),
 ('İngilizce konuşabilen birini arıyoruz.', ['We are looking for someone who can speak English.', "We're looking for somebody who can speak English."], 'someone who + fiil.'),
 ('Dün izlediğimiz film çok sıkıcıydı.', ['The film we watched yesterday was very boring.', 'The movie that we watched yesterday was really boring.'], 'Nesne konumu: the film (that) we watched.'),
])

topic('indirect_questions', 'clauses', 'B1', 'Dolaylı sorular', 'Indirect Questions', '''
**Ne zaman kullanılır?** Kibar sorularda: Do you know…? Can you tell me…? I wonder…
- Soru, büyük bir cümlenin içine girdiğinde **düz cümle sırası** kullanılır (özne + fiil): Do you know where the station is? (where is the station değil)
- do/does/did kullanılmaz: Can you tell me what time it starts? (what time does it start değil)
- Evet/hayır soruları için **if / whether**: Do you know if he is at home?
''', ['Do you know / Can you tell me + soru kelimesi + özne + fiil?', '… + if/whether + özne + fiil?'],
[['Could you tell me where the toilet is?', 'Tuvaletin nerede olduğunu söyleyebilir misiniz?'], ['I wonder why she left.', 'Neden gittiğini merak ediyorum.']],
[
 ('İstasyonun nerede olduğunu biliyor musunuz?', ['Do you know where the station is?'], 'Düz sıra: where the station is.'),
 ('Filmin saat kaçta başladığını söyleyebilir misin?', ['Can you tell me what time the film starts?', 'Could you tell me what time the movie starts?'], 'does kullanılmaz: what time the film starts.'),
 ('Onun evde olup olmadığını biliyor musun?', ['Do you know if he is at home?', "Do you know whether she's at home?"], 'Evet/hayır: if / whether.'),
 ('Neden geç kaldığını merak ediyorum.', ['I wonder why he was late.', 'I wonder why she was late.'], 'I wonder + why + özne + fiil.'),
 ('Bu çantanın ne kadar olduğunu söyleyebilir misiniz?', ['Could you tell me how much this bag is?', 'Can you tell me how much this bag costs?'], 'how much this bag is / costs.'),
 ('Ne demek istediğini anlamadım.', ["I didn't understand what you meant.", "I don't understand what you mean."], 'what you meant (düz sıra).'),
])

# ---------------------------------------------------------------- forms
topic('gerund_infinitive', 'forms', 'B1', 'V-ing mi, to + V1 mi?', 'Gerund or Infinitive', '''
**Bazı fiillerden sonra -ing, bazılarından sonra to + V1 gelir; ezberlemek gerekir.**
- **-ing alanlar:** enjoy, finish, avoid, mind, suggest, keep, consider, give up: I enjoy reading.
- **to + V1 alanlar:** want, decide, hope, plan, agree, promise, need, would like: I decided to leave.
- Edatlardan sonra (in, at, of, about, without, before, after) her zaman -ing gelir: I'm good at cooking. look forward to seeing you.
- **stop:** stop smoking (bırakmak) ile stop to smoke (sigara içmek için durmak) farklıdır.
''', ['enjoy / finish / avoid + V-ing', 'want / decide / hope + to + V1', 'Edat + V-ing'],
[['I enjoy cooking for my friends.', 'Arkadaşlarım için yemek yapmaktan hoşlanırım.'], ['We decided to stay at home.', 'Evde kalmaya karar verdik.']],
[
 ('Kitap okumaktan hoşlanırım.', ['I enjoy reading books.', 'I enjoy reading.'], 'enjoy + V-ing.'),
 ('Yeni bir iş aramaya karar verdim.', ['I decided to look for a new job.', "I've decided to look for a new job."], 'decide + to + V1.'),
 ('Sigarayı bırakmalısın.', ['You should give up smoking.', 'You should stop smoking.', 'You should quit smoking.'], 'give up / stop / quit + V-ing.'),
 ('Seni görmeyi dört gözle bekliyorum.', ["I'm looking forward to seeing you.", 'I am looking forward to seeing you.', 'I look forward to seeing you.'], 'look forward to + V-ing (to bir edattır).'),
 ('Pencereyi açmamın sakıncası var mı?', ['Do you mind if I open the window?', 'Would you mind if I opened the window?', 'Do you mind me opening the window?'], 'mind + V-ing / mind if…'),
 ('Hiçbir şey söylemeden çıktı gitti.', ['He left without saying anything.', 'She left without saying a word.'], 'without + V-ing.'),
])

topic('used_to', 'forms', 'B1', 'Used to / Be used to', 'Used to / Be used to', '''
**İki farklı yapı:**
- **used to + V1:** eskiden yapılan ama artık yapılmayan alışkanlıklar (-erdim). I used to play football. Olumsuz/soru: didn't use to, did you use to?
- **be used to + V-ing / isim:** bir şeye alışkın olmak. I'm used to getting up early.
- **get used to + V-ing / isim:** bir şeye alışmak (süreç). I'm getting used to the cold.
''', ['Özne + used to + V1', 'Özne + am/is/are used to + V-ing', 'Özne + get used to + V-ing'],
[['I used to live in Ankara.', 'Eskiden Ankara\'da yaşardım.'], ["She isn't used to driving on the left.", 'Soldan araba kullanmaya alışkın değil.']],
[
 ('Eskiden her gün sigara içerdim.', ['I used to smoke every day.'], 'Geçmiş alışkanlık: used to + V1.'),
 ('Erken kalkmaya alışkınım.', ["I'm used to getting up early.", 'I am used to waking up early.'], 'be used to + V-ing.'),
 ('Yeni işime yavaş yavaş alışıyorum.', ["I'm slowly getting used to my new job.", "I'm gradually getting used to my new job."], 'get used to + isim: alışma süreci.'),
 ('Çocukken sebze sevmezdim.', ["I didn't use to like vegetables when I was a child.", "When I was a kid, I didn't use to like vegetables."], 'Olumsuz: didn\'t use to + V1.'),
 ('Burada eskiden bir sinema vardı.', ['There used to be a cinema here.'], 'There used to be: eskiden … vardı.'),
 ('Soğuk havaya alışamadım.', ["I couldn't get used to the cold weather.", "I haven't got used to the cold weather.", "I can't get used to the cold weather."], 'get used to + isim.'),
])

# ----------------------------------------------------------- comparison
topic('comparison', 'comparison', 'A2', 'Karşılaştırma ve üstünlük', 'Comparatives and Superlatives', '''
**Karşılaştırma (daha …):**
- Kısa sıfatlar **-er + than:** taller than, cheaper than. Uzun sıfatlar **more + sıfat + than:** more expensive than.
- **Dikkat:** ikisi birlikte kullanılmaz: more taller yanlıştır.
**Üstünlük (en …):** **the + -est** (the tallest) ya da **the most + sıfat** (the most beautiful).
- Düzensizler: good → better → the best, bad → worse → the worst, far → farther/further.
- Eşitlik: as + sıfat + as: as tall as. Olumsuz: not as … as.
''', ['Sıfat-er / more + sıfat + than', 'the + sıfat-est / the most + sıfat', 'as + sıfat + as'],
[['My brother is taller than me.', 'Ağabeyim benden uzun.'], ['This is the best restaurant in the city.', 'Bu, şehrin en iyi restoranı.']],
[
 ('İstanbul, Ankara\'dan daha kalabalık.', ['Istanbul is more crowded than Ankara.'], 'İki heceli -ed sıfatı: more crowded than.'),
 ('Bu, hayatımda okuduğum en ilginç kitap.', ["This is the most interesting book I've ever read.", 'This is the most interesting book I have ever read.'], 'the most + uzun sıfat; ever + Present Perfect.'),
 ('Benim telefonum seninki kadar pahalı değil.', ["My phone isn't as expensive as yours.", 'My phone is not as expensive as yours.'], 'not as … as.'),
 ('Bugün hava dünden daha kötü.', ['The weather is worse today than yesterday.', "Today's weather is worse than yesterday's."], 'bad → worse.'),
 ('Ailemin en küçüğü benim.', ["I'm the youngest in my family.", 'I am the youngest in my family.'], 'the + -est: the youngest; "in my family".'),
 ('Ne kadar çok pratik yaparsan o kadar iyi olursun.', ['The more you practise, the better you get.', 'The more you practice, the better you become.'], 'The more …, the better …'),
])

# ===================================================== more topics (v2)
# ------------------------------------------------------------------ tenses
topic('past_continuous', 'tenses', 'A2', 'Geçmişte süren zaman', 'Past Continuous', '''
**Ne zaman kullanılır?** Geçmişte belli bir anda sürmekte olan eylemler için. Türkçedeki "-iyordu" ekine karşılık gelir.
- "Dün akşam sekizde yemek yiyordum" = I was eating dinner at eight last night.
- Uzun süren eylemin ortasında kısa bir eylem olduğunda: süren eylem **was/were + V-ing**, araya giren eylem **Simple Past**: I was walking home when it started to rain.
- Aynı anda süren iki eylem **while** ile bağlanır: While I was cooking, he was watching TV.
- I, he, she, it ile **was**; you, we, they ile **were**.
''', ['Özne + was/were + V-ing', 'Özne + was/were + not + V-ing', 'Was/Were + özne + V-ing?'],
[['I was reading when the phone rang.', 'Telefon çaldığında kitap okuyordum.'], ['What were you doing at ten last night?', 'Dün gece saat onda ne yapıyordun?']],
[
 ('Dün akşam saat sekizde televizyon izliyordum.', ['I was watching TV at eight last night.', 'I was watching television at eight o\'clock yesterday evening.', 'At eight last night, I was watching TV.'], 'Geçmişte belli bir anda süren eylem: was + V-ing.'),
 ('Sen aradığında duş alıyordum.', ['I was having a shower when you called.', 'I was taking a shower when you called.', 'When you called, I was having a shower.'], 'Süren eylem was + V-ing, araya giren eylem V2: called.'),
 ('Çocuklar uyurken biz film izliyorduk.', ['While the children were sleeping, we were watching a film.', 'We were watching a movie while the kids were sleeping.'], 'Aynı anda süren iki eylem: while + Past Continuous.'),
 ('Eve yürürken yağmur başladı.', ['It started to rain while I was walking home.', 'While I was walking home, it started raining.', 'It began to rain while I was walking home.'], 'Uzun eylem: was walking; kısa eylem: started.'),
 ('O sırada ne yapıyordun?', ['What were you doing at that time?', 'What were you doing then?'], 'Soru: What were you doing…?'),
 ('Ders sırasında dinlemiyordum, o yüzden anlamadım.', ["I wasn't listening during the lesson, so I didn't understand.", "I wasn't listening in class, so I didn't understand."], 'Olumsuz: wasn\'t + V-ing.'),
])

topic('future_continuous_perfect', 'tenses', 'B2', 'Gelecekte süren ve bitmiş zaman', 'Future Continuous / Future Perfect', '''
**İki ileri gelecek zaman:**
- **will be + V-ing (Future Continuous):** gelecekte belli bir anda sürmekte olacak eylem (-iyor olacağım). This time tomorrow I'll be flying to London.
- **will have + V3 (Future Perfect):** gelecekte belli bir zamandan önce bitmiş olacak eylem (-miş olacağım). By 2030 I will have finished university.
- Future Perfect çoğunlukla **by** ile kullanılır: by Friday, by the time you arrive, by next year.
- **Dikkat:** by the time'dan sonra gelen yan cümle Simple Present olur: by the time you arrive (will arrive değil).
''', ['Özne + will be + V-ing', 'Özne + will have + V3', 'By + zaman, özne + will have + V3'],
[["This time next week, I'll be lying on the beach.", 'Gelecek hafta bu saatlerde plajda uzanıyor olacağım.'], ["By the time you get home, I'll have cooked dinner.", 'Sen eve gelene kadar yemeği pişirmiş olacağım.']],
[
 ('Yarın bu saatte sınava giriyor olacağım.', ["This time tomorrow I'll be taking an exam.", 'At this time tomorrow, I will be taking the exam.', "This time tomorrow I'll be sitting an exam."], 'Gelecekte belli bir anda süren eylem: will be + V-ing.'),
 ('Cumaya kadar raporu bitirmiş olacağım.', ["I'll have finished the report by Friday.", 'I will have finished the report by Friday.', 'By Friday, I will have finished the report.'], 'by + zaman: will have + V3.'),
 ('Saat dokuzda toplantıda olacağım, beni aramayın.', ["I'll be having a meeting at nine, so don't call me.", "I'll be in a meeting at nine, so don't call me."], 'Gelecekte süren durum: will be + V-ing ya da will be in a meeting.'),
 ('Sen geldiğinde biz yemeği yemiş olacağız.', ['We will have eaten by the time you arrive.', "By the time you come, we'll have had dinner.", "We'll have eaten when you arrive."], 'by the time + Simple Present, ana cümle will have + V3.'),
 ('Gelecek yıl bu zamanlar yeni evimizde yaşıyor olacağız.', ["This time next year we'll be living in our new house.", 'At this time next year, we will be living in our new home.'], 'This time next year + will be + V-ing.'),
 ('Haziran ayına kadar on kitap okumuş olacağım.', ["I'll have read ten books by June.", 'By June, I will have read ten books.'], 'by June: will have + V3 (read).'),
])

# ---------------------------------------------------------- conditionals
topic('zero_conditional', 'conditionals', 'A2', 'Sıfırıncı tip koşul', 'Zero Conditional', '''
**Ne zaman kullanılır?** Her zaman doğru olan sonuçlar, bilimsel gerçekler ve alışkanlıklar için. "Eğer … -rsa, … -r" anlamı taşır ve if yerine **when** de kullanılabilir.
- "Buzu ısıtırsan erir" = If you heat ice, it melts.
- **İki tarafta da Simple Present** kullanılır.
- Talimatlarda ana cümle emir olabilir: If you feel sick, call me.
''', ['If/When + özne + V1, özne + V1', 'If + özne + V1, emir cümlesi'],
[['If you mix red and blue, you get purple.', 'Kırmızıyla maviyi karıştırırsan mor elde edersin.'], ['When I drink coffee at night, I can\'t sleep.', 'Gece kahve içtiğimde uyuyamam.']],
[
 ('Suyu ısıtırsan kaynar.', ['If you heat water, it boils.', 'When you heat water, it boils.'], 'Genel doğru: if + V1, V1.'),
 ('Geç yattığımda sabah yorgun olurum.', ["When I go to bed late, I'm tired in the morning.", 'If I go to bed late, I feel tired in the morning.'], 'Alışkanlık: when + V1, V1.'),
 ('Bitkiler su almazsa ölür.', ["If plants don't get water, they die.", "Plants die if they don't get water."], 'Olumsuz koşul: if + don\'t + V1.'),
 ('Kendini kötü hissedersen beni ara.', ['If you feel bad, call me.', 'If you feel sick, call me.', 'Call me if you feel unwell.'], 'Talimat: if + V1, emir.'),
 ('Annem kızdığında sesini yükseltmez.', ["When my mother gets angry, she doesn't raise her voice.", "My mum doesn't raise her voice when she gets angry."], 'when + V1 (gets), V1 (doesn\'t raise).'),
 ('Buzu güneşte bırakırsan erir.', ['If you leave ice in the sun, it melts.', 'Ice melts if you leave it in the sun.'], 'Bilimsel gerçek: iki tarafta Simple Present.'),
])

topic('mixed_conditionals', 'conditionals', 'C1', 'Karışık koşul cümleleri', 'Mixed Conditionals', '''
**Ne zaman kullanılır?** Koşul ile sonuç farklı zamanlara ait olduğunda.
- **Geçmişteki koşul → şimdiki sonuç:** If + had + V3, would + V1. "Dün gece uyusaydım şimdi yorgun olmazdım" = If I had slept last night, I wouldn't be tired now.
- **Şimdiki/kalıcı durum → geçmişteki sonuç:** If + V2, would have + V3. "İngilizcem iyi olsaydı o işi alırdım" = If my English were better, I would have got that job.
- İpucu: "now, today" görürsen sonuç tarafı would + V1; geçmişte olmuş bir olay görürsen would have + V3.
''', ['If + had + V3, özne + would + V1 (now)', 'If + V2, özne + would have + V3'],
[["If I had taken the job, I would be living in London now.", 'O işi kabul etseydim şimdi Londra\'da yaşıyor olurdum.'], ["If she weren't so shy, she would have spoken to him.", 'Bu kadar utangaç olmasaydı onunla konuşurdu.']],
[
 ('Dün gece erken yatsaydım şimdi yorgun olmazdım.', ["If I had gone to bed early last night, I wouldn't be tired now.", "If I'd gone to bed earlier last night, I wouldn't be tired now."], 'Geçmiş koşul (had gone) → şimdiki sonuç (wouldn\'t be).'),
 ('Haritayı alsaydık şimdi kaybolmuş olmazdık.', ["If we had taken the map, we wouldn't be lost now.", "If we'd brought the map, we wouldn't be lost now."], 'had + V3 → would + be + now.'),
 ('Tıp okusaydım şimdi doktor olurdum.', ['If I had studied medicine, I would be a doctor now.', "If I'd studied medicine, I'd be a doctor now."], 'Geçmişteki seçim → bugünkü durum.'),
 ('Bu kadar tembel olmasaydı sınavı geçerdi.', ["If he weren't so lazy, he would have passed the exam.", "If she wasn't so lazy, she'd have passed the exam."], 'Kalıcı özellik (weren\'t lazy) → geçmiş sonuç (would have passed).'),
 ('Fransızca bilseydim dün onlara yardım ederdim.', ['If I spoke French, I would have helped them yesterday.', "If I knew French, I'd have helped them yesterday."], 'Şimdiki durum (spoke/knew) → geçmişteki sonuç.'),
 ('O uçağa binseydik şimdi Paris\'te olurduk.', ['If we had caught that plane, we would be in Paris now.', "If we'd taken that flight, we'd be in Paris now."], 'had + V3 → would be + now.'),
])

topic('wish', 'conditionals', 'B2', 'Keşke (wish / if only)', 'Wish / If only', '''
**Keşke cümleleri:**
- **Şimdi için (keşke … olsa):** wish + V2. I wish I had a car. I wish I were taller.
- **Geçmiş için (keşke … olsaydı):** wish + had + V3. I wish I had studied harder.
- **Başkasının davranışından yakınma:** wish + would + V1. I wish you would stop talking.
- **If only** aynı yapıyla kullanılır ve daha güçlü bir duygu katar: If only I knew!
- **Dikkat:** Türkçede "keşke" her zaman aynıdır, İngilizcede zaman bir geriye kayar.
''', ['Özne + wish + özne + V2 (şimdi)', 'Özne + wish + özne + had + V3 (geçmiş)', 'Özne + wish + özne + would + V1 (yakınma)'],
[['I wish I could speak Japanese.', 'Keşke Japonca konuşabilsem.'], ["I wish I hadn't said that.", 'Keşke bunu söylemeseydim.']],
[
 ('Keşke daha çok boş zamanım olsa.', ['I wish I had more free time.', 'If only I had more free time.'], 'Şimdi için: wish + V2 (had).'),
 ('Keşke o arabayı almasaydım.', ["I wish I hadn't bought that car.", 'I wish I had not bought that car.', "If only I hadn't bought that car."], 'Geçmiş pişmanlık: wish + hadn\'t + V3.'),
 ('Keşke burada olsaydın.', ['I wish you were here.', 'I wish you were here with me.'], 'Şimdi için: wish + were.'),
 ('Keşke gürültü yapmayı bıraksan.', ['I wish you would stop making noise.', "I wish you'd stop making so much noise."], 'Yakınma: wish + would + V1.'),
 ('Keşke çocukken piyano öğrenseydim.', ['I wish I had learned the piano when I was a child.', "I wish I'd learnt to play the piano as a child."], 'Geçmiş için: wish + had + V3.'),
 ('Keşke yüzme bilsem.', ['I wish I could swim.', 'I wish I knew how to swim.'], 'Yetenek için: wish + could + V1.'),
])

# -------------------------------------------------------------- modals
topic('deduction', 'modals', 'B1', 'Olasılık ve tahmin: may / might / must / can\'t', 'Possibility and Deduction', '''
**Olasılık ve çıkarım bildiren kipler:**
- **may / might / could + V1:** belki, olabilir (emin değilim). It might rain later.
- **must + V1:** kesin gibi görünen olumlu çıkarım (-meli, -dır). You must be tired after the trip.
- **can't + V1:** imkânsız olduğuna dair çıkarım (olamaz). That can't be true.
- Şu anda süren bir şey için **must/might + be + V-ing:** He must be sleeping.
- **Dikkat:** Olumsuz çıkarımda "mustn't" değil **can't** kullanılır.
''', ['Özne + may / might / could + V1', 'Özne + must + V1 (eminim)', "Özne + can't + V1 (imkânsız)"],
[["She isn't answering. She might be busy.", 'Telefonu açmıyor. Meşgul olabilir.'], ["You've worked all day. You must be exhausted.", 'Bütün gün çalıştın. Çok yorgun olmalısın.']],
[
 ('Yarın yağmur yağabilir.', ['It might rain tomorrow.', 'It may rain tomorrow.', 'It could rain tomorrow.'], 'Olasılık: might / may + V1.'),
 ('Bütün gün yürüdün, aç olmalısın.', ["You've walked all day, so you must be hungry.", 'You walked all day; you must be hungry.'], 'Olumlu çıkarım: must + be.'),
 ('Bu doğru olamaz.', ["That can't be true.", "This can't be true.", 'That cannot be true.'], 'İmkânsız: can\'t + V1 (mustn\'t değil).'),
 ('Işıklar kapalı, evde olmayabilirler.', ["The lights are off. They might not be at home.", "The lights are off, so they may not be home."], 'Olumsuz olasılık: might not / may not.'),
 ('Telefonu açmıyor, uyuyor olmalı.', ["He isn't answering the phone; he must be sleeping.", "She's not answering her phone. She must be asleep."], 'Şu an süren eylem: must be + V-ing.'),
 ('O adam senin kardeşin olamaz, çok yaşlı.', ["That man can't be your brother; he's too old.", "That man can't be your brother. He's very old."], 'can\'t be: olamaz.'),
])

topic('past_modals', 'modals', 'B2', 'Geçmişe yönelik kipler (should have, must have…)', 'Past Modals', '''
**Modal + have + V3:** geçmişle ilgili pişmanlık, eleştiri ve tahmin.
- **should have + V3:** yapmalıydın (ama yapmadın). You should have told me.
- **shouldn't have + V3:** yapmamalıydın (ama yaptın).
- **must have + V3:** kesin öyle olmuş olmalı. She must have forgotten.
- **might / may / could have + V3:** olmuş olabilir. They might have missed the bus.
- **can't / couldn't have + V3:** olmuş olamaz. He can't have seen us.
- **could have + V3:** yapabilirdin ama yapmadın. You could have died!
''', ['Özne + should / shouldn\'t have + V3', 'Özne + must / might / can\'t have + V3', 'Özne + could have + V3'],
[['You should have called me.', 'Beni aramalıydın.'], ['She must have left already.', 'Çoktan çıkmış olmalı.']],
[
 ('Daha erken çıkmalıydık.', ['We should have left earlier.', 'We should have left sooner.'], 'Pişmanlık: should have + V3.'),
 ('O kadar çok yememeliydim.', ["I shouldn't have eaten so much.", 'I should not have eaten that much.'], 'Yapılmaması gereken: shouldn\'t have + V3.'),
 ('Anahtarlarını evde unutmuş olmalı.', ['He must have left his keys at home.', 'She must have forgotten her keys at home.'], 'Geçmişe yönelik kesin tahmin: must have + V3.'),
 ('Otobüsü kaçırmış olabilirler.', ['They might have missed the bus.', 'They may have missed the bus.', 'They could have missed the bus.'], 'Olasılık: might / may have + V3.'),
 ('Bizi görmüş olamaz, çok uzaktaydık.', ["He can't have seen us; we were too far away.", "She couldn't have seen us. We were very far away."], 'İmkânsız: can\'t have + V3.'),
 ('Bana söyleyebilirdin!', ['You could have told me!'], 'Yapılabilirdi ama yapılmadı: could have + V3.'),
])

topic('requests_permission', 'modals', 'A2', 'Rica ve izin: Could you / May I / Would you mind', 'Requests and Permission', '''
**Kibar rica ve izin kalıpları:**
- **Can / Could you + V1?** bir şey rica etmek. Could you help me? (could daha kibar)
- **Can / Could / May I + V1?** izin istemek. May I come in? (may en resmîsi)
- **Would you mind + V-ing?** … eder misiniz? Would you mind closing the door? Cevap "No, not at all" = hayır, sorun değil (yani yaparım).
- **Do you mind if I + V1?** … sakıncası var mı? Do you mind if I sit here?
- **Would you like…?** teklif: Would you like some tea?
''', ['Could you + V1?', 'Can / May I + V1?', 'Would you mind + V-ing?', 'Do you mind if I + V1?'],
[['Could you speak more slowly, please?', 'Daha yavaş konuşabilir misiniz, lütfen?'], ['Would you mind waiting a moment?', 'Bir dakika beklemenizin sakıncası var mı?']],
[
 ('Bana tuzu uzatabilir misin?', ['Could you pass me the salt?', 'Can you pass me the salt, please?', 'Could you pass the salt, please?'], 'Rica: Could / Can you + V1?'),
 ('İçeri girebilir miyim?', ['May I come in?', 'Can I come in?', 'Could I come in?'], 'İzin: May / Can I + V1?'),
 ('Pencereyi kapatır mısınız?', ['Would you mind closing the window?', 'Could you close the window, please?'], 'Would you mind + V-ing (closing).'),
 ('Buraya oturmamın sakıncası var mı?', ['Do you mind if I sit here?', 'Would you mind if I sat here?'], 'Do you mind if I + V1?'),
 ('Biraz çay ister misiniz?', ['Would you like some tea?', 'Would you like a cup of tea?'], 'Teklif: Would you like…?'),
 ('Telefonunuzu kullanabilir miyim, lütfen?', ['Could I use your phone, please?', 'May I use your phone, please?', 'Can I use your phone, please?'], 'İzin: Could / May I…?'),
])

# ---------------------------------------------------------------- nouns
topic('articles', 'nouns', 'A2', 'Artikeller: a / an / the', 'Articles: a / an / the', '''
**Türkçede artikel yoktur, İngilizcede tekil sayılabilen isim yalnız kullanılmaz.**
- **a / an:** ilk kez söz edilen, herhangi bir tekil sayılabilen isim (bir). a book, an apple. Sesli harf **sesiyle** başlayan kelimeden önce **an**: an hour, an umbrella; ama a university.
- **the:** iki tarafın da bildiği, daha önce söz edilen ya da tek olan şey. The sun, the book I bought.
- Meslekler: She is **a** doctor (a olmadan söylenmez).
- **Artikel yok:** genel anlamda çoğul ve sayılamayan isimler (I like cats. Water is important.), öğünler, diller, çoğu ülke ve şehir adı.
- the ile kullanılanlar: the USA, the UK, nehirler, denizler, çalgılar (play the piano).
''', ['a + ünsüz sesle başlayan tekil isim', 'an + ünlü sesle başlayan tekil isim', 'the + bilinen / tek olan isim', '(artikel yok) + genel çoğul / sayılamayan isim'],
[['I saw a dog. The dog was very big.', 'Bir köpek gördüm. Köpek çok büyüktü.'], ['My sister is an engineer.', 'Kız kardeşim mühendis.']],
[
 ('Babam öğretmen.', ['My father is a teacher.', 'My dad is a teacher.'], 'Meslekte a gerekir: a teacher.'),
 ('Bir saat bekledim.', ['I waited for an hour.', 'I waited an hour.'], 'h okunmuyor, ünlü sesle başlar: an hour.'),
 ('Kediyi severim ama köpeklerden korkarım.', ["I like cats, but I'm afraid of dogs.", 'I love cats but I am scared of dogs.'], 'Genel anlamda çoğul isim artikelsiz: cats, dogs.'),
 ('Dün bir film izledim. Film çok sıkıcıydı.', ['I watched a film yesterday. The film was very boring.', 'Yesterday I watched a movie. The movie was really boring.'], 'İlk kez: a film; ikinci kez: the film.'),
 ('Güneş doğudan doğar.', ['The sun rises in the east.'], 'Tek olan şeyler: the sun, the east.'),
 ('Kardeşim gitar çalıyor.', ['My brother plays the guitar.', 'My sister plays the guitar.', 'My brother is playing the guitar.'], 'Çalgılar the ile: play the guitar.'),
])

topic('countable_uncountable', 'nouns', 'A2', 'Sayılabilen ve sayılamayan isimler', 'Countable and Uncountable Nouns', '''
**Sayılabilen isimler** tekil ve çoğul olur: a chair, two chairs. **Sayılamayan isimler** çoğul yapılmaz ve a/an almaz: water, money, information, advice, furniture, bread, news.
- Türkçede sayılabilen ama İngilizcede sayılamayan sık hatalar: **advice** (tavsiye), **information** (bilgi), **news** (haber), **furniture** (mobilya), **homework**, **luggage**.
- Sayılamayanı saymak için ölçü kullanılır: a piece of advice, a glass of water, a loaf of bread, a bottle of milk.
- **How many** + çoğul sayılabilen, **how much** + sayılamayan.
- Sayılamayan isim tekil fiil alır: The news **is** good.
''', ['a / an / one / two + sayılabilen isim', 'some / much / a piece of + sayılamayan isim', 'How many + çoğul isim? / How much + sayılamayan isim?'],
[['Can you give me some advice?', 'Bana biraz tavsiye verebilir misin?'], ['How many eggs do we need?', 'Kaç yumurtaya ihtiyacımız var?']],
[
 ('Sana bir tavsiye vereyim.', ['Let me give you a piece of advice.', 'Let me give you some advice.'], 'advice sayılamaz: a piece of advice (an advice değil).'),
 ('Bu konuda çok fazla bilgi yok.', ["There isn't much information about this.", 'There is not much information on this subject.'], 'information sayılamaz: much information (informations değil).'),
 ('Ne kadar şeker istersin?', ['How much sugar do you want?', 'How much sugar would you like?'], 'Sayılamayan: how much.'),
 ('Sınıfta kaç öğrenci var?', ['How many students are there in the class?', 'How many students are in the class?'], 'Sayılabilen: how many + çoğul.'),
 ('Haberler çok iyi.', ['The news is very good.', 'The news is really good.'], 'news tekil fiil alır: is.'),
 ('İki şişe su aldım.', ['I bought two bottles of water.', 'I got two bottles of water.'], 'Sayılamayanı saymak: two bottles of water.'),
])

topic('quantifiers', 'nouns', 'A2', 'Miktar belirleyiciler: some / any / much / many / a few / a little', 'Quantifiers', '''
**Ne kadar? Kaç tane?**
- **some:** olumlu cümlede ve teklif/ricada (biraz, birkaç). I have some friends. Would you like some coffee?
- **any:** olumsuz ve soruda. I don't have any money. Do you have any questions?
- **many:** sayılabilen çoğul (çok), **much:** sayılamayan (çok); çoğunlukla olumsuz ve soruda. **a lot of / lots of:** ikisiyle de, olumlu cümlede doğal.
- **a few** (sayılabilen) / **a little** (sayılamayan): biraz, birkaç (olumlu anlam). **few / little:** çok az, neredeyse hiç (olumsuz anlam).
- **no / none:** hiç. There is no milk. None of them came.
''', ['some + isim (olumlu)', 'any + isim (olumsuz / soru)', 'many + çoğul / much + sayılamayan', 'a few + çoğul / a little + sayılamayan'],
[['There are a few apples in the fridge.', 'Buzdolabında birkaç elma var.'], ["I don't have much time today.", 'Bugün pek zamanım yok.']],
[
 ('Buzdolabında hiç süt yok.', ["There isn't any milk in the fridge.", 'There is no milk in the fridge.'], 'Olumsuz: not any / no.'),
 ('Birkaç arkadaşımı davet ettim.', ['I invited a few friends.', 'I invited a few of my friends.', "I've invited a few friends."], 'Sayılabilen, olumlu: a few.'),
 ('Biraz süt ister misin?', ['Would you like some milk?', 'Do you want some milk?'], 'Teklifte some kullanılır.'),
 ('Bu yıl çok kitap okumadım.', ["I haven't read many books this year.", "I didn't read many books this year."], 'Sayılabilen, olumsuz: many.'),
 ('Çorbaya biraz tuz ekle.', ['Add a little salt to the soup.', 'Put some salt in the soup.'], 'Sayılamayan: a little salt.'),
 ('Toplantıya çok az kişi geldi.', ['Very few people came to the meeting.', 'Few people came to the meeting.'], 'Neredeyse hiç: few (a few değil).'),
])

topic('demonstratives', 'nouns', 'A1', 'İşaret sözcükleri: this / that / these / those', 'Demonstratives', '''
**Yakın – uzak, tekil – çoğul:**
- **this** (bu, yakın, tekil), **these** (bunlar, yakın, çoğul).
- **that** (şu/o, uzak, tekil), **those** (şunlar/onlar, uzak, çoğul).
- İsimden önce sıfat gibi (this book) ya da tek başına zamir gibi (This is my book) kullanılır.
- İsim çoğulsa işaret sözcüğü de çoğul olmalı: these shoes (this shoes değil).
- Telefonda kendini tanıtırken: This is Ali. Geçmişteki bir dönemden söz ederken that: in those days.
''', ['this / that + tekil isim', 'these / those + çoğul isim', 'This is … / These are …'],
[['This bag is mine, and that one is yours.', 'Bu çanta benim, şu da senin.'], ['Those people over there are my neighbours.', 'Şuradaki insanlar komşularım.']],
[
 ('Bu ayakkabılar çok rahat.', ['These shoes are very comfortable.', 'These shoes are really comfortable.'], 'Çoğul ve yakın: these shoes.'),
 ('Şu ev kimin?', ['Whose house is that?', 'Whose is that house?'], 'Uzak, tekil: that.'),
 ('Bu benim kardeşim, Ayşe.', ['This is my sister, Ayşe.', 'This is my sister Ayse.'], 'Tanıştırırken: This is…'),
 ('Şu ağaçlar çok yaşlı.', ['Those trees are very old.'], 'Uzak, çoğul: those.'),
 ('O günlerde çok mutluyduk.', ['We were very happy in those days.', 'In those days we were very happy.'], 'Geçmiş dönem: in those days.'),
 ('Bunu sevdim ama şunu sevmedim.', ["I liked this one, but I didn't like that one.", "I like this one but I don't like that one."], 'Tekrarı önlemek için: this one / that one.'),
])

topic('possessives', 'nouns', 'A1', 'İyelik sıfatları ve zamirleri: my / mine', 'Possessive Adjectives and Pronouns', '''
**İyelik sıfatları** isimden önce gelir: **my, your, his, her, its, our, their** + isim (my car).
**İyelik zamirleri** tek başına kullanılır, isim almaz: **mine, yours, his, hers, ours, theirs** (The car is mine).
- **his** hem sıfat hem zamir; **its** (onun, cansız/hayvan) ile **it's** (it is) karışmamalı.
- İsimlerde 's: Ali's phone, my parents' house (çoğulda kesme sonda).
- "Benim bir arkadaşım" = a friend of mine.
- **Dikkat:** Türkçedeki gibi "the my book" denmez; artikel ile iyelik birlikte kullanılmaz.
''', ['my / your / his / her / its / our / their + isim', 'mine / yours / his / hers / ours / theirs (isimsiz)', "isim + 's (Ali's car)"],
[["That isn't my umbrella. Mine is black.", 'O benim şemsiyem değil. Benimki siyah.'], ["Is this your book or hers?", 'Bu senin kitabın mı yoksa onunki mi?']],
[
 ('Bu çanta benim değil, onunki.', ["This bag isn't mine; it's hers.", "This bag isn't mine, it's his.", 'This bag is not mine. It is hers.'], 'İsimsiz kullanım: mine, hers.'),
 ('Onların evi bizimkinden büyük.', ['Their house is bigger than ours.'], 'Sıfat: their house; zamir: ours.'),
 ('Ali\'nin telefonu masada.', ["Ali's phone is on the table."], "İsimlerde iyelik: Ali's."),
 ('Köpek kuyruğunu sallıyor.', ['The dog is wagging its tail.'], "its (onun) ile it's (it is) farklıdır."),
 ('O benim eski bir arkadaşım.', ['He is an old friend of mine.', "She's an old friend of mine."], 'a friend of mine.'),
 ('Bu ceket senin mi?', ['Is this jacket yours?', 'Is this your jacket?'], 'yours (zamir) ya da your jacket (sıfat).'),
])

# --------------------------------------------------------- prepositions
topic('prepositions_time', 'prepositions', 'A2', 'Zaman edatları: in / on / at', 'Prepositions of Time', '''
**Türkçede tek bir "-de" eki, İngilizcede üç edat:**
- **at:** saatler ve kısa anlar: at 7 o'clock, at noon, at night, at the weekend (İngiliz İngilizcesi).
- **on:** günler ve tarihler: on Monday, on 5 May, on my birthday, on the weekend (Amerikan).
- **in:** aylar, yıllar, mevsimler, yüzyıllar ve günün bölümleri: in June, in 2020, in summer, in the morning.
- **Edat yok:** this, next, last, every, tomorrow, yesterday önünde: next week, last year (in next week değil).
- **for** + süre (for two hours), **since** + başlangıç (since Monday), **during** + olay (during the film), **by** + son tarih (by Friday), **until** + bitiş (until 6).
''', ['at + saat / kısa an', 'on + gün / tarih', 'in + ay / yıl / mevsim / günün bölümü', 'next / last / every + zaman (edatsız)'],
[['The meeting is on Monday at ten.', 'Toplantı pazartesi saat onda.'], ['I was born in 1998.', '1998\'de doğdum.']],
[
 ('Film saat dokuzda başlıyor.', ['The film starts at nine.', "The movie starts at nine o'clock."], 'Saat: at.'),
 ('Doğum günüm mayısta.', ['My birthday is in May.'], 'Ay: in.'),
 ('Cumartesi sabahı buluşalım.', ["Let's meet on Saturday morning."], 'Belli bir günün sabahı: on Saturday morning.'),
 ('Gelecek hafta İzmir\'e gidiyorum.', ["I'm going to Izmir next week.", 'I am going to İzmir next week.'], 'next week önünde edat yok.'),
 ('Film sırasında telefonum çaldı.', ['My phone rang during the film.', 'My phone rang during the movie.'], 'Olay boyunca: during.'),
 ('Raporu cumaya kadar bitirmeliyim.', ['I have to finish the report by Friday.', 'I must finish the report by Friday.'], 'Son tarih: by (until değil).'),
])

topic('prepositions_place', 'prepositions', 'A2', 'Yer ve yön edatları', 'Prepositions of Place and Movement', '''
**Yer bildiren edatlar:**
- **in:** içinde (in the box, in Istanbul, in the kitchen). **on:** üzerinde, yüzeyinde (on the table, on the wall, on the bus). **at:** belli bir nokta, adres ya da etkinlik (at the door, at school, at a party).
- **under** (altında), **next to / beside** (yanında), **between** (ikisinin arasında), **behind** (arkasında), **in front of** (önünde), **opposite** (karşısında), **above / over** (yukarısında).
**Yön bildiren edatlar:** **to** (-e doğru: go to school), **into** (içine), **out of** (dışarı), **from** (-den), **through** (içinden geçerek), **across** (karşıya), **along** (boyunca).
- **Dikkat:** go home, come home (to almaz); arrive **in** a city, arrive **at** a place.
''', ['in / on / at + yer', 'next to / between / behind / in front of + yer', 'go to / into / out of / across + yer'],
[['The keys are on the table, next to the lamp.', 'Anahtarlar masada, lambanın yanında.'], ['She walked into the room.', 'Odaya girdi.']],
[
 ('Kitap masanın üstünde.', ['The book is on the table.'], 'Yüzey: on.'),
 ('Okul, eczane ile banka arasında.', ['The school is between the pharmacy and the bank.'], 'İkisinin arası: between.'),
 ('Arabayı evin önüne park ettim.', ['I parked the car in front of the house.'], 'Önünde: in front of.'),
 ('Sınavdan sonra eve gittim.', ['I went home after the exam.'], 'go home (to home değil).'),
 ('Karşıdan karşıya dikkatlice geç.', ['Cross the road carefully.', 'Go across the street carefully.'], 'Karşıya geçmek: cross / go across.'),
 ('Saat altıda havaalanına vardık.', ['We arrived at the airport at six.', "We got to the airport at six o'clock."], 'Belli bir yer: arrive at.'),
])

# ------------------------------------------------------------- sentence
topic('there_is', 'sentence', 'A1', 'There is / There are (var / yok)', 'There is / There are', '''
**Türkçedeki "var / yok" yapısı.**
- **There is** + tekil ya da sayılamayan isim: There is a cat in the garden. There is some milk.
- **There are** + çoğul isim: There are three books on the desk.
- Olumsuz: there isn't / there aren't (any). Soru: Is there…? Are there…?
- Geçmiş: there was / there were. Gelecek: there will be. Yakın geçmiş: there has been.
- **Dikkat:** "Bahçede bir ağaç var" = There is a tree in the garden (The garden has a tree da olur ama "In the garden is a tree" denmez). "have" ile karıştırmayın: I have a car (bende araba var).
''', ['There is + tekil / sayılamayan isim', 'There are + çoğul isim', 'Is there / Are there + isim?', 'There was / There were + isim'],
[['There are two banks on this street.', 'Bu sokakta iki banka var.'], ['Is there a pharmacy near here?', 'Buralarda bir eczane var mı?']],
[
 ('Odada üç sandalye var.', ['There are three chairs in the room.'], 'Çoğul: there are.'),
 ('Yakınlarda bir market var mı?', ['Is there a supermarket near here?', 'Is there a market nearby?', 'Is there a grocery store nearby?'], 'Soru: Is there…?'),
 ('Buzdolabında hiç yumurta yok.', ["There aren't any eggs in the fridge.", 'There are no eggs in the fridge.'], 'Olumsuz çoğul: there aren\'t any.'),
 ('Dün gece bir kaza oldu.', ['There was an accident last night.'], 'Geçmiş: there was.'),
 ('Partide çok insan vardı.', ['There were a lot of people at the party.', 'There were many people at the party.'], 'Geçmiş, çoğul: there were.'),
 ('Yarın toplantı olacak mı?', ['Will there be a meeting tomorrow?', 'Is there going to be a meeting tomorrow?'], 'Gelecek soru: Will there be…?'),
])

topic('question_tags', 'sentence', 'B1', 'Onay soruları (question tags)', 'Question Tags', '''
**Türkçedeki "… değil mi?"** İngilizcede cümlenin yardımcı fiiliyle kurulur.
- **Olumlu cümle → olumsuz etiket:** You are tired, **aren't you?**
- **Olumsuz cümle → olumlu etiket:** She doesn't eat meat, **does she?**
- Yardımcı fiil yoksa do / does / did kullanılır: You live here, don't you? He called you, didn't he?
- Etiketteki özne zamirdir: Ali is here, isn't **he**?
- Özel durumlar: I am → **aren't I?** / Let's → **shall we?** / Emir → **will you?** / There is → **isn't there?**
''', ['Olumlu cümle, yardımcı fiil + not + zamir?', 'Olumsuz cümle, yardımcı fiil + zamir?'],
[["It's a beautiful day, isn't it?", 'Güzel bir gün, değil mi?'], ["You haven't seen my keys, have you?", 'Anahtarlarımı görmedin, değil mi?']],
[
 ('Hava çok soğuk, değil mi?', ["It's very cold, isn't it?", 'It is really cold, isn\'t it?', "The weather is very cold, isn't it?"], 'is → isn\'t it?'),
 ('İngilizce konuşuyorsun, değil mi?', ["You speak English, don't you?"], 'Yardımcı fiil yoksa: don\'t you?'),
 ('Dün onu aramadın, değil mi?', ["You didn't call him yesterday, did you?", "You didn't call her yesterday, did you?"], 'Olumsuz → olumlu etiket: did you?'),
 ('Ali gelecek, değil mi?', ["Ali will come, won't he?", "Ali is coming, isn't he?"], 'Etikette zamir: won\'t he?'),
 ('Hadi yürüyüşe çıkalım, olur mu?', ["Let's go for a walk, shall we?"], "Let's → shall we?"),
 ('Daha önce burada bulunmadın, değil mi?', ["You haven't been here before, have you?"], 'haven\'t → have you?'),
])

topic('so_neither', 'sentence', 'B1', 'So / Neither / Too / Either (ben de)', 'So / Neither / Too / Either', '''
**"Ben de" ve "Ben de … değil" demenin yolları:**
- **Olumlu cümleye katılmak:** **So + yardımcı fiil + özne** ya da **özne + yardımcı fiil + too.** "I like coffee." – "So do I." / "I do too." / "Me too."
- **Olumsuz cümleye katılmak:** **Neither / Nor + yardımcı fiil + özne** ya da **özne + yardımcı fiil + not + either.** "I can't swim." – "Neither can I." / "I can't either." / "Me neither."
- Yardımcı fiil cümledeki zamana uyar: I went → So did I. She has finished → So have I.
- **Dikkat:** Neither'dan sonra fiil olumlu kalır: Neither do I (Neither don't I değil).
- **either … or** (ya … ya da), **neither … nor** (ne … ne de): Neither Ali nor Ayşe came.
''', ['So + yardımcı fiil + özne (ben de)', 'Neither + yardımcı fiil + özne (ben de değil)', 'Özne + yardımcı fiil + too / not + either'],
[['"I am hungry." – "So am I."', '"Acıktım." – "Ben de."'], ['"I didn\'t like the film." – "Neither did I."', '"Filmi beğenmedim." – "Ben de beğenmedim."']],
[
 ('"Çay severim." "Ben de."', ['"I like tea." "So do I."', '"I like tea." "Me too."', '"I love tea." "So do I."'], 'Geniş zamanda: So do I.'),
 ('"Yüzemem." "Ben de yüzemem."', ['"I can\'t swim." "Neither can I."', '"I can\'t swim." "Me neither."', '"I can\'t swim." "I can\'t either."'], 'Olumsuza katılmak: Neither can I.'),
 ('"Dün çok yoruldum." "Ben de."', ['"I was very tired yesterday." "So was I."', '"I got really tired yesterday." "So did I."'], 'was → So was I; got → So did I.'),
 ('Ne Ali ne de Ayşe toplantıya geldi.', ['Neither Ali nor Ayşe came to the meeting.', 'Neither Ali nor Ayse came to the meeting.'], 'neither … nor + olumlu fiil.'),
 ('Ya çay ya da kahve içebilirsin.', ['You can drink either tea or coffee.', 'You can have either tea or coffee.'], 'either … or: ya … ya da.'),
 ('O filmi izlemedim, kardeşim de izlemedi.', ["I haven't seen that film, and neither has my brother.", "I didn't watch that movie, and my sister didn't either."], 'neither has / didn\'t either.'),
])

topic('too_enough', 'sentence', 'A2', 'Too / Enough (çok / yeterince)', 'Too / Enough', '''
**İkisi de bir ölçünün fazla ya da yeterli olduğunu söyler:**
- **too + sıfat/zarf:** gereğinden fazla, olumsuz sonuçlu. This coffee is too hot (to drink).
- **sıfat/zarf + enough:** yeterince (enough sıfattan **sonra** gelir). She is old enough to drive.
- **enough + isim:** yeterli miktarda (isimden **önce**). We don't have enough time.
- **too much / too many + isim:** gereğinden fazla. There are too many people here.
- Çoğu zaman **to + V1** ile devam eder: too tired to walk, rich enough to buy.
- **Dikkat:** "very" yalnızca dereceyi artırır, "too" sorun olduğunu anlatır: The bag is very heavy (ama taşıyabilirim) / too heavy (taşıyamıyorum).
''', ['too + sıfat + (to + V1)', 'sıfat + enough + (to + V1)', 'enough + isim', 'too much / too many + isim'],
[["I'm too tired to go out tonight.", 'Bu akşam dışarı çıkamayacak kadar yorgunum.'], ["He isn't tall enough to reach the shelf.", 'Rafa uzanacak kadar uzun değil.']],
[
 ('Bu çanta taşıyamayacağım kadar ağır.', ['This bag is too heavy for me to carry.', 'This bag is too heavy to carry.'], 'too + sıfat + to + V1.'),
 ('Araba kullanacak kadar büyük değilsin.', ["You aren't old enough to drive.", "You're not old enough to drive."], 'sıfat + enough (old enough).'),
 ('Yeterince paramız yok.', ["We don't have enough money.", "We haven't got enough money."], 'enough + isim.'),
 ('Burada çok fazla insan var.', ['There are too many people here.'], 'Çoğul isim: too many.'),
 ('Çay içilemeyecek kadar sıcak.', ['The tea is too hot to drink.'], 'too hot to drink.'),
 ('Yeterince hızlı koşmadı, o yüzden yarışı kaybetti.', ["He didn't run fast enough, so he lost the race.", "She didn't run fast enough, so she lost the race."], 'Zarf + enough: fast enough.'),
])

topic('adverbs_frequency', 'sentence', 'A1', 'Sıklık zarfları: always / usually / never', 'Adverbs of Frequency', '''
**Bir şeyi ne sıklıkla yaptığımızı söyler:** always (her zaman) > usually (genellikle) > often (sık sık) > sometimes (bazen) > rarely / seldom (nadiren) > never (asla).
- **Yeri:** ana fiilden **önce** (I often read), ama **be fiilinden sonra** (She is always late) ve yardımcı fiilden sonra (I have never been there).
- **sometimes** cümle başında da olabilir: Sometimes I walk to work.
- **never** zaten olumsuzdur, not ile kullanılmaz: I never eat meat (I don't never değil).
- Soru: How often do you…? Cevapta: once a week, twice a month, every day.
''', ['Özne + sıklık zarfı + ana fiil', 'Özne + am/is/are + sıklık zarfı', 'How often + do/does + özne + V1?'],
[['I usually get up at seven.', 'Genellikle yedide kalkarım.'], ["She's never late for work.", 'İşe asla geç kalmaz.']],
[
 ('Kahvaltıda genellikle çay içerim.', ['I usually drink tea at breakfast.', 'I usually have tea for breakfast.'], 'Zarf ana fiilden önce: usually drink.'),
 ('O her zaman çok kibar.', ['She is always very polite.', "He's always very kind."], 'be fiilinden sonra: is always.'),
 ('Asla et yemem.', ['I never eat meat.'], 'never + olumlu fiil.'),
 ('Ne sıklıkla spor yaparsın?', ['How often do you exercise?', 'How often do you do sport?', 'How often do you work out?'], 'How often…?'),
 ('Bazen işe yürüyerek giderim.', ['Sometimes I walk to work.', 'I sometimes walk to work.', 'I sometimes go to work on foot.'], 'sometimes başta ya da fiilden önce.'),
 ('Haftada iki kez yüzmeye gideriz.', ['We go swimming twice a week.'], 'Sıklık ifadesi sonda: twice a week.'),
])

# -------------------------------------------------------------- clauses
topic('noun_clauses', 'clauses', 'B2', 'İsim cümlecikleri (that / what / whether)', 'Noun Clauses', '''
**Bir cümlenin bütün olarak isim gibi kullanılması.** Türkçedeki "-dığını, -eceğini, -ip -mediğini" yapılarına karşılık gelir.
- **that** + cümle: düşünce, bilgi ve duygularda. I think (that) he is right. I'm sure that she will come. (that çoğu zaman düşer.)
- **what / where / why / how** + düz cümle: I know what you mean. What he said surprised me.
- **whether / if** + cümle: … olup olmadığını. I don't know whether he will come.
- Özne olarak: **What** you need is rest. **That** he lied is obvious (daha doğalı: It's obvious that he lied).
- **Dikkat:** İçteki cümle soru sırası almaz: I don't know where she lives (where does she live değil).
''', ['Özne + fiil + (that) + özne + fiil', 'Özne + fiil + what/where/why + özne + fiil', 'What + özne + fiil + is/was …', 'Özne + fiil + whether/if + özne + fiil'],
[["I don't think that he's coming.", 'Onun geleceğini sanmıyorum.'], ['What I need is a long holiday.', 'İhtiyacım olan şey uzun bir tatil.']],
[
 ('Haklı olduğunu düşünüyorum.', ["I think that you're right.", 'I think you are right.'], 'think + (that) + cümle.'),
 ('Ne dediğini duymadım.', ["I didn't hear what you said.", "I didn't hear what he said."], 'what + düz cümle.'),
 ('Gelip gelmeyeceğini bilmiyorum.', ["I don't know whether he will come.", "I don't know if she's coming.", "I don't know whether or not he'll come."], 'whether / if: olup olmadığı.'),
 ('Senin ihtiyacın olan şey iyi bir uyku.', ['What you need is a good sleep.', "What you need is a good night's sleep."], 'Özne olarak: What you need is…'),
 ('Onun yalan söylediği belli.', ["It's obvious that he lied.", 'It is clear that she lied.', "It's obvious that he's lying."], "It's obvious that + cümle."),
 ('Nerede yaşadığını hatırlamıyorum.', ["I don't remember where she lives.", "I can't remember where he lives."], 'Düz sıra: where she lives.'),
])

topic('time_clauses', 'clauses', 'B1', 'Zaman cümlecikleri (before / after / until / by the time)', 'Time Clauses', '''
**Zaman bildiren yan cümleler:** when (-dığında), before (-meden önce), after (-dikten sonra), until / till (-e kadar), as soon as (-er -mez), while (-ken), since (-den beri), by the time (-e kadar, -diğinde çoktan), once (-ince).
- **Altın kural:** gelecekten söz ederken zaman cümleciğinde **will kullanılmaz**, Simple Present kullanılır: I'll call you **when I arrive** (when I will arrive değil).
- Bitmiş olmayı vurgulamak için Present Perfect de olur: I'll leave after I have finished.
- Geçmişte: By the time we arrived, the film had started (Past Perfect).
- before / after + V-ing de kullanılır: Wash your hands before eating.
''', ['Ana cümle (will) + when / before / after / until / as soon as + Simple Present', 'By the time + özne + V2, özne + had + V3', 'before / after + V-ing'],
[["I'll text you as soon as I get home.", 'Eve varır varmaz sana mesaj atarım.'], ['By the time we got there, the shop had closed.', 'Oraya vardığımızda dükkân çoktan kapanmıştı.']],
[
 ('Eve gelince seni ararım.', ["I'll call you when I get home.", 'I will call you when I come home.', "When I get home, I'll call you."], 'when + Simple Present (will değil).'),
 ('Yatmadan önce dişlerini fırçala.', ['Brush your teeth before you go to bed.', 'Brush your teeth before going to bed.'], 'before + cümle ya da before + V-ing.'),
 ('Sen gelene kadar burada bekleyeceğim.', ["I'll wait here until you come.", 'I will wait here until you arrive.', "I'll wait here till you come."], 'until + Simple Present.'),
 ('Haberi duyar duymaz ona söyledim.', ['As soon as I heard the news, I told him.', 'I told her as soon as I heard the news.'], 'as soon as: -er -mez.'),
 ('İstasyona vardığımızda tren çoktan kalkmıştı.', ['By the time we got to the station, the train had already left.', 'When we arrived at the station, the train had already left.'], 'By the time + V2, had + V3.'),
 ('Üniversiteyi bitirdikten sonra yurt dışında çalışmak istiyorum.', ['After I finish university, I want to work abroad.', 'I want to work abroad after I graduate from university.', 'After finishing university, I want to work abroad.'], 'after + Simple Present (gelecek anlamında).'),
])

topic('adverb_clauses', 'clauses', 'B2', 'Zarf cümlecikleri: amaç, sonuç, karşıtlık', 'Adverb Clauses: Purpose, Result, Contrast', '''
**Ana cümleyi neden, amaç, sonuç ya da karşıtlık yönünden niteleyen yan cümleler.** (Zaman bildirenler için "Zaman cümlecikleri", koşul için "Koşul cümleleri" konusuna bak.)
- **Amaç (için, -sin diye):** **so that** + özne + can/could/will: I left early so that I could catch the bus. **(in order) to + V1:** I went out to buy bread.
- **Sonuç (o kadar … ki):** **so + sıfat/zarf + that:** It was so cold that we stayed in. **such + (a) + sıfat + isim + that:** It was such a nice day that we went out.
- **Neden:** because, since, as (-dığı için). Since it was late, we took a taxi.
- **Karşıtlık:** although / even though (-e rağmen), **whereas / while** (oysa, -ken diğeri): I like tea, whereas my wife prefers coffee.
- **Tarz:** as if / as though (-mış gibi): He talks as if he knew everything.
''', ['Ana cümle + so that + özne + can/could + V1', 'so + sıfat + that + cümle / such + (a) + sıfat + isim + that', 'Ana cümle + whereas / while + cümle', 'Ana cümle + as if + cümle'],
[["I'm saving money so that I can buy a car.", 'Araba alabilmek için para biriktiriyorum.'], ['The film was so boring that I fell asleep.', 'Film o kadar sıkıcıydı ki uyuyakaldım.']],
[
 ('Treni kaçırmamak için erken çıktım.', ['I left early so that I wouldn\'t miss the train.', 'I left early so as not to miss the train.', "I left early so I wouldn't miss the train."], 'Olumsuz amaç: so that … wouldn\'t / so as not to.'),
 ('Hava o kadar sıcaktı ki dışarı çıkamadık.', ["It was so hot that we couldn't go out.", "The weather was so hot that we couldn't go outside."], 'so + sıfat + that.'),
 ('O kadar güzel bir gündü ki pikniğe gittik.', ['It was such a lovely day that we went for a picnic.', 'It was such a beautiful day that we had a picnic.'], 'such + a + sıfat + isim + that.'),
 ('Ben sabahları çalışmayı severim, oysa kardeşim geceleri çalışır.', ['I like working in the mornings, whereas my brother works at night.', 'I like to work in the morning, while my sister works at night.'], 'Karşıtlık: whereas / while.'),
 ('Her şeyi biliyormuş gibi konuşuyor.', ['He talks as if he knew everything.', 'She speaks as if she knows everything.', 'He talks as though he knew everything.'], 'as if / as though: -mış gibi.'),
 ('Geç olduğu için taksiye bindik.', ['Since it was late, we took a taxi.', 'As it was late, we took a taxi.', 'We took a taxi because it was late.'], 'Neden: since / as / because.'),
])

# ---------------------------------------------------------- conjunctions
topic('transition_words', 'conjunctions', 'B2', 'Geçiş sözcükleri: however / therefore / moreover', 'Transition Words', '''
**İki cümleyi ya da paragrafı mantıklı biçimde bağlar.** Genellikle yeni cümlenin başında gelir ve ardından **virgül** konur.
- **Ekleme:** moreover, furthermore, in addition, also (ayrıca, üstelik).
- **Karşıtlık:** however (ancak), nevertheless (yine de), on the other hand (öte yandan), in contrast.
- **Sonuç:** therefore (bu nedenle), as a result, consequently, so.
- **Örnek verme:** for example, for instance, such as.
- **Sıralama ve özet:** first, then, finally, in conclusion, to sum up.
- **Dikkat:** however iki cümleyi virgülle bağlayamaz: "It was late, however we went" yanlıştır → It was late. However, we went. (ya da noktalı virgül: It was late; however, we went.)
''', ['Cümle. However, + cümle.', 'Cümle; therefore, + cümle.', 'Cümle. Moreover / In addition, + cümle.'],
[['The hotel was expensive. However, the service was excellent.', 'Otel pahalıydı. Ancak hizmet mükemmeldi.'], ['He missed the bus. As a result, he was late for work.', 'Otobüsü kaçırdı. Sonuç olarak işe geç kaldı.']],
[
 ('Hava kötüydü. Yine de yürüyüşe çıktık.', ['The weather was bad. However, we went for a walk.', 'The weather was bad. Nevertheless, we went for a walk.', 'The weather was terrible; however, we still went for a walk.'], 'Karşıtlık: However, / Nevertheless,'),
 ('Çok çalıştı. Bu nedenle sınavı geçti.', ['He worked very hard. Therefore, he passed the exam.', 'She studied a lot. As a result, she passed the exam.'], 'Sonuç: Therefore, / As a result,'),
 ('Bu ev çok büyük. Üstelik bahçesi de var.', ['This house is very big. Moreover, it has a garden.', 'This house is really big. In addition, it has a garden.', 'This house is very big. What is more, it has a garden.'], 'Ekleme: Moreover, / In addition,'),
 ('Birçok meyve severim, örneğin elma ve muz.', ['I like many fruits, for example apples and bananas.', 'I love lots of fruits, such as apples and bananas.', 'I like many fruits, for instance apples and bananas.'], 'Örnek: for example / such as.'),
 ('Şehirde yaşamak pahalı. Öte yandan çok fırsat var.', ['Living in the city is expensive. On the other hand, there are a lot of opportunities.', 'Living in a city is expensive. On the other hand, there are many opportunities.'], 'Karşılaştırma: On the other hand,'),
 ('Sonuç olarak, düzenli spor sağlık için çok önemlidir.', ['In conclusion, regular exercise is very important for health.', 'To sum up, regular exercise is very important for your health.'], 'Özet: In conclusion, / To sum up,'),
])

# ---------------------------------------------------------------- forms
topic('causative', 'forms', 'B2', 'Ettirgen yapı: have / get something done', 'Causative: have / get something done', '''
**Bir işi başkasına yaptırmak.** Türkçedeki "-tır, -dır" (yaptırdım, kestirdim) ekine karşılık gelir.
- **have + nesne + V3:** I had my hair cut. (Saçımı kestirdim.) We're having the house painted.
- **get + nesne + V3:** daha günlük: I need to get my car repaired.
- **have + kişi + V1:** birine bir şey yaptırmak: I had the mechanic check the brakes.
- **get + kişi + to + V1:** birini ikna edip yaptırmak: I got my brother to help me.
- **make + kişi + V1:** zorla yaptırmak: My boss made me work late. **let + kişi + V1:** izin vermek: My parents let me stay out late.
''', ['Özne + have/get + nesne + V3', 'Özne + have + kişi + V1', 'Özne + get + kişi + to + V1', 'Özne + make / let + kişi + V1'],
[['I had my car washed yesterday.', 'Dün arabamı yıkattım.'], ['She got her sister to drive her to the airport.', 'Kız kardeşine onu havaalanına bıraktırdı.']],
[
 ('Dün saçımı kestirdim.', ['I had my hair cut yesterday.', 'I got my hair cut yesterday.'], 'have/get + nesne + V3: had my hair cut.'),
 ('Arabamı tamir ettirmem lazım.', ['I need to have my car repaired.', 'I need to get my car fixed.', 'I have to get my car repaired.'], 'get/have + car + repaired.'),
 ('Evimizi boyatıyoruz.', ["We're having our house painted.", 'We are getting our house painted.'], 'Şimdiki zaman: are having + nesne + V3.'),
 ('Öğretmen bize kompozisyonu yeniden yazdırdı.', ['The teacher made us rewrite the essay.', 'The teacher had us rewrite the essay.'], 'make/have + kişi + V1.'),
 ('Annem gece geç saate kadar dışarıda kalmama izin vermez.', ["My mother doesn't let me stay out late at night.", "My mum won't let me stay out late."], 'let + kişi + V1.'),
 ('Kardeşimi bana yardım etmeye ikna ettim.', ['I got my brother to help me.', 'I persuaded my sister to help me.'], 'get + kişi + to + V1.'),
])

topic('irregular_verbs', 'forms', 'A2', 'Düzensiz fiiller (fiil listesi: V1 / V2 / V3)', 'Irregular Verbs (Verb List)', '''
**Fiillerin üç hâli:** V1 (yalın: go), V2 (geçmiş: went), V3 (geçmiş ortaç: gone).
- **Düzenli fiiller** V2 ve V3'te -ed alır: work – worked – worked.
- **Düzensiz fiiller** ezberlenir. En sık kullanılanlar: be – was/were – been, have – had – had, do – did – done, go – went – gone, see – saw – seen, take – took – taken, give – gave – given, eat – ate – eaten, write – wrote – written, buy – bought – bought, think – thought – thought, bring – brought – brought, teach – taught – taught, find – found – found, leave – left – left, make – made – made, know – knew – known, begin – began – begun, speak – spoke – spoken, break – broke – broken, forget – forgot – forgotten.
- **V2** Simple Past'te (I went), **V3** Present Perfect (I have gone), Past Perfect (had gone) ve edilgen yapıda (it was written) kullanılır.
- **Dikkat:** did / didn't'ten sonra V1 gelir: I didn't go (didn't went değil).
''', ['Simple Past: özne + V2', 'Perfect: have/has/had + V3', 'Edilgen: be + V3'],
[['I bought a new phone and I have already broken it!', 'Yeni bir telefon aldım ve çoktan kırdım bile!'], ['This book was written in 1950.', 'Bu kitap 1950\'de yazıldı.']],
[
 ('Dün çok güzel bir rüya gördüm.', ['I had a beautiful dream last night.', 'I had a very nice dream yesterday.'], 'have a dream → had (see değil).'),
 ('Ona bir hediye aldım.', ['I bought him a present.', 'I bought her a gift.', 'I bought a present for him.'], 'buy – bought – bought.'),
 ('Bu mektubu kim yazdı?', ['Who wrote this letter?'], 'write – wrote – written; özne sorusunda did kullanılmaz.'),
 ('Şifremi unuttum.', ["I've forgotten my password.", 'I forgot my password.'], 'forget – forgot – forgotten.'),
 ('Hiç bu kadar uzun bir köprü görmemiştim.', ["I had never seen such a long bridge.", "I'd never seen a bridge this long."], 'Past Perfect: had + seen (V3).'),
 ('Bardak yere düştü ve kırıldı.', ['The glass fell on the floor and broke.', 'The glass fell to the floor and broke.'], 'fall – fell – fallen, break – broke – broken.'),
])

# ---------------------------------------------------------------- mixed
topic('mixed_review', 'mixed', 'B1', 'Karışık tekrar', 'Mixed Review', '''
**Bu bölümde farklı konulardan cümleler karışık gelir.** Her cümlede önce hangi yapının gerektiğini düşün:
- Zaman ifadesine bak: yesterday → Simple Past, since/for → Present Perfect, şu an → Present Continuous.
- "-se, -seydi" → koşul cümlesi; "keşke" → wish; "-tır, -dır (yaptırmak)" → causative.
- "-ılır, -ıldı" → edilgen yapı; "değil mi?" → question tag; "var / yok" → there is / there are.
- Cevabın doğruysa kutlanırsın, yanlışsa hangi kuralın gerektiği açıklanır.
''', ['Zamanı belirle → yapıyı seç → cümleyi kur'],
[['If I had known, I would have come.', 'Bilseydim gelirdim.'], ['The museum was opened in 2010.', 'Müze 2010\'da açıldı.']],
[
 ('İki yıldır İngilizce öğreniyorum.', ["I've been learning English for two years.", 'I have been studying English for two years.'], 'Süregelen eylem + for: Present Perfect Continuous.'),
 ('Bu köprü geçen yıl yapıldı.', ['This bridge was built last year.'], 'Geçmiş edilgen: was built.'),
 ('Keşke daha çok kitap okusam.', ['I wish I read more books.', 'I wish I read more.'], 'Şimdi için keşke: wish + V2.'),
 ('Masada iki bardak var.', ['There are two glasses on the table.'], 'Çoğul: there are.'),
 ('Sen gelmeden önce yemeği bitirmiştik.', ['We had finished dinner before you came.', 'We had finished eating before you arrived.'], 'Geçmişte daha önce olan: had + V3.'),
 ('Gözlüğümü tamir ettirdim.', ['I had my glasses repaired.', 'I got my glasses fixed.'], 'Causative: had + nesne + V3.'),
 ('Hava güzel, değil mi?', ["The weather is nice, isn't it?", "It's a nice day, isn't it?"], 'Question tag: isn\'t it?'),
 ('Yarın yağmur yağarsa evde kalacağız.', ["If it rains tomorrow, we'll stay at home.", 'We will stay at home if it rains tomorrow.'], 'Birinci tip koşul: if + V1, will + V1.'),
 ('Bu, şimdiye kadar gördüğüm en güzel manzara.', ["This is the most beautiful view I've ever seen.", 'This is the most beautiful view I have ever seen.'], 'Üstünlük + ever + Present Perfect.'),
 ('Bana nerede oturduğunu söyler misin?', ['Can you tell me where you live?', 'Could you tell me where you live?'], 'Dolaylı soru: düz sıra.'),
])

# Display order inside each category (the app groups by category).
ORDER = [
    'simple_present', 'present_continuous', 'simple_past', 'past_continuous', 'present_perfect',
    'present_perfect_continuous', 'past_perfect', 'future', 'future_continuous_perfect',
    'articles', 'countable_uncountable', 'quantifiers', 'demonstratives', 'possessives',
    'prepositions_time', 'prepositions_place',
    'there_is', 'adverbs_frequency', 'too_enough', 'so_neither', 'question_tags',
    'because_so', 'although_despite', 'unless', 'while_when', 'transition_words',
    'zero_conditional', 'first_conditional', 'second_conditional', 'third_conditional', 'mixed_conditionals', 'wish',
    'ability', 'obligation', 'requests_permission', 'deduction', 'past_modals',
    'passive', 'reported_speech',
    'relative_clauses', 'noun_clauses', 'indirect_questions', 'time_clauses', 'adverb_clauses',
    'irregular_verbs', 'gerund_infinitive', 'used_to', 'causative',
    'comparison', 'mixed_review',
]

# Words a learner may use for a topic in the chat ("bugün modals çalışalım").
# Lower case; matched as whole words after Turkish suffixes are cut off.
ALIASES = {
    'simple_present': ['simple present', 'present simple', 'geniş zaman', 'genis zaman'],
    'present_continuous': ['present continuous', 'present progressive', 'şimdiki zaman', 'simdiki zaman'],
    'simple_past': ['simple past', 'past simple', 'past tense', 'geçmiş zaman', 'gecmis zaman', 'di\'li geçmiş'],
    'past_continuous': ['past continuous', 'past progressive', 'geçmişte süren', 'şimdiki zamanın hikayesi', 'şimdiki zamanın hikâyesi'],
    'present_perfect': ['present perfect', 'yakın geçmiş', 'yakin gecmis'],
    'present_perfect_continuous': ['present perfect continuous', 'present perfect progressive'],
    'past_perfect': ['past perfect', 'miş\'li geçmişin hikayesi', 'miş\'li geçmişin hikâyesi', 'had v3'],
    'future': ['future simple', 'future tense', 'be going to', 'gelecek zaman', 'will'],
    'future_continuous_perfect': ['future continuous', 'future perfect', 'future progressive'],
    'articles': ['article', 'articles', 'artikel', 'artikeller', 'a an the', 'a/an/the'],
    'countable_uncountable': ['countable', 'uncountable', 'countable uncountable', 'countable-uncountable', 'sayılabilen', 'sayılamayan', 'sayilabilen', 'sayilamayan'],
    'quantifiers': ['quantifier', 'quantifiers', 'some any', 'much many', 'a few', 'a little', 'miktar'],
    'demonstratives': ['demonstrative', 'demonstratives', 'this that', 'these those', 'işaret sıfatları', 'işaret zamirleri'],
    'possessives': ['possessive', 'possessives', 'possessive adjectives', 'possessive pronouns', 'possessive adjectives-pronouns', 'iyelik'],
    'prepositions_time': ['prepositions of time', 'time prepositions', 'in on at', 'zaman edatları'],
    'prepositions_place': ['prepositions of place', 'place prepositions', 'prepositions of movement', 'yer edatları', 'yön edatları'],
    'there_is': ['there is', 'there are', 'there is there are', 'there is-there are', 'var yok'],
    'adverbs_frequency': ['adverbs of frequency', 'adverb of frequency', 'frequency adverbs', 'sıklık zarfları', 'siklik zarflari'],
    'too_enough': ['too enough', 'too-enough', 'too', 'enough'],
    'so_neither': ['neither', 'either', 'so too', 'neither either', 'neither-either-so-too', 'so neither', 'me too', 'me neither'],
    'question_tags': ['question tag', 'question tags', 'tag question', 'tag questions', 'değil mi soruları', 'onay soruları'],
    'because_so': ['because', 'because of', 'neden sonuç'],
    'although_despite': ['although', 'despite', 'in spite of', 'even though', 'rağmen'],
    'unless': ['unless'],
    'while_when': ['when while', 'as soon as'],
    'transition_words': ['transition word', 'transition words', 'transitions', 'linking words', 'linkers', 'however', 'therefore', 'moreover', 'geçiş sözcükleri', 'geçiş kelimeleri', 'bağlayıcılar'],
    'zero_conditional': ['zero conditional', 'type 0', 'sıfırıncı tip'],
    'first_conditional': ['first conditional', 'type 1', 'birinci tip'],
    'second_conditional': ['second conditional', 'type 2', 'ikinci tip'],
    'third_conditional': ['third conditional', 'type 3', 'üçüncü tip'],
    'mixed_conditionals': ['mixed conditional', 'mixed conditionals', 'karışık koşul'],
    'wish': ['wish', 'if only', 'keşke', 'keske'],
    'ability': ['can could', 'be able to', 'ability', 'yetenek'],
    'obligation': ['must', 'have to', 'should', 'obligation', 'zorunluluk'],
    'requests_permission': ['requests', 'permission', 'would you mind', 'may i', 'rica', 'izin'],
    'deduction': ['deduction', 'possibility', 'may might', 'might', 'olasılık', 'tahmin'],
    'past_modals': ['past modals', 'perfect modals', 'should have', 'must have', 'could have', 'modal perfect'],
    'passive': ['passive', 'passive voice', 'edilgen', 'edilgen yapı'],
    'reported_speech': ['reported speech', 'indirect speech', 'dolaylı anlatım', 'dolayli anlatim'],
    'relative_clauses': ['relative clause', 'relative clauses', 'adjective clause', 'adjective clauses', 'relative (adjective) clause', 'sıfat cümleciği', 'sıfat cümlecikleri', 'who which that'],
    'noun_clauses': ['noun clause', 'noun clauses', 'isim cümleciği', 'isim cümlecikleri'],
    'indirect_questions': ['indirect question', 'indirect questions', 'embedded questions', 'dolaylı soru', 'dolaylı sorular'],
    'time_clauses': ['time clause', 'time clauses', 'zaman cümleciği', 'zaman cümlecikleri', 'by the time', 'until'],
    'adverb_clauses': ['adverb clause', 'adverb clauses', 'adverbial clause', 'adverbial clauses', 'zarf cümleciği', 'zarf cümlecikleri', 'so that', 'such that', 'as if'],
    'irregular_verbs': ['verb list', 'irregular verbs', 'irregular verb', 'düzensiz fiiller', 'fiil listesi', 'v1 v2 v3'],
    'gerund_infinitive': ['gerund', 'infinitive', 'gerunds', 'infinitives', 'gerund infinitive', 'gerund-infinitives', 'gerund-infinitive', 'ing mi to mu'],
    'used_to': ['used to', 'be used to', 'get used to'],
    'causative': ['causative', 'causatives', 'causative verbs', 'have something done', 'get something done', 'ettirgen'],
    'comparison': ['comparative', 'superlative', 'comparatives', 'superlatives', 'comparative-superlative', 'comparative superlative', 'karşılaştırma', 'üstünlük'],
    'mixed_review': ['mixed', 'mixed review', 'karışık', 'karisik', 'karışık tekrar', 'genel tekrar'],
}

rank = {k: i for i, k in enumerate(ORDER)}
assert set(rank) == {t['id'] for t in T}, set(rank) ^ {t['id'] for t in T}
assert set(ALIASES) == set(rank), set(ALIASES) ^ set(rank)
T.sort(key=lambda t: rank[t['id']])
for t in T:
    t['aliases'] = ALIASES[t['id']]

out = {'version': 2, 'topics': T}
here = os.path.dirname(os.path.abspath(__file__))
path = os.path.join(here, '..', '..', 'assets', 'grammar', 'lessons.json')
with open(path, 'w', encoding='utf-8') as f:
    json.dump(out, f, ensure_ascii=False, indent=1)
print('topics', len(T), 'exercises', sum(len(t['exercises']) for t in T))
