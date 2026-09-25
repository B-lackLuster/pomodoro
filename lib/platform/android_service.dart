import 'android_service_stub.dart'
    if (dart.library.io) 'android_service_io.dart';

/// Android 前台服务封装：常驻通知显示倒计时 + 暂停/跳过按钮。
/// 非 Android 平台全部为空操作（web/desktop 绑定 stub 实现）。
abstract class AndroidTimerService {
  bool get isAvailable;

  /// 通知栏「暂停/继续」按钮回调
  void Function()? onUserToggle;

  /// 通知栏「跳过」按钮回调
  void Function()? onUserSkip;

  Future<void> init();

  Future<void> start({
    required String title,
    required String text,
    required bool running,
  });

  Future<void> update({
    required String title,
    required String text,
    required bool running,
  });

  Future<void> stop();

  void dispose();
}

AndroidTimerService createAndroidTimerService() => AndroidTimerServiceImpl();
