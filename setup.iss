; 番茄时钟 Windows 安装包脚本（Inno Setup 6）
; 编译：ISCC.exe C:\dev\setup.iss

[Setup]
AppId={{538D831C-C326-4B6D-B14F-2A31F148B892}
AppName=番茄时钟
AppVersion=1.0.0
AppPublisher=Chengzhaohui
DefaultDirName={autopf}\Pomodoro
DefaultGroupName=番茄时钟
UninstallDisplayIcon={app}\pomodoro.exe
SetupIconFile=C:\dev\pomodoro\windows\runner\resources\app_icon.ico
OutputDir=C:\dev\installer
OutputBaseFilename=番茄时钟-Setup-1.0.0
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "chinese"; MessagesFile: "C:\dev\ChineseSimplified.isl"

[Files]
Source: "C:\dev\pomodoro\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{group}\番茄时钟"; Filename: "{app}\pomodoro.exe"
Name: "{group}\卸载番茄时钟"; Filename: "{uninstallexe}"
Name: "{autodesktop}\番茄时钟"; Filename: "{app}\pomodoro.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加图标："

[Run]
Filename: "{app}\pomodoro.exe"; Description: "立即运行番茄时钟"; Flags: nowait postinstall skipifsilent
