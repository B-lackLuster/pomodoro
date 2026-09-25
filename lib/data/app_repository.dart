import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';
import 'models.dart';

/// 应用数据仓库：番茄记录 + 任务，JSON 存于 SharedPreferences。
/// 个人应用量级（每年数千条）下查询都在内存聚合，写入去抖由调用方控制。
/// 全量数据可导出为单个 JSON（也为 M5 多端同步铺路）。
class AppRepository {
  AppRepository(this._prefs);

  static const _logsKey = 'pomodoro.logs.v1';
  static const _tasksKey = 'pomodoro.tasks.v1';

  final SharedPreferences _prefs;

  List<PomodoroLog> _logs = const [];
  List<Task> _tasks = const [];
  bool _loaded = false;

  void _ensureLoaded() {
    if (_loaded) return;
    _logs = _decodeList(_prefs.getString(_logsKey), PomodoroLog.fromJson);
    _tasks = _decodeList(_prefs.getString(_tasksKey), Task.fromJson);
    _loaded = true;
  }

  List<T> _decodeList<T>(String? raw, T Function(Map<String, dynamic>) fromJson) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return _decodeDynamicList(list, fromJson);
    } catch (_) {
      return const [];
    }
  }

  List<T> _decodeDynamicList<T>(
      List? raw, T Function(Map<String, dynamic>) fromJson) {
    if (raw == null) return const [];
    return raw
        .whereType<Map>()
        .map((e) => fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  // ---------- 日志 ----------

  List<PomodoroLog> logs() {
    _ensureLoaded();
    return List.unmodifiable(_logs);
  }

  Future<void> addLog(PomodoroLog log) async {
    _ensureLoaded();
    if (_logs.any((e) => e.id == log.id)) return;
    _logs = [..._logs, log];
    await _prefs.setString(_logsKey, jsonEncode(_logs.map((e) => e.toJson()).toList()));
  }

  int focusCountForTask(String taskId) {
    _ensureLoaded();
    return _logs
        .where((l) => l.taskId == taskId && l.phase == PomodoroPhase.focus && l.completed)
        .length;
  }

  // ---------- 任务 ----------

  List<Task> tasks() {
    _ensureLoaded();
    return List.unmodifiable(_tasks);
  }

  Future<void> addTask(Task task) async {
    _ensureLoaded();
    _tasks = [..._tasks, task];
    await _prefs.setString(_tasksKey, jsonEncode(_tasks.map((e) => e.toJson()).toList()));
  }

  Future<void> updateTask(Task task) async {
    _ensureLoaded();
    _tasks = [
      for (final t in _tasks) if (t.id == task.id) task else t
    ];
    await _prefs.setString(_tasksKey, jsonEncode(_tasks.map((e) => e.toJson()).toList()));
  }

  Future<void> removeTask(String id) async {
    _ensureLoaded();
    _tasks = _tasks.where((t) => t.id != id).toList();
    await _prefs.setString(_tasksKey, jsonEncode(_tasks.map((e) => e.toJson()).toList()));
  }

  // ---------- 导出 / 导入 ----------

  /// 全量导出为 JSON 字符串
  String exportJson() {
    _ensureLoaded();
    return const JsonEncoder.withIndent('  ').convert({
      'app': 'pomodoro',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'logs': _logs.map((e) => e.toJson()).toList(),
      'tasks': _tasks.map((e) => e.toJson()).toList(),
    });
  }

  /// 从 JSON 合并导入（按 id 去重），返回新合并进来的记录数
  Future<(int logs, int tasks)> importJson(String raw) async {
    _ensureLoaded();
    final data = jsonDecode(raw) as Map<String, dynamic>;
    if (data['app'] != 'pomodoro') {
      throw const FormatException('不是番茄时钟的备份文件');
    }
    final incomingLogs =
        _decodeDynamicList(data['logs'] as List?, PomodoroLog.fromJson);
    final incomingTasks =
        _decodeDynamicList(data['tasks'] as List?, Task.fromJson);

    final logIds = _logs.map((e) => e.id).toSet();
    final newLogs = incomingLogs.where((l) => !logIds.contains(l.id)).toList();
    final taskIds = _tasks.map((e) => e.id).toSet();
    final newTasks = incomingTasks.where((t) => !taskIds.contains(t.id)).toList();

    if (newLogs.isNotEmpty) {
      _logs = [..._logs, ...newLogs];
      await _prefs.setString(_logsKey, jsonEncode(_logs.map((e) => e.toJson()).toList()));
    }
    if (newTasks.isNotEmpty) {
      _tasks = [..._tasks, ...newTasks];
      await _prefs.setString(_tasksKey, jsonEncode(_tasks.map((e) => e.toJson()).toList()));
    }
    return (newLogs.length, newTasks.length);
  }
}
