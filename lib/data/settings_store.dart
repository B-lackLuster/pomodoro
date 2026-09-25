import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';

/// 持久化的应用设置（计时配置 + 主题 + 今日计数快照）
class StoredSettings {
  const StoredSettings({
    this.config = const PomodoroConfig(),
    this.themeMode = 'system',
    this.day = '',
    this.completedToday = 0,
    this.notificationsEnabled = true,
    this.soundEnabled = true,
    this.closeToTray = true,
    this.launchAtStartup = false,
    this.currentTaskId,
  });

  final PomodoroConfig config;

  /// system | light | dark
  final String themeMode;

  /// completedToday 所属日期（yyyy-MM-dd），跨天自动清零
  final String day;
  final int completedToday;

  /// 阶段结束系统通知（桌面端生效）
  final bool notificationsEnabled;

  /// 阶段结束提示音（全平台生效）
  final bool soundEnabled;

  /// 点击关闭窗口时最小化到托盘而不是退出（仅桌面端）
  final bool closeToTray;

  /// 开机自启动（仅桌面端）
  final bool launchAtStartup;

  /// 当前选中的任务（完成番茄时记录归属），null = 未选择
  final String? currentTaskId;

  StoredSettings copyWith({
    PomodoroConfig? config,
    String? themeMode,
    String? day,
    int? completedToday,
    bool? notificationsEnabled,
    bool? soundEnabled,
    bool? closeToTray,
    bool? launchAtStartup,
    String? currentTaskId,
    bool clearCurrentTask = false,
  }) {
    return StoredSettings(
      config: config ?? this.config,
      themeMode: themeMode ?? this.themeMode,
      day: day ?? this.day,
      completedToday: completedToday ?? this.completedToday,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      closeToTray: closeToTray ?? this.closeToTray,
      launchAtStartup: launchAtStartup ?? this.launchAtStartup,
      currentTaskId:
          clearCurrentTask ? null : (currentTaskId ?? this.currentTaskId),
    );
  }

  Map<String, dynamic> toJson() => {
        'config': config.toJson(),
        'themeMode': themeMode,
        'day': day,
        'completedToday': completedToday,
        'notificationsEnabled': notificationsEnabled,
        'soundEnabled': soundEnabled,
        'closeToTray': closeToTray,
        'launchAtStartup': launchAtStartup,
        'currentTaskId': currentTaskId,
      };

  factory StoredSettings.fromJson(Map<String, dynamic> json) => StoredSettings(
        config: json['config'] == null
            ? const PomodoroConfig()
            : PomodoroConfig.fromJson(
                Map<String, dynamic>.from(json['config'] as Map)),
        themeMode: json['themeMode'] as String? ?? 'system',
        day: json['day'] as String? ?? '',
        completedToday: json['completedToday'] as int? ?? 0,
        notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
        soundEnabled: json['soundEnabled'] as bool? ?? true,
        closeToTray: json['closeToTray'] as bool? ?? true,
        launchAtStartup: json['launchAtStartup'] as bool? ?? false,
        currentTaskId: json['currentTaskId'] as String?,
      );
}

class SettingsStore {
  SettingsStore(this._prefs);

  static const _storageKey = 'pomodoro.settings.v1';
  final SharedPreferences _prefs;

  /// 同步读取（须在 SharedPreferences.getInstance() 之后调用），并处理跨天清零
  StoredSettings load() {
    final raw = _prefs.getString(_storageKey);
    var settings = raw == null
        ? StoredSettings(day: todayKey())
        : StoredSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    final today = todayKey();
    if (settings.day != today) {
      settings = StoredSettings(
        config: settings.config,
        themeMode: settings.themeMode,
        day: today,
        completedToday: 0,
      );
      save(settings);
    }
    return settings;
  }

  Future<void> save(StoredSettings settings) async {
    await _prefs.setString(_storageKey, jsonEncode(settings.toJson()));
  }

  static String todayKey() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}'
        '-${n.month.toString().padLeft(2, '0')}'
        '-${n.day.toString().padLeft(2, '0')}';
  }
}
