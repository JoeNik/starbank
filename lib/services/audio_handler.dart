import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';

Future<AudioHandler> initAudioService() async {
  return await AudioService.init(
    builder: () => MusicHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.starbank.app.channel.audio.v7',
      androidNotificationChannelName: 'StarBank 音乐播放',
      androidNotificationChannelDescription: '音乐播放控制',
      androidNotificationOngoing: false, // 修复：与 androidStopForegroundOnPause=false 冲突
      androidStopForegroundOnPause: false, // 暂停时保持前台服务
      androidNotificationClickStartsActivity: true,
      androidShowNotificationBadge: true,
      notificationColor: Color(0xFFFFB27D),
      androidNotificationIcon: 'drawable/ic_stat_music_note',
      // ColorOS 优化：提升通知优先级，确保下拉通知栏显示
      preloadArtwork: true,
      artDownscaleWidth: 512,
      artDownscaleHeight: 512,
      fastForwardInterval: Duration(seconds: 10),
      rewindInterval: Duration(seconds: 10),
    ),
  );
}

/// 使用 audio_service 封装 just_audio
/// 这是解决 Android 14 后台播放问题的核心类
class MusicHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final _player = AudioPlayer();
  int _queueIndex = 0;
  late final Future<void> ready;

  // 暴露给 Service/Controller 以便监听进度流等
  AudioPlayer get player => _player;

  MusicHandler() {
    ready = _init();
  }

  Future<void> _init() async {
    // 0. 配置 AudioSession (这对通知栏显示和音频焦点至关重要)
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    // 1. 将 JustAudio 的播放事件转换为 AudioService 的 PlaybackState
    _player.playbackEventStream.listen(_broadcastState);

    // 2. 监听出错信息
    _player.playerStateStream.listen((state) {
      _broadcastState(_player.playbackEvent);
    });

    // 3. 初始广播，确保通知栏能立即显示
    mediaItem.add(const MediaItem(
      id: '__INIT__',
      title: 'StarBank 音乐',
      artist: '准备就绪',
    ));

    // 初始状态：显示播放按钮（重要：设置 playing=false 但要确保通知能显示）
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.play,
      ],
      processingState: AudioProcessingState.idle,
      playing: false,
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0],
      queueIndex: _queueIndex,
    ));

    // 4. 延迟一小段时间后再发送一次状态，确保系统注册完成
    await Future.delayed(const Duration(milliseconds: 100));
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.play,
      ],
      processingState: AudioProcessingState.idle,
      playing: false,
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0],
      queueIndex: _queueIndex,
    ));
  }

  /// 广播状态给系统（通知栏/锁屏界面）
  /// 参考 Harmonoid 的实现优化
  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    final processingState = _player.processingState;

    debugPrint('🔔 [AudioHandler] Broadcasting state: playing=$playing, state=$processingState');

    // 根据播放状态动态调整控制按钮
    final controls = <MediaControl>[
      MediaControl.skipToPrevious,
      if (playing) MediaControl.pause else MediaControl.play,
      MediaControl.skipToNext,
    ];

    final newState = PlaybackState(
      controls: controls,
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      // Compact actions: 上一首(0), 播放/暂停(1), 下一首(2)
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[processingState]!,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex ?? _queueIndex,
    );

    playbackState.add(newState);
    debugPrint('🔔 [AudioHandler] State broadcasted');
  }

  @override
  Future<void> play() async {
    await ready;
    debugPrint('🎵 [AudioHandler] play() called - starting playback');
    await _player.play();
    // 强制广播一次状态，确保通知栏更新
    _broadcastState(_player.playbackEvent);
  }

  @override
  Future<void> pause() async {
    await ready;
    await _player.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    await ready;
    await _player.seek(position);
  }

  @override
  Future<void> stop() async {
    await ready;
    await _player.stop();
  }

  @override
  Future<void> skipToNext() async {
    await ready;
    // 由于具体的播放列表逻辑目前在 Controller 中管理（GetX），
    // 这里我们发出一个自定义事件，或者让 Controller 监听标准事件。
    // 为了简单起见，且遵循 Controller 中心化，我们这里的回调主要服务于通知栏点击。
    // 实际跳转逻辑如果复杂，可以通过回调或者 EventBus 通知 Controller。
    // 但为了架构标准，理想情况下 Queue 应该在这里管理。
    // 鉴于时间紧迫，我们暂时保留控制器的逻辑，但通知栏点击需要能触发 Controller 的动作。
    // 一种方法是 expose 一个回调，或者使用 GetX 查找 MusicPlayerController (如果不违反分层原则)。
    // 但 Service 层不应依赖 UI 层 Controller。
    // 我们先留空，等下在 MusicService 中绑定。
    // 实际上，MusicPlayerController 可以监听 AudioService 的 skipToNext 流 (如果它是通过 mediaItem 变更实现的)。
    // 但更直接的是：Controller 调用 handler，而 handler 的回调再通知回 Controller? 这会循环。
    // 正确的做法：Controller 是 UI 和数据胶水。Service 持有 Handler。
    // 当点击通知栏 -> 系统调用 Handler.skipToNext -> Handler 触发某个流 -> Controller 监听到流 -> Controller 执行 playNext()。
    // BaseAudioHandler 本身有个 customAction，或者我们可以简单的扩展它。

    // 临时方案：直接在这里不做具体实现，而是指望 MusicService 能够把这些动作桥接出去。
    // 或者更简单的：MusicService 作为一个 GetxService，可以被 Controller 访问。
    // 反之，Handler 无法直接访问 Controller。
    // 我们定义一个 callback 允许外部注册。
    onSkipToNext?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    await ready;
    onSkipToPrevious?.call();
  }

  // 用于外部注册的回调
  VoidCallback? onSkipToNext;
  VoidCallback? onSkipToPrevious;

  /// 设置当前播放的媒体信息（通知栏显示用）
  @override
  Future<void> updateMediaItem(MediaItem item) async {
    await ready;
    debugPrint('📻 [AudioHandler] Updating MediaItem: ${item.title} - ${item.artist}');
    mediaItem.add(item);
    _broadcastState(_player.playbackEvent);
  }

  /// 完整的播放流程：设置音源 → 更新 mediaItem → 播放
  /// 通过 handler 层面的 play() 触发，确保 audio_service 正确启动前台服务
  Future<Duration?> setAudioSourceAndPlay(
    AudioSource source,
    MediaItem item,
  ) async {
    await ready;

    // 1. 先更新 mediaItem，让通知栏显示正确的歌曲信息
    mediaItem.add(item);

    // 2. 立即广播一次 loading 状态，确保通知栏出现
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        MediaControl.pause,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: AudioProcessingState.loading,
      playing: false,
      updatePosition: Duration.zero,
      bufferedPosition: Duration.zero,
      speed: 1.0,
      queueIndex: _queueIndex,
    ));

    // 3. 设置音源
    final duration = await _player.setAudioSource(source);

    // 4. 通过 handler 的 play() 启动播放（触发 audio_service 前台服务）
    await play();

    return duration;
  }

  Future<void> updateQueueAndMediaItem(
    List<MediaItem> items,
    int currentIndex,
  ) async {
    await ready;
    queue.add(items);
    if (items.isEmpty) return;
    _queueIndex = currentIndex.clamp(0, items.length - 1).toInt();
    mediaItem.add(items[_queueIndex]);
    _broadcastState(_player.playbackEvent);
  }
}
