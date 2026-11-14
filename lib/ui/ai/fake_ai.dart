// Stand-in engine for screenshots and tests until lib/ai/ lands.
import 'dart:async';

import 'ai_types.dart';

const _gb = 1024 * 1024 * 1024;

const fakePackages = <AiPackage>[
  AiPackage(
    id: 'lite',
    tier: 'free',
    nameTr: 'Hafif',
    nameEn: 'Lite',
    descTr: 'Her telefonda çalışan hızlı paket. Cümle açıklama ve kısa düzeltmeler için uygundur.',
    descEn: 'A fast package that runs on any phone. Suited to sentence explanations and short corrections.',
    noteTr: 'Yanıtlar zaman zaman hatalı olabilir; önemli konularda sözlükle doğrulayın.',
    noteEn: 'Answers may occasionally be wrong; verify important points with the dictionary.',
    ratings: [('Türkçe açıklama', 'Turkish explanations', 3), ('Dilbilgisi doğruluğu', 'Grammar accuracy', 3), ('Sohbet akıcılığı', 'Chat fluency', 2), ('Hız', 'Speed', 5)],
    sizeBytes: 500 * 1024 * 1024,
    model: 'Qwen3 0.6B',
    licenseName: 'Apache 2.0',
    premium: false,
    minRamGb: 3,
  ),
  AiPackage(
    id: 'standard',
    tier: 'plus',
    nameTr: 'Standart',
    nameEn: 'Standard',
    descTr: 'Açıklamalarda ve düzeltmelerde dengeli kalite. Çeviri tutarlılığı iyidir; günlük kullanım için önerilir.',
    descEn: 'Balanced quality for explanations and corrections. Translation consistency is good; recommended for daily use.',
    noteTr: 'Uzun ve karmaşık cümlelerde nadiren hata yapabilir.',
    noteEn: 'May rarely make mistakes with long, complex sentences.',
    ratings: [('Türkçe açıklama', 'Turkish explanations', 4), ('Dilbilgisi doğruluğu', 'Grammar accuracy', 4), ('Sohbet akıcılığı', 'Chat fluency', 4), ('Hız', 'Speed', 4)],
    sizeBytes: 3 * _gb ~/ 2,
    model: 'Qwen3 1.7B',
    licenseName: 'Apache 2.0',
    premium: true,
    minRamGb: 6,
  ),
  AiPackage(
    id: 'pro',
    tier: 'pro',
    nameTr: 'Pro',
    nameEn: 'Pro',
    descTr: 'En yüksek doğruluk. Dilbilgisi açıklamaları ayrıntılı, sohbet pratiği doğal ve akıcıdır.',
    descEn: 'The highest accuracy. Detailed grammar explanations and natural, fluent chat practice.',
    noteTr: 'Güçlü telefon ister; eski cihazlarda yavaş çalışabilir.',
    noteEn: 'Needs a powerful phone; may be slow on older devices.',
    ratings: [('Türkçe açıklama', 'Turkish explanations', 5), ('Dilbilgisi doğruluğu', 'Grammar accuracy', 5), ('Sohbet akıcılığı', 'Chat fluency', 5), ('Hız', 'Speed', 3)],
    sizeBytes: 3 * _gb,
    model: 'Qwen3 4B',
    licenseName: 'Apache 2.0',
    premium: true,
    minRamGb: 8,
  ),
];

class FakeLocalAi extends LocalAi {
  final Set<String> _installed;
  String? _active;
  @override
  bool premiumUnlocked;
  final Map<String, double> partial;
  FakeLocalAi({Set<String>? installed, this.premiumUnlocked = false, String? active, Map<String, double>? partial})
      : _installed = installed ?? {},
        _active = active,
        partial = partial ?? {};

  @override
  List<AiPackage> get packages => fakePackages;
  @override
  Future<Set<String>> installed() async => {..._installed};
  @override
  String? get activeId => _active;
  @override
  Future<void> setActive(String id) async {
    _active = id;
    notifyListeners();
  }

  @override
  Future<int?> deviceRamMb() async => 6144;

  @override
  Stream<AiDownload> download(String id) async* {
    final p = packages.firstWhere((p) => p.id == id);
    for (var i = 1; i <= 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 60));
      yield AiDownload(p.sizeBytes * i ~/ 20, p.sizeBytes);
    }
    _installed.add(id);
    _active ??= id;
    notifyListeners();
  }

  @override
  Future<void> cancel(String id) async {}
  @override
  Future<void> delete(String id) async {
    _installed.remove(id);
    if (_active == id) _active = _installed.isEmpty ? null : _installed.first;
    notifyListeners();
  }

  @override
  Stream<String> generate(String system, List<(String, String)> messages, {int maxTokens = 512}) =>
      _words('This is a sample answer.');
}

Stream<String> _words(String text) async* {
  for (final w in text.split(' ')) {
    await Future<void>.delayed(const Duration(milliseconds: 15));
    yield '$w ';
  }
}

class FakeTutor extends Tutor {
  @override
  Stream<String> explainSentence(String sentence, {String? bookTitle}) => _words(
      '**Anlamı:** Eğer bu sokaklardan birinde yürürsen, çok çeşitli lezzetli yiyecekler satın alabilirsin.\n\n'
      '**Yapı:** Bu bir ikinci tip koşul cümlesi (second conditional): "If + geçmiş zaman, could + fiil". '
      'Gerçek olmayan ya da hayali bir durumu anlatır.\n\n'
      '**walked down:** Burada "walk down" düz anlamıyla kullanılmış: bir cadde boyunca yürümek.\n\n'
      '**an amazing choice of:** "çok geniş bir seçenek yelpazesi" anlamına gelen kalıp.');

  @override
  Stream<String> correct(String userText) => _words(
      '**Düzeltilmiş:** I have been living in Istanbul for three years.\n\n'
      '**Neden:** Geçmişte başlayıp hâlâ süren bir durum için "present perfect continuous" kullanılır; "since" yerine süre belirttiğin için "for" gelir.');

  @override
  Stream<String> chatReply(List<(String, String)> history, {String level = 'B1', String? topic}) =>
      _words('That sounds great! What kind of books do you enjoy reading the most?');

  @override
  Future<List<QuizItem>> quiz(List<String> words, {int count = 5}) async => const [
        QuizItem('She decided to ___ smoking after the doctor\'s warning.', ['give up', 'give in', 'give out', 'give off'], 0,
            '"give up" bir alışkanlığı bırakmak demektir. "give in" pes etmek, "give off" koku/ısı yaymaktır.'),
        QuizItem('Which word means "dar, ensiz"?', ['wide', 'narrow', 'shallow', 'steep'], 1, '"narrow" dar demektir; "wide" geniş anlamına gelir.'),
        QuizItem('___ it was raining, they went for a walk.', ['Because', 'Although', 'Unless', 'So'], 1,
            '"Although" -e rağmen anlamında zıtlık bildirir.'),
      ];
}
