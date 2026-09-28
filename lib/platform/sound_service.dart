import 'package:audioplayers/audioplayers.dart';

/// 提示音播放（全平台，含 web）
class SoundService {
  final AudioPlayer _player = AudioPlayer();
  bool _enabled = true;

  set enabled(bool value) => _enabled = value;

  Future<void> playBell() async {
    if (!_enabled) return;
    try {
      await _player.stop();
      await _player.play(AssetSource('sound/bell.wav'));
    } catch (_) {
      // 播放失败（如浏览器自动播放限制）时静默忽略
    }
  }

  /// 计时开始音：轻快短 blip
  Future<void> playStart() async {
    if (!_enabled) return;
    try {
      await _player.stop();
      await _player.play(AssetSource('sound/start.wav'));
    } catch (_) {}
  }

  void dispose() {
    _player.dispose();
  }
}
