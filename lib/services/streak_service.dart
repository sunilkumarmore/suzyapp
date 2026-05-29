import 'package:shared_preferences/shared_preferences.dart';

class StreakService {
  static const _kCount = 'streak_count_v1';
  static const _kLastDate = 'streak_last_date_v1';

  static String _today() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String _dateStr(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Records a reading session for today. Returns the new streak count.
  static Future<int> recordToday() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _today();
    final last = prefs.getString(_kLastDate);
    final current = prefs.getInt(_kCount) ?? 0;

    if (last == today) return current; // already recorded today

    // Compute yesterday using calendar arithmetic (DST-safe)
    final now = DateTime.now();
    final yesterday = _dateStr(
      DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1)),
    );

    final newCount = (last == yesterday) ? current + 1 : 1;
    await prefs.setInt(_kCount, newCount);
    await prefs.setString(_kLastDate, today);
    return newCount;
  }

  /// Returns current streak count without modifying it.
  static Future<int> getStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kCount) ?? 0;
  }
}
