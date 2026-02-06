import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';

Future<AudioHandler> initAudioService() async {
  return await AudioService.init(
    builder: () => MusicHandler(),
    config: AudioServiceConfig(
      androidNotificationChannelId:
          'com.starbank.app.channel.audio.v4', // New ID to force fresh settings
      androidNotificationChannelName: 'StarBank 音乐播放器',
      androidNotificationChannelDescription: '提供后台播放和通知栏控制',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: false, // 非常重要：暂停时不移除通知栏，防止被系统杀死
      androidNotificationClickStartsActivity: true,
      androidResumeOnClick: true,
      androidNotificationIcon: 'mipmap/ic_launcher', // 使用标准应用图标
      notificationColor: Color(0xFFFFB27D),
    ),
  );
}

/// 使用 audio_service 封装 just_audio
/// 这是解决 Android 14 后台播放问题的核心类
class MusicHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final _player = AudioPlayer();

  // 暴露给 Service/Controller 以便监听进度流等
  AudioPlayer get player => _player;

  MusicHandler() {
    _init();
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

    // 3. 初始广播，确保通知栏能立即占位
    // 注意：系统通知栏通常需要 MediaItem 有数据（标题、封面等）才会显示
    mediaItem.add(const MediaItem(
      id: 'initial_placeholder',
      title: 'StarBankMusic',
      artist: '准备就绪',
      album: 'StarBank',
    ));

    playbackState.add(playbackState.value.copyWith(
      controls: [MediaControl.play],
      processingState: AudioProcessingState.idle,
      playing: false,
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0],
    ));

    // 4. 处理播放完毕自动下一曲等逻辑通常由 Controller 或 Queue 处理
    // 这里主要负责状态同步
  }

  /// 广播状态给系统（通知栏/锁屏界面）
  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    final queueIndex = event.currentIndex;

    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: queueIndex,
    ));
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> skipToNext() async {
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
    onSkipToPrevious?.call();
  }

  // 用于外部注册的回调
  VoidCallback? onSkipToNext;
  VoidCallback? onSkipToPrevious;

  /// 设置当前播放的媒体信息（通知栏显示用）
  Future<void> updateMediaItem(MediaItem item) async {
    mediaItem.add(item);
  }
}
