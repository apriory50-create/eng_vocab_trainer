import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/db/app_database.dart';
import '../../domain/services/fsrs_service.dart';
import '../../domain/services/tts_service.dart';
import '../../main.dart';

class StudyScreen extends ConsumerStatefulWidget {
  const StudyScreen({super.key});

  @override
  ConsumerState<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends ConsumerState<StudyScreen> {
  final TtsService _tts = TtsService();
  final TextEditingController _answerController = TextEditingController();
  final Stopwatch _stopwatch = Stopwatch();

  List<StudyItem> _queue = [];
  int _index = 0;
  bool _loading = true;
  bool _revealed = false;
  bool _showEnDef = false;
  bool? _wasCorrect;
  int? _suggestedRating;
  List<String> _options = [];

  @override
  void initState() {
    super.initState();
    _loadQueue();
  }

  @override
  void dispose() {
    _tts.stop();
    _answerController.dispose();
    super.dispose();
  }

  Future<void> _loadQueue() async {
    setState(() => _loading = true);
    final db = ref.read(databaseProvider);
    final items = await db.buildStudyQueue();
    if (!mounted) return;
    setState(() {
      _queue = items;
      _index = 0;
      _loading = false;
    });
    _prepareCard();
  }

  void _prepareCard() {
    _answerController.clear();
    _stopwatch.reset();
    _stopwatch.start();
    _revealed = false;
    _showEnDef = false;
    _wasCorrect = null;
    _suggestedRating = null;

    if (_index < _queue.length) {
      final item = _queue[_index];
      _options = [item.lexeme.headword, ...item.distractors]..shuffle();
      if (item.card.direction == 'listening') {
        _tts.speak(item.lexeme.headword);
      }
    }
  }

  void _checkTypedAnswer(StudyItem item) {
    _stopwatch.stop();
    final correct = FsrsService.isAnswerCorrect(
      _answerController.text,
      item.lexeme.headword,
    );
    final rating = FsrsService.autoRate(
      isCorrect: correct,
      responseMs: _stopwatch.elapsedMilliseconds,
    );
    setState(() {
      _revealed = true;
      _wasCorrect = correct;
      _suggestedRating = rating;
    });
    _tts.speak(item.lexeme.headword);
  }

  void _checkOptionAnswer(StudyItem item, String chosen) {
    _stopwatch.stop();
    final correct = chosen.toLowerCase() == item.lexeme.headword.toLowerCase();
    final rating = FsrsService.autoRate(
      isCorrect: correct,
      responseMs: _stopwatch.elapsedMilliseconds,
    );
    setState(() {
      _revealed = true;
      _wasCorrect = correct;
      _suggestedRating = rating;
    });
    _tts.speak(item.lexeme.headword);
  }

  void _revealSelfCheck(StudyItem item) {
    _stopwatch.stop();
    setState(() {
      _revealed = true;
    });
    _tts.speak(item.lexeme.headword);
  }

  Future<void> _submitRating(StudyItem item, int rating) async {
    final db = ref.read(databaseProvider);
    final isCorrect = rating >= 2;
    await db.recordReview(
      card: item.card,
      rating: rating,
      responseMs: _stopwatch.elapsedMilliseconds,
      isCorrect: isCorrect,
    );
    ref.invalidate(dbStatsProvider);

    if (!mounted) return;
    setState(() {
      _index++;
      _prepareCard();
    });
  }

  Future<void> _suspendCurrent(StudyItem item) async {
    final db = ref.read(databaseProvider);
    await db.suspendCard(item.card.id);
    if (!mounted) return;
    setState(() {
      _index++;
      _prepareCard();
    });
  }

  String _maskWordInSentence(String sentence, String word) {
    final reg = RegExp(RegExp.escape(word), caseSensitive: false);
    if (reg.hasMatch(sentence)) {
      return sentence.replaceAll(reg, '_____');
    }
    return '$sentence (_____)';
  }

  String _hintForWord(String word) {
    if (word.isEmpty) return '';
    return '${word[0]}${'_' * (word.length - 1)} (${word.length} симв.)';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_queue.isEmpty || _index >= _queue.length) {
      return Scaffold(
        appBar: AppBar(title: const Text('Занятие')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
                const SizedBox(height: 16),
                const Text(
                  'На сегодня всё готово!',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text('Все запланированные карточки повторены.'),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _loadQueue,
                  child: const Text('Проверить очередь снова'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final item = _queue[_index];
    final dir = item.card.direction;
    final example = item.examples.isNotEmpty ? item.examples.first : null;

    return Scaffold(
      appBar: AppBar(
        title: Text('Карточка ${_index + 1} из ${_queue.length}'),
        actions: [
          IconButton(
            tooltip: 'Озвучить',
            icon: const Icon(Icons.volume_up),
            onPressed: () => _tts.speak(item.lexeme.headword),
          ),
          IconButton(
            tooltip: 'Отложить карточку',
            icon: const Icon(Icons.pause_circle_outline),
            onPressed: () => _suspendCurrent(item),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Chip(label: Text(_directionLabel(dir))),
                const SizedBox(width: 8),
                if (item.lexeme.cefrLevel != null)
                  Chip(label: Text(item.lexeme.cefrLevel!)),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (dir == 'recognize_en_ru') ...[
                      Text(
                        item.lexeme.headword,
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                      ),
                      if (item.lexeme.ipa != null)
                        Text(item.lexeme.ipa!, style: TextStyle(color: Colors.grey.shade600)),
                      if (example != null) ...[
                        const SizedBox(height: 12),
                        Text(example.textEn, style: const TextStyle(fontSize: 16)),
                      ],
                    ] else if (dir == 'recall_ru_en') ...[
                      Text(
                        item.sense.translationRu,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Подсказка: ${_hintForWord(item.lexeme.headword)}',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ] else if (dir == 'listening') ...[
                      Center(
                        child: FilledButton.tonalIcon(
                          onPressed: () => _tts.speak(item.lexeme.headword),
                          icon: const Icon(Icons.hearing),
                          label: const Text('Прослушать слово / фразу'),
                        ),
                      ),
                    ] else if (dir == 'cloze' || dir == 'collocation_pick') ...[
                      Text(
                        example != null
                            ? _maskWordInSentence(example.textEn, item.lexeme.headword)
                            : 'Выберите верный вариант для: ${item.sense.translationRu}',
                        style: const TextStyle(fontSize: 18),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () => setState(() => _showEnDef = !_showEnDef),
                      icon: const Icon(Icons.info_outline, size: 18),
                      label: Text(_showEnDef ? 'Скрыть определение' : 'Определение на английском'),
                    ),
                    if (_showEnDef)
                      Text(
                        item.sense.definitionEn,
                        style: const TextStyle(fontStyle: FontStyle.italic),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Ввод ответа или выбор варианта до показа ответа
            if (!_revealed) ...[
              if (dir == 'recall_ru_en' || dir == 'listening') ...[
                TextField(
                  controller: _answerController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Введите слово на английском',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _checkTypedAnswer(item),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => _checkTypedAnswer(item),
                  child: const Text('Проверить'),
                ),
              ] else if (dir == 'cloze' || dir == 'collocation_pick') ...[
                for (final opt in _options)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton(
                      onPressed: () => _checkOptionAnswer(item, opt),
                      child: Text(opt, style: const TextStyle(fontSize: 16)),
                    ),
                  ),
              ] else ...[
                FilledButton(
                  onPressed: () => _revealSelfCheck(item),
                  child: const Text('Показать ответ'),
                ),
              ],
            ],

            // Блок ответа и оценки FSRS
            if (_revealed) ...[
              Card(
                color: _wasCorrect == null
                    ? null
                    : (_wasCorrect! ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.lexeme.headword,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      if (item.lexeme.ipa != null) Text(item.lexeme.ipa!),
                      const SizedBox(height: 6),
                      Text(
                        item.sense.translationRu,
                        style: const TextStyle(fontSize: 18),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.sense.definitionEn,
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                      if (example != null) ...[
                        const Divider(height: 20),
                        Text(example.textEn),
                        const SizedBox(height: 4),
                        Text(example.textRu, style: TextStyle(color: Colors.grey.shade700)),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_suggestedRating != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Автооценка: ${_ratingLabel(_suggestedRating!)} (можно изменить вручную)',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                  ),
                ),
              Row(
                children: [
                  _ratingBtn(item, 1, 'Снова', Colors.red),
                  const SizedBox(width: 6),
                  _ratingBtn(item, 2, 'Трудно', Colors.orange),
                  const SizedBox(width: 6),
                  _ratingBtn(item, 3, 'Хорошо', Colors.green),
                  const SizedBox(width: 6),
                  _ratingBtn(item, 4, 'Легко', Colors.blue),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _ratingBtn(StudyItem item, int rating, String label, Color color) {
    final isSuggested = _suggestedRating == rating;
    return Expanded(
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isSuggested ? color : color.withOpacity(0.15),
          foregroundColor: isSuggested ? Colors.white : color,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onPressed: () => _submitRating(item, rating),
        child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    );
  }

  String _directionLabel(String dir) {
    switch (dir) {
      case 'recognize_en_ru':
        return 'EN → RU';
      case 'recall_ru_en':
        return 'RU → EN (ввод)';
      case 'cloze':
        return 'Пропуск';
      case 'listening':
        return 'На слух';
      case 'collocation_pick':
        return 'Коллокация';
      default:
        return dir;
    }
  }

  String _ratingLabel(int rating) {
    switch (rating) {
      case 1:
        return 'Снова';
      case 2:
        return 'Трудно';
      case 3:
        return 'Хорошо';
      case 4:
        return 'Легко';
      default:
        return '';
    }
  }
}
