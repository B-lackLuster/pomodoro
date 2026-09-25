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
flutter run -d windows          # Windows 版（需在 Windows 机器上）
flutter run -d web-server --web-port 8765   # web 预览（任意浏览器打开 127.0.0.1:8765）
```

## 已知事项

- 本机暂无完整版 Xcode，macOS 原生构建待安装后进行（App Store 安装即可）
- web 预览初次加载时个别汉字短暂显示为方框，是 CanvasKit 在线字体未下载完成，桌面/移动端使用系统字体不受影响
