import 'dart:async';

import 'desktop.dart';

/// web / 不可用平台的空实现
class DesktopPlatformImpl implements DesktopPlatform {
  @override
  bool get isAvailable => false;

  @override
  Future<void> initWindow({required bool Function() closeToTrayEnabled}) async {}

  @override
  Future<void> showWindow() async {}

  @override
  Future<void> quitApp() async {}

  @override
  Future<void> setFullScreen(bool enabled) async {}

  @override
  Future<void> initTray(TrayActions actions) async {}

  @override
  Future<void> updateTrayCountdown(String title, String tooltip) async {}

  @override
  void setupAutoStart({required String appName}) {}

  @override
  Future<bool> enableAutoStart() async => false;

  @override
  Future<bool> disableAutoStart() async => false;

  @override
  Future<bool> isAutoStartEnabled() async => false;
}
