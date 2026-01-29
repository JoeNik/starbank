import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'audio_handler.dart';

class MusicService extends GetxService {
  MusicHandler? _audioHandler;
  final RxString initErrorMessage = ''.obs;

  // 暴露 Handler 和 Player
  MusicHandler get audioHandler => _audioHandler!;

  // 为了兼容现有代码，暴露内部的 AudioPlayer
  // 如果尚未初始化，返回 null 而不是抛出异常，防止 Release 模式崩溃
  AudioPlayer? get player {
    return _audioHandler?.player;
  }

  @override
  void onInit() {
    super.onInit();
    // 不要在 onInit 中做异步初始化阻塞，改为单独调用或者在 main 中 await
  }

  // 确保初始化完成
  Future<MusicService> init() async {
    try {
      debugPrint('MusicService: Initializing AudioService...');

      // 1. 尝试请求必须的权限 (Android 13+ 通知权限)
      await _requestPermissions();

      // 2. 初始化 AudioService
      final handler = await initAudioService();
      if (handler is MusicHandler) {
        _audioHandler = handler;
        initErrorMessage.value = ''; // Clear error on success
      } else {
        throw Exception("Initialized handler is not MusicHandler");
      }
      debugPrint('MusicService: AudioService Initialized Success');
    } catch (e, stack) {
      debugPrint('MusicService: Error initializing AudioService: $e');
      debugPrintStack(stackTrace: stack); // Log stack trace
      initErrorMessage.value = e.toString();
    }
    return this;
  }

  Future<void> _requestPermissions() async {
    try {
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    } catch (e) {
      debugPrint('Permission request error: $e');
    }
  }

  // 兼容旧方法，但现在总是返回已初始化的 player（因为 init 在 main 做了）
  Future<AudioPlayer?> getOrInitPlayer() async {
    if (_audioHandler == null) {
      await init();
    }
    return _audioHandler?.player;
  }

  @override
  void onClose() {
    _audioHandler?.stop();
    super.onClose();
  }
}
