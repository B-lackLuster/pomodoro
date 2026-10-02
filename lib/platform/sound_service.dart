import 'package:audioplayers/audioplayers.dart';

/// 提示音播放（全平台，含 web）。
/// 统一音量 [volume]，避免不同音源响度差异导致过响。
class SoundService {
  final AudioPlayer _player = AudioPlayer();

  /// 播放音量（0.0 - 1.0）
  static const double volume = 0.6;

  bool _enabled = true;

  set enabled(bool value) => _enabled = value;

  Future<void> _play(String asset) async {
    if (!_enabled) return;
    try {
      await _player.stop();
      await _player.play(AssetSource(asset), volume: volume);
    } catch (_) {
      // 播放失败（如浏览器自动播放限制）时静默忽略
    }
  }

  /// 计时开始
  Future<void> playStart() => _play('sound/start.mp3');

  /// 暂停恢复
  Future<void> playResume() => _play('sound/resume.mp3');

  /// 暂停
  Future<void> playPause() => _play('sound/pause.mp3');

  /// 阶段结束（番茄完成/休息结束）
  Future<void> playPhaseEnd() => _play('sound/end.mp3');

  void dispose() {
    _player.dispose();
  }
}
