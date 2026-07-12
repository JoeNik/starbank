import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

import '../../controllers/app_mode_controller.dart';
import '../../models/baby_cloud_media.dart';
import '../../services/baby_cloud_service.dart';
import '../../widgets/baby_cloud_media_thumbnail.dart';
import '../../widgets/toast_utils.dart';

class BabyCloudMediaDetailPage extends StatefulWidget {
  const BabyCloudMediaDetailPage({
    super.key,
    required this.items,
    required this.initialIndex,
  });

  final List<BabyCloudMedia> items;
  final int initialIndex;

  @override
  State<BabyCloudMediaDetailPage> createState() =>
      _BabyCloudMediaDetailPageState();
}

class _BabyCloudMediaDetailPageState extends State<BabyCloudMediaDetailPage> {
  late PageController _controller;
  late int _index;
  bool _isZoomed = false; // 跟踪是否处于缩放状态
  final _mode = Get.find<AppModeController>();

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        foregroundColor: Colors.white,
        backgroundColor: Colors.black,
        title: Text('${_index + 1}/${widget.items.length}'),
        actions: [
          IconButton(
            tooltip: '删除到回收站',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (!_mode.isParentMode) {
                ToastUtils.showWarning('请先切换到家长模式');
                return;
              }
              await Get.find<BabyCloudService>().softDeleteMedia(item);
              Get.back();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.items.length,
              physics: _isZoomed
                  ? const NeverScrollableScrollPhysics() // 缩放时禁用滑动
                  : const PageScrollPhysics(),
              onPageChanged: (index) => setState(() {
                _index = index;
                _isZoomed = false;
              }),
              itemBuilder: (_, index) {
                final current = widget.items[index];
                if (current.isAudio) return _AudioPreview(item: current);
                if (current.isVideo) return _VideoPreview(item: current);
                return _ZoomableImagePreview(
                  key: ValueKey(current.id),
                  item: current,
                  onZoomChanged: (zoomed) {
                    if (!mounted || index != _index || _isZoomed == zoomed) {
                      return;
                    }
                    setState(() => _isZoomed = zoomed);
                  },
                );
              },
            ),
          ),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(16.w),
            color: Colors.black87,
            child: DefaultTextStyle(
              style: const TextStyle(color: Colors.white70),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.fileName,
                      style: const TextStyle(color: Colors.white)),
                  SizedBox(height: 4.h),
                  Text(
                      '拍摄时间 ${DateFormat('yyyy-MM-dd HH:mm').format(item.takenAt)}'),
                  Text(
                      '上传时间 ${DateFormat('yyyy-MM-dd HH:mm').format(item.uploadedAt)}'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoomableImagePreview extends StatefulWidget {
  const _ZoomableImagePreview({
    super.key,
    required this.item,
    required this.onZoomChanged,
  });

  final BabyCloudMedia item;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomableImagePreview> createState() => _ZoomableImagePreviewState();
}

class _ZoomableImagePreviewState extends State<_ZoomableImagePreview> {
  final TransformationController _transformationController =
      TransformationController();
  bool _gestureLockActive = false;
  bool _pageLockActive = false;

  @override
  void initState() {
    super.initState();
    _transformationController.addListener(_syncPageLockState);
  }

  @override
  void dispose() {
    _transformationController.removeListener(_syncPageLockState);
    if (_pageLockActive) {
      widget.onZoomChanged(false);
    }
    _transformationController.dispose();
    super.dispose();
  }

  void _syncPageLockState() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    final shouldLock = _gestureLockActive || scale > 1.01;
    if (shouldLock == _pageLockActive) return;
    _pageLockActive = shouldLock;
    widget.onZoomChanged(shouldLock);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return InteractiveViewer(
          transformationController: _transformationController,
          minScale: 1,
          maxScale: 4,
          onInteractionStart: (details) {
            if (details.pointerCount < 2) return;
            _gestureLockActive = true;
            _syncPageLockState();
          },
          onInteractionEnd: (_) {
            _gestureLockActive = false;
            _syncPageLockState();
          },
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: BabyCloudMediaThumbnail(
              item: widget.item,
              fit: BoxFit.contain,
              backgroundColor: Colors.black,
              preferOriginal: true,
              showVideoBadge: false,
            ),
          ),
        );
      },
    );
  }
}

class _AudioPreview extends StatefulWidget {
  const _AudioPreview({required this.item});

  final BabyCloudMedia item;

  @override
  State<_AudioPreview> createState() => _AudioPreviewState();
}

class _AudioPreviewState extends State<_AudioPreview> {
  final _player = AudioPlayer();
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final path = await Get.find<BabyCloudService>().ensureLocalMediaFile(
      widget.item,
    );
    if (path == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '录音文件暂不可读取';
        });
      }
      return;
    }
    try {
      await _player.setFilePath(path);
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '录音播放失败: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(28.w),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return Center(
      child: Container(
        margin: EdgeInsets.all(28.w),
        padding: EdgeInsets.all(22.w),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 38.r,
              backgroundColor: const Color(0xFFFFC22D),
              child: Icon(Icons.mic, color: Colors.white, size: 38.sp),
            ),
            SizedBox(height: 18.h),
            Text(
              widget.item.fileName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 17.sp,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 18.h),
            StreamBuilder<Duration>(
              stream: _player.positionStream,
              initialData: Duration.zero,
              builder: (context, snapshot) {
                final position = snapshot.data ?? Duration.zero;
                final duration = _player.duration ?? Duration.zero;
                final maxMs = duration.inMilliseconds <= 0
                    ? 1.0
                    : duration.inMilliseconds.toDouble();
                final value =
                    position.inMilliseconds.clamp(0, maxMs.toInt()).toDouble();
                return Column(
                  children: [
                    Slider(
                      value: value,
                      max: maxMs,
                      activeColor: const Color(0xFFFFC22D),
                      inactiveColor: Colors.white24,
                      onChanged: duration == Duration.zero
                          ? null
                          : (v) => _player.seek(
                                Duration(milliseconds: v.round()),
                              ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_formatDuration(position),
                            style: const TextStyle(color: Colors.white70)),
                        Text(_formatDuration(duration),
                            style: const TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ],
                );
              },
            ),
            SizedBox(height: 12.h),
            StreamBuilder<PlayerState>(
              stream: _player.playerStateStream,
              builder: (context, snapshot) {
                final state = snapshot.data;
                final playing = state?.playing ?? _player.playing;
                return IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFFFC22D),
                    foregroundColor: Colors.white,
                    fixedSize: Size(58.w, 58.w),
                  ),
                  icon: Icon(
                    playing ? Icons.pause : Icons.play_arrow,
                    size: 34.sp,
                  ),
                  onPressed: () async {
                    if (playing) {
                      await _player.pause();
                    } else {
                      if (_player.processingState ==
                          ProcessingState.completed) {
                        await _player.seek(Duration.zero);
                      }
                      await _player.play();
                    }
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _VideoPreview extends StatefulWidget {
  const _VideoPreview({required this.item});

  final BabyCloudMedia item;

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  VideoPlayerController? _controller;
  bool _loading = true;
  String? _error;
  bool _controlsVisible = true;
  bool _dragging = false;
  double? _dragValueMs;
  Timer? _hideControlsTimer;
  bool _wakeLockHeld = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final path = await Get.find<BabyCloudService>().ensureLocalMediaFile(
      widget.item,
    );
    if (!mounted) return;
    if (path == null) {
      setState(() {
        _loading = false;
        _error = '视频文件暂不可读取';
      });
      return;
    }

    final controller = VideoPlayerController.file(File(path));
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      controller.addListener(_onControllerTick);
      setState(() {
        _controller = controller;
        _loading = false;
      });
      await controller.play();
      await _setKeepScreenOn(true);
      _scheduleHideControls();
    } catch (e) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '视频播放失败: $e';
      });
    }
  }

  void _onControllerTick() {
    if (!mounted || _dragging) return;
    setState(() {});
  }

  Future<void> _setKeepScreenOn(bool enabled) async {
    if (_wakeLockHeld == enabled) return;
    try {
      if (enabled) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
      _wakeLockHeld = enabled;
    } catch (e) {
      debugPrint('Wakelock failed: $e');
    }
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) {
      _scheduleHideControls();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    final controller = _controller;
    if (controller == null || !controller.value.isPlaying) return;
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || _dragging) return;
      if (_controller?.value.isPlaying == true) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  Future<void> _togglePlayPause() async {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      await controller.pause();
      await _setKeepScreenOn(false);
      _hideControlsTimer?.cancel();
      if (mounted) setState(() => _controlsVisible = true);
    } else {
      final duration = controller.value.duration;
      final position = controller.value.position;
      if (duration > Duration.zero && position >= duration) {
        await controller.seekTo(Duration.zero);
      }
      await controller.play();
      await _setKeepScreenOn(true);
      _scheduleHideControls();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    final controller = _controller;
    controller?.removeListener(_onControllerTick);
    unawaited(_setKeepScreenOn(false));
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(28.w),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    final controller = _controller!;
    final value = controller.value;
    final duration = value.duration;
    final position = _dragging
        ? Duration(milliseconds: (_dragValueMs ?? 0).round())
        : value.position;
    final maxMs =
        duration.inMilliseconds <= 0 ? 1.0 : duration.inMilliseconds.toDouble();
    final progressMs =
        position.inMilliseconds.clamp(0, maxMs.toInt()).toDouble();
    final playing = value.isPlaying;
    final aspect = value.aspectRatio == 0 ? (16 / 9) : value.aspectRatio;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleControls,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: aspect,
              child: VideoPlayer(controller),
            ),
          ),
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x00000000),
                      Color(0x14000000),
                      Color(0x8C000000),
                    ],
                    stops: [0.42, 0.7, 1],
                  ),
                ),
              ),
            ),
          ),
          IgnorePointer(
            ignoring: !_controlsVisible,
            child: AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: Center(
                child: Material(
                  color: const Color(0x6B000000),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _togglePlayPause,
                    child: SizedBox(
                      width: 70.w,
                      height: 70.w,
                      child: Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 42.sp,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          IgnorePointer(
            ignoring: !_controlsVisible,
            child: AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(14.w, 0, 14.w, 14.h),
                    child: Container(
                      padding: EdgeInsets.fromLTRB(8.w, 6.h, 12.w, 8.h),
                      decoration: BoxDecoration(
                        color: const Color(0x66000000),
                        borderRadius: BorderRadius.circular(14.r),
                        border: Border.all(color: const Color(0x22FFFFFF)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                onPressed: _togglePlayPause,
                                icon: Icon(
                                  playing
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 28.sp,
                                ),
                              ),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 3.5,
                                    thumbShape: RoundSliderThumbShape(
                                      enabledThumbRadius: 7.r,
                                    ),
                                    overlayShape: RoundSliderOverlayShape(
                                      overlayRadius: 14.r,
                                    ),
                                    activeTrackColor: const Color(0xFFFFC22D),
                                    inactiveTrackColor: const Color(0x3DFFFFFF),
                                    thumbColor: const Color(0xFFFFC22D),
                                    overlayColor: const Color(0x33FFC22D),
                                  ),
                                  child: Slider(
                                    value: progressMs,
                                    max: maxMs,
                                    onChangeStart: (_) {
                                      setState(() => _dragging = true);
                                      _hideControlsTimer?.cancel();
                                    },
                                    onChanged: (v) {
                                      setState(() => _dragValueMs = v);
                                    },
                                    onChangeEnd: (v) async {
                                      await controller.seekTo(
                                        Duration(milliseconds: v.round()),
                                      );
                                      if (!mounted) return;
                                      setState(() {
                                        _dragging = false;
                                        _dragValueMs = null;
                                      });
                                      _scheduleHideControls();
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: EdgeInsets.fromLTRB(10.w, 0, 6.w, 2.h),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _formatDuration(position),
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12.sp,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  _formatDuration(duration),
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12.sp,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
