import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:flutter/foundation.dart';

class MusicService extends GetxService {
  AudioPlayer? _player;
  AudioPlayer? get player => _player;

  @override
  void onInit() {
    super.onInit();
    // Do not init player here to avoid startup crash
  }

  Future<AudioPlayer?> getOrInitPlayer() async {
    if (_player != null) return _player;

    debugPrint('MusicService: Initializing AudioPlayer lazy...');

    // Attempt 1: Normal Create
    try {
      _player = AudioPlayer();
      return _player;
    } catch (e) {
      debugPrint('MusicService: First attempt failed ($e). trying fallback...');
    }

    // Attempt 2: Re-init Background then Create (Self-Healing)
    try {
      if (GetPlatform.isAndroid || GetPlatform.isIOS) {
        await JustAudioBackground.init(
          androidNotificationChannelId: 'com.ryanheise.bg_demo.channel.audio',
          androidNotificationChannelName: 'Audio playback',
          androidNotificationOngoing: true,
        );
      }
      debugPrint(
          'MusicService: Fallback init success. Retrying Player creation...');
      _player = AudioPlayer();
      return _player;
    } catch (e) {
      debugPrint('MusicService: Critical Error initializing player: $e');
    }

    return null;
  }

  @override
  void onClose() {
    _player?.dispose();
    super.onClose();
  }
}
