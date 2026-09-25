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
    this.taskId,
  });

  final String id;
  final String? taskId;
  final PomodoroPhase phase;

  /// 自然完成为 true；手动跳过为 false
  final bool completed;
  final DateTime start;
  final DateTime end;

  Duration get countedDuration => end.difference(start);

  Map<String, dynamic> toJson() => {
        'id': id,
        'taskId': taskId,
        'phase': phase.name,
        'completed': completed,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
      };

  factory PomodoroLog.fromJson(Map<String, dynamic> json) => PomodoroLog(
        id: json['id'] as String,
        taskId: json['taskId'] as String?,
        phase: PomodoroPhase.values
            .firstWhere((p) => p.name == json['phase'], orElse: () => PomodoroPhase.focus),
        completed: json['completed'] as bool? ?? true,
        start: DateTime.tryParse(json['start'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        end: DateTime.tryParse(json['end'] as String? ?? '') ??
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
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}
