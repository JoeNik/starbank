import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:palette_generator/palette_generator.dart';
import '../../../controllers/music_player_controller.dart';
import '../../../models/music/music_track.dart';
import '../../../services/chksz_music_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/toast_utils.dart';
import '../../../widgets/music_cover_image.dart';

class MusicPlayerPage extends StatefulWidget {
  const MusicPlayerPage({super.key});

  @override
  State<MusicPlayerPage> createState() => _MusicPlayerPageState();
}

class _MusicPlayerPageState extends State<MusicPlayerPage> {
  // late 获取:配合 build 顶部的注册检查,服务缺失时优雅降级而不是崩溃
  late final MusicPlayerController _controller =
      Get.find<MusicPlayerController>();

  static const Color _baseBg = Color(0xFF14141A);

  // 封面主色(经压暗处理),驱动整页渐变背景与彩色投影
  Color? _dominantColor;
  String _lastColorSongKey = '';

  bool _showLyrics = false;
  bool _lyricsAutoScroll = true;

  final ScrollController _lyricScrollController = ScrollController();
  Worker? _lyricIndexWorker;
  Worker? _trackChangeWorker;

  @override
  void initState() {
    super.initState();
    _lyricIndexWorker = ever(_controller.currentLyricIndex, (index) {
      if (_showLyrics && _lyricsAutoScroll) _scrollToLyric(index);
    });
    // 歌曲切换(索引变化或队列整体刷新)时重新取色
    _trackChangeWorker = ever<int>(_controller.currentIndex, (_) {
      _maybeUpdateColor();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeUpdateColor());
  }

  @override
  void dispose() {
    _lyricIndexWorker?.dispose();
    _trackChangeWorker?.dispose();
    _lyricScrollController.dispose();
    super.dispose();
  }

  MusicTrack? _currentTrack() {
    final list = _controller.playlist;
    final index = _controller.currentIndex.value;
    if (list.isEmpty || index < 0 || index >= list.length) return null;
    return list[index];
  }

  void _maybeUpdateColor() {
    final track = _currentTrack();
    final key = track == null ? '' : '${track.platform}_${track.id}';
    // 同一首歌只提取一次主色,避免图像处理开销
    if (key == _lastColorSongKey) return;
    _lastColorSongKey = key;
    _extractColor(track?.coverUrl);
  }

  Future<void> _extractColor(String? coverUrl) async {
    Color? extracted;
    if (coverUrl != null && coverUrl.isNotEmpty) {
      try {
        final generator = await PaletteGenerator.fromImageProvider(
          NetworkImage(coverUrl),
          maximumColorCount: 16,
        );
        extracted = generator.vibrantColor?.color ??
            generator.dominantColor?.color ??
            generator.mutedColor?.color;
      } catch (_) {
        // 封面加载失败时保持兜底色
      }
    }
    if (!mounted) return;
    setState(() {
      _dominantColor = extracted == null ? null : _darken(extracted);
    });
  }

  /// 压暗并限定亮度区间,保证深色背景下文字可读
  Color _darken(Color color) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness * 0.55).clamp(0.12, 0.45))
        .toColor();
  }

  Color get _baseColor => _dominantColor ?? _darken(AppTheme.primary);

  void _scrollToLyric(int index) {
    if (!_lyricScrollController.hasClients) return;
    final offset = (index * 60.h)
        .clamp(0.0, _lyricScrollController.position.maxScrollExtent);
    // jumpTo 瞬时定位:快歌时 animateTo 的动画会追不上当前行
    _lyricScrollController.jumpTo(offset);
  }

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<MusicPlayerController>()) {
      return Scaffold(
        backgroundColor: _baseBg,
        body: Center(
          child: Text(
            '音乐服务未就绪\n请完全退出应用后重新打开',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 14.sp),
          ),
        ),
      );
    }
    return _buildScaffold(context);
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: _baseBg,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white70),
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
          onPressed: () => Get.back(),
        ),
        centerTitle: true,
        title: Obx(() {
          final count = _controller.playlist.length;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('正在播放',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12.sp,
                      letterSpacing: 2)),
              Text(
                count > 1
                    ? '播放列表 (${_controller.currentIndex.value + 1}/$count)'
                    : '单曲播放',
                style: TextStyle(color: Colors.white38, fontSize: 10.sp),
              ),
            ],
          );
        }),
        actions: [
          IconButton(
            icon: const Icon(Icons.queue_music_rounded, color: Colors.white70),
            onPressed: () => _showQueueSheet(context),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 封面主色渐变背景
          AnimatedContainer(
            duration: const Duration(milliseconds: 600),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _baseColor.withOpacity(0.55),
                  _baseColor.withOpacity(0.18),
                  _baseBg,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24.w),
              child: Column(
                children: [
                  SizedBox(height: 8.h),
                  // 中央内容区自适应伸缩,吸收所有剩余/不足空间
                  Expanded(child: _buildCenterContent()),
                  _buildBottomCluster(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // === 底部信息与控制区(紧凑固定高度) ===

  Widget _buildBottomCluster() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTrackInfo(),
        SizedBox(height: 14.h),
        _buildProgress(),
        SizedBox(height: 10.h),
        _buildControls(),
        SizedBox(height: 4.h),
        _buildSecondaryRow(),
        SizedBox(height: 10.h),
      ],
    );
  }

  // === 中央内容区:封面 / 歌词 二选一 ===

  Widget _buildCenterContent() {
    return GestureDetector(
      onVerticalDragUpdate: (_) {
        // 用户手动拖动歌词时暂停自动滚动
        if (_showLyrics && !_lyricsAutoScroll) return;
        if (_showLyrics) _lyricsAutoScroll = false;
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: _showLyrics ? _buildLyricsView() : _buildCoverView(),
      ),
    );
  }

  Widget _buildCoverView() {
    return Obx(() {
      final track = _currentTrack();
      final hasCover =
          track?.coverUrl != null && track!.coverUrl!.isNotEmpty;

      return Center(
        key: const ValueKey('cover'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 自适应正方形:取剩余宽高中较小者,任何屏幕都不会溢出
            Flexible(
              child: LayoutBuilder(builder: (context, constraints) {
                final side = math.min(
                    constraints.maxWidth, constraints.maxHeight);
                return SizedBox(
                  width: side,
                  height: side,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28.r),
                      boxShadow: [
                        BoxShadow(
                          color: _baseColor.withOpacity(0.35),
                          blurRadius: 40,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28.r),
                      child: hasCover
                          ? Image.network(
                              track.coverUrl!,
                              fit: BoxFit.cover,
                              headers: coverHeadersFor(track.coverUrl),
                              errorBuilder: (context, error, stackTrace) =>
                                  _defaultCover(track.platform),
                            )
                          : _defaultCover(track?.platform),
                    ),
                  ),
                );
              }),
            ),
            SizedBox(height: 12.h),
            Text('轻触歌词图标查看歌词',
                style: TextStyle(color: Colors.white24, fontSize: 11.sp)),
          ],
        ),
      );
    });
  }

  Widget _defaultCover(String? platform) {
    return Container(
      color: _baseColor.withOpacity(0.4),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_note_rounded,
                color: Colors.white24, size: 56.sp),
            SizedBox(height: 8.h),
            Text(platform ?? '',
                style: TextStyle(color: Colors.white24, fontSize: 12.sp)),
          ],
        ),
      ),
    );
  }

  Widget _buildLyricsView() {
    return Obx(() {
      if (_controller.lyrics.isEmpty) {
        return Center(
          key: const ValueKey('lyrics_empty'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lyrics_outlined,
                  color: Colors.white24, size: 48.sp),
              SizedBox(height: 16.h),
              Text('暂无歌词',
                  style: TextStyle(
                      color: Colors.white38,
                      fontSize: 15.sp,
                      letterSpacing: 1.5)),
              SizedBox(height: 6.h),
              Text('该歌曲暂时没有可用歌词',
                  style:
                      TextStyle(color: Colors.white24, fontSize: 11.sp)),
            ],
          ),
        );
      }

      return ListView.builder(
        key: const ValueKey('lyrics_view'),
        controller: _lyricScrollController,
        itemExtent: 60.h,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(
            vertical: MediaQuery.of(context).size.height * 0.28),
        itemCount: _controller.lyrics.length,
        itemBuilder: (context, index) {
          final line = _controller.lyrics[index];
          return GestureDetector(
            onTap: () {
              // 点击歌词跳转到对应进度,并恢复自动滚动
              _controller.seek(line.startTime);
              _lyricsAutoScroll = true;
            },
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Obx(() {
                    final isActive =
                        index == _controller.currentLyricIndex.value;
                    return AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 300),
                      style: TextStyle(
                        color: isActive
                            ? Colors.white
                            : Colors.white.withOpacity(0.4),
                        fontSize: isActive ? 17.sp : 14.sp,
                        fontWeight:
                            isActive ? FontWeight.bold : FontWeight.normal,
                        height: 1.25,
                      ),
                      child: Text(
                        line.content,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }),
                  if (line.translation != null &&
                      line.translation!.isNotEmpty)
                    Text(
                      line.translation!,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.3),
                          fontSize: 10.sp,
                          height: 1.2),
                    ),
                ],
              ),
            ),
          );
        },
      );
    });
  }

  // === 歌曲信息 + 音质徽标 ===

  Widget _buildTrackInfo() {
    return Obx(() {
      final track = _currentTrack();
      if (track == null) return const SizedBox.shrink();

      final qualityLabel = ChkSzMusicService.qualityLabel(
          _controller.currentAudioQuality.value);

      return Column(
        children: [
          Text(
            track.title,
            style: TextStyle(
              color: Colors.white,
              fontSize: 20.sp,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 4.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  track.album != null && track.album!.isNotEmpty
                      ? '${track.artist} - ${track.album}'
                      : track.artist,
                  style: TextStyle(color: Colors.white60, fontSize: 13.sp),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (qualityLabel.isNotEmpty) ...[
                SizedBox(width: 8.w),
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 6.w, vertical: 1.h),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6.r),
                  ),
                  child: Text(
                    qualityLabel,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ],
          ),
        ],
      );
    });
  }

  // === 进度条 ===

  Widget _buildProgress() {
    return Obx(() {
      final pos = _controller.position.value;
      final dur = _controller.duration.value;
      final buf = _controller.buffered.value;

      // Total 永远不小于 Progress 且不为零,防崩溃
      final safeTotal =
          dur > pos ? dur : (pos + const Duration(seconds: 1));
      final safeBuffered = buf <= safeTotal ? buf : safeTotal;

      return ProgressBar(
        progress: pos,
        total: safeTotal,
        buffered: safeBuffered,
        onSeek: _controller.seek,
        baseBarColor: Colors.white12,
        progressBarColor: Colors.white,
        bufferedBarColor: Colors.white24,
        thumbColor: Colors.white,
        barHeight: 3.0,
        thumbRadius: 6.0,
        timeLabelLocation: TimeLabelLocation.below,
        timeLabelTextStyle:
            TextStyle(color: Colors.white54, fontSize: 11.sp),
      );
    });
  }

  // === 主控制区 ===

  Widget _buildControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Mode Switch: Sequence -> Shuffle -> Single
        Obx(() {
          IconData icon;
          Color color = Colors.white38;
          switch (_controller.playMode.value) {
            case PlayMode.sequence:
              icon = Icons.repeat_rounded;
              color = Colors.white38;
              break;
            case PlayMode.shuffle:
              icon = Icons.shuffle_rounded;
              color = Colors.white;
              break;
            case PlayMode.single:
              icon = Icons.repeat_one_rounded;
              color = Colors.white;
              break;
          }
          return IconButton(
            icon: Icon(icon, color: color, size: 24.sp),
            onPressed: () => _controller.changePlayMode(),
          );
        }),
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: Icon(Icons.skip_previous_rounded,
              color: Colors.white, size: 44.sp),
          onPressed: _controller.playPrevious,
        ),
        // 播放/暂停大按钮
        Obx(() => Container(
              width: 64.w,
              height: 64.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primary,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withOpacity(0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: animation,
                  child: child,
                ),
                child: IconButton(
                  key: ValueKey(_controller.isPlaying.value),
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    _controller.isPlaying.value
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 38.sp,
                  ),
                  onPressed: _controller.togglePlay,
                ),
              ),
            )),
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: Icon(Icons.skip_next_rounded,
              color: Colors.white, size: 44.sp),
          onPressed: () => _controller.playNext(),
        ),
        // 歌词开关是本页 setState 驱动的本地状态,不能用 Obx 包装:
        // Obx 内未读取任何 Rx 变量会在构建期抛 "improper use of GetX" 导致整页崩溃
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: Icon(
            Icons.lyrics_rounded,
            color: _showLyrics ? Colors.white : Colors.white38,
            size: 24.sp,
          ),
          onPressed: () {
            setState(() => _showLyrics = !_showLyrics);
            // 切到歌词时立即定位到当前行
            if (_showLyrics) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _scrollToLyric(_controller.currentLyricIndex.value);
              });
            }
          },
        ),
      ],
    );
  }

  // === 次要功能区:收藏 / 定时 ===

  Widget _buildSecondaryRow() {
    return Obx(() {
      final track = _currentTrack();
      final isFav = track != null && _controller.isFavorite(track);
      final timerText = _controller.sleepTimerMinutes.value > 0
          ? '${_controller.sleepTimerMinutes.value} 分钟后停止'
          : '定时关闭';

      // FittedBox 兜底:窄屏/大字体下整体缩放,绝不溢出
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
          TextButton.icon(
            onPressed: track == null
                ? null
                : () {
                    _controller.toggleFavorite(track);
                    ToastUtils.showSuccess(isFav ? '已取消收藏' : '已加入收藏');
                  },
            icon: Icon(
              isFav ? Icons.favorite : Icons.favorite_border,
              size: 18.sp,
              color: isFav ? Colors.redAccent : Colors.white54,
            ),
            label: Text(isFav ? '已收藏' : '收藏',
                style: TextStyle(color: Colors.white54, fontSize: 12.sp)),
          ),
          SizedBox(width: 24.w),
          TextButton.icon(
            onPressed: track == null || _controller.isDownloading.value
                ? null
                : () => _controller.downloadTrack(track),
            icon: _controller.isDownloading.value
                ? SizedBox(
                    width: 18.sp,
                    height: 18.sp,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white54),
                  )
                : Icon(Icons.download_rounded,
                    size: 18.sp, color: Colors.white54),
            label: Text('下载',
                style: TextStyle(color: Colors.white54, fontSize: 12.sp)),
          ),
          SizedBox(width: 24.w),
          TextButton.icon(
            onPressed: () => _showTimerOptions(context),
            icon: Icon(Icons.timer_outlined,
                size: 18.sp,
                color: _controller.sleepTimerMinutes.value > 0
                    ? AppTheme.primary
                    : Colors.white54),
            label: Text(timerText,
                style: TextStyle(color: Colors.white54, fontSize: 12.sp)),
          ),
          ],
        ),
      );
    });
  }

  // === 播放队列面板(可拖拽) ===

  void _showQueueSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E26),
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // 拖拽指示条
                  Container(
                    margin: EdgeInsets.symmetric(vertical: 10.h),
                    width: 40.w,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20.w),
                    child: Obx(() => Row(
                          children: [
                            Text(
                              '播放队列 (${_controller.playlist.length})',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16.sp,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            if (_controller.playlist.isNotEmpty)
                              TextButton(
                                onPressed: () {
                                  _controller.clearPlaylist();
                                },
                                child: Text('清空',
                                    style: TextStyle(
                                        color: Colors.white38,
                                        fontSize: 13.sp)),
                              ),
                          ],
                        )),
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  Expanded(
                    child: Obx(() {
                      if (_controller.playlist.isEmpty) {
                        return Center(
                          child: Text('队列为空',
                              style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 14.sp)),
                        );
                      }
                      return ListView.builder(
                        controller: scrollController,
                        padding: EdgeInsets.symmetric(vertical: 10.h),
                        itemCount: _controller.playlist.length,
                        itemBuilder: (context, index) {
                          final track = _controller.playlist[index];
                          return Obx(() {
                            final isCurrent =
                                index == _controller.currentIndex.value;
                            return ListTile(
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16.w, vertical: 0),
                              leading: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius:
                                        BorderRadius.circular(10.r),
                                    child: Container(
                                      width: 44.w,
                                      height: 44.w,
                                      color: Colors.white10,
                                      child: (track.coverUrl != null &&
                                              track.coverUrl!.isNotEmpty)
                                          ? Image.network(
                                              track.coverUrl!,
                                              fit: BoxFit.cover,
                                              headers: coverHeadersFor(
                                                  track.coverUrl),
                                              errorBuilder: (ctx, err, st) =>
                                                  Icon(Icons.music_note,
                                                      color: Colors.white24,
                                                      size: 20.sp),
                                            )
                                          : Icon(Icons.music_note,
                                              color: Colors.white24,
                                              size: 20.sp),
                                    ),
                                  ),
                                  if (isCurrent)
                                    Positioned.fill(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.black38,
                                          borderRadius:
                                              BorderRadius.circular(10.r),
                                        ),
                                        child: Icon(Icons.equalizer_rounded,
                                            color: AppTheme.primary,
                                            size: 20.sp),
                                      ),
                                    ),
                                ],
                              ),
                              title: Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isCurrent
                                      ? AppTheme.primary
                                      : Colors.white70,
                                  fontSize: 15.sp,
                                  fontWeight: isCurrent
                                      ? FontWeight.w700
                                      : FontWeight.normal,
                                ),
                              ),
                              subtitle: Text(
                                '${track.artist} - ${track.album ?? ""}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: isCurrent
                                        ? AppTheme.primary
                                            .withOpacity(0.7)
                                        : Colors.white38,
                                    fontSize: 12.sp),
                              ),
                              trailing: IconButton(
                                icon: Icon(Icons.close_rounded,
                                    color: Colors.white30, size: 18.sp),
                                onPressed: () =>
                                    _controller.removeTrackAt(index),
                              ),
                              onTap: () {
                                if (!isCurrent) {
                                  _controller.playTrack(track);
                                }
                              },
                            );
                          });
                        },
                      );
                    }),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // === 睡眠定时 ===

  void _showTimerOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          margin: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E26),
            borderRadius: BorderRadius.circular(24.r),
          ),
          padding: EdgeInsets.all(24.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('定时关闭',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18.sp,
                          fontWeight: FontWeight.bold)),
                  if (_controller.sleepTimerMinutes.value > 0)
                    TextButton(
                      onPressed: () {
                        _controller.setSleepTimer(0);
                        Get.back();
                      },
                      child: const Text('取消定时',
                          style: TextStyle(color: Colors.redAccent)),
                    ),
                ],
              ),
              SizedBox(height: 24.h),
              Wrap(
                spacing: 12.w,
                runSpacing: 12.h,
                alignment: WrapAlignment.start,
                children: [10, 15, 20, 30, 40]
                    .map((min) => _buildTimerChip(context, min))
                    .toList()
                  ..add(
                    ActionChip(
                      label: const Text('自定义'),
                      labelStyle: const TextStyle(color: Colors.white),
                      backgroundColor: Colors.grey[800],
                      padding: EdgeInsets.symmetric(
                          horizontal: 12.w, vertical: 8.h),
                      onPressed: () {
                        Get.back(); // close sheet first
                        _showCustomTimerDialog(context);
                      },
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20.r),
                        side: BorderSide.none,
                      ),
                    ),
                  ),
              ),
              SizedBox(height: 12.h),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTimerChip(BuildContext context, int min) {
    final isSelected = _controller.sleepTimerMinutes.value == min;
    return ActionChip(
      label: Text('$min 分钟'),
      labelStyle: TextStyle(
        color: isSelected ? Colors.black : Colors.white,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      backgroundColor: isSelected ? Colors.white : Colors.grey[800],
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      onPressed: () {
        _controller.setSleepTimer(min);
        Get.back();
        ToastUtils.showSuccess('音乐将在 $min 分钟后暂停', title: '定时设置');
      },
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20.r),
        side: BorderSide.none,
      ),
    );
  }

  void _showCustomTimerDialog(BuildContext context) {
    final TextEditingController inputCtrl = TextEditingController();
    Get.defaultDialog(
      title: '自定义时间',
      titleStyle: TextStyle(
          color: Colors.black87, fontSize: 18.sp, fontWeight: FontWeight.bold),
      contentPadding: EdgeInsets.all(20.w),
      content: TextField(
        controller: inputCtrl,
        keyboardType: TextInputType.number,
        autofocus: true,
        style: const TextStyle(color: Colors.black),
        decoration: InputDecoration(
          hintText: '输入分钟数 (如 20)',
          hintStyle: const TextStyle(color: Colors.black38),
          suffixText: '分钟',
          border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(12.r)),
          filled: true,
          fillColor: Colors.grey[100],
        ),
      ),
      confirm: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 10.h),
        ),
        onPressed: () {
          final int? min = int.tryParse(inputCtrl.text);
          if (min != null && min > 0) {
            _controller.setSleepTimer(min);
            Get.back();
            ToastUtils.showSuccess('音乐将在 $min 分钟后暂停', title: '定时设置');
          } else {
            ToastUtils.showError('请输入有效的分钟数', title: '输入错误');
          }
        },
        child: const Text('确定'),
      ),
      radius: 16.r,
      backgroundColor: Colors.white,
    );
  }
}
