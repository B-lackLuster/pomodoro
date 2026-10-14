import WidgetKit
import SwiftUI
import AppIntents
import CoreFoundation

private let groupContainerURL = FileManager.default.containerURL(
    forSecurityApplicationGroupIdentifier: "5V582QBP6Q.com.tomatoclock.pomodoro.shared")

struct PomodoroState {
    var status: String   // idle / running / paused
    var phase: String    // focus / shortBreak / longBreak
    var endAtMs: Double
    var remainSec: Int
    var completed: Int
    var completedMonth: Int = 0
    var day: String = ""
    var dailyResetHour: Int = 4
    var connected: Bool = true

    func onDate(_ date: Date) -> PomodoroState {
        var state = self
        let calendar = Calendar.current
        let boundary = calendar.date(bySettingHour: dailyResetHour, minute: 0,
                                     second: 0, of: date) ?? date
        let studyDate = date < boundary
            ? calendar.date(byAdding: .day, value: -1, to: date) ?? date : date
        let parts = calendar.dateComponents([.year, .month, .day], from: studyDate)
        let key = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        if key != day { state.completed = 0 }
        if key.prefix(7) != day.prefix(7) { state.completedMonth = 0 }
        return state
    }

    static func load() -> PomodoroState {
        let fallback = PomodoroState(status: "idle", phase: "focus", endAtMs: 0,
                                     remainSec: 1500, completed: 0, connected: false)
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
            completed: obj["completed"] as? Int ?? 0,
            completedMonth: obj["completedMonth"] as? Int ?? 0,
            day: obj["day"] as? String ?? "",
            dailyResetHour: min(23, max(0, obj["dailyResetHour"] as? Int ?? 4))
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
        let now = Date()
        var entries = [SimpleEntry(date: now, state: state.onDate(now))]
        var refresh = now.addingTimeInterval(15 * 60)
        if let end = state.endDate, end > now {
            entries.append(SimpleEntry(date: end, state: state))
            refresh = min(refresh, end.addingTimeInterval(1))
        }
        if let reset = Calendar.current.nextDate(
            after: now, matching: DateComponents(hour: state.dailyResetHour, minute: 0, second: 0),
            matchingPolicy: .nextTime) {
            entries.append(SimpleEntry(date: reset, state: state.onDate(reset)))
            refresh = min(refresh, reset)
        }
        entries.sort { $0.date < $1.date }
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

struct PomodoroWidgetView: View {
    let entry: SimpleEntry

    var body: some View {
        let s = entry.state.onDate(entry.date)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text("🍅")
                Text(s.phaseName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(s.phaseColor)
                Spacer()
                // 可交互按钮（macOS 14+）
                if #available(macOS 14.0, *) {
                    Button(intent: ToggleTimerIntent()) {
                        Text(s.status == "running" ? "⏸" : "▶︎")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(s.phaseColor)
                    }
                    .buttonStyle(.plain)
                    Button(intent: SkipTimerIntent()) {
                        Text("⏭")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(s.phase == "focus" ? "跳过专注，不计番茄" : "跳过休息")
                }
            }
            HStack(spacing: 8) {
                Text("今日 🍅×\(s.completed)")
                Text("本月 🍅×\(s.completedMonth)")
            }
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .foregroundColor(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.top, 3)
            Spacer(minLength: 0)
            if !s.connected {
                Text("等待同步")
                    .font(.system(size: 26, weight: .semibold))
                Text("打开番茄时钟以连接小组件")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else if s.status == "running", let end = s.endDate {
                if entry.date >= end {
                    Text(s.phase == "focus" ? "专注已完成" : "休息已结束")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundColor(s.phaseColor)
                    Text("打开应用开始下一阶段")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    Text(timerInterval: entry.date...end, countsDown: true)
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.primary)
                    Text("点击上方按钮可暂停/跳过")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
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
        .description("显示番茄倒计时、今日和本月完成数")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct PomodoroWidgetBundle: WidgetBundle {
    var body: some Widget {
        PomodoroTimerWidget()
    }
}
