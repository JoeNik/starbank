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
  final RxList<MusicTrack> history = <MusicTrack>[].obs;
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
    _loadHistory();

    // 异步初始化播放器监听，防止因 Service 未就绪导致的阻塞或 Crash
    _initControllerAsync();
  }

  void _initControllerAsync() async {
    // 1. 等待 AudioPlayer (可能来自 Handler 或 Fallback)
    int retries = 0;
    while (audioPlayer == null && retries < 10) {
      await Future.delayed(const Duration(milliseconds: 500));
      retries++;
    }

    if (audioPlayer != null) {
      _setupPlayerListeners();
    } else {
      _ensurePlayer();
    }

    // 2. 专门等待 AudioHandler 以绑定通知栏回调 (因为 fallback player 时 Handler 可能还没好)
    int handlerRetries = 0;
    while (_musicService.audioHandler == null && handlerRetries < 20) {
      await Future.delayed(const Duration(milliseconds: 500));
      handlerRetries++;
    }

    if (_musicService.audioHandler != null) {
      _bindHandlerCallbacks();
    } else {
      debugPrint('⚠️ [MusicPlayerController] AudioHandler 初始化超时，通知栏控制可能不可用');
    }
  }

  void _bindHandlerCallbacks() {
    try {
      if (_musicService.audioHandler != null) {
        _musicService.audioHandler!.onSkipToNext = () {
          debugPrint('🔔 [Notification] 下一首');
          playNext();
        };
        _musicService.audioHandler!.onSkipToPrevious = () {
          debugPrint('🔔 [Notification] 上一首');
          playPrevious();
        };
        // 绑定暂停/播放/停止，虽然 JustAudio 自动处理了，但有时需要显式覆盖?
        // 不，MusicHandler 转发了 play/pause 到 player，player 状态变化会自动更新 UI。
        // 所以只需要处理上一首/下一首这两个逻辑操作。
        debugPrint('✅ [MusicPlayerController] 通知栏回调绑定成功');
      }
    } catch (e) {
      debugPrint('❌ [MusicPlayerController] 绑定通知栏回调失败: $e');
    }
  }

  void _loadFavorites() {
    // Load ID 'favorites' from playlistBox
    final favParams = _storage.playlistBox.get('favorites');
    if (favParams != null) {
      favorites.assignAll(favParams.tracks);
    }
  }

  void _loadHistory() {
    final historyData = _storage.playlistBox.get('history');
    if (historyData != null) {
      history.assignAll(historyData.tracks);
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

  void _saveHistory() {
    final pl = Playlist(
      id: 'history',
      name: '播放记录',
      tracks: history.toList(),
      createdAt: DateTime.now(),
    );
    _storage.playlistBox.put('history', pl);
  }

  void addToHistory(MusicTrack track) {
    // 去重并置顶（最近播放）
    history
        .removeWhere((t) => t.id == track.id && t.platform == track.platform);
    history.insert(0, track);
    // 限制记录数量
    if (history.length > 50) {
      history.removeLast();
    }
    _saveHistory();
  }

  void playFavorites() {
    if (favorites.isEmpty) {
      Get.snackbar('提示', '收藏夹是空的哦');
      return;
    }
    playWithList(favorites, favorites.first);
  }

  /// 带着播放列表一起播放，常用于从搜索列表或收藏列表中点选一首歌
  void playWithList(List<MusicTrack> list, MusicTrack track) {
    if (list.isEmpty) return;
    playlist.assignAll(list);
    playTrack(track);
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

    // AudioHandler callbacks are now bound in _bindHandlerCallbacks()

    // 局部变量防止重复触发
    bool isManuallySkipping = false;

    audioPlayer!.playerStateStream.listen((state) {
      isPlaying.value = state.playing;
      if (state.processingState == ProcessingState.completed) {
        // 播放完成后添加记录
        if (playlist.isNotEmpty && currentIndex.value < playlist.length) {
          addToHistory(playlist[currentIndex.value]);
        }
        playNext();
        isManuallySkipping = false;
      }
      // 当重新开始缓冲或空闲时，重置标志位
      if (state.processingState == ProcessingState.buffering ||
          state.processingState == ProcessingState.idle) {
        isManuallySkipping = false;
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

      // [BugFix] 手动检测结束：如果剩余时间 < 500ms 且正在播放，主动切歌
      // 解决部分音频文件在最后几帧卡住不触发 completed 的问题
      final d = duration.value;
      if (!isManuallySkipping &&
          d.inSeconds > 5 &&
          audioPlayer!.playing &&
          (d - p).inMilliseconds < 500 &&
          audioPlayer!.processingState != ProcessingState.completed) {
        isManuallySkipping = true;
        debugPrint('⚡ [MusicPlayerController] 接近尾声，主动切下一首');
        // 记录历史
        if (playlist.isNotEmpty && currentIndex.value < playlist.length) {
          addToHistory(playlist[currentIndex.value]);
        }
        playNext();
      }
    });

    audioPlayer!.durationStream
        .listen((d) => duration.value = d ?? Duration.zero);
    audioPlayer!.bufferedPositionStream.listen((b) => buffered.value = b);
  }

  Future<void> playTrack(MusicTrack track, {int? targetIndex}) async {
    // 强制重置当前尝试播放的 URL，确保逻辑新鲜
    String? currentUrl = track.url;

    debugPrint(
        'Attempting to play: ${track.title} (${track.platform}) - ${track.id}');

    // 1. 优先检查缓存
    if (_cacheService.isInitialized && _cacheService.cacheEnabled.value) {
      debugPrint(
          '🔍 [MusicPlayerController] 正在检查缓存: Platform=${track.platform}, ID=${track.id}');
      try {
        final cachedPath = await _cacheService.getCachedFilePath(track);
        if (cachedPath != null) {
          debugPrint('✅ [MusicPlayerController] 缓存命中! 尝试播放: $cachedPath');
          final success = await _playFromCache(track, cachedPath);
          if (success) {
            debugPrint('✅ [MusicPlayerController] 缓存播放成功');
            return;
          } else {
            debugPrint('⚠️ [MusicPlayerController] 缓存播放失败，自动降级为在线播放');
          }
        } else {
          debugPrint('⚠️ [MusicPlayerController] 缓存未命中');
        }
      } catch (e) {
        debugPrint('❌ [MusicPlayerController] 缓存检查异常: $e');
        // 异常也继续在线播放
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

      // 更新播放列表索引
      // 如果调用方已经指定了目标索引（如 playNext/playPrevious），直接使用
      if (targetIndex != null &&
          targetIndex >= 0 &&
          targetIndex < playlist.length) {
        currentIndex.value = targetIndex;
        playlist[targetIndex] = track;
        debugPrint('✅ [PlayTrack] 使用指定索引: $targetIndex, 歌曲: ${track.title}');
      } else {
        final index = playlist.indexWhere(
            (t) => t.id == track.id && t.platform == track.platform);
        if (index == -1) {
          playlist.add(track);
          currentIndex.value = playlist.length - 1;
          debugPrint('✅ [PlayTrack] 添加新歌曲，索引: ${currentIndex.value}');
        } else {
          currentIndex.value = index;
          playlist[index] = track;
          debugPrint('✅ [PlayTrack] 找到已有歌曲，索引: $index');
        }
      }

      await player.play();
      // 播放成功立即记入历史
      addToHistory(track);

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

    debugPrint('🎵 [PlayNext] 当前索引: ${currentIndex.value}, 下一首索引: $nextIndex');
    playTrack(playlist[nextIndex], targetIndex: nextIndex);
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
    debugPrint(
        '🎵 [PlayPrevious] 当前索引: ${currentIndex.value}, 上一首索引: $prevIndex');
    playTrack(playlist[prevIndex], targetIndex: prevIndex);
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
  Future<bool> _playFromCache(MusicTrack track, String cachedFilePath) async {
    try {
      // Lazy Init & Ensure Singleton Check
      final player = await _ensurePlayer();
      if (player == null) {
        debugPrint('❌ [MusicPlayerController] 音频服务初始化失败');
        return false;
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
      // 播放成功立即记入历史
      addToHistory(track);
      return true;
    } catch (e) {
      debugPrint('❌ [MusicPlayerController] 缓存播放异常: $e');
      // debugPrintStack(stackTrace: stackTrace); // 减少日志刷屏，仅调试用
      // 不要弹窗，返回 false 让上层降级
      return false;
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
