import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/settings_store.dart';
import 'features/timer/timer_page.dart';
import 'platform/app_services.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final initial = SettingsStore(prefs).load();

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      initialSettingsProvider.overrideWithValue(initial),
    ],
  );

  // 先渲染界面，再初始化平台服务（窗口/托盘/通知/前台服务）。
  // 任何平台服务失败都不再阻塞首帧（release 模式下未捕获异常会表现为黑屏）。
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const PomodoroApp(),
    ),
  );

  await AppServices.instance.init(container);
}

const _tomatoSeed = Color(0xFFE53935);

class PomodoroApp extends ConsumerWidget {
  const PomodoroApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = switch (ref.watch(settingsProvider).themeMode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    return MaterialApp(
      title: '番茄时钟',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _tomatoSeed),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _tomatoSeed,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: themeMode,
      home: const TimerPage(),
    );
  }
}
