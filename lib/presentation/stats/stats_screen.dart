import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/db/app_database.dart';
import '../../main.dart';

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  OverallStats? _overall;
  List<DailyStat> _daily = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final db = ref.read(databaseProvider);
    final ov = await db.getOverallStats();
    final days = await db.getDailyStatsList();
    if (!mounted) return;
    setState(() {
      _overall = ov;
      _daily = days;
      _loading = false;
    });
  }

  Future<void> _showImportCsvDialog() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Импорт слов (CSV)'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Формат строк:\nheadword,translation,example',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                maxLines: 6,
                decoration: const InputDecoration(
                  hintText: 'resilient,стойкий,She is very resilient.',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Импортировать')),
        ],
      ),
    );

    if (ok == true && ctrl.text.trim().isNotEmpty) {
      final count = await ref.read(databaseProvider).importCsv(ctrl.text);
      ref.invalidate(dbStatsProvider);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Импортировано новых слов: $count')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Статистика и импорт')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_overall != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Общий прогресс', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          Text('Всего слов и фраз в базе: ${_overall!.totalLexemes}'),
                          Text('В активном изучении: ${_overall!.activeLexemes}'),
                          Text('Всего повторений: ${_overall!.totalReviews}'),
                          Text('Точность ответов: ${(_overall!.accuracy * 100).round()}%'),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _showImportCsvDialog,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Импортировать слова из CSV'),
                ),
                const SizedBox(height: 20),
                const Text('История по дням', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (_daily.isEmpty)
                  const Text('Пока нет завершённых повторений.')
                else
                  for (final d in _daily)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(d.date),
                      subtitle: Text('Новых: ${d.newCards} • Повторений: ${d.reviews}'),
                      trailing: Text('${(d.correctRatio * 100).round()}%'),
                    ),
              ],
            ),
    );
  }
}
