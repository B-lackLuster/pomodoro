import 'dart:async';
import 'dart:math' show max;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../core/timer_engine.dart';
import '../core/study_day.dart';
import '../data/models.dart';
import '../data/settings_store.dart';
import '../data/stats_service.dart';
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
  ProviderSubscription<StatsSummary>? _statsSub;
  int _widgetMonthCount = 0;

  int _lastTraySecond = -1;
  PomodoroStatus? _prevStatus;
  String? _lastWidgetSignature;
  String? _lastTrayTitle;

  late final AndroidTimerService _androidService;
  bool _androidForeground = false;
  bool _androidReady = false;

  void _onTimerState(PomodoroState state) {
    final prevStatus = _prevStatus;
    _prevStatus = state.status;

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
    _pushWidgetState(state);

    final second = (state.remaining.inMilliseconds / 1000).ceil();
    final secondChanged = second != _lastTraySecond;
    _lastTraySecond = second;
    final count = state.completedFocusToday;
    // 托盘图标本身是番茄，标题不再带 🍅 emoji，避免双番茄
    final title = count > 0 ? '×$count ${state.clockText}' : state.clockText;
    final traySignature = '$title:${state.phase.name}:${state.status.name}';
    if (_lastTrayTitle == traySignature && !secondChanged) return;
    _lastTrayTitle = traySignature;
    _container
        ?.read(desktopPlatformProvider)
        .updateTrayCountdown(
          title,
          '番茄时钟 · ${phaseLabel(state.phase)} 剩余 ${state.clockText}'
          '${count > 0 ? ' · 今日 ×$count' : ''}',
        );
    _updateAndroidNotification(state, second);
  }

  /// Android 通知：运行中显示倒计时；空闲时收起服务
  void _updateAndroidNotification(PomodoroState state, int second) {
    if (!_androidReady || !_androidService.isAvailable) return;
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
          title: '${state.clockText} · 已暂停',
          text: '点「继续」接着计时',
          running: false,
        );
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
    _widgetMonthCount = container.read(statsProvider).monthCount;
    _statsSub = container.listen<StatsSummary>(statsProvider, (_, next) {
      _widgetMonthCount = next.monthCount;
      _pushWidgetState(container.read(engineProvider).state);
    });

    // Core synchronization must be ready before optional plugins can block.
    container.read(pomodoroProvider);
    _androidService = container.read(androidTimerServiceProvider);
    _completionSub = container
        .read(engineProvider)
        .completions
        .listen(_onPhaseCompleted);
    _stateSub = container.read(engineProvider).stream.listen(_onTimerState);
    _checkDayRollover();
    _pushWidgetState(container.read(engineProvider).state);
    _scheduleDayRollover();
    _rolloverWatchdog = Timer.periodic(const Duration(seconds: 15), (_) {
      _checkDayRollover();
    });

    debugPrint('[init] stage: notify');
    // 每个平台服务独立兜底：任何一项失败都不影响应用其他功能
    try {
      await _notify.init().timeout(const Duration(seconds: 3));
    } catch (_) {}
    debugPrint('[init] stage: autostart');

    try {
      final desktop = container.read(desktopPlatformProvider);

      // 开机自启：注册应用信息，并把持久化状态与系统真实状态对齐
      desktop.setupAutoStart(appName: 'pomodoro');
      if (desktop.isAvailable) {
        final actual = await desktop.isAutoStartEnabled().timeout(
          const Duration(seconds: 3),
        );
        if (actual != _settings.launchAtStartup) {
          await container
              .read(settingsProvider.notifier)
              .syncLaunchAtStartup(actual);
        }
      }
    } catch (_) {}

    debugPrint('[init] stage: window');
    try {
      final desktop = container.read(desktopPlatformProvider);
      await desktop
          .initWindow(closeToTrayEnabled: () => _settings.closeToTray)
          .timeout(const Duration(seconds: 5));
      debugPrint('[init] stage: window ok');
      await desktop.initTray(
        TrayActions(
          onShow: showMainWindow,
          onToggle: () => container.read(pomodoroProvider.notifier).toggle(),
          onSkip: () => container.read(pomodoroProvider.notifier).skip(),
          onQuit: quit,
        ),
      );
    } catch (_) {}

    debugPrint('[init] stage: streams');
    // 阶段完成 → 提示音 + 系统通知（手动跳过不提醒）

    // Android：前台服务常驻通知（计时状态/秒数变化时更新）
    try {
      await _androidService.init().timeout(const Duration(seconds: 3));
      _androidReady = true;
    } catch (error) {
      debugPrint('[android] Timer service initialization failed: $error');
    }
    _androidService.onUserToggle = () =>
        container.read(pomodoroProvider.notifier).toggle();
    _androidService.onUserSkip = () =>
        container.read(pomodoroProvider.notifier).skip();

    // macOS：小组件按钮命令（Darwin 通知链路）
    container.read(desktopPlatformProvider).setWidgetCommandHandler((cmd) {
      final notifier = container.read(pomodoroProvider.notifier);
      if (cmd == 'toggle') {
        notifier.toggle();
      } else if (cmd == 'skip') {
        notifier.skip();
      }
    });

    // 计时状态 → 托盘倒计时文字 + Android 通知

    // 设置变化 → 同步服务开关
    _settingsSub = container.listen<StoredSettings>(settingsProvider, (
      prev,
      next,
    ) {
      _sound.enabled = next.soundEnabled;
      _notify.enabled = next.notificationsEnabled;
      if (prev?.dailyResetHour != next.dailyResetHour) {
        _scheduleDayRollover();
        _pushWidgetState(container.read(engineProvider).state);
      }
    }, fireImmediately: false);

    debugPrint('[init] stage: tail');
    // 小组件在应用未运行时按下的积压命令，启动后执行
    unawaited(() async {
      final cmd = await container
          .read(desktopPlatformProvider)
          .takePendingWidgetCommand();
      if (cmd == null) return;
      final notifier = container.read(pomodoroProvider.notifier);
      if (cmd == 'toggle') {
        notifier.toggle();
      } else if (cmd == 'skip') {
        notifier.skip();
      }
    }());

    // 通道就绪后补推一次当前状态（启动时引擎先于托盘/小组件通道发状态，
    // 首次推送会被吞，这里兜底）
    _checkDayRollover();
    _lastWidgetSignature = null;
    _onTimerState(container.read(engineProvider).state);
    _scheduleDayRollover();
  }

  Timer? _rolloverTimer;
  Timer? _rolloverWatchdog;

  void _scheduleDayRollover() {
    _rolloverTimer?.cancel();
    final now = DateTime.now();
    final next = nextStudyDayBoundary(now, resetHour: _settings.dailyResetHour);
    _rolloverTimer = Timer(next.difference(now), () {
      _checkDayRollover();
      _scheduleDayRollover();
    });
  }

  void _pushWidgetState(PomodoroState state) {
    final endAt = _container?.read(engineProvider).endAt;
    final signature =
        '${state.status.name}:${state.phase.name}:'
        '${endAt?.millisecondsSinceEpoch}:${state.duration.inSeconds}:'
        '${state.isRunning ? 0 : state.remaining.inMilliseconds}:'
        '${state.completedFocusToday}:$_widgetMonthCount:'
        '${_settings.day}:${_settings.dailyResetHour}';
    if (signature == _lastWidgetSignature) return;
    _lastWidgetSignature = signature;
    unawaited(
      _container?.read(desktopPlatformProvider).updateWidgetState({
        'status': state.status.name,
        'phase': state.phase.name,
        'endAtMs': endAt?.millisecondsSinceEpoch.toDouble() ?? 0.0,
        'remainSec': (state.remaining.inMilliseconds / 1000).ceil(),
        'completed': state.completedFocusToday,
        'completedMonth': _widgetMonthCount,
        'day': _settings.day,
        'dailyResetHour': _settings.dailyResetHour,
      }),
    );
  }

  /// 跨天（按每日重置时间偏移）：清零今日计数并同步小组件
  void _checkDayRollover() {
    final container = _container;
    if (container == null) return;
    final settings = container.read(settingsProvider);
    final today = SettingsStore.todayKey(resetHour: settings.dailyResetHour);
    if (settings.day == today) return;
    final count = computeStats(
      container.read(appRepositoryProvider).logs(),
      resetHour: settings.dailyResetHour,
    ).todayCount;
    unawaited(
      container.read(settingsProvider.notifier).setCompletedToday(count),
    );
    container.read(engineProvider).setCompletedFocusToday(count);
    container.read(dataVersionProvider.notifier).bump();
    _lastTraySecond = -1;
    _pushWidgetState(container.read(engineProvider).state);
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
      taskId: isFocus ? container.read(settingsProvider).currentTaskId : null,
      phase: completion.fromPhase,
      completed: completion.completed,
      activeSeconds: completion.activeDuration.inMicroseconds / 1000000,
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
    _rolloverTimer?.cancel();
    _rolloverWatchdog?.cancel();
    _stateSub?.cancel();
    _completionSub?.cancel();
    _settingsSub?.close();
    _statsSub?.close();
    _sound.dispose();
  }
}
