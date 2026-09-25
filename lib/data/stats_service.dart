import '../core/models.dart';
import 'models.dart';

/// 统计汇总（纯函数计算，便于单测）
class StatsSummary {
  const StatsSummary({
    required this.todayCount,
    required this.todayMinutes,
    required this.weekCount,
    required this.monthCount,
    required this.totalCount,
    required this.streakDays,
    required this.last7Days,
  });

  final int todayCount;
  final int todayMinutes;
  final int weekCount;
  final int monthCount;
  final int totalCount;

  /// 连续打卡天数（今天或昨天往前推，每天至少 1 个完成番茄）
  final int streakDays;

  /// 近 7 天（含今天）每天完成数，旧 → 新
  final List<DailyCount> last7Days;
}

class DailyCount {
  const DailyCount({required this.day, required this.count, required this.minutes});

  /// 当天零点
  final DateTime day;
  final int count;
  final int minutes;
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

StatsSummary computeStats(List<PomodoroLog> logs, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final today = DateTime(ref.year, ref.month, ref.day);
  final weekStart = today.subtract(Duration(days: today.weekday - 1)); // 周一
  final monthStart = DateTime(ref.year, ref.month);

  final focus = logs
      .where((l) => l.phase == PomodoroPhase.focus && l.completed)
      .toList()
    ..sort((a, b) => a.start.compareTo(b.start));

  var todayCount = 0, todayMinutes = 0;
  var weekCount = 0, monthCount = 0;
  final byDay = <DateTime, DailyCount>{};

  for (final l in focus) {
    final start = DateTime(l.start.year, l.start.month, l.start.day);
    final minutes = l.countedDuration.inMinutes;

    if (_sameDay(start, today)) {
      todayCount += 1;
      todayMinutes += minutes;
    }
    if (!start.isBefore(weekStart)) weekCount += 1;
    if (!start.isBefore(monthStart)) monthCount += 1;

    final entry = byDay[start];
    byDay[start] = DailyCount(
      day: start,
      count: (entry?.count ?? 0) + 1,
      minutes: (entry?.minutes ?? 0) + minutes,
    );
  }

  final last7Days = List.generate(7, (i) {
    final day = today.subtract(Duration(days: 6 - i));
    return byDay[day] ?? DailyCount(day: day, count: 0, minutes: 0);
  });

  // 连续打卡：从今天往前数；今天还没有完成则从昨天开始数
  var streak = 0;
  var cursor = byDay.containsKey(today) ? today : today.subtract(const Duration(days: 1));
  while (byDay.containsKey(cursor)) {
    streak += 1;
    cursor = cursor.subtract(const Duration(days: 1));
  }

  return StatsSummary(
    todayCount: todayCount,
    todayMinutes: todayMinutes,
    weekCount: weekCount,
    monthCount: monthCount,
    totalCount: focus.length,
    streakDays: streak,
    last7Days: last7Days,
  );
}
