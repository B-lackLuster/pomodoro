import Cocoa
import FlutterMacOS
import WidgetKit

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

    // 小组件按钮 → Darwin 通知 → 转发给 Dart
    CFNotificationCenterAddObserver(
      CFNotificationCenterGetDarwinNotifyCenter(),
      Unmanaged.passUnretained(instance).toOpaque(),
      { _, observer, name, _, _ in
        guard let observer, let name else { return }
        let plugin = Unmanaged<StatusItemPlugin>.fromOpaque(observer).takeUnretainedValue()
        plugin.handleDarwinNotification(rawName: name.rawValue as String)
      },
      "com.tomatoclock.pomodoro.command" as CFString,
      nil,
      .deliverImmediately)
  }

  func handleDarwinNotification(rawName: String) {
    guard rawName == "com.tomatoclock.pomodoro.command" else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self, let cmd = StatusItemPlugin.takePendingCommand() else { return }
      self.channel?.invokeMethod("onWidgetCommand", arguments: cmd)
    }
  }

  static let groupID = "group.com.tomatoclock.pomodoro"

  static var groupContainerURL: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
  }

  /// 应用冷启动时取走积压命令（小组件在应用未运行时按下按钮的场景）。
  /// 命令走容器内 command.json 文件（跨进程即时可见，无 prefs 刷新延迟）
  static func takePendingCommand() -> String? {
    guard let url = groupContainerURL?.appendingPathComponent("command.json"),
          let data = try? Data(contentsOf: url),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let cmd = obj["command"] as? String else { return nil }
    try? FileManager.default.removeItem(at: url)
    return cmd
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
    case "takePendingCommand":
      result(StatusItemPlugin.takePendingCommand())
    case "setWidgetState":
      // 桌面小组件：状态写 App Group 容器 JSON 文件（跨进程即时可见）并刷新时间线
      if let d = call.arguments as? [String: Any],
         let dir = StatusItemPlugin.groupContainerURL {
        let state: [String: Any] = [
          "status": d["status"] as? String ?? "idle",
          "phase": d["phase"] as? String ?? "focus",
          "endAtMs": d["endAtMs"] as? Double ?? 0,
          "remainSec": d["remainSec"] as? Int ?? 1500,
          "completed": d["completed"] as? Int ?? 0,
          "updatedAt": Date().timeIntervalSince1970,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted]) {
          try? data.write(to: dir.appendingPathComponent("state.json"), options: .atomic)
        }
        WidgetCenter.shared.reloadAllTimelines()
        result(true)
      } else {
        result(false)
      }
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
