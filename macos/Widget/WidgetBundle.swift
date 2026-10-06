import WidgetKit
import SwiftUI
import AppIntents
import CoreFoundation

private let groupContainerURL = FileManager.default.containerURL(
    forSecurityApplicationGroupIdentifier: "group.com.tomatoclock.pomodoro")

enum DarwinNotificationCenter {
    static func post(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString), nil, nil, true)
    }
}

/// 小组件按钮 → 写命令 → Darwin 通知唤醒应用执行
private func writeCommand(_ cmd: String) {
    guard let dir = groupContainerURL else { return }
    let obj: [String: Any] = ["command": cmd, "at": Date().timeIntervalSince1970]
    if let data = try? JSONSerialization.data(withJSONObject: obj) {
        try? data.write(to: dir.appendingPathComponent("command.json"), options: .atomic)
    }
}
struct ToggleTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "开始/暂停"
    func perform() async throws -> some IntentResult {
        writeCommand("toggle")
        DarwinNotificationCenter.post("com.tomatoclock.pomodoro.command")
        return .result()
    }
}

struct SkipTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "跳过当前阶段"
    func perform() async throws -> some IntentResult {
        writeCommand("skip")
        DarwinNotificationCenter.post("com.tomatoclock.pomodoro.command")
        return .result()
    }
}

struct PomodoroState {
    var status: String   // idle / running / paused
    var phase: String    // focus / shortBreak / longBreak
    var endAtMs: Double
    var remainSec: Int
    var completed: Int

    static func load() -> PomodoroState {
        let fallback = PomodoroState(status: "idle", phase: "focus", endAtMs: 0,
                                     remainSec: 1500, completed: 0)
        guard let url = groupContainerURL?.appendingPathComponent("state.json"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return fallback
        }
        return PomodoroState(
            status: obj["status"] as? String ?? "idle",
            phase: obj["phase"] as? String ?? "focus",
            endAtMs: obj["endAtMs"] as? Double ?? 0,
            remainSec: obj["remainSec"] as? Int ?? 1500,
            completed: obj["completed"] as? Int ?? 0
        )
    }

    var phaseName: String {
        switch phase {
        case "shortBreak": return "短休息"
        case "longBreak": return "长休息"
        default: return "专注"
        }
    }

    var phaseColor: Color {
        switch phase {
        case "shortBreak": return Color(red: 0, green: 0.537, blue: 0.482)
        case "longBreak": return Color(red: 0.082, green: 0.396, blue: 0.753)
        default: return Color(red: 0.898, green: 0.224, blue: 0.208)
        }
    }

    var endDate: Date? {
        status == "running" && endAtMs > 0 ? Date(timeIntervalSince1970: endAtMs / 1000) : nil
    }

    var clock: String {
        let s = max(0, remainSec)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let state: PomodoroState
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), state: PomodoroState.load())
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(SimpleEntry(date: Date(), state: PomodoroState.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let state = PomodoroState.load()
        var entries = [SimpleEntry(date: Date(), state: state)]
        var refresh: Date
        if let end = state.endDate {
            // 倒计时结束时再刷新一次，显示"该休息了"
            entries.append(SimpleEntry(date: end, state: state))
            refresh = end.addingTimeInterval(30)
        } else {
            refresh = Date().addingTimeInterval(15 * 60)
        }
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

struct PomodoroWidgetView: View {
    let entry: SimpleEntry

    var body: some View {
        let s = entry.state
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text("🍅")
                Text(s.phaseName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(s.phaseColor)
                Spacer()
                if s.completed > 0 {
                    Text("🍅×\(s.completed)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                // 可交互按钮（macOS 14+）
                if #available(macOS 14.0, *) {
                    Button(intent: ToggleTimerIntent()) {
                        Image(systemName: s.status == "running" ? "pause.fill" : "play.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(s.phaseColor)
                    }
                    .buttonStyle(.borderless)
                    Button(intent: SkipTimerIntent()) {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            Spacer(minLength: 0)
            if s.status == "running", let end = s.endDate {
                Text(timerInterval: Date()...max(Date(), end), countsDown: true)
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.primary)
                Text("点击上方按钮可暂停/跳过")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else if s.status == "paused" {
                Text(s.clock)
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                Text("已暂停 · 点 ▶ 继续")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                Text(s.clock)
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.primary)
                Text("打开应用，开始专注")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackgroundCompat()
    }
}

extension View {
    @ViewBuilder
    func containerBackgroundCompat() -> some View {
        if #available(macOS 14.0, *) {
            containerBackground(for: .widget) { Color.clear }
        } else {
            self
        }
    }
}

struct PomodoroTimerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.tomatoclock.pomodoro.timer", provider: Provider()) { entry in
            PomodoroWidgetView(entry: entry)
        }
        .configurationDisplayName("番茄时钟")
        .description("显示当前番茄倒计时与今日完成数")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct PomodoroWidgetBundle: WidgetBundle {
    var body: some Widget {
        PomodoroTimerWidget()
    }
}
