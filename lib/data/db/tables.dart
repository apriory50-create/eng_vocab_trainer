import 'package:drift/drift.dart';

class WordFamilies extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get root => text()();
  TextColumn get note => text().nullable()();
}

@TableIndex(name: 'idx_lexemes_freq_rank', columns: {#freqRank})
@TableIndex(name: 'idx_lexemes_headword', columns: {#headword})
class Lexemes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get headword => text()();
  TextColumn get kind => text()(); // word | collocation | phrasal_verb | idiom | chunk
  TextColumn get pos => text().nullable()();
  TextColumn get ipa => text().nullable()();
  TextColumn get cefrLevel => text().nullable()();
  IntColumn get freqRank => integer().nullable()();
  IntColumn get familyId => integer().nullable().references(WordFamilies, #id, onDelete: KeyAction.setNull)();
  TextColumn get source => text().withDefault(const Constant('seed'))(); // seed | reader | ai | manual
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class Senses extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get lexemeId => integer().references(Lexemes, #id, onDelete: KeyAction.cascade)();
  TextColumn get definitionEn => text()();
  TextColumn get translationRu => text()();
  TextColumn get register => text().withDefault(const Constant('neutral'))(); // neutral | formal | informal | slang
  TextColumn get note => text().nullable()();
}

class Examples extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get senseId => integer().references(Senses, #id, onDelete: KeyAction.cascade)();
  TextColumn get textEn => text()();
  TextColumn get textRu => text()();
  TextColumn get audioPath => text().nullable()();
  TextColumn get source => text().withDefault(const Constant('ai'))(); // tatoeba | ai | user | reader
}

class Mnemonics extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get lexemeId => integer().references(Lexemes, #id, onDelete: KeyAction.cascade)();
  TextColumn get type => text()(); // keyword | etymology | morphology | story | image_prompt | custom
  TextColumn get textContent => text().named('text')();
  TextColumn get createdBy => text().withDefault(const Constant('ai'))(); // ai | user
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
}

@DataClassName('VocabCard')
@TableIndex(name: 'idx_cards_due', columns: {#due})
@TableIndex(name: 'idx_cards_state', columns: {#state})
class Cards extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get lexemeId => integer().references(Lexemes, #id, onDelete: KeyAction.cascade)();
  IntColumn get senseId => integer().references(Senses, #id, onDelete: KeyAction.cascade)();
  TextColumn get direction => text()(); // recognize_en_ru | recall_ru_en | cloze | listening | collocation_pick
  TextColumn get state => text().withDefault(const Constant('new'))(); // new | learning | review | relearning
  DateTimeColumn get due => dateTime().withDefault(currentDateAndTime)();
  RealColumn get stability => real().withDefault(const Constant(0.0))();
  RealColumn get difficulty => real().withDefault(const Constant(0.0))();
  IntColumn get elapsedDays => integer().withDefault(const Constant(0))();
  IntColumn get scheduledDays => integer().withDefault(const Constant(0))();
  IntColumn get reps => integer().withDefault(const Constant(0))();
  IntColumn get lapses => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastReview => dateTime().nullable()();
  BoolColumn get suspended => boolean().withDefault(const Constant(false))();
}

class ReviewLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get cardId => integer().references(Cards, #id, onDelete: KeyAction.cascade)();
  IntColumn get rating => integer()(); // 1 Again, 2 Hard, 3 Good, 4 Easy
  IntColumn get responseMs => integer()();
  DateTimeColumn get reviewAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get stateBefore => text()();
  TextColumn get exerciseType => text()();
  BoolColumn get correct => boolean()();
}

@DataClassName('ReadingText')
class Texts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();
  TextColumn get body => text()();
  TextColumn get source => text().nullable()();
  RealColumn get knownRatio => real().withDefault(const Constant(0.0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('SettingEntry')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

class DailyStats extends Table {
  TextColumn get date => text()(); // YYYY-MM-DD
  IntColumn get newCards => integer().withDefault(const Constant(0))();
  IntColumn get reviews => integer().withDefault(const Constant(0))();
  IntColumn get minutes => integer().withDefault(const Constant(0))();
  RealColumn get correctRatio => real().withDefault(const Constant(0.0))();

  @override
  Set<Column> get primaryKey => {date};
}
