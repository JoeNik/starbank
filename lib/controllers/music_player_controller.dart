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

    // 用于处理过渡状态的变量
    bool _isTransitioning = false;

    // 1. 监听播放状态变化
    audioPlayer!.playerStateStream.listen((state) {
      isPlaying.value = state.playing;

      // 处理播放完成逻辑
      if (state.processingState == ProcessingState.completed &&
          !_isTransitioning) {
        _isTransitioning = true;
        debugPrint('🎵 [PlayerState] 播放完成，处理后续动作 (模式: ${playMode.value})');

        // 记录历史
        if (playlist.isNotEmpty && currentIndex.value < playlist.length) {
          addToHistory(playlist[currentIndex.value]);
        }

        // 处理单曲循环
        if (playMode.value == PlayMode.single) {
          debugPrint('🎵 [PlayerState] 单曲循环模式，重新播放当前歌曲');
          audioPlayer!.seek(Duration.zero);
          audioPlayer!.play();
          _isTransitioning = false;
        } else {
          // 延迟执行切换，给 UI 和状态一点缓冲时间
          Future.delayed(const Duration(milliseconds: 300), () {
            playNext(isAuto: true);
            _isTransitioning = false;
          });
        }
      }

      // 当播放器准备好并开始播放时，重置过渡状态
      if (state.processingState == ProcessingState.ready && state.playing) {
        _isTransitioning = false;
      }
    });

    // 2. 监听进度（仅用于同步歌词）
    audioPlayer!.positionStream.listen((p) {
      position.value = p;

      // 更新歌词
      if (lyrics.isNotEmpty) {
        final index = lyrics.lastIndexWhere((l) => l.startTime <= p);
        if (index != -1 && index != currentLyricIndex.value) {
          currentLyricIndex.value = index;
        }
      }
    });

    // 3. 监听时长变化
    audioPlayer!.durationStream.listen((d) {
      if (d != null) {
        duration.value = d;
        debugPrint('🎵 [Duration] 歌曲时长: ${d.inSeconds}秒');
      }
    });

    // 4. 监听缓冲位置
    audioPlayer!.bufferedPositionStream.listen((b) {
      buffered.value = b;
    });

    // 5. 监听处理状态（用于调试）
    audioPlayer!.processingStateStream.listen((state) {
      debugPrint('🎵 [ProcessingState] $state');

      // 当状态变为 ready 时，确保时长已正确设置
      if (state == ProcessingState.ready) {
        final d = audioPlayer!.duration;
        if (d != null && d != duration.value) {
          duration.value = d;
          debugPrint('🎵 [Duration] 更新时长: ${d.inSeconds}秒');
        }
      }
    });
  }

  Future<void> playTrack(MusicTrack track, {int? targetIndex}) async {
    debugPrint('🎵 [PlayTrack] 准备播放: ${track.title} (${track.platform})');

    // 1. 预处理：获取播放链接
    String? playUrl;

    // 优先尝试缓存
    if (_cacheService.isInitialized && _cacheService.cacheEnabled.value) {
      final cachedPath = await _cacheService.getCachedFilePath(track);
      if (cachedPath != null) {
        debugPrint('✅ [PlayTrack] 命缓存: $cachedPath');
        playUrl = 'file://$cachedPath';
      }
    }

    // 若无缓存或缓存加载失败，解析在线链接
    if (playUrl == null) {
      try {
        final res = await _tuneHubService.parseTrack(track.platform, track.id);
        if (res.containsKey('url') && res['url'] != null) {
          playUrl = res['url'];
          track.url = playUrl; // 同步给 track 对象

          // 更新歌曲附加信息
          if (res['cover'] != null) track.coverUrl = res['cover'];
          if (res['lyrics'] != null) track.lyricContent = res['lyrics'];
          _parseLyrics(track.lyricContent);
        }
      } catch (e) {
        debugPrint('❌ [PlayTrack] 链接解析异常: $e');
      }
    }

    if (playUrl == null || playUrl.isEmpty) {
      Get.snackbar('播放提示', '无法获取该歌曲的播放地址，自动尝试下一首',
          backgroundColor: Colors.orangeAccent, colorText: Colors.white);
      // 如果是自动播放触发的失败，尝试跳到下一首
      Future.delayed(const Duration(seconds: 1), () => playNext(isAuto: true));
      return;
    }

    // 针对性协议处理
    if (track.platform == 'netease' && playUrl.startsWith('http://')) {
      playUrl = playUrl.replaceFirst('http://', 'https://');
    }

    try {
      final player = await _ensurePlayer();
      if (player == null) return;

      // 重要：在设置新源之前停止当前播放
      await player.stop();

      // 更新系统媒体信息
      final mediaItem = MediaItem(
        id: track.id,
        title: track.title,
        artist: track.artist,
        album: track.album ?? '',
        artUri: track.coverUrl != null && track.coverUrl!.isNotEmpty
            ? Uri.parse(track.coverUrl!)
            : null,
      );
      _musicService.audioHandler?.updateMediaItem(mediaItem);

      // 设置音频源
      final Map<String, String> headers = _getHeaders(track);
      await player.setAudioSource(AudioSource.uri(
        Uri.parse(playUrl),
        headers: headers,
        tag: mediaItem,
      ));

      // 更新控制器索引
      if (targetIndex != null &&
          targetIndex >= 0 &&
          targetIndex < playlist.length) {
        currentIndex.value = targetIndex;
      } else {
        final index = playlist.indexWhere(
            (t) => t.id == track.id && t.platform == track.platform);
        if (index == -1) {
          playlist.add(track);
          currentIndex.value = playlist.length - 1;
        } else {
          currentIndex.value = index;
        }
      }

      // 开始播放
      await player.play();
      addToHistory(track);

      // 异步触发缓存
      if (playUrl.startsWith('http')) {
        _cacheService.cacheSong(track, playUrl).catchError((e) {
          debugPrint('Cache error: $e');
          return false;
        });
      }
    } catch (e) {
      debugPrint('❌ [PlayTrack] 播放过程中出错: $e');
      Get.snackbar('播放失败', '无法播放此歌曲: $e');
      // 出错也尝试下一首
      Future.delayed(const Duration(seconds: 2), () => playNext(isAuto: true));
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

  void playNext({bool isAuto = false}) {
    if (playlist.isEmpty) return;

    // 如果处于单曲循环模式且是自动播放（非手动点下一首），则继续播放当前
    if (isAuto && playMode.value == PlayMode.single) {
      audioPlayer?.seek(Duration.zero);
      audioPlayer?.play();
      return;
    }

    int nextIndex = 0;
    if (playMode.value == PlayMode.shuffle) {
      if (playlist.length > 1) {
        nextIndex = (DateTime.now().microsecondsSinceEpoch % playlist.length);
        // 避免还是同一首
        if (nextIndex == currentIndex.value) {
          nextIndex = (nextIndex + 1) % playlist.length;
        }
      }
    } else {
      // 顺序播放
      if (currentIndex.value < playlist.length - 1) {
        nextIndex = currentIndex.value + 1;
      } else {
        nextIndex = 0; // 列表循环
      }
    }

    debugPrint('🎵 [Sequence] 计算下一首: $nextIndex (当前: ${currentIndex.value})');
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

  Map<String, String> _getHeaders(MusicTrack track) {
    // 默认 Headers (模仿 PC Chrome)
    final Map<String, String> headers = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Referer': 'https://www.google.com/',
    };

    if (track.platform == 'netease') {
      headers['Referer'] = 'https://music.163.com/';
    } else if (track.platform == 'kuwo') {
      headers['Referer'] = 'http://www.kuwo.cn/';
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
