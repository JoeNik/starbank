import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/foundation.dart';

class MusicService extends GetxService {
  AudioPlayer? _player;
  AudioPlayer? get player => _player;

  @override
  void onInit() {
    super.onInit();
    _initPlayer();
  }

  void _initPlayer() {
    try {
      debugPrint(
          'MusicService: Creating Standard AudioPlayer (No Background)...');
      _player = AudioPlayer();
    } catch (e) {
      debugPrint('MusicService: Error creating AudioPlayer: $e');
    }
  }

  // Simplified getter for compatibility
  Future<AudioPlayer?> getOrInitPlayer() async {
    if (_player != null) return _player;
    _initPlayer();
    return _player;
  }

  @override
  void onClose() {
    _player?.dispose();
    super.onClose();
  }
}
