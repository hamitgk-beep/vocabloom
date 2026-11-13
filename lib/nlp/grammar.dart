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
    return hits;
  }
}
