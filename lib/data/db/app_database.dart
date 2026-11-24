import 'dart:io';
import 'dart:math';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../domain/services/fsrs_service.dart';
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

class StudyItem {
  final VocabCard card;
  final Lexeme lexeme;
  final Sense sense;
  final List<Example> examples;
  final List<String> distractors;

  StudyItem({
    required this.card,
    required this.lexeme,
    required this.sense,
    required this.examples,
    required this.distractors,
  });
}

class OverallStats {
  final int totalLexemes;
  final int activeLexemes;
  final int totalReviews;
  final double accuracy;

  OverallStats({
    required this.totalLexemes,
    required this.activeLexemes,
    required this.totalReviews,
    required this.accuracy,
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
      'ai_provider': 'anthropic',
      'ai_base_url': 'https://api.anthropic.com/v1/messages',
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

  Future<String> getSetting(String key, String fallback) async {
    final row = await (select(settings)..where((s) => s.key.equals(key))).getSingleOrNull();
    return row?.value ?? fallback;
  }

  Future<void> setSetting(String key, String value) async {
    await into(settings).insertOnConflictUpdate(
      SettingsCompanion(key: Value(key), value: Value(value)),
    );
  }

  Future<int> getLexemesCount() async {
    final countExp = lexemes.id.count();
    final query = selectOnly(lexemes)..addColumns([countExp]);
    return await query.map((row) => row.read(countExp) ?? 0).getSingle();
  }

  Future<int> getCardsCount() async {
    final countExp = cards.id.count();
    final query = selectOnly(cards)..addColumns([countExp]);
    return await query.map((row) => row.read(countExp) ?? 0).getSingle();
  }

  Future<int> getDueCardsCount() async {
    final now = DateTime.now();
    final countExp = cards.id.count();
    final query = selectOnly(cards)
      ..addColumns([countExp])
      ..where(cards.suspended.equals(false) & cards.due.isSmallerOrEqualValue(now));
    return await query.map((row) => row.read(countExp) ?? 0).getSingle();
  }

  Future<Set<String>> getKnownHeadwordsSet() async {
    final rows = await select(lexemes).get();
    return rows.map((e) => e.headword.toLowerCase().trim()).toSet();
  }

  Future<LexemeWithPrimarySense?> findLexemeByHeadword(String word) async {
    final clean = word.toLowerCase().trim();
    final all = await select(lexemes).get();
    Lexeme? found;
    for (final l in all) {
      if (l.headword.toLowerCase().trim() == clean) {
        found = l;
        break;
      }
    }
    if (found == null) return null;
    final senseRows = await (select(senses)..where((s) => s.lexemeId.equals(found!.id))).get();
    final primarySense = senseRows.isNotEmpty ? senseRows.first : null;
    final exampleRows = primarySense == null
        ? <Example>[]
        : await (select(examples)..where((e) => e.senseId.equals(primarySense.id))).get();
    return LexemeWithPrimarySense(
      lexeme: found,
      sense: primarySense,
      examples: exampleRows,
    );
  }

  Future<int> addCustomLexeme({
    required String headword,
    required String translationRu,
    String definitionEn = '',
    String exampleEn = '',
    String exampleRu = '',
    String? ipa,
    String? pos,
    String? cefrLevel,
    String kind = 'word',
    String source = 'manual',
  }) async {
    return transaction(() async {
      final lexemeId = await into(lexemes).insert(
        LexemesCompanion.insert(
          headword: headword.trim(),
          kind: kind,
          pos: Value(pos),
          ipa: Value(ipa),
          cefrLevel: Value(cefrLevel),
          source: Value(source),
        ),
      );

      final senseId = await into(senses).insert(
        SensesCompanion.insert(
          lexemeId: lexemeId,
          definitionEn: definitionEn.trim(),
          translationRu: translationRu.trim(),
        ),
      );

      if (exampleEn.trim().isNotEmpty) {
        await into(examples).insert(
          ExamplesCompanion.insert(
            senseId: senseId,
            textEn: exampleEn.trim(),
            textRu: exampleRu.trim(),
            source: Value(source == 'ai' ? 'ai' : 'user'),
          ),
        );
      }

      await into(cards).insert(
        CardsCompanion.insert(
          lexemeId: lexemeId,
          senseId: senseId,
          direction: 'recognize_en_ru',
        ),
      );
      await into(cards).insert(
        CardsCompanion.insert(
          lexemeId: lexemeId,
          senseId: senseId,
          direction: 'recall_ru_en',
        ),
      );

      return lexemeId;
    });
  }

  /// Импорт CSV формата: headword,translation,example
  Future<int> importCsv(String csvContent) async {
    final existing = await getKnownHeadwordsSet();
    final lines = csvContent.split(RegExp(r'\r?\n'));
    int added = 0;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.toLowerCase().startsWith('headword,')) continue;

      final parts = line.split(',');
      if (parts.length < 2) continue;

      final headword = parts[0].trim();
      final translation = parts[1].trim();
      final example = parts.length >= 3 ? parts.sublist(2).join(',').trim() : '';

      if (headword.isEmpty || translation.isEmpty) continue;
      if (existing.contains(headword.toLowerCase())) continue;

      await addCustomLexeme(
        headword: headword,
        translationRu: translation,
        exampleEn: example,
        source: 'manual',
      );
      existing.add(headword.toLowerCase());
      added++;
    }
    return added;
  }

  // --- Тексты для чтения ---
  Future<List<ReadingText>> getAllTexts() {
    return (select(texts)..orderBy([(t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)])).get();
  }

  Future<int> addReadingText({
    required String title,
    required String body,
    String? source,
    required double knownRatio,
  }) {
    return into(texts).insert(
      TextsCompanion.insert(
        title: title.trim(),
        body: body.trim(),
        source: Value(source),
        knownRatio: Value(knownRatio),
      ),
    );
  }

  Future<void> deleteReadingText(int id) async {
    await (delete(texts)..where((t) => t.id.equals(id))).go();
  }

  // --- Статистика ---
  Future<List<DailyStat>> getDailyStatsList() {
    return (select(dailyStats)
          ..orderBy([(d) => OrderingTerm(expression: d.date, mode: OrderingMode.desc)])
          ..limit(30))
        .get();
  }

  Future<OverallStats> getOverallStats() async {
    final totalLex = await getLexemesCount();
    final reviewedCards = await (select(cards)..where((c) => c.reps.isBiggerThanValue(0))).get();
    final activeLexIds = reviewedCards.map((c) => c.lexemeId).toSet();

    final logs = await select(reviewLogs).get();
    final totalRev = logs.length;
    final correctCount = logs.where((l) => l.correct).length;
    final acc = totalRev == 0 ? 0.0 : correctCount / totalRev;

    return OverallStats(
      totalLexemes: totalLex,
      activeLexemes: activeLexIds.length,
      totalReviews: totalRev,
      accuracy: acc,
    );
  }

  // --- Мнемоники и Пиявки ---
  Future<List<Mnemonic>> getMnemonicsForLexeme(int lexemeId) {
    return (select(mnemonics)..where((m) => m.lexemeId.equals(lexemeId))).get();
  }

  Future<void> saveMnemonic({
    required int lexemeId,
    required String type,
    required String content,
    String createdBy = 'ai',
  }) async {
    await into(mnemonics).insert(
      MnemonicsCompanion.insert(
        lexemeId: lexemeId,
        type: type,
        textContent: content,
        createdBy: Value(createdBy),
      ),
    );
  }

  Future<List<StudyItem>> getLeeches() async {
    final leechCards = await (select(cards)
          ..where((c) => c.lapses.isBiggerOrEqualValue(4) & c.suspended.equals(false))
          ..orderBy([(c) => OrderingTerm(expression: c.lapses, mode: OrderingMode.desc)]))
        .get();

    final items = <StudyItem>[];
    for (final card in leechCards) {
      final lex = await (select(lexemes)..where((l) => l.id.equals(card.lexemeId))).getSingleOrNull();
      final sense = await (select(senses)..where((s) => s.id.equals(card.senseId))).getSingleOrNull();
      if (lex == null || sense == null) continue;
      final exList = await (select(examples)..where((e) => e.senseId.equals(sense.id))).get();
      items.add(StudyItem(
        card: card,
        lexeme: lex,
        sense: sense,
        examples: exList,
        distractors: const [],
      ));
    }
    return items;
  }

  // --- Очередь FSRS ---
  Future<List<StudyItem>> buildStudyQueue() async {
    final now = DateTime.now();
    final newLimit = int.tryParse(await getSetting('daily_new_limit', '15')) ?? 15;
    final reviewLimit = int.tryParse(await getSetting('daily_review_limit', '100')) ?? 100;

    final dueReviews = await (select(cards)
          ..where((c) =>
              c.suspended.equals(false) &
              c.state.equals('review') &
              c.due.isSmallerOrEqualValue(now))
          ..orderBy([(c) => OrderingTerm(expression: c.due, mode: OrderingMode.asc)])
          ..limit(reviewLimit))
        .get();

    final learningCards = await (select(cards)
          ..where((c) =>
              c.suspended.equals(false) &
              (c.state.equals('learning') | c.state.equals('relearning')) &
              c.due.isSmallerOrEqualValue(now))
          ..orderBy([(c) => OrderingTerm(expression: c.due, mode: OrderingMode.asc)]))
        .get();

    final newCards = await (select(cards)
          ..where((c) => c.suspended.equals(false) & c.state.equals('new'))
          ..orderBy([(c) => OrderingTerm(expression: c.id, mode: OrderingMode.asc)])
          ..limit(newLimit))
        .get();

    final orderedCards = <VocabCard>[...dueReviews, ...learningCards, ...newCards];
    final spacedCards = _avoidConsecutiveLexemes(orderedCards);

    final allLexemes = await select(lexemes).get();
    final rng = Random();
    final items = <StudyItem>[];

    for (final card in spacedCards) {
      final lex = await (select(lexemes)..where((l) => l.id.equals(card.lexemeId))).getSingleOrNull();
      final sense = await (select(senses)..where((s) => s.id.equals(card.senseId))).getSingleOrNull();
      if (lex == null || sense == null) continue;

      final exList = await (select(examples)..where((e) => e.senseId.equals(sense.id))).get();

      final candidates = allLexemes
          .where((l) => l.id != lex.id)
          .map((l) => l.headword)
          .toList()
        ..shuffle(rng);
      final distractors = candidates.take(3).toList();

      items.add(StudyItem(
        card: card,
        lexeme: lex,
        sense: sense,
        examples: exList,
        distractors: distractors,
      ));
    }
    return items;
  }

  List<VocabCard> _avoidConsecutiveLexemes(List<VocabCard> list) {
    final result = List<VocabCard>.from(list);
    for (int i = 1; i < result.length; i++) {
      if (result[i].lexemeId == result[i - 1].lexemeId) {
        final swapIdx = result.indexWhere(
          (c) => c.lexemeId != result[i - 1].lexemeId,
          i + 1,
        );
        if (swapIdx != -1) {
          final tmp = result[i];
          result[i] = result[swapIdx];
          result[swapIdx] = tmp;
        }
      }
    }
    return result;
  }

  Future<void> recordReview({
    required VocabCard card,
    required int rating,
    required int responseMs,
    required bool isCorrect,
  }) async {
    final desiredRetention =
        double.tryParse(await getSetting('desired_retention', '0.9')) ?? 0.9;
    final fsrs = FsrsService();
    final now = DateTime.now();

    final res = fsrs.review(
      currentState: card.state,
      currentStability: card.stability,
      currentDifficulty: card.difficulty,
      reps: card.reps,
      lapses: card.lapses,
      lastReview: card.lastReview,
      rating: rating,
      desiredRetention: desiredRetention,
      now: now,
    );

    await transaction(() async {
      await (update(cards)..where((c) => c.id.equals(card.id))).write(
        CardsCompanion(
          state: Value(res.state),
          due: Value(res.due),
          stability: Value(res.stability),
          difficulty: Value(res.difficulty),
          elapsedDays: Value(res.elapsedDays),
          scheduledDays: Value(res.scheduledDays),
          reps: Value(res.reps),
          lapses: Value(res.lapses),
          lastReview: Value(now),
        ),
      );

      await into(reviewLogs).insert(
        ReviewLogsCompanion.insert(
          cardId: card.id,
          rating: rating,
          responseMs: responseMs,
          stateBefore: card.state,
          exerciseType: card.direction,
          correct: isCorrect,
        ),
      );

      final todayKey =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final existingStat =
          await (select(dailyStats)..where((d) => d.date.equals(todayKey))).getSingleOrNull();

      final isNew = card.state == 'new';
      if (existingStat == null) {
        await into(dailyStats).insert(
          DailyStatsCompanion.insert(
            date: todayKey,
            newCards: Value(isNew ? 1 : 0),
            reviews: const Value(1),
            minutes: const Value(1),
            correctRatio: Value(isCorrect ? 1.0 : 0.0),
          ),
        );
      } else {
        final totalRev = existingStat.reviews + 1;
        final prevCorrect = existingStat.correctRatio * existingStat.reviews;
        final newRatio = (prevCorrect + (isCorrect ? 1 : 0)) / totalRev;
        await (update(dailyStats)..where((d) => d.date.equals(todayKey))).write(
          DailyStatsCompanion(
            newCards: Value(existingStat.newCards + (isNew ? 1 : 0)),
            reviews: Value(totalRev),
            correctRatio: Value(newRatio),
          ),
        );
      }
    });
  }

  Future<void> suspendCard(int cardId) async {
    await (update(cards)..where((c) => c.id.equals(cardId))).write(
      const CardsCompanion(suspended: Value(true)),
    );
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

