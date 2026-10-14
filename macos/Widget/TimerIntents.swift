import Foundation
import AppIntents
import CoreFoundation

// Compile into both Runner and the widget: foreground intents execute in Runner.
private let commandContainerURL = FileManager.default.containerURL(
    forSecurityApplicationGroupIdentifier: "5V582QBP6Q.com.tomatoclock.pomodoro.shared")

enum DarwinNotificationCenter {
    static func post(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString), nil, nil, true)
    }
}

/// 小组件按钮 → 写命令 → Darwin 通知唤醒应用执行
private func writeCommand(_ cmd: String) throws {
    guard let dir = commandContainerURL else { throw CocoaError(.fileWriteNoPermission) }
    let obj: [String: Any] = ["command": cmd, "at": Date().timeIntervalSince1970]
    let data = try JSONSerialization.data(withJSONObject: obj)
    try data.write(to: dir.appendingPathComponent("command.json"), options: .atomic)
    NSLog("[widget-command] Queued %@", cmd)
}
@available(macOS 14.0, *)
struct ToggleTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "开始/暂停"
    static var openAppWhenRun: Bool = true
    func perform() async throws -> some IntentResult {
        try writeCommand("toggle")
        DarwinNotificationCenter.post("com.tomatoclock.pomodoro.command")
        return .result()
    }
}

@available(macOS 14.0, *)
struct SkipTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "跳过当前阶段"
    static var openAppWhenRun: Bool = true
    func perform() async throws -> some IntentResult {
        try writeCommand("skip")
        DarwinNotificationCenter.post("com.tomatoclock.pomodoro.command")
        return .result()
    }
}

