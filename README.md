# 番茄时钟（Pomodoro）

跨平台番茄钟：Windows / macOS / Android（附带 web 预览版）。Flutter 一套代码三端。

## 当前进度（M3 已完成）

- ✅ 纯 Dart 计时引擎（时间戳驱动，后台/休眠/挂起后依然精准），23 个单元测试
- ✅ 标准番茄循环：专注 → 短休息，每 N 轮长休息；时长/轮数/每日目标可配置
- ✅ 开始 / 暂停 / 继续 / 跳过 / 重置当前阶段 / 完全重置
- ✅ 自动开始下一阶段（休息/专注独立开关）
- ✅ 今日完成数 + 每日目标，跨天自动清零
- ✅ 设置持久化（SharedPreferences），浅色/深色/跟随系统主题
- ✅ M2：阶段结束系统通知（macOS/Windows）+ 提示音（自合成 bell.wav，全平台）
- ✅ M2：托盘/菜单栏常驻，倒计时实时显示（macOS 菜单栏文字），点击弹菜单
- ✅ M2：关闭窗口最小化到托盘（可关）、开机自启动（macOS SMAppService / Windows 注册表）
- ✅ M2：全屏专注模式（桌面端真全屏）
- ✅ M3：任务清单（添加/完成/删除，点选"当前任务"，完成番茄自动归属）
- ✅ M3：番茄记录（每个阶段起止时间入库，跳过也记录但标记未完成）
- ✅ M3：数据统计（今日/本周/本月/累计、连续打卡、近 7 天柱状图，自绘零依赖）
- ✅ M3：数据导出/导入（JSON 备份，按 id 合并，桌面端）
- ⬜ M4：Android 前台服务、通知操作、桌面小部件
- ⬜ M5：多端同步（WebDAV）、打包分发（dmg / exe 安装包 / APK）

## 架构说明

- `lib/core/`：纯 Dart 计时引擎，时间戳驱动，无 Flutter 依赖
- `lib/platform/desktop.dart`：桌面能力抽象，条件导入（`dart.library.io`）隔离，
  web 构建自动绑定空实现（`desktop_none.dart`），桌面端为真实实现（`desktop_io.dart`）
- `lib/platform/app_services.dart`：服务门面，订阅引擎「阶段完成事件流」
  （`PomodoroEngine.completions`）驱动通知/提示音，手动跳过不提醒

## macOS 26 (Tahoe) 兼容性备忘

本机实测（macOS 26.6 + Xcode 26.6）踩到的三个系统级坑及解法：

1. **菜单栏状态项不显示**：Tahoe 新增「菜单栏」权限，第三方应用的状态项默认被
   静默拦截（窗口高度为 0）。需在 系统设置 → 菜单栏 中允许本应用。
   另外 tray_manager 0.5.3 的 NSView 注入方式在 Tahoe 上同样不渲染，
   `macos/Runner/MainFlutterWindow.swift` 里自实现了 `StatusItemPlugin` 替代。
2. **preventClose 失效**：window_manager 的 setPreventClose 在 Tahoe 上不生效
   （windowShouldClose 被绕过，窗口照样真关）。通过重写 MainFlutterWindow 的
   `performClose` 在更上层拦截，关闭请求转发给 Dart 决定隐藏还是退出。
3. **最后窗口关闭即退出**：Flutter 模板 AppDelegate 默认
   `applicationShouldTerminateAfterLastWindowClosed = true`，托盘应用必须改为
   `false`，退出统一走托盘菜单的 `exit(0)`。

4. **桌面小组件停在 25:00**：macOS 15+ 会保护 App Group 目录。
   本项目使用团队前缀容器 `5V582QBP6Q.com.tomatoclock.pomodoro.shared`，
   主程序、小组件与三个 entitlements 必须保持一致。原先 `group.com...`
   容器被系统拒绝读写时，小组件会一直显示默认值。更换签名团队时也要同步修改容器前缀。
   Release 禁用自动注入基础 entitlements，使用团队前缀容器，不依赖短期开发配置文件。
   小组件倒计时由 SwiftUI 原生计时文本刷新，状态变化才写文件并请求时间线刷新。
   更新应用后若系统仍运行旧的小组件扩展，可移除并重新添加小组件。

每日完成数默认在本地时间 04:00 更新，可在设置中调整。更新今日显示不会删除历史记录，
跨日的番茄按完成时间归属日期。应用在边界时刻主动更新，并在休眠唤醒后补检。

## 目录结构

```
lib/
  core/        # 纯 Dart 计时引擎（无 Flutter 依赖，可单测）
    models.dart          # 枚举 / PomodoroConfig / PomodoroState
    timer_engine.dart    # 时间戳驱动状态机
  data/
    settings_store.dart  # 设置持久化（JSON in SharedPreferences）
  features/
    timer/               # 计时页 + 进度环
    settings/            # 设置页
  state/
    providers.dart       # Riverpod 状态管理
```

## 运行

```bash
# 环境变量（国内镜像，已在 ~/.zshrc 配置）
export PATH="$HOME/development/flutter/bin:$PATH"
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export PUB_HOSTED_URL=https://pub.flutter-io.cn

flutter test                    # 引擎单元测试
flutter run -d macos            # macOS 桌面版（需完整版 Xcode）
flutter build macos --release   # 产物：build/macos/Build/Products/Release/pomodoro.app
flutter run -d windows          # Windows 版（需在 Windows 机器上）
flutter run -d web-server --web-port 8765   # web 预览（任意浏览器打开 127.0.0.1:8765）
```

## 已知事项

- macOS 正式版与小组件已在本机使用 Xcode 构建验证；签名证书需与项目的开发团队一致。
- web 预览初次加载时个别汉字短暂显示为方框，是 CanvasKit 在线字体未下载完成，桌面/移动端使用系统字体不受影响

## 版本信息

当前版本为 **1.2.0（构建 5）**，可在「设置 → 关于」查看安装包的实际版本。
版本统一由 `pubspec.yaml` 的 `version` 定义；macOS 主程序和小组件使用同一版本。
本次更新包含小组件实时同步、按钮下方今日/本月番茄数，以及凌晨 4 点跨日刷新修复。

1.1.1 修复小组件播放/暂停和跳过按钮无响应：`TimerIntents.swift` 必须同时编译进
Runner 与 Widget 两个 target，才能在主程序中执行需要打开应用的按钮动作。
更新应用时应完整替换 `.app`，不要把新文件叠加复制到旧包内；随后重新注册小组件扩展。

1.1.2 修复跳过长休后，跳过下一次未完成的专注却再次进入长休的问题。
长休只在完整完成指定数量的番茄时触发；未完成的专注跳过后进入短休且不计番茄。
阶段已到期但心跳尚未刷新时点击跳过，会正常结算已完成的番茄，避免漏计。

1.2.0 更新计数和连续规则：

- 实际专注时间严格超过当前阶段的一半后跳过，计 1 个番茄；恰好一半、未过半不计。
- 暂停时间不计入实际专注时长；新记录保存实际时长，旧记录保留原来的计数结果。
- 默认连续完成 4 个有效番茄才触发长休（间隔数仍可在设置调整），过半跳过也算有效番茄。
- 单次非专注停顿（暂停、休息与待开始等待）超过当时一个专注阶段的时长，连续进度重新累计。
  正常 5 分钟短休不打断连续进度；未达标就跳过或重置专注也会中断连续进度。
- 长休结束或跳过后开始新一轮。连续进度变化不会扣除今日或历史番茄数。
- 主界面显示本轮连续进度；今日、本月、任务统计与小组件沿用同一计数结果。
