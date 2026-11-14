import 'dart:async';
import 'dart:math';

import '../app_state.dart';
import '../data/dict_db.dart';
import '../data/user_db.dart';
import '../nlp/text.dart';
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

  static Tutor of(AppState app) => Tutor(app, app.localAi);

  // ------------------------------------------------------------- prompts

  static const _teacher =
      'Sen VocaBloom uygulamasının deneyimli İngilizce öğretmenisin. Öğrencin Türk; açıklamaları doğal, akıcı ve '
      'dilbilgisi kurallarına uygun Türkçe ile yaparsın. Kısa, net ve sıcak bir üslup kullanırsın. '
      'İngilizce örnekleri ve terimleri İngilizce bırakırsın (ör. Present Perfect, phrasal verb). '
      'Emin olmadığın bir şeyi uydurmazsın; sana verilen sözlük bilgisi ile dilbilgisi analizini doğru kabul edip '
      'onlara dayanırsın. Bölüm başlıklarını **kalın** yazarsın, maddeler için "- " kullanırsın; başka biçimlendirme kullanmazsın.';

  static String _explainSystem() => '$_teacher\n\n'
      'Görev: Verilen İngilizce cümleyi Türk bir öğrenciye açıkla. Yanıtın şu sırayla olsun:\n'
      '**Çeviri:** cümlenin doğal Türkçe çevirisi (kelimesi kelimesine değil).\n'
      '**Yapı:** cümlenin zamanı ve önemli dilbilgisi yapıları, neden kullanıldıkları (1-3 madde).\n'
      '**Kalıplar:** varsa deyim, phrasal verb ve kalıpların bu cümledeki anlamı.\n'
      '**İpucu:** Türklerin bu cümlede sık yaptığı bir hata veya hatırlatma (1 cümle).\n'
      'Toplam 120 kelimeyi geçme.';

  static String _correctSystem() => '$_teacher\n\n'
      'Görev: Öğrencinin yazdığı İngilizce metni düzelt. Yanıtın şu biçimde olsun:\n'
      '**Doğru hâli:** metnin dilbilgisi ve kullanım açısından doğru, doğal hâli. Anlamı değiştirme; gereksiz yere '
      'üslubu değiştirme.\n'
      '**Hatalar:** her hata için bir madde: yanlış → doğru: kısa Türkçe gerekçe (kural adıyla).\n'
      '**Daha doğal:** istersen anadili İngilizce olan birinin söyleyeceği bir alternatif (1 cümle).\n'
      'Metin zaten doğruysa yalnızca "**Doğru hâli:**" satırına aynısını yaz ve "**Hatalar:** Hata yok, tebrikler!" de.\n'
      'Öğrenci Türkçe yazdıysa cümlenin İngilizcesini ver ve nasıl kurulduğunu açıkla.';

  static String _chatSystem(String level, String? topic, List<String> words) =>
      'You are Bloom, a friendly English conversation partner in the VocaBloom app. The learner is Turkish, level '
      '$level (CEFR). Speak natural, everyday English the way people really talk, with contractions and common '
      'phrases, but keep your sentences at the learner\'s level. Keep each reply to 1-3 short sentences and usually '
      'end with a question so the conversation continues. '
      '${topic == null ? '' : 'Topic: $topic. '}'
      '${words.isEmpty ? '' : 'When it fits naturally, use some of these words the learner is studying: ${words.join(', ')}. '}'
      'If the learner\'s last message has a mistake, first reply naturally, then add one line that starts with '
      '"💡 " and gives the correction with a very short reason in Turkish. Do not correct style or punctuation. '
      'If there is no mistake, do not add that line. If the learner writes in Turkish, answer in simple English and '
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
      b.writeln('Kalıplar (sözlükten):');
      final seen = <String>{};
      for (final m in matches) {
        final e = m.expr;
        if (!seen.add(e.phrase)) continue;
        exprWords.addAll(m.tokens);
        final mean = e.trShown ?? e.enTr ?? e.en;
        if (mean == null) continue;
        final cat = categoryById[e.cat]?.name ?? e.cat;
        b.writeln('- ${e.phrase} ($cat): ${_short(mean)}');
      }
    }
    final words = <String>[];
    for (var i = 0; i < toks.length && words.length < 14; i++) {
      if (exprWords.contains(i)) continue;
      final w = toks[i].lower;
      if (w.length < 3 || _function.contains(w)) continue;
      final lemma = app.primaryLemma(w);
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
    "i'm", "it's", "don't", "didn't", "can't", 'all', 'any', 'some',
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
    final facts = grounding(userText);
    final user = 'Öğrencinin metni:\n"""\n${userText.trim()}\n"""'
        '${facts.isEmpty ? '' : '\n\nYardımcı bilgi (yalnızca kelime anlamları için kullan; metnin doğru olduğu '
            'anlamına gelmez):\n$facts'}';
    return ai.generate(_correctSystem(), [('user', user)], maxTokens: 380, temperature: 0.1);
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
          promptTr: 'Boşluğa hangi kelime gelir?',
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
          promptTr: 'Bu kelimenin Türkçe anlamı hangisi?',
          options: opts,
          answer: opts.indexOf(mean),
          explanationTr: '"$lemma" = $mean${ctx == null ? '' : '\nÖrnek: $ctx'}',
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
