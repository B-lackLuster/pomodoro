import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/stats_service.dart';
import '../../state/providers.dart';

/// 数据统计：今日/本周/本月完成数、连续打卡、近 7 天柱状图
class StatsPage extends ConsumerWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('数据统计')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: '今日',
                  value: '${stats.todayCount}',
                  sub: '${stats.todayMinutes} 分钟',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: '本周',
                  value: '${stats.weekCount}',
                  sub: '连续打卡 ${stats.streakDays} 天',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: '本月',
                  value: '${stats.monthCount}',
                  sub: '累计 ${stats.totalCount}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('近 7 天', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 160,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: _BarChartPainter(
                        data: stats.last7Days,
                        barColor: theme.colorScheme.primary,
                        gridColor:
                            theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
                        labelColor: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.local_fire_department_outlined),
              title: const Text('连续打卡'),
              trailing: Text(
                '${stats.streakDays} 天',
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
              subtitle: const Text('每天完成至少 1 个番茄即算打卡'),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.sub});

  final String label;
  final String value;
  final String sub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: [
            Text(label, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              sub,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// 近 7 天柱状图（自绘，不引入图表库以控制包体）
class _BarChartPainter extends CustomPainter {
  _BarChartPainter({
    required this.data,
    required this.barColor,
    required this.gridColor,
    required this.labelColor,
  });

  final List<DailyCount> data;
  final Color barColor;
  final Color gridColor;
  final Color labelColor;

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final maxCount =
        data.map((d) => d.count).reduce(math.max).clamp(1, 1 << 30);

    final chartBottom = size.height - 22;
    final slot = size.width / data.length;
    final barWidth = math.min(slot * 0.5, 36.0);

    // 基线
    final baseline = Paint()
      ..strokeWidth = 1
      ..color = gridColor;
    canvas.drawLine(Offset(0, chartBottom), Offset(size.width, chartBottom), baseline);

    final countStyle = TextStyle(fontSize: 10, color: labelColor);
    final dayStyle = TextStyle(fontSize: 10, color: labelColor);

    for (var i = 0; i < data.length; i++) {
      final d = data[i];
      final center = slot * i + slot / 2;
      final barHeight =
          chartBottom * (d.count / maxCount) * 0.86;
      final rect = Rect.fromLTWH(
          center - barWidth / 2, chartBottom - barHeight, barWidth, barHeight);

      final paint = Paint()..color = barColor;
      final rrect = RRect.fromRectAndCorners(
        rect,
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      );
      canvas.drawRRect(rrect, paint);

      // 数量标签
      if (d.count > 0) {
        _text(canvas, '${d.count}', Offset(center, chartBottom - barHeight - 8),
            countStyle);
      }

      // 星期标签
      final weekdayIndex = (d.day.weekday + 6) % 7; // 周一=0
      _text(canvas, _weekdays[weekdayIndex], Offset(center, chartBottom + 10), dayStyle);
    }
  }

  void _text(Canvas canvas, String text, Offset center, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy));
  }

  @override
  bool shouldRepaint(_BarChartPainter oldDelegate) => true;
}
