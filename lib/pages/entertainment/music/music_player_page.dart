import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import '../../../controllers/music_player_controller.dart';
import 'dart:math' as math;

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

  @override
  void initState() {
    super.initState();
    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
  }

  @override
  void dispose() {
    _rotateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900], // Dark theme default
      appBar: AppBar(
        title: const Text('正在播放', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
          onPressed: () => Get.back(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.timer, color: Colors.white),
            onPressed: () {
              // Show Timer options
              _showTimerOptions(context);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w),
          child: Column(
            children: [
              SizedBox(height: 40.h),
              // Rotating Disc
              Obx(() {
                if (!_controller.isPlaying.value) {
                  _rotateController.stop();
                } else {
                  _rotateController.repeat();
                }

                final currentTrack = _controller.playlist.isNotEmpty
                    ? _controller.playlist[_controller.currentIndex.value]
                    : null;

                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 600),
                  child: GestureDetector(
                    key: ValueKey('${currentTrack?.id}_${_showLyrics}'),
                    onTap: () {
                      setState(() {
                        _showLyrics = !_showLyrics;
                      });
                    },
                    child: _showLyrics
                        ? Container(
                            height: 280.w,
                            width: double.infinity,
                            padding: EdgeInsets.all(20.w),
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(20.r),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: (currentTrack?.lyricContent?.isNotEmpty ??
                                    false)
                                ? SingleChildScrollView(
                                    physics: const BouncingScrollPhysics(),
                                    child: Text(
                                      currentTrack!.lyricContent!,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: Colors.white.withOpacity(0.9),
                                          fontSize: 16.sp,
                                          height: 2.0,
                                          letterSpacing: 1.2),
                                    ),
                                  )
                                : Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.notes_rounded,
                                          color: Colors.white24, size: 60.sp),
                                      SizedBox(height: 16.h),
                                      Text(
                                        '纯音乐，请欣赏',
                                        style: TextStyle(
                                            color: Colors.white38,
                                            fontSize: 14.sp,
                                            letterSpacing: 2.0),
                                      ),
                                    ],
                                  ),
                          )
                        : AnimatedBuilder(
                            animation: _rotateController,
                            builder: (context, child) {
                              return Transform.rotate(
                                angle: _rotateController.value * 2 * math.pi,
                                child: Container(
                                  width: 280.w,
                                  height: 280.w,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    image: currentTrack?.coverUrl != null
                                        ? DecorationImage(
                                            image: NetworkImage(
                                                currentTrack!.coverUrl!),
                                            fit: BoxFit.cover,
                                          )
                                        : null,
                                    color: Colors.grey[800],
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.5),
                                        blurRadius: 20,
                                        spreadRadius: 5,
                                      )
                                    ],
                                    border: Border.all(
                                        color: Colors.black, width: 8),
                                  ),
                                  child: currentTrack?.coverUrl == null
                                      ? const Center(
                                          child: Icon(Icons.music_note,
                                              color: Colors.white, size: 80))
                                      : null,
                                ),
                              );
                            },
                          ),
                  ),
                );
              }),

              SizedBox(height: 40.h),

              // Info
              Obx(() {
                if (_controller.playlist.isEmpty)
                  return const SizedBox.shrink();
                final track =
                    _controller.playlist[_controller.currentIndex.value];
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  child: Column(
                    key: ValueKey(track.id),
                    children: [
                      Text(
                        track.title,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24.sp,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 8.h),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            track.artist,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 16.sp,
                            ),
                          ),
                          SizedBox(width: 10.w),
                          Obx(() => IconButton(
                                icon: Icon(
                                  _controller.isFavorite(track)
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color: _controller.isFavorite(track)
                                      ? Colors.redAccent
                                      : Colors.white70,
                                ),
                                onPressed: () =>
                                    _controller.toggleFavorite(track),
                              )),
                        ],
                      ),
                    ],
                  ),
                );
              }),

              const Spacer(),

              // Progress Bar
              Obx(() => ProgressBar(
                    progress: _controller.position.value,
                    total: _controller.duration.value,
                    buffered: _controller.buffered.value,
                    onSeek: _controller.seek,
                    baseBarColor: Colors.white24,
                    progressBarColor: Colors.white,
                    bufferedBarColor: Colors.white38,
                    thumbColor: Colors.white,
                    timeLabelTextStyle: const TextStyle(color: Colors.white),
                  )),

              SizedBox(height: 20.h),

              // Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.skip_previous,
                        color: Colors.white, size: 40),
                    onPressed: _controller.playPrevious,
                  ),
                  Obx(() => Container(
                        width: 70.w,
                        height: 70.w,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                        child: IconButton(
                          icon: Icon(
                            _controller.isPlaying.value
                                ? Icons.pause
                                : Icons.play_arrow,
                            color: Colors.black,
                            size: 40,
                          ),
                          onPressed: _controller.togglePlay,
                        ),
                      )),
                  IconButton(
                    icon: const Icon(Icons.skip_next,
                        color: Colors.white, size: 40),
                    onPressed: _controller.playNext,
                  ),
                ],
              ),
              SizedBox(height: 40.h),
            ],
          ),
        ),
      ),
    );
  }

  void _showTimerOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r))),
      builder: (context) {
        return Container(
          padding: EdgeInsets.all(20.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('定时关闭',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18.sp,
                      fontWeight: FontWeight.bold)),
              SizedBox(height: 20.h),
              Wrap(
                spacing: 12.w,
                children: [15, 30, 60]
                    .map((min) => ActionChip(
                          label: Text('$min 分钟'),
                          onPressed: () {
                            _controller.setSleepTimer(min);
                            Get.back();
                            Get.snackbar('定时设置', '$min 分钟后停止播放');
                          },
                        ))
                    .toList(),
              ),
              if (_controller.sleepTimerMinutes.value > 0)
                Padding(
                  padding: EdgeInsets.only(top: 20.h),
                  child: ActionChip(
                    label: const Text('取消定时'),
                    backgroundColor: Colors.redAccent,
                    onPressed: () {
                      _controller.setSleepTimer(0);
                      Get.back();
                    },
                  ),
                )
            ],
          ),
        );
      },
    );
  }
}
