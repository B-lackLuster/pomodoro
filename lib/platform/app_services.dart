import 'dart:async';
import 'dart:math' show max;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../core/timer_engine.dart';
import '../data/models.dart';
import '../data/settings_store.dart';
import '../state/providers.dart';
import 'android_service.dart';
import 'desktop.dart';
import 'notify_service.dart';
import 'sound_service.dart';

/// 应用级平台服务门面：把引擎事件接到 系统通知 / 提示音 / 托盘 / 窗口。
/// 在 main() 中 runApp 之前调用 [init]。
class AppServices {
  AppServices._();

  static final AppServices instance = AppServices._();

  final SoundService _sound = SoundService();
  final NotifyService _notify = NotifyService();

  ProviderContainer? _container;
  StreamSubscription<PomodoroState>? _stateSub;
  StreamSubscription<PhaseCompletion>? _completionSub;
  ProviderSubscription<StoredSettings>? _settingsSub;

  int _lastTraySecond = -1;
  PomodoroStatus? _prevStatus;
  PomodoroPhase? _prevPhase;

  late final AndroidTimerService _androidService;
  bool _androidForeground = false;

  void _onTimerState(PomodoroState state) {
    final prevStatus = _prevStatus;
    final prevPhase = _prevPhase;
    _prevStatus = state.status;
    _prevPhase = state.phase;

    // 状态转换音效：开始（待开始→计时）、恢复（暂停→计时）、暂停（计时→暂停）
    if (state.isRunning && prevStatus != PomodoroStatus.running) {
      if (prevStatus == PomodoroStatus.paused) {
        _sound.playResume();
      } else {
        _sound.playStart();
      }
    } else if (state.status == PomodoroStatus.paused &&
        prevStatus == PomodoroStatus.running) {
      _sound.playPause();
    }

    // 桌面小组件：阶段或状态变化时推送（倒计时由系统原生每秒自刷新）
    if (state.phase != prevPhase || state.status != prevStatus) {
      unawaited(_container?.read(desktopPlatformProvider).updateWidgetState({
        'status': state.status.name,
        'phase': state.phase.name,
        'endAtMs': state.isRunning
            ? DateTime.now().add(state.remaining).millisecondsSinceEpoch.toDouble()
            : 0.0,
        'remainSec': state.remaining.inSeconds,
        'completed': state.completedFocusToday,
      }));
    }

    final second = state.remaining.inSeconds;
    if (second == _lastTraySecond) return;
    _lastTraySecond = second;
    _container
        ?.read(desktopPlatformProvider)
        .updateTrayCountdown(
          state.clockText,
          '番茄时钟 · ${phaseLabel(state.phase)} 剩余 ${state.clockText}',
        );
    _updateAndroidNotification(state, second);
  }

  /// Android 通知：运行中显示倒计时；空闲时收起服务
  void _updateAndroidNotification(PomodoroState state, int second) {
    if (!_androidService.isAvailable) return;
    if (state.isRunning) {
      final title = '${state.clockText} · ${phaseLabel(state.phase)}';
      final text = state.isBreak
          ? '休息一下，别想工作'
          : '第 ${state.focusInCycle % max(1, _settings.config.roundsBeforeLongBreak) + 1} 个番茄进行中';
      if (_androidForeground) {
        _androidService.update(title: title, text: text, running: true);
      } else {
        _androidForeground = true;
        _androidService.start(title: title, text: text, running: true);
      }
    } else if (_androidForeground) {
      // 暂停或空闲：保持常驻但文案更新；空闲时彻底收起
      if (state.status == PomodoroStatus.paused) {
        _androidService.update(
            title: '${state.clockText} · 已暂停', text: '点「继续」接着计时', running: false);
      } else {
        _androidForeground = false;
        _androidService.stop();
      }
    }
  }

  StoredSettings get _settings =>
      _container?.read(settingsProvider) ?? const StoredSettings();

  Future<void> init(ProviderContainer container) async {
    _container = container;
    _sound.enabled = _settings.soundEnabled;
    _notify.enabled = _settings.notificationsEnabled;

    // 每个平台服务独立兜底：任何一项失败都不影响应用其他功能
    try {
      await _notify.init();
    } catch (_) {}

    try {
      final desktop = container.read(desktopPlatformProvider);

      // 开机自启：注册应用信息，并把持久化状态与系统真实状态对齐
      desktop.setupAutoStart(appName: 'pomodoro');
      if (desktop.isAvailable) {
        final actual = await desktop.isAutoStartEnabled();
        if (actual != _settings.launchAtStartup) {
          await container
              .read(settingsProvider.notifier)
              .syncLaunchAtStartup(actual);
        }
      }
    } catch (_) {}

    try {
      final desktop = container.read(desktopPlatformProvider);
      await desktop.initWindow(
        closeToTrayEnabled: () => _settings.closeToTray,
      );
      await desktop.initTray(TrayActions(
        onShow: showMainWindow,
        onToggle: () => container.read(pomodoroProvider.notifier).toggle(),
        onSkip: () => container.read(pomodoroProvider.notifier).skip(),
        onQuit: quit,
      ));
    } catch (_) {}

    // 阶段完成 → 提示音 + 系统通知（手动跳过不提醒）
    _completionSub = container
        .read(engineProvider)
        .completions
        .listen(_onPhaseCompleted);

    // Android：前台服务常驻通知（计时状态/秒数变化时更新）
    _androidService = container.read(androidTimerServiceProvider);
    await _androidService.init();
    _androidService.onUserToggle =
        () => container.read(pomodoroProvider.notifier).toggle();
    _androidService.onUserSkip =
        () => container.read(pomodoroProvider.notifier).skip();

    // 计时状态 → 托盘倒计时文字 + Android 通知
    _stateSub = container
        .read(engineProvider)
        .stream
        .listen(_onTimerState);

    // 设置变化 → 同步服务开关
    _settingsSub = container.listen<StoredSettings>(
      settingsProvider,
      (prev, next) {
        _sound.enabled = next.soundEnabled;
        _notify.enabled = next.notificationsEnabled;
      },
      fireImmediately: false,
    );
  }

  int _logSeq = 0;

  void _onPhaseCompleted(PhaseCompletion completion) {
    _recordLog(completion);
    if (completion.manualSkip) {
      _sound.playSkip();
      return;
    }
    _sound.playPhaseEnd();
    if (completion.fromPhase == PomodoroPhase.focus) {
      final minutes = completion.toDuration.inMinutes;
      final phase = phaseLabel(completion.toPhase);
      _notify.showPhaseDone('🍅 番茄完成！', '干得漂亮，接下来是$phase（$minutes 分钟）');
    } else {
      final minutes = completion.toDuration.inMinutes;
      _notify.showPhaseDone('休息结束', '开始下一个专注（$minutes 分钟），加油！');
    }
  }

  /// 阶段结束（含手动跳过）写入番茄记录，完成数归属当前任务
  void _recordLog(PhaseCompletion completion) {
    final container = _container;
    if (container == null) return;
    final isFocus = completion.fromPhase == PomodoroPhase.focus;
    final log = PomodoroLog(
      id: '${completion.endedAt.microsecondsSinceEpoch}_${_logSeq++}',
      taskId: isFocus
          ? container.read(settingsProvider).currentTaskId
          : null,
      phase: completion.fromPhase,
      completed: !completion.manualSkip,
      start: completion.startedAt,
      end: completion.endedAt,
    );
    unawaited(container.read(appRepositoryProvider).addLog(log));
    container.read(dataVersionProvider.notifier).bump();
  }

  void showMainWindow() {
    _container?.read(desktopPlatformProvider).showWindow();
  }

  Future<void> quit() async {
    await _container?.read(desktopPlatformProvider).quitApp();
  }

  void dispose() {
    _stateSub?.cancel();
    _completionSub?.cancel();
    _settingsSub?.close();
    _sound.dispose();
  }
}
