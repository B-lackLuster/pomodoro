import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../state/providers.dart';
import 'phase_style.dart';
import 'progress_ring.dart';

/// 全屏专注模式：整屏只显示倒计时，点击任意位置退出。
/// 桌面端进入时把窗口切成真全屏，退出时还原。
class FocusModePage extends ConsumerStatefulWidget {
  const FocusModePage({super.key});

  @override
  ConsumerState<FocusModePage> createState() => _FocusModePageState();
}

class _FocusModePageState extends ConsumerState<FocusModePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(desktopPlatformProvider).setFullScreen(true);
    });
  }

  Future<void> _exit() async {
    await ref.read(desktopPlatformProvider).setFullScreen(false);
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final pomo = ref.watch(pomodoroProvider);
    final phaseColor = phaseColors[pomo.phase]!;
    final statusText = switch (pomo.status) {
      PomodoroStatus.running => pomo.isBreak ? '休息中' : '专注中',
      PomodoroStatus.paused => '已暂停 · 点击任意位置返回',
      PomodoroStatus.idle => '点击任意位置返回',
    };

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        ref.read(desktopPlatformProvider).setFullScreen(false);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _exit,
          child: Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final ringSize =
                    math.min(constraints.maxWidth, constraints.maxHeight) * 0.72;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ProgressRing(
                      progress: pomo.progress,
                      timeText: pomo.clockText,
                      statusText: '${phaseLabel(pomo.phase)} · $statusText',
                      color: phaseColor,
                      size: ringSize,
                      strokeWidth: 12,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
