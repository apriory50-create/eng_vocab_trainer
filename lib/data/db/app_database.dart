import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'tables.dart';

part 'app_database.g.dart';

class LexemeWithPrimarySense {
  final Lexeme lexeme;
  final Sense? sense;
  final List<Example> examples;

  LexemeWithPrimarySense({
    required this.lexeme,
    required this.sense,
    required this.examples,
  });
}

@DriftDatabase(tables: [
  WordFamilies,
  Lexemes,
  Senses,
  Examples,
  Mnemonics,
  Cards,
  ReviewLogs,
  Texts,
  Settings,
  DailyStats,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
          await _insertDefaultSettings();
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Future<void> _insertDefaultSettings() async {
    final defaults = {
      'daily_new_limit': '15',
      'daily_review_limit': '100',
      'ai_model': 'claude-sonnet-4-20250514',
      'tts_voice': 'en-US',
      'tts_speed': '0.95',
      'ui_theme': 'system',
      'desired_retention': '0.9',
    };
    for (final entry in defaults.entries) {
      await into(settings).insertOnConflictUpdate(
        SettingsCompanion(
          key: Value(entry.key),
          value: Value(entry.value),
        ),
      );
    }
  }

  Future<int> getLexemesCount() async {
    final countExp = lexemes.id.count();
    final query = selectOnly(lexemes)..addColumns([countExp]);
    final result = await query.map((row) => row.read(countExp) ?? 0).getSingle();
    return result;
  }

  Future<int> getCardsCount() async {
    final countExp = cards.id.count();
    final query = selectOnly(cards)..addColumns([countExp]);
    final result = await query.map((row) => row.read(countExp) ?? 0).getSingle();
    return result;
  }

  Future<List<LexemeWithPrimarySense>> searchLexemes({
    String queryText = '',
    String? kindFilter,
    int limit = 100,
  }) async {
    final q = select(lexemes)
      ..orderBy([(t) => OrderingTerm(expression: t.freqRank, mode: OrderingMode.asc)])
      ..limit(limit);

    if (queryText.trim().isNotEmpty) {
      final pattern = '%${queryText.trim()}%';
      q.where((t) => t.headword.like(pattern));
    }
    if (kindFilter != null && kindFilter != 'all') {
      q.where((t) => t.kind.equals(kindFilter));
    }

    final lexemeRows = await q.get();
    final results = <LexemeWithPrimarySense>[];

    for (final lex in lexemeRows) {
      final senseRows = await (select(senses)..where((s) => s.lexemeId.equals(lex.id))).get();
      final primarySense = senseRows.isNotEmpty ? senseRows.first : null;
      final exampleRows = primarySense == null
          ? <Example>[]
          : await (select(examples)..where((e) => e.senseId.equals(primarySense.id))).get();

      results.add(LexemeWithPrimarySense(
        lexeme: lex,
        sense: primarySense,
        examples: exampleRows,
      ));
    }
    return results;
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'eng_vocab_trainer.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
