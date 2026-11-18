import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import '../../../controllers/music_player_controller.dart';
import '../../../controllers/app_mode_controller.dart';
import '../../../models/music/music_track.dart';
import '../../../services/chksz_music_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/memphis_widgets.dart';
import '../../../widgets/module_background_scene.dart';
import '../../../widgets/toast_utils.dart';
import '../../../widgets/music_cover_image.dart';

/// 通用「收藏到多个歌单」底部弹窗（播放器页、音乐首页、歌单详情页共用）
/// 支持同时勾选将歌曲加入「❤️ 我的最爱」及任意多个自定义歌单，并支持当场新建歌单。
void showAddToPlaylistsSheet(BuildContext context, MusicTrack track) {
  if (!Get.isRegistered<MusicPlayerController>()) return;
  final controller = Get.find<MusicPlayerController>();
  if (Get.isRegistered<AppModeController>() &&
      Get.find<AppModeController>().isChildMode) {
    ToastUtils.showInfo('儿童模式下无法修改歌单，请先切换到家长模式');
    return;
  }

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetCtx) {
      return Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetCtx).size.height * 0.72,
        ),
        margin: EdgeInsets.fromLTRB(
          12.w,
          0,
          12.w,
          MediaQuery.of(sheetCtx).padding.bottom + 12.h,
        ),
        padding: EdgeInsets.all(18.w),
        decoration: BoxDecoration(
          color: AppTheme.cream,
          borderRadius: BorderRadius.circular(26.r),
          border: AppTheme.border(),
          boxShadow: AppTheme.paperShadow(h: 14.0),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部歌曲信息 + 新建歌单按钮
            Row(
              children: [
                Container(
                  width: 42.w,
                  height: 42.w,
                  decoration: BoxDecoration(
                    color: AppTheme.tealSoft,
                    borderRadius: BorderRadius.circular(10.r),
                    border: AppTheme.border(),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9.r),
                    child: (track.coverUrl != null &&
                            track.coverUrl!.isNotEmpty)
                        ? Image.network(
                            track.coverUrl!,
                            fit: BoxFit.cover,
                            headers: coverHeadersFor(track.coverUrl),
                            errorBuilder: (_, __, ___) => const Icon(
                                Icons.music_note_rounded,
                                color: AppTheme.tomato),
                          )
                        : const Icon(Icons.music_note_rounded,
                            color: AppTheme.tomato),
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '收藏到歌单',
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.ink,
                        ),
                      ),
                      Text(
                        '${track.title} · ${track.artist}（可多选）',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5.sp,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSub,
                        ),
                      ),
                    ],
                  ),
                ),
                MemphisButton(
                  text: '＋ 新建歌单',
                  color: AppTheme.yellow,
                  textColor: AppTheme.ink,
                  borderRadius: 999,
                  fontSize: 12.sp,
                  padding:
                      EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                  onTap: () => _showCreatePlaylistDialog(
                    sheetCtx,
                    controller,
                    initialTrack: track,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            const Divider(height: 1),
            SizedBox(height: 8.h),

            // 歌单多选列表
            Flexible(
              child: Obx(() {
                final isFav = controller.isFavorite(track);
                final customList = controller.customPlaylists;

                return ListView(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  children: [
                    // 1. 默认「我的最爱」
                    _playlistCheckTile(
                      title: '❤️ 我的最爱（默认收藏）',
                      subtitle: '共 ${controller.favorites.length} 首歌曲',
                      checked: isFav,
                      accentColor: AppTheme.tomato,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        controller.toggleFavorite(track);
                      },
                    ),
                    // 2. 所有自定义歌单
                    ...customList.map((pl) {
                      final inPl = controller.isTrackInPlaylist(pl.id, track);
                      return _playlistCheckTile(
                        title: pl.name,
                        subtitle: '共 ${pl.tracks.length} 首歌曲',
                        checked: inPl,
                        accentColor: AppTheme.teal,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          controller.toggleTrackInPlaylist(pl.id, track);
                        },
                      );
                    }),
                  ],
                );
              }),
            ),
            SizedBox(height: 10.h),
            MemphisButton(
              text: '完成',
              color: AppTheme.tomato,
              textColor: AppTheme.paperWhite,
              borderRadius: 14.r,
              onTap: () => Navigator.of(sheetCtx).pop(),
            ),
          ],
        ),
      );
    },
  );
}

Widget _playlistCheckTile({
  required String title,
  required String subtitle,
  required bool checked,
  required Color accentColor,
  required VoidCallback onTap,
}) {
  return Padding(
    padding: EdgeInsets.only(bottom: 8.h),
    child: BouncyTap(
      pressedScale: 0.97,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: checked ? AppTheme.yellowSoft : AppTheme.paperWhite,
          borderRadius: BorderRadius.circular(16.r),
          border: AppTheme.border(),
          boxShadow: AppTheme.paperShadow(h: checked ? 6.0 : 3.0),
        ),
        child: Row(
          children: [
            Container(
              width: 26.w,
              height: 26.w,
              decoration: BoxDecoration(
                color: checked ? accentColor : AppTheme.creamDeep,
                shape: BoxShape.circle,
                border: AppTheme.border(),
              ),
              child: Icon(
                checked ? Icons.check_rounded : Icons.add_rounded,
                size: 16.sp,
                color: checked ? AppTheme.paperWhite : AppTheme.ink,
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.ink,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSub,
                    ),
                  ),
                ],
              ),
            ),
            if (checked)
              MemphisTag(
                text: '已收藏',
                color: accentColor,
                textColor: AppTheme.paperWhite,
                fontSize: 10.sp,
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                shadowOffset: 1.5,
              ),
          ],
        ),
      ),
    ),
  );
}

/// 弹出新建自定义歌单对话框（带少儿常用歌单预设名标签）
void _showCreatePlaylistDialog(
  BuildContext context,
  MusicPlayerController controller, {
  MusicTrack? initialTrack,
}) {
  final nameCtrl = TextEditingController();
  const presets = [
    '🌙 睡前哄睡轻音乐',
    '🚗 出行路上听',
    '🕺 快乐唱跳儿歌',
    '📖 故事磨耳朵',
    '🔤 英语启蒙儿歌',
  ];

  showDialog(
    context: context,
    builder: (dlgCtx) {
      return Dialog(
        backgroundColor: AppTheme.cream,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24.r),
        ),
        child: Padding(
          padding: EdgeInsets.all(20.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '📁 新建收藏歌单',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.ink,
                ),
              ),
              SizedBox(height: 12.h),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                style: TextStyle(
                  color: AppTheme.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 14.sp,
                ),
                decoration: InputDecoration(
                  hintText: '输入歌单名称（如：宝宝最爱儿歌）',
                  filled: true,
                  fillColor: AppTheme.paperWhite,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                ),
              ),
              SizedBox(height: 10.h),
              Text(
                '快捷模板（点一下直接填入）：',
                style: TextStyle(
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textSub,
                ),
              ),
              SizedBox(height: 6.h),
              Wrap(
                spacing: 6.w,
                runSpacing: 6.h,
                children: presets.map((p) {
                  return GestureDetector(
                    onTap: () => nameCtrl.text = p,
                    child: Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                      decoration: BoxDecoration(
                        color: AppTheme.paperWhite,
                        borderRadius: BorderRadius.circular(999),
                        border: AppTheme.border(),
                      ),
                      child: Text(
                        p,
                        style: TextStyle(
                          fontSize: 10.5.sp,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.ink,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              SizedBox(height: 16.h),
              Row(
                children: [
                  Expanded(
                    child: MemphisButton(
                      text: '取消',
                      color: AppTheme.paperWhite,
                      textColor: AppTheme.ink,
                      onTap: () => Navigator.of(dlgCtx).pop(),
                    ),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: MemphisButton(
                      text: '创建歌单',
                      color: AppTheme.tomato,
                      textColor: AppTheme.paperWhite,
                      onTap: () {
                        final created =
                            controller.createCustomPlaylist(nameCtrl.text);
                        if (initialTrack != null) {
                          controller.toggleTrackInPlaylist(
                              created.id, initialTrack);
                        }
                        Navigator.of(dlgCtx).pop();
                        ToastUtils.showSuccess('已创建歌单「${created.name}」');
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// 017 · 中世纪现代（Mid-Century Modern · Reid Miles / Blue Note 1956 唱机美学）商业级音乐播放器页面
/// 全面进化亮点：
/// 1. 丝滑零卡顿「唱机 ⇄ 歌词」切换：采用双层预挂载保活 Stack + GPU 硬件加速动画，切换耗时 0ms，歌词列表仅用单一监听驱动高亮。
/// 2. 鲜活有趣的动态唱机舞台：
///    - 旋转黑胶唱片 + 扇形丝绸流光（Vinyl Sheen）；
///    - Eames 彩球机械唱臂真实摆动压盘 + 音乐节拍呼吸微颤；
///    - 16 阶中世纪现代糖果色动态声波律动柱（Equalizer Bars）；
///    - 从唱针飘出的彩色音符（♪ ♫ ♬）与原子星芒气泡粒子流；
///    - 唱机底部自带「🎤 实时双行迷你歌词胶囊」，不切页也能跟着唱！
/// 3. 支持「📁 多歌单收藏」：歌名右侧直接提供「❤️ 最爱」「📁 加歌单（含歌单数角标）」「⬇️ 下载」三大快捷按钮。
class MusicPlayerPage extends StatefulWidget {
  const MusicPlayerPage({super.key});

  @override
  State<MusicPlayerPage> createState() => _MusicPlayerPageState();
}

class _MusicPlayerPageState extends State<MusicPlayerPage>
    with SingleTickerProviderStateMixin {
  late final MusicPlayerController _controller =
      Get.find<MusicPlayerController>();

  /// 使用局部 ValueNotifier 驱动「唱机 ⇄ 歌词」切换，避免整页 setState 重建
  final ValueNotifier<bool> _showLyricsNotifier = ValueNotifier<bool>(false);

  /// 使用局部 ValueNotifier 控制歌词是否自动跟随滚动
  final ValueNotifier<bool> _lyricsAutoScrollNotifier =
      ValueNotifier<bool>(true);

  /// 用户手动滑动歌词后，3.5 秒无操作自动恢复歌词跟随滚动的定时器
  Timer? _autoScrollResumeTimer;

  final ScrollController _lyricScrollController = ScrollController();

  /// 驱动黑胶旋转、声波跳动与音符飘浮的统一 Ticker（包裹在独立 RepaintBoundary 中）
  late final AnimationController _stageAnimCtrl;
  Worker? _lyricIndexWorker;
  Worker? _lyricsListWorker;
  Worker? _playingWorker;
  int _burstSeed = 0;

  @override
  void initState() {
    super.initState();
    _stageAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
    if (Get.isRegistered<MusicPlayerController>()) {
      if (_controller.isPlaying.value) {
        _stageAnimCtrl.repeat();
      }
      _playingWorker = ever<bool>(_controller.isPlaying, (playing) {
        if (!mounted) return;
        // 仅在唱机视图可见时才运行 60fps 唱机舞台动画，歌词页完全零开销
        if (playing && !_showLyricsNotifier.value) {
          _stageAnimCtrl.repeat();
        } else {
          _stageAnimCtrl.stop();
        }
      });
      _lyricIndexWorker = ever<int>(_controller.currentLyricIndex, (index) {
        // 仅在歌词视图激活且开启自动滚词时滚动列表
        if (_showLyricsNotifier.value && _lyricsAutoScrollNotifier.value) {
          _scrollToLyric(index);
        }
      });
      _lyricsListWorker = ever(_controller.lyrics, (_) {
        // 切歌或新歌词加载完成时，自动恢复滚词并立即对齐
        _lyricsAutoScrollNotifier.value = true;
        if (_showLyricsNotifier.value) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToLyric(_controller.currentLyricIndex.value,
                immediate: true);
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _autoScrollResumeTimer?.cancel();
    _lyricIndexWorker?.dispose();
    _lyricsListWorker?.dispose();
    _playingWorker?.dispose();
    _stageAnimCtrl.dispose();
    _lyricScrollController.dispose();
    _showLyricsNotifier.dispose();
    _lyricsAutoScrollNotifier.dispose();
    super.dispose();
  }

  MusicTrack? _currentTrack() {
    final list = _controller.playlist;
    final index = _controller.currentIndex.value;
    if (list.isEmpty || index < 0 || index >= list.length) return null;
    return list[index];
  }

  /// 滚动到指定歌词行；[immediate] 为 true 时使用 jumpTo 瞬时定位，避免切换页面时跨多行动画掉帧
  void _scrollToLyric(int index, {bool immediate = false}) {
    if (!mounted || !_lyricScrollController.hasClients) return;
    final pos = _lyricScrollController.position;
    if (!pos.hasContentDimensions) return;
    final itemH = 56.h;
    final rawTarget = index * itemH - (pos.viewportDimension * 0.32);
    final offset = rawTarget.clamp(0.0, pos.maxScrollExtent);
    final distance = (pos.pixels - offset).abs();
    if (distance < 3.0) return;

    // 切换视图瞬间或跨度超过 6 行时直接 jumpTo，避免同时构建大量行导致卡顿
    if (immediate || distance > itemH * 6) {
      _lyricScrollController.jumpTo(offset);
    } else {
      _lyricScrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// 用户手指主动拖拽歌词列表时暂停自动滚词，并在 3.5 秒后自动恢复
  void _onUserDragLyrics() {
    if (_lyricsAutoScrollNotifier.value) {
      _lyricsAutoScrollNotifier.value = false;
    }
    _autoScrollResumeTimer?.cancel();
    _autoScrollResumeTimer = Timer(const Duration(milliseconds: 3500), () {
      if (!mounted) return;
      _lyricsAutoScrollNotifier.value = true;
      if (_showLyricsNotifier.value) {
        _scrollToLyric(_controller.currentLyricIndex.value);
      }
    });
  }

  void _toggleLyricsView(bool show) {
    if (_showLyricsNotifier.value == show) return;
    HapticFeedback.selectionClick();
    _showLyricsNotifier.value = show;

    if (show) {
      // 切到歌词页时立即暂停唱机 60fps 旋转与粒子动画，释放全部 GPU 资源给歌词列表
      _stageAnimCtrl.stop();
      _autoScrollResumeTimer?.cancel();
      _lyricsAutoScrollNotifier.value = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToLyric(_controller.currentLyricIndex.value, immediate: true);
      });
    } else {
      // 切回唱机页时，若当前正在播放则恢复唱机旋转与声波律动
      if (_controller.isPlaying.value) {
        _stageAnimCtrl.repeat();
      }
    }
  }

  /// 快退或快进指定秒数（便捷微调）
  void _seekRelative(int deltaSeconds) {
    HapticFeedback.selectionClick();
    final cur = _controller.position.value;
    final total = _controller.duration.value;
    final targetSec = (cur.inSeconds + deltaSeconds)
        .clamp(0, total.inSeconds > 0 ? total.inSeconds : 36000);
    _controller.seek(Duration(seconds: targetSec));
  }

  String _platformLabel(String? p) {
    switch (p) {
      case 'netease':
        return '网易云音乐';
      case 'kuwo':
        return '酷我音乐';
      case 'qq':
        return 'QQ音乐';
      default:
        return 'HI-FI 电台';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<MusicPlayerController>()) {
      return Scaffold(
        backgroundColor: AppTheme.cream,
        body: Center(
          child: Text(
            '音乐服务未就绪\n请完全退出应用后重新打开',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.textSub,
              fontSize: 14.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
    return _buildScaffold(context);
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.cream,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(
            child: ModuleBackgroundScene(
              theme: ModuleBackgroundTheme.entertainment,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 10.h),
              child: Column(
                children: [
                  _buildTopHeader(context),
                  SizedBox(height: 6.h),
                  // 中央舞台：预挂载保活双层 Stack，切换 0 卡顿！
                  Expanded(child: _buildKeepAliveCenterStage()),
                  SizedBox(height: 8.h),
                  // 底部商业级人体工学操控舱
                  _buildControlDeck(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 顶部导航与「唱机 / 歌词」分段开关 ====================

  Widget _buildTopHeader(BuildContext context) {
    return Row(
      children: [
        MemphisIconButton(
          icon: Icons.keyboard_arrow_down_rounded,
          size: 40.w,
          iconSize: 24.sp,
          bgColor: AppTheme.paperWhite,
          onTap: () => Get.back(),
        ),
        const Spacer(),
        ValueListenableBuilder<bool>(
          valueListenable: _showLyricsNotifier,
          builder: (context, showLyrics, _) {
            return Container(
              padding: EdgeInsets.all(3.w),
              decoration: BoxDecoration(
                color: AppTheme.creamDeep,
                borderRadius: BorderRadius.circular(999),
                border: AppTheme.border(),
                boxShadow: AppTheme.paperShadow(h: 4.0),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildViewSegmentTab(
                    label: '💿 动态唱机',
                    active: !showLyrics,
                    onTap: () => _toggleLyricsView(false),
                  ),
                  SizedBox(width: 4.w),
                  _buildViewSegmentTab(
                    label: '📜 同步歌词',
                    active: showLyrics,
                    onTap: () => _toggleLyricsView(true),
                  ),
                ],
              ),
            );
          },
        ),
        const Spacer(),
        Obx(() {
          final mins = _controller.sleepTimerMinutes.value;
          return MemphisIconButton(
            icon: mins > 0 ? Icons.timer_rounded : Icons.timer_outlined,
            size: 40.w,
            iconSize: 20.sp,
            bgColor: mins > 0 ? AppTheme.yellow : AppTheme.paperWhite,
            iconColor: AppTheme.ink,
            tooltip: '定时关闭',
            onTap: () => _showTimerOptions(context),
          );
        }),
      ],
    );
  }

  Widget _buildViewSegmentTab({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutBack,
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 5.h),
        decoration: BoxDecoration(
          color: active ? AppTheme.tomato : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          boxShadow: active ? AppTheme.paperShadow(h: 4.0) : const [],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.sp,
            fontWeight: FontWeight.w900,
            color: active ? AppTheme.paperWhite : AppTheme.ink,
          ),
        ),
      ),
    );
  }

  // ==================== 中央舞台：Offstage 双层保活 0ms 瞬切 ====================

  Widget _buildKeepAliveCenterStage() {
    final turntableStage = RepaintBoundary(child: _buildTurntableStage());
    final lyricsStage = RepaintBoundary(child: _buildLyricsStage());

    return ValueListenableBuilder<bool>(
      valueListenable: _showLyricsNotifier,
      builder: (context, showLyrics, _) {
        return Stack(
          fit: StackFit.expand,
          children: [
            // 第 1 层：动态黑胶唱机舞台（切到歌词时直接 Offstage 停止绘制与合成，0 GPU 负担）
            Offstage(
              offstage: showLyrics,
              child: turntableStage,
            ),
            // 第 2 层：同步滚动歌词舞台（切回唱机时 Offstage 保活状态，0 离屏 saveLayer 开销）
            Offstage(
              offstage: !showLyrics,
              child: lyricsStage,
            ),
          ],
        );
      },
    );
  }

  /// 动态中世纪现代黑胶唱机舞台（黑胶旋转 + 唱臂摆动 + 16阶律动声波 + 飘浮音符 + 实时双行迷你歌词）
  Widget _buildTurntableStage() {
    return Obx(() {
      final track = _currentTrack();
      final hasCover =
          track?.coverUrl != null && track!.coverUrl!.isNotEmpty;
      final playing = _controller.isPlaying.value;
      final qualityLabel = ChkSzMusicService.qualityLabel(
          _controller.currentAudioQuality.value);

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0;
          if (v < -260) {
            HapticFeedback.lightImpact();
            _controller.playNext();
          } else if (v > 260) {
            HapticFeedback.lightImpact();
            _controller.playPrevious();
          }
        },
        child: LayoutBuilder(builder: (context, constraints) {
          final availH = constraints.maxHeight;
          final availW = constraints.maxWidth;
          // 为底部迷你歌词胶囊预留空间
          final showMiniLyric = availH > 220;
          final stageH = showMiniLyric ? availH - 58 : availH;
          final maxSide = math.min(availW, math.max(110.0, stageH - 22));
          final sleeveSize = (maxSide * 0.78).clamp(100.0, 236.0);
          final vinylSize = sleeveSize * 0.92;

          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 主唱机与动态声波/音符粒子舞台
              SizedBox(
                width: availW,
                height: stageH,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    // 底层 + 顶层环绕动态画布：声波律动柱 + 飘浮彩色音符与原子彩球（独立 RepaintBoundary）
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: _stageAnimCtrl,
                          builder: (context, _) {
                            return CustomPaint(
                              painter: _LivingStageEffectsPainter(
                                phase: _stageAnimCtrl.value,
                                isPlaying: playing,
                                burstSeed: _burstSeed,
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                    // 中央唱机组合：左侧剪纸封套 + 右侧旋转黑胶 + 机械唱臂
                    SizedBox(
                      width: math.min(availW, sleeveSize * 1.32),
                      height: sleeveSize + 10,
                      child: Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          // 右侧旋转黑胶唱片（带丝绸流光高光与双色叠印盘心）
                          Positioned(
                            right: 4,
                            child: GestureDetector(
                              onTap: () {
                                HapticFeedback.mediumImpact();
                                setState(() => _burstSeed++);
                                _controller.togglePlay();
                              },
                              child: RepaintBoundary(
                                child: AnimatedBuilder(
                                  animation: _stageAnimCtrl,
                                  builder: (context, _) {
                                    // 节拍微弹缩放（144 BPM 模拟律动）
                                    final beat = playing
                                        ? 1.0 +
                                            0.018 *
                                                math.sin(_stageAnimCtrl.value *
                                                    24 *
                                                    math.pi)
                                        : 1.0;
                                    return Transform.scale(
                                      scale: beat,
                                      child: Transform.rotate(
                                        angle: _stageAnimCtrl.value *
                                            2 *
                                            math.pi,
                                        child: Container(
                                          width: vinylSize,
                                          height: vinylSize,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: AppTheme.ink,
                                            boxShadow:
                                                AppTheme.paperShadow(h: 12.0),
                                          ),
                                          child: CustomPaint(
                                            painter: _VinylDiscPainter(),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),

                          // 左侧：Reid Miles / Blue Note 剪纸唱片封套卡（点击即刻切换歌词）
                          Positioned(
                            left: 2,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _toggleLyricsView(true),
                              child: Transform.rotate(
                                angle: -0.025,
                                child: Container(
                                  width: sleeveSize,
                                  height: sleeveSize,
                                  padding: const EdgeInsets.all(9),
                                  decoration: BoxDecoration(
                                    color: AppTheme.paperWhite,
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(22),
                                      topRight: Radius.circular(16),
                                      bottomLeft: Radius.circular(18),
                                      bottomRight: Radius.circular(24),
                                    ),
                                    border: AppTheme.border(),
                                    boxShadow: AppTheme.paperShadow(h: 14.0),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 9,
                                            height: 9,
                                            decoration: const BoxDecoration(
                                              color: AppTheme.tomato,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Container(
                                            width: 9,
                                            height: 9,
                                            decoration: const BoxDecoration(
                                              color: AppTheme.teal,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 5),
                                          Expanded(
                                            child: Text(
                                              'BLUE NOTE · ${_platformLabel(track?.platform)}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 9.0,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: 0.6,
                                                color: AppTheme.textSub,
                                              ),
                                            ),
                                          ),
                                          if (qualityLabel.isNotEmpty)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 5,
                                                      vertical: 1),
                                              decoration: BoxDecoration(
                                                color: AppTheme.yellow,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                qualityLabel,
                                                style: const TextStyle(
                                                  fontSize: 8.0,
                                                  fontWeight: FontWeight.w900,
                                                  color: AppTheme.ink,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Expanded(
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(13),
                                          child: hasCover
                                              ? Image.network(
                                                  track.coverUrl!,
                                                  fit: BoxFit.cover,
                                                  headers: coverHeadersFor(
                                                      track.coverUrl),
                                                  errorBuilder: (context, error,
                                                          stackTrace) =>
                                                      _defaultCover(
                                                          track.platform),
                                                )
                                              : _defaultCover(track?.platform),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // 右上角：Eames 彩球机械唱臂（随播放状态摆动压上黑胶，点击也可控制播放暂停）
                          Positioned(
                            top: -4,
                            right: 0,
                            child: GestureDetector(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                _controller.togglePlay();
                              },
                              child: AnimatedRotation(
                                duration: const Duration(milliseconds: 520),
                                curve: Curves.elasticOut,
                                turns: playing ? 0.035 : -0.065,
                                alignment: Alignment.topRight,
                                child: SizedBox(
                                  width: 68,
                                  height: 92,
                                  child: CustomPaint(
                                    painter: _TonearmPainter(playing: playing),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 唱机下方实时双行迷你歌词胶囊（点击直接展开全屏歌词）
              if (showMiniLyric)
                GestureDetector(
                  onTap: () => _toggleLyricsView(true),
                  child: Container(
                    height: 50,
                    width: double.infinity,
                    padding:
                        EdgeInsets.symmetric(horizontal: 14.w, vertical: 5.h),
                    decoration: BoxDecoration(
                      color: AppTheme.paperWhite.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(16.r),
                      border: AppTheme.border(),
                      boxShadow: AppTheme.paperShadow(h: 5.0),
                    ),
                    child: Obx(() {
                      final list = _controller.lyrics;
                      final idx = _controller.currentLyricIndex.value;
                      if (list.isEmpty) {
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.music_note_rounded,
                                size: 15.sp, color: AppTheme.tomato),
                            SizedBox(width: 6.w),
                            Flexible(
                              child: Text(
                                playing
                                    ? '🎶 正在播放好听的旋律 · 轻触展开歌词舞台'
                                    : '⏸ 已暂停 · 轻触黑胶唱盘或播放键继续听',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.sp,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textSub,
                                ),
                              ),
                            ),
                          ],
                        );
                      }
                      final curLine =
                          idx >= 0 && idx < list.length ? list[idx].content : '';
                      final nextLine = idx + 1 < list.length
                          ? list[idx + 1].content
                          : '✦ 轻触查看完整滚动歌词';

                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '🎤 $curLine',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5.sp,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.tomato,
                            ),
                          ),
                          SizedBox(height: 1.5.h),
                          Text(
                            nextLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5.sp,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textSub,
                            ),
                          ),
                        ],
                      );
                    }),
                  ),
                ),
            ],
          );
        }),
      );
    });
  }

  Widget _defaultCover(String? platform) {
    return Container(
      color: AppTheme.tealSoft,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.album_rounded, color: AppTheme.tomato, size: 50.sp),
            SizedBox(height: 6.h),
            Text(
              _platformLabel(platform),
              style: TextStyle(
                color: AppTheme.ink,
                fontSize: 11.5.sp,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 同步歌词剪纸舞台（单一 Obx 驱动，60/120fps 极速滚动，点击任意行即刻跳转）
  Widget _buildLyricsStage() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.paperWhite,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24.r),
          topRight: Radius.circular(18.r),
          bottomLeft: Radius.circular(20.r),
          bottomRight: Radius.circular(26.r),
        ),
        border: AppTheme.border(),
        boxShadow: AppTheme.paperShadow(h: 10.0),
      ),
      child: Stack(
        children: [
          Obx(() {
            final lines = _controller.lyrics;
            final activeIdx = _controller.currentLyricIndex.value;

            if (lines.isEmpty) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _toggleLyricsView(false),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lyrics_outlined,
                          color: AppTheme.tomato.withValues(alpha: 0.45),
                          size: 46.sp),
                      SizedBox(height: 10.h),
                      Text(
                        '纯音乐或正在加载歌词…',
                        style: TextStyle(
                          color: AppTheme.ink,
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 6.h),
                      Text(
                        '轻触任意空白处可返回动态唱机',
                        style: TextStyle(
                          color: AppTheme.textSub,
                          fontSize: 11.5.sp,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 10.h),
                      MemphisButton(
                        text: '🔄 重新获取歌词',
                        color: AppTheme.yellow,
                        fontSize: 12.sp,
                        borderRadius: 999,
                        onTap: () {
                          final track = _currentTrack();
                          if (track != null) {
                            _controller.playTrack(track);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              );
            }

            return Listener(
              onPointerMove: (event) {
                if (event.delta.dy.abs() > 3.5) {
                  _onUserDragLyrics();
                }
              },
              child: ListView.builder(
                controller: _lyricScrollController,
                itemExtent: 56.h,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.symmetric(vertical: 68.h, horizontal: 14.w),
                itemCount: lines.length,
                itemBuilder: (context, index) {
                  final line = lines[index];
                  final isActive = index == activeIdx;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      _autoScrollResumeTimer?.cancel();
                      _lyricsAutoScrollNotifier.value = true;
                      _controller.seek(line.startTime);
                      _scrollToLyric(index);
                    },
                    child: Container(
                      alignment: Alignment.center,
                      padding: EdgeInsets.symmetric(horizontal: 10.w),
                      decoration: isActive
                          ? BoxDecoration(
                              color: AppTheme.yellowSoft,
                              borderRadius: BorderRadius.circular(12.r),
                            )
                          : null,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            line.content,
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isActive
                                  ? AppTheme.tomato
                                  : AppTheme.ink.withValues(alpha: 0.58),
                              fontSize: isActive ? 15.5.sp : 13.5.sp,
                              fontWeight:
                                  isActive ? FontWeight.w900 : FontWeight.w700,
                              height: 1.2,
                            ),
                          ),
                          if (line.translation != null &&
                              line.translation!.isNotEmpty)
                            Text(
                              line.translation!,
                              maxLines: 1,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppTheme.textSub,
                                fontSize: 10.sp,
                                fontWeight: FontWeight.w600,
                                height: 1.15,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          }),

          // 右上角快捷返回唱机按钮 + 定位当前句按钮
          Positioned(
            top: 10.h,
            right: 10.w,
            child: ValueListenableBuilder<bool>(
              valueListenable: _lyricsAutoScrollNotifier,
              builder: (context, autoScroll, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!autoScroll) ...[
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          _autoScrollResumeTimer?.cancel();
                          _lyricsAutoScrollNotifier.value = true;
                          _scrollToLyric(_controller.currentLyricIndex.value);
                        },
                        child: MemphisTag(
                          text: '🎯 定位当前句',
                          color: AppTheme.yellow,
                          fontSize: 10.sp,
                          shadowOffset: 2.0,
                        ),
                      ),
                      SizedBox(width: 6.w),
                    ],
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _toggleLyricsView(false),
                      child: MemphisTag(
                        text: '💿 回唱机',
                        color: AppTheme.tealSoft,
                        fontSize: 10.sp,
                        shadowOffset: 2.0,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 底部人体工学操控舱（便捷、可控、大热区） ====================

  Widget _buildControlDeck(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 12.h),
      decoration: BoxDecoration(
        color: AppTheme.paperWhite,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(26.r),
          topRight: Radius.circular(20.r),
          bottomLeft: Radius.circular(22.r),
          bottomRight: Radius.circular(28.r),
        ),
        border: AppTheme.border(),
        boxShadow: AppTheme.paperShadow(h: 12.0),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTrackHeaderRow(context),
          SizedBox(height: 8.h),
          _buildProgressAndQuickSeek(),
          SizedBox(height: 8.h),
          _buildPrimaryTransportRow(context),
        ],
      ),
    );
  }

  /// 第 1 行：歌曲标题 + 右侧「❤️ 最爱」「📁 加歌单」「⬇️ 下载」三大快捷按钮
  Widget _buildTrackHeaderRow(BuildContext context) {
    return Obx(() {
      final track = _currentTrack();
      if (track == null) {
        return SizedBox(
          height: 42.h,
          child: Center(
            child: Text(
              '当前没有正在播放的歌曲',
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w800,
                color: AppTheme.textSub,
              ),
            ),
          ),
        );
      }

      final isFav = _controller.isFavorite(track);
      final plCount = _controller.countPlaylistsContaining(track);
      final isDownloading = _controller.isDownloading.value;

      return Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.ink,
                    fontSize: 17.5.sp,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  track.album != null && track.album!.isNotEmpty
                      ? '${track.artist} · ${track.album}'
                      : track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textSub,
                    fontSize: 11.5.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 6.w),
          // 1. 一键最爱红心
          MemphisIconButton(
            icon:
                isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            size: 38.w,
            iconSize: 19.sp,
            bgColor: isFav ? AppTheme.pinkSoft : AppTheme.cream,
            iconColor: isFav ? AppTheme.tomato : AppTheme.ink,
            tooltip: isFav ? '取消最爱' : '加入最爱',
            onTap: () {
              HapticFeedback.lightImpact();
              _controller.toggleFavorite(track);
              ToastUtils.showSuccess(isFav ? '已从我的最爱移除' : '❤️ 已加入我的最爱');
            },
          ),
          SizedBox(width: 6.w),
          // 2. 收藏到多个歌单按钮（带已收藏歌单数角标）
          Stack(
            clipBehavior: Clip.none,
            children: [
              MemphisIconButton(
                icon: Icons.library_add_rounded,
                size: 38.w,
                iconSize: 19.sp,
                bgColor: plCount > 0 ? AppTheme.yellowSoft : AppTheme.cream,
                iconColor: AppTheme.ink,
                tooltip: '收藏到多个歌单',
                onTap: () => showAddToPlaylistsSheet(context, track),
              ),
              if (plCount > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppTheme.tomato,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$plCount',
                      style: const TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(width: 6.w),
          // 3. 下载按钮
          MemphisIconButton(
            icon: isDownloading
                ? Icons.downloading_rounded
                : Icons.download_rounded,
            size: 38.w,
            iconSize: 19.sp,
            bgColor: isDownloading ? AppTheme.yellowSoft : AppTheme.cream,
            iconColor: AppTheme.ink,
            tooltip: '下载到本地',
            onTap:
                isDownloading ? null : () => _controller.downloadTrack(track),
          ),
        ],
      );
    });
  }

  /// 第 2 行：局部 Obx 进度条 + ±10s 快退/快进微调胶囊
  Widget _buildProgressAndQuickSeek() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Obx(() {
          final pos = _controller.position.value;
          final dur = _controller.duration.value;
          final buf = _controller.buffered.value;

          final safeTotal =
              dur > pos ? dur : (pos + const Duration(seconds: 1));
          final safeBuffered = buf <= safeTotal ? buf : safeTotal;

          return ProgressBar(
            progress: pos,
            total: safeTotal,
            buffered: safeBuffered,
            onSeek: _controller.seek,
            baseBarColor: AppTheme.creamDeep,
            progressBarColor: AppTheme.tomato,
            bufferedBarColor: AppTheme.teal.withValues(alpha: 0.35),
            thumbColor: AppTheme.tomato,
            thumbGlowColor: AppTheme.tomato.withValues(alpha: 0.20),
            barHeight: 5.5,
            thumbRadius: 8.0,
            thumbGlowRadius: 16.0,
            timeLabelLocation: TimeLabelLocation.below,
            timeLabelPadding: 3.0,
            timeLabelTextStyle: TextStyle(
              color: AppTheme.textSub,
              fontSize: 11.sp,
              fontWeight: FontWeight.w800,
            ),
          );
        }),
        SizedBox(height: 3.h),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildQuickSeekChip(
              icon: Icons.replay_10_rounded,
              label: '快退 10s',
              onTap: () => _seekRelative(-10),
            ),
            SizedBox(width: 8.w),
            _buildQuickSeekChip(
              icon: Icons.restart_alt_rounded,
              label: '重头听',
              onTap: () {
                HapticFeedback.selectionClick();
                _controller.seek(Duration.zero);
              },
            ),
            SizedBox(width: 8.w),
            _buildQuickSeekChip(
              icon: Icons.forward_10_rounded,
              label: '快进 10s',
              onTap: () => _seekRelative(10),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickSeekChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return BouncyTap(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 3.5.h),
        decoration: BoxDecoration(
          color: AppTheme.cream,
          borderRadius: BorderRadius.circular(999),
          border: AppTheme.border(),
          boxShadow: AppTheme.paperShadow(h: 3.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13.5.sp, color: AppTheme.ink),
            SizedBox(width: 3.w),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.sp,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 第 3 行：五键主控台（带直观中文状态标签，单手大热区）
  Widget _buildPrimaryTransportRow(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Obx(() {
          final mode = _controller.playMode.value;
          final (IconData icon, String label, Color bg) = switch (mode) {
            PlayMode.sequence => (
                Icons.repeat_rounded,
                '顺序播放',
                AppTheme.cream,
              ),
            PlayMode.shuffle => (
                Icons.shuffle_rounded,
                '随机播放',
                AppTheme.yellowSoft,
              ),
            PlayMode.single => (
                Icons.repeat_one_rounded,
                '单曲循环',
                AppTheme.tealSoft,
              ),
          };
          return _buildLabeledDeckAction(
            icon: icon,
            label: label,
            bgColor: bg,
            onTap: () {
              HapticFeedback.selectionClick();
              _controller.changePlayMode();
            },
          );
        }),
        MemphisIconButton(
          icon: Icons.skip_previous_rounded,
          size: 46.w,
          iconSize: 27.sp,
          bgColor: AppTheme.cream,
          iconColor: AppTheme.ink,
          tooltip: '上一首',
          onTap: () {
            HapticFeedback.lightImpact();
            _controller.playPrevious();
          },
        ),
        Obx(() {
          final playing = _controller.isPlaying.value;
          return BouncyTap(
            enableHaptic: true,
            onTap: _controller.togglePlay,
            child: Container(
              width: 64.w,
              height: 64.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.tomato,
                border: AppTheme.border(),
                boxShadow: AppTheme.paperShadow(h: 12.0),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  key: ValueKey<bool>(playing),
                  color: AppTheme.paperWhite,
                  size: 36.sp,
                ),
              ),
            ),
          );
        }),
        MemphisIconButton(
          icon: Icons.skip_next_rounded,
          size: 46.w,
          iconSize: 27.sp,
          bgColor: AppTheme.cream,
          iconColor: AppTheme.ink,
          tooltip: '下一首',
          onTap: () {
            HapticFeedback.lightImpact();
            _controller.playNext();
          },
        ),
        Obx(() {
          final count = _controller.playlist.length;
          return _buildLabeledDeckAction(
            icon: Icons.queue_music_rounded,
            label: '队列($count)',
            bgColor: AppTheme.cream,
            onTap: () => _showQueueSheet(context),
          );
        }),
      ],
    );
  }

  Widget _buildLabeledDeckAction({
    required IconData icon,
    required String label,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return BouncyTap(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.5.h),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14.r),
          border: AppTheme.border(),
          boxShadow: AppTheme.paperShadow(h: 4.0),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppTheme.ink, size: 19.sp),
            SizedBox(height: 2.h),
            Text(
              label,
              style: TextStyle(
                fontSize: 9.5.sp,
                fontWeight: FontWeight.w900,
                color: AppTheme.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 播放队列面板 ====================

  void _showQueueSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.62,
          minChildSize: 0.35,
          maxChildSize: 0.90,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: AppTheme.cream,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
                border: AppTheme.border(),
                boxShadow: AppTheme.paperShadow(h: 16.0),
              ),
              child: Column(
                children: [
                  Container(
                    margin: EdgeInsets.symmetric(vertical: 10.h),
                    width: 42.w,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.textSub.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20.w),
                    child: Obx(() => Row(
                          children: [
                            Text(
                              '🎵 播放队列 (${_controller.playlist.length})',
                              style: TextStyle(
                                color: AppTheme.ink,
                                fontSize: 17.sp,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const Spacer(),
                            if (_controller.playlist.isNotEmpty)
                              BouncyTap(
                                onTap: _controller.clearPlaylist,
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 10.w, vertical: 4.h),
                                  decoration: BoxDecoration(
                                    color: AppTheme.tomatoSoft,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '清空队列',
                                    style: TextStyle(
                                      color: AppTheme.tomato,
                                      fontSize: 12.sp,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        )),
                  ),
                  SizedBox(height: 8.h),
                  const Divider(height: 1),
                  Expanded(
                    child: Obx(() {
                      final list = _controller.playlist;
                      final curIdx = _controller.currentIndex.value;
                      if (list.isEmpty) {
                        return Center(
                          child: Text(
                            '播放队列为空，快去挑选好听的儿歌吧～',
                            style: TextStyle(
                              color: AppTheme.textSub,
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );
                      }
                      return ListView.builder(
                        controller: scrollController,
                        padding: EdgeInsets.symmetric(
                            horizontal: 14.w, vertical: 10.h),
                        itemCount: list.length,
                        itemBuilder: (context, index) {
                          final track = list[index];
                          final isCurrent = index == curIdx;
                          return Container(
                            margin: EdgeInsets.only(bottom: 8.h),
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? AppTheme.yellowSoft
                                  : AppTheme.paperWhite,
                              borderRadius: BorderRadius.circular(16.r),
                              border: AppTheme.border(),
                              boxShadow: AppTheme.paperShadow(
                                  h: isCurrent ? 6.0 : 3.0),
                            ),
                            child: ListTile(
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12.w, vertical: 2.h),
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(10.r),
                                child: Container(
                                  width: 42.w,
                                  height: 42.w,
                                  color: AppTheme.tealSoft,
                                  child: (track.coverUrl != null &&
                                          track.coverUrl!.isNotEmpty)
                                      ? Image.network(
                                          track.coverUrl!,
                                          fit: BoxFit.cover,
                                          headers:
                                              coverHeadersFor(track.coverUrl),
                                          errorBuilder: (ctx, err, st) => Icon(
                                              Icons.music_note,
                                              color: AppTheme.tomato,
                                              size: 20.sp),
                                        )
                                      : Icon(Icons.music_note,
                                          color: AppTheme.tomato, size: 20.sp),
                                ),
                              ),
                              title: Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isCurrent
                                      ? AppTheme.tomato
                                      : AppTheme.ink,
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              subtitle: Text(
                                track.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppTheme.textSub,
                                  fontSize: 11.5.sp,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    icon: Icon(Icons.library_add_outlined,
                                        color: AppTheme.teal, size: 19.sp),
                                    tooltip: '收藏到歌单',
                                    onPressed: () =>
                                        showAddToPlaylistsSheet(context, track),
                                  ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    icon: Icon(Icons.close_rounded,
                                        color: AppTheme.textSub, size: 18.sp),
                                    onPressed: () =>
                                        _controller.removeTrackAt(index),
                                  ),
                                ],
                              ),
                              onTap: () {
                                if (!isCurrent) {
                                  _controller.playTrack(track,
                                      targetIndex: index);
                                }
                              },
                            ),
                          );
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

  // ==================== 睡眠定时面板 ====================

  void _showTimerOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          margin: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            color: AppTheme.cream,
            borderRadius: BorderRadius.circular(24.r),
            border: AppTheme.border(),
            boxShadow: AppTheme.paperShadow(h: 14.0),
          ),
          padding: EdgeInsets.all(22.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '⏰ 定时关闭',
                    style: TextStyle(
                      color: AppTheme.ink,
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (_controller.sleepTimerMinutes.value > 0)
                    TextButton(
                      onPressed: () {
                        _controller.setSleepTimer(0);
                        Get.back();
                      },
                      child: const Text(
                        '取消定时',
                        style: TextStyle(
                          color: AppTheme.tomato,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: 16.h),
              Wrap(
                spacing: 10.w,
                runSpacing: 10.h,
                alignment: WrapAlignment.start,
                children: [10, 15, 20, 30, 45, 60]
                    .map((min) => _buildTimerChip(context, min))
                    .toList()
                  ..add(
                    BouncyTap(
                      onTap: () {
                        Get.back();
                        _showCustomTimerDialog(context);
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 14.w, vertical: 8.h),
                        decoration: BoxDecoration(
                          color: AppTheme.tealSoft,
                          borderRadius: BorderRadius.circular(999),
                          border: AppTheme.border(),
                          boxShadow: AppTheme.paperShadow(h: 4.0),
                        ),
                        child: Text(
                          '✨ 自定义分钟',
                          style: TextStyle(
                            color: AppTheme.ink,
                            fontSize: 12.5.sp,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
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
    return BouncyTap(
      onTap: () {
        _controller.setSleepTimer(min);
        Get.back();
        ToastUtils.showSuccess('音乐将在 $min 分钟后自动暂停', title: '定时设置');
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.tomato : AppTheme.paperWhite,
          borderRadius: BorderRadius.circular(999),
          border: AppTheme.border(),
          boxShadow: AppTheme.paperShadow(h: isSelected ? 6.0 : 4.0),
        ),
        child: Text(
          '$min 分钟',
          style: TextStyle(
            color: isSelected ? AppTheme.paperWhite : AppTheme.ink,
            fontSize: 12.5.sp,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  void _showCustomTimerDialog(BuildContext context) {
    final TextEditingController inputCtrl = TextEditingController();
    Get.defaultDialog(
      title: '自定义睡眠定时',
      titleStyle: TextStyle(
        color: AppTheme.ink,
        fontSize: 18.sp,
        fontWeight: FontWeight.w900,
      ),
      contentPadding: EdgeInsets.all(20.w),
      content: TextField(
        controller: inputCtrl,
        keyboardType: TextInputType.number,
        autofocus: true,
        style: const TextStyle(
            color: AppTheme.ink, fontWeight: FontWeight.w800),
        decoration: InputDecoration(
          hintText: '输入分钟数 (如 25)',
          suffixText: '分钟',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14.r)),
          filled: true,
          fillColor: AppTheme.paperWhite,
        ),
      ),
      confirm: MemphisButton(
        text: '确定开启',
        color: AppTheme.tomato,
        textColor: AppTheme.paperWhite,
        onTap: () {
          final int? min = int.tryParse(inputCtrl.text);
          if (min != null && min > 0) {
            _controller.setSleepTimer(min);
            Get.back();
            ToastUtils.showSuccess('音乐将在 $min 分钟后暂停', title: '定时设置');
          } else {
            ToastUtils.showError('请输入有效的分钟数', title: '输入错误');
          }
        },
      ),
      radius: 20.r,
      backgroundColor: AppTheme.cream,
    );
  }
}

/// 黑胶唱片盘面同心音轨、丝绸流光扇区与中心双色叠印盘心画笔
class _VinylDiscPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    // 1. 黑胶丝绸扇形高光（随旋转呈现动感金属光泽）
    final sheenPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..style = PaintingStyle.fill;
    final rect = Rect.fromCircle(center: c, radius: r * 0.96);
    canvas.drawArc(rect, -0.35, 0.45, true, sheenPaint);
    canvas.drawArc(rect, math.pi - 0.35, 0.45, true, sheenPaint);

    // 2. 唱片反光音轨细纹
    final groovePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    for (var frac = 0.44; frac <= 0.90; frac += 0.065) {
      canvas.drawCircle(c, r * frac, groovePaint);
    }

    // 3. 中心中世纪现代双色叠印盘心（向日葵黄 + 番茄红 + 绿松石点缀）
    canvas.drawCircle(c, r * 0.33, Paint()..color = AppTheme.yellow);
    final halfRect = Rect.fromCircle(center: c, radius: r * 0.33);
    canvas.drawArc(
      halfRect,
      -math.pi / 4,
      math.pi,
      true,
      Paint()..color = AppTheme.tomato,
    );
    canvas.drawCircle(
      Offset(c.dx + r * 0.14, c.dy - r * 0.10),
      r * 0.06,
      Paint()..color = AppTheme.teal,
    );
    // 唱机中心轴孔
    canvas.drawCircle(c, r * 0.07, Paint()..color = AppTheme.cream);
  }

  @override
  bool shouldRepaint(covariant _VinylDiscPainter oldDelegate) => false;
}

/// Eames 彩球机械唱臂画笔
class _TonearmPainter extends CustomPainter {
  final bool playing;

  const _TonearmPainter({required this.playing});

  @override
  void paint(Canvas canvas, Size size) {
    final pivot = Offset(size.width - 16, 16);
    // 唱臂底座圆盘
    canvas.drawCircle(
      pivot.translate(1.5, 3),
      13,
      Paint()..color = AppTheme.shadowBrown.withValues(alpha: 0.22),
    );
    canvas.drawCircle(
      pivot,
      13,
      Paint()..color = AppTheme.paperWhite,
    );
    canvas.drawCircle(
      pivot,
      7,
      Paint()..color = playing ? AppTheme.teal : AppTheme.yellow,
    );

    // 钢丝折线唱臂杆
    final armPath = Path()
      ..moveTo(pivot.dx, pivot.dy)
      ..lineTo(pivot.dx - 16, pivot.dy + 44)
      ..lineTo(pivot.dx - 34, pivot.dy + 66);
    canvas.drawPath(
      armPath,
      Paint()
        ..color = AppTheme.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // 番茄红唱头与发光唱针点
    final headCenter = Offset(pivot.dx - 34, pivot.dy + 66);
    canvas.drawCircle(
      headCenter,
      6.5,
      Paint()..color = AppTheme.tomato,
    );
    if (playing) {
      canvas.drawCircle(
        headCenter,
        10.5,
        Paint()
          ..color = AppTheme.yellow.withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TonearmPainter oldDelegate) =>
      oldDelegate.playing != playing;
}

/// 动态唱机舞台声波律动柱 & 飘浮音符/原子彩球画笔
class _LivingStageEffectsPainter extends CustomPainter {
  final double phase;
  final bool isPlaying;
  final int burstSeed;

  const _LivingStageEffectsPainter({
    required this.phase,
    required this.isPlaying,
    required this.burstSeed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    const palette = [
      AppTheme.tomato,
      AppTheme.yellow,
      AppTheme.teal,
      AppTheme.cobalt,
      AppTheme.pink,
    ];

    // 1. 底部 16 阶中世纪现代动态声波律动柱（Equalizer Bars）
    const barCount = 16;
    final totalBarW = math.min(w * 0.76, 240.0);
    final startX = (w - totalBarW) / 2;
    final stepX = totalBarW / barCount;
    final baseY = h - 4;

    for (var i = 0; i < barCount; i++) {
      final wave1 = math.sin(phase * 2 * math.pi * 6 + i * 0.65);
      final wave2 = math.cos(phase * 2 * math.pi * 4 - i * 0.9);
      final amp = isPlaying ? ((wave1 + wave2 + 2) / 4) : 0.15;
      final barH = 4.0 + amp * 16.0;
      final color = palette[i % palette.length];
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          startX + i * stepX + 2,
          baseY - barH,
          stepX - 4,
          barH,
        ),
        const Radius.circular(4),
      );
      canvas.drawRRect(
        rect,
        Paint()..color = color.withValues(alpha: isPlaying ? 0.85 : 0.35),
      );
    }

    if (!isPlaying) return;

    // 2. 播放时飘浮上升的彩色音符与原子彩球粒子流
    const symbols = ['♪', '♫', '♬', '✦', '●'];
    for (var k = 0; k < 7; k++) {
      final t = (phase * 3.0 + k * 0.143 + burstSeed * 0.07) % 1.0;
      final sideLeft = k.isEven;
      final baseX = sideLeft ? w * 0.10 : w * 0.88;
      final sway = math.sin(t * 2 * math.pi + k) * 14.0;
      final x = (baseX + sway).clamp(8.0, w - 20.0);
      final y = h * 0.78 - t * (h * 0.68);
      final alpha = (math.sin(t * math.pi)).clamp(0.0, 1.0) * 0.82;
      final c = palette[(k + burstSeed) % palette.length];

      final sym = symbols[k % symbols.length];
      final tp = TextPainter(
        text: TextSpan(
          text: sym,
          style: TextStyle(
            fontSize: 13.0 + (k % 3) * 3.0,
            fontWeight: FontWeight.w900,
            color: c.withValues(alpha: alpha),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x, y));
    }
  }

  @override
  bool shouldRepaint(covariant _LivingStageEffectsPainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.isPlaying != isPlaying ||
      oldDelegate.burstSeed != burstSeed;
}
