import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import '../../../controllers/music_player_controller.dart';
import '../../../models/music/music_track.dart';
import 'dart:math' as math;
import 'dart:ui';

class MusicPlayerPage extends StatefulWidget {
  const MusicPlayerPage({super.key});

  @override
  State<MusicPlayerPage> createState() => _MusicPlayerPageState();
}

class _MusicPlayerPageState extends State<MusicPlayerPage>
    with SingleTickerProviderStateMixin {
  final MusicPlayerController _controller = Get.find<MusicPlayerController>();
  late AnimationController _rotateController;
  bool _showLyrics = false;

  final ScrollController _lyricScrollController = ScrollController();
  Worker? _lyricWorker;

  @override
  void initState() {
    super.initState();
    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    // Auto-scroll lyrics
    _lyricWorker = ever(_controller.currentLyricIndex, (index) {
      if (_showLyrics &&
          _controller.lyrics.isNotEmpty &&
          _lyricScrollController.hasClients) {
        _scrollToCurrentLyric(index);
      }
    });
  }

  void _scrollToCurrentLyric(int index) {
    // Calculate offset to center the item
    // itemExtent = 50.h. We pad vertical starts with a buffer.
    // Center ~ 150.h from top (approx).
    double offset = index * 50.h;

    // Limits will be handled by animateTo clamping (mostly)
    _lyricScrollController.animateTo(
      offset,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _rotateController.dispose();
    _lyricWorker?.dispose();
    _lyricScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212), // 默认深色背景，防止白屏刺眼
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('正在播放',
            style: TextStyle(color: Colors.white, fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.timer_outlined, color: Colors.white70),
            onPressed: () => _showTimerOptions(context),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Background Layer (Isolated Error Boundary)
          Obx(() {
            String? coverUrl;
            // Defensive Logic for Track Access
            if (_controller.playlist.isNotEmpty &&
                _controller.currentIndex.value >= 0 &&
                _controller.currentIndex.value < _controller.playlist.length) {
              final track =
                  _controller.playlist[_controller.currentIndex.value];
              if (track.coverUrl != null && track.coverUrl!.isNotEmpty) {
                coverUrl = track.coverUrl;
              }
            }

            if (coverUrl == null) {
              return Container(color: const Color(0xFF1E1E1E));
            }

            return Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  coverUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(color: const Color(0xFF1E1E1E));
                  },
                ),
                Container(color: Colors.black.withOpacity(0.7)), // Dim layer
                BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(color: Colors.transparent),
                ),
              ],
            );
          }),

          // 2. Main Content
          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24.w),
              child: Column(
                children: [
                  SizedBox(height: 20.h),

                  // Content Area (Lyrics / Disc)
                  Expanded(child: _buildCenterContent()),

                  SizedBox(height: 30.h),

                  // Track Info
                  _buildTrackInfo(),

                  SizedBox(height: 30.h),

                  // Progress Bar (Defensive)
                  Obx(() {
                    final pos = _controller.position.value;
                    final dur = _controller.duration.value;
                    final buf = _controller.buffered.value;

                    // Ensure Total is never smaller than Progress and never Zero to prevent crashes
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
                      barHeight: 4.0,
                      thumbRadius: 6.0,
                      timeLabelTextStyle:
                          TextStyle(color: Colors.white54, fontSize: 12.sp),
                    );
                  }),

                  SizedBox(height: 20.h),

                  // Controls
                  _buildControls(),

                  SizedBox(height: 48.h),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildCenterContent() {
    return Obx(() {
      // Logic to control rotation animation state
      if (!_controller.isPlaying.value) {
        _rotateController.stop();
      } else {
        _rotateController.repeat();
      }

      MusicTrack? currentTrack;
      if (_controller.playlist.isNotEmpty &&
          _controller.currentIndex.value >= 0 &&
          _controller.currentIndex.value < _controller.playlist.length) {
        currentTrack = _controller.playlist[_controller.currentIndex.value];
      }

      return GestureDetector(
        onTap: () {
          setState(() => _showLyrics = !_showLyrics);
        },
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          child: _showLyrics
              ? _buildLyricsView(currentTrack)
              : _buildCoverView(currentTrack),
        ),
      );
    });
  }

  Widget _buildTrackInfo() {
    return Obx(() {
      if (_controller.playlist.isEmpty) return const SizedBox.shrink();

      final index = _controller.currentIndex.value;
      if (index < 0 || index >= _controller.playlist.length)
        return const SizedBox.shrink();

      final track = _controller.playlist[index];

      return Column(
        children: [
          Text(
            track.title,
            style: TextStyle(
              color: Colors.white,
              fontSize: 22.sp,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 8.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                track.artist,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 15.sp,
                ),
              ),
              SizedBox(width: 8.w),
              // Favorite Button
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(
                  _controller.isFavorite(track)
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: _controller.isFavorite(track)
                      ? Colors.redAccent
                      : Colors.white38,
                  size: 20.sp,
                ),
                onPressed: () => _controller.toggleFavorite(track),
              ),
            ],
          ),
        ],
      );
    });
  }

  Widget _buildControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: Icon(Icons.shuffle, color: Colors.white38, size: 24.sp),
          onPressed: () {},
        ),
        IconButton(
          icon: Icon(Icons.skip_previous_rounded,
              color: Colors.white, size: 42.sp),
          onPressed: _controller.playPrevious,
        ),
        Obx(() => Container(
              width: 72.w,
              height: 72.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.1),
                border: Border.all(color: Colors.white30, width: 1.5),
              ),
              child: IconButton(
                icon: Icon(
                  _controller.isPlaying.value
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 38.sp,
                ),
                onPressed: _controller.togglePlay,
              ),
            )),
        IconButton(
          icon: Icon(Icons.skip_next_rounded, color: Colors.white, size: 42.sp),
          onPressed: _controller.playNext,
        ),
        IconButton(
          icon: Icon(Icons.list_rounded, color: Colors.white38, size: 24.sp),
          onPressed: () {},
        ),
      ],
    );
  }

  Widget _buildCoverView(dynamic currentTrack) {
    return Center(
      child: AnimatedBuilder(
        animation: _rotateController,
        builder: (context, child) {
          return Transform.rotate(
            angle: _rotateController.value * 2 * math.pi,
            child: Container(
              width: 260.w,
              height: 260.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                image: (currentTrack != null && currentTrack.coverUrl != null)
                    ? DecorationImage(
                        image: NetworkImage(currentTrack.coverUrl!),
                        fit: BoxFit.cover,
                      )
                    : null,
                color: Colors.black26,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 30,
                    spreadRadius: 10,
                    offset: const Offset(0, 10),
                  )
                ],
                border: Border.all(color: Colors.white10, width: 8),
              ),
              child: (currentTrack?.coverUrl == null)
                  ? Icon(Icons.music_note_rounded,
                      color: Colors.white24, size: 80.sp)
                  : null,
            ),
          );
        },
      ),
    );
  }

  Widget _buildLyricsView(dynamic currentTrack) {
    // 1. Basic empty check
    if (currentTrack?.lyricContent == null ||
        currentTrack!.lyricContent!.isEmpty) {
      return Container(
        key: const ValueKey('lyrics_empty'),
        margin: EdgeInsets.symmetric(horizontal: 16.w),
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(24.r),
          border: Border.all(color: Colors.white10),
        ),
        child: _buildNoLyricState(),
      );
    }

    final hasParsed = _controller.lyrics.isNotEmpty;

    return Container(
      key: const ValueKey('lyrics_view'),
      width: double.infinity,
      margin: EdgeInsets.symmetric(horizontal: 16.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(color: Colors.white10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24.r),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: ShaderMask(
            shaderCallback: (Rect bounds) {
              return LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.white,
                  Colors.white,
                  Colors.transparent
                ],
                stops: const [0.0, 0.2, 0.8, 1.0],
              ).createShader(bounds);
            },
            blendMode: BlendMode.dstIn,
            child: hasParsed
                ? ListView.builder(
                    controller: _lyricScrollController,
                    itemCount: _controller.lyrics.length,
                    itemExtent: 50.h,
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.symmetric(vertical: 180.h),
                    itemBuilder: (context, index) {
                      return Obx(() {
                        final isActive =
                            index == _controller.currentLyricIndex.value;
                        return Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 300),
                            style: TextStyle(
                              color: isActive ? Colors.white : Colors.white38,
                              fontSize: isActive ? 18.sp : 15.sp,
                              fontWeight: isActive
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              height: 1.5,
                            ),
                            child: Text(
                              _controller.lyrics[index].content,
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        );
                      });
                    },
                  )
                : SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding:
                        EdgeInsets.symmetric(vertical: 40.h, horizontal: 20.w),
                    child: Text(
                      currentTrack!.lyricContent!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 16.sp,
                        height: 1.8,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildNoLyricState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Cute Illustration Placeholder implies music/silence
        Icon(Icons.nightlife_rounded, color: Colors.white24, size: 48.sp),
        SizedBox(height: 16.h),
        Text(
          'Enjoy the vibe ~',
          style: TextStyle(
            color: Colors.white38,
            fontSize: 16.sp,
            fontWeight: FontWeight.w300,
            letterSpacing: 1.5,
          ),
        ),
        SizedBox(height: 8.h),
        Text(
          '暂无歌词',
          style: TextStyle(
            color: Colors.white24,
            fontSize: 12.sp,
          ),
        ),
      ],
    );
  }

  void _showTimerOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent, // Transparent for custom look
      builder: (context) {
        return Container(
          margin: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
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
                children: [15, 30, 45, 60, 90]
                    .map((min) => _buildTimerChip(context, min))
                    .toList()
                  ..add(
                    ActionChip(
                      label: const Text('自定义'),
                      labelStyle: const TextStyle(color: Colors.white),
                      backgroundColor: Colors.grey[800],
                      padding:
                          EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
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
      // Fix: Use explicit dark color for unselected background to avoid white-on-white
      backgroundColor: isSelected ? Colors.white : Colors.grey[800],
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      onPressed: () {
        _controller.setSleepTimer(min);
        Get.back();
        Get.snackbar(
          '定时设置',
          '音乐将在 $min 分钟后暂停',
          backgroundColor: Colors.white12,
          colorText: Colors.white,
          snackPosition: SnackPosition.TOP,
        );
      },
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20.r),
        side: BorderSide.none, // Remove default border
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
        style: const TextStyle(color: Colors.black), // Force black text
        decoration: InputDecoration(
          hintText: '输入分钟数 (如 20)',
          hintStyle: const TextStyle(color: Colors.black38), // Visible hint
          suffixText: '分钟',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r)),
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
            Get.snackbar(
              '定时设置',
              '音乐将在 $min 分钟后暂停',
              backgroundColor: Colors.white12,
              colorText: Colors.white,
            );
          } else {
            Get.snackbar('输入错误', '请输入有效的分钟数', backgroundColor: Colors.red[100]);
          }
        },
        child: const Text('确定'),
      ),
      radius: 16.r,
      backgroundColor: Colors.white,
    );
  }
}
