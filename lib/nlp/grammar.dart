import 'dart:math';

import 'text.dart';
import '../l10n.dart';

class TenseHit {
  final String en;
  final String tr;
  final String explain;
  final String words;
  TenseHit(this.en, this.tr, this.explain, this.words);
}

const _skip = {
  'not', "n't", 'never', 'already', 'just', 'also', 'always', 'still', 'ever', 'probably',
  'really', 'only', 'often', 'even', 'certainly', 'definitely', 'actually', 'finally', 'all'
};
const _modals = {'can', 'could', 'may', 'might', 'must', 'shall', 'should', 'would', 'will', "won't", "can't", "couldn't", "shouldn't", "wouldn't", "mustn't"};
const _subjects = {
  'i', 'you', 'he', 'she', 'it', 'we', 'they', 'who', 'there', 'that', 'this', 'which', 'someone', 'somebody',
  'everyone', 'everybody', 'nobody', 'no one', 'anyone', 'people', 'everything', 'nothing', 'something'
};

/// Rule-based detection of English tenses and verb structures in a sentence.
class TenseDetector {
  final Lemmatizer lem;
  final Set<String> pastForms; // irregular simple past forms
  final Set<String> participles; // irregular past participles
  TenseDetector(this.lem, this.pastForms, this.participles);

  bool _isPP(String w) => participles.contains(w) || (w.endsWith('ed') && w.length > 3);
  bool _isIng(String w) => w.endsWith('ing') && w.length > 4;
  bool _isPast(String w) => pastForms.contains(w) || (w.endsWith('ed') && w.length > 3);

  String _expand(String w) {
    if (w.endsWith("'ll")) return 'will';
    if (w.endsWith("'ve")) return 'have';
    if (w.endsWith("'re")) return 'are';
    if (w.endsWith("'m")) return 'am';
    if (w.endsWith("'d")) return 'would';
    if (w == "won't") return 'will';
    if (w.endsWith("n't")) return w.substring(0, w.length - 3).replaceAll('ca', 'can');
    return w;
  }

  List<TenseHit> detect(List<Token> toks) {
    final w = [for (final t in toks) _expand(t.lower)];
    final raw = [for (final t in toks) t.text];
    final hits = <TenseHit>[];
    final used = <int>{};

    int next(int i) {
      var j = i + 1;
      while (j < w.length && _skip.contains(w[j])) {
        j++;
      }
      return j;
    }

    String span(List<int> idx) => idx.map((i) => raw[i]).join(' ');
    void add(String en, String tr, String ex, List<int> idx) {
      if (idx.any(used.contains)) return;
      used.addAll(idx);
      hits.add(TenseHit(en, tr, ex, span(idx)));
    }

    for (var i = 0; i < w.length; i++) {
      final a = w[i];
      final j = next(i);
      final b = j < w.length ? w[j] : '';
      final k = next(j);
      final c = k < w.length ? w[k] : '';
      final l = next(k);
      final d = l < w.length ? w[l] : '';

      if (a == 'will' || a == 'shall') {
        if (b == 'have' && c == 'been' && _isIng(d)) {
          add('Future Perfect Continuous', 'Gelecekte süregelen bitmiş zaman',
              L('will have been + V-ing: gelecekteki bir ana kadar sürmüş olacak eylem.', 'will have been + V-ing: an action that will have been going on up to a future moment.'), [i, j, k, l]);
        } else if (b == 'have' && _isPP(c)) {
          add('Future Perfect', 'Gelecekte bitmiş zaman', L('will have + V3: gelecekteki bir andan önce tamamlanmış olacak.', 'will have + V3: will be finished before a moment in the future.'), [i, j, k]);
        } else if (b == 'be' && _isIng(c)) {
          add('Future Continuous', 'Gelecekte süren zaman', L('will be + V-ing: gelecekte belli bir anda devam ediyor olacak.', 'will be + V-ing: will be in progress at a certain time in the future.'), [i, j, k]);
        } else if (b == 'be' && _isPP(c)) {
          add('Future Simple (Passive)', 'Gelecek zaman, edilgen', L('will be + V3: gelecekte yapılacak (edilgen).', 'will be + V3: will be done in the future (passive).'), [i, j, k]);
        } else if (b.isNotEmpty) {
          add('Future Simple', 'Gelecek zaman (-ecek)', 'will + V1: gelecekte olacak bir eylem, karar veya tahmin.', [i, j]);
        }
      } else if ((a == 'am' || a == 'is' || a == 'are' || a == "'s") && b == 'going' && c == 'to') {
        add('Be going to', 'Planlı gelecek (-ecek)', L('am/is/are going to + V1: önceden planlanmış veya belirtisi olan gelecek.', 'am/is/are going to + V1: a planned future, or one we can already see coming.'), [i, j, k]);
      } else if ((a == 'was' || a == 'were') && b == 'going' && c == 'to') {
        add('Was/were going to', 'Geçmişte niyet (-ecekti)', L('was/were going to + V1: geçmişte yapılması planlanan.', 'was/were going to + V1: something that was planned in the past.'), [i, j, k]);
      } else if ((a == 'have' || a == 'has') && b == 'been' && _isIng(c)) {
        add('Present Perfect Continuous', 'Geçmişten beri süregelen zaman', L('have/has been + V-ing: geçmişte başlayıp hâlâ süren eylem (-iyor, -dır).', 'have/has been + V-ing: an action that started in the past and is still going on.'), [i, j, k]);
      } else if (a == 'had' && b == 'been' && _isIng(c)) {
        add('Past Perfect Continuous', 'Geçmişte süregelmiş zaman', L('had been + V-ing: geçmişteki bir andan önce bir süredir devam eden.', 'had been + V-ing: had been going on for a while before a moment in the past.'), [i, j, k]);
      } else if ((a == 'have' || a == 'has') && b == 'been' && _isPP(c)) {
        add('Present Perfect (Passive)', 'Yakın geçmiş, edilgen', L('have/has been + V3: yapılmış (edilgen).', 'have/has been + V3: has been done (passive).'), [i, j, k]);
      } else if ((a == 'have' || a == 'has') && _isPP(b) && i > 0) {
        add('Present Perfect', 'Yakın geçmiş / -miş', L('have/has + V3: etkisi şimdiye uzanan geçmiş eylem.', 'have/has + V3: a past action whose effect reaches the present.'), [i, j]);
      } else if (a == 'had' && b == 'been' && _isPP(c)) {
        add('Past Perfect (Passive)', 'Miş\'li geçmiş, edilgen', L('had been + V3: daha önce yapılmıştı (edilgen).', 'had been + V3: had been done earlier (passive).'), [i, j, k]);
      } else if (a == 'had' && _isPP(b)) {
        add('Past Perfect', 'Miş\'li geçmişin hikâyesi (-mişti)', L('had + V3: geçmişteki başka bir olaydan önce olmuştu.', 'had + V3: happened before another past event.'), [i, j]);
      } else if ((a == 'am' || a == 'is' || a == 'are') && b == 'being' && _isPP(c)) {
        add('Present Continuous (Passive)', 'Şimdiki zaman, edilgen', L('am/is/are being + V3: şu anda yapılmakta.', 'am/is/are being + V3: is being done right now.'), [i, j, k]);
      } else if ((a == 'am' || a == 'is' || a == 'are') && _isIng(b)) {
        add('Present Continuous', 'Şimdiki zaman (-iyor)', L('am/is/are + V-ing: şu anda veya bu sıralar olan eylem.', 'am/is/are + V-ing: an action happening now or around this time.'), [i, j]);
      } else if ((a == 'was' || a == 'were') && _isIng(b)) {
        add('Past Continuous', 'Geçmişte süren zaman (-iyordu)', L('was/were + V-ing: geçmişte bir anda devam etmekte olan.', 'was/were + V-ing: was in progress at a moment in the past.'), [i, j]);
      } else if ((a == 'am' || a == 'is' || a == 'are') && _isPP(b)) {
        add('Simple Present (Passive)', 'Geniş zaman, edilgen', L('am/is/are + V3: yapılır (edilgen).', 'am/is/are + V3: is done (passive).'), [i, j]);
      } else if ((a == 'was' || a == 'were') && _isPP(b)) {
        add('Simple Past (Passive)', 'Geçmiş zaman, edilgen', L('was/were + V3: yapıldı (edilgen).', 'was/were + V3: was done (passive).'), [i, j]);
      } else if (a == 'would' && b == 'have' && _isPP(c)) {
        add('Would have + V3', 'Geçmiş koşul (-ardı / -mış olurdu)', L('would have + V3: geçmişte gerçekleşmemiş varsayım (3. tip koşul).', 'would have + V3: an imagined past that did not happen (third conditional).'), [i, j, k]);
      } else if (_modals.contains(a) && b == 'have' && _isPP(c)) {
        add('Modal Perfect', 'Geçmişe yönelik tahmin / pişmanlık', L('${toks[i].text} have + V3: geçmiş hakkında olasılık, çıkarım veya pişmanlık.', '${toks[i].text} have + V3: possibility, deduction or regret about the past.'), [i, j, k]);
      } else if (a == 'would' && b.isNotEmpty) {
        add('Would + V1', 'Koşul / alışkanlık (-erdi)', L('would + V1: varsayım, kibar istek veya geçmişteki alışkanlık.', 'would + V1: an imagined situation, a polite request or a past habit.'), [i, j]);
      } else if (_modals.contains(a) && b.isNotEmpty && !_subjects.contains(b)) {
        add('Modal Verb', 'Kip fiili', L('${toks[i].text} + V1: yetenek, olasılık, zorunluluk veya izin bildirir.', '${toks[i].text} + V1: expresses ability, possibility, obligation or permission.'), [i, j]);
      } else if (a == 'used' && b == 'to') {
        add('Used to', 'Geçmiş alışkanlık (-erdi)', L('used to + V1: eskiden yapılan ama artık yapılmayan.', 'used to + V1: something done in the past but not anymore.'), [i, j]);
      }
    }

    // Simple past / present after a subject when no auxiliary structure was found.
    for (var i = 0; i < w.length - 1; i++) {
      final capital = toks[i].text[0].toUpperCase() == toks[i].text[0];
      if (!_subjects.contains(w[i]) && !capital) continue;
      var j = i + 1;
      while (j < w.length && _skip.contains(w[j])) {
        j++;
      }
      if (j >= w.length || used.contains(j)) continue;
      final v = w[j];
      if (v == 'did' || v == 'was' || v == 'were') {
        add('Simple Past', 'Geçmiş zaman (-di)', L('Geçmişte olup bitmiş eylem.', 'An action that happened and finished in the past.'), [j]);
      } else if (v == 'do' || v == 'does' || v == 'am' || v == 'is' || v == 'are') {
        add('Simple Present', 'Geniş zaman (-ir)', L('Genel doğrular, alışkanlıklar, durumlar.', 'General truths, habits and states.'), [j]);
      } else if (_isPast(v) && lem.lemmas(v).first != v) {
        add('Simple Past', 'Geçmiş zaman (-di)', L('V2: geçmişte olup bitmiş eylem.', 'V2: an action that happened and finished in the past.'), [j]);
      } else if (_subjects.contains(w[i]) && (v.endsWith('s') || {'i', 'you', 'we', 'they'}.contains(w[i])) &&
          !_isIng(v) && !_isPP(v) && !_subjects.contains(v) && !stopWords.contains(v)) {
        add('Simple Present', 'Geniş zaman (-ir)', L('V1 / V1+s: alışkanlık, genel doğru veya kalıcı durum.', 'V1 / V1+s: a habit, general truth or lasting state.'), [j]);
      }
    }

    // Conditionals and other structures signalled by single words.
    final lowerSet = w.toSet();
    if (lowerSet.contains('if') || lowerSet.contains('unless')) {
      final hasWould = lowerSet.contains('would');
      final hasHad = lowerSet.contains('had');
      final hasWill = lowerSet.contains('will');
      String type;
      if (hasWould && hasHad && lowerSet.contains('have')) {
        type = L('3. tip koşul (geçmişte gerçekleşmemiş): If + had V3, would have V3', 'Third conditional (unreal past): If + had V3, would have V3');
      } else if (hasWould) {
        type = L('2. tip koşul (şimdiki/gelecek varsayım): If + V2, would V1', 'Second conditional (imagined present/future): If + V2, would V1');
      } else if (hasWill) {
        type = L('1. tip koşul (gerçek olasılık): If + V1, will V1', 'First conditional (real possibility): If + V1, will V1');
      } else {
        type = L('0. tip koşul (genel doğru) veya basit koşul', 'Zero conditional (general truth) or simple condition');
      }
      hits.add(TenseHit('Conditional', 'Koşul cümlesi', type, w.contains('if') ? 'if' : 'unless'));
    }
    for (var i = 0; i < w.length; i++) {
      if ({'who', 'whom', 'whose', 'which'}.contains(w[i]) && i > 0 && !_modals.contains(w[i - 1])) {
        hits.add(TenseHit('Relative Clause', 'Sıfat cümleciği', L('"${toks[i].text}" önceki ismi niteleyen bir yan cümle başlatıyor (-en, -dığı).', '"${toks[i].text}" starts a clause that describes the noun before it.'), toks[i].text));
        break;
      }
    }
    _structures(toks, w, hits);
    return hits;
  }

  static const _aux = {
    'am', 'is', 'are', 'was', 'were', 'do', 'does', 'did', 'have', 'has', 'had', 'will', 'would', 'can', 'could',
    'shall', 'should', 'may', 'might', 'must'
  };
  static const _pronouns = {'i', 'you', 'he', 'she', 'it', 'we', 'they', 'there'};
  static const _transitions = {
    'however': ('karşıtlık: ancak', 'contrast: however'),
    'therefore': ('sonuç: bu nedenle', 'result: therefore'),
    'moreover': ('ekleme: üstelik', 'addition: moreover'),
    'furthermore': ('ekleme: ayrıca', 'addition: furthermore'),
    'nevertheless': ('karşıtlık: yine de', 'contrast: nevertheless'),
    'consequently': ('sonuç: dolayısıyla', 'result: consequently'),
    'meanwhile': ('zaman: bu arada', 'time: meanwhile'),
    'otherwise': ('koşul: aksi hâlde', 'condition: otherwise'),
  };

  /// Sentence patterns beyond tenses, each pointing to a grammar lesson.
  void _structures(List<Token> toks, List<String> w, List<TenseHit> hits) {
    final lw = [for (final t in toks) t.lower];
    final n = w.length;
    final ws = ' ${lw.join(' ')} ';
    void hit(String en, String tr, String trEx, String enEx, String words) => hits.add(TenseHit(en, tr, L(trEx, enEx), words));
    bool isAux(String x) => _aux.contains(x) || (x.endsWith("n't") && x.length > 3) || x == "won't";

    // Question tag: "…, isn't it?" at the end of a full clause.
    if (n >= 4 && _pronouns.contains(w[n - 1]) && isAux(lw[n - 2]) && n - 2 >= 2) {
      hit('Question Tag', 'Onay sorusu (değil mi?)', '"${toks[n - 2].text} ${toks[n - 1].text}" cümlenin sonundaki "değil mi?" sorusudur; olumlu cümleye olumsuz, olumsuz cümleye olumlu etiket gelir.',
          '"${toks[n - 2].text} ${toks[n - 1].text}" is a question tag: a positive clause takes a negative tag and the other way round.', '${toks[n - 2].text} ${toks[n - 1].text}');
    }
    // There is / there are / there was …
    for (var i = 0; i < n - 1; i++) {
      if (lw[i] == 'there' && {'is', 'are', 'was', 'were', "there's", 'will', 'has', 'have', 'used'}.contains(lw[i + 1])) {
        hit('There is / There are', 'Var / yok yapısı', '"there + be" bir şeyin var olduğunu söyler: tekil isimle is/was, çoğulla are/were.',
            '"there + be" says that something exists: is/was with a singular noun, are/were with a plural.', '${toks[i].text} ${toks[i + 1].text}');
        break;
      }
    }
    // So do I / Neither can I.
    for (var i = 0; i < n - 2; i++) {
      if ((lw[i] == 'so' || lw[i] == 'neither' || lw[i] == 'nor') && isAux(lw[i + 1]) && _pronouns.contains(w[i + 2]) && (i == 0 || i == n - 3)) {
        hit('So / Neither', 'Ben de / Ben de değil', '"${toks[i].text} + yardımcı fiil + özne" başkasının söylediğine katılmayı gösterir: so olumluya, neither olumsuza.',
            '"${toks[i].text} + auxiliary + subject" agrees with what was said: so after a positive, neither after a negative.', '${toks[i].text} ${toks[i + 1].text} ${toks[i + 2].text}');
        break;
      }
    }
    // Causative: have/get + object + V3.
    for (var i = 0; i < n - 2; i++) {
      final v = lem.lemmas(lw[i]).first;
      if ((v == 'have' || v == 'get') && i + 3 < n + 1) {
        for (var k = i + 2; k <= i + 4 && k < n; k++) {
          if (_isPP(lw[k]) && {'my', 'your', 'his', 'her', 'our', 'their', 'the', 'a', 'it', 'them'}.contains(lw[i + 1])) {
            hit('Causative', 'Ettirgen yapı (-tır, -dır)', 'have/get + nesne + V3: işi başkasına yaptırmak (ör. had my hair cut = saçımı kestirdim).',
                'have/get + object + V3: having someone else do the job (e.g. had my hair cut).', toks.sublist(i, k + 1).map((t) => t.text).join(' '));
            i = n;
            break;
          }
        }
      }
    }
    // Wish / if only.
    final wi = lw.indexWhere((x) => x == 'wish' || x == 'wishes' || x == 'wished');
    if (wi > 0 && _subjects.contains(lw[wi - 1]) && wi + 1 < n && _subjects.contains(lw[wi + 1]) || ws.contains(' if only ')) {
      hit('Wish', 'Keşke', 'wish + V2 şimdi için, wish + had V3 geçmiş için "keşke" anlamı verir.', 'wish + V2 for the present, wish + had V3 for the past.', wi >= 0 ? toks[wi].text : 'if only');
    }
    // Too / enough.
    for (var i = 0; i < n - 1; i++) {
      if (lw[i] == 'too' && i + 1 < n && !{'much', 'many'}.contains(lw[i + 1]) && i != n - 1 && (ws.contains(' too ${lw[i + 1]} to ') || i + 2 == n)) {
        hit('Too + adjective', 'Gereğinden fazla (too)', 'too + sıfat (+ to V1): bir şeyin fazlalığı yüzünden olmadığını anlatır.', 'too + adjective (+ to V1): so much that something is not possible.', '${toks[i].text} ${toks[i + 1].text}');
        break;
      }
      if (lw[i + 1] == 'enough' && i + 2 < n && lw[i + 2] == 'to') {
        hit('Adjective + enough', 'Yeterince (enough)', 'sıfat + enough + to V1: yeterli derecede.', 'adjective + enough + to V1: to a sufficient degree.', '${toks[i].text} ${toks[i + 1].text}');
        break;
      }
    }
    // Comparatives and superlatives.
    for (var i = 0; i < n - 1; i++) {
      if ((lw[i] == 'more' || lw[i] == 'less' || (lw[i].endsWith('er') && lw[i].length > 4)) && lw[i + 1] == 'than' ||
          i + 2 < n && lw[i] == 'more' && lw[i + 2] == 'than') {
        hit('Comparative', 'Karşılaştırma (daha …)', 'sıfat-er / more + sıfat + than: iki şeyi karşılaştırır.', 'adjective-er / more + adjective + than: compares two things.', toks.sublist(i, min(n, i + 3)).map((t) => t.text).join(' '));
        break;
      }
      if (lw[i] == 'the' && (lw[i + 1] == 'most' || lw[i + 1] == 'least' || (lw[i + 1].endsWith('est') && lw[i + 1].length > 4) || {'best', 'worst'}.contains(lw[i + 1]))) {
        hit('Superlative', 'Üstünlük (en …)', 'the + sıfat-est / the most + sıfat: bir grubun en …si.', 'the + adjective-est / the most + adjective: the extreme of a group.', toks.sublist(i, min(n, i + 3)).map((t) => t.text).join(' '));
        break;
      }
    }
    // Contrast, purpose and result clauses.
    for (final (key, en, tr, trEx, enEx) in const [
      ('although', 'Although', 'Karşıtlık (-e rağmen)', 'although + cümle: -e rağmen.', 'although + clause: contrast.'),
      ('even though', 'Even though', 'Karşıtlık (-e rağmen)', 'even though + cümle: -mesine rağmen (vurgulu).', 'even though + clause: strong contrast.'),
      ('despite', 'Despite', 'Karşıtlık (-e rağmen)', 'despite + isim / V-ing: -e rağmen (arkasından cümle gelmez).', 'despite + noun / V-ing: contrast without a clause.'),
      ('in spite of', 'In spite of', 'Karşıtlık (-e rağmen)', 'in spite of + isim / V-ing: -e rağmen.', 'in spite of + noun / V-ing: contrast.'),
      ('unless', 'Unless', 'Koşul (-medikçe)', 'unless = if … not: -medikçe, -mezse.', 'unless = if … not.'),
      ('so that', 'So that', 'Amaç (-sin diye)', 'so that + özne + can/could: amaç bildirir.', 'so that + subject + can/could: purpose.'),
      ('in order to', 'In order to', 'Amaç (-mek için)', 'in order to + V1: amaç bildirir.', 'in order to + V1: purpose.'),
      ('as if', 'As if', 'Gibi (-mış gibi)', 'as if + cümle: -mış gibi.', 'as if + clause: as though.'),
      ('as though', 'As though', 'Gibi (-mış gibi)', 'as though + cümle: -mış gibi.', 'as though + clause.'),
      ('whereas', 'Whereas', 'Karşıtlık (oysa)', 'whereas + cümle: iki durumu karşılaştırır, "oysa".', 'whereas + clause: compares two facts.'),
      ('as soon as', 'As soon as', 'Zaman (-er -mez)', 'as soon as + cümle: -er -mez; gelecek için Simple Present alır.', 'as soon as + clause: immediately when; Simple Present for the future.'),
      ('by the time', 'By the time', 'Zaman (-diğinde çoktan)', 'by the time + cümle: o zamana kadar; ana cümle çoğunlukla Perfect olur.', 'by the time + clause: before that moment; the main clause is often perfect.'),
      ('not only', 'Not only … but also', 'Sadece … değil, aynı zamanda', 'not only … but also: iki şeyi birlikte vurgular; başa gelirse devrik cümle kurulur.', 'not only … but also; at the start it takes inversion.'),
    ]) {
      if (ws.contains(' $key ')) hit(en, tr, trEx, enEx, key);
    }
    final so = lw.indexOf('so'), such = lw.indexOf('such');
    if (so >= 0 && so + 2 < n && lw.indexOf('that', so) > so + 1 && lw.indexOf('that', so) <= so + 3) {
      hit('So … that', 'Sonuç (o kadar … ki)', 'so + sıfat/zarf + that: o kadar … ki.', 'so + adjective/adverb + that: result.', 'so … that');
    } else if (such >= 0 && lw.indexOf('that', such) > such + 1 && lw.indexOf('that', such) <= such + 5) {
      hit('Such … that', 'Sonuç (öyle bir … ki)', 'such + (a) + sıfat + isim + that: öyle … ki.', 'such + (a) + adjective + noun + that: result.', 'such … that');
    }
    // Participle clause at the start: "Having finished…", "Walking home, …".
    if (n > 3 && lw[0] == 'having' && _isPP(lw[1])) {
      hit('Participle Clause', 'Ortaç cümleciği (-dikten sonra)', 'Having + V3, …: önce olan eylemi kısaltılmış bir yan cümleyle verir.', 'Having + V3, …: a shortened clause for the earlier action.', '${toks[0].text} ${toks[1].text}');
    }
    // Inversion after a negative adverb: "Never have I…", "Rarely does she…".
    if (n > 3 && {'never', 'rarely', 'seldom', 'hardly', 'scarcely', 'little'}.contains(lw[0]) && isAux(lw[1]) && _subjects.contains(w[2]) ||
        ws.startsWith(' no sooner ') || ws.startsWith(' under no circumstances ') || ws.startsWith(' only when ') && lw.contains('did')) {
      hit('Inversion', 'Devrik cümle', 'Olumsuz bir zarf başa gelince yardımcı fiil özneden önce gelir (Never have I…).', 'After a negative adverb at the start, the auxiliary comes before the subject.', '${toks[0].text} ${toks[1].text}');
    }
    // Cleft sentence: "It was Ali who…", "What I need is…".
    if (n > 4 && lw[0] == 'it' && (lw[1] == 'was' || lw[1] == 'is') && (lw.sublist(3, min(n, 7)).contains('who') || lw.sublist(3, min(n, 7)).contains('that')) && toks[2].text[0] == toks[2].text[0].toUpperCase() ||
        n > 4 && lw[0] == 'what' && _subjects.contains(lw[1]) && lw.sublist(2, min(n, 6)).any((x) => x == 'is' || x == 'was')) {
      hit('Cleft Sentence', 'Vurgulu cümle', 'It was … who/that ya da What … is …: cümlenin bir bölümünü öne çıkarır.', 'It was … who/that or What … is …: puts one part of the sentence in focus.', '${toks[0].text} ${toks[1].text}');
    }
    // Transition words.
    for (var i = 0; i < n; i++) {
      final t = _transitions[lw[i]];
      if (t != null) {
        hit('Transition Word', 'Geçiş sözcüğü', '"${toks[i].text}" (${t.$1}): iki cümleyi mantıkla bağlar, ardından genellikle virgül gelir.', '"${toks[i].text}" (${t.$2}) links two sentences, usually followed by a comma.', toks[i].text);
        break;
      }
    }
    // Impersonal passive: "It is said that…", "He is believed to…".
    for (var i = 0; i < n - 2; i++) {
      if ({'is', 'was', 'are', 'were'}.contains(lw[i]) && {'said', 'believed', 'thought', 'known', 'reported', 'expected', 'considered', 'claimed'}.contains(lw[i + 1]) &&
          (lw[i + 2] == 'that' || lw[i + 2] == 'to')) {
        hit('Impersonal Passive', 'Kişisiz edilgen (… olduğu söyleniyor)', 'be + said/believed + that / to V1: söylenti ve haber dilinde kullanılır.', 'be + said/believed + that / to V1: used in reports and rumours.', '${toks[i].text} ${toks[i + 1].text} ${toks[i + 2].text}');
        break;
      }
    }
  }
}
