import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../state/providers.dart';

/// 任务清单：添加任务、设预估番茄数、勾选完成、点选为"当前任务"。
/// 完成的番茄自动归属当前任务。
class TasksPage extends ConsumerWidget {
  const TasksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksProvider);
    final settings = ref.watch(settingsProvider);
    final currentId = settings.currentTaskId;

    final active = tasks.where((t) => !t.done).toList();
    final finished = tasks.where((t) => t.done).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('任务')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context, ref),
        child: const Icon(Icons.add),
      ),
      body: tasks.isEmpty
          ? const Center(
              child: Text('还没有任务\n点右下角 + 添加一个', textAlign: TextAlign.center))
          : ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                for (final task in active)
                  _TaskTile(task: task, isCurrent: task.id == currentId),
                if (finished.isNotEmpty) ...[
                  const Divider(height: 1),
                  const _SectionLabel('已完成'),
                  for (final task in finished)
                    _TaskTile(task: task, isCurrent: task.id == currentId),
                ],
              ],
            ),
    );
  }

  Future<void> _showAddDialog(BuildContext context, WidgetRef ref) async {
    final titleController = TextEditingController();
    var estimate = 1;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('新建任务'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                autofocus: true,
                decoration: const InputDecoration(labelText: '任务名称'),
                onSubmitted: (_) =>
                    Navigator.of(context).pop(true),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('预估番茄'),
                  const Spacer(),
                  IconButton(
                    onPressed: estimate > 1
                        ? () => setState(() => estimate -= 1)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$estimate',
                      style: Theme.of(context).textTheme.titleMedium),
                  IconButton(
                    onPressed: estimate < 99
                        ? () => setState(() => estimate += 1)
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && titleController.text.trim().isNotEmpty) {
      await ref.read(tasksProvider.notifier).add(titleController.text, estimate);
    }
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

class _TaskTile extends ConsumerWidget {
  const _TaskTile({required this.task, required this.isCurrent});

  final Task task;
  final bool isCurrent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(tasksProvider.notifier);
    final doneCount = ref.watch(appRepositoryProvider).focusCountForTask(task.id);
    final theme = Theme.of(context);

    return ListTile(
      leading: Checkbox(
        value: task.done,
        onChanged: (_) => controller.toggleDone(task),
      ),
      title: Text(
        task.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: task.done
            ? TextStyle(
                decoration: TextDecoration.lineThrough,
                color: theme.colorScheme.onSurfaceVariant)
            : null,
      ),
      subtitle: Text(
        '🍅 $doneCount${task.done ? '' : ' / 预估 ${task.estimate}'}'
        '${isCurrent ? '　·　当前任务' : ''}',
        style: isCurrent
            ? TextStyle(color: theme.colorScheme.primary)
            : theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      onTap: task.done
          ? null
          : () async {
              await ref
                  .read(settingsProvider.notifier)
                  .setCurrentTask(isCurrent ? null : task.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(
                      isCurrent ? '已取消当前任务' : '当前任务：${task.title}（完成的番茄将归属它）'),
                  duration: const Duration(seconds: 2),
                ));
              }
            },
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 20),
        tooltip: '删除任务',
        onPressed: () => controller.remove(task.id),
      ),
    );
  }
}

/// 供计时页显示当前任务
String currentTaskLabel(Task? task) =>
    task == null ? '未选择任务（去任务页点选）' : '当前：${task.title}';
