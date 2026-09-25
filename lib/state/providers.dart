import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';
import '../core/timer_engine.dart';
import '../data/app_repository.dart';
import '../data/models.dart';
import '../data/settings_store.dart';
import '../data/stats_service.dart';
import '../platform/android_service.dart';
import '../platform/desktop.dart';

/// 在 main() 中通过 ProviderScope overrides 注入
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('必须在 main 中 override sharedPreferencesProvider'),
);

final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => SettingsStore(ref.watch(sharedPreferencesProvider)),
);

final appRepositoryProvider = Provider<AppRepository>(
  (ref) => AppRepository(ref.watch(sharedPreferencesProvider)),
);

/// 数据版本号：日志/任务变化时自增，驱动统计与任务列表刷新
class DataVersionController extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final dataVersionProvider =
    NotifierProvider<DataVersionController, int>(DataVersionController.new);

/// 桌面平台能力（web 上为空实现）
final desktopPlatformProvider = Provider<DesktopPlatform>(
  (ref) => createDesktopPlatform(),
);

/// Android 前台服务（非 Android 为空实现）
final androidTimerServiceProvider = Provider<AndroidTimerService>(
  (ref) => createAndroidTimerService(),
);

/// 在 main() 中注入初始设置（已含跨天清零处理）
final initialSettingsProvider = Provider<StoredSettings>(
  (ref) => throw UnimplementedError('必须在 main 中 override initialSettingsProvider'),
);

final engineProvider = Provider<PomodoroEngine>((ref) {
  final engine = PomodoroEngine();
  ref.onDispose(engine.dispose);
  return engine;
});

class SettingsController extends Notifier<StoredSettings> {
  @override
  StoredSettings build() => ref.watch(initialSettingsProvider);

  Future<void> updateConfig(PomodoroConfig config) async {
    state = state.copyWith(config: config);
    ref.read(engineProvider).updateConfig(config);
    await _persist();
  }

  Future<void> setThemeMode(String mode) async {
    state = state.copyWith(themeMode: mode);
    await _persist();
  }

  Future<void> setNotificationsEnabled(bool value) async {
    state = state.copyWith(notificationsEnabled: value);
    await _persist();
  }

  Future<void> setSoundEnabled(bool value) async {
    state = state.copyWith(soundEnabled: value);
    await _persist();
  }

  Future<void> setCloseToTray(bool value) async {
    state = state.copyWith(closeToTray: value);
    await _persist();
  }

  Future<void> setCompletedToday(int count) async {
    state = state.copyWith(completedToday: count, day: SettingsStore.todayKey());
    await _persist();
  }

  /// 切换开机自启（含系统侧实际生效的副作用）
  Future<void> setLaunchAtStartup(bool value) async {
    state = state.copyWith(launchAtStartup: value);
    final desktop = ref.read(desktopPlatformProvider);
    if (desktop.isAvailable) {
      if (value) {
        await desktop.enableAutoStart();
      } else {
        await desktop.disableAutoStart();
      }
    }
    await _persist();
  }

  /// 切换当前任务（完成番茄时记录归属）
  Future<void> setCurrentTask(String? taskId) async {
    state = state.copyWith(currentTaskId: taskId, clearCurrentTask: taskId == null);
    await _persist();
  }

  /// 仅同步状态（不调用系统接口），用于启动时与系统真实状态对齐
  Future<void> syncLaunchAtStartup(bool value) async {
    state = state.copyWith(launchAtStartup: value);
    await _persist();
  }

  Future<void> _persist() => ref.read(settingsStoreProvider).save(state);
}

class TasksController extends Notifier<List<Task>> {
  @override
  List<Task> build() {
    ref.watch(dataVersionProvider);
    return ref.watch(appRepositoryProvider).tasks();
  }

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${DateTime.now().microsecond}';

  Future<void> add(String title, int estimate) async {
    final repo = ref.read(appRepositoryProvider);
    await repo.addTask(Task(
      id: _newId(),
      title: title.trim(),
      estimate: estimate.clamp(1, 99),
      createdAt: DateTime.now(),
    ));
    state = repo.tasks();
  }

  Future<void> toggleDone(Task task) async {
    final repo = ref.read(appRepositoryProvider);
    await repo.updateTask(task.copyWith(done: !task.done));
    state = repo.tasks();
  }

  Future<void> edit(Task task, {String? title, int? estimate}) async {
    final repo = ref.read(appRepositoryProvider);
    await repo.updateTask(task.copyWith(title: title, estimate: estimate));
    state = repo.tasks();
  }

  Future<void> remove(String id) async {
    final repo = ref.read(appRepositoryProvider);
    await repo.removeTask(id);
    if (ref.read(settingsProvider).currentTaskId == id) {
      await ref.read(settingsProvider.notifier).setCurrentTask(null);
    }
    state = repo.tasks();
  }
}

final tasksProvider =
    NotifierProvider<TasksController, List<Task>>(TasksController.new);

/// 当前选中的任务对象（无则 null）
final currentTaskProvider = Provider<Task?>((ref) {
  final id = ref.watch(settingsProvider).currentTaskId;
  if (id == null) return null;
  final list = ref.watch(tasksProvider);
  return list.where((t) => t.id == id).firstOrNull;
});

final statsProvider = Provider<StatsSummary>((ref) {
  ref.watch(dataVersionProvider);
  return computeStats(ref.watch(appRepositoryProvider).logs());
});

class PomodoroController extends Notifier<PomodoroState> {
  StreamSubscription<PomodoroState>? _sub;

  @override
  PomodoroState build() {
    final engine = ref.watch(engineProvider);
    final settings = ref.watch(initialSettingsProvider);
    engine.updateConfig(settings.config);
    engine.setCompletedFocusToday(settings.completedToday);

    _sub?.cancel();
    _sub = engine.stream.listen((s) {
      final prev = state;
      state = s;
      if (s.completedFocusToday != prev.completedFocusToday) {
        ref
            .read(settingsProvider.notifier)
            .setCompletedToday(s.completedFocusToday);
      }
    });
    ref.onDispose(() => _sub?.cancel());
    return engine.state;
  }

  void start() => ref.read(engineProvider).start();
  void pause() => ref.read(engineProvider).pause();
  void toggle() => ref.read(engineProvider).toggle();
  void skip() => ref.read(engineProvider).skip();
  void resetPhase() => ref.read(engineProvider).resetPhase();
  void resetAll() => ref.read(engineProvider).resetAll();
}

final settingsProvider =
    NotifierProvider<SettingsController, StoredSettings>(SettingsController.new);

final pomodoroProvider =
    NotifierProvider<PomodoroController, PomodoroState>(PomodoroController.new);
