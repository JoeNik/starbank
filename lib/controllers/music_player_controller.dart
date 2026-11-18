import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
// import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_service/audio_service.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import '../models/music/music_track.dart';
import '../models/music/playlist.dart';
import '../services/public_storage_service.dart';
import '../services/tunehub_service.dart';
import '../services/chksz_music_service.dart';
import '../services/music_source.dart';
import '../services/storage_service.dart';
import '../widgets/music_cover_image.dart';

import '../services/music_service.dart';
import '../services/music_cache_service.dart';

class MusicPlayerController extends GetxController {
  final TuneHubService _tuneHubService = Get.find<TuneHubService>();

  /// 注册中心为可选项:热重载或异常场景下缺失时回退 TuneHub,不让播放瘫痪
  MusicSourceRegistry? get _sourceRegistry =>
      Get.isRegistered<MusicSourceRegistry>()
          ? Get.find<MusicSourceRegistry>()
          : null;
  final StorageService _storage = Get.find<StorageService>();
  final MusicService _musicService = Get.find<MusicService>();
  late final MusicCacheService _cacheService;

  // Use the singleton player from MusicService
  AudioPlayer? get audioPlayer => _musicService.player;

  final RxList<MusicTrack> playlist = <MusicTrack>[].obs;
  final RxList<MusicTrack> favorites = <MusicTrack>[].obs;
  final RxList<MusicTrack> history = <MusicTrack>[].obs;

  /// 用户自定义收藏歌单列表（支持多个歌单分类收藏）
  final RxList<Playlist> customPlaylists = <Playlist>[].obs;
  final RxInt currentIndex = 0.obs;
  final RxBool isPlaying = false.obs;
  // isInitialized effectively reflects if the Service has a player, which is always true now
  final RxBool isInitialized = true.obs;
  bool _isPlayerSetup = false;

  // === 并发控制 ===
  // 当前播放任务ID,用于取消旧的播放请求
  int _currentPlayTaskId = 0;
  // 是否正在切歌过渡中,防止 stop() 触发的 completed 状态误触自动切歌
  bool _isTransitioning = false;
  // 安全超时定时器：防止 _isTransitioning 因异常流程永久卡住
  Timer? _transitionSafetyTimer;

  // Progress
  final Rx<Duration> position = Duration.zero.obs;
  final Rx<Duration> duration = Duration.zero.obs;
  final Rx<Duration> buffered = Duration.zero.obs;

  // Timer
  Timer? _sleepTimer;
  final RxInt sleepTimerMinutes = 0.obs; // 0 = off

  // 当前播放音质档位(如 exhigh / hires),空表示未知;UI 层负责转显示名
  final RxString currentAudioQuality = ''.obs;

  // === 歌曲下载(保存到公共下载目录) ===
  final PublicStorageService _publicStorage = PublicStorageService();
  final RxBool isDownloading = false.obs;
  static const String downloadSubDir = 'starBank/music';

  @override
  void onInit() {
    super.onInit();
    _cacheService = Get.find<MusicCacheService>();
    _loadFavorites();
    _loadHistory();
    _loadCustomPlaylists();
    _restoreQueue();
    _restorePlayMode();
    unawaited(_musicService.ensureNotificationPermission());

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

  /// 家庭同步写回歌单盒后刷新收藏、自定义歌单与播放历史。
  void reloadLibraryFromStorage() {
    favorites.clear();
    history.clear();
    customPlaylists.clear();
    _loadFavorites();
    _loadHistory();
    _loadCustomPlaylists();
  }

  // ==================== 多歌单收藏管理系统 ====================

  static const String _seededPlaylistsFlagKey = 'custom_playlists_seeded_v1';

  void _loadCustomPlaylists() {
    final loaded = <Playlist>[];
    for (final key in _storage.playlistBox.keys) {
      final k = key.toString();
      if (k == 'favorites' || k == 'history') continue;
      final pl = _storage.playlistBox.get(key);
      if (pl != null) {
        loaded.add(pl);
      }
    }
    if (loaded.isEmpty &&
        _storage.getValue(_seededPlaylistsFlagKey) != 'true') {
      final now = DateTime.now();
      final defaults = [
        Playlist(
          id: 'pl_bedtime',
          name: '🌙 睡前哄睡轻音乐',
          tracks: [],
          createdAt: now,
        ),
        Playlist(
          id: 'pl_sing',
          name: '🕺 快乐唱跳儿歌',
          tracks: [],
          createdAt: now.add(const Duration(milliseconds: 10)),
        ),
        Playlist(
          id: 'pl_story',
          name: '📖 故事与古诗磨耳朵',
          tracks: [],
          createdAt: now.add(const Duration(milliseconds: 20)),
        ),
      ];
      for (final pl in defaults) {
        _storage.playlistBox.put(pl.id, pl);
        loaded.add(pl);
      }
      _storage.saveValue(_seededPlaylistsFlagKey, 'true');
    }
    loaded.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    customPlaylists.assignAll(loaded);
  }

  /// 新建自定义歌单
  Playlist createCustomPlaylist(String name) {
    final trimmed = name.trim();
    final id = 'pl_${DateTime.now().millisecondsSinceEpoch}';
    final pl = Playlist(
      id: id,
      name: trimmed.isEmpty ? '新歌单 ${customPlaylists.length + 1}' : trimmed,
      tracks: [],
      createdAt: DateTime.now(),
    );
    _storage.playlistBox.put(pl.id, pl);
    customPlaylists.add(pl);
    customPlaylists.refresh();
    return pl;
  }

  /// 重命名自定义歌单
  void renameCustomPlaylist(String playlistId, String newName) {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    final idx = customPlaylists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;
    final pl = customPlaylists[idx];
    final updated = Playlist(
      id: pl.id,
      name: trimmed,
      coverUrl: pl.coverUrl,
      tracks: List<MusicTrack>.from(pl.tracks),
      createdAt: pl.createdAt,
    );
    _storage.playlistBox.put(updated.id, updated);
    customPlaylists[idx] = updated;
    customPlaylists.refresh();
  }

  /// 删除自定义歌单
  void deleteCustomPlaylist(String playlistId) {
    _storage.playlistBox.delete(playlistId);
    customPlaylists.removeWhere((p) => p.id == playlistId);
    customPlaylists.refresh();
  }

  /// 检查歌曲是否已在指定自定义歌单中
  bool isTrackInPlaylist(String playlistId, MusicTrack track) {
    final idx = customPlaylists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return false;
    return customPlaylists[idx]
        .tracks
        .any((t) => t.id == track.id && t.platform == track.platform);
  }

  /// 检查歌曲是否已被收藏在「我的收藏」或任意自定义歌单中
  int countPlaylistsContaining(MusicTrack track) {
    var count = isFavorite(track) ? 1 : 0;
    for (final pl in customPlaylists) {
      if (pl.tracks
          .any((t) => t.id == track.id && t.platform == track.platform)) {
        count++;
      }
    }
    return count;
  }

  /// 将歌曲加入或移出指定自定义歌单，返回操作后是否在歌单内
  bool toggleTrackInPlaylist(String playlistId, MusicTrack track) {
    final idx = customPlaylists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return false;
    final pl = customPlaylists[idx];
    final tracks = List<MusicTrack>.from(pl.tracks);
    final existIdx = tracks
        .indexWhere((t) => t.id == track.id && t.platform == track.platform);
    final bool added;
    if (existIdx >= 0) {
      tracks.removeAt(existIdx);
      added = false;
    } else {
      tracks.insert(0, track);
      added = true;
    }
    final cover = tracks.firstWhereOrNull(
            (t) => t.coverUrl != null && t.coverUrl!.isNotEmpty)?.coverUrl ??
        pl.coverUrl;
    final updated = Playlist(
      id: pl.id,
      name: pl.name,
      coverUrl: cover,
      tracks: tracks,
      createdAt: pl.createdAt,
    );
    _storage.playlistBox.put(updated.id, updated);
    customPlaylists[idx] = updated;
    customPlaylists.refresh();
    return added;
  }

  /// 从自定义歌单移除指定索引的歌曲
  void removeTrackFromCustomPlaylist(String playlistId, int trackIndex) {
    final idx = customPlaylists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;
    final pl = customPlaylists[idx];
    if (trackIndex < 0 || trackIndex >= pl.tracks.length) return;
    final tracks = List<MusicTrack>.from(pl.tracks)..removeAt(trackIndex);
    final cover = tracks.firstWhereOrNull(
            (t) => t.coverUrl != null && t.coverUrl!.isNotEmpty)?.coverUrl;
    final updated = Playlist(
      id: pl.id,
      name: pl.name,
      coverUrl: cover,
      tracks: tracks,
      createdAt: pl.createdAt,
    );
    _storage.playlistBox.put(updated.id, updated);
    customPlaylists[idx] = updated;
    customPlaylists.refresh();
  }

  void toggleFavorite(MusicTrack track) {
    if (isFavorite(track)) {
      favorites.removeWhere(
          (element) => element.id == track.id && element.platform == track.platform);
    } else {
      favorites.insert(0, track);
    }
    _saveFavorites();
  }

  bool isFavorite(MusicTrack track) {
    return favorites.any(
        (element) => element.id == track.id && element.platform == track.platform);
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

  /// 从播放记录中删除单条记录
  void removeFromHistory(MusicTrack track) {
    history.removeWhere((t) => t.id == track.id && t.platform == track.platform);
    _saveHistory();
  }

  /// 一键清空播放记录
  void clearHistory() {
    history.clear();
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
    _persistQueue();
    playTrack(track);
  }

  /// 按平台与当前音源路由解析:
  /// - netease → 当前激活音源(ChKSz/TuneHub),失败回退 TuneHub
  /// - 其他平台(酷我/QQ) → 仅 TuneHub 支持
  Future<Map<String, dynamic>> _resolveTrackSource(
      MusicTrack track, int taskId) async {
    if (track.platform == 'netease') {
      final active = _sourceRegistry?.active;
      if (active != null && active.id != _tuneHubService.id) {
        try {
          final res = await active.parseTrack(track.platform, track.id);
          final url = res['url']?.toString() ?? '';
          if (url.isNotEmpty) return res;
          debugPrint(
              '⚠️ [PlayTrack #$taskId] ${active.displayName} 解析为空,回退 TuneHub');
        } catch (e) {
          debugPrint(
              '⚠️ [PlayTrack #$taskId] ${active.displayName} 解析异常: $e,回退 TuneHub');
        }
      }
    }
    return _tuneHubService.parseTrack(track.platform, track.id);
  }

  /// 异步多路兜底补拉歌词（ChKSz → 网易官方公开接口 → TuneHub），成功后刷新歌词视图并持久化到曲目对象
  Future<void> _fetchLyricsAsync(MusicTrack track, int taskId) async {
    String? lrcText;
    String? tlyricText;

    // 1. 优先尝试 ChKSz 独立歌词接口
    if (track.platform == 'netease') {
      try {
        final source = _sourceRegistry?.byId('chksz');
        if (source is ChkSzMusicService) {
          final lrc = await source.fetchLyric(track.id);
          if (lrc['lrc'] != null && lrc['lrc']!.trim().isNotEmpty) {
            lrcText = lrc['lrc'];
            tlyricText = lrc['tlyric'];
          }
        }
      } catch (e) {
        debugPrint('⚠️ [Lyric #$taskId] ChKSz 歌词拉取异常: $e');
      }
    }

    // 2. 若未拿到且为网易云曲目，走网易云公开免 Key 歌词接口直拉
    if ((lrcText == null || lrcText.trim().isEmpty) &&
        track.platform == 'netease') {
      try {
        final uri = Uri.parse(
            'https://music.163.com/api/song/lyric?id=${track.id}&lv=1&kv=1&tv=-1');
        final resp = await http.get(
          uri,
          headers: _getHeaders(track),
        ).timeout(const Duration(seconds: 6));
        if (resp.statusCode == 200) {
          final data = jsonDecode(utf8.decode(resp.bodyBytes));
          if (data is Map) {
            final lrcObj = data['lrc'];
            final tlyricObj = data['tlyric'];
            if (lrcObj is Map && lrcObj['lyric'] != null) {
              lrcText = lrcObj['lyric'].toString();
            }
            if (tlyricObj is Map && tlyricObj['lyric'] != null) {
              tlyricText = tlyricObj['lyric'].toString();
            }
          }
        }
      } catch (e) {
        debugPrint('⚠️ [Lyric #$taskId] 网易公开接口拉取异常: $e');
      }
    }

    // 3. 第三路兜底：尝试 TuneHub 解析结果中的 lyrics 字段
    if (lrcText == null || lrcText.trim().isEmpty) {
      try {
        final res = await _tuneHubService.parseTrack(track.platform, track.id);
        final raw = res['lyrics']?.toString() ?? '';
        if (raw.trim().isNotEmpty) {
          lrcText = raw;
        }
      } catch (_) {}
    }

    if (lrcText == null || lrcText.trim().isEmpty) return;
    if (taskId != _currentPlayTaskId) return;

    track.lyricContent = lrcText;
    _parseLyrics(lrcText, translation: tlyricText);
    _persistTrackLyricToLibraries(track, lrcText);
    debugPrint('🎤 [PlayTrack #$taskId] 歌词补拉成功 (${lyrics.length} 行)');
  }

  /// 将拉取到的歌词回写到队列、收藏、历史与自定义歌单，保证下次缓存播放 0 延迟直接展示歌词
  void _persistTrackLyricToLibraries(MusicTrack track, String lrcText) {
    var queueChanged = false;
    for (final t in playlist) {
      if (t.id == track.id && t.platform == track.platform) {
        t.lyricContent = lrcText;
        queueChanged = true;
      }
    }
    if (queueChanged) _persistQueue();

    var favChanged = false;
    for (final t in favorites) {
      if (t.id == track.id && t.platform == track.platform) {
        t.lyricContent = lrcText;
        favChanged = true;
      }
    }
    if (favChanged) _saveFavorites();

    var histChanged = false;
    for (final t in history) {
      if (t.id == track.id && t.platform == track.platform) {
        t.lyricContent = lrcText;
        histChanged = true;
      }
    }
    if (histChanged) _saveHistory();
  }

  String _brToLabel(dynamic br) {
    final v = (br is num) ? br.toInt() : int.tryParse('$br');
    if (v == null || v <= 0) return '';
    return '${(v / 1000).round()}K';
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

    // 1. 监听播放状态变化
    audioPlayer!.playerStateStream.listen((state) {
      isPlaying.value = state.playing;

      // 处理播放完成逻辑 (只有真正播放完成才触发,手动切歌时 _isTransitioning 已被设为 true)
      if (state.processingState == ProcessingState.completed &&
          !_isTransitioning) {
        _isTransitioning = true;
        debugPrint('🎵 [PlayerState] 歌曲自然播放完成，自动切歌 (模式: ${playMode.value})');

        // 启动安全超时：10秒内若 _isTransitioning 未被正常重置，则强制重置
        _transitionSafetyTimer?.cancel();
        _transitionSafetyTimer = Timer(const Duration(seconds: 10), () {
          if (_isTransitioning) {
            debugPrint('⚠️ [Safety] _isTransitioning 超时10秒未重置，强制重置');
            _isTransitioning = false;
          }
        });

        // 记录历史
        if (playlist.isNotEmpty && currentIndex.value < playlist.length) {
          addToHistory(playlist[currentIndex.value]);
        }

        // 处理单曲循环
        if (playMode.value == PlayMode.single) {
          debugPrint('🎵 [PlayerState] 单曲循环模式，重新播放当前歌曲');
          _musicService.seek(Duration.zero).then((_) {
            _musicService.play();
            // seek+play 完成后立即重置
            _isTransitioning = false;
            _transitionSafetyTimer?.cancel();
          });
        } else {
          // 延迟执行切换，给 UI 和状态一点缓冲时间
          Future.delayed(const Duration(milliseconds: 300), () {
            playNext(isAuto: true);
          });
        }
      }

      // 重置过渡状态：当新歌开始加载或开始播放时
      if (_isTransitioning) {
        if (state.processingState == ProcessingState.loading ||
            state.processingState == ProcessingState.buffering ||
            (state.processingState == ProcessingState.ready && state.playing)) {
          _isTransitioning = false;
          _transitionSafetyTimer?.cancel();
        }
      }
    });

    // 2. 监听进度（仅用于同步歌词）
    audioPlayer!.positionStream.listen((p) {
      position.value = p;
      _syncLyricIndexWithPosition(p);
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
    // === 并发控制: 生成新的任务ID,旧任务会自动失效 ===
    final int taskId = ++_currentPlayTaskId;
    debugPrint(
        '🎵 [PlayTrack #$taskId] 开始: ${track.title} (${track.platform})');

    // 辅助函数: 检查当前任务是否仍然有效
    bool isTaskValid() => taskId == _currentPlayTaskId;

    // 重置音质标签(缓存播放时无解析响应)
    currentAudioQuality.value = '';

    // 切歌瞬间先解析已有歌词（若曾缓存过歌词，本地播放也能立即显示）
    _parseLyrics(track.lyricContent);

    // 1. 预处理：获取播放链接
    String? playUrl;
    bool fromCache = false;

    // 优先尝试缓存
    debugPrint(
        '📦 [Cache #$taskId] 检查缓存状态: initialized=${_cacheService.isInitialized}, enabled=${_cacheService.cacheEnabled.value}');

    if (_cacheService.isInitialized && _cacheService.cacheEnabled.value) {
      // 先快速检查是否有缓存(不进行解密)
      final hasCached = _cacheService.isCached(track);
      debugPrint(
          '📦 [Cache #$taskId] 缓存索引检查: ${hasCached ? "命中" : "未命中"} (${track.id}@${track.platform})');

      if (hasCached) {
        final cachedPath = await _cacheService.getCachedFilePath(track);
        if (!isTaskValid()) {
          debugPrint('🔄 [PlayTrack #$taskId] 任务已取消(缓存解密后)');
          _isTransitioning = false;
          return;
        }
        if (cachedPath != null) {
          debugPrint('✅ [PlayTrack #$taskId] 从缓存播放');
          playUrl = 'file://$cachedPath';
          fromCache = true;
          // 修复缓存播放无歌词 Bug：命中音频缓存但曲目尚无歌词时，立即后台异步补拉歌词！
          if (lyrics.isEmpty) {
            unawaited(_fetchLyricsAsync(track, taskId));
          }
        } else {
          debugPrint('⚠️ [PlayTrack #$taskId] 缓存解密失败,将使用在线链接');
        }
      }
    }

    // 若无缓存,解析在线链接
    if (playUrl == null && !fromCache) {
      debugPrint('🌐 [PlayTrack #$taskId] 开始解析在线链接...');
      try {
        final res = await _resolveTrackSource(track, taskId);
        if (!isTaskValid()) {
          debugPrint('🔄 [PlayTrack #$taskId] 任务已取消(URL解析后)');
          _isTransitioning = false;
          return;
        }
        if (res.containsKey('url') && res['url'] != null) {
          playUrl = res['url'];
          track.url = playUrl;

          // 更新歌曲附加信息
          if (res['cover'] != null) track.coverUrl = res['cover'];
          if (res['lyrics'] != null &&
              res['lyrics'].toString().trim().isNotEmpty) {
            track.lyricContent = res['lyrics'].toString();
          }
          _parseLyrics(track.lyricContent);

          // 记录实际命中的音质档位
          final level = res['level']?.toString() ?? '';
          currentAudioQuality.value =
              level.isNotEmpty ? level : _brToLabel(res['br']);
          debugPrint(
              '🌐 [PlayTrack #$taskId] 在线链接解析成功 (音质: ${currentAudioQuality.value})');

          // 若解析响应中不含歌词，异步多路补拉歌词，不阻塞播放
          if (lyrics.isEmpty) {
            unawaited(_fetchLyricsAsync(track, taskId));
          }
        }
      } catch (e) {
        debugPrint('❌ [PlayTrack #$taskId] 链接解析异常: $e');
      }
    }

    // 检查URL是否有效
    if (playUrl == null || playUrl.isEmpty) {
      debugPrint('⚠️ [PlayTrack #$taskId] 无法获取播放地址');
      _isTransitioning = false;
      if (isTaskValid()) {
        // 静默跳下一首,不打扰用户
        Future.delayed(const Duration(milliseconds: 500), () {
          if (isTaskValid()) playNext(isAuto: true);
        });
      }
      return;
    }

    // 针对性协议处理
    if (track.platform == 'netease' && playUrl.startsWith('http://')) {
      playUrl = playUrl.replaceFirst('http://', 'https://');
    }

    // 2. 播放音频
    try {
      await _ensurePlayer();
      if (audioPlayer == null || !isTaskValid()) {
        debugPrint('🔄 [PlayTrack #$taskId] 任务已取消(获取播放器后)');
        _isTransitioning = false;
        return;
      }

      // 标记为过渡状态,防止 stop() 触发的 completed 状态误触自动切歌
      _isTransitioning = true;

      // 重置播放器状态 (忽略任何中断异常)
      try {
        await _musicService.stop();
      } catch (_) {}

      // 重置进度显示
      position.value = Duration.zero;
      duration.value = Duration.zero;

      // 再次检查任务有效性
      if (!isTaskValid()) {
        debugPrint('🔄 [PlayTrack #$taskId] 任务已取消(停止后)');
        _isTransitioning = false;
        return;
      }

      final mediaItem = _toMediaItem(track);

      // 通过 MusicService 设置音源并播放（走 AudioHandler，触发通知栏）
      final Map<String, String> headers = _getHeaders(track);
      final source = AudioSource.uri(
        Uri.parse(playUrl),
        headers: headers,
      );
      final resolvedDuration = await _musicService.setSourceAndPlay(
        source,
        mediaItem,
        headers,
      );

      // 最后一次检查
      if (!isTaskValid()) {
        _isTransitioning = false;
        try {
          await _musicService.stop();
        } catch (_) {}
        return;
      }

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

      if (resolvedDuration != null) {
        track.durationMs = resolvedDuration.inMilliseconds;
      }
      _syncAudioServiceQueue(currentDuration: resolvedDuration);

      addToHistory(track);
      _persistQueue();
      debugPrint(
          '✅ [PlayTrack #$taskId] 播放成功: ${track.title} ${fromCache ? "(缓存)" : "(在线)"}');

      // 只有在线播放时才触发缓存 (缓存播放不需要重复缓存)
      if (!fromCache && playUrl.startsWith('http')) {
        _cacheService.cacheSong(track, playUrl).catchError((e) {
          debugPrint('Cache error: $e');
          return false;
        });
      }
    } catch (e) {
      // 只记录日志,不弹窗打扰用户
      debugPrint('❌ [PlayTrack #$taskId] 播放失败: $e');

      // 重置过渡状态
      _isTransitioning = false;

      // 如果不是被新任务取消的,尝试下一首
      if (isTaskValid() && !e.toString().contains('interrupted')) {
        Future.delayed(const Duration(seconds: 1), () {
          if (isTaskValid()) playNext(isAuto: true);
        });
      }
    }
  }

  // Play Mode
  final Rx<PlayMode> playMode = PlayMode.sequence.obs;

  // === 播放队列持久化(重启后恢复队列/进度索引/播放模式) ===
  static const String _queueStorageKey = 'music_queue_tracks';
  static const String _queueIndexKey = 'music_queue_index';
  static const String _playModeStorageKey = 'player_play_mode';

  void _persistQueue() {
    try {
      _storage.saveValue(_queueStorageKey,
          jsonEncode(playlist.map((t) => t.toJson()).toList()));
      _storage.saveValue(_queueIndexKey, currentIndex.value.toString());
    } catch (e) {
      debugPrint('⚠️ [Queue] 队列持久化失败: $e');
    }
  }

  void _restoreQueue() {
    try {
      final raw = _storage.getValue(_queueStorageKey);
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw) as List?;
      if (list == null || list.isEmpty) return;
      final restored = list
          .map((e) =>
              MusicTrack.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      playlist.assignAll(restored);
      final idx =
          int.tryParse(_storage.getValue(_queueIndexKey) ?? '0') ?? 0;
      currentIndex.value = idx.clamp(0, restored.length - 1);
      final current = restored[currentIndex.value];
      _parseLyrics(current.lyricContent);
      debugPrint('✅ [Queue] 已恢复播放队列 ${restored.length} 首');
    } catch (e) {
      debugPrint('⚠️ [Queue] 播放队列恢复失败: $e');
    }
  }

  void _restorePlayMode() {
    final saved = int.tryParse(_storage.getValue(_playModeStorageKey) ?? '');
    if (saved != null && saved >= 0 && saved < PlayMode.values.length) {
      playMode.value = PlayMode.values[saved];
    }
  }

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
    _storage.saveValue(_playModeStorageKey, playMode.value.index.toString());
  }

  void playNext({bool isAuto = false}) {
    if (playlist.isEmpty) return;

    // 如果处于单曲循环模式且是自动播放（非手动点下一首），则继续播放当前
    if (isAuto && playMode.value == PlayMode.single) {
      _musicService.seek(Duration.zero);
      _musicService.play();
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

  /// 将歌曲插入当前播放歌曲之后(下一首播放)
  void playNextInQueue(MusicTrack track) {
    if (playlist.isEmpty) {
      playWithList([track], track);
      return;
    }
    final exists =
        playlist.any((t) => t.id == track.id && t.platform == track.platform);
    if (exists) {
      Get.snackbar('提示', '这首歌已经在播放列表里啦');
      return;
    }
    playlist.insert(currentIndex.value + 1, track);
    _syncAudioServiceQueue();
    _persistQueue();
    Get.snackbar('下一首播放', '${track.title} - ${track.artist}');
  }

  /// 从播放队列中移除指定歌曲
  void removeTrackAt(int index) {
    if (index < 0 || index >= playlist.length) return;
    final wasCurrent = index == currentIndex.value;
    playlist.removeAt(index);

    if (playlist.isEmpty) {
      _musicService.stop();
      currentIndex.value = 0;
      position.value = Duration.zero;
      duration.value = Duration.zero;
      isPlaying.value = false;
      _persistQueue();
      return;
    }
    if (wasCurrent) {
      // 播放移除位置处的下一首(索引越界时回退到列表末尾)
      int nextIndex = index;
      if (nextIndex >= playlist.length) nextIndex = playlist.length - 1;
      playTrack(playlist[nextIndex], targetIndex: nextIndex);
    } else if (index < currentIndex.value) {
      currentIndex.value--;
      _syncAudioServiceQueue();
    }
    _persistQueue();
  }

  /// 清空播放队列并停止播放
  void clearPlaylist() {
    _musicService.stop();
    playlist.clear();
    currentIndex.value = 0;
    position.value = Duration.zero;
    duration.value = Duration.zero;
    isPlaying.value = false;
    _persistQueue();
  }

  void togglePlay() {
    if (isPlaying.value) {
      _musicService.pause();
    } else {
      _musicService.play();
    }
  }

  void seek(Duration pos) {
    position.value = pos;
    _syncLyricIndexWithPosition(pos);
    _musicService.seek(pos);
  }

  /// 根据播放进度立即同步歌词高亮索引
  void _syncLyricIndexWithPosition(Duration p) {
    if (lyrics.isEmpty) {
      if (currentLyricIndex.value != 0) currentLyricIndex.value = 0;
      return;
    }
    final index = lyrics.lastIndexWhere((l) => l.startTime <= p);
    final resolved = index == -1 ? 0 : index;
    if (resolved != currentLyricIndex.value) {
      currentLyricIndex.value = resolved;
    }
  }

  // === 歌曲下载:保存到公共下载目录 Download/starBank/music ===

  /// 音频来源优先复用已缓存(解密)文件,其次解析在线链接并带平台头下载
  Future<void> downloadTrack(MusicTrack track) async {
    if (isDownloading.value) return;
    isDownloading.value = true;
    try {
      Uint8List? bytes;

      // 1. 优先读本地缓存里已解密的音频
      if (_cacheService.isInitialized && _cacheService.isCached(track)) {
        try {
          final cachedPath = await _cacheService.getCachedFilePath(track);
          if (cachedPath != null) {
            final f = File(cachedPath);
            if (await f.exists()) bytes = await f.readAsBytes();
          }
        } catch (e) {
          debugPrint('⚠️ [Download] 读取缓存失败,改走在线下载: $e');
        }
      }

      // 2. 无缓存时解析在线链接(与播放同一路径)并下载
      if (bytes == null) {
        var url = (track.url != null && track.url!.startsWith('http'))
            ? track.url!
            : '';
        if (url.isEmpty) {
          final res = await _resolveTrackSource(track, 0);
          url = res['url']?.toString() ?? '';
        }
        if (url.isEmpty) {
          Get.snackbar('下载失败', '暂时拿不到这首歌的音频链接');
          return;
        }
        if (track.platform == 'netease' && url.startsWith('http://')) {
          url = url.replaceFirst('http://', 'https://');
        }
        final resp = await http
            .get(Uri.parse(url), headers: _getHeaders(track))
            .timeout(const Duration(minutes: 5));
        if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) {
          Get.snackbar('下载失败', '音频下载出错 (HTTP ${resp.statusCode})');
          return;
        }
        bytes = resp.bodyBytes;
      }

      // 3. API 29 以下需要存储权限;29+ MediaStore 免权限
      final sdk = await _publicStorage.sdkInt();
      if (sdk > 0 && sdk < 29) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          Get.snackbar('下载失败', '需要存储权限才能保存到下载目录');
          return;
        }
      }

      // 4. 文件名过滤系统保留字符
      final safeName =
          '${track.title} - ${track.artist}'.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
      final fileName = safeName.isEmpty
          ? 'song_${track.platform}_${track.id}.mp3'
          : '$safeName.mp3';

      final savedName = await _publicStorage.saveToDownload(
        bytes: bytes,
        fileName: fileName,
        subDir: downloadSubDir,
        mimeType: PublicStorageService.audioMime(fileName),
      );
      Get.snackbar('下载完成', 'Download/$downloadSubDir/$savedName',
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      debugPrint('❌ [Download] 下载失败: $e');
      Get.snackbar('下载失败', '$e', snackPosition: SnackPosition.BOTTOM);
    } finally {
      isDownloading.value = false;
    }
  }

  // Timer logic
  void setSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    sleepTimerMinutes.value = minutes;
    if (minutes > 0) {
      _sleepTimer = Timer(Duration(minutes: minutes), () {
        _musicService.pause();
        sleepTimerMinutes.value = 0;
        Get.snackbar('定时关闭', '音乐已停止');
      });
    }
  }

  // --- Lyrics Logic ---

  final RxList<LyricLine> lyrics = <LyricLine>[].obs;
  final RxInt currentLyricIndex = 0.obs;

  void _parseLyrics(String? content, {String? translation}) {
    lyrics.clear();
    currentLyricIndex.value = 0;
    if (content == null || content.trim().isEmpty) return;

    // 兼容 [mm:ss.SS] / [mm:ss.SSS] / [mm:ss:SS] 以及无毫秒的 [mm:ss]，支持一行多个时间标签
    final tagRegExp = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
    // 跳过如 [ti:...] [ar:...] [al:...] [by:...] [offset:...] 等非歌词元数据标签
    final metaRegExp = RegExp(r'^\[[a-zA-Z]+:.*\]$');

    List<LyricLine> parse(String text) {
      final result = <LyricLine>[];
      final plainLines = <String>[];
      for (final rawLine in text.replaceAll('\r\n', '\n').split('\n')) {
        final line = rawLine.trim();
        if (line.isEmpty || metaRegExp.hasMatch(line)) continue;
        final matches = tagRegExp.allMatches(line).toList();
        if (matches.isEmpty) {
          if (!line.startsWith('[')) plainLines.add(line);
          continue;
        }
        final body = line.replaceAll(tagRegExp, '').trim();
        if (body.isEmpty) continue;
        for (final m in matches) {
          final min = int.tryParse(m.group(1)!) ?? 0;
          final sec = int.tryParse(m.group(2)!) ?? 0;
          final msStr = m.group(3) ?? '0';
          final ms = int.tryParse(msStr.padRight(3, '0').substring(0, 3)) ?? 0;
          result.add(LyricLine(
            Duration(minutes: min, seconds: sec, milliseconds: ms),
            body,
          ));
        }
      }
      if (result.isEmpty && plainLines.isNotEmpty) {
        // 兜底：若返回的是纯文本无时间戳歌词，按每行 4 秒生成时间轴
        for (var i = 0; i < plainLines.length; i++) {
          result.add(LyricLine(Duration(seconds: i * 4), plainLines[i]));
        }
      }
      result.sort((a, b) => a.startTime.compareTo(b.startTime));
      return result;
    }

    final parsed = parse(content);

    // 翻译歌词按时间就近合并(1 秒内取最接近的一条)
    if (translation != null &&
        translation.trim().isNotEmpty &&
        parsed.isNotEmpty) {
      final transLines = parse(translation);
      for (final line in parsed) {
        LyricLine? best;
        var bestDelta = const Duration(seconds: 1);
        for (final t in transLines) {
          final delta = (t.startTime - line.startTime).abs();
          if (delta <= bestDelta) {
            bestDelta = delta;
            best = t;
          }
        }
        line.translation = best?.content;
      }
    }

    lyrics.assignAll(parsed);
    _syncLyricIndexWithPosition(position.value);
  }

  @override
  void onClose() {
    // Cannot dispose global player from controller!
    // _musicService handles lifecycle if needed.
    _sleepTimer?.cancel();
    _transitionSafetyTimer?.cancel();
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

  MediaItem _toMediaItem(MusicTrack track, {Duration? duration}) {
    // 网易封面统一 https,避免系统媒体组件加载明文图片失败
    String? artUri = track.coverUrl;
    if (artUri != null &&
        artUri.isNotEmpty &&
        track.platform == 'netease' &&
        artUri.startsWith('http://')) {
      artUri = artUri.replaceFirst('http://', 'https://');
    }
    return MediaItem(
      id: '${track.platform}:${track.id}',
      title: track.title,
      artist: track.artist,
      album: track.album ?? '',
      duration: duration ??
          (track.durationMs != null
              ? Duration(milliseconds: track.durationMs!)
              : null),
      artUri: (artUri != null && artUri.isNotEmpty)
          ? Uri.tryParse(artUri)
          : null,
      // 网易图片 CDN 封 Dart 开头的 UA;通知栏封面走原生加载(替换语义),带完整浏览器头
      artHeaders: nativeCoverHeadersFor(artUri),
      extras: {
        'platform': track.platform,
        'trackId': track.id,
      },
    );
  }

  void _syncAudioServiceQueue({Duration? currentDuration}) {
    final handler = _musicService.audioHandler;
    if (handler == null || playlist.isEmpty) return;
    final items = <MediaItem>[];
    for (var i = 0; i < playlist.length; i++) {
      items.add(
        _toMediaItem(
          playlist[i],
          duration: i == currentIndex.value ? currentDuration : null,
        ),
      );
    }
    unawaited(handler.updateQueueAndMediaItem(items, currentIndex.value));
  }
}

class LyricLine {
  final Duration startTime;
  final String content;

  /// 翻译歌词(与原文时间就近合并后回填)
  String? translation;

  LyricLine(this.startTime, this.content, {this.translation});
}

enum PlayMode {
  sequence,
  shuffle,
  single,
}
