import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/db/app_database.dart';
import '../../domain/services/tts_service.dart';
import '../../main.dart';
import '../settings/settings_screen.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key});

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  List<ReadingText> _texts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTexts();
  }

  Future<void> _loadTexts() async {
    setState(() => _loading = true);
    final db = ref.read(databaseProvider);
    final list = await db.getAllTexts();
    if (!mounted) return;
    setState(() {
      _texts = list;
      _loading = false;
    });
  }

  double _calculateCoverage(String body, Set<String> knownWords) {
    final matches = RegExp(r"[A-Za-z']+").allMatches(body);
    final words = matches.map((m) => m.group(0)!.toLowerCase()).toList();
    if (words.isEmpty) return 0.0;
    final knownCount = words.where((w) => w.length <= 2 || knownWords.contains(w)).length;
    return knownCount / words.length;
  }

  Future<void> _showAddTextDialog() async {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Добавить текст'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Заголовок',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bodyCtrl,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Английский текст (статья, субтитры...)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    if (saved == true && titleCtrl.text.trim().isNotEmpty && bodyCtrl.text.trim().isNotEmpty) {
      final db = ref.read(databaseProvider);
      final known = await db.getKnownHeadwordsSet();
      final ratio = _calculateCoverage(bodyCtrl.text, known);
      await db.addReadingText(
        title: titleCtrl.text,
        body: bodyCtrl.text,
        source: 'manual',
        knownRatio: ratio,
      );
      await _loadTexts();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Чтение')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddTextDialog,
        icon: const Icon(Icons.add),
        label: const Text('Текст'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _texts.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Добавьте английский текст или статью.\nНажимайте на незнакомые слова, чтобы перевести их и добавить в колоду.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: _texts.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = _texts[index];
                    final pct = (item.knownRatio * 100).round();
                    return ListTile(
                      title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('Покрытие словарём: $pct%'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await ref.read(databaseProvider).deleteReadingText(item.id);
                          await _loadTexts();
                        },
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => TextReaderDetailScreen(text: item)),
                      ),
                    );
                  },
                ),
    );
  }
}

class TextReaderDetailScreen extends ConsumerStatefulWidget {
  final ReadingText text;
  const TextReaderDetailScreen({super.key, required this.text});

  @override
  ConsumerState<TextReaderDetailScreen> createState() => _TextReaderDetailScreenState();
}

class _TextReaderDetailScreenState extends ConsumerState<TextReaderDetailScreen> {
  final TtsService _tts = TtsService();
  Set<String> _knownWords = {};

  @override
  void initState() {
    super.initState();
    _loadKnown();
  }

  Future<void> _loadKnown() async {
    final known = await ref.read(databaseProvider).getKnownHeadwordsSet();
    if (!mounted) return;
    setState(() => _knownWords = known);
  }

  Future<void> _onWordTap(String rawWord) async {
    final clean = rawWord.replaceAll(RegExp(r"[^A-Za-z'-]"), '');
    if (clean.isEmpty) return;

    final db = ref.read(databaseProvider);
    final existing = await db.findLexemeByHeadword(clean);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _WordInspectSheet(
        word: clean,
        existing: existing,
        tts: _tts,
        onAdded: () {
          _loadKnown();
          ref.invalidate(dbStatsProvider);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.text.body.split(RegExp(r'(\s+)'));

    return Scaffold(
      appBar: AppBar(title: Text(widget.text.title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 4,
          runSpacing: 8,
          children: tokens.map((token) {
            final clean = token.replaceAll(RegExp(r"[^A-Za-z'-]"), '').toLowerCase();
            final isKnown = clean.length <= 2 || _knownWords.contains(clean);
            return InkWell(
              onTap: clean.isEmpty ? null : () => _onWordTap(token),
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                decoration: isKnown
                    ? null
                    : BoxDecoration(
                        color: Colors.amber.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(4),
                      ),
                child: Text(
                  token.trim(),
                  style: const TextStyle(fontSize: 18, height: 1.4),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _WordInspectSheet extends ConsumerStatefulWidget {
  final String word;
  final LexemeWithPrimarySense? existing;
  final TtsService tts;
  final VoidCallback onAdded;

  const _WordInspectSheet({
    required this.word,
    required this.existing,
    required this.tts,
    required this.onAdded,
  });

  @override
  ConsumerState<_WordInspectSheet> createState() => _WordInspectSheetState();
}

class _WordInspectSheetState extends ConsumerState<_WordInspectSheet> {
  final _transCtrl = TextEditingController();
  final _exCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _transCtrl.dispose();
    _exCtrl.dispose();
    super.dispose();
  }

  Future<void> _addViaAi() async {
    setState(() => _busy = true);
    try {
      final ai = await loadAiClient(ref);
      final data = await ai.generateWordCard(headword: widget.word);
      final senses = (data['senses'] as List<dynamic>? ?? []);
      final firstSense = senses.isNotEmpty ? senses.first as Map<String, dynamic> : {};
      final examples = (firstSense['examples'] as List<dynamic>? ?? []);
      final firstEx = examples.isNotEmpty ? examples.first as Map<String, dynamic> : {};

      await ref.read(databaseProvider).addCustomLexeme(
            headword: widget.word,
            translationRu: (firstSense['translation_ru'] ?? '').toString(),
            definitionEn: (firstSense['definition_en'] ?? '').toString(),
            exampleEn: (firstEx['en'] ?? '').toString(),
            exampleRu: (firstEx['ru'] ?? '').toString(),
            ipa: data['ipa']?.toString(),
            pos: data['pos']?.toString(),
            cefrLevel: data['cefr']?.toString(),
            source: 'ai',
          );
      widget.onAdded();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Слово «${widget.word}» добавлено через ИИ')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка ИИ: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addManual() async {
    if (_transCtrl.text.trim().isEmpty) return;
    await ref.read(databaseProvider).addCustomLexeme(
          headword: widget.word,
          translationRu: _transCtrl.text,
          exampleEn: _exCtrl.text,
          source: 'reader',
        );
    widget.onAdded();
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Слово «${widget.word}» добавлено в колоду')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.word,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.volume_up),
                onPressed: () => widget.tts.speak(widget.word),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (existing != null) ...[
            if (existing.lexeme.ipa != null) Text(existing.lexeme.ipa!),
            if (existing.sense != null) ...[
              const SizedBox(height: 6),
              Text(existing.sense!.translationRu, style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 4),
              Text(existing.sense!.definitionEn, style: TextStyle(color: Colors.grey.shade700)),
            ],
            if (existing.examples.isNotEmpty) ...[
              const Divider(height: 16),
              Text(existing.examples.first.textEn),
            ],
          ] else ...[
            const Text('Слова ещё нет в вашем словаре.'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _addViaAi,
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome),
              label: const Text('Разобрать через ИИ и добавить'),
            ),
            const Divider(height: 24),
            TextField(
              controller: _transCtrl,
              decoration: const InputDecoration(
                labelText: 'Или введите перевод вручную',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _exCtrl,
              decoration: const InputDecoration(
                labelText: 'Пример (необязательно)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _addManual,
              child: const Text('Сохранить вручную'),
            ),
          ],
        ],
      ),
    );
  }
}
