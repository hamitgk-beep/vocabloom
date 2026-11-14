import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../app_state.dart';
import '../data/dict_db.dart';
import '../data/user_db.dart';
import '../l10n.dart';
import '../nlp/text.dart';
import 'grammar_chat.dart';
import 'grammar_practice.dart';
import 'local_ai.dart';

/// One multiple-choice question.
class QuizItem {
  /// The question, e.g. a book sentence with the word blanked out.
  final String question;

  /// Turkish instruction shown above the question.
  final String promptTr;
  final List<String> options;

  /// Index of the right option.
  final int answer;

  /// Short Turkish explanation (from the dictionary; never invented).
  final String explanationTr;
  final String word;
  const QuizItem({
    required this.question,
    required this.promptTr,
    required this.options,
    required this.answer,
    required this.explanationTr,
    required this.word,
  });
}

/// The English teacher on top of [LocalAi].
///
/// Small models make fewer mistakes when they do not have to remember facts.
/// So every request carries what the app already knows for sure: the
/// dictionary meanings of the words, the tenses found by the rule-based
/// detector and the expressions in the sentence. The model only has to put
/// them into clear Turkish.
class Tutor {
  final AppState app;
  final LocalAi ai;
  Tutor(this.app, this.ai);

  /// The grammar lessons; tests read them from the file.
  Future<List<GrammarTopic>> Function() lessons = loadGrammarTopics;

  static Tutor of(AppState app) => Tutor(app, app.localAi);

  // ------------------------------------------------------------- prompts

  static const _teacher =
      'Sen VocaBloom uygulamasının deneyimli İngilizce öğretmenisin. Öğrencin Türk; açıklamaları doğal, akıcı ve '
      'dilbilgisi kurallarına uygun Türkçe ile yaparsın. Kısa, net ve sıcak bir üslup kullanırsın. '
      'İngilizce örnekleri ve terimleri İngilizce bırakırsın (ör. Present Perfect, phrasal verb). '
      'Emin olmadığın bir şeyi uydurmazsın; sana verilen sözlük bilgisi ile dilbilgisi analizini doğru kabul edip '
      'onlara dayanırsın. Bölüm başlıklarını **kalın** yazarsın, maddeler için "- " kullanırsın; başka biçimlendirme kullanmazsın.';

  // Small models copy an example far better than they follow a description,
  // so each task carries one short, flawless example answer.
  static String _explainSystem() => '$_teacher\n\n'
      'Görev: Verilen İngilizce cümleyi Türk bir öğrenciye kısaca (en fazla 120 kelime) açıkla. Yanıtın dört '
      'bölümden oluşur: **Çeviri:** (doğal Türkçe çeviri), **Yapı:** (zaman ve dilbilgisi yapıları, 1-3 madde), '
      '**Kalıplar:** (varsa deyim ve phrasal verb; yoksa bu bölümü yazma), **İpucu:** (Türklerin sık yaptığı bir hata, '
      '1 cümle). Türkçe yazımın kusursuz olsun; Türkçe cümlelerin içine İngilizce kelime karıştırma.\n\n'
      'Örnek cümle: "I have been waiting for you since nine o\'clock."\n'
      'Örnek yanıt:\n'
      '**Çeviri:** Saat dokuzdan beri seni bekliyorum.\n'
      '**Yapı:**\n'
      '- "have been waiting": Present Perfect Continuous (geçmişten beri süregelen zaman). Bekleme geçmişte başladı '
      've hâlâ sürüyor.\n'
      '- "since nine o\'clock": "since" başlangıç noktasını verir (-den beri).\n'
      '**Kalıplar:**\n'
      '- wait for someone: birini beklemek.\n'
      '**İpucu:** "since" ile şimdiki zaman kullanılmaz; "I am waiting since nine" yanlıştır.';

  static String _correctSystem() => '$_teacher\n\n'
      'Görev: Öğrencinin yazdığı İngilizce metindeki dilbilgisi ve kelime hatalarını düzelt. Yalnızca gerçekten '
      'yanlış olanları yaz; doğru bir kullanımı asla hata olarak gösterme, üslup ve noktalama hatası arama. Anlamı '
      'değiştirme. Yanıtın: **Doğru hâli:** (metnin doğru hâli), **Hatalar:** (her hata için "- yanlış → doğru: kısa '
      'Türkçe gerekçe"), isteğe bağlı **Daha doğal:** (anadili İngilizce olan birinin söyleyişi, 1 cümle).\n\n'
      'Örnek metin: "Yesterday I have went to school."\n'
      'Örnek yanıt:\n'
      '**Doğru hâli:** Yesterday I went to school.\n'
      '**Hatalar:**\n'
      '- have went → went: "yesterday" bitmiş bir zamanı gösterir, bu yüzden Simple Past (geçmiş zaman) kullanılır.\n\n'
      'Metin zaten doğruysa yanıt yalnızca şudur:\n'
      '**Doğru hâli:** (metnin aynısı)\n'
      '**Hatalar:** Hata yok, tebrikler!';

  static String _translateSystem() => '$_teacher\n\n'
      'Görev: Öğrenci ne demek istediğini Türkçe yazdı. Bunu günlük hayatta söylenecek doğal İngilizceyle ver ve '
      'cümlenin nasıl kurulduğunu kısaca açıkla. Yanıtın: **İngilizcesi:** (cümle), **Nasıl kuruldu:** (1-3 madde).\n\n'
      'Örnek metin: "Ne zamandır burada yaşıyorsun?"\n'
      'Örnek yanıt:\n'
      '**İngilizcesi:** How long have you been living here?\n'
      '**Nasıl kuruldu:**\n'
      '- "Ne zamandır" süre sorduğu için "How long" ile başlar.\n'
      '- Geçmişte başlayıp hâlâ süren durum Present Perfect Continuous ile söylenir: have you been living.';

  /// Whether [text] is Turkish rather than English.
  static bool isTurkish(String text) {
    final t = text.toLowerCase();
    if (RegExp('[çğışöü]').hasMatch(t)) return true;
    final words = RegExp(r"[a-z']+").allMatches(t).map((m) => m.group(0)!).toList();
    const tr = {'ve', 'bir', 'bu', 'ne', 'mi', 'mı', 'ben', 'sen', 'biz', 'için', 'ama', 'çok', 'var', 'yok', 'de', 'da',
      'gibi', 'nasil', 'neden', 'evet', 'hayir', 'tamam', 'merhaba', 'yarin', 'bugun', 'dun'};
    const en = {'the', 'a', 'an', 'is', 'are', 'i', 'you', 'to', 'and', 'of', 'in', 'it', 'have', 'was', 'do', 'my'};
    final nTr = words.where(tr.contains).length, nEn = words.where(en.contains).length;
    return nTr > nEn;
  }

  static String _chatSystem(String level, String? topic, List<String> words) =>
      'You are Bloom, a friendly English conversation partner in the VocaBloom app. The learner is Turkish, level '
      '$level (CEFR). Speak natural, everyday English the way people really talk, with contractions and common '
      'phrases, but keep your sentences at the learner\'s level. Keep each reply to 1-3 short sentences and usually '
      'end with a question so the conversation continues. '
      '${topic == null ? '' : 'Topic: $topic. '}'
      '${words.isEmpty ? '' : 'When it fits naturally, use some of these words the learner is studying: ${words.join(', ')}. '}'
      'If the learner\'s last message has a mistake, first reply naturally, then add one line that starts with '
      '"💡 " and gives the correction with a very short reason in Turkish. Do not correct style or punctuation. '
      'If there is no mistake, never add that line, and never add it to your own sentences. If the learner writes in Turkish, answer in simple English and '
      'add a "💡 " line showing how to say their message in English.';

  // ---------------------------------------------------------- grounding

  /// Facts about [sentence] from the dictionary and the grammar detector.
  String grounding(String sentence) {
    final toks = tokenize(sentence);
    final b = StringBuffer();
    final tenses = app.tenses.detect(toks);
    if (tenses.isNotEmpty) {
      b.writeln('Dilbilgisi analizi (kesin):');
      final seen = <String>{};
      for (final t in tenses) {
        if (!seen.add('${t.en}|${t.words}')) continue;
        b.writeln('- "${t.words}": ${t.en} = ${t.tr}. ${t.explain}');
      }
    }
    final matches = app.dict.matcher.match(toks);
    final exprWords = <int>{};
    if (matches.isNotEmpty) {
      var head = false;
      final seen = <String>{};
      for (final m in matches) {
        final e = m.expr;
        if (!seen.add(e.phrase)) continue;
        // Single words the reader marks anyway (and, be, went …) only add noise.
        if (m.tokens.length == 1 && (e.cat == 'irregular_verbs' || _function.contains(e.phrase))) continue;
        exprWords.addAll(m.tokens);
        final mean = e.trShown ?? e.enTr ?? e.en;
        if (mean == null) continue;
        final cat = categoryById[e.cat]?.name ?? e.cat;
        if (!head) b.writeln('Kalıplar (sözlükten):');
        head = true;
        b.writeln('- ${e.phrase} ($cat): ${_short(mean)}');
      }
    }
    final words = <String>[];
    for (var i = 0; i < toks.length && words.length < 14; i++) {
      if (exprWords.contains(i)) continue;
      final w = toks[i].lower;
      if (w.length < 3 || _function.contains(w)) continue;
      // Names (capitalised inside the sentence) are not looked up: Tom ≠ "erkek kedi".
      if (i > 0 && toks[i].text[0] != toks[i].text[0].toLowerCase()) continue;
      final lemma = _lemma(w);
      if (words.any((x) => x.startsWith('$lemma:'))) continue;
      final info = app.dict.lookup(lemma);
      final tr = _meaningIn(info, toks, i) ?? _meaning(info);
      if (tr != null) words.add('$lemma: $tr');
    }
    if (words.isNotEmpty) {
      b.writeln('Kelime anlamları (sözlükten, cümleye uyanı seç):');
      for (final w in words) {
        b.writeln('- $w');
      }
    }
    return b.toString().trim();
  }

  /// Turkish meanings, the sense that fits the sentence first (the reader's
  /// own choice), then the most common FreeDict meaning.
  String? _meaningIn(WordInfo info, List<Token> toks, int i) {
    final s = app.dict.bestSense(info, toks, i);
    final out = <String>[...?s?.tr.take(2)];
    if (info.trFreeDict.isNotEmpty) {
      final f = info.trFreeDict.first.split(',').first.trim();
      if (!out.contains(f)) out.add(f);
    }
    if (out.isEmpty) return null;
    final pos = s == null ? null : posNames[s.pos == 's' ? 'a' : s.pos];
    return '${out.join(', ')}${pos == null ? '' : ' ($pos)'}';
  }

  /// The word itself when it is a dictionary word, otherwise the longest
  /// lemma (rivers → river, not "rive"; mother stays mother, not "moth").
  String _lemma(String w) {
    final ls = app.dict.lemmatizer.lemmas(w);
    if (ls.contains(w) && !app.dict.lookup(w).isEmpty) return w;
    final c = [...ls]..sort((a, b) => b.length.compareTo(a.length));
    return c.isEmpty ? w : c.first;
  }

  static String? _meaning(WordInfo info) {
    final out = <String>[];
    for (final s in info.senses) {
      for (final t in s.tr) {
        if (!out.contains(t)) out.add(t);
      }
      if (out.length >= 3) break;
    }
    for (final t in info.trFreeDict) {
      if (out.length >= 3) break;
      if (!out.contains(t)) out.add(t);
    }
    return out.isEmpty ? null : out.take(3).join(', ');
  }

  static String _short(String s) => s.length <= 140 ? s : '${s.substring(0, 137)}…';

  static const _function = {
    'the', 'and', 'but', 'for', 'nor', 'yet', 'are', 'was', 'were', 'been', 'being', 'have', 'has', 'had', 'does',
    'did', 'not', "n't", 'you', 'she', 'his', 'her', 'its', 'our', 'their', 'they', 'them', 'him', 'this', 'that',
    'these', 'those', 'with', 'from', 'into', 'onto', 'than', 'then', 'there', 'here', 'what', 'which', 'who',
    'whom', 'whose', 'will', 'would', 'shall', 'should', 'can', 'could', 'may', 'might', 'must', 'very', 'just',
    "i'm", "it's", "don't", "didn't", "can't", 'all', 'any', 'some', 'or', 'only', 'also', 'ever', 'never',
    'one', 'two', 'now', 'out', 'off', 'about', 'over', 'under', 'after', 'before', 'because', 'when', 'while',
    'myself', 'yourself', 'himself', 'herself', 'itself', 'ourselves', 'themselves', 'more', 'most', 'much',
  };

  // -------------------------------------------------------------- tasks

  /// Explains a sentence from a book in Turkish.
  Stream<String> explainSentence(String sentence, {String? paragraph, String? bookTitle}) {
    final facts = grounding(sentence);
    final ctx = paragraph != null && paragraph.length > sentence.length + 20
        ? 'Bağlam (paragraf): ${_short(paragraph.replaceAll('\n', ' '))}\n'
        : '';
    final user = '${bookTitle == null ? '' : 'Kitap: $bookTitle\n'}$ctx'
        'Cümle: "$sentence"\n\n${facts.isEmpty ? '' : '$facts\n\n'}Bu cümleyi açıkla.';
    return ai.generate(_explainSystem(), [('user', user)], maxTokens: 420, temperature: 0.2);
  }

  /// Corrects the learner's English (or helps with a Turkish sentence).
  Stream<String> correct(String userText) {
    if (isTurkish(userText)) {
      return ai.generate(_translateSystem(), [('user', 'Öğrencinin metni:\n"""\n${userText.trim()}\n"""')],
          maxTokens: 260, temperature: 0.2);
    }
    final facts = grounding(userText);
    final user = 'Öğrencinin metni:\n"""\n${userText.trim()}\n"""'
        '${facts.isEmpty ? '' : '\n\nYardımcı bilgi (yalnızca kelime anlamları için kullan; metnin doğru olduğu '
            'anlamına gelmez):\n$facts'}';
    return _guardNoError(userText, ai.generate(_correctSystem(), [('user', user)], maxTokens: 380, temperature: 0.1));
  }

  @visibleForTesting
  static Stream<String> guardNoErrorForTest(String original, Stream<String> answer) => _guardNoError(original, answer);

  static const noErrorAnswer = '**Hatalar:** Hata yok, tebrikler!';

  /// Small models sometimes list "mistakes" in a correct text. When the
  /// corrected text the model gives is the learner's text itself, the answer is
  /// "no mistakes", whatever else it wrote. The answer is streamed as usual
  /// once the "Doğru hâli" line is complete.
  static Stream<String> _guardNoError(String original, Stream<String> answer) async* {
    final buf = StringBuffer();
    var decided = false;
    await for (final piece in answer) {
      if (decided) {
        yield piece;
        continue;
      }
      buf.write(piece);
      final text = buf.toString();
      final m = RegExp(r'\*\*Doğru hâli:\*\*\s*(.+?)\s*\n\s*\*\*Hatalar', dotAll: true).firstMatch(text);
      if (m == null) {
        if (text.length > 1200) {
          decided = true;
          yield text;
        }
        continue;
      }
      decided = true;
      if (sameText(m.group(1)!, original)) {
        yield '**Doğru hâli:** ${original.trim()}\n$noErrorAnswer';
        return;
      }
      yield text;
    }
    if (!decided) yield buf.toString();
  }

  /// Equal apart from case, quotes, spaces and final punctuation.
  static bool sameText(String a, String b) {
    String n(String s) => s
        .toLowerCase()
        .replaceAll(RegExp('[’‘]'), "'")
        .replaceAll(RegExp(r'["“”]'), '')
        .replaceAll(RegExp(r'[.!?,;:\s]+'), ' ')
        .trim();
    return n(a) == n(b);
  }

  /// Next turn of an everyday conversation. [history] is (role, text) with
  /// role 'user' or 'assistant'; an empty history makes Bloom open the chat.
  Stream<String> chatReply(List<(String, String)> history, {String level = 'B1', String? topic}) {
    final learning = app.user.words(WordStatus.learning).take(8).map((w) => w.lemma).toList();
    final msgs = history.isEmpty
        ? [('user', 'Start the conversation with a short, friendly question${topic == null ? '' : ' about $topic'}.')]
        // Keep the context small on phones: the last 12 turns.
        : history.sublist(max(0, history.length - 12));
    return ai.generate(_chatSystem(level, topic, learning), msgs, maxTokens: 160, temperature: 0.7);
  }

  /// The chat: everyday conversation, and grammar study when the learner
  /// asks for it ("bugün modals çalışalım", "passive anlat", "cümle sor").
  /// [session] keeps a running translation drill between turns.
  Stream<String> chat(TutorChatSession session, List<(String, String)> history, {String level = 'B1', String? topic}) async* {
    final text = history.isNotEmpty && history.last.$1 == 'user' ? history.last.$2.trim() : '';
    if (text.isEmpty) {
      yield* chatReply(history, level: level, topic: topic);
      return;
    }
    final topics = await lessons();
    final drill = session.drill;
    if (drill != null && !drill.finished) {
      if (isDrillStop(text)) {
        session.drill = null;
        yield drillSummary(drill);
        return;
      }
      if (isDrillSkip(text)) {
        final (_, e) = drill.current;
        drill.index++;
        yield '${L('**Doğru cevap:**', '**Answer:**')} "${e.answers.first}"\n${e.noteTr}\n\n${_nextOrEnd(session, drill)}';
        return;
      }
    }
    final drilling = drill != null && !drill.finished;
    // During a drill an English line is an answer ("I have to take a test"
    // is not a request); a new topic is asked for in Turkish.
    final intent = drilling && !isTurkish(text) ? null : parseGrammarIntent(text, topics, last: session.last);
    if (intent != null) {
      yield* _startGrammar(session, intent, topics);
      return;
    }
    if (drill != null && !drill.finished) {
      final (t, e) = drill.current;
      if (isTurkish(text) && !isCorrectTranslation(e, text)) {
        yield '${L('Bu cümleyi İngilizce yazmalısın:', 'Please write this sentence in English:')} **"${e.tr}"**\n'
            '${L('İpucu:', 'Hint:')} ${e.noteTr}\n$drillHelp';
        return;
      }
      final right = isCorrectTranslation(e, text);
      yield* checkTranslation(t, e, text);
      if (right) {
        drill.right++;
        GrammarProgress(app.user).markDone(t.id, e.id);
      }
      drill.index++;
      yield '\n\n${_nextOrEnd(session, drill)}';
      return;
    }
    yield* chatReply(history, level: level, topic: topic);
  }

  String _nextOrEnd(TutorChatSession session, GrammarDrill drill) {
    if (!drill.finished) return drillQuestion(drill);
    session.drill = null;
    return drillSummary(drill);
  }

  Stream<String> _startGrammar(TutorChatSession session, GrammarIntent intent, List<GrammarTopic> topics) async* {
    if (intent.mode == GrammarMode.list) {
      yield topicList(topics);
      return;
    }
    session.last = intent;
    final t = intent.topic;
    if (intent.mode == GrammarMode.explain) {
      session.drill = null;
      yield '${t != null ? topicExplanation(t) : categoryOverview(intent.category!, topics)}\n\n'
          '${L('Bu konuda çeviri alıştırması yapmak istersen **"cümle sor"** yaz.', 'To practise this topic with translation sentences, write **"quiz me"**.')}';
      return;
    }
    final done = <String>{
      for (final x in topics.where((x) => t != null ? x.id == t.id : x.category == intent.category))
        ...GrammarProgress(app.user).done(x.id)
    };
    final drill = session.drill = startDrill(intent, topics, done: done);
    final intro = intent.mode == GrammarMode.study
        ? '${t != null ? topicExplanation(t, short: true) : categoryOverview(intent.category!, topics).split('\n\nBirini').first}\n\n'
            '${L('Şimdi pratik yapalım. Türkçe cümleleri İngilizceye çevir, ben de kontrol edeyim.', 'Now let\'s practise. Translate the Turkish sentences into English and I\'ll check them.')} $drillHelp\n\n'
        : '${L('**${drill.title}** için ${drill.items.length} cümle hazırladım.', 'I have ${drill.items.length} sentences on **${drill.title}** for you.')} $drillHelp\n\n';
    yield '$intro${drillQuestion(drill)}';
  }

  // ------------------------------------------------------ grammar practice

  static String _gradeSystem() => '$_teacher\n\n'
      'Görev: Gramer pratiği. Öğrenci verilen Türkçe cümleyi İngilizceye çevirdi. Cevabını, sana verilen doğru '
      'cevaplar ve konunun kuralıyla karşılaştırarak değerlendir. Doğru cevaplar kesin doğrudur; öğrencinin cevabı '
      'onlardan farklı ama dilbilgisi ve anlam olarak da doğruysa bunu kabul et. Yalnızca gerçek hataları göster.\n'
      'Yanıtın şu biçimde olsun:\n'
      '1. İlk satır: kısa, cesaret verici bir değerlendirme (ör. "Harika bir deneme! Anlamı neredeyse tam verdin.").\n'
      '2. **Düzeltmeler:** her hata için numaralı madde: kuralın adı, neyin yanlış olduğu ve doğru biçimi.\n'
      '3. **Doğru ve doğal kurulumlar:** "- " ile doğru cevaplardan en uygun bir veya iki tanesi, gerekirse kısa bir not.\n'
      'Cevap tamamen doğruysa yalnızca övgü satırını ve **Doğru ve doğal kurulumlar:** bölümünü yaz.\n\n'
      'Örnek:\n'
      'Türkçe: "İş yüküm artmasına rağmen projeyi zamanında bitirebildim."\n'
      'Öğrencinin cevabı: "I was able to complete the project although increase my workload"\n'
      'Örnek yanıt:\n'
      'Harika bir deneme! Anlamı neredeyse tam verdin, sadece "although" sonrasındaki yapıyı düzeltmemiz gerekiyor.\n'
      '**Düzeltmeler:**\n'
      '1. "Although" yapısı: although bir bağlaçtır, arkasından tam bir cümle (özne + fiil) gelir: "although my '
      'workload increased".\n'
      '2. "Despite" seçeneği: arkasından cümle değil isim getirmek istersen "despite" kullanılır: "despite my '
      'increased workload".\n'
      '3. "Zamanında" karşılığı eksik: "on time" eklenmeli.\n'
      '**Doğru ve doğal kurulumlar:**\n'
      '- "I was able to finish the project on time, although my workload increased."\n'
      '- "I managed to finish the project on time despite my increased workload." ("managed to", "üstesinden gelerek '
      'başardım" vurgusu katar.)';

  /// Whether [answer] is one of the correct versions (no model needed).
  bool isCorrectTranslation(GrammarExercise e, String answer) => matchesReference(e, answer);

  /// Feedback on the learner's translation of [e]. A right answer is praised
  /// at once without the model; otherwise the model compares it with the
  /// correct versions and the topic's rule.
  Stream<String> checkTranslation(GrammarTopic t, GrammarExercise e, String answer) {
    if (matchesReference(e, answer)) {
      final others = e.answers.where((a) => !matchesReference(GrammarExercise('', '', [a], ''), answer)).take(2).toList();
      return Stream.value('${L('Harika, tamamen doğru! 🎉', 'Great, exactly right! 🎉')}'
          '${others.isEmpty ? '' : '\n${L('**Doğru ve doğal kurulumlar:**', '**Other natural ways to say it:**')}\n${others.map((a) => '- "$a"').join('\n')}'}');
    }
    final user = 'Konu: ${t.titleTr} (${t.titleEn})\n'
        'Kural: ${e.noteTr.isEmpty ? t.structureTr.join(' / ') : e.noteTr}\n'
        'Türkçe: "${e.tr}"\n'
        'Doğru cevaplar:\n${e.answers.map((a) => '- "$a"').join('\n')}\n'
        'Öğrencinin cevabı: "${answer.trim()}"';
    return ai.generate(_gradeSystem(), [('user', user)], maxTokens: 420, temperature: 0.2);
  }

  /// Multiple-choice questions on the learner's words.
  ///
  /// The questions, options and answers come from the dictionary and the
  /// sentences the words were saved from, so they are always right. The model
  /// is not needed for this; [explain] can add an AI explanation afterwards.
  Future<List<QuizItem>> quiz({List<String>? words, int count = 5, int? seed}) async {
    final rnd = Random(seed);
    final saved = [...app.user.words(WordStatus.learning), ...app.user.words(WordStatus.learned)];
    final pool = <(String, String, String?)>[]; // lemma, meaning, context
    final want = words?.toSet();
    for (final w in saved) {
      if (want != null && !want.contains(w.lemma)) continue;
      final m = w.meaning ?? _meaning(app.dict.lookup(w.lemma));
      if (m == null) continue;
      pool.add((w.lemma, m.split(',').first.trim(), w.context));
    }
    if (want != null) {
      for (final l in want) {
        if (pool.any((x) => x.$1 == l)) continue;
        final m = _meaning(app.dict.lookup(l));
        if (m != null) pool.add((l, m.split(',').first.trim(), null));
      }
    }
    if (pool.length < 4) {
      // Not enough saved words: fill the option pool with common words.
      for (final l in _fillers) {
        if (pool.length >= 8) break;
        if (pool.any((x) => x.$1 == l)) continue;
        final m = _meaning(app.dict.lookup(l));
        if (m != null) pool.add((l, m.split(',').first.trim(), null));
      }
    }
    pool.shuffle(rnd);
    final out = <QuizItem>[];
    for (final (lemma, mean, ctx) in pool) {
      if (out.length >= count) break;
      final others = pool.where((x) => x.$1 != lemma).toList()..shuffle(rnd);
      if (others.length < 3) break;
      final blank = ctx == null ? null : _blank(ctx, lemma);
      if (blank != null && rnd.nextBool()) {
        final opts = [lemma, ...others.take(3).map((x) => x.$1)]..shuffle(rnd);
        out.add(QuizItem(
          question: blank,
          promptTr: L('Boşluğa hangi kelime gelir?', 'Which word fills the gap?'),
          options: opts,
          answer: opts.indexOf(lemma),
          explanationTr: '"$lemma" = $mean',
          word: lemma,
        ));
      } else {
        final opts = [mean, ...others.map((x) => x.$2).where((m) => m != mean).toSet().take(3)]..shuffle(rnd);
        if (opts.length < 4) continue;
        out.add(QuizItem(
          question: lemma,
          promptTr: L('Bu kelimenin Türkçe anlamı hangisi?', 'What does this word mean in Turkish?'),
          options: opts,
          answer: opts.indexOf(mean),
          explanationTr: '"$lemma" = $mean${ctx == null ? '' : '\n${L('Örnek', 'Example')}: $ctx'}',
          word: lemma,
        ));
      }
    }
    return out;
  }

  /// A short AI explanation of a quiz item after it was answered.
  Stream<String> explain(QuizItem q) => ai.generate(
        '$_teacher\n\nGörev: Bir kelime sorusunun cevabını 2-3 cümleyle açıkla ve kelimeyle yeni, kısa bir '
        'İngilizce örnek cümle ve Türkçesini ver.',
        [
          (
            'user',
            'Soru: ${q.question}\nDoğru cevap: ${q.options[q.answer]}\nSözlük: ${q.explanationTr}\n'
                '${grounding(q.word)}'
          )
        ],
        maxTokens: 200,
        temperature: 0.3,
      );

  /// [sentence] with every form of [lemma] replaced by "_____", or null when
  /// the word is not found in it.
  String? _blank(String sentence, String lemma) {
    final toks = tokenize(sentence);
    for (final t in toks.reversed) {
      if (t.lower == lemma || app.dict.lemmatizer.lemmas(t.lower).contains(lemma)) {
        return sentence.replaceRange(t.start, t.end, '_____');
      }
    }
    return null;
  }

  static const _fillers = [
    'decide', 'remember', 'improve', 'careful', 'borrow', 'journey', 'achieve', 'enough', 'suddenly', 'weather',
  ];
}
