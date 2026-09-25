# Windows 版构建指南

本包是「番茄时钟」的完整源码，可在任何 Windows 10/11 (x64) 电脑上构建出 Windows 版应用。
如果你使用 AI 编程助手（Codex / Claude Code 等），直接把本文档发给它照做即可。

## 一、环境准备（一次性）

1. **安装 Flutter SDK (Windows)**

   - 下载 stable 版 zip：https://docs.flutter.dev/get-started/install/windows
     （国内镜像：把 `storage.googleapis.com` 换成 `storage.flutter-io.cn`，
     或设置环境变量 `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`、
     `PUB_HOSTED_URL=https://pub.flutter-io.cn`）
   - 解压到 `C:\dev\flutter`（**路径不要带中文和空格**）
   - 把 `C:\dev\flutter\bin` 加入 PATH

2. **安装 Visual Studio 构建工具（必须）**

   - 下载 Visual Studio 2022 Community 或仅 Build Tools：
     https://visualstudio.microsoft.com/zh-hans/downloads/
   - 安装时勾选工作负载：**"使用 C++ 的桌面开发"**
     （含 MSVC、Windows SDK、CMake）
   - 这一步约 7GB，是编译 Windows 桌面程序的硬性要求

3. **验证环境**

   ```bat
   flutter doctor
   ```

   确认 `[√] Flutter` 和 `[√] Visual Studio -- develop Windows apps` 两项通过。

## 二、构建

解压本包后，在项目根目录（有 `pubspec.yaml` 的目录）执行：

```bat
build_windows.bat
```

或手动执行：

```bat
flutter pub get
flutter build windows --release
```

构建成功后，产物在：

```
build\windows\x64\runner\Release\
```

**整个 Release 文件夹**就是绿色版应用（exe + dll + data 必须放在一起），
可整体拷贝到任意目录运行，双击 `pomodoro.exe` 启动。

## 三、可选：做成安装包

绿色版已可用。若想要传统"下一步下一步"式安装包，可用 Inno Setup：

1. 安装 Inno Setup：https://jrsoftware.org/isinfo.php
2. 用下面内容保存为 `setup.iss`（按实际路径调整）：

```iss
[Setup]
AppName=番茄时钟
AppVersion=1.0.0
DefaultDirName={autopf}\Pomodoro
OutputDir=.
OutputBaseFilename=番茄时钟-Setup-1.0.0

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs

[Icons]
Name: "{commondesktop}\番茄时钟"; Filename: "{app}\pomodoro.exe"
```

3. Inno Setup 里编译该脚本，得到 `番茄时钟-Setup-1.0.0.exe`。

## 四、Windows 版功能说明

以下功能在 Windows 上已实现（代码就绪，若构建版本较新建议实际点一遍）：

- 托盘常驻（番茄图标），悬停显示"阶段 + 剩余时间"提示
- 点击托盘图标弹出菜单：显示主窗口 / 开始·暂停 / 跳过 / 退出
- 关闭窗口最小化到托盘（设置里可关）
- 开机自启动（设置里开关，写注册表 Run 项）
- 阶段结束系统通知（Toast）+ 提示音
- 任务清单、数据统计、全屏专注模式与 macOS 版一致

注意：Windows 托盘图标本身不显示倒计时文字（macOS 菜单栏才有），
悬停图标可看到剩余时间；主窗口与任务栏图标正常显示。

## 五、常见问题

- **构建报 "Unable to locate suitable Visual Studio toolchain"**：
  VS Build Tools 没装 C++ 工作负载，重开 Visual Studio Installer 勾选。
- **`flutter pub get` 慢/失败**：设置国内镜像环境变量（见上）。
- **exe 双击没反应**：确认是把整个 Release 文件夹一起拷走的，exe 单独拿出来跑不了。
- **杀毒软件报警**：未签名的自编译程序可能被误报，加入信任即可（或自行代码签名）。
