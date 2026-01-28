import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:flutter/foundation.dart';

class MusicService extends GetxService {
  late AudioPlayer player;

  @override
  void onInit() {
    super.onInit();
    _initPlayer();
  }

  void _initPlayer() {
    try {
      // 核心：全局唯一的播放器实例
      player = AudioPlayer();
    } catch (e) {
      debugPrint('MusicService: Error creating AudioPlayer: $e');
      // 如果是为了解决热重载导致的单例问题，这里可能很难捕获，
      // 因为 PlatformException 通常在构造函数内部或 native 调用时抛出
    }
  }

  Future<void> init() async {
    // 确保 JustAudioBackground 初始化
    // 注意：JustAudioBackground.init() 应该在 main.dart 中调用
    // 但为了保险，这里可以检查或再次调用（虽然它是一个 Future）
    debugPrint('MusicService initialized');
  }

  @override
  void onClose() {
    // 全局服务一般不销毁播放器，除非应用退出
    player.dispose();
    super.onClose();
  }
}
