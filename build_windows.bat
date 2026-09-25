@echo off
chcp 65001 >nul
title 番茄时钟 - Windows 构建脚本
echo ============================================
echo   番茄时钟 Windows 版一键构建
echo ============================================
echo.

where flutter >nul 2>nul
if errorlevel 1 (
    echo [错误] 未找到 flutter 命令。
    echo 请先安装 Flutter SDK 并把 bin 目录加入 PATH，参见 BUILD_WINDOWS.md。
    pause
    exit /b 1
)

echo [1/3] 拉取依赖...
call flutter pub get
if errorlevel 1 goto :fail

echo [2/3] 编译 release 版...
call flutter build windows --release
if errorlevel 1 goto :fail

echo [3/3] 完成！
set OUT=%~dp0build\windows\x64\runner\Release
echo 产物目录: %OUT%
echo 正在打开产物目录，双击 pomodoro.exe 即可运行。
explorer "%OUT%"
exit /b 0

:fail
echo.
echo [错误] 构建失败，请把上面的完整报错发给 AI 助手分析。
pause
exit /b 1
