import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'data/db/app_database.dart';
import 'data/seed/seed_loader.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final seedInitProvider = FutureProvider<int>((ref) async {
  final db = ref.watch(databaseProvider);
  final loader = SeedLoader(db);
  return loader.loadAllMissingSeeds();
});

final dbStatsProvider = FutureProvider<({int lexemes, int cards})>((ref) async {
  await ref.watch(seedInitProvider.future);
  final db = ref.watch(databaseProvider);
  final lexCount = await db.getLexemesCount();
  final cardCount = await db.getCardsCount();
  return (lexemes: lexCount, cards: cardCount);
});

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/home',
    routes: [
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          GoRoute(path: '/study', builder: (_, __) => const PlaceholderTab(title: 'Занятие (Этап 2)')),
          GoRoute(path: '/library', builder: (_, __) => const LibraryScreen()),
          GoRoute(path: '/reader', builder: (_, __) => const PlaceholderTab(title: 'Чтение (Этап 4)')),
          GoRoute(path: '/settings', builder: (_, __) => const PlaceholderTab(title: 'Настройки (Этап 3)')),
        ],
      ),
    ],
  );
});

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: EngVocabApp()));
}

class EngVocabApp extends ConsumerWidget {
  const EngVocabApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Словарь B1–C1',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}

class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  static const _tabs = ['/home', '/study', '/library', '/reader', '/settings'];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final currentIndex = _tabs.indexWhere((t) => location.startsWith(t)).clamp(0, _tabs.length - 1);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (idx) => context.go(_tabs[idx]),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Главная'),
          NavigationDestination(icon: Icon(Icons.school_outlined), selectedIcon: Icon(Icons.school), label: 'Учить'),
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Словарь'),
          NavigationDestination(icon: Icon(Icons.article_outlined), selectedIcon: Icon(Icons.article), label: 'Чтение'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Настройки'),
        ],
      ),
    );
  }
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(dbStatsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Словарь B1–C1')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: statsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('Ошибка инициализации БД: $err')),
          data: (stats) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Состояние локальной базы', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Text('Загружено слов и фраз: ${stats.lexemes}'),
                      const SizedBox(height: 4),
                      Text('Создано карточек повторения: ${stats.cards}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => context.go('/library'),
                icon: const Icon(Icons.menu_book),
                label: const Text('Открыть словарь'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String _query = '';
  String _kind = 'all';

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Словарь')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Поиск слова или фразы...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (val) => setState(() => _query = val),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                for (final entry in {
                  'all': 'Все',
                  'word': 'Слова',
                  'phrasal_verb': 'Фразовые',
                  'collocation': 'Коллокации',
                  'chunk': 'Чанки',
                  'idiom': 'Идиомы',
                }.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(entry.value),
                      selected: _kind == entry.key,
                      onSelected: (_) => setState(() => _kind = entry.key),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<LexemeWithPrimarySense>>(
              future: db.searchLexemes(queryText: _query, kindFilter: _kind),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snapshot.data ?? [];
                if (items.isEmpty) {
                  return const Center(child: Text('Ничего не найдено'));
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ListTile(
                      title: Text(
                        item.lexeme.headword,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (item.sense != null) Text(item.sense!.translationRu),
                          if (item.examples.isNotEmpty)
                            Text(
                              item.examples.first.textEn,
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                            ),
                        ],
                      ),
                      trailing: Chip(
                        label: Text(item.lexeme.cefrLevel ?? item.lexeme.kind),
                        visualDensity: VisualDensity.compact,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class PlaceholderTab extends StatelessWidget {
  final String title;
  const PlaceholderTab({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(child: Text('$title — будет добавлено на следующем этапе')),
    );
  }
}
