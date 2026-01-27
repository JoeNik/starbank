import 'dart:async';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/music/music_track.dart';
import '../models/music/playlist.dart';
import '../services/tunehub_service.dart';
import '../services/storage_service.dart';

class MusicPlayerController extends GetxController {
  final TuneHubService _tuneHubService = Get.find<TuneHubService>();
  final StorageService _storage = Get.find<StorageService>();
  final AudioPlayer audioPlayer = AudioPlayer();

  final RxList<MusicTrack> playlist = <MusicTrack>[].obs;
  final RxList<MusicTrack> favorites = <MusicTrack>[].obs;
  final RxInt currentIndex = 0.obs;
  final RxBool isPlaying = false.obs;

  // Progress
  final Rx<Duration> position = Duration.zero.obs;
  final Rx<Duration> duration = Duration.zero.obs;
  final Rx<Duration> buffered = Duration.zero.obs;

  // Timer
  Timer? _sleepTimer;
  final RxInt sleepTimerMinutes = 0.obs; // 0 = off

  @override
  void onInit() {
    super.onInit();
    _loadFavorites();
    _initAudioPlayer();
  }

  void _loadFavorites() {
    // Load ID 'favorites' from playlistBox
    final favParams = _storage.playlistBox.get('favorites');
    if (favParams != null) {
      favorites.assignAll(favParams.tracks);
    }
  }

  void toggleFavorite(MusicTrack track) {
    if (isFavorite(track)) {
      favorites.removeWhere((element) => element.id == track.id);
    } else {
      favorites.add(track);
    }
    _saveFavorites();
  }

  bool isFavorite(MusicTrack track) {
    return favorites.any((element) => element.id == track.id);
  }

  void _saveFavorites() {
    final pl = Playlist(
      id: 'favorites',
      name: '我的收藏',
      tracks: favorites.toList(),
      createdAt: DateTime.now(),
    );
    _storage.playlistBox.put('favorites', pl);
  }

  void playFavorites() {
    if (favorites.isEmpty) {
      Get.snackbar('提示', '收藏夹是空的哦');
      return;
    }
    playlist.assignAll(favorites);
    playTrack(favorites.first);
  }

  void _initAudioPlayer() {
    audioPlayer.playerStateStream.listen((state) {
      isPlaying.value = state.playing;
      if (state.processingState == ProcessingState.completed) {
        playNext();
      }
    });

    audioPlayer.positionStream.listen((p) => position.value = p);
    audioPlayer.durationStream
        .listen((d) => duration.value = d ?? Duration.zero);
    audioPlayer.bufferedPositionStream.listen((b) => buffered.value = b);
  }

  Future<void> playTrack(MusicTrack track) async {
    // 1. Get Play URL if needed
    String? url = track.url;
    if (url == null || url.isEmpty) {
      // Fetch from Service
      // url = await _tuneHubService.getPlayUrl(track.id, platform: track.platform);
      // For demo, assume we might have it or fetching logic needs to be added to service
      // Temporary: hardcode or fail
      // url = 'https://music.163.com/song/media/outer/url?id=${track.id}.mp3'; // Netease fallback
    }

    // Netease fallback construct (common trick)
    if ((url == null || url.isEmpty) && track.platform == 'netease') {
      url = 'https://music.163.com/song/media/outer/url?id=${track.id}.mp3';
    }

    if (url == null) {
      Get.snackbar('错误', '无法获取播放地址');
      return;
    }

    try {
      // Define Metadata for Lock Screen / Notification
      final mediaItem = MediaItem(
        id: track.id,
        album: track.album ?? 'Unknown Album',
        title: track.title,
        artist: track.artist,
        artUri: track.coverUrl != null ? Uri.parse(track.coverUrl!) : null,
      );

      await audioPlayer.setAudioSource(AudioSource.uri(
        Uri.parse(url),
        tag: mediaItem,
      ));

      // Update Playlist State (if not already there, add it or play from list)
      if (!playlist.contains(track)) {
        playlist.add(track);
        currentIndex.value = playlist.length - 1;
      } else {
        currentIndex.value = playlist.indexOf(track);
      }

      await audioPlayer.play();
    } catch (e) {
      Get.snackbar('播放失败', e.toString());
    }
  }

  void playNext() {
    if (playlist.isEmpty) return;
    if (currentIndex.value < playlist.length - 1) {
      playTrack(playlist[currentIndex.value + 1]);
    } else {
      // Loop or stop
      // For now, loop back to start
      playTrack(playlist[0]);
    }
  }

  void playPrevious() {
    if (playlist.isEmpty) return;
    if (currentIndex.value > 0) {
      playTrack(playlist[currentIndex.value - 1]);
    } else {
      playTrack(playlist.last);
    }
  }

  void togglePlay() {
    if (isPlaying.value) {
      audioPlayer.pause();
    } else {
      audioPlayer.play();
    }
  }

  void seek(Duration pos) {
    audioPlayer.seek(pos);
  }

  // Timer Logic
  void setSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    sleepTimerMinutes.value = minutes;
    if (minutes > 0) {
      _sleepTimer = Timer(Duration(minutes: minutes), () {
        audioPlayer.pause();
        sleepTimerMinutes.value = 0;
        Get.snackbar('定时关闭', '音乐已停止');
      });
    }
  }

  @override
  void onClose() {
    audioPlayer.dispose();
    _sleepTimer?.cancel();
    super.onClose();
  }
}
