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
  ProviderInfo('gemini', 'Google Gemini', ApiKind.gemini, 'https://generativelanguage.googleapis.com', 'gemini-flash-lite-latest',
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

/// Models earlier versions used as their default, per provider.
const legacyDefaults = {
  'gemini': {'gemini-flash-latest', 'gemini-2.5-flash'},
};

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
    var model = db.getSetting('ai_model_$id') ?? p.defaultModel;
    // Earlier versions saved their default model with the key; the old Gemini
    // default (a slow "thinking" model) is replaced by the current one.
    if (legacyDefaults[id]?.contains(model.trim()) ?? false) model = p.defaultModel;
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

  /// A conversation in plain text (no JSON): the tutor's answers in the
  /// reading panels, the grammar practice and the chat. [history] is
  /// (role, text) with role 'user' or 'assistant', the last one the user's.
  Future<String> chat(String system, List<(String, String)> history, {int maxTokens = 1500}) =>
      _send('', null, maxTokens: maxTokens, system: system, history: history);

  ({Uri url, Map<String, String> headers, Map<String, dynamic> body}) _request(String prompt, Map<String, dynamic>? schema,
      {Uint8List? png, int maxTokens = 16000, String? system, List<(String, String)>? history, bool stream = false, bool think = true}) {
    final kind = cfg.provider.kind;
    final sys = system ?? _system;
    final turns = history ?? [('user', prompt)];
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
          'system': sys,
          'output_config': {
            'effort': 'low',
            if (schema != null) 'format': {'type': 'json_schema', 'schema': schema},
          },
          'messages': [
            for (final (role, text) in turns)
              {
                'role': role == 'assistant' ? 'assistant' : 'user',
                'content': [
                  if (img != null && history == null) {'type': 'image', 'source': {'type': 'base64', 'media_type': 'image/png', 'data': img}},
                  {'type': 'text', 'text': text},
                ],
              }
          ],
        };
        if (!cfg.model.startsWith('claude-haiku')) {
          body['fallbacks'] = 'default';
          headers['anthropic-beta'] = 'server-side-fallback-2026-07-01';
        }
      case ApiKind.gemini:
        url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/${cfg.model}:${stream ? 'streamGenerateContent?alt=sse' : 'generateContent'}');
        headers['x-goog-api-key'] = cfg.key;
        body = {
          'systemInstruction': {
            'parts': [
              {'text': sys}
            ]
          },
          'contents': [
            for (final (role, text) in turns)
              {
                'role': role == 'assistant' ? 'model' : 'user',
                'parts': [
                  if (img != null && history == null) {'inline_data': {'mime_type': 'image/png', 'data': img}},
                  {'text': text},
                ],
              }
          ],
          'generationConfig': {
            if (schema != null) 'responseMimeType': 'application/json',
            'maxOutputTokens': maxTokens,
            // A chat answer needs no long hidden reasoning: it is what made
            // answers take most of a minute on the "thinking" Flash models.
            if (!think) 'thinkingConfig': geminiQuickThinking(cfg.model),
          },
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
            {'role': 'system', 'content': sys},
            if (history != null)
              for (final (role, text) in history) {'role': role == 'assistant' ? 'assistant' : 'user', 'content': text}
            else
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
          if (schema != null) 'response_format': {'type': 'json_object'},
          'max_tokens': maxTokens,
          if (stream) 'stream': true,
        };
    }
    if (stream && kind == ApiKind.anthropic) body['stream'] = true;
    return (url: url, headers: headers, body: body);
  }

  Future<String> _send(String prompt, Map<String, dynamic>? schema,
      {Uint8List? png, int maxTokens = 16000, String? system, List<(String, String)>? history}) async {
    final kind = cfg.provider.kind;
    final (:url, :headers, :body) = _request(prompt, schema, png: png, maxTokens: maxTokens, system: system, history: history);

    // Busy (503/529) or rate-limited (429): wait a little and try again.
    // A chat answer is short: do not let one request hang the learner.
    final limit = history != null ? const Duration(seconds: 60) : const Duration(minutes: 5);
    var res = await http.post(url, headers: headers, body: jsonEncode(body)).timeout(limit);
    // A learner waiting for a chat answer gets one quick retry; the error
    // (busy, limit reached) is better than a long silent wait.
    for (final wait in history != null ? const [3] : const [3, 8, 20]) {
      if (res.statusCode != 503 && res.statusCode != 529 && res.statusCode != 429) break;
      await Future<void>.delayed(Duration(seconds: wait));
      res = await http.post(url, headers: headers, body: jsonEncode(body)).timeout(limit);
    }
    final raw = utf8.decode(res.bodyBytes);
    Map<String, dynamic>? data;
    try {
      data = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {}
    if (res.statusCode != 200 || data == null) throw _error(res.statusCode, raw, data);
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

  Exception _error(int status, String raw, Map<String, dynamic>? data) {
    final err = data?['error'];
    final msg = err is Map ? err['message'] : (err ?? raw);
    final hint = switch (status) {
      400 when '$msg'.toLowerCase().contains('api key') => L(' (Anahtar geçersiz görünüyor; kopyalarken eksik/boşluk kalmış olabilir.)', ' (The key looks invalid; part of it may be missing or have extra spaces from copying.)'),
      401 || 403 => L(' (Anahtar geçersiz ya da bu servise yetkisi yok.)', ' (The key is invalid or has no access to this service.)'),
      404 => L(' (Model adı bulunamadı; model kutusunu değiştirip tekrar deneyin.)', ' (Model name not found; change the model box and try again.)'),
      429 => L(' (Kullanım sınırına takıldı; ücretsiz planda biraz bekleyip tekrar deneyin.)', ' (Usage limit reached; on the free plan, wait a bit and try again.)'),
      503 || 529 => L(' (Anahtarın çalışıyor, ama model şu an çok yoğun. Biraz sonra tekrar deneyin ya da model adını değiştirin, ör. gemini-flash-lite-latest.)', ' (Your key works, but the model is very busy right now. Try again a bit later or change the model name, e.g. gemini-flash-lite-latest.)'),
      _ => '',
    };
    return Exception(L('${cfg.provider.name} hatası ($status): $msg$hint', '${cfg.provider.name} error ($status): $msg$hint'));
  }

  /// A chat answer as it is written, piece by piece, so the first words show
  /// within a second or two instead of after the whole answer. [history] is
  /// as in [chat]. Hidden reasoning ("thinking") is kept short or off.
  Stream<String> chatStream(String system, List<(String, String)> history, {int maxTokens = 1500}) async* {
    final kind = cfg.provider.kind;
    var think = kind != ApiKind.gemini;
    var tries = 0;
    while (true) {
      final (:url, :headers, :body) = _request('', null, maxTokens: maxTokens, system: system, history: history, stream: true, think: think);
      final client = http.Client();
      try {
        final req = http.Request('POST', url)
          ..headers.addAll(headers)
          ..body = jsonEncode(body);
        final res = await client.send(req).timeout(const Duration(seconds: 30));
        if (res.statusCode != 200) {
          final raw = await res.stream.bytesToString();
          Map<String, dynamic>? data;
          try {
            final j = jsonDecode(raw);
            data = j is List ? (j.firstOrNull as Map<String, dynamic>?) : j as Map<String, dynamic>;
          } catch (_) {}
          // A model that cannot switch its thinking off: ask again without the setting.
          if (!think && res.statusCode == 400 && raw.toLowerCase().contains('think')) {
            think = true;
            continue;
          }
          // Busy or rate-limited: one quick retry.
          if ((res.statusCode == 503 || res.statusCode == 529 || res.statusCode == 429) && tries++ == 0) {
            await Future<void>.delayed(const Duration(seconds: 2));
            continue;
          }
          throw _error(res.statusCode, raw, data);
        }
        var cut = false;
        await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
          if (!line.startsWith('data:')) continue;
          final payload = line.substring(5).trim();
          if (payload.isEmpty || payload == '[DONE]') continue;
          final Map<String, dynamic> d;
          try {
            d = jsonDecode(payload) as Map<String, dynamic>;
          } catch (_) {
            continue;
          }
          if (d['error'] != null) throw _error(500, payload, d);
          switch (kind) {
            case ApiKind.anthropic:
              final delta = d['delta'];
              if (d['type'] == 'content_block_delta' && delta is Map && delta['type'] == 'text_delta') yield '${delta['text'] ?? ''}';
              if (d['type'] == 'message_delta' && delta is Map && delta['stop_reason'] == 'max_tokens') cut = true;
            case ApiKind.gemini:
              final c = (d['candidates'] as List?)?.firstOrNull as Map?;
              for (final p in ((c?['content'] as Map?)?['parts'] as List?) ?? const []) {
                if (p is Map && p['thought'] != true && p['text'] is String) yield p['text'] as String;
              }
            case ApiKind.openai:
            case ApiKind.azure:
              final ch = (d['choices'] as List?)?.firstOrNull as Map?;
              final t = (ch?['delta'] as Map?)?['content'];
              if (t is String) yield t;
              if (ch?['finish_reason'] == 'length') cut = true;
          }
        }
        if (cut) yield '…';
        return;
      } finally {
        client.close();
      }
    }
  }

  /// Translates numbered sentences; also returns a short Turkish summary.
  /// Each translation comes back with its sentence's number, so a model that
  /// joins or splits sentences cannot shift the Turkish onto the wrong ones:
  /// a sentence it left out stays empty.
  Future<({List<String> translations, String summary})> translateChunk(List<String> sentences) async {
    final numbered = [for (var i = 0; i < sentences.length; i++) '[$i] ${sentences[i]}'].join('\n');
    final r = await _json(
      'Below are ${sentences.length} consecutive sentences from a book, numbered from 0. '
      'Return JSON {"translations": [{"i": 0, "tr": "..."}, ...], "summary": "..."}: one item per number, with "i" the '
      'sentence number and "tr" the Turkish translation of exactly that sentence (translate headings too; never join or '
      'split sentences), and "summary" is 2-4 Turkish sentences that summarise what this passage tells.\n\n$numbered',
      {
        'type': 'object',
        'properties': {
          'translations': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'i': {'type': 'integer'},
                'tr': {'type': 'string'},
              },
              'required': ['i', 'tr'],
              'additionalProperties': false,
            },
          },
          'summary': {'type': 'string'},
        },
        'required': ['translations', 'summary'],
        'additionalProperties': false,
      },
    );
    final out = List.filled(sentences.length, '');
    final list = r['translations'] as List? ?? const [];
    for (var k = 0; k < list.length; k++) {
      final e = list[k];
      if (e is Map) {
        final i = e['i'] is num ? (e['i'] as num).toInt() : int.tryParse('${e['i']}');
        if (i != null && i >= 0 && i < out.length) out[i] = '${e['tr'] ?? ''}'.trim();
      } else if (e is String && list.length == out.length) {
        // A plain list (older answer shape): trusted only when the count matches.
        out[k] = e;
      }
    }
    return (translations: out, summary: '${r['summary'] ?? ''}');
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

  /// Short Turkish meaning (1 to 4 words) of [word] as it is used in
  /// [sentence] ("course" in "a new golf course" -> "saha, golf sahası").
  Future<String> meaningInSentence(String word, String sentence) async {
    final r = await _json(
      'Sentence:\n$sentence\n\nWord: $word\n\n'
      'Return JSON {"tr": "..."}: the Turkish meaning of the word exactly as it is used in this sentence, '
      'in 1 to 4 words, the way a Turkish dictionary would put it (no explanation, no quotes).',
      {
        'type': 'object',
        'properties': {'tr': {'type': 'string'}},
        'required': ['tr'],
        'additionalProperties': false,
      },
      maxTokens: 400,
    );
    return '${r['tr']}'.trim();
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
    final paras = db.paras(bookId, ch.idx).where((p) => p.kind != 'i' && db.paraTranslation(p.id) == null).toList();
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

/// Gemini's setting for "think as little as this model allows": the 2.5
/// models take a token budget (0 = off, except Pro), the newer ones a level.
Map<String, dynamic> geminiQuickThinking(String model) {
  final m = model.toLowerCase();
  if (m.contains('2.5') || m.contains('2.0')) return {'thinkingBudget': m.contains('pro') ? 128 : 0};
  return {'thinkingLevel': m.contains('pro') ? 'low' : 'minimal'};
}
