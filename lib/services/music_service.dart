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
  MusicHandler? get audioHandler => _audioHandler;

  // 为了兼容现有代码，暴露内部的 AudioPlayer
  // 如果尚未初始化，返回 null 而不是抛出异常，防止 Release 模式崩溃
  AudioPlayer? get player {
    return _audioHandler?.player ?? _fallbackPlayer;
  }

  @override
  void onInit() {
    super.onInit();
    // 不要在 onInit 中做异步初始化阻塞，改为单独调用或者在 main 中 await
  }

  // Fallback player if AudioService fails
  AudioPlayer? _fallbackPlayer;

  // 确保初始化完成
  Future<MusicService> init() async {
    try {
      debugPrint('MusicService: Initializing AudioService...');

      // 1. 尝试请求必须的权限 (Android 13+ 通知权限)
      await _requestPermissions();

      // 2. 初始化 AudioService
      final handler = await initAudioService();
      if (handler is MusicHandler) {
        await handler.ready;
        _audioHandler = handler;
        initErrorMessage.value = ''; // Clear error on success
      } else {
        throw Exception("Initialized handler is not MusicHandler");
      }
      debugPrint('MusicService: AudioService Initialized Success');
    } catch (e, stack) {
      debugPrint('MusicService: Error initializing AudioService: $e');
      debugPrintStack(stackTrace: stack); // Log stack trace

      initErrorMessage.value = 'Mode Restricted: ${e.toString()}';

      // FALLBACK: Initialize basic AudioPlayer so app is usable
      if (_fallbackPlayer == null) {
        debugPrint('MusicService: Initializing Fallback Player...');
        _fallbackPlayer = AudioPlayer();
      }
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

  Future<void> ensureNotificationPermission() => _requestPermissions();

  // === 播放控制便捷方法 ===
  // 优先通过 AudioHandler 执行（确保通知栏正常），fallback 时直接操作 AudioPlayer

  /// 播放（通过 handler 触发，确保前台服务启动）
  Future<void> play() async {
    if (_audioHandler != null) {
      await _audioHandler!.play();
    } else {
      await _fallbackPlayer?.play();
    }
  }

  /// 暂停
  Future<void> pause() async {
    if (_audioHandler != null) {
      await _audioHandler!.pause();
    } else {
      await _fallbackPlayer?.pause();
    }
  }

  /// 跳转进度
  Future<void> seek(Duration position) async {
    if (_audioHandler != null) {
      await _audioHandler!.seek(position);
    } else {
      await _fallbackPlayer?.seek(position);
    }
  }

  /// 停止播放
  Future<void> stop() async {
    if (_audioHandler != null) {
      await _audioHandler!.stop();
    } else {
      await _fallbackPlayer?.stop();
    }
  }

  /// 完整播放流程：设置音源 + 更新 mediaItem + 播放
  /// 返回音频时长（可能为 null）
  Future<Duration?> setSourceAndPlay(
    AudioSource source,
    MediaItem mediaItem,
    Map<String, String>? headers,
  ) async {
    if (_audioHandler != null) {
      return await _audioHandler!.setAudioSourceAndPlay(source, mediaItem);
    }
    // Fallback: 直接用 player（无通知栏）
    final duration = await _fallbackPlayer?.setAudioSource(source);
    await _fallbackPlayer?.play();
    return duration;
  }

  // 兼容旧方法，但现在总是返回已初始化的 player（因为 init 在 main 做了）
  Future<AudioPlayer?> getOrInitPlayer() async {
    if (_audioHandler == null && _fallbackPlayer == null) {
      await init();
    }
    // Return either the full handler player or the fallback one
    return _audioHandler?.player ?? _fallbackPlayer;
  }

  @override
  void onClose() {
    _audioHandler?.stop();
    super.onClose();
  }
}
