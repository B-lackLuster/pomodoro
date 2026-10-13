import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/core/study_day.dart';
import 'package:pomodoro/data/settings_store.dart';

void main() {
  test('默认四点跨天，包括月末和年末', () {
    expect(studyDayKey(DateTime(2027, 1, 1, 3, 59, 59)), '2026-12-31');
    expect(studyDayKey(DateTime(2027, 1, 1, 4)), '2027-01-01');
    expect(studyDayKey(DateTime(2026, 10, 1, 2)), '2026-09-30');
    expect(const StoredSettings().dailyResetHour, 4);
    expect(StoredSettings.fromJson({}).dailyResetHour, 4);
  });

  test('按准确边界安排下一次刷新，恰好四点时安排明天', () {
    expect(
      nextStudyDayBoundary(DateTime(2026, 10, 13, 3, 59, 59)),
      DateTime(2026, 10, 13, 4),
    );
    expect(
      nextStudyDayBoundary(DateTime(2026, 10, 13, 4)),
      DateTime(2026, 10, 14, 4),
    );
    expect(
      nextStudyDayBoundary(DateTime(2026, 12, 31, 22)),
      DateTime(2027, 1, 1, 4),
    );
  });

  test('保留显式设置的自然日，非法小时限制在有效范围', () {
    expect(StoredSettings.fromJson({'dailyResetHour': 0}).dailyResetHour, 0);
    expect(StoredSettings.fromJson({'dailyResetHour': 99}).dailyResetHour, 23);
    expect(studyDayKey(DateTime(2026, 10, 13, 0), resetHour: 0), '2026-10-13');
  });
}
