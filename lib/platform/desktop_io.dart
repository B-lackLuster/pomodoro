import 'dart:async';
import 'dart:convert' show base64Encode;
import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'
    show MethodCall, MethodChannel, rootBundle;
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop.dart';

/// macOS / Windows / Linux 真实实现。
/// 本文件仅在支持 dart:io 的平台参与编译（见 desktop.dart 的条件导出）。
///
/// 托盘：macOS 走自实现的 StatusItemPlugin（tray_manager 0.5.3 在 macOS 26
/// 上 NSStatusItem 不渲染）；Windows/Linux 走 tray_manager。
class DesktopPlatformImpl with TrayListener implements DesktopPlatform {
  late final _WindowCloseHandler _windowCloseHandler = _WindowCloseHandler(this);

  final _MacStatusItem _macStatusItem = _MacStatusItem();

  bool Function()? _closeToTrayEnabled;
  TrayActions? _trayActions;
  bool _trayReady = false;

  @override
  bool get isAvailable =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  @override
  Future<void> initWindow({required bool Function() closeToTrayEnabled}) async {
    // Android 上没有窗口管理器（window_manager 未实现 Android 端），
    // 调用会抛 MissingPluginException，必须在 isAvailable 之外直接跳过
    if (!isAvailable) return;
    _closeToTrayEnabled = closeToTrayEnabled;
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      title: '番茄时钟',
      size: Size(440, 720),
      minimumSize: Size(380, 600),
      titleBarStyle: TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.setPreventClose(true);
    });
    windowManager.addListener(_windowCloseHandler);
  }

  @override
  Future<void> showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  Future<void> quitApp() async {
    if (Platform.isMacOS) {
      // 走原生通道：允许真正关闭（绕过托盘拦截）再关窗
      try {
        await _macStatusItem.quit();
      } catch (_) {}
    }
    await windowManager.destroy();
    exit(0);
  }

  @override
  Future<void> setFullScreen(bool enabled) async {
    try {
      await windowManager.setFullScreen(enabled);
    } catch (_) {
      // 部分窗口管理器不支持全屏切换，忽略
    }
  }

  @override
  Future<void> enterMiniMode() async {
    try {
      await windowManager.setMinimumSize(const Size(0, 0));
      // macOS 的 hidden 样式默认保留红绿灯按钮，需显式隐藏避免遮挡内容
      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );
      await windowManager.setSize(Size(280, 116));
      await windowManager.setAlwaysOnTop(true);
    } catch (_) {}
  }

  @override
  Future<void> exitMiniMode() async {
    try {
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setTitleBarStyle(TitleBarStyle.normal);
      await windowManager.setMinimumSize(Size(380, 600));
      await windowManager.setSize(Size(440, 720));
    } catch (_) {}
  }

  @override
  Future<void> startWindowDrag() async {
    try {
      await windowManager.startDragging();
    } catch (_) {}
  }

  @override
  Future<void> updateWidgetState(Map<String, Object?> state) async {
    if (!Platform.isMacOS) return;
    await _macStatusItem.setWidgetState(state);
  }

  @override
  Future<String?> takePendingWidgetCommand() async {
    if (!Platform.isMacOS) return null;
    try {
      return await _macStatusItem.takePendingCommand();
    } catch (_) {
      return null;
    }
  }

  @override
  void setWidgetCommandHandler(void Function(String command)? handler) {
    _macStatusItem.onWidgetCommand = handler;
  }

  @override
  Future<void> initTray(TrayActions actions) async {
    if (!isAvailable) return;
    _trayActions = actions;

    if (Platform.isMacOS) {
      _macStatusItem.onLeftClick = () => actions.onShow();
      _macStatusItem.onMenu = _handleMacMenu;
      _macStatusItem.onCloseRequested = _handleWindowClose;
      final ok = await _macStatusItem.show();
      if (!ok) {
        _trayReady = false;
        return;
      }
      await _macStatusItem.setToolTip('番茄时钟');
      await _macStatusItem.setMenu(const [
        {'label': '显示主窗口'},
        {'isSeparator': true},
        {'label': '开始 / 暂停'},
        {'label': '跳过当前阶段'},
        {'isSeparator': true},
        {'label': '退出'},
      ]);
      _trayReady = true;
      return;
    }

    // Windows / Linux：tray_manager
    trayManager.addListener(this);
    try {
      // Windows 用多尺寸 .ico（LoadImage 对 .ico 支持最稳，PNG 偶发加载失败）
      final iconPath = Platform.isWindows ? 'assets/tray/tomato.ico' : 'assets/tray/tomato_32.png';
      await trayManager.setIcon(iconPath);
      await trayManager.setToolTip('番茄时钟');
      await trayManager.setContextMenu(_buildMenu());
      _trayReady = true;
    } catch (e) {
      _trayReady = false;
      debugPrint('[tray] init failed: $e');
    }
  }

  void _handleMacMenu(int index) {
    switch (index) {
      case 0:
        _trayActions?.onShow();
      case 2:
        _trayActions?.onToggle();
      case 3:
        _trayActions?.onSkip();
      case 5:
        _trayActions?.onQuit();
    }
  }

  Menu _buildMenu() {
    return Menu(items: [
      MenuItem(label: '显示主窗口', onClick: (_) => _trayActions?.onShow()),
      MenuItem.separator(),
      MenuItem(label: '开始 / 暂停', onClick: (_) => _trayActions?.onToggle()),
      MenuItem(label: '跳过当前阶段', onClick: (_) => _trayActions?.onSkip()),
      MenuItem.separator(),
      MenuItem(label: '退出', onClick: (_) => _trayActions?.onQuit()),
    ]);
  }

  @override
  Future<void> updateTrayCountdown(String title, String tooltip) async {
    if (!_trayReady) return;
    try {
      if (Platform.isMacOS) {
        await _macStatusItem.setTitle(' $title');
        await _macStatusItem.setToolTip(tooltip);
      } else {
        await trayManager.setToolTip(tooltip);
      }
    } catch (_) {}
  }

  @override
  void onTrayIconMouseDown() {
    _trayActions?.onShow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  Future<void> _handleWindowClose() async {
    if (_closeToTrayEnabled?.call() ?? true) {
      await windowManager.hide();
    } else {
      await windowManager.destroy();
    }
  }

  @override
  void setupAutoStart({required String appName}) {
    if (!isAvailable) return;
    var appPath = Platform.resolvedExecutable;
    if (Platform.isMacOS) {
      // .../Pomodoro.app/Contents/MacOS/xxx → .../Pomodoro.app
      final idx = appPath.indexOf('.app/');
      if (idx != -1) appPath = appPath.substring(0, idx + 4);
    }
    LaunchAtStartup.instance.setup(appName: appName, appPath: appPath);
  }

  @override
  Future<bool> enableAutoStart() async {
    try {
      return await LaunchAtStartup.instance.enable();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> disableAutoStart() async {
    try {
      return await LaunchAtStartup.instance.disable();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isAutoStartEnabled() async {
    try {
      return await LaunchAtStartup.instance.isEnabled();
    } catch (_) {
      return false;
    }
  }
}

/// macOS 菜单栏状态项的 Dart 侧封装（对应 Runner 里的 StatusItemPlugin）
class _MacStatusItem {
  static const _channel = MethodChannel('pomodoro/status_item');

  void Function()? onLeftClick;
  void Function(int menuIndex)? onMenu;
  void Function()? onCloseRequested;

  /// 小组件按钮命令（toggle / skip）
  void Function(String command)? onWidgetCommand;

  Future<bool> show() async {
    try {
      final data = await rootBundle.load('assets/tray/tomato_32.png');
      final base64Icon = base64Encode(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      _channel.setMethodCallHandler(_onMethodCall);
      await _channel.invokeMethod('show', {'base64Icon': base64Icon});
      return true;
    } catch (e) {
      debugPrint('[tray] macOS status item failed: $e');
      return false;
    }
  }

  Future<void> quit() async {
    try {
      await _channel.invokeMethod('quit');
    } catch (_) {}
  }

  Future<void> setWidgetState(Map<String, Object?> state) async {
    try {
      await _channel.invokeMethod('setWidgetState', state);
    } catch (_) {}
  }

  Future<String?> takePendingCommand() async {
    try {
      return await _channel.invokeMethod('takePendingCommand');
    } catch (_) {
      return null;
    }
  }

  Future<void> setTitle(String title) async {
    try {
      await _channel.invokeMethod('setTitle', {'title': title});
    } catch (_) {}
  }

  Future<void> setToolTip(String tooltip) async {
    try {
      await _channel.invokeMethod('setToolTip', {'tooltip': tooltip});
    } catch (_) {}
  }

  Future<void> setMenu(List<Map<String, Object>> items) async {
    try {
      await _channel.invokeMethod('setMenu', {'items': items});
    } catch (_) {}
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onLeftClick':
        onLeftClick?.call();
      case 'onMenuClicked':
        final index = call.arguments as int?;
        if (index != null) onMenu?.call(index);
      case 'onWindowCloseRequested':
        onCloseRequested?.call();
      case 'onWidgetCommand':
        final cmd = call.arguments as String?;
        if (cmd != null) onWidgetCommand?.call(cmd);
    }
    return null;
  }
}

class _WindowCloseHandler extends WindowListener {
  _WindowCloseHandler(this._owner);

  final DesktopPlatformImpl _owner;

  @override
  void onWindowClose() {
    _owner._handleWindowClose();
  }
}
