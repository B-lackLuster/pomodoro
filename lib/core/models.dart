/// 番茄钟核心数据模型。纯 Dart，无 Flutter 依赖。
library;

/// 当前所处阶段
enum PomodoroPhase { focus, shortBreak, longBreak }

/// 计时器运行状态
enum PomodoroStatus { idle, running, paused }

/// 阶段的中文显示名
String phaseLabel(PomodoroPhase phase) => switch (phase) {
      PomodoroPhase.focus => '专注',
      PomodoroPhase.shortBreak => '短休息',
      PomodoroPhase.longBreak => '长休息',
    };

class PomodoroConfig {
  const PomodoroConfig({
    this.focusMinutes = 25,
    this.shortBreakMinutes = 5,
    this.longBreakMinutes = 15,
    this.roundsBeforeLongBreak = 4,
    this.autoStartBreak = true,
    this.autoStartFocus = false,
    this.dailyGoal = 8,
  });

  final int focusMinutes;
  final int shortBreakMinutes;
  final int longBreakMinutes;

  /// 每完成几个专注番茄，进入一次长休息
  final int roundsBeforeLongBreak;

  final bool autoStartBreak;
  final bool autoStartFocus;
  final int dailyGoal;

  Duration get focusDuration => Duration(minutes: focusMinutes);
  Duration get shortBreakDuration => Duration(minutes: shortBreakMinutes);
  Duration get longBreakDuration => Duration(minutes: longBreakMinutes);

  PomodoroConfig copyWith({
    int? focusMinutes,
    int? shortBreakMinutes,
    int? longBreakMinutes,
    int? roundsBeforeLongBreak,
    bool? autoStartBreak,
    bool? autoStartFocus,
    int? dailyGoal,
  }) {
    return PomodoroConfig(
      focusMinutes: focusMinutes ?? this.focusMinutes,
      shortBreakMinutes: shortBreakMinutes ?? this.shortBreakMinutes,
      longBreakMinutes: longBreakMinutes ?? this.longBreakMinutes,
      roundsBeforeLongBreak: roundsBeforeLongBreak ?? this.roundsBeforeLongBreak,
      autoStartBreak: autoStartBreak ?? this.autoStartBreak,
      autoStartFocus: autoStartFocus ?? this.autoStartFocus,
      dailyGoal: dailyGoal ?? this.dailyGoal,
    );
  }

  Map<String, dynamic> toJson() => {
        'focusMinutes': focusMinutes,
        'shortBreakMinutes': shortBreakMinutes,
        'longBreakMinutes': longBreakMinutes,
        'roundsBeforeLongBreak': roundsBeforeLongBreak,
        'autoStartBreak': autoStartBreak,
        'autoStartFocus': autoStartFocus,
        'dailyGoal': dailyGoal,
      };

  factory PomodoroConfig.fromJson(Map<String, dynamic> json) => PomodoroConfig(
        focusMinutes: json['focusMinutes'] as int? ?? 25,
        shortBreakMinutes: json['shortBreakMinutes'] as int? ?? 5,
        longBreakMinutes: json['longBreakMinutes'] as int? ?? 15,
        roundsBeforeLongBreak: json['roundsBeforeLongBreak'] as int? ?? 4,
        autoStartBreak: json['autoStartBreak'] as bool? ?? true,
        autoStartFocus: json['autoStartFocus'] as bool? ?? false,
        dailyGoal: json['dailyGoal'] as int? ?? 8,
      );
}

class PomodoroState {
  const PomodoroState({
    required this.phase,
    required this.status,
    required this.duration,
    required this.remaining,
    required this.completedFocusToday,
    required this.focusInCycle,
  });

  final PomodoroPhase phase;
  final PomodoroStatus status;

  /// 当前阶段总时长
  final Duration duration;

  /// 当前阶段剩余时长
  final Duration remaining;

  /// 今日完成的专注番茄数
  final int completedFocusToday;

  /// 自上次 resetAll 以来的专注完成数，用于按模轮转长休息
  final int focusInCycle;

  bool get isBreak => phase != PomodoroPhase.focus;
  bool get isRunning => status == PomodoroStatus.running;

  double get progress {
    final total = duration.inMilliseconds;
    if (total <= 0) return 0;
    return ((total - remaining.inMilliseconds) / total).clamp(0.0, 1.0);
  }

  String get clockText {
    final totalSeconds = remaining.inMilliseconds > 0
        ? (remaining.inMilliseconds / 1000).ceil()
        : 0;
    final m = (totalSeconds / 60).floor();
    final s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
