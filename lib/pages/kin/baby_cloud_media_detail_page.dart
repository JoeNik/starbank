import 'dart:io';

import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final path = await Get.find<BabyCloudService>().ensureLocalMediaFile(
      widget.item,
    );
    if (path == null) return;
    final controller = VideoPlayerController.file(File(path));
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (_) {
      await controller.dispose();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(controller),
            IconButton.filled(
              icon: Icon(
                  controller.value.isPlaying ? Icons.pause : Icons.play_arrow),
              onPressed: () {
                setState(() {
                  controller.value.isPlaying
                      ? controller.pause()
                      : controller.play();
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}
