import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';
import '../core/study_day.dart';

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
    this.dailyResetHour = 4,
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

  /// 每日重置时间（0-23 时，0=0点）。跨天判断按此偏移，
  /// 例如设为 4 时，凌晨 4 点前的完成数仍算前一天
  final int dailyResetHour;

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
    int? dailyResetHour,
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
      currentTaskId: clearCurrentTask
          ? null
          : (currentTaskId ?? this.currentTaskId),
      dailyResetHour: dailyResetHour ?? this.dailyResetHour,
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
    'dailyResetHour': dailyResetHour,
  };

  factory StoredSettings.fromJson(Map<String, dynamic> json) => StoredSettings(
    config: json['config'] == null
        ? const PomodoroConfig()
        : PomodoroConfig.fromJson(
            Map<String, dynamic>.from(json['config'] as Map),
          ),
    themeMode: json['themeMode'] as String? ?? 'system',
    day: json['day'] as String? ?? '',
    completedToday: json['completedToday'] as int? ?? 0,
    notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
    soundEnabled: json['soundEnabled'] as bool? ?? true,
    closeToTray: json['closeToTray'] as bool? ?? true,
    launchAtStartup: json['launchAtStartup'] as bool? ?? false,
    currentTaskId: json['currentTaskId'] as String?,
    dailyResetHour: (json['dailyResetHour'] as int? ?? 4).clamp(0, 23),
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
        ? StoredSettings()
        : StoredSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    final today = todayKey(resetHour: settings.dailyResetHour);
    if (settings.day != today) {
      settings = settings.copyWith(day: today, completedToday: 0);
      save(settings);
    }
    return settings;
  }

  Future<void> save(StoredSettings settings) async {
    await _prefs.setString(_storageKey, jsonEncode(settings.toJson()));
  }

  /// 今日日期键（按每日重置时间偏移：如 resetHour=4，凌晨4点前仍属前一天）
  static String todayKey({int resetHour = 4, DateTime? now}) =>
      studyDayKey(now ?? DateTime.now(), resetHour: resetHour);
}
