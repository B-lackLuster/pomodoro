import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import 'phase_style.dart';

/// 迷你悬浮窗模式：无边框、置顶小窗，只保留倒计时和操作按钮，可拖动。
/// 仅桌面端可用；进入时收起标题栏缩小窗口，退出时还原。
class MiniModePage extends ConsumerStatefulWidget {
  const MiniModePage({super.key});

  @override
  ConsumerState<MiniModePage> createState() => _MiniModePageState();
}

class _MiniModePageState extends ConsumerState<MiniModePage> {
  Future<void> _enterMini() async {
    await ref.read(desktopPlatformProvider).enterMiniMode();
  }

  Future<void> _exitMini() async {
    await ref.read(desktopPlatformProvider).exitMiniMode();
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _enterMini());
  }

  @override
  Widget build(BuildContext context) {
    final pomo = ref.watch(pomodoroProvider);
    final color = phaseColor(pomo.phase);
    final playing = pomo.isRunning;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1214),
      body: GestureDetector(
        // 按住空白处拖动窗口
        onPanStart: (_) =>
            ref.read(desktopPlatformProvider).startWindowDrag(),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: playing ? color : color.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                pomo.clockText,
                style: const TextStyle(
                  color: Color(0xFFF3E7E4),
                  fontSize: 34,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              _MiniButton(
                icon: playing
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                tooltip: playing ? '暂停' : '开始',
                onTap: () => ref.read(pomodoroProvider.notifier).toggle(),
              ),
              _MiniButton(
                icon: Icons.skip_next_rounded,
                tooltip: '跳过',
                onTap: () => ref.read(pomodoroProvider.notifier).skip(),
              ),
              _MiniButton(
                icon: Icons.close_fullscreen_rounded,
                tooltip: '还原窗口',
                onTap: _exitMini,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: const Color(0xFFF3E7E4), size: 22),
        ),
      ),
    );
  }
}

/// 当前平台是否支持迷你悬浮窗（桌面端）
bool miniModeSupported() =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux);
