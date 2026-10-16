import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../platform/json_file.dart';
import '../../state/providers.dart';

final _packageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);

/// 当前是否为桌面平台（决定窗口相关开关是否展示）
final bool isDesktop =
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux);

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  Future<void> _exportData(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final suggested =
        'pomodoro-backup-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.json';
    final location = await getSaveLocation(suggestedName: suggested);
    if (location == null) return;
    final json = ref.read(appRepositoryProvider).exportJson();
    await writeTextFile(location.path, json);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已导出到 ${location.path}')));
    }
  }

  Future<void> _importData(BuildContext context, WidgetRef ref) async {
    const typeGroup = XTypeGroup(label: 'JSON', extensions: ['json']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null || !context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入备份'),
        content: const Text('将按 id 合并备份中的番茄记录与任务（不覆盖现有数据），继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final (logs, tasks) = await ref
          .read(appRepositoryProvider)
          .importJson(await file.readAsString());
      ref.invalidate(dataVersionProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入完成：新增 $logs 条番茄记录、$tasks 个任务')),
        );
      }
    } on FormatException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导入失败：${e.message}')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final config = settings.config;
    final notifier = ref.read(settingsProvider.notifier);
    final packageInfo = ref.watch(_packageInfoProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const _SectionHeader('时长（分钟）'),
          _NumberTile(
            label: '专注时长',
            value: config.focusMinutes,
            min: 1,
            max: 180,
            step: 5,
            onChanged: (v) =>
                notifier.updateConfig(config.copyWith(focusMinutes: v)),
          ),
          _NumberTile(
            label: '短休息时长',
            value: config.shortBreakMinutes,
            min: 1,
            max: 60,
            step: 1,
            onChanged: (v) =>
                notifier.updateConfig(config.copyWith(shortBreakMinutes: v)),
          ),
          _NumberTile(
            label: '长休息时长',
            value: config.longBreakMinutes,
            min: 5,
            max: 90,
            step: 5,
            onChanged: (v) =>
                notifier.updateConfig(config.copyWith(longBreakMinutes: v)),
          ),
          _NumberTile(
            label: '长休息间隔（连续番茄数）',
            value: config.roundsBeforeLongBreak,
            min: 2,
            max: 8,
            step: 1,
            onChanged: (v) => notifier.updateConfig(
              config.copyWith(roundsBeforeLongBreak: v),
            ),
          ),
          _NumberTile(
            label: '每日目标（个番茄）',
            value: config.dailyGoal,
            min: 1,
            max: 24,
            step: 1,
            onChanged: (v) =>
                notifier.updateConfig(config.copyWith(dailyGoal: v)),
          ),
          const _SectionHeader('计数与连续规则'),
          const ListTile(
            title: Text('专注过半后跳过，计 1 个番茄'),
            subtitle: Text('按实际专注时间计算，不含暂停；恰好一半不计数。'),
          ),
          ListTile(
            title: Text('连续 ${config.roundsBeforeLongBreak} 个番茄后长休'),
            subtitle: Text(
              '暂停、休息及等待超过 ${config.focusMinutes} 分钟，'
              '或跳过未达标的专注，连续进度重新累计；今日计数保留。',
            ),
          ),
          const _SectionHeader('自动化'),
          SwitchListTile(
            title: const Text('专注结束后自动开始休息'),
            value: config.autoStartBreak,
            onChanged: (v) =>
                notifier.updateConfig(config.copyWith(autoStartBreak: v)),
          ),
          SwitchListTile(
            title: const Text('休息结束后自动开始专注'),
            value: config.autoStartFocus,
            onChanged: (v) =>
                notifier.updateConfig(config.copyWith(autoStartFocus: v)),
          ),
          const _SectionHeader('每日'),
          ListTile(
            title: const Text('每日重置时间'),
            subtitle: const Text('今日完成数和统计在此时间跨天'),
            trailing: Text(
              '${settings.dailyResetHour.toString().padLeft(2, '0')}:00',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            onTap: () async {
              final hour = await showDialog<int>(
                context: context,
                builder: (context) =>
                    _ResetHourDialog(initial: settings.dailyResetHour),
              );
              if (hour != null) {
                await notifier.setDailyResetHour(hour);
              }
            },
          ),
          const _SectionHeader('通知与声音'),
          if (isDesktop)
            SwitchListTile(
              title: const Text('阶段结束系统通知'),
              value: settings.notificationsEnabled,
              onChanged: (v) => notifier.setNotificationsEnabled(v),
            ),
          SwitchListTile(
            title: const Text('阶段结束提示音'),
            value: settings.soundEnabled,
            onChanged: (v) => notifier.setSoundEnabled(v),
          ),
          const _SectionHeader('外观'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'system',
                  label: Text('跟随系统'),
                  icon: Icon(Icons.brightness_auto),
                ),
                ButtonSegment(
                  value: 'light',
                  label: Text('浅色'),
                  icon: Icon(Icons.light_mode_outlined),
                ),
                ButtonSegment(
                  value: 'dark',
                  label: Text('深色'),
                  icon: Icon(Icons.dark_mode_outlined),
                ),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (selection) =>
                  notifier.setThemeMode(selection.first),
            ),
          ),
          if (isDesktop) ...[
            const _SectionHeader('窗口'),
            SwitchListTile(
              title: const Text('关闭窗口时最小化到托盘'),
              value: settings.closeToTray,
              onChanged: (v) => notifier.setCloseToTray(v),
            ),
            SwitchListTile(
              title: const Text('开机自动启动'),
              value: settings.launchAtStartup,
              onChanged: (v) => notifier.setLaunchAtStartup(v),
            ),
            const _SectionHeader('数据'),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('导出数据（番茄记录 + 任务）'),
              onTap: () => _exportData(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('从备份导入（按 id 合并）'),
              onTap: () => _importData(context, ref),
            ),
          ],
          const _SectionHeader('关于'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('番茄时钟'),
            subtitle: packageInfo.when(
              data: (info) =>
                  Text('版本 ${info.version}（构建 ${info.buildNumber}）'),
              loading: () => const Text('正在读取版本…'),
              error: (_, _) => const Text('暂时无法读取版本'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

class _NumberTile extends StatelessWidget {
  const _NumberTile({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: value - step >= min
                ? () => onChanged(value - step)
                : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(
            width: 40,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            onPressed: value + step <= max
                ? () => onChanged(value + step)
                : null,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }
}

class _ResetHourDialog extends StatefulWidget {
  const _ResetHourDialog({required this.initial});

  final int initial;

  @override
  State<_ResetHourDialog> createState() => _ResetHourDialogState();
}

class _ResetHourDialogState extends State<_ResetHourDialog> {
  late int hour = widget.initial;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('每日重置时间'),
      content: SizedBox(
        width: 280,
        child: DropdownButtonFormField<int>(
          initialValue: hour,
          decoration: const InputDecoration(labelText: '重置时刻'),
          items: [
            for (var h = 0; h < 24; h++)
              DropdownMenuItem(
                value: h,
                child: Text(
                  '${h.toString().padLeft(2, '0')}:00'
                  '${h == 4
                      ? '（默认）'
                      : h == 0
                      ? '（自然日）'
                      : ''}',
                ),
              ),
          ],
          onChanged: (v) => setState(() => hour = v ?? 0),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(hour),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
