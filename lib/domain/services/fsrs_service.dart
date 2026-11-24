import 'dart:math' as math;

class FsrsResult {
  final String state; // learning | review | relearning
  final double stability;
  final double difficulty;
  final int elapsedDays;
  final int scheduledDays;
  final int reps;
  final int lapses;
  final DateTime due;

  FsrsResult({
    required this.state,
    required this.stability,
    required this.difficulty,
    required this.elapsedDays,
    required this.scheduledDays,
    required this.reps,
    required this.lapses,
    required this.due,
  });
}

class FsrsService {
  // Параметры FSRS-4.5 по умолчанию
  static const List<double> w = [
    0.4, 0.6, 2.4, 5.8, 4.93, 0.94, 0.86, 0.01,
    1.49, 0.14, 0.94, 2.18, 0.05, 0.34, 1.26, 0.29, 2.61,
  ];

  /// rating: 1 = Again, 2 = Hard, 3 = Good, 4 = Easy
  FsrsResult review({
    required String currentState,
    required double currentStability,
    required double currentDifficulty,
    required int reps,
    required int lapses,
    required DateTime? lastReview,
    required int rating,
    double desiredRetention = 0.9,
    DateTime? now,
  }) {
    final currentTime = now ?? DateTime.now();
    final elapsedDays = lastReview == null
        ? 0
        : math.max(0, currentTime.difference(lastReview).inDays);

    double s = currentStability;
    double d = currentDifficulty;
    int newReps = reps + 1;
    int newLapses = lapses;
    String newState;
    int scheduledDays;
    DateTime due;

    if (currentState == 'new' || reps == 0) {
      d = _initDifficulty(rating);
      s = _initStability(rating);

      if (rating == 1) {
        newState = 'learning';
        scheduledDays = 0;
        due = currentTime.add(const Duration(minutes: 1));
      } else if (rating == 2) {
        newState = 'learning';
        scheduledDays = 0;
        due = currentTime.add(const Duration(minutes: 10));
      } else if (rating == 3) {
        newState = 'review';
        scheduledDays = _nextInterval(s, desiredRetention);
        due = currentTime.add(Duration(days: scheduledDays));
      } else {
        newState = 'review';
        scheduledDays = math.max(2, _nextInterval(s, desiredRetention));
        due = currentTime.add(Duration(days: scheduledDays));
      }
    } else {
      final retrievability = _retrievability(elapsedDays, s);
      d = _nextDifficulty(d, rating);

      if (rating == 1) {
        newLapses += 1;
        newState = 'relearning';
        s = _nextForgetStability(d, s, retrievability);
        scheduledDays = 0;
        due = currentTime.add(const Duration(minutes: 5));
      } else {
        newState = 'review';
        s = _nextRecallStability(d, s, retrievability, rating);
        scheduledDays = _nextInterval(s, desiredRetention);
        if (rating == 2) {
          scheduledDays = math.max(1, (scheduledDays * 0.8).round());
        } else if (rating == 4) {
          scheduledDays = math.max(scheduledDays + 1, (scheduledDays * 1.3).round());
        }
        due = currentTime.add(Duration(days: scheduledDays));
      }
    }

    return FsrsResult(
      state: newState,
      stability: s,
      difficulty: d,
      elapsedDays: elapsedDays,
      scheduledDays: scheduledDays,
      reps: newReps,
      lapses: newLapses,
      due: due,
    );
  }

  double _initStability(int rating) => math.max(0.1, w[rating - 1]);

  double _initDifficulty(int rating) {
    final val = w[4] - (rating - 3) * w[5];
    return val.clamp(1.0, 10.0);
  }

  double _retrievability(int elapsedDays, double stability) {
    if (stability <= 0) return 0.9;
    return math.pow(1 + elapsedDays / (9 * stability), -1).toDouble();
  }

  double _nextDifficulty(double d, int rating) {
    final nextD = d - w[6] * (rating - 3);
    // Mean reversion к начальной сложности
    final meanReverted = w[7] * _initDifficulty(3) + (1 - w[7]) * nextD;
    return meanReverted.clamp(1.0, 10.0);
  }

  double _nextRecallStability(double d, double s, double r, int rating) {
    final hardPenalty = rating == 2 ? w[15] : 1.0;
    final easyBonus = rating == 4 ? w[16] : 1.0;
    final factor = math.exp(w[8]) *
        (11 - d) *
        math.pow(s, -w[9]) *
        (math.exp((1 - r) * w[10]) - 1) *
        hardPenalty *
        easyBonus;
    return math.max(0.1, s * (1 + factor));
  }

  double _nextForgetStability(double d, double s, double r) {
    final val = w[11] *
        math.pow(d, -w[12]) *
        (math.pow(s + 1, w[13]) - 1) *
        math.exp((1 - r) * w[14]);
    return math.max(0.1, math.min(s, val));
  }

  int _nextInterval(double stability, double desiredRetention) {
    final interval = stability * 9 * (1 / desiredRetention - 1);
    return math.max(1, interval.round());
  }

  /// Автооценка по правильности и времени ответа (мс)
  static int autoRate({required bool isCorrect, required int responseMs}) {
    if (!isCorrect) return 1; // Again
    if (responseMs > 8000) return 2; // Hard (медленно — режим до автоматизма)
    if (responseMs < 2500) return 4; // Easy (очень быстро)
    return 3; // Good
  }

  /// Проверка введённого ответа с допуском 1 опечатки для слов длиной > 4
  static bool isAnswerCorrect(String input, String target) {
    final a = input.trim().toLowerCase();
    final b = target.trim().toLowerCase();
    if (a == b) return true;
    if (b.length > 4 && levenshtein(a, b) <= 1) return true;
    return false;
  }

  static int levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    final v0 = List<int>.generate(t.length + 1, (i) => i);
    final v1 = List<int>.filled(t.length + 1, 0);

    for (int i = 0; i < s.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < t.length; j++) {
        final cost = (s[i] == t[j]) ? 0 : 1;
        v1[j + 1] = math.min(
          math.min(v1[j] + 1, v0[j + 1] + 1),
          v0[j] + cost,
        );
      }
      for (int j = 0; j <= t.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v0[t.length];
  }
}
