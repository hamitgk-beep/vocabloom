# -*- coding: utf-8 -*-
"""Hand-curated English expression lists with Turkish meanings.

Each line: phrase | Türkçe anlam | (optional) not
Pattern conventions used in phrases:
  sb / sth   -> any 1-3 words (somebody / something)
  one's      -> my, your, his, her, its, our, their, one's
  a / the    -> any determiner (a, an, the, my, his, this ...)
Written for this project; released with the app under CC BY-SA 4.0.
"""

CONJUNCTIONS = """
and | ve
but | ama, fakat
or | veya, ya da
so | bu yüzden, o yüzden
yet | yine de, ama
nor | ne de
because | çünkü
although | -e rağmen, -mesine rağmen
though | gerçi, -e rağmen
even though | -diği halde, -mesine rağmen
even if | -se bile
while | -iken; oysa
whereas | oysa, halbuki
unless | -medikçe, -mezse
until | -e kadar, -inceye dek
till | -e kadar
since | -den beri; -diği için
as | -dığı için; -iken; gibi
as long as | -dığı sürece
as soon as | -ir -mez
as if | sanki, -mış gibi
as though | sanki, -mış gibi
so that | -sin diye, -mesi için
in order that | -sin diye
provided that | şartıyla, -mek koşuluyla
providing that | şartıyla
in case | -e karşı, olur da diye
if | eğer, -se
whether | -ip -mediği
once | -ir -mez, bir kez -dikten sonra
before | -meden önce
after | -dikten sonra
when | -dığında
whenever | ne zaman -se
wherever | nerede -se
where | -dığı yerde
than | -den (daha)
both sb and | hem ... hem de
either sb or | ya ... ya da
neither sb nor | ne ... ne de
not only sb but also | sadece ... değil, aynı zamanda ...
whether sb or | ... olsun ya da olmasın
now that | madem ki, artık -diğine göre
so as to | -mek için
in order to | -mek için, -mek amacıyla
rather than | -mektense, yerine
whereby | ki bununla, -dığı (yolla)
lest | -mesin diye
except that | ancak, şu farkla ki
given that | -diği göz önüne alınırsa
supposing | farz edelim ki
"""

DISCOURSE_MARKERS = """
however | ancak, bununla birlikte
therefore | bu nedenle
moreover | üstelik, ayrıca
furthermore | dahası, bundan başka
nevertheless | yine de, buna rağmen
nonetheless | yine de
meanwhile | bu arada
otherwise | aksi takdirde
consequently | sonuç olarak
hence | bu yüzden, dolayısıyla
thus | böylece, bu yüzden
besides | ayrıca, üstelik
instead | bunun yerine
indeed | gerçekten de, hakikaten
actually | aslında
basically | temelde, kısacası
anyway | neyse, her neyse
anyhow | neyse
well | şey, peki, eh
you know | bilirsin, yani
I mean | yani, demek istediğim
kind of | biraz, bir nevi
sort of | bir bakıma, biraz
by the way | bu arada, aklıma gelmişken
in fact | aslında, gerçekte
as a matter of fact | aslına bakarsan
in other words | başka bir deyişle
that is to say | yani, başka bir deyişle
for example | örneğin
for instance | mesela, örneğin
in addition | buna ek olarak
on the other hand | öte yandan
on the contrary | aksine, tam tersine
in contrast | buna karşın
as a result | sonuç olarak
in conclusion | sonuç olarak, toparlarsak
to sum up | özetle
all in all | genel olarak, her şey hesaba katılınca
after all | ne de olsa; sonunda
above all | her şeyden önce
first of all | her şeyden önce, ilk olarak
to begin with | başlangıç olarak, bir kere
finally | son olarak, nihayet
lastly | son olarak
of course | elbette, tabii ki
obviously | açıkçası, belli ki
clearly | açıkça, belli ki
apparently | görünüşe göre
honestly | dürüst olmak gerekirse
frankly | açıkçası
to be honest | dürüst olmak gerekirse
in my opinion | bence, kanımca
as far as I know | bildiğim kadarıyla
at least | en azından
at any rate | her halükârda
in any case | her durumda
still | yine de, hâlâ
even so | öyle olsa bile
all the same | yine de
admittedly | kabul etmek gerekir ki
similarly | benzer şekilde
likewise | aynı şekilde
in the meantime | bu arada, o sırada
eventually | sonunda, eninde sonunda
right | peki, tamam
okay | tamam, peki
oh | ah, oh
um | ıı (duraksama)
uh | ıı (duraksama)
hmm | hımm
you see | anlarsın ya, bak şimdi
mind you | ama unutma ki
let me see | bir bakayım, dur bakalım
so to speak | tabiri caizse
more or less | aşağı yukarı, az çok
as I was saying | dediğim gibi
speaking of which | laf açılmışken
in short | kısacası
in brief | kısaca
namely | yani, şöyle ki
in particular | özellikle
especially | özellikle
"""

PREPOSITIONAL_PHRASES = """
at first | ilk başta
at last | sonunda, nihayet
at once | hemen, derhal
at all | hiç, hiç de
at times | zaman zaman
at the moment | şu anda
at the same time | aynı zamanda
at the end | sonunda
at the beginning | başta
at home | evde
at night | gece
at work | işte
at risk | risk altında
at ease | rahat, huzurlu
at hand | yakında, el altında
at heart | özünde
at random | rastgele
at a loss | şaşkın, ne yapacağını bilemeyen
at first sight | ilk görüşte
by chance | tesadüfen
by accident | kazara
by mistake | yanlışlıkla
by heart | ezbere
by far | açık ara, kat kat
by hand | elle
by no means | asla, hiçbir şekilde
by all means | elbette, tabii ki
by oneself | kendi başına
in time | zamanında, vaktinde
on time | tam vaktinde
in advance | önceden
in charge of | -den sorumlu
in danger | tehlikede
in general | genel olarak
in love | aşık
in public | herkesin önünde
in private | özel olarak, baş başa
in secret | gizlice
in trouble | başı dertte
in vain | boşuna
in a hurry | aceleyle
in the end | sonunda
in the long run | uzun vadede
in the dark | karanlıkta; habersiz
in person | bizzat, şahsen
in silence | sessizce
in spite of | -e rağmen
in front of | -in önünde
in terms of | açısından
in favour of | -den yana
in favor of | -den yana
in touch | iletişimde
in tears | gözyaşları içinde
in turn | sırayla; buna karşılık
in common | ortak
in detail | ayrıntılı olarak
on purpose | bilerek, kasten
on foot | yürüyerek
on fire | yanıyor, alevler içinde
on board | gemide, uçakta
on duty | görevde, nöbette
on holiday | tatilde
on the way | yolda
on behalf of | adına
on the whole | genel olarak
on and off | ara sıra
on edge | gergin
out of order | bozuk
out of date | modası geçmiş, güncel olmayan
out of breath | nefes nefese
out of sight | gözden uzak
out of control | kontrolden çıkmış
out of the question | söz konusu bile değil
under control | kontrol altında
under pressure | baskı altında
under the weather | keyifsiz, hasta
within reach | ulaşılabilir mesafede
without doubt | şüphesiz
beyond doubt | şüphe götürmez
for good | temelli, kalıcı olarak
for ever | sonsuza dek
for sure | kesinlikle
for a while | bir süre
for the time being | şimdilik
from time to time | zaman zaman
from now on | bundan sonra
up to date | güncel
with regard to | ile ilgili olarak
because of | yüzünden
due to | nedeniyle
instead of | yerine
according to | -e göre
apart from | -den başka, dışında
ahead of | -in önünde, -den önce
thanks to | sayesinde
as well as | yanı sıra, ve de
"""

PHRASAL_VERBS = """
give up | vazgeçmek, bırakmak
give in | boyun eğmek, pes etmek
give away | bedavaya vermek; ele vermek
give back | geri vermek
look after | bakmak, ilgilenmek
look for | aramak
look up | (sözlükte) bakmak; düzelmek
look forward to | dört gözle beklemek
look into | araştırmak, incelemek
look out | dikkat etmek
look down on | küçümsemek, tepeden bakmak
look up to | saygı duymak, örnek almak
put off | ertelemek; soğutmak
put on | giymek; (kilo) almak
put out | söndürmek
put up with | katlanmak, tahammül etmek
put away | kaldırmak, yerine koymak
put down | yere koymak; bastırmak; aşağılamak
take off | çıkarmak; (uçak) kalkmak
take on | üstlenmek; işe almak
take over | devralmak, kontrolü ele almak
take after | (birine) çekmek, benzemek
take up | (bir uğraşa) başlamak; yer kaplamak
take in | anlamak, kavramak; kandırmak
take back | geri almak
turn on | açmak (cihaz)
turn off | kapatmak (cihaz)
turn up | ortaya çıkmak; sesini açmak
turn down | reddetmek; sesini kısmak
turn into | -e dönüşmek
turn out | ortaya çıkmak, sonuçlanmak
turn around | dönmek, arkasını dönmek
get up | kalkmak (yataktan)
get on | binmek; geçinmek
get off | inmek
get over | atlatmak, üstesinden gelmek
get along | iyi geçinmek
get away | kaçmak, kurtulmak
get back | geri dönmek; geri almak
get by | idare etmek, geçinip gitmek
get rid of | -den kurtulmak
get out | dışarı çıkmak
get in | içeri girmek; binmek
get through | atlatmak; ulaşmak (telefonla)
come across | rastlamak, karşılaşmak
come back | geri gelmek
come up with | (fikir) bulmak, ortaya atmak
come up | gündeme gelmek; yaklaşmak
come along | eşlik etmek; ilerlemek
come in | içeri girmek
come out | çıkmak, ortaya çıkmak
come down | inmek; düşmek
come over | uğramak, gelmek
come on | hadi; başlamak
go on | devam etmek; olmak
go out | dışarı çıkmak; sönmek
go back | geri dönmek
go away | gitmek, uzaklaşmak
go off | patlamak; çalmak (alarm); bozulmak
go over | gözden geçirmek
go through | yaşamak, geçirmek (zor dönem); incelemek
go up | artmak; yükselmek
go down | azalmak; batmak
go ahead | devam etmek, buyur
break down | bozulmak; yıkılmak (duygusal)
break up | ayrılmak; dağılmak
break in | zorla girmek
break out | patlak vermek; kaçmak
bring up | yetiştirmek; (konu) açmak
bring about | neden olmak
bring back | geri getirmek; hatırlatmak
call off | iptal etmek
call back | geri aramak
call on | ziyaret etmek; çağrıda bulunmak
carry on | devam etmek
carry out | yerine getirmek, uygulamak
check in | giriş yapmak (otel, havalimanı)
check out | çıkış yapmak; incelemek
cheer up | neşelenmek, neşelendirmek
clean up | temizlemek, toparlamak
cut down | azaltmak; kesip devirmek
cut off | kesmek, bağlantısını koparmak
deal with | ilgilenmek, ele almak
end up | sonunda -e varmak, kendini ... bulmak
fall apart | dağılmak, parçalanmak
fall behind | geri kalmak
fall down | düşmek
fall out | kavga edip bozuşmak
figure out | anlamak, çözmek
fill in | doldurmak (form)
fill out | doldurmak (form)
find out | öğrenmek, keşfetmek
grow up | büyümek
hang on | beklemek; sıkı tutunmak
hang out | takılmak, vakit geçirmek
hang up | telefonu kapatmak
hold on | beklemek; dayanmak
hold back | geri tutmak, saklamak
keep on | devam etmek
keep up | ayak uydurmak, sürdürmek
keep up with | -e ayak uydurmak
keep away | uzak durmak
let down | hayal kırıklığına uğratmak
let in | içeri almak
log in | oturum açmak
make up | uydurmak; barışmak; makyaj yapmak
make out | seçebilmek, anlamak
make up for | telafi etmek
mix up | karıştırmak
move on | yoluna devam etmek
pass away | vefat etmek
pass out | bayılmak
pay back | geri ödemek; intikam almak
pick up | almak, kaldırmak; (birini) almak
point out | belirtmek, işaret etmek
pull over | kenara çekmek
run away | kaçmak
run into | rastlamak, çarpmak
run out of | -i tükenmek, bitmek
run over | ezmek (araçla)
set up | kurmak
set off | yola çıkmak; patlatmak
settle down | yerleşmek; sakinleşmek
show off | gösteriş yapmak
show up | gelmek, ortaya çıkmak
shut down | kapatmak
shut up | susmak
sit down | oturmak
stand up | ayağa kalkmak
stand for | -in kısaltması olmak; savunmak
stand out | göze çarpmak
stay up | geç saate kadar uyumamak
think over | iyice düşünmek
throw away | atmak, çöpe atmak
try on | denemek (giysi)
try out | denemek
wake up | uyanmak
warm up | ısınmak
wear out | yıpranmak; yorulmak
work out | spor yapmak; çözmek; yolunda gitmek
write down | not almak, yazmak
back up | desteklemek; yedeklemek
blow up | patlamak, havaya uçurmak
calm down | sakinleşmek
catch up | yetişmek, açığı kapatmak
count on | güvenmek
do without | -sız idare etmek
drop by | uğramak
drop out | (okulu) bırakmak
fit in | uyum sağlamak
get across | anlatmak, iletmek
hand in | teslim etmek
hand out | dağıtmak
hurry up | acele etmek
lie down | uzanmak
look around | etrafa bakmak
pick out | seçmek
put together | bir araya getirmek
rely on | güvenmek, bel bağlamak
sort out | halletmek, düzene koymak
speak up | yüksek sesle konuşmak; fikrini söylemek
take apart | sökmek, parçalara ayırmak
tell off | azarlamak
"""

COLLOCATIONS = """
make a decision | karar vermek
make a mistake | hata yapmak
make an effort | çaba göstermek
make money | para kazanmak
make progress | ilerleme kaydetmek
make sense | mantıklı olmak, anlam ifade etmek
make sure | emin olmak
make a difference | fark yaratmak
make friends | arkadaş edinmek
make a living | geçimini sağlamak
make noise | gürültü yapmak
make a phone call | telefon etmek
make an excuse | bahane uydurmak
make room | yer açmak
do homework | ödev yapmak
do business | iş yapmak
do one's best | elinden geleni yapmak
do the dishes | bulaşık yıkamak
do a favour | iyilik yapmak
do a favor | iyilik yapmak
do harm | zarar vermek
take a break | mola vermek
take a chance | şansını denemek
take a look | bir göz atmak
take a seat | oturmak, yer almak
take notes | not almak
take place | gerçekleşmek, yer almak
take care | dikkat etmek, kendine iyi bakmak
take a risk | risk almak
take advantage of | -den yararlanmak; istismar etmek
take part in | -e katılmak
take time | zaman almak
take a photo | fotoğraf çekmek
have a good time | iyi vakit geçirmek
have a look | bakmak
have breakfast | kahvaltı etmek
have a rest | dinlenmek
have fun | eğlenmek
have no idea | hiç bilmemek, hiçbir fikri olmamak
pay attention | dikkat etmek
pay a visit | ziyaret etmek
pay a compliment | iltifat etmek
catch a cold | soğuk algınlığına yakalanmak
catch fire | alev almak
catch sight of | -i gözüne kestirmek, görmek
keep a secret | sır saklamak
keep a promise | sözünü tutmak
keep calm | sakin kalmak
keep in touch | iletişimi sürdürmek
lose weight | kilo vermek
lose one's temper | öfkesine hakim olamamak
lose track of | -in izini kaybetmek
save time | zaman kazanmak
save money | para biriktirmek
waste time | zaman kaybetmek
spend time | zaman geçirmek
tell the truth | doğruyu söylemek
tell a lie | yalan söylemek
tell a story | hikâye anlatmak
break a promise | sözünü tutmamak
break the law | yasayı çiğnemek
break the news | haberi vermek
come to an end | sona ermek
come to a decision | karara varmak
come true | gerçekleşmek
fall asleep | uykuya dalmak
fall in love | aşık olmak
fall ill | hastalanmak
heavy rain | şiddetli yağmur
heavy traffic | yoğun trafik
strong coffee | sert kahve
strong wind | kuvvetli rüzgâr
deep sleep | derin uyku
deeply moved | derinden etkilenmiş
bitterly disappointed | büyük hayal kırıklığına uğramış
highly unlikely | pek olası değil
fully aware | tamamen farkında
utterly ridiculous | tamamen saçma
fast asleep | derin uykuda
wide awake | tamamen uyanık
a great deal | çok, büyük ölçüde
a matter of time | an meselesi
bear in mind | akılda tutmak
draw a conclusion | sonuç çıkarmak
draw attention | dikkat çekmek
give birth | doğum yapmak
give a speech | konuşma yapmak
raise a question | soru gündeme getirmek
reach an agreement | anlaşmaya varmak
run a business | iş yürütmek
run a risk | risk almak
set an example | örnek olmak
set a record | rekor kırmak
shed light on | -e ışık tutmak
take into account | hesaba katmak
"""

IDIOMS = """
break the ice | buzları eritmek
a piece of cake | çocuk oyuncağı, çok kolay
hit the nail on the head | tam üstüne basmak
let the cat out of the bag | ağzından kaçırmak
spill the beans | ağzındaki baklayı çıkarmak
under the weather | keyifsiz, hasta
once in a blue moon | kırk yılda bir
cost an arm and a leg | çok pahalıya mal olmak
kick the bucket | nalları dikmek, ölmek
pull one's leg | birine takılmak, işletmek
break a leg | bol şans (oyunculara)
bite the bullet | dişini sıkmak
call it a day | paydos etmek
cut corners | işi baştan savma yapmak
get out of hand | kontrolden çıkmak
hit the sack | yatmak, uyumak
hit the road | yola koyulmak
in hot water | başı belada
miss the boat | fırsatı kaçırmak
on the ball | uyanık, işini bilen
play it by ear | duruma göre davranmak
sit on the fence | tarafsız kalmak, kararsız kalmak
the last straw | bardağı taşıran son damla
through thick and thin | iyi günde kötü günde
when pigs fly | balık kavağa çıkınca
beat around the bush | lafı dolandırmak
burn the midnight oil | gece yarılarına kadar çalışmak
cry over spilt milk | olmuşa ağlamak
feel blue | hüzünlü hissetmek
get cold feet | son anda korkup vazgeçmek
give sb the cold shoulder | birine soğuk davranmak
go the extra mile | fazlasını yapmak, ekstra çaba göstermek
have a heart of gold | altın kalpli olmak
keep an eye on | göz kulak olmak
let sleeping dogs lie | uyuyan yılanın kuyruğuna basmamak
make ends meet | iki yakasını bir araya getirmek
on cloud nine | havalara uçmak, çok mutlu
once and for all | kesin olarak, ilk ve son kez
over the moon | çok mutlu, havalara uçan
see eye to eye | aynı fikirde olmak
speak of the devil | iti an çomağı hazırla
take it easy | sakin ol, kafana takma
the ball is in your court | top sende, karar senin
up in the air | belirsiz, askıda
blessing in disguise | hayırlı bir aksilik
by the skin of one's teeth | kıl payı
cut to the chase | sadede gelmek
face the music | sonuçlarına katlanmak
go back to the drawing board | baştan başlamak
hang in there | dayan, pes etme
it's not rocket science | o kadar da zor değil
jump on the bandwagon | rüzgâra kapılmak, modaya uymak
keep one's chin up | moralini yüksek tutmak
lose one's touch | eski hünerini kaybetmek
off the top of one's head | düşünmeden, hemencecik
on thin ice | tehlikeli durumda
out of the blue | birdenbire, durup dururken
pull oneself together | kendini toparlamak
rain cats and dogs | bardaktan boşanırcasına yağmak
ring a bell | tanıdık gelmek
see the light | gerçeği anlamak
steal the show | gösteriyi çalmak, ilgiyi üstüne çekmek
take sb for granted | birinin kıymetini bilmemek
the tip of the iceberg | buzdağının görünen kısmı
throw in the towel | pes etmek, havlu atmak
turn a blind eye | göz yummak
under one's nose | burnunun dibinde
a dime a dozen | sokakta bulunmuş, çok sıradan
add insult to injury | yaraya tuz biber ekmek
back to square one | başa dönmek
barking up the wrong tree | yanlış kapıyı çalmak
best of both worlds | iki dünyanın en iyisi
devil's advocate | şeytanın avukatı
get the ball rolling | işi başlatmak
in the same boat | aynı gemide, aynı durumda
keep one's fingers crossed | şans dilemek
lend a hand | yardım elini uzatmak
make a long story short | uzun lafın kısası
no pain no gain | emek olmadan yemek olmaz
on the same page | aynı fikirde, aynı anlayışta
out of one's mind | aklını kaçırmış
put all one's eggs in one basket | tüm umudunu tek şeye bağlamak
read between the lines | satır aralarını okumak
second nature | huy haline gelmiş
take the plunge | cesaret edip girişmek
the elephant in the room | herkesin bildiği ama konuşmadığı sorun
time flies | zaman su gibi akıp geçiyor
under the table | gizlice, el altından
wrap one's head around | kafasında oturtmak, anlamak
lose heart | cesaretini kaybetmek
by heart | ezbere
"""

PROVERBS = """
actions speak louder than words | icraat sözden daha etkilidir
all that glitters is not gold | her parlayan altın değildir
an apple a day keeps the doctor away | günde bir elma doktoru uzak tutar
better late than never | geç olsun da güç olmasın
birds of a feather flock together | benzer benzerini çeker
don't count your chickens before they hatch | dereyi görmeden paçaları sıvama
don't judge a book by its cover | kitabı kapağına göre yargılama
easy come easy go | haydan gelen huya gider
every cloud has a silver lining | her işte bir hayır vardır
honesty is the best policy | dürüstlük en iyi yoldur
if it ain't broke don't fix it | çalışan şeyi kurcalama
it takes two to tango | tek elden ses çıkmaz
knowledge is power | bilgi güçtür
laughter is the best medicine | gülmek en iyi ilaçtır
look before you leap | atlamadan önce iyice düşün
necessity is the mother of invention | ihtiyaç icadın anasıdır
no news is good news | haber yoksa iyi haberdir
practice makes perfect | işleye işleye demir ışıldar
rome wasn't built in a day | Roma bir günde kurulmadı, sabırlı ol
the early bird catches the worm | erken kalkan yol alır
there's no place like home | ev gibisi yoktur
time is money | vakit nakittir
two heads are better than one | akıl akıldan üstündür
when in rome do as the romans do | ne yerde ne yerde, onlardan ol
where there's a will there's a way | isteyen her şeyi başarır
you can't have your cake and eat it | hem dağdan hem bağdan olmaz
a friend in need is a friend indeed | dost kara günde belli olur
a picture is worth a thousand words | bir resim bin kelimeye bedeldir
absence makes the heart grow fonder | uzaklık sevgiyi artırır
beauty is in the eye of the beholder | güzellik bakanın gözündedir
blood is thicker than water | kan sudan koyudur
curiosity killed the cat | merak kediyi öldürür
don't put all your eggs in one basket | bütün yumurtaları aynı sepete koyma
great minds think alike | büyük beyinler aynı düşünür
haste makes waste | acele işe şeytan karışır
ignorance is bliss | cahillik mutluluktur
it's no use crying over spilt milk | olan oldu, ağlamanın faydası yok
let bygones be bygones | geçmişe mazi derler
money doesn't grow on trees | para ağaçta yetişmez
out of sight out of mind | gözden ırak olan gönülden de ırak olur
the pen is mightier than the sword | kalem kılıçtan keskindir
too many cooks spoil the broth | iki kaptan bir gemiyi batırır
you can't teach an old dog new tricks | yaşlı kurt yeni numara öğrenmez
strike while the iron is hot | demir tavında dövülür
still waters run deep | durgun suların derinliği fazladır
slow and steady wins the race | ağır ağır giden yol alır
the grass is always greener on the other side | komşunun tavuğu komşuya kaz görünür
there's no such thing as a free lunch | bedava peynir fare kapanında olur
what goes around comes around | ne ekersen onu biçersin
you reap what you sow | ne ekersen onu biçersin
first come first served | ilk gelen alır
fortune favours the bold | şans cesurdan yanadır
money talks | paranın sesi çıkar
seeing is believing | görmeden inanmam
"""

CHUNKS = """
as soon as possible | mümkün olan en kısa sürede
at the end of the day | günün sonunda, sonuçta
I don't think so | sanmıyorum
I'm afraid | korkarım ki, maalesef
I'd rather | tercih ederim, -sem daha iyi
it depends | duruma bağlı
it's up to you | sana kalmış
let me know | bana haber ver
long time no see | görüşmeyeli uzun zaman oldu
never mind | boş ver, önemli değil
no way | olamaz, asla
no wonder | şaşılacak bir şey yok
not at all | hiç de değil; rica ederim
nice to meet you | tanıştığımıza memnun oldum
how about | ... ne dersin
what about | ... ne olacak, ya ...
what's the matter | ne oldu, sorun ne
what's going on | neler oluyor
how come | nasıl oluyor da
by the time | -diği zamana kadar
sooner or later | er ya da geç
once upon a time | bir zamanlar
the thing is | mesele şu ki
it seems that | görünüşe göre
there is no point | anlamı yok, boşuna
it's worth | değer
can't help | -mekten kendini alamamak
would you mind | ... sakıncası var mı
I wonder if | acaba ... -ir mi
as far as | -diği kadarıyla
as well | de, da, ayrıca
so far | şimdiye kadar
no matter | ne olursa olsun
for the first time | ilk kez
all of a sudden | birdenbire
over and over | tekrar tekrar
again and again | tekrar tekrar
one by one | teker teker
little by little | azar azar
step by step | adım adım
day by day | günden güne
every now and then | arada bir
as usual | her zamanki gibi
had better | -se iyi olur
used to | eskiden -erdi
be about to | -mek üzere olmak
be supposed to | -mesi gerekiyor/bekleniyor
be used to | -e alışkın olmak
get used to | -e alışmak
there's nothing like | ... gibisi yok
it goes without saying | söylemeye gerek yok
to tell you the truth | doğrusunu söylemek gerekirse
what do you mean | ne demek istiyorsun
I see | anlıyorum
you're welcome | rica ederim
thank goodness | çok şükür
"""

BINOMIALS = """
safe and sound | sağ salim
up and down | aşağı yukarı
back and forth | ileri geri
by and large | genel olarak
far and wide | her yerde, dört bir yanda
here and there | orada burada
now and then | arada sırada
odds and ends | ıvır zıvır
pros and cons | artıları ve eksileri
rise and fall | yükseliş ve düşüş
sick and tired | bıkmış usanmış
trial and error | deneme yanılma
ups and downs | inişler ve çıkışlar
wear and tear | aşınma, yıpranma
black and white | siyah beyaz; açık seçik
bread and butter | ekmek kapısı, temel geçim
first and foremost | her şeyden önce
give and take | karşılıklı fedakârlık
law and order | kanun ve düzen
loud and clear | açık ve net
nice and easy | yavaş ve sakin
peace and quiet | huzur ve sükûnet
rock and roll | rock and roll
short and sweet | kısa ve öz
sooner or later | er ya da geç
thick and thin | iyi gün kötü gün
time and again | tekrar tekrar
tooth and nail | var gücüyle, dişini tırnağına takarak
touch and go | belirsiz, riskli
more or less | aşağı yukarı
all or nothing | ya hep ya hiç
null and void | hükümsüz
heart and soul | candan, tüm benliğiyle
flesh and blood | etten kemikten; öz evlat
over and above | üstüne üstlük, ayrıca
"""

FALSE_FRIENDS = """
actually | aslında (≠ aktüel/güncel)
eventually | sonunda (≠ eventüel/muhtemel)
sympathetic | anlayışlı, şefkatli (≠ sempatik)
sensible | mantıklı, makul (≠ hassas)
sensitive | hassas, duyarlı
lunatic | deli (≠ lunatik/huysuz)
pathetic | acınası (≠ patetik değil tam)
library | kütüphane (≠ kitapevi)
bookstore | kitapçı
camp | kamp; grup (bağlam)
fabric | kumaş (≠ fabrika)
factory | fabrika
cylinder | silindir (≠ şapka)
politics | siyaset (≠ politika/strateji)
policy | politika, ilke
genial | güler yüzlü (≠ dahiyane)
ingenious | dahiyane
nervous | gergin, endişeli (≠ sinirli/öfkeli)
angry | sinirli, kızgın
argument | tartışma (≠ argüman tek anlamı değil)
discussion | görüşme, tartışma
control | denetim; kontrol (≠ check etmek)
check | kontrol etmek
eventual | nihai (≠ eventüel)
agenda | gündem (≠ ajanda/defter)
diary | günlük, ajanda
magazine | dergi (≠ mağaza)
store | mağaza
receipt | makbuz, fiş (≠ reçete)
prescription | reçete
mark | not; işaret (≠ marka)
brand | marka
pension | emekli maaşı (≠ pansiyon)
guesthouse | pansiyon
sentence | cümle; ceza (bağlam)
"""

MODAL_VERBS = """
can | -ebilmek (yetenek, izin)
could | -ebilirdi; -ebilir miyim (kibar)
may | -ebilir (olasılık, izin)
might | -ebilir (zayıf olasılık)
must | -meli, zorunda olmak; kesin -dir
shall | -ecek (öneri: Shall we...?)
should | -meli (tavsiye)
will | -ecek
would | -erdi; -er miydin (kibar)
ought to | -meli (ahlaki gereklilik)
have to | -mek zorunda olmak
has to | -mek zorunda
need to | -mesi gerekmek
needn't | -mesine gerek yok
had better | -se iyi olur
"""

IRREGULAR_VERBS = """
be|was|were|been | olmak
begin|began|begun | başlamak
break|broke|broken | kırmak
bring|brought|brought | getirmek
build|built|built | inşa etmek
buy|bought|bought | satın almak
catch|caught|caught | yakalamak
choose|chose|chosen | seçmek
come|came|come | gelmek
do|did|done | yapmak
draw|drew|drawn | çizmek
drink|drank|drunk | içmek
drive|drove|driven | sürmek
eat|ate|eaten | yemek
fall|fell|fallen | düşmek
feel|felt|felt | hissetmek
fight|fought|fought | dövüşmek
find|found|found | bulmak
fly|flew|flown | uçmak
forget|forgot|forgotten | unutmak
get|got|gotten | almak, olmak
give|gave|given | vermek
go|went|gone | gitmek
grow|grew|grown | büyümek
have|had|had | sahip olmak
hear|heard|heard | duymak
hide|hid|hidden | saklamak
hold|held|held | tutmak
keep|kept|kept | tutmak, saklamak
know|knew|known | bilmek
lead|led|led | yönetmek, yol göstermek
leave|left|left | ayrılmak, bırakmak
lose|lost|lost | kaybetmek
make|made|made | yapmak
mean|meant|meant | anlamına gelmek
meet|met|met | buluşmak
pay|paid|paid | ödemek
ride|rode|ridden | binmek
ring|rang|rung | çalmak (zil)
rise|rose|risen | yükselmek
run|ran|run | koşmak
say|said|said | söylemek
see|saw|seen | görmek
sell|sold|sold | satmak
send|sent|sent | göndermek
shake|shook|shaken | sallamak
shine|shone|shone | parlamak
shoot|shot|shot | ateş etmek
sing|sang|sung | şarkı söylemek
sink|sank|sunk | batmak
sit|sat|sat | oturmak
sleep|slept|slept | uyumak
speak|spoke|spoken | konuşmak
spend|spent|spent | harcamak
stand|stood|stood | ayakta durmak
steal|stole|stolen | çalmak (hırsızlık)
strike|struck|struck | vurmak
swim|swam|swum | yüzmek
take|took|taken | almak
teach|taught|taught | öğretmek
tear|tore|torn | yırtmak
tell|told|told | anlatmak
think|thought|thought | düşünmek
throw|threw|thrown | atmak, fırlatmak
understand|understood|understood | anlamak
wake|woke|woken | uyanmak
wear|wore|worn | giymek
win|won|won | kazanmak
write|wrote|written | yazmak
"""

CATEGORIES = {
    "conjunctions": CONJUNCTIONS,
    "discourse_markers": DISCOURSE_MARKERS,
    "prepositional_phrases": PREPOSITIONAL_PHRASES,
    "phrasal_verbs": PHRASAL_VERBS,
    "collocations": COLLOCATIONS,
    "idioms": IDIOMS,
    "proverbs": PROVERBS,
    "chunks": CHUNKS,
    "binomials": BINOMIALS,
    "false_friends": FALSE_FRIENDS,
    "modal_verbs": MODAL_VERBS,
    "irregular_verbs": IRREGULAR_VERBS,
}
