import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../state/providers.dart';
import 'phase_style.dart';

/// 迷你悬浮窗模式：无边框、置顶小窗。
/// 渐变底 + 阶段鼓励语（随时间轮换）+ 大倒计时 + 底部进度线，可拖动。
/// 仅桌面端可用；进入时收起标题栏缩小窗口，退出时还原。
class MiniModePage extends ConsumerStatefulWidget {
  const MiniModePage({super.key});

  @override
  ConsumerState<MiniModePage> createState() => _MiniModePageState();
}

class _MiniModePageState extends ConsumerState<MiniModePage> {
  static const _focusPhrases = [
    '专注当下，一次只做一件事',
    '稳住节奏，胜利在望',
    '此刻的专注，是未来的底气',
    '深呼吸，进入心流',
    '关掉干扰，拥抱专注',
    '每一分钟都算数',
    '你在变强的路上',
  ];

  static const _shortBreakPhrases = [
    '休息一下，是为了走更远',
    '起身活动，看看远方',
    '喝口水，放松眼睛',
    '喘口气，你做得很好',
    '伸个懒腰，再战一轮',
  ];

  static const _longBreakPhrases = [
    '好好休息，犒劳一下自己',
    '长休时刻，彻底放空',
    '充好电，下一程更精彩',
    '走得远的人，都懂得休息',
  ];

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

    // 鼓励语随剩余分钟数轮换，节奏感与内容同步变化
    final phrases = switch (pomo.phase) {
      PomodoroPhase.focus => _focusPhrases,
      PomodoroPhase.shortBreak => _shortBreakPhrases,
      PomodoroPhase.longBreak => _longBreakPhrases,
    };
    final phrase = phrases[
        (pomo.focusInCycle * 3 + pomo.remaining.inMinutes) % phrases.length];

    return Scaffold(
      backgroundColor: const Color(0xFF171012),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              // 按住空白处拖动窗口
              onPanStart: (_) =>
                  ref.read(desktopPlatformProvider).startWindowDrag(),
              behavior: HitTestBehavior.opaque,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2A1A1E), Color(0xFF171012)],
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(14, 10, 4, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: playing
                                    ? color
                                    : color.withValues(alpha: 0.35),
                                shape: BoxShape.circle,
                                boxShadow: playing
                                    ? [
                                        BoxShadow(
                                          color: color.withValues(alpha: 0.6),
                                          blurRadius: 6,
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              phaseLabel(pomo.phase),
                              style: TextStyle(
                                color: color.withValues(alpha: 0.9),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          pomo.clockText,
                          style: const TextStyle(
                            color: Color(0xFFF3E7E4),
                            fontSize: 34,
                            height: 1.1,
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          phrase,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: const Color(0xFFF3E7E4)
                                .withValues(alpha: 0.55),
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _MiniButton(
                          icon: playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          tooltip: playing ? '暂停' : '开始',
                          onTap: () =>
                              ref.read(pomodoroProvider.notifier).toggle(),
                        ),
                        _MiniButton(
                          icon: Icons.skip_next_rounded,
                          tooltip: '跳过',
                          onTap: () =>
                              ref.read(pomodoroProvider.notifier).skip(),
                        ),
                        _MiniButton(
                          icon: Icons.close_fullscreen_rounded,
                          tooltip: '还原窗口',
                          onTap: _exitMini,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 底部进度线
          Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: pomo.progress,
              child: Container(height: 2.5, color: color),
            ),
          ),
        ],
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
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          child: Icon(icon, color: const Color(0xFFF3E7E4), size: 20),
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
