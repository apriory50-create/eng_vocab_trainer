import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/db/app_database.dart';
import '../../main.dart';
import 'settings_screen.dart';

class LeechesScreen extends ConsumerStatefulWidget {
  const LeechesScreen({super.key});

  @override
  ConsumerState<LeechesScreen> createState() => _LeechesScreenState();
}

class _LeechesScreenState extends ConsumerState<LeechesScreen> {
  List<StudyItem> _items = [];
  bool _loading = true;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final db = ref.read(databaseProvider);
    final list = await db.getLeeches();
    if (!mounted) return;
    setState(() {
      _items = list;
      _loading = false;
    });
  }

  Future<void> _generateMnemonic(StudyItem item) async {
    setState(() => _generating = true);
    try {
      final ai = await loadAiClient(ref);
      final data = await ai.generateMnemonic(
        headword: item.lexeme.headword,
        translationRu: item.sense.translationRu,
      );
      final kw = data['keyword'] as Map<String, dynamic>? ?? {};
      final parts = <String>[
        if ((kw['sound_alike_ru'] ?? '').toString().isNotEmpty)
          'Созвучие: ${kw['sound_alike_ru']} — ${kw['image']} (${kw['link']})',
        if ((data['etymology'] ?? '').toString().isNotEmpty)
          'Этимология: ${data['etymology']}',
        if ((data['story_one_sentence'] ?? '').toString().isNotEmpty)
          'Образ: ${data['story_one_sentence']}',
      ];
      final text = parts.isEmpty ? data.toString() : parts.join('\n\n');

      final db = ref.read(databaseProvider);
      await db.saveMnemonic(
        lexemeId: item.lexeme.id,
        type: 'keyword',
        content: text,
      );

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Новая мнемоника: ${item.lexeme.headword}'),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Сохранено'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Пиявки (4+ ошибок)')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('Трудных карточек пока нет — отличный результат!'))
              : ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return ListTile(
                      title: Text(item.lexeme.headword, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${item.sense.translationRu} • Ошибок: ${item.card.lapses}'),
                      trailing: _generating
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : TextButton.icon(
                              onPressed: () => _generateMnemonic(item),
                              icon: const Icon(Icons.auto_awesome, size: 18),
                              label: const Text('Мнемоника'),
                            ),
                    );
                  },
                ),
    );
  }
}
