/// Grammar structures the reader can highlight: tenses, conditionals,
/// relative clauses, gerund / infinitive, comparison and reported speech.
///
/// Everything is rule-based and offline. The rules prefer to say nothing
/// over saying something wrong: a verb whose role is unclear (a noun that
/// can also be a verb, an -ed word that may be an adjective …) is left
/// unmarked.
library;

import 'text.dart';

/// A text in both interface languages: (Turkish, English).
typedef Tx = (String, String);

/// Filter ids of the grammar highlights, in display order.
const grammarCatIds = [
  'g_tenses', 'g_passive', 'g_conditionals', 'g_relative', 'g_gerund_inf', 'g_comparison', 'g_reported', //
  'g_past_modals', 'g_used_to', 'g_causative', 'g_emphasis', 'g_tags', 'g_participles',
];

/// One structure found in a paragraph.
class GMark {
  /// Filter id (one of [grammarCatIds]).
  final String cat;

  /// Structure id, e.g. 'past_perfect', 'cond_2', 'rel_who'.
  final String key;

  /// Paragraph token indices, ascending (not always next to each other:
  /// "Have you seen" marks "Have" and "seen").
  final List<int> tokens;

  /// Grammar topics to open (the first is the main one).
  final List<String> lessons;

  /// English term and Turkish name: ('Past Perfect', "Miş'li geçmişin hikâyesi").
  final String en;
  final String tr;

  /// What the structure is (general).
  final Tx explain;

  /// What it does in this sentence (antecedent, the two clauses, backshift …).
  final Tx? note;

  /// Colour variant inside the filter. Tenses: 0 present, 1 past, 2 future.
  final int tone;

  const GMark(this.cat, this.key, this.tokens, this.lessons, this.en, this.tr, this.explain, {this.note, this.tone = 0});

  @override
  String toString() => '$key(${tokens.join(',')})';
}

/// Verb group found in a sentence (finite tense, or modal).
class _VG {
  final List<int> toks;

  /// Tense key ('simple_past' …) or 'modal', 'modal_perfect'.
  final String kind;
  final bool passive;

  /// The modal word for modal groups ("would", "could" …).
  final String modal;
  _VG(this.toks, this.kind, {this.passive = false, this.modal = ''});
  int get first => toks.first;
  int get last => toks.last;
  bool get isTense => kind != 'modal' && kind != 'modal_perfect' && kind != 'imperative';
}

class _TenseInfo {
  final String en, tr, exTr, exEn, lesson;
  final int tone;
  const _TenseInfo(this.en, this.tr, this.exTr, this.exEn, this.lesson, this.tone);
}

const _tenses = <String, _TenseInfo>{
  'simple_present': _TenseInfo(
    'Simple Present',
    'Geniş zaman',
    'V1 / V1+s (do / does): alışkanlıklar, genel doğrular ve kalıcı durumlar.',
    'V1 / V1+s (do / does): habits, general truths and lasting states.',
    'simple_present',
    0,
  ),
  'present_continuous': _TenseInfo(
    'Present Continuous',
    'Şimdiki zaman (-iyor)',
    'am / is / are + V-ing: şu anda ya da bu sıralar süren eylem.',
    'am / is / are + V-ing: an action going on now or around this time.',
    'present_continuous',
    0,
  ),
  'present_perfect': _TenseInfo(
    'Present Perfect',
    'Yakın geçmiş (-miş, -di)',
    'have / has + V3: geçmişte olmuş, etkisi şimdiye uzanan eylem.',
    'have / has + V3: a past action whose result reaches the present.',
    'present_perfect',
    0,
  ),
  'present_perfect_continuous': _TenseInfo(
    'Present Perfect Continuous',
    'Geçmişten beri süren zaman',
    'have / has been + V-ing: geçmişte başlayıp hâlâ süren ya da yeni biten eylem.',
    'have / has been + V-ing: started in the past and still going on (or just stopped).',
    'present_perfect_continuous',
    0,
  ),
  'simple_past': _TenseInfo(
    'Simple Past',
    'Geçmiş zaman (-di)',
    'V2 (did): geçmişte olup bitmiş eylem. Hikâyelerin ana zamanı.',
    'V2 (did): an action that happened and finished in the past. The main tense of stories.',
    'simple_past',
    1,
  ),
  'past_continuous': _TenseInfo(
    'Past Continuous',
    'Geçmişte süren zaman (-iyordu)',
    'was / were + V-ing: geçmişte bir anda devam etmekte olan eylem.',
    'was / were + V-ing: an action in progress at a moment in the past.',
    'past_continuous',
    1,
  ),
  'past_perfect': _TenseInfo(
    'Past Perfect',
    "Miş'li geçmişin hikâyesi (-mişti)",
    'had + V3: geçmişteki başka bir olaydan daha önce olmuş eylem.',
    'had + V3: happened before another past event.',
    'past_perfect',
    1,
  ),
  'past_perfect_continuous': _TenseInfo(
    'Past Perfect Continuous',
    'Geçmişte süregelmiş zaman (-iyordu)',
    'had been + V-ing: geçmişteki bir andan önce bir süredir devam eden eylem.',
    'had been + V-ing: had been going on for a while before a moment in the past.',
    'past_perfect',
    1,
  ),
  'used_to': _TenseInfo(
    'Used to',
    'Geçmiş alışkanlık (-erdi)',
    'used to + V1: eskiden düzenli yapılan ama artık yapılmayan eylem ya da eski durum.',
    'used to + V1: something done regularly in the past but not any more, or a past state.',
    'used_to',
    1,
  ),
  'was_going_to': _TenseInfo(
    'Was / were going to',
    'Geçmişteki plan (-ecekti)',
    'was / were going to + V1: geçmişte yapılması planlanan (çoğu zaman yapılmayan) eylem.',
    'was / were going to + V1: something planned in the past (often it did not happen).',
    'future',
    1,
  ),
  'future_simple': _TenseInfo(
    'Future Simple',
    'Gelecek zaman (-ecek)',
    'will + V1: gelecekte olacak eylem, tahmin, söz ya da anlık karar.',
    'will + V1: a future action, a prediction, a promise or a decision made now.',
    'future',
    2,
  ),
  'going_to': _TenseInfo(
    'Be going to',
    'Planlı gelecek (-ecek)',
    'am / is / are going to + V1: önceden planlanmış ya da belirtisi görülen gelecek.',
    'am / is / are going to + V1: a planned future, or one we can already see coming.',
    'future',
    2,
  ),
  'future_continuous': _TenseInfo(
    'Future Continuous',
    'Gelecekte süren zaman (-iyor olacak)',
    'will be + V-ing: gelecekte belli bir anda devam ediyor olacak eylem.',
    'will be + V-ing: will be in progress at a moment in the future.',
    'future_continuous_perfect',
    2,
  ),
  'future_perfect': _TenseInfo(
    'Future Perfect',
    'Gelecekte bitmiş zaman (-miş olacak)',
    'will have + V3: gelecekteki bir andan önce tamamlanmış olacak eylem.',
    'will have + V3: will be finished before a moment in the future.',
    'future_continuous_perfect',
    2,
  ),
  'future_perfect_continuous': _TenseInfo(
    'Future Perfect Continuous',
    'Gelecekte süregelmiş zaman',
    'will have been + V-ing: gelecekteki bir ana kadar sürmüş olacak eylem.',
    'will have been + V-ing: will have been going on up to a moment in the future.',
    'future_continuous_perfect',
    2,
  ),
};

const _passiveTx = (
  ' Edilgen (passive): özne işi yapan değil, işten etkilenen; yapan kişi gerekirse "by" ile söylenir.',
  ' Passive: the subject does not do the action but receives it; the doer, if needed, comes with "by".',
);

// ------------------------------------------------------------ word lists

const _skip = {
  'not',
  'never',
  'already',
  'just',
  'also',
  'always',
  'still',
  'ever',
  'probably',
  'really',
  'only',
  'often',
  'even',
  'certainly',
  'definitely',
  'actually',
  'finally',
  'all',
  'both',
  'sometimes',
  'usually',
  'soon',
  'hardly',
  'nearly',
  'almost',
  'surely',
  'simply',
  'merely',
  'quite',
  'rather',
  'once',
  'again',
  'now',
  'then',
  'perhaps',
  'suddenly',
  'slowly',
  'quickly',
  'immediately',
  'gradually',
  'seldom',
  'rarely',
  'barely',
  'scarcely',
  'mostly',
  'clearly',
  'obviously',
  'apparently',
  'evidently',
  'possibly',
  'generally',
  'normally',
  'recently',
  'completely',
  'entirely',
  'totally',
  'fully',
  'partly',
  'truly',
  'indeed',
  'too',
  'each',
  'yet',
  'long',
  'since',
  'first',
  'later',
  'secretly',
  'quietly',
  'happily',
  'sadly',
};
const _subjOnly = {'i', 'he', 'she', 'we', 'they'};
const _subjMaybe = {
  'you',
  'it',
  'who',
  'which',
  'one',
  'this',
  'that',
  'these',
  'those',
  'everyone',
  'everybody',
  'someone',
  'somebody',
  'nobody',
  'anyone',
  'anybody',
  'everything',
  'something',
  'nothing',
  'anything',
  'all',
  'none',
  'both',
  'each',
};
const _singularSubj = {
  'he',
  'she',
  'it',
  'this',
  'that',
  'one',
  'everyone',
  'everybody',
  'someone',
  'somebody',
  'nobody',
  'anyone',
  'anybody',
  'everything',
  'something',
  'nothing',
  'anything',
  'each',
};
const _det = {
  'the',
  'a',
  'an',
  'this',
  'that',
  'these',
  'those',
  'my',
  'your',
  'his',
  'her',
  'its',
  'our',
  'their',
  'some',
  'every',
  'each',
  'no',
  'any',
  'another',
  'many',
  'several',
  'few',
  'both',
  'all',
  'such',
  'what',
  'whose',
  'which',
  'much',
  'more',
  'most',
  'other',
};
const _possDet = {'my', 'your', 'his', 'her', 'its', 'our', 'their'};
const _objPron = {'me', 'you', 'him', 'her', 'us', 'them', 'it'};
const _preps = {
  'in',
  'on',
  'at',
  'of',
  'for',
  'about',
  'without',
  'before',
  'after',
  'by',
  'from',
  'with',
  'into',
  'onto',
  'through',
  'like',
  'besides',
  'despite',
  'upon',
  'against',
  'towards',
  'toward',
  'over',
  'under',
  'during',
  'off',
  'up',
  'down',
  'out',
  'around',
  'among',
  'between',
  'behind',
  'beyond',
  'near',
  'across',
  'along',
  'past',
  'within',
  'than',
  'as',
  'to',
  'since',
  'until',
  'till',
};

/// Words that open a new clause; a subject may follow them.
const _openers = {
  'and',
  'but',
  'or',
  'so',
  'because',
  'when',
  'while',
  'after',
  'before',
  'if',
  'unless',
  'as',
  'since',
  'until',
  'till',
  'though',
  'although',
  'that',
  'then',
  'where',
  'whereas',
  'once',
  'whether',
  'nor',
  'yet',
  'why',
  'how',
  'what',
  'whenever',
  'wherever',
  'whatever',
  'whoever',
  'than',
};

/// Function words that are never the main verb of a clause.
const _notVerb = {
  'the',
  'a',
  'an',
  'and',
  'or',
  'but',
  'of',
  'to',
  'in',
  'on',
  'at',
  'for',
  'with',
  'by',
  'it',
  'this',
  'that',
  'he',
  'she',
  'they',
  'we',
  'you',
  'i',
  'his',
  'her',
  'their',
  'as',
  'from',
  'not',
  'so',
  'if',
  'than',
  'then',
  'there',
  'my',
  'your',
  'its',
  'our',
  'me',
  'him',
  'them',
  'one',
  'some',
  'any',
  'all',
  'what',
  'which',
  'who',
  'when',
  'where',
  'how',
  'into',
  'out',
  'up',
  'down',
  'off',
  'very',
  'too',
  'also',
  'just',
  'only',
  'here',
  'now',
  'yes',
  'no',
  'well',
  'still',
  'even',
  'ever',
  'never',
  'again',
  'once',
  'more',
  'most',
  'less',
  'much',
  'many',
  'such',
  'own',
  'same',
  'other',
  'each',
  'every',
  'both',
  'few',
  'about',
  'over',
  'after',
  'before',
  'back',
  'away',
  'round',
  'around',
  'through',
  'because',
  'while',
  'though',
  'although',
  'until',
  'since',
  'whether',
  'either',
  'neither',
  'nor',
  'yet',
  'us',
  'himself',
  'herself',
  'itself',
  'themselves',
  'myself',
  'yourself',
  'ourselves',
  'nothing',
  'something',
  'everything',
  'anything',
  'someone',
  'everyone',
  'anyone',
  'nobody',
  'somebody',
  'everybody',
  'anybody',
  'thing',
  'things',
  'whose',
  'whom',
  'mr',
  'mrs',
  'ms',
  'sir',
  'dr',
  'oh',
  'ah',
  'o',
  'cannot',
  'last',
  'next',
  'first',
  'second',
  'little',
  'enough',
  'whatever',
  'together',
  'perhaps',
  'alone',
  'quite',
  'rather',
  'always',
  'already',
  'soon',
  'often',
  'please',
  'today',
  'tonight',
  'tomorrow',
  'yesterday',
  'twice',
  'thus',
  'hence',
  'indeed',
  'instead',
  'unless',
  'upon',
  'within',
  'without',
  'among',
  'beside',
  'besides',
  'during',
  'against',
  'towards',
  'toward',
  'per',
  'via',
  'two',
  'three',
  'four',
  'five',
  'six',
  'seven',
  'eight',
  'nine',
  'ten',
  'hundred',
  'thousand',
  'million',
  'news',
  'these',
  'those',
  'let',
  "let's",
  'lets',
};

/// -ing words used as adjectives after "be" ("it is interesting").
const _ingAdj = {
  'interesting',
  'boring',
  'exciting',
  'amazing',
  'surprising',
  'tiring',
  'annoying',
  'confusing',
  'disappointing',
  'embarrassing',
  'frightening',
  'shocking',
  'terrifying',
  'worrying',
  'charming',
  'satisfying',
  'relaxing',
  'depressing',
  'fascinating',
  'astonishing',
  'encouraging',
  'convincing',
  'promising',
  'outstanding',
  'willing',
  'loving',
  'caring',
  'amusing',
  'alarming',
  'appalling',
  'thrilling',
  'pleasing',
  'striking',
  'touching',
  'disturbing',
  'exhausting',
  'challenging',
  'demanding',
  'rewarding',
  'puzzling',
  'refreshing',
  'overwhelming',
  'humiliating',
  'irritating',
  'entertaining',
  'inspiring',
  'misleading',
  'threatening',
  'welcoming',
  'cunning',
  'daring',
  'dashing',
  'enchanting',
  'stunning',
  'dazzling',
  'glittering',
  'shining',
  'sparkling',
  'missing',
  'understanding',
  'forgiving',
  'grasping',
  'pleasant',
};

/// -ed / V3 words used as adjectives after "be" ("she was tired").

/// -ing words that are prepositions or nouns, not participles.
const _ingNotParticiple = {
  'according', 'including', 'regarding', 'concerning', 'considering', 'during', 'notwithstanding', 'excepting', 'following', 'pending', //
  'nothing', 'something', 'anything', 'everything', 'morning', 'evening', 'king', 'thing', 'ring', 'wing', 'string', 'spring', 'ceiling',
  'darling', 'pudding', 'shilling', 'farthing', 'sterling', 'lightning', 'stocking', 'wedding', 'clothing', 'ending', 'beginning', 'building',
  'meeting', 'feeling', 'painting', 'drawing', 'reading', 'writing', 'living', 'opening', 'setting', 'surroundings', 'savings', 'gathering',
  'good-morning', 'good-evening', 'supposing', 'providing', 'seeing', 'granting', 'saying',
};

/// Nouns of time: "spent the day reading" is spend + time + V-ing, not a reduced relative.
const _spendNouns = {
  'day',
  'days',
  'time',
  'times',
  'hour',
  'hours',
  'minute',
  'minutes',
  'morning',
  'evening',
  'night',
  'nights',
  'afternoon',
  'week',
  'weeks',
  'month',
  'months',
  'year',
  'years',
  'while',
  'moment',
  'trouble',
  'difficulty',
  'fun',
  'problem',
  'problems',
  'way',
  'life',
  'rest',
  'lot',
  'deal',
};

/// Verbs like "be" before a feeling adjective: "feel bored", "looks interesting".
const _linkVerbs = {'feel', 'seem', 'look', 'get', 'become', 'sound', 'remain', 'grow', 'appear'};

/// -ed / -ing feeling adjectives and their pair.
const _feelingPairs = <String, String>{
  'bored': 'boring',
  'boring': 'bored',
  'interested': 'interesting',
  'interesting': 'interested',
  'excited': 'exciting',
  'exciting': 'excited',
  'tired': 'tiring',
  'tiring': 'tired',
  'surprised': 'surprising',
  'surprising': 'surprised',
  'amazed': 'amazing',
  'amazing': 'amazed',
  'confused': 'confusing',
  'confusing': 'confused',
  'embarrassed': 'embarrassing',
  'embarrassing': 'embarrassed',
  'frightened': 'frightening',
  'frightening': 'frightened',
  'worried': 'worrying',
  'worrying': 'worried',
  'disappointed': 'disappointing',
  'disappointing': 'disappointed',
  'exhausted': 'exhausting',
  'exhausting': 'exhausted',
  'annoyed': 'annoying',
  'annoying': 'annoyed',
  'shocked': 'shocking',
  'shocking': 'shocked',
  'satisfied': 'satisfying',
  'satisfying': 'satisfied',
  'terrified': 'terrifying',
  'terrifying': 'terrified',
  'fascinated': 'fascinating',
  'fascinating': 'fascinated',
  'relaxed': 'relaxing',
  'relaxing': 'relaxed',
  'depressed': 'depressing',
  'depressing': 'depressed',
  'amused': 'amusing',
  'amusing': 'amused',
  'thrilled': 'thrilling',
  'thrilling': 'thrilled',
  'astonished': 'astonishing',
  'astonishing': 'astonished',
  'disgusted': 'disgusting',
  'disgusting': 'disgusted',
  'irritated': 'irritating',
  'irritating': 'irritated',
  'puzzled': 'puzzling',
  'puzzling': 'puzzled',
  'charmed': 'charming',
  'charming': 'charmed',
  'alarmed': 'alarming',
  'alarming': 'alarmed',
  'inspired': 'inspiring',
  'inspiring': 'inspired',
  'touched': 'touching',
  'touching': 'touched',
  'overwhelmed': 'overwhelming',
  'overwhelming': 'overwhelmed',
  'frustrated': 'frustrating',
  'frustrating': 'frustrated',
  'scared': 'scary',
  'pleased': 'pleasing',
};

/// Old English "is come", "was become": be + a verb that takes no object is no passive.
const _intransPP = {'come', 'become', 'gone', 'arrived', 'fallen', 'risen', 'departed'};
bool _noPassive(String x) => _edAdj.contains(x) || _intransPP.contains(x);

const _edAdj = {
  'grown',
  'indisposed',
  'tired',
  'bored',
  'interested',
  'excited',
  'worried',
  'surprised',
  'scared',
  'frightened',
  'pleased',
  'satisfied',
  'married',
  'ashamed',
  'amazed',
  'annoyed',
  'confused',
  'disappointed',
  'embarrassed',
  'exhausted',
  'shocked',
  'terrified',
  'relaxed',
  'delighted',
  'determined',
  'used',
  'supposed',
  'concerned',
  'involved',
  'astonished',
  'puzzled',
  'upset',
  'alarmed',
  'amused',
  'depressed',
  'disgusted',
  'fascinated',
  'horrified',
  'impressed',
  'irritated',
  'offended',
  'overjoyed',
  'relieved',
  'stunned',
  'thrilled',
  'troubled',
  'tempted',
  'lost',
  'gone',
  'done',
  'finished',
  'dressed',
  'prepared',
  'convinced',
  'engaged',
  'related',
  'known',
  'aged',
  'beloved',
  'blessed',
  'cursed',
  'crowded',
  'experienced',
  'skilled',
  'talented',
  'learned',
  'naked',
  'wicked',
  'sacred',
  'ragged',
  'rugged',
  'crooked',
  'jagged',
  'wretched',
  'dogged',
  'kindred',
  'hundred',
  'contented',
  'content',
  'drunk',
  'hidden',
  'afraid',
  'tied',
  'stuck',
  'gifted',
  'armed',
  'dead',
  'mixed',
  'ruined',
  'scattered',
  'silent',
  'bewildered',
  'enchanted',
  'charmed',
  'startled',
  'dismayed',
  'grieved',
  'saddened',
  'overcome',
  'inclined',
  'obliged',
  'bound',
  'entitled',
  'acquainted',
  'accustomed',
  'qualified',
  'situated',
  'located',
};

/// Verbs + V-ing.
const _gerundVerbs = {
  'enjoy',
  'avoid',
  'finish',
  'mind',
  'suggest',
  'consider',
  'keep',
  'practise',
  'practice',
  'miss',
  'deny',
  'admit',
  'imagine',
  'risk',
  'delay',
  'postpone',
  'quit',
  'recommend',
  'appreciate',
  'dislike',
  'resist',
  'involve',
  'mention',
  'tolerate',
  'fancy',
  'discuss',
  'detest',
  'resent',
  'justify',
  'escape',
  'excuse',
  'forgive',
  'anticipate',
  'contemplate',
  'envisage',
};

/// Verbs + to V1.
const _infVerbs = {
  'want',
  'need',
  'decide',
  'hope',
  'plan',
  'promise',
  'agree',
  'refuse',
  'offer',
  'expect',
  'learn',
  'manage',
  'fail',
  'seem',
  'appear',
  'afford',
  'choose',
  'pretend',
  'attempt',
  'intend',
  'threaten',
  'arrange',
  'prepare',
  'deserve',
  'wish',
  'tend',
  'happen',
  'claim',
  'wait',
  'struggle',
  'hesitate',
  'aim',
  'demand',
  'dare',
  'volunteer',
  'seek',
  'long',
  'vow',
  'swear',
  'resolve',
  'strive',
  'endeavour',
  'endeavor',
  'determine',
  'neglect',
};

/// Verbs that take both; the meaning changes for some.
const _bothVerbs = {'like', 'love', 'hate', 'prefer', 'begin', 'start', 'continue', 'try', 'remember', 'forget', 'stop', 'regret', 'bear', 'cease'};

const _bothNotes = <String, Tx>{
  'stop': (
    'stop + V-ing: o işi bırakmak (stopped smoking = sigarayı bıraktı). stop + to V1: bir şey yapmak için durmak (stopped to smoke = sigara içmek için durdu).',
    'stop + V-ing: give the activity up (stopped smoking). stop + to V1: stop in order to do it (stopped to smoke).',
  ),
  'remember': (
    'remember + V-ing: yapmış olduğunu hatırlamak (geçmiş). remember + to V1: yapmayı unutmamak (yapılacak iş).',
    'remember + V-ing: recall doing it (the past). remember + to V1: not forget to do it (a task).',
  ),
  'forget': (
    'forget + V-ing: yaptığını unutmak (geçmiş). forget + to V1: yapmayı unutmak (yapılmadı).',
    'forget + V-ing: forget that you did it (the past). forget + to V1: forget to do it (it was not done).',
  ),
  'try': ('try + V-ing: deneme olarak yapmak, işe yarar mı diye bakmak. try + to V1: yapmaya çalışmak, uğraşmak.', 'try + V-ing: do it as an experiment. try + to V1: make an effort to do it.'),
  'regret': ('regret + V-ing: yaptığına pişman olmak. regret + to V1: (kötü haber verirken) üzülerek söylemek.', 'regret + V-ing: be sorry you did it. regret + to V1: be sorry to say (bad news).'),
};

/// Verbs + object + to V1 ("asked him to wait").
const _objInfVerbs = {
  'want',
  'ask',
  'tell',
  'expect',
  'allow',
  'encourage',
  'advise',
  'persuade',
  'force',
  'invite',
  'remind',
  'teach',
  'warn',
  'order',
  'beg',
  'urge',
  'permit',
  'command',
  'forbid',
  'require',
  'enable',
  'cause',
  'get',
  'need',
  'would',
  'like',
  'help',
  'oblige',
  'instruct',
};

/// Reporting verbs.
const _reportVerbs = {
  'say',
  'tell',
  'ask',
  'explain',
  'reply',
  'answer',
  'claim',
  'admit',
  'deny',
  'promise',
  'warn',
  'mention',
  'report',
  'announce',
  'complain',
  'insist',
  'whisper',
  'add',
  'inform',
  'assure',
  'remind',
  'confess',
  'argue',
  'state',
  'declare',
  'swear',
  'boast',
  'exclaim',
  'murmur',
  'mutter',
  'shout',
  'cry',
  'protest',
  'suggest',
  'respond',
  'confirm',
  'repeat',
  'inquire',
  'enquire',
  'wonder',
  'demand',
  'beg',
  'order',
  'command',
  'advise',
  'urge',
  'agree',
};

/// Verbs that may take an object before the reported clause ("told him that").
const _reportObj = {'tell', 'ask', 'inform', 'assure', 'remind', 'warn', 'promise', 'advise', 'beg', 'order', 'command', 'urge'};

/// Verbs before "if" that make it an embedded question, not a condition.
const _askIf = {
  'ask',
  'wonder',
  'know',
  'see',
  'check',
  'doubt',
  'decide',
  'tell',
  'find',
  'learn',
  'discover',
  'sure',
  'matter',
  'care',
  'say',
  'guess',
  'determine',
  'inquire',
  'enquire',
  'question',
  'remember',
  'forget',
  'notice',
  'understand',
  'test',
  'try',
};

/// Nouns before "that" that take a "that" clause of their own ("the fact that …").
const _thatNouns = {
  'fact',
  'idea',
  'news',
  'belief',
  'hope',
  'feeling',
  'sense',
  'possibility',
  'chance',
  'evidence',
  'proof',
  'rumour',
  'rumor',
  'thought',
  'claim',
  'notion',
  'impression',
  'assumption',
  'suggestion',
  'conclusion',
  'report',
  'doubt',
  'sign',
  'knowledge',
  'truth',
  'word',
  'message',
  'promise',
  'statement',
  'fear',
  'certainty',
  'danger',
  'risk',
  'warning',
  'opinion',
  'view',
  'theory',
  'argument',
  'decision',
  'realization',
  'realisation',
  'condition',
  'principle',
  'point',
  'reason',
  'way',
  'now',
  'so',
  'such',
  'order',
};
const _placeNouns = {
  'place',
  'house',
  'town',
  'city',
  'room',
  'country',
  'village',
  'street',
  'spot',
  'area',
  'home',
  'palace',
  'garden',
  'cave',
  'land',
  'world',
  'island',
  'shop',
  'school',
  'hotel',
  'restaurant',
  'office',
  'building',
  'kingdom',
  'forest',
  'road',
  'part',
  'point',
  'hall',
  'market',
  'square',
  'corner',
  'castle',
  'region',
  'valley',
  'river',
  'sea',
  'desert',
  'mountain',
  'field',
  'park',
  'church',
  'temple',
  'chamber',
  'courtyard',
  'hill',
  'situation',
  'case',
  'stage',
  'farm',
};
const _timeNouns = {
  'day',
  'time',
  'year',
  'moment',
  'night',
  'morning',
  'week',
  'month',
  'period',
  'age',
  'era',
  'hour',
  'evening',
  'afternoon',
  'days',
  'times',
  'years',
  'season',
  'minute',
  'occasion',
  'century',
  'summer',
  'winter',
  'spring',
  'autumn',
  'weekend',
};
const _whWords = {'what', 'where', 'when', 'why', 'how', 'who', 'which', 'whom', 'whose'};

/// Comparatives that are not "more + adjective" or "-er": irregular ones.
const _irregComp = {'better': 'good / well', 'worse': 'bad / badly', 'further': 'far', 'farther': 'far', 'less': 'little', 'more': 'much / many', 'elder': 'old'};
const _irregSup = {'best': 'good / well', 'worst': 'bad / badly', 'furthest': 'far', 'farthest': 'far', 'least': 'little', 'most': 'much / many', 'eldest': 'old'};

/// -er / -est words not to treat as comparative / superlative.
const _notComp = {
  'later',
  'latter',
  'former',
  'upper',
  'inner',
  'outer',
  'lower',
  'utter',
  'other',
  'rather',
  'never',
  'ever',
  'over',
  'under',
  'after',
  'whether',
  'either',
  'neither',
  'together',
  'however',
  'proper',
  'eager',
  'clever',
  'bitter',
  'silver',
  'tender',
  'sober',
  'slender',
  'mere',
  'sheer',
  'super',
  'latest',
  'honest',
  'modest',
  'earnest',
  'interest',
  'forest',
  'harvest',
};

/// Prepositions that take a gerund after them.
const _gerundPreps = {'in', 'on', 'at', 'of', 'for', 'about', 'without', 'before', 'after', 'by', 'from', 'with', 'besides', 'despite', 'upon', 'against', 'instead', 'through'};

const _subordinators = {'if', 'unless', 'when', 'whenever', 'because', 'while', 'although', 'though', 'once', 'until', 'whereas'};

/// Past forms of reporting verbs, verbs wherever they stand.
const _saidForms = {'said', 'told', 'asked', 'replied', 'answered', 'explained', 'whispered', 'shouted', 'cried', 'added', 'promised', 'admitted', 'insisted', 'warned', 'announced', 'complained'};

/// -ing words that are nouns ("in the morning", "of the building").
const _ingNouns = {
  'morning',
  'evening',
  'building',
  'ceiling',
  'wedding',
  'meeting',
  'painting',
  'feeling',
  'beginning',
  'ending',
  'clothing',
  'setting',
  'sibling',
  'darling',
  'pudding',
  'stocking',
  'lightning',
  'dwelling',
  'earring',
  'offspring',
  'awning',
  'railing',
  'landing',
  'lodging',
  'sterling',
  'herring',
  'shilling',
  'duckling',
  'seedling',
  'spring',
  'string',
  'wing',
  'ring',
  'king',
  'thing',
  'afternoon',
  'dining',
  'savings',
  'surroundings',
  'belongings',
  'feelings',
  'paintings',
  'buildings',
  'meetings',
  'beginnings',
  'warning',
  'opening',
  'crossing',
  'heading',
  'filling',
  'icing',
  'stuffing',
  'frosting',
  'housing',
  'gathering',
  'hearing',
  'training',
  'learning',
  'clearing',
  'carving',
  'drawing',
  'engraving',
  'recording',
  'ruling',
  'sitting',
  'shooting',
  'helping',
  'serving',
  'booking',
  'parking',
  'shopping',
  'swimming',
  'cooking',
  'reading',
  'writing',
  'singing',
};

const _quote = {'"', '“', '”', '«', '»', '„', "'", '‘', '’'};

/// Clause and verb analysis behind the grammar highlights.
class GrammarMarker {
  /// Base-form candidates of a word (most likely first).
  final List<String> Function(String lower) lemmas;

  /// Parts of speech of a lemma in the dictionary ('n', 'v', 'a', 'r').
  final Set<String> Function(String lemma) posOfLemma;

  /// Irregular V2 forms and V3 forms.
  final Set<String> pastForms;
  final Set<String> participles;

  GrammarMarker({required this.lemmas, required this.posOfLemma, required this.pastForms, required Set<String> participles}) : participles = {...participles, 'born'};

  // ---------------------------------------------------------- word tests

  final _verbLemmaCache = <String, String?>{};

  /// The verb this inflected word comes from ("walked" -> walk), or null.
  String? _verbOf(String w) => _verbLemmaCache.putIfAbsent(w, () {
    for (final l in lemmas(w)) {
      if (l != w && posOfLemma(l).contains('v')) return l;
    }
    return null;
  });

  bool _isVerbLemma(String w) => !_notVerb.contains(w) && posOfLemma(w).contains('v');

  /// A verb's base form: "walk", "go", "be".
  bool _isBase(String w) => _isVerbLemma(w) && !w.endsWith('ing') && !(w.endsWith('ed') && _verbOf(w) != null);

  bool _isIng(String w) {
    if (w == 'being') return true;
    if (!w.endsWith('ing') || w.length < 5 || _notVerb.contains(w)) return false;
    return _verbOf(w) != null;
  }

  bool _isPP(String w) {
    if (_notVerb.contains(w)) return false;
    if (participles.contains(w)) return true;
    return w.endsWith('ed') && w.length > 3 && _verbOf(w) != null;
  }

  bool _isPast(String w) {
    if (_notVerb.contains(w)) return false;
    if (pastForms.contains(w)) return true;
    return w.endsWith('ed') && w.length > 3 && _verbOf(w) != null;
  }

  /// Third person singular present: "walks", "goes".
  bool _isS(String w) {
    if (!w.endsWith('s') || w.length < 3 || _notVerb.contains(w) || w.endsWith("'s") || w.endsWith('ss') || w.endsWith('us')) return false;
    final v = _verbOf(w);
    return v != null && (w == '${v}s' || w == '${v}es' || (v.endsWith('y') && w == '${v.substring(0, v.length - 1)}ies'));
  }

  bool _isAdjLemma(String w) => posOfLemma(w).contains('a');

  bool _isNounish(String w) {
    if (_notVerb.contains(w) || _det.contains(w)) return false;
    for (final l in lemmas(w)) {
      if (posOfLemma(l).contains('n')) return true;
    }
    return false;
  }

  // ---------------------------------------------------------- the analysis

  /// All structures in a paragraph.
  List<GMark> mark(String text, List<Token> toks) {
    final out = <GMark>[];
    if (toks.isEmpty) return out;
    // Sentences as token ranges.
    final ranges = sentenceRanges(text);
    var ti = 0;
    for (final (_, e) in ranges) {
      final start = ti;
      while (ti < toks.length && toks[ti].start < e) {
        ti++;
      }
      if (ti > start) {
        // A rule that trips over odd text (OCR noise …) must not break the page.
        final mine = <GMark>[];
        try {
          _Sentence(this, text, toks, start, ti).run(mine);
          out.addAll(mine);
        } catch (_) {
          assert(false, 'grammar marks failed on: ${text.substring(toks[start].start, toks[ti - 1].end)}');
        }
      }
    }
    return out;
  }
}

/// One sentence being analysed.
class _Sentence {
  final GrammarMarker g;
  final String text;
  final List<Token> toks;
  final int s, e; // token range [s, e)
  late final List<String> w = [for (final t in toks) t.lower];
  final groups = <_VG>[];
  final used = <int>{};

  _Sentence(this.g, this.text, this.toks, this.s, this.e);

  String gap(int i) => i <= s ? text.substring(0, toks[i].start).split(RegExp(r'[.!?…]')).last : text.substring(toks[i - 1].end, toks[i].start);

  /// A comma, colon, dash, bracket or quote right before token i.
  bool cut(int i) => i > s && RegExp(r'''[,;:—–()\[\]"“”«»‘’']|\s-|-\s''').hasMatch(gap(i));
  bool quoteBefore(int i) => i > s && gap(i).split('').any(_quote.contains);

  bool clauseStart(int i) => i == s || cut(i) || _openers.contains(w[i - 1]);

  /// Next token index after i, skipping adverbs like "not", "never".
  int nx(int i) {
    var j = i + 1;
    while (j < e && (_skip.contains(w[j]) || w[j] == "n't") && !cut(j)) {
      j++;
    }
    return j;
  }

  /// Previous token index before i, skipping adverbs.
  int pv(int i) {
    var j = i - 1;
    while (j >= s && _skip.contains(w[j]) && !cut(j + 1)) {
      j--;
    }
    return j;
  }

  String at(int i) => i >= s && i < e ? w[i] : '';

  bool isCap(int i) {
    if (i < s || i >= e) return false;
    final t = toks[i].text;
    return t[0].toUpperCase() == t[0] && t[0].toLowerCase() != t[0];
  }

  /// A name (Aladdin, Baghdad): capitalised and not an ordinary word.
  bool isName(int i) {
    if (!isCap(i)) return false;
    if (w[i] == 'i') return false;
    if (i > s && !RegExp(r'["“‘(]\s*$').hasMatch(gap(i))) return !_notVerb.contains(w[i]) && !g._isVerbLemma(w[i]) || g.posOfLemma(w[i]).isEmpty;
    return g.lemmas(w[i]).every((l) => g.posOfLemma(l).isEmpty);
  }

  /// The auxiliary a token stands for: "isn't" -> is, "he'd" -> 'd, "it's" -> 's.
  String? aux(int i) {
    if (i < s || i >= e) return null;
    final x = w[i];
    const plain = {'am', 'is', 'are', 'was', 'were', 'have', 'has', 'had', 'do', 'does', 'did', 'will', 'shall', 'would', 'can', 'could', 'may', 'might', 'must', 'should', 'ought'};
    if (plain.contains(x)) return x;
    if (x == 'cannot') return 'can';
    if (x == "won't") return 'will';
    if (x == "shan't") return 'shall';
    if (x == "can't") return 'can';
    if (x == "ain't") return 'is';
    if (x.endsWith("n't")) {
      final b = x.substring(0, x.length - 3);
      return plain.contains(b) ? b : null;
    }
    final k = x.indexOf("'");
    if (k <= 0) return null;
    final head = x.substring(0, k), tail = x.substring(k);
    const pron = {'i', 'you', 'he', 'she', 'it', 'we', 'they', 'that', 'there', 'here', 'what', 'who', 'where', 'how', 'this', 'everyone', 'nobody', 'someone', 'everything', 'nothing', 'something'};
    if (!pron.contains(head)) return null;
    return switch (tail) {
      "'m" => 'am',
      "'re" => 'are',
      "'ve" => 'have',
      "'ll" => 'will',
      "'d" => "'d",
      "'s" => "'s",
      _ => null,
    };
  }

  /// Whether a token holds its own subject ("he's", "I'll").
  bool subjInside(int i) => w[i].contains("'") && aux(i) != null && !w[i].endsWith("n't");

  /// Is there a subject right before the verb at i?
  /// Returns 's' (third person singular), 'p' (other) or null.
  String? subjectBefore(int i) {
    if (cut(i)) return null;
    final p = pv(i);
    if (p < s) return null;
    if (p + 1 < i && cut(p + 1)) return null;
    final x = w[p];
    // A verb or a possessive right before is not a subject: "had tears", "Aladdin's hands".
    if (aux(p) != null || groups.any((v) => v.toks.contains(p)) || x.endsWith("'s") || gap(p + 1).startsWith("'")) return null;
    if (_subjOnly.contains(x)) return x == 'he' || x == 'she' ? 's' : 'p';
    if (_subjMaybe.contains(x)) {
      final starts = clauseStart(p) || (p > s && (w[p - 1] == 'who' || w[p - 1] == 'which'));
      if (x == 'who' || x == 'which') return p > s ? '?' : null; // relative: agrees with the noun before
      if (x == 'that') {
        // Relative "that" after a noun ("the park that runs"), not "making that noise".
        final y = p > s ? w[p - 1] : '';
        return p > s && !cut(p) && g._isNounish(y) && !_thatNouns.contains(y) && aux(p - 1) == null && !groups.any((v) => v.toks.contains(p - 1)) ? '?' : null;
      }
      if (!starts) return null;
      return _singularSubj.contains(x) ? 's' : 'p';
    }
    if (isName(p) && !_det.contains(x)) {
      // "Aladdin smiled", "Princess Badr smiled"; not "asked Aladdin questions".
      var k = p;
      while (k > s && isName(k - 1) && !cut(k)) {
        k--;
      }
      if (clauseStart(k) || (k > s && _det.contains(w[k - 1]) && clauseStart(k - 1))) return 's';
      // "One day Aladdin heard …", but not the object of a verb or preposition.
      final y = w[k - 1];
      final objectSlot =
          groups.any((v) => v.toks.contains(k - 1)) ||
          aux(k - 1) != null ||
          _preps.contains(y) ||
          _det.contains(y) && y != 'that' && y != 'which' ||
          y.endsWith("'s") ||
          g._isPast(y) ||
          g._isS(y) ||
          g._isVerbLemma(y) && !g.posOfLemma(y).contains('n');
      return objectSlot ? null : 's';
    }
    // A noun phrase at the start of the clause: "The old man", "Her sisters".
    if (!g._isNounish(x) || _det.contains(x) || _preps.contains(x)) return null;
    if (g._isVerbLemma(x) && !g.posOfLemma(x).contains('n') && g._verbOf(x) == null) return null;
    var k = p;
    var sawDet = false;
    while (k > s && p - k < 5) {
      if (cut(k)) break;
      final y = w[k - 1];
      if (_det.contains(y) || y.endsWith("'s")) {
        sawDet = true;
        k--;
        if (_det.contains(y)) break;
        continue;
      }
      if (_openers.contains(y) || _preps.contains(y) || aux(k - 1) != null) break;
      if (g._isAdjLemma(y) || g._isNounish(y) || isName(k - 1)) {
        k--;
        continue;
      }
      break;
    }
    // No determiner ("Black smoke came"): only at the very start of the
    // sentence, and the caller accepts it only for a clear past form.
    if (!sawDet && !isName(k)) {
      // "If water reaches 100 degrees": a bare noun after a subordinating word.
      if (k != s) return k > s && !cut(k) && _subordinators.contains(w[k - 1]) && !(x.endsWith('s') && g.lemmas(x).first != x) && p == k ? 's' : null;
      // "Aladdin smiled": a bare singular noun that cannot be an order ("Turn left").
      final plural0 = x.endsWith('s') && !x.endsWith('ss') && g.lemmas(x).first != x;
      return !plural0 && !g._isVerbLemma(w[k]) ? 's' : '0';
    }
    // "after the city gardens": after / before / since … are prepositions here as often as not.
    if (!clauseStart(k) || k > s && !cut(k) && const {'after', 'before', 'since', 'until', 'till', 'as', 'than'}.contains(w[k - 1])) return null;
    final plural = x.endsWith('s') && !x.endsWith('ss') && g.lemmas(x).first != x;
    return plural ? 'p' : 's';
  }

  void addGroup(List<int> idx, String kind, {bool passive = false, String modal = ''}) {
    if (idx.any(used.contains)) return;
    used.addAll(idx);
    groups.add(_VG(idx, kind, passive: passive, modal: modal));
  }

  // ------------------------------------------------------------ verb groups

  void findGroups() {
    for (var i = s; i < e; i++) {
      if (used.contains(i)) continue;
      final a0 = aux(i);
      if (a0 == null) continue;
      if (i > s && w[i - 1] == 'to') continue; // "to have"
      // Question order: "Have you seen …", "Did she go …", "Is he coming …".
      var j = nx(i);
      final invert =
          !subjInside(i) &&
          j < e &&
          (_subjOnly.contains(w[j]) || w[j] == 'you' || w[j] == 'it' || w[j] == 'there' || (isName(j) && j > s)) &&
          (i == s || cut(i) || _whWords.contains(w[i - 1]) || w[i - 1] == 'nor' || w[i - 1] == 'neither');
      if (invert) j = nx(j);
      final b = at(j);
      final k = j < e ? nx(j) : e;
      final c = at(k);
      final l = k < e ? nx(k) : e;
      final d = at(l);
      var a = a0;
      if (a == "'s") {
        final objAfter = c.isNotEmpty && (_det.contains(c) || _objPron.contains(c) || isName(k));
        a = g._isPP(b) && (!_edAdj.contains(b) || objAfter) || b == 'been' || b == 'got' ? 'has' : 'is';
      }
      if (a == "'d") {
        if (b == 'better' || b == 'rather') continue;
        a = g._isPP(b) || b == 'been' ? 'had' : 'would';
      }
      final head = [i];
      List<int> grp(List<int> rest) => [...head, ...rest];

      if (a == 'will' || a == 'shall') {
        if (b == 'have' && c == 'been' && g._isIng(d)) {
          addGroup(grp([j, k, l]), 'future_perfect_continuous');
        } else if (b == 'have' && g._isPP(c)) {
          addGroup(grp([j, k]), 'future_perfect');
        } else if (b == 'be' && g._isIng(c) && !_ingAdj.contains(c)) {
          addGroup(grp([j, k]), 'future_continuous');
        } else if (b == 'be' && g._isPP(c) && !_noPassive(c)) {
          addGroup(grp([j, k]), 'future_simple', passive: true);
        } else if (g._isBase(b)) {
          addGroup(grp([j]), 'future_simple');
        }
        continue;
      }
      if (const {'would', 'can', 'could', 'may', 'might', 'must', 'should', 'ought'}.contains(a)) {
        var jj = j;
        if (a == 'ought' && b == 'to') jj = nx(j);
        final bb = at(jj);
        final kk = jj < e ? nx(jj) : e;
        if (bb == 'have' && (g._isPP(at(kk)) || at(kk) == 'been')) {
          final ll = nx(kk);
          final pass = at(kk) == 'been' && g._isPP(at(ll)) && !g._isIng(at(ll)) && !_noPassive(at(ll));
          addGroup(grp([jj, kk, if (at(kk) == 'been' && (g._isIng(at(ll)) || g._isPP(at(ll)))) ll]), 'modal_perfect', modal: a, passive: pass);
        } else if (bb == 'be' && (g._isIng(at(kk)) || g._isPP(at(kk)))) {
          final pass = g._isPP(at(kk)) && !g._isIng(at(kk)) && !_noPassive(at(kk));
          addGroup(grp([jj, kk]), 'modal', modal: a, passive: pass);
        } else if (g._isBase(bb)) {
          addGroup(grp([jj]), 'modal', modal: a);
        } else {
          used.add(i);
        }
        continue;
      }
      if (const {'am', 'is', 'are'}.contains(a)) {
        if (b == 'going' && c == 'to' && g._isBase(d)) {
          addGroup(grp([j, k, l]), 'going_to');
        } else if (b == 'being' && g._isPP(c) && !_noPassive(c)) {
          addGroup(grp([j, k]), 'present_continuous', passive: true);
        } else if (g._isIng(b) && b != 'being' && !_ingAdj.contains(b)) {
          addGroup(grp([j]), 'present_continuous');
        } else if (g._isPP(b) && !_noPassive(b) && !g._isIng(b) && b != 'been') {
          addGroup(grp([j]), 'simple_present', passive: true);
        } else {
          addGroup(head, 'simple_present');
        }
        continue;
      }
      if (a == 'was' || a == 'were') {
        if (b == 'going' && c == 'to' && g._isBase(d)) {
          addGroup(grp([j, k, l]), 'was_going_to');
        } else if (b == 'being' && g._isPP(c) && !_noPassive(c)) {
          addGroup(grp([j, k]), 'past_continuous', passive: true);
        } else if (g._isIng(b) && b != 'being' && !_ingAdj.contains(b)) {
          addGroup(grp([j]), 'past_continuous');
        } else if (g._isPP(b) && !_noPassive(b) && b != 'been') {
          addGroup(grp([j]), 'simple_past', passive: true);
        } else {
          addGroup(head, 'simple_past');
        }
        continue;
      }
      if (a == 'have' || a == 'has' || a == 'had') {
        final perf = a == 'had' ? 'past_perfect' : 'present_perfect';
        if (b == 'been' && g._isIng(c) && !_ingAdj.contains(c)) {
          addGroup(grp([j, k]), '${perf}_continuous');
        } else if (b == 'been' && g._isPP(c) && !_noPassive(c)) {
          addGroup(grp([j, k]), perf, passive: true);
        } else if (g._isPP(b) || b == 'been') {
          addGroup(grp([j]), perf);
        } else if (subjInside(i) || subjectBefore(i) != null || invert) {
          // "have" as the main verb: "They have a house", "She had a dog".
          addGroup(head, a == 'had' ? 'simple_past' : 'simple_present');
        }
        continue;
      }
      if (a == 'do' || a == 'does' || a == 'did') {
        final kind = a == 'did' ? 'simple_past' : 'simple_present';
        if (g._isBase(b) && b != 'not') {
          addGroup(grp([j]), kind);
        } else if (subjectBefore(i) != null || subjInside(i)) {
          addGroup(head, kind); // "do" as the main verb, or "So did I"
        }
        continue;
      }
    }

    // "used to + V1": a past habit.
    for (var i = s; i < e - 2; i++) {
      if (w[i] == 'used' &&
          w[i + 1] == 'to' &&
          !used.contains(i) &&
          g._isBase(w[i + 2]) &&
          !(pv(i) >= s && (aux(pv(i)) != null || const {'get', 'got', 'getting', 'be', 'been', 'being'}.contains(w[pv(i)])))) {
        addGroup([i, i + 1, i + 2], 'used_to');
      }
    }

    // Main verbs with no auxiliary: "She walked", "They live", "He knows".
    for (var i = s; i < e; i++) {
      if (used.contains(i) || aux(i) != null) continue;
      final x = w[i];
      if (_notVerb.contains(x) || x.length < 2) continue;
      if (isName(i) || isCap(i) && i > s && !RegExp(r'["“‘(]\s*$').hasMatch(gap(i))) continue; // "Jack", "Oxford"
      if (i > s && !cut(i)) {
        final y = w[i - 1];
        if (y == 'to' || (_det.contains(y) && !const {'that', 'which', 'what', 'whose', 'all', 'both', 'each'}.contains(y)) || y.endsWith("'s") || _preps.contains(y)) continue;
      }
      // "Having finished her work, …": a participle, not a tense.
      final pp0 = pv(i);
      if (pp0 >= s && const {'having', 'being', 'been', 'be', 'have', 'has', 'had', 'get', 'got'}.contains(w[pp0]) && aux(pp0) == null) continue;
      final past = g._isPast(x);
      final pres3 = g._isS(x);
      final base = g._isBase(x) && !past;
      if (!past && !pres3 && !base) continue;
      var sub = subjectBefore(i);
      if (sub == '0') sub = g.pastForms.contains(x) && !g.participles.contains(x) ? 'p' : null;
      String? kind;
      if (sub != null) {
        if (past && (!g.participles.contains(x) || g.pastForms.contains(x) || x.endsWith('ed'))) {
          kind = 'simple_past';
        } else if (pres3 && (sub == 's' || sub == '?')) {
          kind = 'simple_present';
        } else if (base && (sub == 'p' || sub == '?' && !g._isNounish(x)) && (!g.participles.contains(x) || g.lemmas(x).contains(x))) {
          kind = 'simple_present';
        }
      } else {
        // "… and walked away": joined to a verb of the same tense.
        final p = pv(i);
        // Not "a small and tilted hat": the word before "and" is no adjective.
        final adjBefore = p > s && g.posOfLemma(w[p - 1]).contains('a') && !g.posOfLemma(w[p - 1]).contains('v') && !g.posOfLemma(w[p - 1]).contains('r');
        if (p >= s && const {'and', 'but', 'or', 'then'}.contains(w[p]) && !cut(i) && !adjBefore) {
          final prev = groups.where((v) => v.last < p && v.isTense && !v.passive).lastOrNull;
          if (prev != null && prev.kind == 'simple_past' && past && g.lemmas(x).first != x) {
            kind = 'simple_past';
          } else if (prev != null && prev.kind == 'simple_present' && pres3 && !g._isNounish(x)) {
            kind = 'simple_present';
          } else if (prev != null && prev.kind == 'simple_present' && base && w[p] == 'and' && p == i - 1 && !g._isS(w[prev.last]) && aux(prev.last) == null && boundaryAfter(prev.last) > i) {
            kind = 'simple_present'; // "I enjoy reading and want to learn"
          }
        }
        // Reporting verbs are verbs even after a long subject: "The man who lives here said that …".
        if (kind == null && _saidForms.contains(x) && at(i + 1) != 'by' && !(i > s && aux(i - 1) != null)) {
          kind = 'simple_past';
        }
      }
      if (kind == null) continue;
      // A noun right after a determiner-less noun ("the city walls") is not a verb:
      // the word after must not itself be a verb that agrees.
      final n1 = at(i + 1);
      final pw = i > s ? w[i - 1] : '';
      final afterNoun = i > s && !cut(i) && g._isNounish(pw) && !_subjOnly.contains(pw) && !_subjMaybe.contains(pw) && aux(i - 1) == null;
      if (afterNoun && n1.isNotEmpty && !cut(i + 1) && g._isNounish(x) && (g._isS(n1) || g._isPast(n1)) && aux(i + 1) == null) continue;
      addGroup([i], kind);
    }
    groups.sort((a, b) => a.first.compareTo(b.first));
  }

  // ------------------------------------------------------------ output

  void run(List<GMark> out) {
    findGroups();
    _tenseMarks(out);
    _conditionals(out);
    _relatives(out);
    _gerundInf(out);
    _comparison(out);
    _reported(out);
    _passive(out);
    _pastModals(out);
    _usedTo(out);
    _causative(out);
    _emphasis(out);
    _tags(out);
    _participles(out);
  }

  String words(List<int> idx) => idx.map((i) => toks[i].text).join(' ');

  void _tenseMarks(List<GMark> out) {
    for (final v in groups) {
      if (!v.isTense) continue;
      final t = _tenses[v.kind]!;
      final ex = v.passive ? ('${t.exTr}${_passiveTx.$1}', '${t.exEn}${_passiveTx.$2}') : (t.exTr, t.exEn);
      out.add(GMark('g_tenses', v.kind, v.toks, [t.lesson, if (v.passive) 'passive'], v.passive ? '${t.en} (Passive)' : t.en, v.passive ? '${t.tr}, edilgen' : t.tr, ex, tone: t.tone));
    }
  }

  // ---------------------------------------------------------- conditionals

  int boundaryAfter(int i) {
    var j = i + 1;
    while (j < e && !cut(j)) {
      j++;
    }
    return j;
  }

  int boundaryBefore(int i) {
    var j = i;
    while (j > s && !cut(j)) {
      j--;
    }
    return j;
  }

  List<_VG> groupsIn(int a, int b) => [
    for (final v in groups)
      if (v.first >= a && v.first < b) v,
  ];

  void _conditionals(List<GMark> out) {
    for (var i = s; i < e; i++) {
      final x = w[i];
      final inverted = i == s && (x == 'had' || x == 'were' || x == 'should') && i + 2 < e && (_subjOnly.contains(w[i + 1]) || w[i + 1] == 'you' || w[i + 1] == 'it' || isName(i + 1));
      // "provided (that)", "as long as", "on condition that": other words for "if".
      final conn = inverted || x == 'if' || x == 'unless' ? <int>[i] : _condConnector(i);
      if (conn == null) continue;
      final cw = words(conn).toLowerCase();
      if (x == 'if' || x == 'unless') {
        if (i > s && (w[i - 1] == 'as' || w[i - 1] == 'what')) continue;
        if (at(i + 1) == 'only' || at(i + 1) == 'so' || at(i + 1) == 'not' || at(i + 1) == 'any' || at(i + 1) == 'ever' && at(i + 2) == 'there') continue;
        // "I asked if …", "I don't know if …": an embedded question.
        var q = false;
        for (var k = i - 1; k >= s && k >= i - 3; k--) {
          if (g.lemmas(w[k]).any(_askIf.contains) || w[k] == 'whether') q = true;
          if (cut(k + 1)) break;
        }
        if (q) continue;
      }
      // Split into the if-clause and the main clause.
      int ifA = i, ifB, mainA, mainB;
      if (clauseStart(i) && (i == s || cut(i) || w[i - 1] == 'and' || w[i - 1] == 'but' || w[i - 1] == 'even')) {
        ifB = boundaryAfter(i);
        if (ifB >= e && i > s) {
          // "…, if you like." – the main clause comes first.
          mainA = boundaryBefore(i - 1 < s ? s : i - 1);
          mainB = i;
          if (mainA >= mainB) continue;
        } else {
          mainA = ifB;
          if (mainA < e && w[mainA] == 'then') mainA++;
          mainB = boundaryAfter(mainA);
          if (mainB < e && mainB - mainA < 2) mainB = boundaryAfter(mainB);
          if (i > s && i == boundaryBefore(i) && i - 1 >= s) {
            // ", if …," in the middle: main clause around it.
          }
        }
      } else {
        mainA = boundaryBefore(i);
        mainB = i;
        if (mainA < s) mainA = s;
        ifB = boundaryAfter(i);
      }
      final ifG = groupsIn(ifA, ifB).where((v) => !(inverted && v.first == i && v.toks.length == 1 && x == 'should')).toList();
      final mainG = groupsIn(mainA, mainB);
      if (ifG.isEmpty && !inverted) continue;
      final ifV = ifG.isEmpty ? null : ifG.first;
      // An order as the main clause: "Call me if you need anything."
      final imperative = mainA < e && g._isBase(w[mainA]) && !groups.any((v) => v.toks.contains(mainA)) && (mainA == s || cut(mainA));
      if (mainG.isEmpty && !imperative) continue;
      final m = mainG.isEmpty || imperative && mainG.first.first > mainA ? _VG([mainA], 'imperative') : mainG.first;
      String? type;
      final ik = ifV?.kind ?? '';
      final pastPerf = ik == 'past_perfect' || ik == 'past_perfect_continuous' || (inverted && x == 'had');
      final past = ik == 'simple_past' || ik == 'past_continuous' || (ifV?.kind == 'modal' && ifV?.modal == 'could') || (inverted && x == 'were');
      final present = ik == 'simple_present' || ik == 'present_continuous' || ik == 'present_perfect' || ik == 'present_perfect_continuous' || (inverted && x == 'should');
      final wouldLike = {'would', 'could', 'might', "'d"};
      final mWould = m.kind == 'modal' && wouldLike.contains(m.modal);
      final mWouldHave = m.kind == 'modal_perfect' && wouldLike.contains(m.modal);
      final mFuture =
          m.kind == 'future_simple' ||
          m.kind == 'going_to' ||
          m.kind == 'future_continuous' ||
          m.kind == 'future_perfect' ||
          (m.kind == 'modal' && const {'can', 'may', 'must', 'should', 'might'}.contains(m.modal));
      if (pastPerf && mWouldHave) {
        type = 'cond_3';
      } else if (pastPerf && mWould) {
        type = 'cond_mixed_32';
      } else if (past && mWouldHave) {
        type = 'cond_mixed_23';
      } else if (past && mWould) {
        type = 'cond_2';
      } else if (present && (mFuture || m.kind == 'imperative')) {
        type = 'cond_1';
      } else if (present && m.kind == 'simple_present' && x != 'unless') {
        type = 'cond_0';
      } else if (present && m.kind == 'simple_present') {
        type = 'cond_0';
      }
      if (type == null) continue;
      final info = _condInfo[type]!;
      final idx = <int>{...conn, ...?ifV?.toks, ...m.toks}.toList()..sort();
      final other = conn.length > 1 || x == 'provided' || x == 'providing';
      final ifText = words([for (var k = ifA; k < ifB && k < ifA + 8; k++) k]);
      final mainText = words([for (var k = mainA; k < mainB && k < mainA + 8; k++) k]);
      final lessons = [info.lesson, if (x == 'unless') 'unless', if (inverted) 'inverted_conditionals'];
      out.add(
        GMark(
          'g_conditionals',
          type,
          idx,
          lessons,
          inverted ? '${info.en} (inverted)' : info.en,
          inverted ? '${info.tr}, devrik' : info.tr,
          (
            info.exTr +
                (x == 'unless' ? ' Unless = if … not (-medikçe, -mezse).' : '') +
                (inverted ? ' "If" düşmüş, yardımcı fiil başa gelmiş (devrik koşul).' : '') +
                (other ? ' Burada "if" yerine "$cw" kullanılmış: "-mek şartıyla, -diği sürece" anlamında, koşulu daha vurgulu söyler.' : ''),
            info.exEn +
                (x == 'unless' ? ' Unless = if … not.' : '') +
                (inverted ? ' "If" is dropped and the auxiliary comes first (inversion).' : '') +
                (other ? ' Here "$cw" is used instead of "if": "only if", stressing the condition.' : ''),
          ),
          note: (
            'Koşul: "$ifText${ifB - ifA > 8 ? ' …' : ''}" · Sonuç: "$mainText${mainB - mainA > 8 ? ' …' : ''}"',
            'Condition: "$ifText${ifB - ifA > 8 ? ' …' : ''}" · Result: "$mainText${mainB - mainA > 8 ? ' …' : ''}"',
          ),
        ),
      );
    }
  }

  /// Token indices of a condition word other than "if" starting at [i], or null.
  List<int>? _condConnector(int i) {
    final x = w[i];
    final startOk = clauseStart(i) || i == s;
    if ((x == 'provided' || x == 'providing') && startOk && i + 1 < e) {
      final j = at(i + 1) == 'that' ? i + 2 : i + 1;
      if (j < e && (_subjOnly.contains(w[j]) || w[j] == 'you' || w[j] == 'it' || _det.contains(w[j]) || isName(j) || subjInside(j)) && groups.any((v) => v.first > j - 1 && v.first <= j + 4)) {
        return [i, if (j == i + 2) i + 1];
      }
    }
    if ((x == 'as' || x == 'so') && at(i + 1) == 'long' && at(i + 2) == 'as' && i + 3 < e && !(i > s && (aux(i - 1) != null || w[i - 1] == 'for'))) {
      final j = i + 3;
      // "as long as you promise" (a condition), not "as long as the river" (a length).
      if ((_subjOnly.contains(w[j]) || w[j] == 'you' || w[j] == 'it' || isName(j) || subjInside(j)) && groups.any((v) => v.first >= j && v.first <= j + 3)) return [i, i + 1, i + 2];
    }
    if (x == 'on' && at(i + 1) == 'condition' && at(i + 2) == 'that') return [i, i + 1, i + 2];
    return null;
  }

  // ------------------------------------------------------------ passive

  void _passive(List<GMark> out) {
    for (final v in groups) {
      if (!v.passive) continue;
      final String en, tr;
      final Tx ex;
      if (v.isTense) {
        final t = _tenses[v.kind]!;
        en = '${t.en} Passive';
        tr = '${t.tr}, edilgen';
        ex = (t.exTr.split(':').first, t.exEn.split(':').first);
      } else {
        en = 'Modal Passive';
        tr = 'Kipli edilgen';
        ex = ('${v.modal} be / have been + V3', '${v.modal} be / have been + V3');
      }
      // The doer, when the sentence names it: "by the police".
      int? by;
      for (var k = v.last + 1; k < e && k <= v.last + 5; k++) {
        if (cut(k)) break;
        if (w[k] == 'by' && k + 1 < e && !g._isIng(w[k + 1])) {
          by = k;
          break;
        }
      }
      final byText = by == null ? null : words([for (var k = by; k < e && k <= by + 3 && (k == by || !cut(k)); k++) k]);
      out.add(
        GMark(
          'g_passive',
          'passive',
          v.toks,
          ['passive', if (v.isTense) _tenses[v.kind]!.lesson],
          'Passive Voice · $en',
          'Edilgen çatı · $tr',
          (
            'Edilgen: özne işi yapan değil, işten etkilenendir (be + V3). Önemli olan iş ve sonucudur; yapan kişi gerekirse "by" ile söylenir. Bu cümlede zaman: ${ex.$1}.',
            'Passive: the subject does not do the action but receives it (be + V3). What matters is the action; the doer, if needed, comes with "by". Here: ${ex.$2}.',
          ),
          note: byText == null
              ? ('Yapan kişi söylenmemiş: kim yaptığı bilinmiyor ya da önemli değil.', 'The doer is not mentioned: unknown or not important.')
              : ('İşi yapan: "$byText".', 'The doer: "$byText".'),
          tone: v.isTense ? _tenses[v.kind]!.tone : 0,
        ),
      );
    }
  }

  // ------------------------------------------------------------ past modals

  void _pastModals(List<GMark> out) {
    for (final v in groups) {
      if (v.kind != 'modal_perfect') continue;
      final neg = v.toks.any((k) => toks[k].lower.endsWith("n't") || toks[k].lower == 'cannot') || (v.first + 1 < e && w[v.first + 1] == 'not');
      final key = '${v.modal}${neg ? '_not' : ''}';
      final info = _pastModalInfo[key] ?? _pastModalInfo[v.modal];
      if (info == null) continue;
      final idx = [...v.toks, if (v.first + 1 < e && w[v.first + 1] == 'not' && !v.toks.contains(v.first + 1)) v.first + 1]..sort();
      out.add(GMark('g_past_modals', 'past_modal', idx, const ['past_modals', 'deduction'], '${words([v.first])} have + V3', info.$1, (info.$2, info.$3)));
    }
  }

  // ------------------------------------------------------- used to / be used to

  void _usedTo(List<GMark> out) {
    for (final v in groups) {
      if (v.kind == 'used_to') {
        out.add(
          GMark(
            'g_used_to',
            'used_to',
            v.toks,
            const ['used_to'],
            'used to + V1',
            'Geçmiş alışkanlık (-erdi)',
            (
              'used to + V1: eskiden düzenli yapılan ama artık yapılmayan şey (I used to swim = eskiden yüzerdim). "be used to + V-ing" ile karıştırma: o "alışkın olmak" demektir.',
              'used to + V1: something done regularly in the past but not now (I used to swim). Do not mix it up with "be used to + V-ing", which means "be accustomed to".',
            ),
          ),
        );
      }
    }
    for (var i = s + 1; i < e - 2; i++) {
      if (w[i] != 'used' || w[i + 1] != 'to') continue;
      final p = pv(i);
      if (p < s) continue;
      final be = aux(p) != null && const {'am', 'is', 'are', 'was', 'were', "'s"}.contains(aux(p)) || const {'be', 'been', 'being'}.contains(w[p]);
      final get = g.lemmas(w[p]).contains('get') || g.lemmas(w[p]).contains('become');
      if (!be && !get) continue;
      final n = w[i + 2];
      final head = [p, i, i + 1];
      if (g._isIng(n) && n != 'being') {
        out.add(
          GMark('g_used_to', 'be_used_to', [...head, i + 2], const ['used_to', 'gerund_infinitive'], '${get ? 'get' : 'be'} used to + V-ing', get ? 'Alışmak' : 'Alışkın olmak', (
            '${get ? 'get' : 'be'} used to + V-ing / isim: ${get ? 'bir şeye alışmak (zamanla)' : 'bir şeye alışkın olmak'}. Buradaki "to" edat olduğu için fiil -ing alır. "used to + V1" (eskiden yapardı) ile karıştırma.',
            '${get ? 'get' : 'be'} used to + V-ing / noun: ${get ? 'become accustomed to something' : 'be accustomed to something'}. This "to" is a preposition, so the verb takes -ing. Not the same as "used to + V1" (a past habit).',
          )),
        );
      } else if ((_det.contains(n) || _objPron.contains(n) || isName(i + 2) || g._isNounish(n) && !g._isBase(n)) && !cut(i + 2)) {
        out.add(
          GMark(
            'g_used_to',
            'be_used_to',
            head,
            const ['used_to'],
            '${get ? 'get' : 'be'} used to + noun',
            get ? 'Alışmak' : 'Alışkın olmak',
            (
              '${get ? 'get' : 'be'} used to + isim / V-ing: ${get ? 'bir şeye alışmak' : 'bir şeye alışkın olmak'} (I am used to the cold = soğuğa alışkınım). "used to + V1" (eskiden yapardı) ile karıştırma.',
              '${get ? 'get' : 'be'} used to + noun / V-ing: ${get ? 'become accustomed to' : 'be accustomed to'} (I am used to the cold). Not the same as "used to + V1" (a past habit).',
            ),
          ),
        );
      } else if (be &&
          g._isBase(n) &&
          !cut(i + 2) &&
          (!g._isNounish(n) || i + 3 < e && !cut(i + 3) && (_det.contains(w[i + 3]) || _objPron.contains(w[i + 3]) || g._isNounish(w[i + 3]) && !const {'and', 'or', 'but'}.contains(w[i + 3])))) {
        out.add(
          GMark('g_used_to', 'used_for', [...head, i + 2], const ['passive', 'used_to'], 'be used to + V1 (passive)', 'Kullanılmak (-mek için)', (
            'Dikkat: be used to + V1 burada "-mek için kullanılmak" demek (edilgen: use → used). "Alışkın olmak" (be used to + V-ing) ya da "eskiden yapardı" (used to + V1) değil.',
            'Careful: be used to + V1 here means "be used for doing" (the passive of use). Not "be accustomed to" (be used to + V-ing) or a past habit (used to + V1).',
          )),
        );
      }
    }
  }

  // ------------------------------------------------------------ causative

  void _causative(List<GMark> out) {
    final question = text.substring(toks[e - 1].end).trimLeft().startsWith('?');
    for (var i = s; i < e - 2; i++) {
      final lem = g.lemmas(w[i]);
      final verb = lem.contains('have')
          ? 'have'
          : lem.contains('get')
          ? 'get'
          : lem.contains('make')
          ? 'make'
          : null;
      if (verb == null || w[i].contains("'")) continue;
      // "Have you finished?", "Had I known": a question or inversion, not a causative.
      if (verb == 'have' && (i == s || cut(i) || _whWords.contains(w[i - 1])) && (question || i == s && w[i] == 'had')) continue;
      final isV = groups.any((v) => v.toks.contains(i)) || i > s && (w[i - 1] == 'to' || aux(i - 1) != null || _skip.contains(w[i - 1]));
      if (!isV) continue;
      // The object: a pronoun, a name, or a short noun phrase ending in a noun.
      var j = i + 1;
      if (cut(j)) continue;
      int objEnd;
      if (_objPron.contains(w[j]) && w[j] != 'you' || isName(j)) {
        objEnd = j;
      } else if (_det.contains(w[j]) || _possDet.contains(w[j])) {
        var k = j + 1;
        var last = -1;
        while (k < e && k <= j + 4 && !cut(k)) {
          if (g._isNounish(w[k]) && !g._isPP(w[k])) {
            last = k;
            k++;
            continue;
          }
          if (g._isAdjLemma(w[k]) && !g._isPP(w[k])) {
            k++;
            continue;
          }
          break;
        }
        if (last < 0) continue;
        objEnd = last;
      } else {
        continue;
      }
      final k = objEnd + 1;
      if (k >= e || cut(k)) continue;
      final y = w[k];
      // "made Reddy Fox jump": a name goes on; "had a little better arranged": no object.
      if (isCap(k) || [for (var q = j; q <= objEnd; q++) w[q]].any((x) => const {'little', 'bit', 'lot', 'few', 'better'}.contains(x) || _skip.contains(x))) continue;
      final objText = words([for (var q = j; q <= objEnd; q++) q]);
      // have / get + object + V3: "had his hair cut", "got the car repaired".
      if ((verb == 'have' || verb == 'get') &&
          g._isPP(y) &&
          !_edAdj.contains(y) &&
          !g._isIng(y) &&
          // "I got a letter written by him": something received, not a job.
          !(verb == 'get' && (w[j] == 'a' || w[j] == 'an') && at(k + 1) == 'by') &&
          !(k + 1 < e && !cut(k + 1) && g._isNounish(w[k + 1]) && !_preps.contains(w[k + 1]) && !_det.contains(w[k + 1]) && g._isAdjLemma(y))) {
        out.add(
          GMark(
            'g_causative',
            'causative_pp',
            [i, k],
            const ['causative'],
            '$verb + object + V3',
            'Ettirgen yapı (-tırmak)',
            (
              '$verb + nesne + V3: işi kendin yapmazsın, başkasına yaptırırsın (I had my hair cut = saçımı kestirdim). Aynı yapı bazen başına gelen kötü bir olayı anlatır (He had his car stolen = arabası çalındı).',
              '$verb + object + V3: you do not do the job yourself, someone does it for you (I had my hair cut). The same pattern can also tell what happened to you (He had his car stolen).',
            ),
            note: ('Yaptırılan iş: "$objText ${toks[k].text}".', 'The job: "$objText ${toks[k].text}".'),
          ),
        );
        continue;
      }
      // have / make + person + V1: "made him cry", "had them wait".
      if ((verb == 'have' || verb == 'make') && objEnd == j && g._isBase(y) && (!g._isNounish(y) || w[j] != 'her' && !_det.contains(w[j])) && !_notVerb.contains(y)) {
        out.add(
          GMark(
            'g_causative',
            'causative_base',
            [i, j, k],
            const ['causative'],
            '$verb + person + V1',
            verb == 'make' ? 'Zorla yaptırmak' : 'Birine yaptırmak',
            verb == 'make'
                ? (
                    'make + kişi + V1 (to yok): birini bir şey yapmaya zorlamak ya da yol açmak (made him cry = onu ağlattı).',
                    'make + person + V1 (no "to"): force or cause someone to do something (made him cry).',
                  )
                : ('have + kişi + V1 (to yok): birine bir işi yaptırmak, görev vermek (had them wait = onları beklettirdi).', 'have + person + V1 (no "to"): get someone to do a job (had them wait).'),
          ),
        );
        continue;
      }
      // get + person + to V1: "got him to help".
      if (verb == 'get' && objEnd == j && y == 'to' && k + 1 < e && g._isBase(w[k + 1])) {
        out.add(
          GMark('g_causative', 'causative_get', [i, j, k, k + 1], const ['causative'], 'get + person + to V1', 'İkna ederek yaptırmak', (
            'get + kişi + to V1: birini ikna ederek bir şey yaptırmak (got him to help = ona yardım ettirdi, onu yardıma razı etti).',
            'get + person + to V1: persuade someone to do something (got him to help).',
          )),
        );
      }
    }
  }

  // ------------------------------------------------------- inversion and cleft

  void _emphasis(List<GMark> out) {
    final question = text.substring(toks[e - 1].end).trimLeft().startsWith('?');
    if (question || e - s < 4) return;
    bool subj(int k) => k < e && (_subjOnly.contains(w[k]) || w[k] == 'you' || w[k] == 'it' || w[k] == 'there' || _det.contains(w[k]) || isName(k));
    // Inversion after a negative word at the start: "Never have I seen …".
    int? lead;
    if (const {'never', 'rarely', 'seldom', 'hardly', 'scarcely', 'barely', 'little', 'nowhere'}.contains(w[s])) lead = s + 1;
    if (w[s] == 'not' && at(s + 1) == 'only') lead = s + 2;
    if (w[s] == 'no' && at(s + 1) == 'sooner') lead = s + 2;
    if (const {'under', 'on', 'at', 'in'}.contains(w[s]) && at(s + 1) == 'no' && const {'circumstances', 'account', 'time', 'way', 'condition'}.contains(at(s + 2))) lead = s + 3;
    if (lead != null && lead < e - 1 && !cut(lead) && aux(lead) != null && !subjInside(lead) && subj(lead + 1)) {
      out.add(
        GMark(
          'g_emphasis',
          'inversion',
          [for (var k = s; k <= lead; k++) k],
          const ['inversion'],
          'Inversion',
          'Devrik cümle',
          (
            'Olumsuz ya da kısıtlayıcı bir söz (never, hardly, not only, no sooner …) cümle başına gelince soru gibi yardımcı fiil özneden önce gelir: Never have I seen = hiç görmedim. Anlamı vurgular; resmî ve edebî dilde sık görülür.',
            'When a negative or limiting word (never, hardly, not only, no sooner …) starts the sentence, the auxiliary comes before the subject, as in a question: Never have I seen. It adds emphasis and is common in formal and literary English.',
          ),
          note: ('Düz sırası: "${toks[lead + 1].text} ${toks[lead].text.toLowerCase()} …"', 'Normal order: "${toks[lead + 1].text} ${toks[lead].text.toLowerCase()} …"'),
        ),
      );
    }
    // Cleft: "It was John who called", "It was in Paris that they met".
    if (w[s] == 'it' || w[s] == "it's" || w[s] == "'twas") {
      var k = s + 1;
      if (w[s] == 'it') {
        if (!const {'is', 'was', "isn't", "wasn't"}.contains(at(k))) k = -1;
        k = k < 0 ? -1 : k + 1;
      }
      if (k > 0 && at(k) == 'not') k++;
      if (k > 0 && k < e - 1) {
        int? end;
        if (isName(k) || const {'me', 'him', 'her', 'us', 'them', 'you', 'i', 'he', 'she', 'we', 'they'}.contains(w[k])) {
          end = k;
          while (end! + 1 < e && isName(end + 1) && !cut(end + 1)) {
            end++;
          }
        } else if (const {'in', 'at', 'on', 'because', 'for', 'by', 'from', 'with', 'during', 'after', 'before', 'here', 'there', 'then'}.contains(w[k])) {
          var q = k + 1;
          while (q < e && q <= k + 5 && !cut(q) && w[q] != 'that' && w[q] != 'who') {
            q++;
          }
          if (q < e && q > k + 1 && (w[q] == 'that') && !cut(q)) end = q - 1;
        }
        if (end != null && end + 1 < e && (w[end + 1] == 'who' || w[end + 1] == 'that') && !cut(end + 1) && groups.any((v) => v.first > end! + 1 && v.first <= end + 5)) {
          final idx = [s, if (w[s] == 'it') s + 1, end + 1];
          out.add(
            GMark(
              'g_emphasis',
              'cleft',
              idx,
              const ['cleft_sentences'],
              'Cleft Sentence',
              'Vurgu cümlesi (It is … that)',
              (
                'It is / It was + vurgulanan öğe + who / that …: cümlenin bir parçasını öne çıkarır (It was John who called = arayan John idi, başkası değil).',
                'It is / It was + focus + who / that …: puts one part of the sentence in focus (It was John who called, not someone else).',
              ),
              note: ('Vurgulanan: "${words([for (var q = s + (w[s] == 'it' ? 2 : 1); q <= end; q++) q])}".', 'In focus: "${words([for (var q = s + (w[s] == 'it' ? 2 : 1); q <= end; q++) q])}".'),
            ),
          );
        }
      }
    }
    // Pseudo-cleft: "What I need is a holiday", "What happened was …".
    if (w[s] == 'what') {
      final first = groups.where((v) => v.first > s && v.first <= s + 3).firstOrNull;
      if (first != null) {
        final be = groups.where((v) => v.first > first.last && v.first <= first.last + 6 && v.toks.length == 1 && const {'is', 'was'}.contains(aux(v.first))).firstOrNull;
        if (be != null && be.first + 1 < e && !cut(be.first) && ![for (var q = first.last + 1; q < be.first; q++) q].any((q) => cut(q) || const {'but', 'and', 'or'}.contains(w[q]))) {
          out.add(
            GMark('g_emphasis', 'pseudo_cleft', [s, be.first], const ['cleft_sentences'], 'Cleft Sentence (What …)', 'Vurgu cümlesi (What … is)', (
              'What + cümle + is / was + vurgulanan: önce merak uyandırır, asıl bilgiyi sona bırakır (What I need is a holiday = ihtiyacım olan şey bir tatil).',
              'What + clause + is / was + focus: builds up to the main information at the end (What I need is a holiday).',
            )),
          );
        }
      }
    }
  }

  // ------------------------------------------------------------ tag questions

  // ------------------------------------------------------------ participles

  void _participles(List<GMark> out) {
    final taken = <int>{};
    bool inGroup(int k) => groups.any((v) => v.toks.contains(k));
    bool subjAt(int k) => k < e && (_subjOnly.contains(w[k]) || const {'you', 'it', 'there'}.contains(w[k]) || _det.contains(w[k]) || _possDet.contains(w[k]) || isName(k));
    bool partIng(String x) => g._isIng(x) && x != 'being' && !_ingNotParticiple.contains(x) && !g.posOfLemma(x).contains('n') && !g.posOfLemma(x).contains('a');
    bool partIngFront(String x) => (g._isIng(x) || x == 'being') && !_ingNotParticiple.contains(x);
    const clauseTr =
        'Ortaç cümleciği, yan cümleyi kısaltır: V-ing = aynı anda / etken (yaparken, yaparak), Having + V3 = önce olan (yaptıktan sonra), V3 = edilgen (yapılmış). Öznesi ana cümlenin öznesiyle aynıdır.';
    const clauseEn = 'A participle clause shortens a clause: V-ing = at the same time / active, Having + V3 = earlier, V3 = passive meaning. Its subject is the subject of the main clause.';

    // 1. At the start: "Walking home, I met …", "Having finished, she left", "Built in 1890, the bridge …".
    var k0 = s;
    if (const {'while', 'when'}.contains(w[s]) && s + 1 < e && partIngFront(w[s + 1])) k0 = s + 1;
    final x0 = w[k0];
    int? head;
    String? kind;
    if (x0 == 'having' && k0 + 1 < e && g._isPP(w[k0 + 1]) && !cut(k0 + 1)) {
      head = k0 + 1;
      kind = 'perfect';
    } else if (x0 == 'not' && k0 + 1 < e && partIngFront(w[k0 + 1]) && !cut(k0 + 1)) {
      head = k0 + 1;
      kind = 'ing';
    } else if (partIngFront(x0) && x0 != 'having') {
      head = k0;
      kind = 'ing';
    } else if (k0 == s && g._isPP(x0) && !_intransPP.contains(x0) && !_feelingPairs.containsKey(x0) && !g._isIng(x0)) {
      head = k0;
      kind = 'pp';
    }
    // "Had he known …"; and a real sentence start with a capital, not the rest after a quote ("… !" said Alice).
    if (head != null && (aux(head) != null || !isCap(s))) head = null;
    if (head != null) {
      int? comma;
      for (var k = head + 1; k < e && k <= head + 12; k++) {
        if (cut(k)) {
          comma = k;
          break;
        }
      }
      final commaOnly = comma != null && comma > head + 1 && RegExp(r'^[\s\d]*,\s*$').hasMatch(gap(comma));
      if (commaOnly && subjAt(comma) && !groups.any((v) => v.first > head! && v.first < comma!) && groups.any((v) => v.first >= comma! && v.first <= comma + 4 && v.first > comma)) {
        final idx = [for (var q = s; q <= head; q++) q];
        taken.addAll(idx);
        out.add(
          GMark(
            'g_participles',
            kind == 'perfect'
                ? 'participle_perfect'
                : kind == 'pp'
                ? 'participle_passive'
                : 'participle_ing',
            idx,
            const ['participle_clauses'],
            kind == 'perfect'
                ? 'Participle Clause (Having + V3)'
                : kind == 'pp'
                ? 'Participle Clause (V3)'
                : 'Participle Clause (V-ing)',
            kind == 'perfect'
                ? 'Ortaç cümleciği (yaptıktan sonra)'
                : kind == 'pp'
                ? 'Ortaç cümleciği (edilgen, yapılmış)'
                : 'Ortaç cümleciği (yaparken / yaparak)',
            (clauseTr, clauseEn),
            note: ('Cümleciğin öznesi virgülden sonra gelen özne: "${words([comma])}".', 'The clause shares the subject after the comma: "${words([comma])}".'),
          ),
        );
      }
    }

    for (var i = s + 1; i < e; i++) {
      if (taken.contains(i)) continue;
      final x = w[i];
      // 2. After a comma at the end: "She left the room, slamming the door."
      if (cut(i) && RegExp(r'^\s*,\s*$').hasMatch(gap(i)) && partIng(x) && !inGroup(i) && !g._isIng(w[i - 1]) && groups.any((v) => v.isTense && v.last < i && v.first >= s)) {
        final n1 = at(i + 1);
        final pw = w[i - 1];
        // "a sensible, deserving woman": a list of adjectives before a noun.
        final adjList = (g._isAdjLemma(pw) || _edAdj.contains(pw) || _feelingPairs.containsKey(pw)) && g._isNounish(n1) && !_det.contains(n1) && !_preps.contains(n1) && !_possDet.contains(n1);
        if (n1 != 'and' && n1 != 'or' && !adjList && !(i + 1 < e && cut(i + 1) && g._isIng(n1))) {
          taken.add(i);
          out.add(
            GMark(
              'g_participles',
              'participle_ing',
              [i],
              const ['participle_clauses'],
              'Participle Clause (V-ing)',
              'Ortaç cümleciği (yaparak / yaparken)',
              (clauseTr, clauseEn),
              note: (
                'Virgülden sonraki V-ing, ana cümledeki kişinin aynı anda yaptığı şeyi anlatır: "-erek, -ken".',
                'The V-ing after the comma tells what the same person was doing at the same time.',
              ),
            ),
          );
          continue;
        }
      }
      // 3. A reduced relative clause after a noun: "a letter written by him", "the man standing by the door".
      if (!cut(i) && !inGroup(i) && i + 1 < e && !cut(i + 1)) {
        final y = w[i - 1];
        final pp = g.participles.contains(x) && !g.pastForms.contains(x) && !_edAdj.contains(x) && !_noPassive(x);
        final ing = g._isIng(x) && x != 'being' && !_ingNotParticiple.contains(x) && !_ingAdj.contains(x) && !_feelingPairs.containsKey(x);
        if ((pp || ing) &&
            x != 'having' &&
            x != 'going' &&
            g._isNounish(y) &&
            !y.endsWith("'s") &&
            !y.endsWith('ly') &&
            y != 'being' &&
            !_spendNouns.contains(y) &&
            !isName(i - 1) &&
            !inGroup(i - 1) &&
            aux(i - 1) == null &&
            !_subjOnly.contains(y) &&
            !_objPron.contains(y)) {
          var d = i - 1;
          while (d > s && d > i - 4 && !cut(d) && (g._isAdjLemma(w[d - 1]) || g._isNounish(w[d - 1])) && !_det.contains(w[d - 1])) {
            d--;
          }
          final hasDet = d > s && !cut(d) && (_det.contains(w[d - 1]) || _possDet.contains(w[d - 1])) && w[d - 1] != 'that';
          final n = w[i + 1];
          final follows = pp
              ? (const {'by', 'in', 'on', 'at', 'from', 'with', 'for', 'as', 'into', 'during', 'since', 'over', 'under'}.contains(n))
              : (_preps.contains(n) || _det.contains(n) || _possDet.contains(n));
          if (hasDet && follows) {
            taken.add(i);
            final np = words([for (var q = d - 1; q < i; q++) q]);
            out.add(
              GMark(
                'g_participles',
                pp ? 'reduced_relative_pp' : 'reduced_relative_ing',
                [i],
                const ['participle_clauses', 'relative_clauses'],
                pp ? 'Reduced Relative Clause (V3)' : 'Reduced Relative Clause (V-ing)',
                pp ? 'Kısaltılmış sıfat cümleciği (yapılmış olan)' : 'Kısaltılmış sıfat cümleciği (yapan)',
                pp
                    ? (
                        'İsimden sonra gelen V3, "which / who + be + V3" yerine geçer ve edilgen anlam verir (a letter written by him = onun yazdığı mektup).',
                        'A V3 after a noun stands for "which / who + be + V3" and has a passive meaning (a letter written by him).',
                      )
                    : (
                        'İsimden sonra gelen V-ing, "who / which + fiil" yerine geçer (the man standing by the door = kapının yanında duran adam).',
                        'A V-ing after a noun stands for "who / which + verb" (the man standing by the door).',
                      ),
                note: (
                  'Kısaltılmamış hali: "$np ${pp ? 'which / who is (was)' : 'who / which'} ${toks[i].text} …".',
                  'In full: "$np ${pp ? 'which / who is (was)' : 'who / which'} ${toks[i].text} …".',
                ),
              ),
            );
            continue;
          }
        }
      }
      // 4. Feeling adjectives: "I was bored", "a boring film".
      final pair = _feelingPairs[x];
      if (pair != null && !inGroup(i)) {
        final p = pv(i);
        final y = p >= s ? w[p] : '';
        final afterBe =
            p >= s &&
            !cut(p + 1) &&
            (aux(p) != null && const {'am', 'is', 'are', 'was', 'were', "'s"}.contains(aux(p)) && !subjInside(p) ||
                const {'be', 'been', 'being'}.contains(y) ||
                _linkVerbs.any((l) => g.lemmas(y).contains(l)) ||
                subjInside(p) && const {"'m", "'re", "'s"}.any(w[p].endsWith));
        final n1 = at(i + 1);
        final ingObj = x.endsWith('ing') && i + 1 < e && !cut(i + 1) && (_det.contains(n1) || _objPron.contains(n1) || _possDet.contains(n1));
        final beforeNoun =
            i + 1 < e &&
            !cut(i + 1) &&
            g._isNounish(n1) &&
            !g._isS(n1) &&
            (y == 'very' || y == 'so' || y == 'really' || y == 'quite' || y == 'most' || y == 'more' || _det.contains(y) || _possDet.contains(y));
        if ((afterBe && !ingObj) || beforeNoun) {
          final ed = x.endsWith('ed') || x.endsWith('en');
          out.add(
            GMark(
              'g_participles',
              ed ? 'feeling_ed' : 'feeling_ing',
              [i],
              const ['participle_adjectives'],
              ed ? '-ed adjective (how someone feels)' : '-ing adjective (what causes the feeling)',
              ed ? '-ed sıfatı (hisseden)' : '-ing sıfatı (hissettiren)',
              ed
                  ? ('-ed ile biten sıfat, kişinin ne hissettiğini anlatır: I am bored = sıkıldım.', 'An -ed adjective tells how someone feels: I am bored.')
                  : ('-ing ile biten sıfat, o duyguyu neyin verdiğini anlatır: The film is boring = film sıkıcı.', 'An -ing adjective tells what causes the feeling: The film is boring.'),
              note: ed
                  ? ('Karşılığı: "$pair" (o duyguyu veren şey).', 'Its pair: "$pair" (what causes the feeling).')
                  : ('Karşılığı: "$pair" (o duyguyu yaşayan kişi).', 'Its pair: "$pair" (the person who feels it).'),
            ),
          );
        }
      }
    }
  }

  void _tags(List<GMark> out) {
    if (e - s < 4) return;
    final after = text.substring(toks[e - 1].end);
    if (!after.trimLeft().startsWith('?')) return;
    final a = e - 2, p = e - 1;
    final ax = aux(a);
    if (ax == null || ax == "'s" || ax == "'d" || subjInside(a) || !cut(a)) return;
    if (!const {'i', 'you', 'he', 'she', 'it', 'we', 'they', 'there'}.contains(w[p])) return;
    final neg = w[a].endsWith("n't") || w[a] == 'cannot';
    out.add(
      GMark(
        'g_tags',
        'tag',
        [a, p],
        const ['question_tags'],
        'Question Tag',
        'Onay sorusu (değil mi?)',
        (
          'Cümle sonundaki kısa soru "değil mi?" anlamı verir. Olumlu cümleye olumsuz, olumsuz cümleye olumlu etiket gelir; yardımcı fiil ana cümleninkiyle aynıdır (She is late, isn’t she?).',
          'A short question at the end means "right?". A positive sentence takes a negative tag and the other way round, with the same auxiliary as the main clause (She is late, isn’t she?).',
        ),
        note: neg
            ? (
                'Etiket olumsuz ("${words([a, p])}"), yani ana cümle olumlu: konuşan onay bekliyor.',
                'The tag is negative ("${words([a, p])}"), so the main clause is positive: the speaker expects a yes.',
              )
            : ('Etiket olumlu ("${words([a, p])}"): ana cümle olumsuz ya da emir cümlesi.', 'The tag is positive ("${words([a, p])}"): the main clause is negative or an order.'),
      ),
    );
  }

  // ------------------------------------------------------- relative clauses

  void _relatives(List<GMark> out) {
    for (var i = s + 1; i < e; i++) {
      final x = w[i];
      if (!const {'who', 'whom', 'whose', 'which', 'that', 'where', 'when'}.contains(x)) continue;
      var p = i - 1;
      var prep = -1;
      if (_preps.contains(w[p]) && const {'whom', 'which', 'whose'}.contains(x) && p > s) {
        prep = p;
        p--;
      }
      final g0 = gap(prep >= 0 ? prep : i);
      // Not after a quotation mark, colon or number ("asked: 'Who is …'", "Stages 1 to 4 which").
      if (RegExp(r'''[:"“”‘’'—–\-0-9]''').hasMatch(g0) || prep >= 0 && gap(i).trim().isNotEmpty) continue;
      final comma = cut(prep >= 0 ? prep : i);
      final y = w[p];
      // The word before must be the noun the clause describes.
      final nounish =
          (g._isNounish(y) ||
              isName(p) ||
              const {
                'those',
                'anyone',
                'someone',
                'everyone',
                'one',
                'people',
                'anything',
                'something',
                'everything',
                'nothing',
                'all',
                'somebody',
                'anybody',
                'everybody',
                'nobody',
                'none',
              }.contains(y)) &&
          !_preps.contains(y) &&
          aux(p) == null &&
          !_objPron.contains(y) &&
          !_subjOnly.contains(y);
      final verbBefore =
          groups.any((v) => v.toks.contains(p)) ||
          g
              .lemmas(y)
              .any(
                (l) =>
                    _askIf.contains(l) ||
                    _reportVerbs.contains(l) ||
                    l == 'think' ||
                    l == 'believe' ||
                    l == 'show' ||
                    l == 'explain' ||
                    l == 'understand' ||
                    l == 'realize' ||
                    l == 'realise' ||
                    l == 'imagine',
              );
      if (verbBefore) continue;
      if (_preps.contains(y) && prep < 0) continue;
      final n1 = at(i + 1);
      bool ok;
      switch (x) {
        case 'who' || 'whom' || 'whose':
          ok = nounish || (comma && isName(p));
        case 'which':
          // "the box which …" or ", which …"; not "which one" (a question word).
          ok = (nounish || comma) && !(i + 2 < e && g._isNounish(n1) && !g._isVerbLemma(n1) && groups.every((v) => !v.toks.contains(i + 1)) && !comma);
        case 'that':
          if (comma || !nounish || _thatNouns.contains(y) || g._isAdjLemma(y) && !g.posOfLemma(y).contains('n')) {
            ok = false;
          } else {
            // Followed by a verb ("the man that lives") or by a subject and a verb ("the book that I read").
            final vNext = groups.any((v) => v.first == i + 1) || (n1.isNotEmpty && aux(i + 1) != null);
            final subjNext = (_subjOnly.contains(n1) || n1 == 'you' || n1 == 'it' || _det.contains(n1) || isName(i + 1)) && groups.any((v) => v.first > i + 1 && v.first <= i + 4);
            // "the book that I read": the verb in it has no object of its own.
            final gv = subjNext ? groups.firstWhere((v) => v.first > i + 1 && v.first <= i + 4) : null;
            final gapOk =
                gv == null ||
                (!gv.passive &&
                    !(gv.toks.length == 1 && aux(gv.first) != null) &&
                    (gv.last + 1 >= e || cut(gv.last + 1) || _preps.contains(w[gv.last + 1]) || groups.any((v) => v.first == gv.last + 1) || _skip.contains(w[gv.last + 1])));
            ok = vNext || subjNext && gapOk;
            if (ok && _det.contains(n1) && !groups.any((v) => v.first > i + 1 && v.first <= i + 4 && v.first != i + 2)) ok = false;
          }
        case 'where':
          ok = _placeNouns.contains(y) || comma && isName(p);
        case 'when':
          ok = _timeNouns.contains(y) && !comma;
        default:
          ok = false;
      }
      if (!ok) continue;
      // The clause: up to the next comma when it is set off by commas,
      // otherwise to the end of its first verb.
      final start = prep >= 0 ? prep : i;
      var end = i;
      final b = boundaryAfter(i);
      final vg = groups.where((v) => v.first > i && v.first < b).firstOrNull;
      if (comma) {
        // "If there is no Mr Glass, whose hat is this?" is a question.
        if ((x == 'whose' || x == 'which') && i + 2 < e && aux(i + 2) != null && text.substring(toks[e - 1].end).trimLeft().startsWith('?')) continue;
        end = b - 1;
      } else if (vg != null) {
        end = vg.last;
      } else {
        continue;
      }
      if (end - start > 14) end = vg?.last ?? start;
      final idx = [for (var k = start; k <= end; k++) k];
      final info = _relInfo[x]!;
      final noun = isName(p) || !(p > s && _det.contains(w[p - 1])) ? toks[p].text : '${toks[p - 1].text} ${toks[p].text}';
      final kind = comma
          ? (
              'Virgülle ayrıldığı için ek bilgi veriyor (non-defining): çıkarılsa da cümle anlamını korur; "that" kullanılamaz.',
              'Set off by commas, so it adds extra information (non-defining): the sentence still works without it, and "that" cannot be used.',
            )
          : ('Virgülsüz olduğu için hangi "$noun" kastedildiğini belirliyor (defining).', 'With no commas it tells us which one is meant (defining).');
      out.add(
        GMark(
          'g_relative',
          'rel_$x',
          idx,
          const ['relative_clauses'],
          'Relative Clause · $x',
          'Sıfat cümleciği · $x',
          info,
          note: ('"${words(idx)}" → "$noun" ismini niteliyor. ${kind.$1}', '"${words(idx)}" → describes "$noun". ${kind.$2}'),
        ),
      );
    }
  }

  // ------------------------------------------------------ gerund / infinitive

  void _gerundInf(List<GMark> out) {
    for (var i = s; i < e - 1; i++) {
      final x = w[i];
      final lem = g.lemmas(x);
      bool inSet(Set<String> set) => set.contains(x) || lem.any(set.contains);
      String verbLemma(Set<String> set) => set.contains(x) ? x : lem.firstWhere(set.contains);
      // The verb itself has to be used as a verb here, not as a noun ("a plan to …" is fine too, but we stay with verbs).
      final isV =
          groups.any((v) => v.toks.contains(i)) ||
          (i > s && (w[i - 1] == 'to' || aux(i - 1) != null || _skip.contains(w[i - 1])) && g._isVerbLemma(lem.first)) ||
          g._isIng(x) && i > s && aux(i - 1) != null;
      var j = nx(i);
      final n1 = at(j);
      // "can't stand / can't help + V-ing".
      final cant = pv(i) >= s && const {"can't", 'cannot', "couldn't"}.contains(w[pv(i)]) && (lem.contains('stand') || lem.contains('help'));
      if (cant && g._isIng(n1) && !cut(j)) {
        out.add(
          GMark('g_gerund_inf', 'gerund_verb', [pv(i), i, j], const ['gerund_infinitive'], 'Verb + Gerund (V-ing)', 'Fiil + V-ing', (
            "can't stand / can't help + V-ing: -e dayanamamak / -meden edememek; ardından fiil -ing alır.",
            "can't stand / can't help + V-ing: the next verb takes -ing.",
          )),
        );
        continue;
      }
      // Verb + V-ing.
      if (isV && (inSet(_gerundVerbs) || inSet(_bothVerbs)) && g._isIng(n1) && n1 != 'being' && !_ingAdj.contains(n1) && !cut(j)) {
        final v = inSet(_gerundVerbs) ? verbLemma(_gerundVerbs) : verbLemma(_bothVerbs);
        final note = _bothNotes[v];
        out.add(
          GMark(
            'g_gerund_inf',
            'gerund_verb',
            [i, j],
            const ['gerund_infinitive'],
            'Verb + Gerund (V-ing)',
            'Fiil + V-ing',
            note != null
                ? note
                : _bothVerbs.contains(v)
                ? ('"$v" hem V-ing hem to V1 alabilir; anlam neredeyse aynıdır.', '"$v" can take V-ing or to V1 with almost the same meaning.')
                : ('"$v" fiilinden sonra ikinci fiil -ing alır (to + V1 olmaz): enjoy reading, avoid making.', 'After "$v" the second verb takes -ing (not to + V1): enjoy reading, avoid making.'),
          ),
        );
        continue;
      }
      // Verb + to V1.
      if (isV && (inSet(_infVerbs) || inSet(_bothVerbs)) && n1 == 'to' && !cut(j) && g._isBase(at(j + 1))) {
        final v = inSet(_infVerbs) ? verbLemma(_infVerbs) : verbLemma(_bothVerbs);
        final note = _bothNotes[v];
        out.add(
          GMark(
            'g_gerund_inf',
            'inf_verb',
            [i, j, j + 1],
            const ['gerund_infinitive'],
            'Verb + to-Infinitive',
            'Fiil + to V1',
            note ??
                (_bothVerbs.contains(v)
                    ? ('"$v" hem to V1 hem V-ing alabilir; anlam neredeyse aynıdır.', '"$v" can take to V1 or V-ing with almost the same meaning.')
                    : ('"$v" fiilinden sonra ikinci fiil to + V1 olur: want to go, decide to stay.', 'After "$v" the second verb is to + V1: want to go, decide to stay.')),
          ),
        );
        continue;
      }
      // Verb + object + to V1: "asked him to wait".
      if (isV && inSet(_objInfVerbs) && (_objPron.contains(n1) || isName(j)) && at(j + 1) == 'to' && g._isBase(at(j + 2)) && !cut(j) && !cut(j + 1)) {
        final v = verbLemma(_objInfVerbs);
        out.add(
          GMark('g_gerund_inf', 'obj_inf', [i, j, j + 1, j + 2], const ['gerund_infinitive'], 'Verb + Object + to-Infinitive', 'Fiil + nesne + to V1', (
            '"$v + kişi + to V1": birinin bir şey yapmasını istemek, söylemek ya da sağlamak (asked him to wait = ondan beklemesini istedi).',
            '"$v + person + to V1": wanting, telling or getting someone to do something (asked him to wait).',
          )),
        );
        continue;
      }
      // Preposition + V-ing: "before leaving", "interested in reading".
      if ((_gerundPreps.contains(x) || x == 'to' && i > s && _toGerund(i)) && g._isIng(n1) && j == i + 1 && n1 != 'being' && !_ingAdj.contains(n1)) {
        // "in towering waves": an -ing adjective before a noun.
        if (const {'in', 'with', 'of', 'at', 'from', 'through', 'upon', 'against'}.contains(x) &&
            g._isAdjLemma(n1) &&
            j + 1 < e &&
            !cut(j + 1) &&
            g._isNounish(w[j + 1]) &&
            !_det.contains(w[j + 1]) &&
            !_objPron.contains(w[j + 1]) &&
            !_preps.contains(w[j + 1])) {
          continue;
        }
        final noun =
            _ingNouns.contains(n1) && !const {'without', 'before', 'after', 'by', 'despite', 'besides', 'instead'}.contains(x) ||
            const {'morning', 'evening', 'building', 'ceiling', 'wedding', 'meeting', 'painting', 'beginning', 'ending', 'thing', 'king', 'ring', 'spring', 'string', 'wing'}.contains(n1);
        final objNext = j + 1 < e && !cut(j + 1) && (_det.contains(w[j + 1]) || _objPron.contains(w[j + 1]) || isName(j + 1) || w[j + 1] == 'to' || _skip.contains(w[j + 1]));
        if (noun && !objNext) continue; // "of the building", "in the morning"
        if (i > s && _det.contains(w[i - 1])) continue;
        out.add(
          GMark(
            'g_gerund_inf',
            'prep_gerund',
            [i, j],
            const ['gerund_infinitive'],
            'Preposition + Gerund',
            'Edat + V-ing',
            x == 'to'
                ? (
                    'Bu kalıpta "to" bir edattır, mastar değil; bu yüzden fiil -ing alır (look forward to seeing, be used to living).',
                    'In this pattern "to" is a preposition, not part of an infinitive, so the verb takes -ing (look forward to seeing).',
                  )
                : (
                    'Edattan ($x) sonra fiil her zaman -ing alır: before leaving, without saying, interested in learning.',
                    'After a preposition ($x) a verb always takes -ing: before leaving, without saying, interested in learning.',
                  ),
          ),
        );
      }
    }
  }

  /// "look forward to", "be used to", "get used to", "object to": a "to" that is a preposition.
  bool _toGerund(int i) {
    final a = at(i - 1), b = i - 2 >= s ? w[i - 2] : '';
    if (a == 'forward' && g.lemmas(b).contains('look')) return true;
    if (a == 'used' && (aux(i - 2) != null || g.lemmas(b).contains('get') || g.lemmas(b).contains('become'))) return true;
    if (a == 'accustomed' || a == 'addicted' || a == 'committed' || a == 'devoted' || a == 'dedicated') return true;
    if (g.lemmas(a).contains('object') && groups.any((v) => v.toks.contains(i - 1))) return true;
    return false;
  }

  // ------------------------------------------------------------ comparison

  void _comparison(List<GMark> out) {
    // "The more you practise, the better you become."
    if (e - s > 4 && w[s] == 'the' && (w[s + 1] == 'more' || w[s + 1] == 'less' || _comparativeBase(w[s + 1]) != null || _irregComp.containsKey(w[s + 1]))) {
      for (var k = s + 2; k < e - 1; k++) {
        if (cut(k) && w[k] == 'the' && (w[k + 1] == 'more' || w[k + 1] == 'less' || _comparativeBase(w[k + 1]) != null || _irregComp.containsKey(w[k + 1]))) {
          out.add(
            GMark('g_comparison', 'double_comparative', [s, s + 1, k, k + 1], const ['comparison'], 'The more …, the more …', 'Ne kadar …, o kadar …', (
              'the + karşılaştırma …, the + karşılaştırma …: biri arttıkça öteki de artar (The more you practise, the better you become = ne kadar çok çalışırsan o kadar iyi olursun).',
              'the + comparative …, the + comparative …: as one thing grows, so does the other (The more you practise, the better you become).',
            )),
          );
          break;
        }
      }
    }
    for (var i = s; i < e; i++) {
      if (out.isNotEmpty && out.last.key == 'double_comparative' && out.last.tokens.contains(i)) continue;
      final x = w[i];
      final n1 = at(i + 1);
      // the + superlative / possessive + superlative
      final supIrr = _irregSup.containsKey(x) && x != 'most' && x != 'least';
      final supEst = _superlativeBase(x);
      final prevDet = i > s && (w[i - 1] == 'the' || _possDet.contains(w[i - 1]) || w[i - 1].endsWith("'s"));
      if ((x == 'most' || x == 'least') && prevDet && n1.isNotEmpty && g._isAdjLemma(n1) && !g.posOfLemma(n1).contains('n')) {
        out.add(
          GMark('g_comparison', 'superlative', [i - 1, i, i + 1], const ['comparison'], 'Superlative', 'Üstünlük (en …)', (
            'the most / the least + sıfat: bir grubun en … olanı (uzun sıfatlarla). Kısa sıfatlar -est alır: the tallest.',
            'the most / the least + adjective: the extreme of a group (long adjectives). Short ones take -est: the tallest.',
          )),
        );
        i++;
        continue;
      }
      if ((supIrr || supEst != null) && prevDet) {
        final base = supIrr ? _irregSup[x]! : supEst!;
        out.add(
          GMark('g_comparison', 'superlative', [i - 1, i], const ['comparison'], 'Superlative', 'Üstünlük (en …)', (
            'the + sıfat-est: bir grubun en … olanı ($base → $x). Uzun sıfatlarda the most kullanılır.',
            'the + adjective-est: the extreme of a group ($base → $x). Long adjectives use the most.',
          )),
        );
        continue;
      }
      // as … as
      if (x == 'as' &&
          i + 2 < e &&
          w[i + 2] == 'as' &&
          !const {'well', 'soon', 'long', 'far', 'much', 'many', 'if', 'though', 'such'}.contains(n1) &&
          (g._isAdjLemma(n1) || g.posOfLemma(n1).contains('r')) &&
          !(i > s && w[i - 1] == 'such') &&
          !cut(i + 1) &&
          !cut(i + 2)) {
        out.add(
          GMark('g_comparison', 'equality', [i, i + 1, i + 2], const ['comparison'], 'as … as (equality)', 'Eşitlik (… kadar)', (
            'as + sıfat + as: iki şeyin eşit olduğunu söyler (as tall as = … kadar uzun). Olumsuzu: not as … as.',
            'as + adjective + as: two things are equal (as tall as). Negative: not as … as.',
          )),
        );
        i += 2;
        continue;
      }
      // more / less + adjective (+ than)
      if ((x == 'more' || x == 'less') && n1.isNotEmpty && !cut(i + 1) && (g._isAdjLemma(n1) || g.posOfLemma(n1).contains('r') && n1.endsWith('ly')) && !g.posOfLemma(n1).contains('n')) {
        final than = i + 2 < e && w[i + 2] == 'than';
        out.add(
          GMark('g_comparison', 'comparative', [i, i + 1, if (than) i + 2], const ['comparison'], 'Comparative', 'Karşılaştırma (daha …)', (
            'more / less + sıfat (+ than): iki şeyi karşılaştırır; uzun sıfatlar more alır (more beautiful than).',
            'more / less + adjective (+ than): compares two things; long adjectives take more (more beautiful than).',
          )),
        );
        i += than ? 2 : 1;
        continue;
      }
      final compIrr = _irregComp.containsKey(x) && x != 'more' && x != 'less';
      final compEr = _comparativeBase(x);
      if (compIrr || compEr != null) {
        final than = n1 == 'than' && !cut(i + 1);
        // Irregular forms only with "than" or before a noun ("a better idea"); "-er" forms need a real adjective base.
        if (compIrr && !than && !(i + 1 < e && g._isNounish(n1) && !cut(i + 1)) && !(i > s && const {'much', 'far', 'even', 'no', 'any', 'a', 'little'}.contains(w[i - 1]))) continue;
        if (compIrr && x == 'better' && i > s && w[i - 1] == "'d") continue;
        final base = compIrr ? _irregComp[x]! : compEr!;
        out.add(
          GMark('g_comparison', 'comparative', [i, if (than) i + 1], const ['comparison'], 'Comparative', 'Karşılaştırma (daha …)', (
            'sıfat-er (+ than): iki şeyi karşılaştırır ($base → $x = daha …). Kısa sıfatlar -er, uzunlar more alır.',
            'adjective-er (+ than): compares two things ($base → $x). Short adjectives take -er, long ones more.',
          )),
        );
        if (than) i++;
        continue;
      }
      if ((x == 'more' || x == 'less' || x == 'fewer') && i + 2 < e && w[i + 2] == 'than' && g._isNounish(n1) && !cut(i + 1)) {
        out.add(
          GMark('g_comparison', 'comparative', [i, i + 1, i + 2], const ['comparison'], 'Comparative', 'Karşılaştırma (daha …)', (
            'more / less / fewer + isim + than: miktarları karşılaştırır (more money than = … -den daha çok para).',
            'more / less / fewer + noun + than: compares amounts (more money than).',
          )),
        );
        i += 2;
      }
    }
  }

  String? _comparativeBase(String x) => _degreeBase(x, 'er');
  String? _superlativeBase(String x) => _degreeBase(x, 'est');

  String? _degreeBase(String x, String suf) {
    if (!x.endsWith(suf) || x.length < suf.length + 3 || _notComp.contains(x) || _notVerb.contains(x)) return null;
    final own = g.posOfLemma(x);
    if (own.isNotEmpty && !(own.length == 1 && own.contains('a')) && !(own.every((p) => p == 'a' || p == 'r'))) return null;
    final stem = x.substring(0, x.length - suf.length);
    final cands = <String>[
      stem,
      '${stem}e',
      if (stem.endsWith('i')) '${stem.substring(0, stem.length - 1)}y',
      if (stem.length > 2 && stem[stem.length - 1] == stem[stem.length - 2]) stem.substring(0, stem.length - 1),
    ];
    for (final c in cands) {
      if (c.length >= 2 && g.posOfLemma(c).contains('a')) return c;
    }
    return null;
  }

  // -------------------------------------------------------- reported speech

  void _reported(List<GMark> out) {
    for (final v in groups) {
      if (v.kind == 'imperative' || v.passive) continue;
      final i = v.last;
      final lem = g.lemmas(w[i]);
      final verb = lem.where(_reportVerbs.contains).firstOrNull;
      if (verb == null) continue;
      if (quoteBefore(i) || (i + 1 < e && (quoteBefore(i + 1) || cut(i + 1)))) continue;
      // Direct speech before the verb: "…," he said.
      if (RegExp(r'["”“]').hasMatch(text.substring(toks[s].start, toks[i].start))) continue;
      var j = i + 1;
      if (j >= e) continue;
      final obj = <int>[];
      if (_reportObj.contains(verb) && (_objPron.contains(w[j]) || isName(j)) && j + 1 < e && !cut(j + 1)) {
        obj.add(j);
        j++;
      }
      final n1 = w[j];
      String? kind;
      var mark = [...v.toks, ...obj];
      if (n1 == 'that' &&
          j + 1 < e &&
          !cut(j + 1) &&
          (_subjOnly.contains(w[j + 1]) ||
              _subjMaybe.contains(w[j + 1]) ||
              _det.contains(w[j + 1]) ||
              isName(j + 1) ||
              subjInside(j + 1) ||
              g._isNounish(w[j + 1]) && groups.any((x) => x.first > j + 1 && x.first <= j + 4))) {
        kind = 'rep_statement';
        mark.add(j);
      } else if ((n1 == 'if' || n1 == 'whether') && const {'ask', 'wonder', 'inquire', 'enquire', 'want'}.contains(verb)) {
        kind = 'rep_question';
        mark.add(j);
      } else if (_whWords.contains(n1) &&
          const {'ask', 'wonder', 'inquire', 'enquire', 'tell', 'explain'}.contains(verb) &&
          j + 1 < e &&
          (_subjOnly.contains(w[j + 1]) || _det.contains(w[j + 1]) || w[j + 1] == 'you' || w[j + 1] == 'it' || isName(j + 1) || subjInside(j + 1) || groups.any((x) => x.first == j + 1))) {
        kind = 'rep_question';
        mark.add(j);
      } else if (obj.isNotEmpty && n1 == 'to' && j + 1 < e && g._isBase(w[j + 1]) && const {'tell', 'ask', 'order', 'warn', 'advise', 'beg', 'command', 'urge', 'remind'}.contains(verb)) {
        kind = 'rep_command';
        mark.addAll([j, j + 1]);
      } else if (n1 != 'to' &&
          (verb == 'say' || verb == 'tell' && obj.isNotEmpty || verb == 'explain' || verb == 'claim' || verb == 'admit' || verb == 'promise' || verb == 'insist') &&
          (_subjOnly.contains(n1) || subjInside(j)) &&
          groups.any((x) => x.first == j || x.first == j + 1 || x.toks.contains(j))) {
        kind = 'rep_statement'; // "He said he was tired" ("that" left out)
      }
      if (kind == null) continue;
      // The tense inside the reported clause, to explain the backshift.
      final inner = groups.where((x) => x.first > mark.last && x.first <= mark.last + 6 && x.first < boundaryAfter(mark.last)).firstOrNull;
      Tx? shift;
      if (inner != null && inner.isTense && _backshift.containsKey(inner.kind) && v.tone == 1) {
        final b = _backshift[inner.kind]!;
        final t = _tenses[inner.kind]!;
        shift = (
          'Aktarılan cümlede ${t.en} ("${words(inner.toks)}"): konuşmacının kendi sözünde büyük olasılıkla ${b.$1} idi. Aktarırken zaman bir adım geçmişe kayar.',
          'The reported clause is in the ${t.en} ("${words(inner.toks)}"); the speaker most likely said it in the ${b.$2}. Reporting moves the tense one step back.',
        );
      } else if (inner != null && inner.kind == 'modal' && const {'would', 'could', 'might'}.contains(inner.modal) && v.tone == 1) {
        final orig = switch (inner.modal) {
          'would' => 'will',
          'could' => 'can',
          _ => 'may',
        };
        shift = ('Aktarılan cümlede "${inner.modal}": konuşmacı büyük olasılıkla "$orig" demişti.', 'The reported clause has "${inner.modal}": the speaker most likely said "$orig".');
      }
      if (kind == 'rep_question' && v.tone != 1) kind = 'indirect_question'; // "I wonder if …", "Can you tell me where …"
      final info = _repInfo[kind]!;
      mark = mark.toSet().toList()..sort();
      out.add(
        GMark(
          'g_reported',
          kind,
          mark,
          kind == 'indirect_question'
              ? const ['indirect_questions']
              : kind == 'rep_question'
              ? const ['reported_speech', 'indirect_questions']
              : const ['reported_speech'],
          info.$1,
          info.$2,
          info.$3,
          note: shift,
        ),
      );
    }
  }
}

extension on _VG {
  int get tone => isTense ? _tenses[kind]!.tone : -1;
}

/// The tense a speaker most likely used, for each backshifted tense.
const _backshift = <String, (String, String)>{
  'simple_past': ('Simple Present ya da Simple Past', 'Simple Present or the Simple Past'),
  'past_continuous': ('Present Continuous', 'Present Continuous'),
  'past_perfect': ('Present Perfect ya da Simple Past', 'Present Perfect or the Simple Past'),
  'past_perfect_continuous': ('Present Perfect Continuous', 'Present Perfect Continuous'),
  'was_going_to': ('am / is / are going to', 'am / is / are going to'),
};

/// Past modals: (Turkish name, Turkish, English explanation).
const _pastModalInfo = <String, (String, String, String)>{
  'should': (
    'Yapmalıydı (eleştiri / pişmanlık)',
    'should have + V3: geçmişte yapılması doğru olan ama yapılmayan şey; eleştiri ya da pişmanlık (You should have told me = bana söylemeliydin).',
    'should have + V3: the right thing to do in the past, which was not done; criticism or regret (You should have told me).',
  ),
  'should_not': (
    'Yapmamalıydı',
    "shouldn't have + V3: geçmişte yapılan ama yapılmaması gereken şey (I shouldn't have said that = bunu söylememeliydim).",
    "shouldn't have + V3: something done in the past that was a mistake (I shouldn't have said that).",
  ),
  'ought': ('Yapmalıydı', 'ought to have + V3: should have gibi; yapılması gereken ama yapılmayan şey.', 'ought to have + V3: like should have; the right thing that was not done.'),
  'could': (
    'Yapabilirdi / olmuş olabilir',
    'could have + V3: iki anlamı var: (1) geçmişte mümkündü ama olmadı (You could have died = ölebilirdin); (2) olmuş olabilir, emin değiliz (He could have taken it = o almış olabilir).',
    'could have + V3: two meanings: (1) it was possible but did not happen (You could have died); (2) it may have happened, we are not sure (He could have taken it).',
  ),
  'could_not': (
    'Olmuş olamaz / yapamazdı',
    "couldn't have + V3: kesin olumsuz çıkarım, geçmişte olmuş olması imkânsız (She couldn't have seen us = bizi görmüş olamaz).",
    "couldn't have + V3: a sure negative deduction, it is impossible that it happened (She couldn't have seen us).",
  ),
  'can_not': (
    'Olmuş olamaz',
    "can't have + V3: geçmiş hakkında kesin olumsuz tahmin (He can't have forgotten = unutmuş olamaz).",
    "can't have + V3: a sure negative deduction about the past (He can't have forgotten).",
  ),
  'must': (
    '-mış olmalı (güçlü tahmin)',
    'must have + V3: geçmiş hakkında güçlü tahmin, kanıta dayanan çıkarım (He must have left = gitmiş olmalı).',
    'must have + V3: a strong deduction about the past, based on evidence (He must have left).',
  ),
  'might': (
    'Belki -mıştır',
    'might have + V3: geçmişte belki olmuştur, emin değiliz; ya da olabilirdi ama olmadı (It might have been him = belki oydu).',
    'might have + V3: perhaps it happened, we are not sure; or it was possible but did not happen (It might have been him).',
  ),
  'might_not': (
    'Belki -mamıştır',
    "might not have + V3: belki olmamıştır (She might not have heard = belki duymamıştır).",
    "might not have + V3: perhaps it did not happen (She might not have heard).",
  ),
  'may': (
    'Belki -mıştır',
    'may have + V3: geçmişte belki olmuştur (They may have missed the train = treni kaçırmış olabilirler).',
    'may have + V3: perhaps it happened (They may have missed the train).',
  ),
  'may_not': ('Belki -mamıştır', 'may not have + V3: belki olmamıştır.', 'may not have + V3: perhaps it did not happen.'),
  'would': (
    'Yapardı (gerçekleşmemiş)',
    'would have + V3: geçmişte olmamış bir durumun hayalî sonucu; çoğu zaman 3. tip koşulun sonuç kısmıdır (I would have helped = yardım ederdim).',
    'would have + V3: the imagined result of something that did not happen; often the result part of a third conditional (I would have helped).',
  ),
  'would_not': (
    'Yapmazdı (gerçekleşmemiş)',
    "wouldn't have + V3: olmamış bir durumda yapılmayacak olan (I wouldn't have gone = gitmezdim).",
    "wouldn't have + V3: what would not have happened in an imagined past (I wouldn't have gone).",
  ),
};

class _CondInfo {
  final String en, tr, exTr, exEn, lesson;
  const _CondInfo(this.en, this.tr, this.exTr, this.exEn, this.lesson);
}

const _condInfo = <String, _CondInfo>{
  'cond_0': _CondInfo(
    'Zero Conditional',
    '0. tip koşul (genel doğru)',
    'If + Simple Present, Simple Present: koşul her gerçekleştiğinde sonuç da gerçekleşir (genel doğrular, kurallar).',
    'If + Simple Present, Simple Present: whenever the condition happens, the result happens (facts, rules).',
    'zero_conditional',
  ),
  'cond_1': _CondInfo(
    'First Conditional',
    '1. tip koşul (gerçek olasılık)',
    'If + Simple Present, will / can / emir + V1: gelecekte gerçekleşmesi olası bir koşul ve sonucu. If-cümlesinde will kullanılmaz.',
    'If + Simple Present, will / can / imperative + V1: a real possibility in the future and its result. No "will" in the if-clause.',
    'first_conditional',
  ),
  'cond_2': _CondInfo(
    'Second Conditional',
    '2. tip koşul (şimdiki / gelecek varsayım)',
    'If + V2 (were), would / could + V1: şu an ya da gelecekte gerçek olmayan, hayalî durum. Zaman geçmiş görünür ama anlam şimdidir.',
    'If + V2 (were), would / could + V1: an unreal or imagined present or future. The verb looks past but the meaning is present.',
    'second_conditional',
  ),
  'cond_3': _CondInfo(
    'Third Conditional',
    '3. tip koşul (geçmişte gerçekleşmeyen)',
    'If + had V3, would / could have + V3: geçmişte olmamış bir şeyi ve onun olası sonucunu hayal eder (pişmanlık, eleştiri).',
    'If + had V3, would / could have + V3: imagines a past that did not happen and its result (regret, criticism).',
    'third_conditional',
  ),
  'cond_mixed_32': _CondInfo(
    'Mixed Conditional',
    'Karışık koşul (geçmiş → şimdi)',
    'If + had V3, would + V1: geçmişte olmayan bir şeyin şimdiki sonucu.',
    'If + had V3, would + V1: an unreal past with a result in the present.',
    'mixed_conditionals',
  ),
  'cond_mixed_23': _CondInfo(
    'Mixed Conditional',
    'Karışık koşul (şimdi → geçmiş)',
    'If + V2, would have + V3: şimdi gerçek olmayan bir durumun geçmişteki sonucu.',
    'If + V2, would have + V3: an unreal present situation with a result in the past.',
    'mixed_conditionals',
  ),
};

const _relInfo = <String, Tx>{
  'who': (
    'who: insanlar için kullanılan ilgi zamiri (-en, -an kişi). Önündeki ismi niteleyen bir yan cümle başlatır.',
    'who: relative pronoun for people. It starts a clause that describes the noun before it.',
  ),
  'whom': (
    'whom: insanlar için, yan cümlenin nesnesi olduğunda (resmî). Günlük dilde çoğu zaman who ya da hiç kullanılmaz.',
    'whom: for people when they are the object of the clause (formal). In everyday English "who" or nothing is used.',
  ),
  'whose': ('whose: sahiplik bildirir (-in … olduğu): the man whose car was stolen = arabası çalınan adam.', 'whose: shows possession: the man whose car was stolen.'),
  'which': (
    'which: eşyalar, hayvanlar ve fikirler için ilgi zamiri. Virgülden sonra gelirse bazen bütün cümleyi niteler.',
    'which: relative pronoun for things, animals and ideas. After a comma it can describe the whole sentence.',
  ),
  'that': (
    'that: hem insanlar hem eşyalar için, yalnızca virgülsüz (defining) yan cümlelerde kullanılır. Nesne olduğunda düşebilir.',
    'that: for people and things, only in clauses with no commas (defining). It can be left out when it is the object.',
  ),
  'where': ('where: yer bildiren isimden sonra "-diği yer" anlamında yan cümle başlatır (= in which).', 'where: after a place noun it starts a clause meaning "the place in which".'),
  'when': (
    'when: zaman bildiren isimden sonra "-diği zaman" anlamında yan cümle başlatır (the day when we met).',
    'when: after a time noun it starts a clause meaning "the time at which" (the day when we met).',
  ),
};

const _repInfo = <String, (String, String, Tx)>{
  'rep_statement': (
    'Reported Speech (statement)',
    'Dolaylı anlatım (aktarılan söz)',
    (
      'Birinin sözünü tırnaksız aktarır: say / tell + (that) + cümle. Ana fiil geçmişteyse aktarılan cümlenin zamanı bir adım geçmişe kayar (am → was, will → would) ve zamirler değişir.',
      'Reports what someone said without quotation marks: say / tell + (that) + clause. When the reporting verb is past, the tense moves one step back (am → was, will → would) and pronouns change.',
    ),
  ),
  'rep_question': (
    'Reported Question',
    'Dolaylı soru',
    (
      'Soruyu aktarır: ask + if / whether (evet-hayır soruları) ya da soru kelimesi. Aktarılan soruda düz cümle sırası kullanılır (where he was, where was he değil) ve soru işareti konmaz.',
      'Reports a question: ask + if / whether (yes/no questions) or a question word. The reported question uses statement word order (where he was, not where was he) and no question mark.',
    ),
  ),
  'indirect_question': (
    'Indirect Question',
    'Dolaylı soru',
    (
      'Soruyu bir cümlenin içine yerleştirir: I wonder if …, Can you tell me where …? Soru kelimesinden sonra düz cümle sırası gelir (where the station is, where is the station değil).',
      'Puts a question inside a sentence: I wonder if …, Can you tell me where …? After the question word the order is that of a statement (where the station is, not where is the station).',
    ),
  ),
  'rep_command': (
    'Reported Command / Request',
    'Dolaylı emir / rica',
    (
      'Emri ya da ricayı aktarır: tell / ask + kişi + to V1 (olumsuzu: not to V1). "Bekle!" dedi → He told me to wait.',
      'Reports an order or request: tell / ask + person + to V1 (negative: not to V1). "Wait!" → He told me to wait.',
    ),
  ),
};
