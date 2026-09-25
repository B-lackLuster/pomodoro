import 'desktop_none.dart'
    if (dart.library.io) 'desktop_io.dart';

/// 桌面平台能力抽象：窗口管理 / 托盘 / 开机自启。
/// web 构建会绑定 [DesktopPlatformNone]（全部空实现），桌面端绑定真实实现，
/// 保证同一份代码可以在所有平台上编译。
abstract class DesktopPlatform {
  /// 当前运行环境是否具备桌面能力
  bool get isAvailable;

  /// 初始化主窗口：尺寸、标题、拦截关闭事件（用于最小化到托盘）
  Future<void> initWindow({required bool Function() closeToTrayEnabled});

  Future<void> showWindow();

  /// 强制退出（绕过"最小化到托盘"拦截）
  Future<void> quitApp();

  Future<void> setFullScreen(bool enabled);

  Future<void> initTray(TrayActions actions);

  /// 托盘实时倒计时（macOS 菜单栏文字；Windows 更新悬停提示）
  Future<void> updateTrayCountdown(String title, String tooltip);

  void setupAutoStart({required String appName});

  Future<bool> enableAutoStart();

  Future<bool> disableAutoStart();

  Future<bool> isAutoStartEnabled();
}

/// 托盘菜单回调
class TrayActions {
  const TrayActions({
    required this.onShow,
    required this.onToggle,
    required this.onSkip,
    required this.onQuit,
  });

  final void Function() onShow;
  final void Function() onToggle;
  final void Function() onSkip;
  final void Function() onQuit;
}

DesktopPlatform createDesktopPlatform() => DesktopPlatformImpl();
