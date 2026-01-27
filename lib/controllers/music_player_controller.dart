import 'dart:async';
import 'package:flutter/material.dart';
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
  late AudioPlayer audioPlayer;

  final RxList<MusicTrack> playlist = <MusicTrack>[].obs;
  final RxList<MusicTrack> favorites = <MusicTrack>[].obs;
  final RxInt currentIndex = 0.obs;
  final RxBool isPlaying = false.obs;
  final RxBool isInitialized = false.obs;

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
    try {
      audioPlayer = AudioPlayer();
      isInitialized.value = true;

      audioPlayer.playerStateStream.listen((state) {
        isPlaying.value = state.playing;
        if (state.processingState == ProcessingState.completed) {
          playNext();
        }
      });

      audioPlayer.positionStream.listen((p) {
        position.value = p;
        // Update lyric index
        if (lyrics.isNotEmpty) {
          // Find the last lyric that started before or at current position
          final index = lyrics.lastIndexWhere((l) => l.startTime <= p);
          if (index != -1 && index != currentLyricIndex.value) {
            currentLyricIndex.value = index;
          }
        }
      });
      audioPlayer.durationStream
          .listen((d) => duration.value = d ?? Duration.zero);
      audioPlayer.bufferedPositionStream.listen((b) => buffered.value = b);
    } catch (e) {
      debugPrint('AudioPlayer initialization failed: $e');
      isInitialized.value = false;
    }
  }

  Future<void> playTrack(MusicTrack track) async {
    // 强制重置当前尝试播放的 URL，确保逻辑新鲜
    String? currentUrl = track.url;

    debugPrint(
        'Attempting to play: ${track.title} (${track.platform}) - ${track.id}');

    // 始终尝试刷新 URL，因为它通常具有时效性
    try {
      final res = await _tuneHubService.parseTrack(track.platform, track.id);
      if (res.containsKey('url') && res['url'] != null) {
        currentUrl = res['url'];
        track.url = currentUrl;

        // 校准字段：使用 cover 而不是 pic
        if (res.containsKey('cover') && res['cover'] != null) {
          track.coverUrl = res['cover'];
        }

        // 校准字段：使用 lyrics 而不是 lyric
        if (res.containsKey('lyrics') && res['lyrics'] != null) {
          track.lyricContent = res['lyrics'];
        }

        // Parse lyrics immediately
        _parseLyrics(track.lyricContent);

        // 同步来自 info 的更准确信息
        if (res.containsKey('info') && res['info'] is Map) {
          final infoData = res['info'] as Map;
          track.title = infoData['name'] ?? track.title;
          track.artist = infoData['artist'] ?? track.artist;
          track.album = infoData['album'] ?? track.album;
        }

        debugPrint(
            'Parse Success: URL=$currentUrl, Cover=${track.coverUrl != null}, Lyric=${track.lyricContent != null}');
      } else {
        debugPrint('Parse Warning: No URL in response. Raw res: $res');
      }
    } catch (e) {
      debugPrint('Fetch URL error: $e');
    }

    if (currentUrl == null || currentUrl.isEmpty) {
      Get.snackbar('播放提示', '抱歉，暂时无法获取该平台的播放地址',
          backgroundColor: Colors.orangeAccent, colorText: Colors.white);
      return;
    }

    // 针对性协议处理：网易云倾向 HTTPS，酷我倾向 HTTP
    String playUrl = currentUrl;
    if (track.platform == 'netease' && playUrl.startsWith('http://')) {
      playUrl = playUrl.replaceFirst('http://', 'https://');
    }

    // 针对性防缓存处理：如果链接包含 sign, token 或来自酷我，不要添加任何额外参数，防止签名失效
    final bool isSigned = playUrl.contains('sign') ||
        playUrl.contains('token') ||
        playUrl.contains('\$');
    if (!isSigned) {
      final cacheBuster = 't=${DateTime.now().millisecondsSinceEpoch}';
      playUrl = playUrl.contains('?')
          ? '$playUrl&$cacheBuster'
          : '$playUrl?$cacheBuster';
    }

    try {
      await audioPlayer.stop();

      final mediaItem = MediaItem(
        id: track.id,
        album: track.album ?? 'Unknown Album',
        title: track.title,
        artist: track.artist,
        artUri: track.coverUrl != null && track.coverUrl!.startsWith('http')
            ? Uri.parse(track.coverUrl!)
            : null,
      );

      // 准备 Headers
      final Map<String, String> headers = _getHeaders(track);

      try {
        await audioPlayer.setAudioSource(AudioSource.uri(
          Uri.parse(playUrl),
          headers: headers,
          tag: mediaItem,
        ));
      } catch (e) {
        // 容错回退：如果是 HTTPS 失败且平台是网易云，尝试退回原始 HTTP
        debugPrint('Protocol error, retrying with raw URL: $e');
        await audioPlayer.setAudioSource(AudioSource.uri(
          Uri.parse(currentUrl),
          headers: headers,
          tag: mediaItem,
        ));
      }

      final index = playlist
          .indexWhere((t) => t.id == track.id && t.platform == track.platform);
      if (index == -1) {
        playlist.add(track);
        currentIndex.value = playlist.length - 1;
      } else {
        currentIndex.value = index;
        // 更新列表中的元数据（防止旧的封面/链接）
        playlist[index] = track;
      }

      await audioPlayer.play();
    } catch (e) {
      debugPrint('Audio play failed: $e');
      Get.snackbar('播放失败', '音频加载超时或解析错误');
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

  // Timer logic
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

  // --- Lyrics Logic ---

  final RxList<LyricLine> lyrics = <LyricLine>[].obs;
  final RxInt currentLyricIndex = 0.obs;

  void _parseLyrics(String? content) {
    lyrics.clear();
    currentLyricIndex.value = 0;
    if (content == null || content.isEmpty) return;

    // Regex to match [mm:ss.SS] or [mm:ss.SSS]
    final regExp = RegExp(r'^\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)');
    final lines = content.split('\n');

    for (final line in lines) {
      final match = regExp.firstMatch(line);
      if (match != null) {
        final min = int.parse(match.group(1)!);
        final sec = int.parse(match.group(2)!);
        final msStr = match.group(3)!;
        // Normalize milliseconds: .1 -> 100, .12 -> 120, .123 -> 123
        final ms = int.parse(msStr.padRight(3, '0'));

        final time = Duration(minutes: min, seconds: sec, milliseconds: ms);
        final text = match.group(4)!.trim();
        // Skip empty lines if desired, or keep them for spacing
        // Keeping them is better for fidelity
        lyrics.add(LyricLine(time, text));
      }
    }
  }

  @override
  void onClose() {
    if (isInitialized.value) {
      audioPlayer.dispose();
    }
    _sleepTimer?.cancel();
    super.onClose();
  }

  Map<String, String> _getHeaders(MusicTrack track) {
    // 默认 Headers (模仿 PC Chrome)
    final Map<String, String> headers = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Referer': 'https://www.google.com/',
    };

    if (track.platform == 'netease') {
      headers['Referer'] = 'https://music.163.com/';
      // 网易云部分链接可能需要 Cookie，但通常 Referer 足够
    } else if (track.platform == 'kuwo') {
      headers['Referer'] = 'http://www.kuwo.cn/';
      // 酷有时候对 HTTP 更友好，或者特定的 UA
      headers['User-Agent'] =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/115.0';
    } else if (track.platform == 'qq') {
      headers['Referer'] = 'https://y.qq.com/';
    }

    return headers;
  }
}

class LyricLine {
  final Duration startTime;
  final String content;

  LyricLine(this.startTime, this.content);
}
