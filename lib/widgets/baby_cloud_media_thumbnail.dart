import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../models/baby_cloud_media.dart';
import '../services/baby_cloud_service.dart';

class BabyCloudMediaThumbnail extends StatefulWidget {
  const BabyCloudMediaThumbnail({
    super.key,
    required this.item,
    this.fit = BoxFit.cover,
    this.backgroundColor,
    this.preferOriginal = false,
    this.showVideoBadge = true,
  });

  final BabyCloudMedia item;
  final BoxFit fit;
  final Color? backgroundColor;
  final bool preferOriginal;
  final bool showVideoBadge;

  @override
  State<BabyCloudMediaThumbnail> createState() =>
      _BabyCloudMediaThumbnailState();
}

class _BabyCloudMediaThumbnailState extends State<BabyCloudMediaThumbnail>
    with SingleTickerProviderStateMixin {
  final _cloud = Get.find<BabyCloudService>();
  late final AnimationController _retryController;
  Future<String?>? _downloadFuture;
  Object? _lastError;
  bool _manualOriginalFallback = false;
  bool _forceThumbnailRetry = false;

  @override
  void initState() {
    super.initState();
    _retryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    _prepare();
  }

  @override
  void dispose() {
    _retryController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant BabyCloudMediaThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.ref != widget.item.ref ||
        oldWidget.item.localPath != widget.item.localPath ||
        oldWidget.item.localThumbnailPath != widget.item.localThumbnailPath ||
        oldWidget.preferOriginal != widget.preferOriginal) {
      _manualOriginalFallback = false;
      _prepare();
    }
  }

  void _prepare() {
    final forceThumbnailRetry = _forceThumbnailRetry;
    _forceThumbnailRetry = false;
    _downloadFuture = null;
    _lastError = null;
    if (!widget.preferOriginal) {
      if (widget.item.isAudio || widget.item.isDiary) {
        return;
      }
      if (_readableThumbnailPath() != null) return;
      if (!widget.item.isVideo && _readableOriginalPath() != null) {
        _downloadFuture = _cloud.ensureLocalThumbnailFile(
          widget.item,
          forceRemote: forceThumbnailRetry,
        );
        return;
      }
      if (_manualOriginalFallback && !widget.item.isVideo) {
        _downloadFuture = _cloud.ensureLocalMediaFile(widget.item);
        return;
      }
      _downloadFuture = _cloud.ensureLocalThumbnailFile(
        widget.item,
        forceRemote: forceThumbnailRetry,
      );
      return;
    }
    if (_readableOriginalPath() != null) return;
    _downloadFuture = _cloud.ensureLocalMediaFile(widget.item);
  }

  @override
  Widget build(BuildContext context) {
    final imagePath = _bestImagePath();
    if (imagePath != null &&
        (!widget.preferOriginal || _downloadFuture == null)) {
      return _withVideoBadge(_image(imagePath));
    }

    final future = _downloadFuture;
    if (future == null) return _withVideoBadge(_fallback());

    return FutureBuilder<String?>(
      future: future,
      builder: (_, snapshot) {
        if (snapshot.hasError) _lastError = snapshot.error;
        final downloaded = snapshot.data;
        if (downloaded != null && _exists(downloaded)) {
          return _withVideoBadge(_image(downloaded));
        }
        if (imagePath != null) {
          return Stack(
            fit: StackFit.expand,
            children: [
              _image(imagePath),
              if (snapshot.connectionState != ConnectionState.done)
                const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          );
        }
        return _withVideoBadge(
          _fallback(
            loading: snapshot.connectionState != ConnectionState.done,
            failed: snapshot.connectionState == ConnectionState.done,
          ),
        );
      },
    );
  }

  Widget _image(String path) {
    return Image.file(
      File(path),
      fit: widget.fit,
      cacheWidth: _decodeCacheWidth(),
      excludeFromSemantics: true,
      gaplessPlayback: true,
      filterQuality: FilterQuality.low,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return Stack(
          fit: StackFit.expand,
          children: [
            _fallback(loading: true),
            Opacity(opacity: 0, child: child),
          ],
        );
      },
      errorBuilder: (_, error, __) {
        _lastError = error;
        return _fallback(failed: true);
      },
    );
  }

  int? _decodeCacheWidth() {
    final media = MediaQuery.maybeOf(context);
    final dpr = media?.devicePixelRatio ?? 1;
    final logicalWidth = widget.preferOriginal
        ? media?.size.width ?? 360
        : media?.size.shortestSide ?? 180;
    final target = (logicalWidth * dpr * (widget.preferOriginal ? 2.0 : 1.25))
        .round();
    final maxWidth = widget.preferOriginal ? 2200 : 900;
    return math.min(math.max(target, 240), maxWidth);
  }

  Widget _withVideoBadge(Widget child) {
    if ((!widget.item.isVideo && !widget.item.isAudio) ||
        !widget.showVideoBadge) {
      return child;
    }
    final isVideo = widget.item.isVideo;
    final badgeColor =
        isVideo ? const Color(0xFFE85D4A) : const Color(0xFF4C70E8);
    final badgeIcon = isVideo ? Icons.videocam_rounded : Icons.mic_rounded;
    final badgeText = isVideo ? '视频' : '录音';
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.18),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.34),
                  ],
                  stops: const [0, 0.46, 1],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 6.w,
          right: 6.w,
          child: _MediaTypeBadge(
            color: badgeColor,
            icon: badgeIcon,
            text: badgeText,
          ),
        ),
        Center(
          child: Container(
            width: 42.w,
            height: 42.w,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.52),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.82),
                width: 1.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.34),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              isVideo ? Icons.play_arrow_rounded : Icons.graphic_eq_rounded,
              color: Colors.white,
              size: isVideo ? 30.sp : 24.sp,
            ),
          ),
        ),
      ],
    );
  }

  Widget _fallback({bool loading = false, bool failed = false}) {
    final canRetry = failed || _lastError != null;
    return Container(
      color: widget.backgroundColor ?? Colors.grey.shade200,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: loading
                ? const CircularProgressIndicator(strokeWidth: 2)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.item.isVideo
                            ? Icons.videocam_outlined
                            : widget.item.isAudio
                                ? Icons.mic_none_outlined
                                : widget.item.isDiary
                                    ? Icons.notes_outlined
                                    : Icons.image_not_supported_outlined,
                        color: widget.backgroundColor == Colors.black
                            ? Colors.white54
                            : Colors.grey.shade500,
                        size: 28.sp,
                      ),
                      if (failed || _lastError != null) ...[
                        SizedBox(height: 4.h),
                        Text(
                          '无法加载',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: widget.backgroundColor == Colors.black
                                ? Colors.white54
                                : Colors.grey.shade600,
                            fontSize: 10.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
          if (canRetry)
            Positioned(
              right: 6.w,
              bottom: 6.w,
              child: _retryButton(),
            ),
        ],
      ),
    );
  }

  Widget _retryButton() {
    final loadOriginal = !widget.preferOriginal &&
        !widget.item.isVideo &&
        widget.item.thumbnailRemotePath?.trim().isNotEmpty != true;
    return Tooltip(
      message: loadOriginal ? '加载原图' : '重新加载缩略图',
      child: InkWell(
        onTap: _retryLoad,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
          decoration: BoxDecoration(
            color: widget.backgroundColor == Colors.black
                ? Colors.white.withValues(alpha: 0.14)
                : Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: widget.backgroundColor == Colors.black
                  ? Colors.white24
                  : Colors.grey.shade300,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _retryController,
                builder: (context, child) {
                  final eased = Curves.easeOutBack.transform(
                    _retryController.value.clamp(0.0, 1.0).toDouble(),
                  );
                  return Transform.rotate(
                    angle: _retryController.value * math.pi * 2,
                    child: Transform.scale(
                      scale: 1 + eased * 0.16,
                      child: child,
                    ),
                  );
                },
                child: Icon(
                  loadOriginal ? Icons.image_search_outlined : Icons.refresh,
                  size: 13.sp,
                  color: widget.backgroundColor == Colors.black
                      ? Colors.white70
                      : Colors.grey.shade700,
                ),
              ),
              SizedBox(width: 3.w),
              Text(
                loadOriginal ? '原图' : '重试',
                style: TextStyle(
                  fontSize: 10.sp,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  color: widget.backgroundColor == Colors.black
                      ? Colors.white70
                      : Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _retryLoad() {
    _retryController.forward(from: 0);
    setState(() {
      _lastError = null;
      if (!widget.preferOriginal &&
          !widget.item.isVideo &&
          widget.item.thumbnailRemotePath?.trim().isNotEmpty != true) {
        _manualOriginalFallback = true;
      } else {
        _forceThumbnailRetry = true;
      }
      _prepare();
    });
  }

  String? _bestImagePath() {
    if (!widget.preferOriginal) {
      final thumb = _readableThumbnailPath();
      if (thumb != null) return thumb;
    }

    final original = _readableOriginalPath();
    if (original != null && !widget.item.isVideo) return original;

    final thumb = _readableThumbnailPath();
    if (thumb != null) return thumb;
    return null;
  }

  String? _readableOriginalPath() {
    final path = widget.item.localPath;
    if (path == null || path.trim().isEmpty) return null;
    return _exists(path) ? path : null;
  }

  String? _readableThumbnailPath() {
    final path = widget.item.localThumbnailPath;
    if (path == null || path.trim().isEmpty) return null;
    final original = widget.item.localPath;
    if (!widget.item.isVideo &&
        original != null &&
        original.trim().isNotEmpty &&
        path == original) {
      return null;
    }
    return _exists(path) ? path : null;
  }

  bool _exists(String path) {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }
}

class _MediaTypeBadge extends StatelessWidget {
  const _MediaTypeBadge({
    required this.color,
    required this.icon,
    required this.text,
  });

  final Color color;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.78)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 3.h),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11.sp, color: Colors.white),
            SizedBox(width: 3.w),
            Text(
              text,
              style: TextStyle(
                color: Colors.white,
                fontSize: 10.sp,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
