import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/user_db.dart';
import '../nlp/text.dart';

/// Optional online analysis through the Claude API (raw HTTP: there is no
/// official Dart SDK). Results are stored in the local database, so the book
/// keeps working offline afterwards.
class ClaudeService {
  static const models = {
    'claude-opus-5-5': 'Claude Opus 5.5 (en iyi kalite)',
    'claude-sonnet-5-5': 'Claude Sonnet 5.5 (dengeli)',
    'claude-haiku-5-5': 'Claude Haiku 5.5 (en ucuz)',
  };
  static const defaultModel = 'claude-opus-5-5';

  final String apiKey;
  final String model;
  ClaudeService(this.apiKey, {this.model = defaultModel});

  static ClaudeService? fromSettings(UserDb db) {
    final key = db.getSetting('api_key');
    if (key == null || key.trim().isEmpty) return null;
    return ClaudeService(key.trim(), model: db.getSetting('api_model') ?? defaultModel);
  }

  Future<Map<String, dynamic>> _call(String system, String prompt, Map<String, dynamic> schema, {int maxTokens = 16000}) async {
    final body = <String, dynamic>{
      'model': model,
      'max_tokens': maxTokens,
      'system': system,
      'output_config': {
        'effort': 'low',
        'format': {'type': 'json_schema', 'schema': schema},
      },
      'messages': [
        {'role': 'user', 'content': prompt}
      ],
    };
    final headers = {
      'content-type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2026-10-21',
    };
    // Haiku has no server-side fallback; Opus 5.5 / Sonnet 5.5 use the default route.
    if (model != 'claude-haiku-5-5') {
      body['fallbacks'] = 'default';
      headers['anthropic-beta'] = 'server-side-fallback-2026-07-01';
    }
    final res = await http
        .post(Uri.parse('https://api.anthropic.com/v1/messages'), headers: headers, body: jsonEncode(body))
        .timeout(const Duration(minutes: 5));
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      final msg = (data['error'] as Map?)?['message'] ?? res.body;
      throw Exception('Claude API hatası (${res.statusCode}): $msg');
    }
    if (data['stop_reason'] == 'refusal') throw Exception('İstek model tarafından reddedildi.');
    if (data['stop_reason'] == 'max_tokens') throw Exception('Yanıt çok uzun, kesildi.');
    final text = (data['content'] as List)
        .whereType<Map>()
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'] as String)
        .join();
    return jsonDecode(text) as Map<String, dynamic>;
  }

  static const _system =
      'You are a careful English-to-Turkish literary translator helping a Turkish reader learn English. '
      'Translate naturally and faithfully, keeping the meaning each sentence has in its context.';

  /// Translates numbered sentences; also returns a short Turkish summary.
  Future<({List<String> translations, String summary})> translateChunk(List<String> sentences) async {
    final numbered = [for (var i = 0; i < sentences.length; i++) '[$i] ${sentences[i]}'].join('\n');
    final r = await _call(
      _system,
      'Below are ${sentences.length} consecutive sentences from a book, numbered from 0. '
      'Return "translations": exactly ${sentences.length} Turkish translations in the same order, one per number '
      '(translate headings too). Return "summary": 2-4 Turkish sentences that summarise what this passage tells.\n\n$numbered',
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
    return (translations: (r['translations'] as List).cast<String>(), summary: r['summary'] as String);
  }

  /// Translation plus a Turkish breakdown of one sentence (used on demand).
  Future<({String translation, String explanation})> explainSentence(String sentence, String context) async {
    final r = await _call(
      _system,
      'Context paragraph:\n$context\n\nSentence:\n$sentence\n\n'
      'Give "translation": natural Turkish translation of the sentence. Give "explanation": in Turkish, a short '
      'breakdown for a learner: the tense(s) used, conjunctions, phrasal verbs, idioms and other notable patterns, '
      'and what any hard words mean here.',
      {
        'type': 'object',
        'properties': {
          'translation': {'type': 'string'},
          'explanation': {'type': 'string'},
        },
        'required': ['translation', 'explanation'],
        'additionalProperties': false,
      },
      maxTokens: 4000,
    );
    return (translation: r['translation'] as String, explanation: r['explanation'] as String);
  }
}

/// Runs the online analysis for a whole book and saves the results.
Future<void> analyzeBook(ClaudeService svc, UserDb db, int bookId,
    {void Function(int done, int total)? onProgress, bool Function()? cancelled}) async {
  final chapters = db.chapters(bookId);
  final total = db.parasMissingTranslation(bookId).length;
  var done = 0;
  for (final ch in chapters) {
    final paras = db.paras(bookId, ch.idx).where((p) => db.paraTranslation(p.id) == null).toList();
    final summaries = <String>[];
    var i = 0;
    while (i < paras.length) {
      if (cancelled?.call() == true) return;
      // ~2500 words per request keeps the response well under max_tokens.
      final batch = <Para>[];
      var words = 0;
      while (i < paras.length && (batch.isEmpty || words < 2500)) {
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
      summaries.add(r.summary);
      done += batch.length;
      onProgress?.call(done, total);
    }
    if (summaries.isNotEmpty) db.setChapterSummary(bookId, ch.idx, summaries.join(' '));
  }
}
