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

out = {'version': 1, 'topics': T}
here = os.path.dirname(os.path.abspath(__file__))
path = os.path.join(here, '..', '..', 'assets', 'grammar', 'lessons.json')
with open(path, 'w', encoding='utf-8') as f:
    json.dump(out, f, ensure_ascii=False, indent=1)
print('topics', len(T), 'exercises', sum(len(t['exercises']) for t in T))
