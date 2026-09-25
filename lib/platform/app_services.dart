import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../core/timer_engine.dart';
import '../data/models.dart';
import '../data/settings_store.dart';
import '../state/providers.dart';
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

  StoredSettings get _settings =>
      _container?.read(settingsProvider) ?? const StoredSettings();

  Future<void> init(ProviderContainer container) async {
    _container = container;
    _sound.enabled = _settings.soundEnabled;
    _notify.enabled = _settings.notificationsEnabled;

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

    await desktop.initWindow(
      closeToTrayEnabled: () => _settings.closeToTray,
    );
    await _notify.init();
    await desktop.initTray(TrayActions(
      onShow: showMainWindow,
      onToggle: () => container.read(pomodoroProvider.notifier).toggle(),
      onSkip: () => container.read(pomodoroProvider.notifier).skip(),
      onQuit: quit,
    ));

    // 阶段完成 → 提示音 + 系统通知（手动跳过不提醒）
    _completionSub = container
        .read(engineProvider)
        .completions
        .listen(_onPhaseCompleted);

    // 计时状态 → 托盘倒计时文字
    _stateSub = container
        .read(engineProvider)
        .stream
        .listen(_updateTrayCountdown);

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
    if (completion.manualSkip) return;
    _sound.playBell();
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

  void _updateTrayCountdown(PomodoroState state) {
    final second = state.remaining.inSeconds;
    if (second == _lastTraySecond) return;
    _lastTraySecond = second;
    _container
        ?.read(desktopPlatformProvider)
        .updateTrayCountdown(
          state.clockText,
          '番茄时钟 · ${phaseLabel(state.phase)} 剩余 ${state.clockText}',
        );
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
