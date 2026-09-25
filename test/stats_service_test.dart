import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/core/models.dart';
import 'package:pomodoro/data/models.dart';
import 'package:pomodoro/data/stats_service.dart';

void main() {
  final today = DateTime(2026, 9, 6); // 周日
  DateTime day(int offset) => today.subtract(Duration(days: offset));

  PomodoroLog focusLog(DateTime start, {int minutes = 25, bool completed = true}) {
    return PomodoroLog(
      id: 'log_${start.microsecondsSinceEpoch}',
      phase: PomodoroPhase.focus,
      completed: completed,
      start: start,
      end: start.add(Duration(minutes: minutes)),
    );
  }

  test('今日/本周/本月/累计计数', () {
    final logs = [
      focusLog(today.add(const Duration(hours: 9))),
      focusLog(today.add(const Duration(hours: 14))),
      focusLog(day(1).add(const Duration(hours: 10))), // 昨天（本周）
      focusLog(day(3).add(const Duration(hours: 10))), // 本周内
      focusLog(DateTime(today.year, today.month, 1)), // 本月 1 号（本周内）
      focusLog(DateTime(today.year, 1, 15)), // 一月（本月外）
    ];
    final s = computeStats(logs, now: today.add(const Duration(hours: 20)));

    expect(s.todayCount, 2);
    expect(s.weekCount, 5);
    expect(s.monthCount, 5);
    expect(s.totalCount, 6);
    expect(s.todayMinutes, 50);
  });

  test('未完成的（跳过）不计入统计', () {
    final logs = [
      focusLog(today, completed: true),
      PomodoroLog(
        id: 'skipped',
        phase: PomodoroPhase.focus,
        completed: false,
        start: today,
        end: today.add(const Duration(minutes: 10)),
      ),
    ];
    final s = computeStats(logs, now: today.add(const Duration(hours: 12)));
    expect(s.todayCount, 1);
    expect(s.totalCount, 1);
  });

  test('连续打卡：今天有则含今天，没有则从昨天数', () {
    final withToday = [
      focusLog(today),
      focusLog(day(1)),
      focusLog(day(2)),
      focusLog(day(4)), // 断档
    ];
    expect(computeStats(withToday, now: today).streakDays, 3);

    final withoutToday = [
      focusLog(day(1)),
      focusLog(day(2)),
    ];
    expect(computeStats(withoutToday, now: today).streakDays, 2);
  });

  test('近 7 天序列长度与旧→新排序', () {
    final logs = [focusLog(today), focusLog(day(6))];
    final s = computeStats(logs, now: today);
    expect(s.last7Days.length, 7);
    expect(s.last7Days.first.day, day(6));
    expect(s.last7Days.last.day, today);
    expect(s.last7Days.last.count, 1);
    expect(s.last7Days.first.count, 1);
    expect(s.last7Days[3].count, 0);
  });
}
