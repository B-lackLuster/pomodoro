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
  final store = SettingsStore(prefs);
  final initial = store.load();

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      initialSettingsProvider.overrideWithValue(initial),
    ],
  );
  // 窗口/托盘/通知等平台服务必须在 runApp 之前就绪
  await AppServices.instance.init(container);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const PomodoroApp(),
    ),
  );
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
