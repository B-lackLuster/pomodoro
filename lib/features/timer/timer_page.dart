import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../state/providers.dart';
import '../settings/settings_page.dart';
import '../stats/stats_page.dart';
import '../tasks/tasks_page.dart';
import 'focus_mode_page.dart';
import 'mini_mode_page.dart';
import 'phase_style.dart';
import 'progress_ring.dart';

class TimerPage extends ConsumerWidget {
  const TimerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pomo = ref.watch(pomodoroProvider);
    final config = ref.watch(settingsProvider).config;
    final currentTask = ref.watch(currentTaskProvider);
    final theme = Theme.of(context);

    final statusText = switch (pomo.status) {
      PomodoroStatus.running => pomo.isBreak ? '休息中' : '专注中',
      PomodoroStatus.paused => '已暂停',
      PomodoroStatus.idle => '准备开始',
    };

    void push(Widget page) => Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => page));

    return Scaffold(
      appBar: AppBar(
        title: const Text('番茄时钟'),
        actions: [
          IconButton(
            icon: const Icon(Icons.checklist_outlined),
            tooltip: '任务',
            onPressed: () => push(const TasksPage()),
          ),
          IconButton(
            icon: const Icon(Icons.insights_outlined),
            tooltip: '数据统计',
            onPressed: () => push(const StatsPage()),
          ),
          IconButton(
            icon: const Icon(Icons.picture_in_picture_alt_outlined),
            tooltip: '迷你悬浮窗（置顶）',
            onPressed: miniModeSupported()
                ? () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const MiniModePage()))
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.fullscreen),
            tooltip: '全屏专注模式',
            onPressed: () => push(const FocusModePage()),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
            onPressed: () => push(const SettingsPage()),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PhaseBadge(pomo: pomo, config: config),
              const SizedBox(height: 24),
              ProgressRing(
                progress: pomo.progress,
                timeText: pomo.clockText,
                statusText: statusText,
                color: phaseColor(pomo.phase),
              ),
              const SizedBox(height: 24),
              Text(
                '今日完成 🍅 × ${pomo.completedFocusToday}'
                '　目标 ${config.dailyGoal}',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => push(const TasksPage()),
                child: Text(
                  currentTaskLabel(currentTask),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: currentTask == null
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _Controls(pomo: pomo),
            ],
          ),
        ),
      ),
    );
  }
}

/// 阶段标签 + 当前长休周期内的番茄进度点
class _PhaseBadge extends StatelessWidget {
  const _PhaseBadge({required this.pomo, required this.config});

  final PomodoroState pomo;
  final PomodoroConfig config;

  @override
  Widget build(BuildContext context) {
    final filled = pomo.focusInCycle == 0
        ? 0
        : ((pomo.focusInCycle - 1) % config.roundsBeforeLongBreak) + 1;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Chip(
          avatar: Icon(
            pomo.isBreak ? Icons.snooze : Icons.local_fire_department,
            size: 18,
            color: phaseColor(pomo.phase),
          ),
          label: Text(phaseLabel(pomo.phase)),
        ),
        const SizedBox(width: 12),
        for (var i = 0; i < config.roundsBeforeLongBreak; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Icon(
              i < filled ? Icons.fiber_manual_record : Icons.fiber_manual_record_outlined,
              size: 10,
              color: i < filled
                  ? phaseColor(PomodoroPhase.focus)
                  : Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
      ],
    );
  }
}

class _Controls extends ConsumerWidget {
  const _Controls({required this.pomo});

  final PomodoroState pomo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(pomodoroProvider.notifier);
    final mainLabel = switch (pomo.status) {
      PomodoroStatus.running => '暂停',
      PomodoroStatus.paused => '继续',
      PomodoroStatus.idle => '开始',
    };

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.outlined(
          tooltip: '重置当前阶段',
          onPressed: controller.resetPhase,
          icon: const Icon(Icons.replay),
        ),
        const SizedBox(width: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            textStyle: const TextStyle(fontSize: 18),
          ),
          onPressed: controller.toggle,
          icon: Icon(pomo.isRunning ? Icons.pause : Icons.play_arrow),
          label: Text(mainLabel),
        ),
        const SizedBox(width: 16),
        IconButton.outlined(
          tooltip: '跳过当前阶段',
          onPressed: controller.skip,
          icon: const Icon(Icons.skip_next),
        ),
      ],
    );
  }
}
