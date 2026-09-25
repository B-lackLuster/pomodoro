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
}
