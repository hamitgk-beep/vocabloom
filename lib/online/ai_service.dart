import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../data/user_db.dart';
import '../nlp/word_family.dart';
import '../l10n.dart';
import '../nlp/text.dart';

/// The kinds of HTTP API the providers speak.
enum ApiKind { anthropic, openai, gemini, azure }

class ProviderInfo {
  final String id;
  final String nameTr;
  final ApiKind kind;
  final String baseUrl; // for openai-compatible providers
  final String defaultModel;
  final bool needsKey;
  final bool vision;
  final String keyHelpTr;
  final String? nameEn, keyHelpEn;
  const ProviderInfo(this.id, this.nameTr, this.kind, this.baseUrl, this.defaultModel,
      {this.needsKey = true, this.vision = true, String keyHelp = '', this.nameEn, this.keyHelpEn}) : keyHelpTr = keyHelp;

  String get name => uiEnglish ? nameEn ?? nameTr : nameTr;
  String get keyHelp => uiEnglish ? keyHelpEn ?? keyHelpTr : keyHelpTr;
}

/// Supported AI services. Model names can be changed in the settings,
/// because every provider renames its models from time to time.
const providers = <ProviderInfo>[
  ProviderInfo('anthropic', 'Anthropic Claude', ApiKind.anthropic, 'https://api.anthropic.com', 'claude-opus-5-5',
      keyHelp: 'console.anthropic.com → API Keys'),
  ProviderInfo('openai', 'OpenAI ChatGPT', ApiKind.openai, 'https://api.openai.com/v1', 'gpt-4o-mini',
      keyHelp: 'platform.openai.com → API keys'),
  ProviderInfo('gemini', 'Google Gemini', ApiKind.gemini, 'https://generativelanguage.googleapis.com', 'gemini-flash-latest',
      keyHelp: 'aistudio.google.com → Get API key'),
  ProviderInfo('azure', 'Microsoft Copilot / Azure OpenAI', ApiKind.azure, '', 'gpt-4o-mini',
      keyHelp: 'Azure AI Foundry: uç nokta adresi + anahtar. Copilot uygulamasının kendisi geliştiricilere API sunmuyor; '
          'Microsoft\'un aynı modelleri Azure OpenAI üzerinden kullanılır.', keyHelpEn: 'Azure AI Foundry: endpoint address + key. The Copilot app itself offers no API to developers; '
          'Microsoft\'s same models are used through Azure OpenAI.'),
  ProviderInfo('deepseek', 'DeepSeek', ApiKind.openai, 'https://api.deepseek.com/v1', 'deepseek-chat',
      vision: false, keyHelp: 'platform.deepseek.com → API keys'),
  ProviderInfo('mistral', 'Mistral AI', ApiKind.openai, 'https://api.mistral.ai/v1', 'mistral-small-latest',
      keyHelp: 'console.mistral.ai → API Keys'),
  ProviderInfo('xai', 'xAI Grok', ApiKind.openai, 'https://api.x.ai/v1', 'grok-3-mini', vision: false, keyHelp: 'console.x.ai'),
  ProviderInfo('groq', 'Groq', ApiKind.openai, 'https://api.groq.com/openai/v1', 'llama-3.3-70b-versatile',
      vision: false, keyHelp: 'console.groq.com → API Keys'),
  ProviderInfo('openrouter', 'OpenRouter (yüzlerce model)', ApiKind.openai, 'https://openrouter.ai/api/v1', 'openrouter/auto',
      keyHelp: 'openrouter.ai → Keys', nameEn: 'OpenRouter (hundreds of models)'),
  ProviderInfo('ollama', 'Ollama (bilgisayarda yerel, internetsiz)', ApiKind.openai, 'http://localhost:11434/v1', 'llama3.2',
      needsKey: false, vision: false, keyHelp: 'ollama.com programını kur, ardından: ollama pull llama3.2', nameEn: 'Ollama (local on your computer, offline)', keyHelpEn: 'Install the ollama.com app, then run: ollama pull llama3.2'),
  ProviderInfo('custom', 'Diğer (OpenAI uyumlu adres)', ApiKind.openai, '', '', needsKey: false,
      keyHelp: 'OpenAI uyumlu herhangi bir servisin adresi, anahtarı ve model adı.', nameEn: 'Other (OpenAI-compatible address)', keyHelpEn: 'The address, key and model name of any OpenAI-compatible service.'),
];

final providerById = {for (final p in providers) p.id: p};

class AiConfig {
  final ProviderInfo provider;
  final String key;
  final String model;
  final String baseUrl;
  AiConfig(this.provider, this.key, this.model, this.baseUrl);
}

/// Settings are stored per provider so switching does not lose keys.
class AiSettings {
  static String? activeId(UserDb db) => db.getSetting('ai_provider') ?? (db.getSetting('api_key') != null ? 'anthropic' : null);

  static AiConfig? active(UserDb db) {
    final id = activeId(db);
    final p = id == null ? null : providerById[id];
    if (p == null) return null;
    final key = db.getSetting('ai_key_$id') ?? (id == 'anthropic' ? db.getSetting('api_key') : null) ?? '';
    final model = db.getSetting('ai_model_$id') ?? p.defaultModel;
    final base = db.getSetting('ai_url_$id') ?? p.baseUrl;
    if (p.needsKey && key.trim().isEmpty) return null;
    if (model.trim().isEmpty || (p.kind != ApiKind.anthropic && p.kind != ApiKind.gemini && base.trim().isEmpty)) return null;
    return AiConfig(p, key.trim(), model.trim(), base.trim());
  }
}

class AiService {
  final AiConfig cfg;
  AiService(this.cfg);

  static AiService? fromSettings(UserDb db) {
    final c = AiSettings.active(db);
    return c == null ? null : AiService(c);
  }

  String get label => '${cfg.provider.name} · ${cfg.model}';

  /// Whether the provider's server can be reached right now.
  Future<bool> reachable() async {
    try {
      final host = Uri.parse(_base()).host;
      if (host == 'localhost' || host == '127.0.0.1') {
        final s = await Socket.connect(host, Uri.parse(_base()).port, timeout: const Duration(seconds: 2));
        s.destroy();
        return true;
      }
      final r = await InternetAddress.lookup(host).timeout(const Duration(seconds: 4));
      return r.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  String _base() => switch (cfg.provider.kind) {
        ApiKind.anthropic => 'https://api.anthropic.com',
        ApiKind.gemini => 'https://generativelanguage.googleapis.com',
        _ => cfg.baseUrl,
      };

  static const _system =
      'You are a careful English-to-Turkish literary translator helping a Turkish reader learn English. '
      'Translate naturally and faithfully, keeping the meaning each sentence has in its context. '
      'Always answer with one JSON object only.';

  /// Sends [prompt] (and optionally an image) and returns the parsed JSON object.
  Future<Map<String, dynamic>> _json(String prompt, Map<String, dynamic> schema, {Uint8List? png, int maxTokens = 16000}) async {
    final text = await _send(prompt, schema, png: png, maxTokens: maxTokens);
    return _parseJson(text);
  }

  static Map<String, dynamic> _parseJson(String text) {
    var t = text.trim();
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(t);
    if (fence != null) t = fence.group(1)!.trim();
    final start = t.indexOf('{'), end = t.lastIndexOf('}');
    if (start < 0 || end < start) throw Exception(L('Yapay zekâ geçerli JSON döndürmedi.', 'The AI did not return valid JSON.'));
    return jsonDecode(t.substring(start, end + 1)) as Map<String, dynamic>;
  }

  Future<String> _send(String prompt, Map<String, dynamic> schema, {Uint8List? png, int maxTokens = 16000}) async {
    final kind = cfg.provider.kind;
    late Uri url;
    final headers = <String, String>{'content-type': 'application/json'};
    late Map<String, dynamic> body;
    final img = png == null ? null : base64Encode(png);
    switch (kind) {
      case ApiKind.anthropic:
        // Claude through its own Messages API (there is no official Dart SDK).
        url = Uri.parse('https://api.anthropic.com/v1/messages');
        headers['x-api-key'] = cfg.key;
        headers['anthropic-version'] = '2026-10-21';
        body = {
          'model': cfg.model,
          'max_tokens': maxTokens,
          'system': _system,
          'output_config': {
            'effort': 'low',
            'format': {'type': 'json_schema', 'schema': schema},
          },
          'messages': [
            {
              'role': 'user',
              'content': [
                if (img != null) {'type': 'image', 'source': {'type': 'base64', 'media_type': 'image/png', 'data': img}},
                {'type': 'text', 'text': prompt},
              ],
            }
          ],
        };
        if (!cfg.model.startsWith('claude-haiku')) {
          body['fallbacks'] = 'default';
          headers['anthropic-beta'] = 'server-side-fallback-2026-07-01';
        }
      case ApiKind.gemini:
        url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/${cfg.model}:generateContent');
        headers['x-goog-api-key'] = cfg.key;
        body = {
          'systemInstruction': {
            'parts': [
              {'text': _system}
            ]
          },
          'contents': [
            {
              'role': 'user',
              'parts': [
                if (img != null) {'inline_data': {'mime_type': 'image/png', 'data': img}},
                {'text': prompt},
              ],
            }
          ],
          'generationConfig': {'responseMimeType': 'application/json', 'maxOutputTokens': maxTokens},
        };
      case ApiKind.openai:
      case ApiKind.azure:
        if (kind == ApiKind.azure) {
          // https://<resource>.openai.azure.com  (deployment name = model)
          final base = cfg.baseUrl.replaceAll(RegExp(r'/+$'), '');
          url = Uri.parse('$base/openai/deployments/${cfg.model}/chat/completions?api-version=2024-10-21');
          headers['api-key'] = cfg.key;
        } else {
          url = Uri.parse('${cfg.baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions');
          if (cfg.key.isNotEmpty) headers['authorization'] = 'Bearer ${cfg.key}';
        }
        body = {
          if (kind == ApiKind.openai) 'model': cfg.model,
          'messages': [
            {'role': 'system', 'content': _system},
            {
              'role': 'user',
              'content': img == null
                  ? prompt
                  : [
                      {'type': 'image_url', 'image_url': {'url': 'data:image/png;base64,$img'}},
                      {'type': 'text', 'text': prompt},
                    ],
            },
          ],
          'response_format': {'type': 'json_object'},
          'max_tokens': maxTokens,
        };
    }
    // Busy (503/529) or rate-limited (429): wait a little and try again.
    var res = await http.post(url, headers: headers, body: jsonEncode(body)).timeout(const Duration(minutes: 5));
    for (final wait in const [3, 8, 20]) {
      if (res.statusCode != 503 && res.statusCode != 529 && res.statusCode != 429) break;
      await Future<void>.delayed(Duration(seconds: wait));
      res = await http.post(url, headers: headers, body: jsonEncode(body)).timeout(const Duration(minutes: 5));
    }
    final raw = utf8.decode(res.bodyBytes);
    Map<String, dynamic>? data;
    try {
      data = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {}
    if (res.statusCode != 200 || data == null) {
      final err = data?['error'];
      final msg = err is Map ? err['message'] : (err ?? raw);
      final hint = switch (res.statusCode) {
        400 when '$msg'.toLowerCase().contains('api key') => L(' (Anahtar geçersiz görünüyor; kopyalarken eksik/boşluk kalmış olabilir.)', ' (The key looks invalid; part of it may be missing or have extra spaces from copying.)'),
        401 || 403 => L(' (Anahtar geçersiz ya da bu servise yetkisi yok.)', ' (The key is invalid or has no access to this service.)'),
        404 => L(' (Model adı bulunamadı; model kutusunu değiştirip tekrar deneyin.)', ' (Model name not found; change the model box and try again.)'),
        429 => L(' (Kullanım sınırına takıldı; ücretsiz planda biraz bekleyip tekrar deneyin.)', ' (Usage limit reached; on the free plan, wait a bit and try again.)'),
        503 || 529 => L(' (Anahtarın çalışıyor, ama model şu an çok yoğun. Biraz sonra tekrar deneyin ya da model adını değiştirin, ör. gemini-flash-lite-latest.)', ' (Your key works, but the model is very busy right now. Try again a bit later or change the model name, e.g. gemini-flash-lite-latest.)'),
        _ => '',
      };
      throw Exception(L('${cfg.provider.name} hatası (${res.statusCode}): $msg$hint', '${cfg.provider.name} error (${res.statusCode}): $msg$hint'));
    }
    switch (kind) {
      case ApiKind.anthropic:
        if (data['stop_reason'] == 'refusal') throw Exception(L('İstek model tarafından reddedildi.', 'The request was refused by the model.'));
        if (data['stop_reason'] == 'max_tokens') throw Exception(L('Yanıt çok uzun olduğu için kesildi.', 'The answer was cut off because it was too long.'));
        return (data['content'] as List).whereType<Map>().where((b) => b['type'] == 'text').map((b) => b['text'] as String).join();
      case ApiKind.gemini:
        final c = (data['candidates'] as List?)?.firstOrNull as Map?;
        final parts = ((c?['content'] as Map?)?['parts'] as List?) ?? const [];
        return parts.whereType<Map>().map((p) => p['text'] ?? '').join();
      case ApiKind.openai:
      case ApiKind.azure:
        final ch = (data['choices'] as List).first as Map;
        if (ch['finish_reason'] == 'length') throw Exception(L('Yanıt çok uzun olduğu için kesildi.', 'The answer was cut off because it was too long.'));
        return ((ch['message'] as Map)['content'] ?? '') as String;
    }
  }

  /// Translates numbered sentences; also returns a short Turkish summary.
  Future<({List<String> translations, String summary})> translateChunk(List<String> sentences) async {
    final numbered = [for (var i = 0; i < sentences.length; i++) '[$i] ${sentences[i]}'].join('\n');
    final r = await _json(
      'Below are ${sentences.length} consecutive sentences from a book, numbered from 0. '
      'Return JSON {"translations": [...], "summary": "..."} where "translations" has exactly ${sentences.length} '
      'Turkish translations in the same order, one per number (translate headings too), and "summary" is 2-4 Turkish '
      'sentences that summarise what this passage tells.\n\n$numbered',
      {
        'type': 'object',
        'properties': {
          'translations': {'type': 'array', 'items': {'type': 'string'}},
          'summary': {'type': 'string'},
        },
        'required': ['translations', 'summary'],
        'additionalProperties': false,
      },
    );
    return (translations: (r['translations'] as List).map((e) => '$e').toList(), summary: '${r['summary'] ?? ''}');
  }

  /// Turkish meanings for dictionary expressions that only have English
  /// definitions. Returns one (meaning, explanation) per input, in order.
  Future<List<({String tr, String exp})>> translateExprs(List<({String phrase, String cat, String en})> items) async {
    final numbered = [
      for (var i = 0; i < items.length; i++) '[$i] ${items[i].phrase} (${items[i].cat.replaceAll('_', ' ')}): ${items[i].en}'
    ].join('\n');
    final r = await _json(
      'Below are ${items.length} English dictionary entries for Turkish learners of English, numbered from 0, '
      'each with its category and English definition(s). Return JSON {"items": [...]} with exactly ${items.length} '
      'objects in the same order. For each: "tr" is the Turkish meaning as a short dictionary-style equivalent '
      '(a few words, or the matching Turkish idiom/proverb if one exists; separate different senses with "; "), and '
      '"exp" is a Turkish translation of the English definition(s), one or two short sentences.\n\n$numbered',
      {
        'type': 'object',
        'properties': {
          'items': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'tr': {'type': 'string'},
                'exp': {'type': 'string'},
              },
              'required': ['tr', 'exp'],
              'additionalProperties': false,
            },
          },
        },
        'required': ['items'],
        'additionalProperties': false,
      },
    );
    return [
      for (final x in (r['items'] as List? ?? const []))
        (tr: '${(x as Map)['tr'] ?? ''}'.trim(), exp: '${x['exp'] ?? ''}'.trim())
    ];
  }

  /// Detailed meanings of an expression (phrasal verb, idiom ...) for a learner:
  /// each sense in English and Turkish with example sentences and translations.
  Future<List<ExprSense>> exprDetail(String phrase, String category, {String? sentence}) async {
    final r = await _json(
      'Explain the English ${category.replaceAll('_', ' ')} "$phrase" for a Turkish learner of English. '
      '${sentence == null ? '' : 'It appears in this sentence: "$sentence". Put the sense used there first. '}'
      'Return JSON {"senses": [...]} with its common senses (at most 4). For each sense: "title_en" (short English '
      'heading), "title_tr" (Turkish heading, e.g. "Uzman veya yardım çağırmak"), "explain_en" (one English sentence '
      'on when it is used), "explain_tr" (the same in Turkish), "examples": 2 objects {"en": natural English example '
      'sentence, "tr": its Turkish translation}. "in_sentence": true only for the sense used in the given sentence.',
      {
        'type': 'object',
        'properties': {
          'senses': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'title_en': {'type': 'string'},
                'title_tr': {'type': 'string'},
                'explain_en': {'type': 'string'},
                'explain_tr': {'type': 'string'},
                'in_sentence': {'type': 'boolean'},
                'examples': {
                  'type': 'array',
                  'items': {
                    'type': 'object',
                    'properties': {'en': {'type': 'string'}, 'tr': {'type': 'string'}},
                    'required': ['en', 'tr'],
                    'additionalProperties': false,
                  },
                },
              },
              'required': ['title_en', 'title_tr', 'explain_en', 'explain_tr', 'in_sentence', 'examples'],
              'additionalProperties': false,
            },
          },
        },
        'required': ['senses'],
        'additionalProperties': false,
      },
      maxTokens: 4000,
    );
    return [for (final s in (r['senses'] as List? ?? const [])) ExprSense.fromJson((s as Map).cast<String, dynamic>())];
  }

  /// Word family (root, verb/noun/adjective/adverb forms, negatives) with
  /// Turkish meanings and what each affix does.
  Future<WordFamily> wordFamily(String word) async {
    final r = await _json(
      'For Turkish learners of English, give the word family of "$word". Return JSON with: "root" (the base word), '
      '"root_tr" (its Turkish meaning), and "entries": the common English words built from the same root, including '
      'the root itself, grouped by part of speech. For each entry: "word"; "pos" (verb, noun, adjective or adverb); '
      '"tr" (short Turkish meaning); "affix" (the prefix or suffix added, like "-tion" or "un-", or "" for the root); '
      '"note" (in Turkish, one short sentence on how the affix changes the meaning, e.g. "-er eki işi yapan kişiyi '
      'gösterir"); "negative" (true for negative/opposite forms like unhappy, disagree). Only include real, '
      'reasonably common words; at most 14 entries.',
      {
        'type': 'object',
        'properties': {
          'root': {'type': 'string'},
          'root_tr': {'type': 'string'},
          'entries': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'word': {'type': 'string'},
                'pos': {'type': 'string', 'enum': ['verb', 'noun', 'adjective', 'adverb']},
                'tr': {'type': 'string'},
                'affix': {'type': 'string'},
                'note': {'type': 'string'},
                'negative': {'type': 'boolean'},
              },
              'required': ['word', 'pos', 'tr', 'affix', 'note', 'negative'],
              'additionalProperties': false,
            },
          },
        },
        'required': ['root', 'root_tr', 'entries'],
        'additionalProperties': false,
      },
      maxTokens: 4000,
    );
    const posMap = {'verb': 'v', 'noun': 'n', 'adjective': 'a', 'adverb': 'r'};
    return WordFamily('${r['root']}', '${r['root_tr'] ?? ''}', [
      for (final e in (r['entries'] as List? ?? const []))
        FamilyEntry('${(e as Map)['word']}', posMap['${e['pos']}'] ?? 'n',
            tr: '${e['tr'] ?? ''}',
            affixNote: '${e['affix'] ?? ''}'.isEmpty ? null : '${e['affix']}: ${e['note'] ?? ''}',
            negative: e['negative'] == true),
    ], fromAi: true);
  }

  /// Translation plus a Turkish breakdown of one sentence (used on demand).
  Future<({String translation, String explanation, String explanationEn})> explainSentence(String sentence, String context) async {
    final r = await _json(
      'Context paragraph:\n$context\n\nSentence:\n$sentence\n\n'
      'Return JSON {"translation": "...", "explanation": "...", "explanation_en": "..."}: "translation" is a natural '
      'Turkish translation of the sentence; "explanation" is, in Turkish, a short breakdown for a learner: the tense(s) '
      'used, conjunctions, phrasal verbs, idioms and other notable patterns, and what any hard words mean here; '
      '"explanation_en" is the same breakdown in simple English.',
      {
        'type': 'object',
        'properties': {
          'translation': {'type': 'string'},
          'explanation': {'type': 'string'},
          'explanation_en': {'type': 'string'},
        },
        'required': ['translation', 'explanation', 'explanation_en'],
        'additionalProperties': false,
      },
      maxTokens: 4000,
    );
    return (
      translation: '${r['translation']}',
      explanation: '${r['explanation']}',
      explanationEn: '${r['explanation_en'] ?? ''}',
    );
  }

  /// Reads the text of a scanned page image (online OCR).
  Future<String> ocrPage(Uint8List png) async {
    if (!cfg.provider.vision) throw Exception(L('${cfg.provider.name} resimdeki metni okuyamıyor.', '${cfg.provider.name} cannot read text in images.'));
    final r = await _json(
      'This is a scanned page of an English book. Transcribe the book text exactly as printed, in reading order. '
      'Separate paragraphs with a blank line. Leave out page numbers, running headers and text inside pictures. '
      'Return JSON {"text": "..."}; use an empty string if the page has no book text.',
      {
        'type': 'object',
        'properties': {'text': {'type': 'string'}},
        'required': ['text'],
        'additionalProperties': false,
      },
      png: png,
      maxTokens: 8000,
    );
    return '${r['text'] ?? ''}';
  }
}

/// One sense of an expression, from [AiService.exprDetail].
class ExprSense {
  final String titleEn, titleTr, explainEn, explainTr;
  /// Part of speech in English ("verb", "noun"...), for word explanations.
  final String? pos;
  final bool inSentence;
  final List<(String, String)> examples;
  ExprSense(this.titleEn, this.titleTr, this.explainEn, this.explainTr, this.inSentence, this.examples, {this.pos});

  factory ExprSense.fromJson(Map<String, dynamic> j) => ExprSense(
        '${j['title_en'] ?? ''}',
        '${j['title_tr'] ?? ''}',
        '${j['explain_en'] ?? ''}',
        '${j['explain_tr'] ?? ''}',
        j['in_sentence'] == true,
        [for (final e in (j['examples'] as List? ?? const [])) ('${(e as Map)['en'] ?? ''}', '${e['tr'] ?? ''}')],
        pos: j['pos'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'title_en': titleEn,
        'title_tr': titleTr,
        'explain_en': explainEn,
        'explain_tr': explainTr,
        'in_sentence': inSentence,
        'examples': [for (final e in examples) {'en': e.$1, 'tr': e.$2}],
      };
}

/// Runs the online analysis for a whole book and saves the results. Already
/// translated paragraphs are skipped, so it can resume at any time.
Future<void> analyzeBook(AiService svc, UserDb db, int bookId,
    {void Function(int done, int total)? onProgress, bool Function()? cancelled}) async {
  final chapters = db.chapters(bookId);
  final total = db.parasMissingTranslation(bookId).length;
  var done = 0;
  for (final ch in chapters) {
    final paras = db.paras(bookId, ch.idx).where((p) => db.paraTranslation(p.id) == null).toList();
    final summaries = <String>[if (ch.summary != null) ch.summary!];
    var i = 0;
    while (i < paras.length) {
      if (cancelled?.call() == true) return;
      final batch = <Para>[];
      var words = 0;
      while (i < paras.length && (batch.isEmpty || words < 2000)) {
        batch.add(paras[i]);
        words += paras[i].text.split(' ').length;
        i++;
      }
      final sentences = <String>[];
      final counts = <int>[];
      for (final p in batch) {
        final s = sentenceRanges(p.text).map((r) => p.text.substring(r.$1, r.$2).trim()).toList();
        counts.add(s.length);
        sentences.addAll(s);
      }
      final r = await svc.translateChunk(sentences);
      var k = 0;
      for (var b = 0; b < batch.length; b++) {
        final tr = <String>[];
        for (var c = 0; c < counts[b]; c++) {
          tr.add(k < r.translations.length ? r.translations[k] : '');
          k++;
        }
        db.setParaTranslation(batch[b].id, tr);
      }
      if (r.summary.isNotEmpty) summaries.add(r.summary);
      done += batch.length;
      onProgress?.call(done, total);
    }
    if (summaries.isNotEmpty) db.setChapterSummary(bookId, ch.idx, summaries.join(' '));
  }
  db.db.execute('UPDATE books SET analyzed=1 WHERE id=?', [bookId]);
}
