import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/core/models.dart';
import 'package:pomodoro/data/app_repository.dart';
import 'package:pomodoro/data/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repo = AppRepository(await SharedPreferences.getInstance());
  });

  test('任务增删改', () async {
    await repo.addTask(Task(
      id: 't1',
      title: '写周报',
      estimate: 3,
      createdAt: DateTime(2026, 9, 6),
    ));
    expect(repo.tasks().single.title, '写周报');

    await repo.updateTask(repo.tasks().single.copyWith(done: true));
    expect(repo.tasks().single.done, true);

    await repo.removeTask('t1');
    expect(repo.tasks(), isEmpty);
  });

  test('日志追加与按任务聚合', () async {
    await repo.addTask(Task(
        id: 't1', title: '任务A', estimate: 2, createdAt: DateTime(2026, 9, 6)));
    final base = DateTime(2026, 9, 6, 10);
    await repo.addLog(PomodoroLog(
      id: 'l1',
      taskId: 't1',
      phase: PomodoroPhase.focus,
      completed: true,
      start: base,
      end: base.add(const Duration(minutes: 25)),
    ));
    await repo.addLog(PomodoroLog(
      id: 'l2',
      taskId: 't1',
      phase: PomodoroPhase.focus,
      completed: false, // 跳过的不算完成
      start: base.add(const Duration(hours: 1)),
      end: base.add(const Duration(hours: 1, minutes: 10)),
    ));
    await repo.addLog(PomodoroLog(
      id: 'l3',
      phase: PomodoroPhase.shortBreak,
      completed: true,
      start: base.add(const Duration(minutes: 25)),
      end: base.add(const Duration(minutes: 30)),
    ));

    expect(repo.logs().length, 3);
    expect(repo.focusCountForTask('t1'), 1);
    expect(repo.focusCountForTask('none'), 0);
  });

  test('导出再导入：跨仓库按 id 合并不重复', () async {
    final base = DateTime(2026, 9, 6, 9);
    await repo.addLog(PomodoroLog(
      id: 'l1',
      taskId: 't1',
      phase: PomodoroPhase.focus,
      completed: true,
      start: base,
      end: base.add(const Duration(minutes: 25)),
    ));
    await repo.addTask(Task(
        id: 't1', title: '任务A', estimate: 1, createdAt: DateTime(2026, 9, 6)));

    final json = repo.exportJson();

    // 另一个仓库导入同一份备份两次 → 第二次全去重
    SharedPreferences.setMockInitialValues({});
    final repo2 = AppRepository(await SharedPreferences.getInstance());
    final (newLogs1, newTasks1) = await repo2.importJson(json);
    expect(newLogs1, 1);
    expect(newTasks1, 1);

    final (newLogs2, newTasks2) = await repo2.importJson(json);
    expect(newLogs2, 0);
    expect(newTasks2, 0);
    expect(repo2.logs().single.id, 'l1');
    expect(repo2.tasks().single.title, '任务A');
  });

  test('导入非本应用备份抛 FormatException', () async {
    expect(
      () => repo.importJson('{"app": "other"}'),
      throwsFormatException,
    );
  });
}
