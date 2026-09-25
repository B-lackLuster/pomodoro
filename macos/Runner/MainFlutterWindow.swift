import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// 关闭拦截器：返回 false 表示阻止本次关闭（用于最小化到托盘）。
  /// window_manager 的 preventClose 在 macOS 26 (Tahoe) 上不生效
  /// （窗口照样真关、触发"最后窗口关闭即退出"），所以在 performClose 层拦截。
  static var closeInterceptor: ((MainFlutterWindow) -> Bool)?

  /// 允许真正关闭（托盘"退出"菜单使用）
  var allowsRealClose = false

  override func performClose(_ sender: Any?) {
    if !allowsRealClose, let interceptor = Self.closeInterceptor,
       !interceptor(self) {
      return
    }
    super.performClose(sender)
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(
      NSRect(x: windowFrame.minX, y: windowFrame.minY, width: 440, height: 720),
      display: true)
    self.title = "番茄时钟"
    self.minSize = NSSize(width: 380, height: 600)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // 菜单栏托盘状态项（tray_manager 在 macOS 26 上不渲染，自实现）
    StatusItemPlugin.register(
      with: flutterViewController.registrar(forPlugin: "StatusItemPlugin"))

    super.awakeFromNib()
  }
}

/// 菜单栏状态项：番茄图标 + 倒计时文字 + 右键菜单。
/// 左键点击回主窗口；窗口关闭请求转发给 Dart 决定隐藏还是退出。
public class StatusItemPlugin: NSObject, FlutterPlugin {
  private var statusItem: NSStatusItem?
  private var channel: FlutterMethodChannel?
  private var menu: NSMenu?
  private var hasMenu = false

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = StatusItemPlugin()
    let channel = FlutterMethodChannel(
      name: "pomodoro/status_item", binaryMessenger: registrar.messenger)
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)

    MainFlutterWindow.closeInterceptor = { [weak instance] _ in
      instance?.notifyWindowCloseRequested()
      return false
    }
  }

  func notifyWindowCloseRequested() {
    channel?.invokeMethod("onWindowCloseRequested", arguments: nil)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "show":
      ensureStatusItem()
      if let base64 = args["base64Icon"] as? String,
         let data = Data(base64Encoded: base64),
         let image = NSImage(data: data) {
        image.size = NSSize(width: 18, height: 18)
        statusItem?.button?.image = image
      }
      result(true)
    case "setTitle":
      statusItem?.button?.title = args["title"] as? String ?? ""
      result(true)
    case "setToolTip":
      statusItem?.button?.toolTip = args["tooltip"] as? String ?? ""
      result(true)
    case "setMenu":
      buildMenu(from: args["items"] as? [[String: Any]] ?? [])
      // 设置为状态项菜单后，左键/右键点击均弹出菜单
      statusItem?.menu = menu
      hasMenu = true
      result(true)
    case "quit":
      // 允许真正关闭窗口再退出（绕过托盘拦截）
      if let window = NSApp.windows.first(where: { $0 is MainFlutterWindow })
          as? MainFlutterWindow {
        window.allowsRealClose = true
        window.performClose(nil)
      }
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func ensureStatusItem() {
    guard statusItem == nil else { return }
    // 点击行为由 statusItem.menu 接管（左右键均弹菜单），无需 action
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  }

  private func buildMenu(from items: [[String: Any]]) {
    let m = NSMenu()
    for (idx, entry) in items.enumerated() {
      if entry["isSeparator"] as? Bool == true {
        m.addItem(NSMenuItem.separator())
        continue
      }
      let mi = NSMenuItem(
        title: entry["label"] as? String ?? "",
        action: #selector(menuClicked(_:)),
        keyEquivalent: "")
      mi.tag = idx
      mi.target = self
      m.addItem(mi)
    }
    menu = m
  }

  @objc private func menuClicked(_ sender: NSMenuItem) {
    channel?.invokeMethod("onMenuClicked", arguments: sender.tag)
  }
}
