import 'package:flutter/services.dart';

import 'android_service.dart';

/// Android 真实实现（仅 android 平台参与编译）
class AndroidTimerServiceImpl implements AndroidTimerService {
  static const _channel = MethodChannel('pomodoro/android_service');

  @override
  void Function()? onUserToggle;
  @override
  void Function()? onUserSkip;

  bool _available = false;

  @override
  bool get isAvailable => _available;

  @override
  Future<void> init() async {
    _channel.setMethodCallHandler(_onMethodCall);
    _available = true;
  }

  @override
  Future<void> start({
    required String title,
    required String text,
    required bool running,
  }) async {
    if (!_available) return;
    try {
      await _channel.invokeMethod('startService', {
        'title': title,
        'text': text,
        'running': running,
      });
    } on PlatformException catch (_) {
      // 用户未授予通知权限等情况：不阻塞主流程
    }
  }

  @override
  Future<void> update({
    required String title,
    required String text,
    required bool running,
  }) async {
    if (!_available) return;
    try {
      await _channel.invokeMethod('updateNotification', {
        'title': title,
        'text': text,
        'running': running,
      });
    } on PlatformException catch (_) {}
  }

  @override
  Future<void> stop() async {
    if (!_available) return;
    try {
      await _channel.invokeMethod('stopService');
    } on PlatformException catch (_) {}
  }

  @override
  void dispose() {
    if (_available) _channel.setMethodCallHandler(null);
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onUserToggle':
        onUserToggle?.call();
      case 'onUserSkip':
        onUserSkip?.call();
    }
    return null;
  }
}
