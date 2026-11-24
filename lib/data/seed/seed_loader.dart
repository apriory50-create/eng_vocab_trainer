import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import '../db/app_database.dart';

class SeedLoader {
  final AppDatabase db;

  SeedLoader(this.db);

  static const List<String> seedFiles = [
    'assets/seed/words_b1.json',
    'assets/seed/words_b2_c1.json',
    'assets/seed/phrasal_verbs.json',
    'assets/seed/collocations.json',
    'assets/seed/chunks_idioms.json',
  ];

  Future<int> loadAllMissingSeeds() async {
    int insertedTotal = 0;

    final existingRows = await db.select(db.lexemes).get();
    final existingHeadwords = existingRows.map((e) => e.headword.toLowerCase()).toSet();

    for (final assetPath in seedFiles) {
      String rawJson;
      try {
        rawJson = await rootBundle.loadString(assetPath);
      } catch (_) {
        // Файл батча ещё не добавлен — пропускаем без ошибки
        continue;
      }

      final List<dynamic> items = jsonDecode(rawJson) as List<dynamic>;

      await db.transaction(() async {
        for (final item in items) {
          final map = item as Map<String, dynamic>;
          final headword = (map['headword'] as String).trim();
          if (existingHeadwords.contains(headword.toLowerCase())) {
            continue;
          }

          final lexemeId = await db.into(db.lexemes).insert(
                LexemesCompanion.insert(
                  headword: headword,
                  kind: map['kind'] as String? ?? 'word',
                  pos: Value(map['pos'] as String?),
                  ipa: Value(map['ipa'] as String?),
                  cefrLevel: Value(map['cefr_level'] as String?),
                  freqRank: Value(map['freq_rank'] as int?),
                  source: const Value('seed'),
                ),
              );

          final sensesList = (map['senses'] as List<dynamic>? ?? []);
          for (final s in sensesList) {
            final sMap = s as Map<String, dynamic>;
            final senseId = await db.into(db.senses).insert(
                  SensesCompanion.insert(
                    lexemeId: lexemeId,
                    definitionEn: sMap['definition_en'] as String? ?? '',
                    translationRu: sMap['translation_ru'] as String? ?? '',
                    register: Value(sMap['register'] as String? ?? 'neutral'),
                    note: Value(sMap['note'] as String?),
                  ),
                );

            final examplesList = (sMap['examples'] as List<dynamic>? ?? []);
            for (final ex in examplesList) {
              final exMap = ex as Map<String, dynamic>;
              await db.into(db.examples).insert(
                    ExamplesCompanion.insert(
                      senseId: senseId,
                      textEn: exMap['en'] as String? ?? '',
                      textRu: exMap['ru'] as String? ?? '',
                      source: const Value('seed'),
                    ),
                  );
            }

            // Создаём 2 базовые карточки для первого значения
            await db.into(db.cards).insert(
                  CardsCompanion.insert(
                    lexemeId: lexemeId,
                    senseId: senseId,
                    direction: 'recognize_en_ru',
                  ),
                );
            await db.into(db.cards).insert(
                  CardsCompanion.insert(
                    lexemeId: lexemeId,
                    senseId: senseId,
                    direction: 'recall_ru_en',
                  ),
                );
          }

          existingHeadwords.add(headword.toLowerCase());
          insertedTotal++;
        }
      });
    }

    return insertedTotal;
  }
}
