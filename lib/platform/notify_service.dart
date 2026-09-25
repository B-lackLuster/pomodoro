import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 阶段结束系统通知（macOS / Windows；Android 在 M4 接入）
class NotifyService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _available = false;
  bool _enabled = true;

  /// Windows 通知激活回调标识（一次生成，固定使用）
  static const _windowsGuid = 'b665aaf1-d3c1-4e3b-a590-a8b18d162ded';
  static const _appUserModelId = 'com.tomatoclock.pomodoro';

  set enabled(bool value) => _enabled = value;

  Future<void> init() async {
    if (kIsWeb) return;
    final platform = defaultTargetPlatform;
    if (platform != TargetPlatform.macOS &&
        platform != TargetPlatform.windows &&
        platform != TargetPlatform.android) {
      return;
    }
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        macOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          // 声音统一由应用内 SoundService 播放，避免双重提示音
          requestSoundPermission: false,
          requestBadgePermission: false,
          defaultPresentSound: false,
        ),
        windows: WindowsInitializationSettings(
          appName: '番茄时钟',
          appUserModelId: _appUserModelId,
          guid: _windowsGuid,
        ),
      );
      final ok = await _plugin.initialize(settings: settings);
      _available = ok ?? false;
      // Android 13+ 需要运行时请求通知权限
      if (platform == TargetPlatform.android) {
        try {
          await _plugin
              .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin>()
              ?.requestNotificationsPermission();
        } catch (_) {}
      }
    } catch (_) {
      _available = false;
    }
  }

  Future<void> showPhaseDone(String title, String body) async {
    if (!_available || !_enabled) return;
    try {
      const details = NotificationDetails(
        macOS: DarwinNotificationDetails(presentSound: false),
        windows: WindowsNotificationDetails(),
      );
      await _plugin.show(
        id: 1,
        title: title,
        body: body,
        notificationDetails: details,
      );
    } catch (_) {}
  }
}
