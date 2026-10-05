import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // 托盘应用：窗口关闭/隐藏后进程继续常驻，退出由托盘菜单显式触发
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // 点程序坞图标时若主窗口被隐藏（最小化到托盘），重新显示
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      if let win = NSApp.windows.first(where: { $0 is MainFlutterWindow }) {
        win.makeKeyAndOrderFront(nil)
      }
      NSApp.activate(ignoringOtherApps: true)
    }
    return true
  }
}
