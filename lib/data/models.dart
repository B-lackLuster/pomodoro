/// M3 数据模型：番茄记录与任务（JSON 持久化）
library;

import '../core/models.dart';

/// 一条阶段记录（完成的番茄、被跳过的阶段都记录，统计时按 completed 过滤）
class PomodoroLog {
  const PomodoroLog({
    required this.id,
    required this.phase,
    required this.completed,
    required this.start,
    required this.end,
    this.activeSeconds,
    this.taskId,
  });

  final String id;
  final String? taskId;
  final PomodoroPhase phase;

  /// 达到计数条件（自然完成或实际专注严格过半后跳过）。
  final bool completed;
  final DateTime start;
  final DateTime end;

  /// 新记录保存扣除暂停后的实际计时时长；旧记录仍可读取。
  final double? activeSeconds;

  Duration get countedDuration => activeSeconds == null
      ? end.difference(start)
      : Duration(microseconds: (activeSeconds! * 1000000).round());

  Map<String, dynamic> toJson() => {
    'id': id,
    'taskId': taskId,
    'phase': phase.name,
    'completed': completed,
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
    if (activeSeconds != null) 'activeSeconds': activeSeconds,
  };

  factory PomodoroLog.fromJson(Map<String, dynamic> json) => PomodoroLog(
    id: json['id'] as String,
    taskId: json['taskId'] as String?,
    phase: PomodoroPhase.values.firstWhere(
      (p) => p.name == json['phase'],
      orElse: () => PomodoroPhase.focus,
    ),
    completed: json['completed'] as bool? ?? true,
    activeSeconds: (json['activeSeconds'] as num?)?.toDouble(),
    start:
        DateTime.tryParse(json['start'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    end:
        DateTime.tryParse(json['end'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );
}

/// 任务：完成的番茄数从日志聚合，不冗余存储
class Task {
  const Task({
    required this.id,
    required this.title,
    this.estimate = 1,
    this.done = false,
    required this.createdAt,
  });

  final String id;
  final String title;

  /// 预估番茄数
  final int estimate;
  final bool done;
  final DateTime createdAt;

  Task copyWith({String? title, int? estimate, bool? done}) => Task(
    id: id,
    title: title ?? this.title,
    estimate: estimate ?? this.estimate,
    done: done ?? this.done,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'estimate': estimate,
    'done': done,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Task.fromJson(Map<String, dynamic> json) => Task(
    id: json['id'] as String,
    title: json['title'] as String? ?? '未命名任务',
    estimate: json['estimate'] as int? ?? 1,
    done: json['done'] as bool? ?? false,
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );
}
