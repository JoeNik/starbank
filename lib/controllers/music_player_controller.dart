import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
// import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_service/audio_service.dart';
import '../models/music/music_track.dart';
import '../models/music/playlist.dart';
import '../services/tunehub_service.dart';
import '../services/storage_service.dart';

import '../services/music_service.dart';
import '../services/music_cache_service.dart';

class MusicPlayerController extends GetxController {
  final TuneHubService _tuneHubService = Get.find<TuneHubService>();
  final StorageService _storage = Get.find<StorageService>();
  final MusicService _musicService = Get.find<MusicService>();
  late final MusicCacheService _cacheService;

  // Use the singleton player from MusicService
  AudioPlayer? get audioPlayer => _musicService.player;

  final RxList<MusicTrack> playlist = <MusicTrack>[].obs;
  final RxList<MusicTrack> favorites = <MusicTrack>[].obs;
  final RxInt currentIndex = 0.obs;
  final RxBool isPlaying = false.obs;
  // isInitialized effectively reflects if the Service has a player, which is always true now
  final RxBool isInitialized = true.obs;
  bool _isPlayerSetup = false;

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
    _cacheService = Get.find<MusicCacheService>();
    _loadFavorites();

    // 异步初始化播放器监听，防止因 Service 未就绪导致的阻塞或 Crash
    _initControllerAsync();
  }

  void _initControllerAsync() async {
    // 尝试等待 Service 初始化
    int retries = 0;
    while (audioPlayer == null && retries < 5) {
      await Future.delayed(const Duration(milliseconds: 500));
      retries++;
    }

    if (audioPlayer != null) {
      _setupPlayerListeners();
    } else {
      // 如果超时，尝试调用 ensurePlayer 强行拉起
      _ensurePlayer();
    }
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

  // Ensure Player is Initialized & Listeners Attached
  Future<AudioPlayer?> _ensurePlayer() async {
    final p = await _musicService.getOrInitPlayer();
    if (p != null && !_isPlayerSetup) {
      _setupPlayerListeners();
      _isPlayerSetup = true;
    }
    return p;
  }

  void _setupPlayerListeners() {
    if (audioPlayer == null) return;

    // We bind Listeners to the Singleton Player

    // Bind AudioHandler callbacks for Lock Screen / Notification controls
    try {
      if (_musicService.audioHandler != null) {
        _musicService.audioHandler!.onSkipToNext = () {
          debugPrint('Notification: Skip to Next');
          playNext();
        };
        _musicService.audioHandler!.onSkipToPrevious = () {
          debugPrint('Notification: Skip to Previous');
          playPrevious();
        };
      }
    } catch (e) {
      debugPrint('Error binding AudioHandler callbacks: $e');
    }

    audioPlayer!.playerStateStream.listen((state) {
      isPlaying.value = state.playing;
      if (state.processingState == ProcessingState.completed) {
        playNext();
      }
    });

    audioPlayer!.positionStream.listen((p) {
      position.value = p;
      if (lyrics.isNotEmpty) {
        final index = lyrics.lastIndexWhere((l) => l.startTime <= p);
        if (index != -1 && index != currentLyricIndex.value) {
          currentLyricIndex.value = index;
        }
      }
    });

    audioPlayer!.durationStream
        .listen((d) => duration.value = d ?? Duration.zero);
    audioPlayer!.bufferedPositionStream.listen((b) => buffered.value = b);
  }

  Future<void> playTrack(MusicTrack track) async {
    // 强制重置当前尝试播放的 URL，确保逻辑新鲜
    String? currentUrl = track.url;

    debugPrint(
        'Attempting to play: ${track.title} (${track.platform}) - ${track.id}');

    // 1. 优先检查缓存
    if (_cacheService.isInitialized && _cacheService.cacheEnabled.value) {
      debugPrint(
          '🔍 [MusicPlayerController] 正在检查缓存: Platform=${track.platform}, ID=${track.id}');
      final cachedPath = await _cacheService.getCachedFilePath(track);
      if (cachedPath != null) {
        debugPrint('✅ [MusicPlayerController] 缓存命中! 路径: $cachedPath');
        await _playFromCache(track, cachedPath);
        return;
      } else {
        debugPrint('⚠️ [MusicPlayerController] 缓存未命中');
      }
    } else {
      debugPrint('ℹ️ [MusicPlayerController] 缓存服务未启用或未初始化');
    }

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

    try {
      // Lazy Init & Ensure Singleton Check
      final player = await _ensurePlayer();
      if (player == null) {
        final errorMsg = _musicService.initErrorMessage.value;
        Get.snackbar('初始化失败', '音频服务无法启动: $errorMsg',
            backgroundColor: Colors.redAccent,
            colorText: Colors.white,
            duration: const Duration(seconds: 5));
        return;
      }

      await player.stop();

      // Update MediaItem for Notification & Background Service
      final mediaItem = MediaItem(
        id: track.id,
        title: track.title,
        artist: track.artist ?? '',
        album: track.album ?? '',
        artUri: track.coverUrl != null && track.coverUrl!.isNotEmpty
            ? Uri.parse(track.coverUrl!)
            : null,
      );
      // Safe call here
      _musicService.audioHandler?.updateMediaItem(mediaItem);

      // 准备 Headers
      final Map<String, String> headers = _getHeaders(track);

      try {
        await player.setAudioSource(AudioSource.uri(
          Uri.parse(playUrl),
          headers: headers,
          tag: mediaItem,
        ));
      } catch (e) {
        // 容错回退
        debugPrint('Protocol error, retrying with raw URL: $e');
        await player.setAudioSource(AudioSource.uri(
          Uri.parse(currentUrl),
          headers: headers,
          // tag: mediaItem,
        ));
      }

      final index = playlist
          .indexWhere((t) => t.id == track.id && t.platform == track.platform);
      if (index == -1) {
        playlist.add(track);
        currentIndex.value = playlist.length - 1;
      } else {
        currentIndex.value = index;
        playlist[index] = track;
      }

      await player.play();

      // 4. 自动缓存歌曲
      if (_cacheService.isInitialized && _cacheService.cacheEnabled.value) {
        debugPrint('💾 [MusicPlayerController] 准备自动缓存: ${track.title}');
        _cacheService.cacheSong(track, playUrl).then((success) {
          if (success) {
            debugPrint('✅ [MusicPlayerController] 自动缓存成功');
          } else {
            debugPrint('❌ [MusicPlayerController] 自动缓存失败');
          }
        }).catchError((e) {
          debugPrint('❌ [MusicPlayerController] 自动缓存异常: $e');
        });
      }
    } on PlayerException catch (e) {
      debugPrint("Error code: ${e.code}");
      debugPrint("Error message: ${e.message}");
      Get.snackbar('播放失败', '音频错误: ${e.message}',
          backgroundColor: Colors.redAccent, colorText: Colors.white);
    } on PlayerInterruptedException catch (e) {
      debugPrint("Connection aborted: ${e.message}");
    } catch (e, stackTrace) {
      debugPrint('Audio play failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      Get.snackbar('播放失败', '加载错误: ${e.toString()}',
          backgroundColor: Colors.redAccent,
          colorText: Colors.white,
          duration: const Duration(seconds: 5));
    }
  }

  // Play Mode
  final Rx<PlayMode> playMode = PlayMode.sequence.obs;

  void changePlayMode() {
    switch (playMode.value) {
      case PlayMode.sequence:
        playMode.value = PlayMode.shuffle;
        break;
      case PlayMode.shuffle:
        playMode.value = PlayMode.single;
        break;
      case PlayMode.single:
        playMode.value = PlayMode.sequence;
        break;
    }
  }

  void playNext() {
    if (playlist.isEmpty) return;

    // Handle Single Loop manually if triggered by completion
    // But usually playNext is called by user or auto-completion.
    // If auto-completion (checked in listener), we might want to respect single loop.
    // If user clicked 'Next', we usually skip to next track even in single loop mode.
    // We'll differentiate behavior based on invocation if needed, but for now simple logic:

    // If invoked by user (UI button), force next track logic (ignore single loop).
    // The auto-next logic in setupPlayerListeners calls this too.
    // We should probably check there.
    // Actually, standard behavior: User click next -> next track. Auto-finish -> re-play if single.

    int nextIndex = currentIndex.value;

    if (playMode.value == PlayMode.shuffle) {
      // Random index
      if (playlist.length > 1) {
        final random = DateTime.now().millisecondsSinceEpoch;
        // Simple random to avoid same track if possible
        int newIndex;
        do {
          newIndex = (newIndex = (random % playlist.length).toInt() %
              playlist.length); // simple pseudo
          // actually better use Random class
          // But to quick fix without import math, just linear scan or something?
          // Let's use:
          newIndex = (DateTime.now().microsecondsSinceEpoch % playlist.length);
        } while (newIndex == currentIndex.value && playlist.length > 1);
        nextIndex = newIndex;
      }
    } else {
      // Sequence
      if (currentIndex.value < playlist.length - 1) {
        nextIndex = currentIndex.value + 1;
      } else {
        // Loop back to start (Loop All implicitly for Sequence)
        nextIndex = 0;
      }
    }

    playTrack(playlist[nextIndex]);
  }

  void playPrevious() {
    if (playlist.isEmpty) return;

    int prevIndex = currentIndex.value;
    if (playMode.value == PlayMode.shuffle) {
      // Shuffle previous is also random usually, or history.
      // For simple implementation, random.
      prevIndex = (DateTime.now().microsecondsSinceEpoch % playlist.length);
    } else {
      if (currentIndex.value > 0) {
        prevIndex = currentIndex.value - 1;
      } else {
        prevIndex = playlist.length - 1;
      }
    }
    playTrack(playlist[prevIndex]);
  }

  void togglePlay() {
    if (audioPlayer != null && isPlaying.value) {
      audioPlayer!.pause();
    } else if (audioPlayer != null) {
      audioPlayer!.play();
    }
  }

  void seek(Duration pos) {
    audioPlayer?.seek(pos);
  }

  // Timer logic
  void setSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    sleepTimerMinutes.value = minutes;
    if (minutes > 0) {
      _sleepTimer = Timer(Duration(minutes: minutes), () {
        audioPlayer?.pause();
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
    // Cannot dispose global player from controller!
    // _musicService handles lifecycle if needed.
    _sleepTimer?.cancel();
    super.onClose();
  }

  /// 从缓存播放音乐
  Future<void> _playFromCache(MusicTrack track, String cachedFilePath) async {
    try {
      // Lazy Init & Ensure Singleton Check
      final player = await _ensurePlayer();
      if (player == null) {
        final errorMsg = _musicService.initErrorMessage.value;
        Get.snackbar('初始化失败', '音频服务无法启动: $errorMsg',
            backgroundColor: Colors.redAccent,
            colorText: Colors.white,
            duration: const Duration(seconds: 5));
        return;
      }

      await player.stop();

      // Update MediaItem for Notification & Background Service
      final mediaItem = MediaItem(
        id: track.id,
        title: track.title,
        artist: track.artist ?? '',
        album: track.album ?? '',
        artUri: track.coverUrl != null && track.coverUrl!.isNotEmpty
            ? Uri.parse(track.coverUrl!)
            : null,
      );
      _musicService.audioHandler?.updateMediaItem(mediaItem);

      // 从缓存文件播放
      debugPrint('🎵 加载本地缓存文件: $cachedFilePath');
      await player.setAudioSource(AudioSource.file(
        cachedFilePath,
        tag: mediaItem,
      ));

      final index = playlist
          .indexWhere((t) => t.id == track.id && t.platform == track.platform);
      if (index == -1) {
        playlist.add(track);
        currentIndex.value = playlist.length - 1;
      } else {
        currentIndex.value = index;
        playlist[index] = track;
      }

      await player.play();
    } on PlayerException catch (e) {
      debugPrint("Error code: ${e.code}");
      debugPrint("Error message: ${e.message}");
      Get.snackbar('播放失败', '音频错误: ${e.message}',
          backgroundColor: Colors.redAccent, colorText: Colors.white);
    } catch (e, stackTrace) {
      debugPrint('Cache play failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      Get.snackbar('播放失败', '缓存播放错误: ${e.toString()}',
          backgroundColor: Colors.redAccent,
          colorText: Colors.white,
          duration: const Duration(seconds: 5));
    }
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

enum PlayMode {
  sequence,
  shuffle,
  single,
}
