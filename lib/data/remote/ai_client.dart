import 'dart:convert';
import 'package:http/http.dart' as http;

class AiConfig {
  final String provider; // 'anthropic' | 'openai'
  final String apiKey;
  final String baseUrl;
  final String model;

  AiConfig({
    required this.provider,
    required this.apiKey,
    required this.baseUrl,
    required this.model,
  });
}

class AiClient {
  final AiConfig config;

  AiClient(this.config);

  Future> _requestJson({
    required String systemPrompt,
    required String userPrompt,
  }) async {
    if (config.apiKey.trim().isEmpty) {
      throw Exception('API-ключ не задан. Укажите его в Настройках.');
    }

    Exception? lastError;
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final rawText = config.provider == 'openai'
            ? await _callOpenAi(systemPrompt, userPrompt)
            : await _callAnthropic(systemPrompt, userPrompt);

        final cleaned = _cleanJson(rawText);
        final decoded = jsonDecode(cleaned);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        throw const FormatException('Ожидался JSON-объект');
      } catch (e) {
        lastError = Exception('Ошибка ИИ (попытка ${attempt + 1}):$e');
      }
    }
    throw lastError ?? Exception('Неизвестная ошибка ИИ');
  }

  Future<String> _callAnthropic(String systemPrompt, String userPrompt) async {
    final uri = Uri.parse(config.baseUrl.isEmpty
        ? '[https://api.anthropic.com/v1/messages](https://api.anthropic.com/v1/messages)'
        : config.baseUrl);
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': config.apiKey.trim(),
        'anthropic-version': '2023-06-01',
      },
      body: jsonEncode({
        'model': config.model,
        'max_tokens': 1200,
        'system': systemPrompt,
        'messages': [
          {'role': 'user', 'content': userPrompt},
        ],
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}:${response.body}');
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final content = data['content'] as List<dynamic>;
    return content.first['text'] as String;
  }

  Future<String> _callOpenAi(String systemPrompt, String userPrompt) async {
    final uri = Uri.parse(config.baseUrl.isEmpty
        ? '[https://api.openai.com/v1/chat/completions](https://api.openai.com/v1/chat/completions)'
        : config.baseUrl);
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${config.apiKey.trim()}',
      },
      body: jsonEncode({
        'model': config.model,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}:${response.body}');
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final choices = data['choices'] as List<dynamic>;
    return choices.first['message']['content'] as String;
  }

  String _cleanJson(String raw) {
    var text = raw.trim();
    if (text.startsWith('```json')) {
      text = text.substring(7);
    } else if (text.startsWith('```')) {
      text = text.substring(3);
    }
    if (text.endsWith('```')) {
      text = text.substring(0, text.length - 3);
    }
    return text.trim();
  }

  /// Промпт A: карточка слова
  Future> generateWordCard({
    required String headword,
    String? pos,
    String? contextSentence,
  }) {
    const sys = 'Отвечай строго валидным JSON без пояснений и без Markdown-ограждений.';
    final user = '''
Сгенерируй карточку для английского слова/фразы "$headword"${pos != null ? ' ($pos)' : ''}${contextSentence != null ? ' в контексте: "$contextSentence"' : ''}.
Верни JSON строго по схеме:
{"ipa":"","pos":"","cefr":"","senses":[{"definition_en":"","translation_ru":"","register":"","examples":[{"en":"","ru":""}]}],"collocations":[""],"word_family":[""],"synonyms":[""],"common_mistakes_for_russian_speakers":""}
Требования: 1–3 значения, по 3 естественных примера уровня B1–C1 на каждое значение, в разных грамматических формах и сочетаниях.
''';
    return _requestJson(systemPrompt: sys, userPrompt: user);
  }

  /// Промпт B: мнемоника
  Future> generateMnemonic({
    required String headword,
    required String translationRu,
  }) {
    const sys = 'Отвечай строго валидным JSON без пояснений и без Markdown-ограждений.';
    final user = '''
Придумай мнемонику для английского слова "$headword" (перевод: "$translationRu").
Верни JSON строго по схеме:
{"keyword":{"sound_alike_ru":"","image":"","link":""},"etymology":"","morphology":"","story_one_sentence":"","image_prompt":""}
Требования: созвучие с русским словом, яркий и нелепый образ с участием значения, связка в одном предложении. Если честное созвучие найти нельзя, оставь поля keyword пустыми, не выдумывай натянутое.
''';
    return _requestJson(systemPrompt: sys, userPrompt: user);
  }

  /// Промпт C: мини-история из 5–7 слов
  Future> generateMiniStory({
    required List<String> words,
    String interests = 'повседневная жизнь, технологии, путешествия',
    String level = 'B2',
  }) {
    const sys = 'Отвечай строго валидным JSON без пояснений и без Markdown-ограждений.';
    final user = '''
Напиши мини-историю (80–120 слов) уровня $level на тему "$interests", используя слова: ${words.join(', ')}.
Выдели использованные слова маркерами **слово**.
Верни JSON: {"title":"","story":"","words_used":[""],"questions":[""]}
''';
    return _requestJson(systemPrompt: sys, userPrompt: user);
  }

  /// Промпт D: проверка предложения пользователя
  Future> checkSentence({
    required String word,
    required String sentence,
  }) {
    const sys = 'Отвечай строго валидным JSON без пояснений и без Markdown-ограждений.';
    final user = '''
Проверь употребление слова "$word" в предложении: "$sentence".
Верни JSON: {"correct":true,"issues":[""],"natural_version":"","explanation_ru":""}
''';
    return _requestJson(systemPrompt: sys, userPrompt: user);
  }
}
