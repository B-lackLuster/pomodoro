import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/core/models.dart';
import 'package:pomodoro/core/timer_engine.dart';
import 'package:pomodoro/data/models.dart';
import 'package:pomodoro/data/stats_service.dart';

void main() {
  late DateTime now;
  late PomodoroEngine engine;
  setUp(() {
    now = DateTime(2026, 10, 17, 9);
    engine = PomodoroEngine(
      now: () => now,
      tickInterval: const Duration(days: 1),
    );
  });
  tearDown(() => engine.dispose());

  void advance(Duration time) {
    now = now.add(time);
    engine.debugTick();
  }

  void complete(int count) {
    for (var i = 0; i < count; i++) {
      engine.start();
      advance(const Duration(minutes: 25));
      if (i < count - 1) engine.skip();
    }
  }

  test('恰好一半不计数，多一微秒即计数，使用点击时的实际剩余时间', () {
    engine.start();
    advance(const Duration(minutes: 12, seconds: 30));
    engine.skip();
    expect(engine.state.completedFocusToday, 0);
    engine.skip();
    engine.start();
    // 不触发心跳，检验点击与显示刷新之间的时间也能正确结算。
    now = now.add(const Duration(minutes: 12, seconds: 30, microseconds: 1));
    engine.skip();
    expect(engine.state.completedFocusToday, 1);
    expect(engine.state.focusInCycle, 1);
    expect(engine.state.phase, PomodoroPhase.shortBreak);
  });

  test('十分钟专注加三十分钟暂停，不会因墙钟时间过半而计数', () {
    engine.start();
    advance(const Duration(minutes: 10));
    engine.pause();
    advance(const Duration(minutes: 30));
    engine.skip();
    expect(engine.state.completedFocusToday, 0);
  });

  test('暂停前后实际专注相加，超过一半时跳过只计一次', () {
    engine.start();
    advance(const Duration(minutes: 8));
    engine.pause();
    advance(const Duration(minutes: 5));
    engine.start();
    advance(const Duration(minutes: 5));
    engine.skip();
    expect(engine.state.completedFocusToday, 1);
    engine.skip();
    engine.skip(); // 尚未开始的下一专注不计数。
    expect(engine.state.completedFocusToday, 1);
  });

  test('三次完整完成加一次过半跳过，触发长休；长休后重新累计', () {
    complete(3);
    engine.skip();
    engine.start();
    advance(const Duration(minutes: 13));
    engine.skip();
    expect(engine.state.completedFocusToday, 4);
    expect(engine.state.phase, PomodoroPhase.longBreak);
    expect(engine.state.focusInCycle, 4);
    engine.skip();
    expect(engine.state.focusInCycle, 0);
    complete(1);
    expect(engine.state.completedFocusToday, 5);
    expect(engine.state.phase, PomodoroPhase.shortBreak);
    expect(engine.state.focusInCycle, 1);
  });

  test('第4次专注未过半就跳过，中断连续进度，今日已完成数保留', () {
    complete(3);
    engine.skip();
    engine.start();
    advance(const Duration(minutes: 12));
    engine.skip();
    expect(engine.state.focusInCycle, 0);
    expect(engine.state.completedFocusToday, 3);
    expect(engine.state.phase, PomodoroPhase.shortBreak);
    engine.skip();
    complete(1);
    expect(engine.state.focusInCycle, 1);
    expect(engine.state.completedFocusToday, 4);
    expect(engine.state.phase, PomodoroPhase.shortBreak);
  });

  test('连续3次后，当前专注暂停超过25分钟，恢复后只算新一轮第1次', () {
    complete(3);
    engine.skip();
    engine.start();
    advance(const Duration(minutes: 10));
    engine.pause();
    advance(const Duration(minutes: 25, seconds: 1));
    expect(engine.state.focusInCycle, 0);
    expect(engine.state.completedFocusToday, 3);
    engine.start();
    advance(const Duration(minutes: 15));
    expect(engine.state.completedFocusToday, 4);
    expect(engine.state.focusInCycle, 1);
    expect(engine.state.phase, PomodoroPhase.shortBreak);
  });

  test('暂停恰好25分钟仍连续，超过25分钟才重新累计', () {
    complete(3);
    engine.skip();
    engine.start();
    advance(const Duration(minutes: 1));
    engine.pause();
    advance(const Duration(minutes: 25));
    expect(engine.state.focusInCycle, 3);
    engine.start();
    advance(const Duration(minutes: 24));
    expect(engine.state.phase, PomodoroPhase.longBreak);
    expect(engine.state.completedFocusToday, 4);
  });

  test('正常短休5分钟不会中断连续完成', () {
    for (var i = 0; i < 4; i++) {
      engine.start();
      advance(const Duration(minutes: 25));
      if (i < 3) advance(const Duration(minutes: 5));
    }
    expect(engine.state.completedFocusToday, 4);
    expect(engine.state.phase, PomodoroPhase.longBreak);
  });

  testWidgets('暂停超过阈值时自动刷新连续进度，不必点击恢复', (tester) async {
    complete(3);
    engine.skip();
    engine.start();
    engine.pause();
    expect(engine.state.focusInCycle, 3);
    now = now.add(const Duration(minutes: 25));
    await tester.pump(const Duration(minutes: 25));
    expect(engine.state.focusInCycle, 3);
    now = now.add(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
    expect(engine.state.focusInCycle, 0);
    expect(engine.state.completedFocusToday, 3);
  });

  test('短休加等待合计超过25分钟，会清连续进度；每天多次间隔均只短休', () {
    for (var i = 0; i < 5; i++) {
      engine.start();
      advance(const Duration(minutes: 25));
      expect(engine.state.phase, PomodoroPhase.shortBreak);
      if (i < 4) {
        advance(const Duration(minutes: 5));
        now = now.add(const Duration(minutes: 21)); // 待开始时没有计时心跳。
      }
    }
    expect(engine.state.completedFocusToday, 5);
    expect(engine.state.focusInCycle, 1);
  });

  test('自定义50分钟专注，过半及中断阈值随当前阶段时长变化', () {
    engine.updateConfig(const PomodoroConfig(focusMinutes: 50));
    engine.start();
    advance(const Duration(minutes: 26));
    engine.skip();
    expect(engine.state.completedFocusToday, 1);
    engine.skip();
    advance(const Duration(minutes: 30));
    engine.start();
    advance(const Duration(minutes: 50));
    expect(engine.state.focusInCycle, 2);
  });

  test('暂停期间修改配置不改变进行中阶段的过半判定', () {
    engine.start();
    advance(const Duration(minutes: 10));
    engine.pause();
    engine.updateConfig(const PomodoroConfig(focusMinutes: 10));
    engine.skip();
    expect(engine.state.completedFocusToday, 0);
  });

  test('过半跳过的完成事件、持久化记录和统计一致，扣除暂停分钟', () async {
    final events = <PhaseCompletion>[];
    final sub = engine.completions.listen(events.add);
    engine.start();
    advance(const Duration(minutes: 8));
    engine.pause();
    advance(const Duration(minutes: 20));
    engine.start();
    advance(const Duration(minutes: 7));
    engine.skip();
    await Future<void>.delayed(Duration.zero);
    final event = events.single;
    expect(event.manualSkip, true);
    expect(event.completed, true);
    expect(event.activeDuration, const Duration(minutes: 15));
    expect(
      event.endedAt.difference(event.startedAt),
      const Duration(minutes: 35),
    );
    final log = PomodoroLog(
      id: 'counted-skip',
      phase: event.fromPhase,
      completed: event.completed,
      start: event.startedAt,
      end: event.endedAt,
      activeSeconds: event.activeDuration.inMicroseconds / 1000000,
    );
    final restored = PomodoroLog.fromJson(log.toJson());
    final stats = computeStats([restored], now: now, resetHour: 4);
    expect(stats.todayCount, engine.state.completedFocusToday);
    expect(stats.monthCount, 1);
    expect(stats.todayMinutes, 15);
    await sub.cancel();
  });

  test('旧记录缺少实际时长字段时仍可读取，完成属性不重算', () {
    final log = PomodoroLog.fromJson({
      'id': 'legacy',
      'phase': 'focus',
      'completed': false,
      'start': now.toIso8601String(),
      'end': now.add(const Duration(minutes: 16)).toIso8601String(),
    });
    expect(log.countedDuration, const Duration(minutes: 16));
    expect(log.completed, false);
  });

  test('自然完成的实际时长也扣除暂停', () async {
    final events = <PhaseCompletion>[];
    final sub = engine.completions.listen(events.add);
    engine.start();
    advance(const Duration(minutes: 10));
    engine.pause();
    advance(const Duration(minutes: 30));
    engine.start();
    advance(const Duration(minutes: 15));
    await Future<void>.delayed(Duration.zero);
    expect(events.single.activeDuration, const Duration(minutes: 25));
    expect(events.single.completed, true);
    await sub.cancel();
  });
}
