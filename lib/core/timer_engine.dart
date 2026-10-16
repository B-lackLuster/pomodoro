import 'dart:async';

import 'package:meta/meta.dart';

import 'models.dart';
import 'study_day.dart';

/// 一次阶段切换（自然结束或手动跳过）
class PhaseCompletion {
  const PhaseCompletion({
    required this.fromPhase,
    required this.toPhase,
    required this.toDuration,
    required this.manualSkip,
    required this.completed,
    required this.activeDuration,
    required this.completedFocusToday,
    required this.startedAt,
    required this.endedAt,
  });

  final PomodoroPhase fromPhase;
  final PomodoroPhase toPhase;

  /// 新阶段的总时长
  final Duration toDuration;
  final bool manualSkip;

  /// 达到计数条件（含实际专注过半后跳过），与手动跳过的动作独立。
  final bool completed;

  /// 实际计时时长，扣除暂停与未开始的等待。
  final Duration activeDuration;
  final int completedFocusToday;

  /// 被结束阶段的实际开始时刻（用于写入番茄记录）
  final DateTime startedAt;

  /// 被结束阶段的结束时刻
  final DateTime endedAt;
}

/// 纯 Dart 番茄钟引擎（无 Flutter / 平台依赖），三端共用同一份逻辑。
///
/// 计时基于绝对时间戳（_endAt）而不是"每秒减一"：
/// 进程挂起、系统休眠、前后台切换后恢复时，剩余时间依然按真实墙钟计算。
/// 心跳定时器只负责刷新显示，到点判断完全由时间戳决定。
class PomodoroEngine {
  PomodoroEngine({
    DateTime Function()? now,
    int dailyResetHour = 4,
    this.tickInterval = const Duration(milliseconds: 200),
  }) : _now = now ?? DateTime.now,
       _dailyResetHour = dailyResetHour {
    _day = studyDayKey(_now(), resetHour: _dailyResetHour);
  }

  int _dailyResetHour;
  late String _day;

  void updateDailyResetHour(int hour) {
    _dailyResetHour = hour.clamp(0, 23);
    _refreshDay();
  }

  void _refreshDay() {
    final day = studyDayKey(_now(), resetHour: _dailyResetHour);
    if (day == _day) return;
    _day = day;
    _state = _copyWith(completedFocusToday: 0);
    _emit();
  }

  /// 可注入时钟，供测试使用
  final DateTime Function() _now;

  final Duration tickInterval;

  Timer? _ticker;
  Timer? _continuityTimer;
  DateTime? _endAt;
  DateTime? _interruptionStartedAt;
  Duration _interruptionLimit = const Duration(minutes: 25);

  /// 当前阶段开始计时的时刻（日志记录用；未运行时为 null）
  DateTime? _phaseStartedAt;

  PomodoroConfig _config = const PomodoroConfig();

  PomodoroState _state = PomodoroState(
    phase: PomodoroPhase.focus,
    status: PomodoroStatus.idle,
    duration: const Duration(minutes: 25),
    remaining: const Duration(minutes: 25),
    completedFocusToday: 0,
    focusInCycle: 0,
  );

  final StreamController<PomodoroState> _controller =
      StreamController<PomodoroState>.broadcast();

  final StreamController<PhaseCompletion> _completionsController =
      StreamController<PhaseCompletion>.broadcast();

  PomodoroState get state => _state;
  Stream<PomodoroState> get stream => _controller.stream;

  /// 阶段切换事件（含手动跳过），供通知/提示音等副作用订阅
  Stream<PhaseCompletion> get completions => _completionsController.stream;
  PomodoroConfig get config => _config;
  DateTime? get endAt => _endAt;

  /// 休息、待开始和手动暂停均属于两段专注之间的停顿。
  void _beginInterruption(DateTime at, Duration focusDuration) {
    if (_interruptionStartedAt != null) return;
    _interruptionStartedAt = at;
    _interruptionLimit = focusDuration;
    _continuityTimer?.cancel();
    final deadline = at.add(focusDuration).add(const Duration(microseconds: 1));
    final delay = deadline.difference(_now());
    // Timer uses milliseconds; round up so strict "longer than" never fires early.
    final delayMs = (delay.inMicroseconds / 1000).ceil();
    _continuityTimer = Timer(
      Duration(milliseconds: delayMs < 0 ? 0 : delayMs),
      () {
        if (_expireContinuity(_now())) _emit();
      },
    );
  }

  bool _expireContinuity(DateTime at) {
    final interruption = _interruptionStartedAt;
    if (interruption == null ||
        at.difference(interruption) <= _interruptionLimit ||
        _state.focusInCycle == 0) {
      return false;
    }
    _state = _copyWith(focusInCycle: 0);
    return true;
  }

  void _endInterruption() {
    _continuityTimer?.cancel();
    _continuityTimer = null;
    _interruptionStartedAt = null;
  }

  Duration _remainingAt(DateTime at) {
    final remaining = _state.isRunning && _endAt != null
        ? _endAt!.difference(at)
        : _state.remaining;
    return Duration(
      microseconds: remaining.inMicroseconds.clamp(
        0,
        _state.duration.inMicroseconds,
      ),
    );
  }

  /// 更新配置。尚未开始时立即应用；运行或暂停的阶段保持不变，下一阶段生效。
  void updateConfig(PomodoroConfig config) {
    _config = config;
    if (_state.status != PomodoroStatus.idle) return;
    final phaseDuration = _durationOf(_state.phase);
    final notStarted = _state.remaining == _state.duration;
    _state = _copyWith(
      duration: phaseDuration,
      remaining: notStarted ? phaseDuration : _state.remaining,
    );
    _emit();
  }

  void start() {
    _refreshDay();
    _expireContinuity(_now());
    if (_state.isRunning) return;
    final wasIdle = _state.status == PomodoroStatus.idle;
    final remaining = _state.status == PomodoroStatus.paused
        ? _state.remaining
        : _state.duration;
    if (remaining <= Duration.zero) return;
    if (_state.phase == PomodoroPhase.focus) _endInterruption();
    _endAt = _now().add(remaining);
    if (wasIdle) _phaseStartedAt = _now();
    _state = _copyWith(status: PomodoroStatus.running, remaining: remaining);
    _startTicker();
    _emit();
  }

  void toggle() => _state.isRunning ? pause() : start();

  void pause() {
    if (!_state.isRunning) return;
    _refreshDay();
    if (!_endAt!.isAfter(_now())) {
      _advance(manualSkip: false);
      return;
    }
    _stopTicker();
    final remaining = _endAt!.difference(_now());
    _endAt = null;
    _state = _copyWith(
      status: PomodoroStatus.paused,
      remaining: remaining.isNegative ? Duration.zero : remaining,
    );
    if (_state.phase == PomodoroPhase.focus) {
      _beginInterruption(_now(), _state.duration);
    }
    _emit();
  }

  /// 重置当前阶段到初始时长；重置专注会中断连续进度，保留今日计数。
  void resetPhase() {
    final now = _now();
    if (_state.phase == PomodoroPhase.focus) {
      _beginInterruption(now, _state.duration);
    }
    _expireContinuity(now);
    _stopTicker();
    _endAt = null;
    _phaseStartedAt = null;
    final d = _durationOf(_state.phase);
    _state = _copyWith(
      status: PomodoroStatus.idle,
      duration: d,
      remaining: d,
      focusInCycle: _state.phase == PomodoroPhase.focus ? 0 : null,
    );
    _emit();
  }

  /// 完全重置：回到专注阶段、清空循环进度（保留今日计数）
  void resetAll() {
    _endInterruption();
    _stopTicker();
    _endAt = null;
    _phaseStartedAt = null;
    _state = PomodoroState(
      phase: PomodoroPhase.focus,
      status: PomodoroStatus.idle,
      duration: _config.focusDuration,
      remaining: _config.focusDuration,
      completedFocusToday: _state.completedFocusToday,
      focusInCycle: 0,
    );
    _emit();
  }

  /// 跳过当前阶段。实际专注严格超过一半则计数；手动跳过不自动开始下一阶段。
  void skip() {
    _refreshDay();
    // A button arriving after the deadline must not discard a finished phase.
    if (_state.isRunning && _endAt != null && !_endAt!.isAfter(_now())) {
      _advance(manualSkip: false);
      return;
    }
    _stopTicker();
    _advance(manualSkip: true);
  }

  /// 外部（持久层）回填今日完成数
  void setCompletedFocusToday(int count) {
    _day = studyDayKey(_now(), resetHour: _dailyResetHour);
    if (count == _state.completedFocusToday) return;
    _state = _copyWith(completedFocusToday: count);
    _emit();
  }

  Duration _durationOf(PomodoroPhase phase) {
    switch (phase) {
      case PomodoroPhase.focus:
        return _config.focusDuration;
      case PomodoroPhase.shortBreak:
        return _config.shortBreakDuration;
      case PomodoroPhase.longBreak:
        return _config.longBreakDuration;
    }
  }

  void _startTicker() {
    _stopTicker();
    _ticker = Timer.periodic(tickInterval, (_) => _onTick());
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _onTick() {
    _refreshDay();
    if (_expireContinuity(_now())) _emit();
    if (!_state.isRunning || _endAt == null) return;
    final remaining = _endAt!.difference(_now());
    if (remaining <= Duration.zero) {
      _advance(manualSkip: false);
    } else if (remaining != _state.remaining) {
      _state = _copyWith(remaining: remaining);
      _emit();
    }
  }

  /// 测试辅助：配合注入时钟手动触发一次心跳判断，实现确定性测试
  @visibleForTesting
  void debugTick() => _onTick();

  void _advance({required bool manualSkip}) {
    _stopTicker();
    final endedAt = manualSkip ? _now() : (_endAt ?? _now());
    _expireContinuity(endedAt);
    final startedAt = _phaseStartedAt ?? endedAt;
    final fromPhase = _state.phase;
    final wasFocus = fromPhase == PomodoroPhase.focus;
    final activeDuration = _phaseStartedAt == null
        ? Duration.zero
        : _state.duration - _remainingAt(endedAt);
    final completedPhase =
        !manualSkip ||
        (wasFocus &&
            activeDuration.inMicroseconds * 2 > _state.duration.inMicroseconds);
    var completed = _state.completedFocusToday;
    var inCycle = _state.focusInCycle;
    if (wasFocus && completedPhase) {
      if (studyDayKey(endedAt, resetHour: _dailyResetHour) == _day) {
        completed += 1;
      }
      inCycle += 1;
    } else if (wasFocus) {
      inCycle = 0;
    } else if (fromPhase == PomodoroPhase.longBreak) {
      // 一轮长休（包括跳过）结束后，开始新一轮连续专注。
      inCycle = 0;
    }
    if (wasFocus) _beginInterruption(endedAt, _state.duration);

    final PomodoroPhase next;
    if (wasFocus) {
      next =
          completedPhase &&
              inCycle > 0 &&
              inCycle >= _config.roundsBeforeLongBreak
          ? PomodoroPhase.longBreak
          : PomodoroPhase.shortBreak;
    } else {
      next = PomodoroPhase.focus;
    }

    final duration = _durationOf(next);
    final autoStart = manualSkip
        ? false
        : (next == PomodoroPhase.focus
              ? _config.autoStartFocus
              : _config.autoStartBreak);

    _state = PomodoroState(
      phase: next,
      status: autoStart ? PomodoroStatus.running : PomodoroStatus.idle,
      duration: duration,
      remaining: duration,
      completedFocusToday: completed,
      focusInCycle: inCycle,
    );

    if (autoStart) {
      if (next == PomodoroPhase.focus) _endInterruption();
      _endAt = _now().add(duration);
      _phaseStartedAt = _now();
      _startTicker();
    } else {
      _endAt = null;
      _phaseStartedAt = null;
    }

    _completionsController.add(
      PhaseCompletion(
        fromPhase: fromPhase,
        toPhase: next,
        toDuration: duration,
        manualSkip: manualSkip,
        completed: completedPhase,
        activeDuration: activeDuration,
        completedFocusToday: completed,
        startedAt: startedAt,
        endedAt: endedAt,
      ),
    );
    _emit();
  }

  PomodoroState _copyWith({
    PomodoroPhase? phase,
    PomodoroStatus? status,
    Duration? duration,
    Duration? remaining,
    int? completedFocusToday,
    int? focusInCycle,
  }) {
    return PomodoroState(
      phase: phase ?? _state.phase,
      status: status ?? _state.status,
      duration: duration ?? _state.duration,
      remaining: remaining ?? _state.remaining,
      completedFocusToday: completedFocusToday ?? _state.completedFocusToday,
      focusInCycle: focusInCycle ?? _state.focusInCycle,
    );
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(_state);
  }

  void dispose() {
    _endInterruption();
    _stopTicker();
    _controller.close();
    _completionsController.close();
  }
}
