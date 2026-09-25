import 'android_service.dart';

/// 非 Android 平台的空实现
class AndroidTimerServiceImpl implements AndroidTimerService {
  @override
  void Function()? onUserToggle;

  @override
  void Function()? onUserSkip;

  @override
  bool get isAvailable => false;

  @override
  Future<void> init() async {}

  @override
  Future<void> start({
    required String title,
    required String text,
    required bool running,
  }) async {}

  @override
  Future<void> update({
    required String title,
    required String text,
    required bool running,
  }) async {}

  @override
  Future<void> stop() async {}

  @override
  void dispose() {}
}
