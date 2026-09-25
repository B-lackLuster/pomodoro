import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/core/models.dart';
import 'package:pomodoro/core/timer_engine.dart';

void main() {
  late DateTime current;
  late PomodoroEngine engine;

  setUp(() {
    current = DateTime(2026, 9, 6, 9, 0, 0);
    // 心跳间隔设为 1 小时：测试期间真实定时器永不触发，
    // 时间推进完全由注入时钟 + debugTick() 控制，保证确定性
    engine = PomodoroEngine(
      now: () => current,
      tickInterval: const Duration(hours: 1),
    );
  });

  tearDown(() {
    engine.dispose();
  });

  void advance(Duration d) {
    current = current.add(d);
    engine.debugTick();
  }

  group('基础计时', () {
    test('初始状态：专注 25 分钟，待开始', () {
      expect(engine.state.phase, PomodoroPhase.focus);
      expect(engine.state.status, PomodoroStatus.idle);
      expect(engine.state.remaining, const Duration(minutes: 25));
      expect(engine.state.clockText, '25:00');
      expect(engine.state.progress, 0);
    });

    test('开始后随时间递减', () {
      engine.start();
      advance(const Duration(minutes: 10));
      expect(engine.state.isRunning, true);
      expect(engine.state.remaining, const Duration(minutes: 15));
      expect(engine.state.clockText, '15:00');
      expect(engine.state.progress, closeTo(0.4, 0.001));
    });

    test('暂停后时间冻结，继续后从剩余时长接着走', () {
      engine.start();
      advance(const Duration(minutes: 10));
      engine.pause();
      expect(engine.state.status, PomodoroStatus.paused);
      expect(engine.state.remaining, const Duration(minutes: 15));

      // 暂停期间流逝 30 分钟，剩余时间不应变化
      advance(const Duration(minutes: 30));
      expect(engine.state.remaining, const Duration(minutes: 15));

      engine.start();
      advance(const Duration(minutes: 14));
      expect(engine.state.remaining, const Duration(minutes: 1));
    });

    test('时间戳回拨（系统休眠后恢复）不会把剩余时间算成负数', () {
      engine.start();
      advance(const Duration(minutes: 24, seconds: 59));
      engine.pause();
      engine.start();
      advance(const Duration(minutes: 10));
      // endAt 已过：走完剩余并进入下一阶段
      expect(engine.state.phase, PomodoroPhase.shortBreak);
      expect(engine.state.completedFocusToday, 1);
    });
  });

  group('阶段流转', () {
    test('专注自然结束 → 完成数 +1 → 进入短休息并自动开始', () {
      engine.start();
      advance(const Duration(minutes: 25));
      expect(engine.state.phase, PomodoroPhase.shortBreak);
      expect(engine.state.completedFocusToday, 1);
      expect(engine.state.focusInCycle, 1);
      expect(engine.state.isRunning, true, reason: '默认 autoStartBreak=true');
    });

    test('默认配置：第 4 个番茄完成后进入长休息', () {
      for (var i = 0; i < 3; i++) {
        engine.start();
        advance(const Duration(minutes: 25)); // focus 完成 → 短休息自动开始
        engine.skip(); // 跳过短休息 → 回到专注
      }
      engine.start();
      advance(const Duration(minutes: 25));
      expect(engine.state.phase, PomodoroPhase.longBreak);
      expect(engine.state.completedFocusToday, 4);
      expect(engine.state.focusInCycle, 4);
    });

    test('手动跳过专注不计完成数，也不自动开始下一阶段', () {
      engine.start();
      advance(const Duration(minutes: 10));
      engine.skip();
      expect(engine.state.phase, PomodoroPhase.shortBreak);
      expect(engine.state.completedFocusToday, 0);
      expect(engine.state.status, PomodoroStatus.idle);
    });

    test('autoStartFocus=false 时休息结束停在待开始', () {
      engine.start();
      advance(const Duration(minutes: 25)); // → 短休息（自动开始）
      advance(const Duration(minutes: 5)); // → 专注（不自动开始）
      expect(engine.state.phase, PomodoroPhase.focus);
      expect(engine.state.status, PomodoroStatus.idle);
      expect(engine.state.completedFocusToday, 1);
    });

    test('长休息结束后循环继续，按模轮转', () {
      for (var i = 0; i < 3; i++) {
        engine.start();
        advance(const Duration(minutes: 25));
        engine.skip();
      }
      engine.start();
      advance(const Duration(minutes: 25)); // 第 4 个完成 → 长休息
      expect(engine.state.phase, PomodoroPhase.longBreak);
      engine.skip(); // 跳过长休息 → 专注
      expect(engine.state.phase, PomodoroPhase.focus);
      engine.start();
      advance(const Duration(minutes: 25)); // 第 5 个完成 → 短休息
      expect(engine.state.phase, PomodoroPhase.shortBreak);
      expect(engine.state.focusInCycle, 5);
      expect(engine.state.completedFocusToday, 5);
    });

    test('resetAll 回到专注并清空循环进度，保留今日计数', () {
      engine.start();
      advance(const Duration(minutes: 25));
      engine.resetAll();
      expect(engine.state.phase, PomodoroPhase.focus);
      expect(engine.state.focusInCycle, 0);
      expect(engine.state.completedFocusToday, 1);
      expect(engine.state.remaining, const Duration(minutes: 25));
    });

    test('resetPhase 只重置当前阶段', () {
      engine.start();
      advance(const Duration(minutes: 10));
      engine.resetPhase();
      expect(engine.state.remaining, const Duration(minutes: 25));
      expect(engine.state.status, PomodoroStatus.idle);
    });
  });

  group('配置更新', () {
    test('未开始的阶段立即应用新时长', () {
      engine.updateConfig(const PomodoroConfig(focusMinutes: 50));
      expect(engine.state.duration, const Duration(minutes: 50));
      expect(engine.state.remaining, const Duration(minutes: 50));
    });

    test('运行中的阶段不受影响，下一阶段使用新配置', () {
      engine.start();
      engine.updateConfig(const PomodoroConfig(focusMinutes: 50));
      expect(engine.state.remaining, const Duration(minutes: 25));

      advance(const Duration(minutes: 25));
      expect(engine.state.phase, PomodoroPhase.shortBreak);
      expect(engine.state.duration, const Duration(minutes: 5));
    });
  });

  group('状态流', () {
    test('状态变化通过广播流发出', () async {
      final emissions = <PomodoroState>[];
      final sub = engine.stream.listen(emissions.add);
      engine.start();
      advance(const Duration(minutes: 5));
      await Future<void>.delayed(Duration.zero);
      expect(emissions, isNotEmpty);
      expect(emissions.last.remaining, const Duration(minutes: 20));
      await sub.cancel();
    });

    test('阶段完成事件流：自然完成与手动跳过都发出事件并携带标记', () async {
      final events = <PhaseCompletion>[];
      final sub = engine.completions.listen(events.add);
      engine.start();
      advance(const Duration(minutes: 25)); // 专注自然完成 → 短休息
      engine.skip(); // 手动跳过短休息 → 专注
      await Future<void>.delayed(Duration.zero);
      expect(events.length, 2);

      expect(events[0].fromPhase, PomodoroPhase.focus);
      expect(events[0].toPhase, PomodoroPhase.shortBreak);
      expect(events[0].toDuration, const Duration(minutes: 5));
      expect(events[0].manualSkip, false);
      expect(events[0].completedFocusToday, 1);
      // 起止时间戳：阶段从 9:00 开始，9:25 结束
      expect(events[0].startedAt, DateTime(2026, 9, 6, 9, 0, 0));
      expect(events[0].endedAt, DateTime(2026, 9, 6, 9, 25, 0));

      expect(events[1].fromPhase, PomodoroPhase.shortBreak);
      expect(events[1].toPhase, PomodoroPhase.focus);
      expect(events[1].manualSkip, true);
      expect(events[1].completedFocusToday, 1);
      await sub.cancel();
    });
  });
}
