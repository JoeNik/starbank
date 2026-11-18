import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../controllers/music_player_controller.dart';
import '../../../controllers/app_mode_controller.dart';
import '../../../services/chksz_music_service.dart';
import '../../../models/music/music_track.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/memphis_widgets.dart';
import '../../../widgets/toast_utils.dart';
import '../../../widgets/music_cover_image.dart';
import 'music_player_page.dart';

/// 网易云歌单详情页(由 ChKSz /api/163_playlist 驱动)。
/// 静态缓存跨页面共享:首页歌单卡片与详情页共用一次请求结果。
class PlaylistDetailPage extends StatefulWidget {
  const PlaylistDetailPage({
    super.key,
    required this.playlistId,
    this.fallbackName,
  });

  final String playlistId;
  final String? fallbackName;

  static final Map<String, Map<String, dynamic>> cache = {};

  @override
  State<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<PlaylistDetailPage> {
  // late 获取:配合 build 顶部的注册检查,服务缺失时优雅降级而不是崩溃
  late final MusicPlayerController _controller =
      Get.find<MusicPlayerController>();
  late final AppModeController _modeController =
      Get.find<AppModeController>();

  String _name = '';
  String? _cover;
  List<MusicTrack> _tracks = [];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _name = widget.fallbackName ?? '网易云歌单';
    _load();
  }

  Future<void> _load({bool force = false}) async {
    if (!force) {
      final cached = PlaylistDetailPage.cache[widget.playlistId];
      if (cached != null) {
        _applyResult(cached);
        return;
      }
    }
    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    try {
      final chksz = Get.isRegistered<ChkSzMusicService>()
          ? Get.find<ChkSzMusicService>()
          : null;
      if (chksz == null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _failed = true;
          });
        }
        return;
      }
      final result = await chksz.fetchPlaylist(widget.playlistId);
      final tracks = result['tracks'];
      if (tracks is List && tracks.isNotEmpty) {
        PlaylistDetailPage.cache[widget.playlistId] = result;
        _applyResult(result);
      } else {
        if (mounted) {
          setState(() {
            _loading = false;
            _failed = true;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  void _applyResult(Map<String, dynamic> result) {
    if (!mounted) return;
    setState(() {
      _name = (result['name'] as String?) ?? _name;
      _cover = result['cover'] as String?;
      _tracks = (result['tracks'] as List).cast<MusicTrack>();
      _loading = false;
      _failed = false;
    });
  }

  void _playAll() {
    if (_tracks.isEmpty) return;
    _controller.playWithList(_tracks, _tracks.first);
    Get.to(() => const MusicPlayerPage());
  }

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<MusicPlayerController>()) {
      return Scaffold(
        backgroundColor: AppTheme.bgPink,
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: const Center(child: Text('音乐服务未就绪,请完全退出应用后重新打开')),
      );
    }
    return _buildPage(context);
  }

  Widget _buildPage(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPink,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(_name,
            style: TextStyle(
                fontSize: 17.sp, fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
          : _failed
              ? _buildError()
              : _buildContent(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_rounded,
              size: 56.sp, color: Colors.black26),
          SizedBox(height: 16.h),
          Text('歌单加载失败',
              style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87)),
          SizedBox(height: 6.h),
          Text('请检查网络后重试',
              style: TextStyle(fontSize: 13.sp, color: Colors.black45)),
          SizedBox(height: 16.h),
          ElevatedButton.icon(
            onPressed: () => _load(force: true),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('重新加载'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        // 歌单头部（中世纪现代剪纸封套卡 + Q 弹播放全部按钮）
        Padding(
          padding: EdgeInsets.all(16.w),
          child: MemphisCard(
            color: AppTheme.paperWhite,
            borderRadius: 22.r,
            shadowOffset: 5.0,
            padding: EdgeInsets.all(14.w),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Transform.rotate(
                  angle: -0.025,
                  child: Container(
                    padding: EdgeInsets.all(5.w),
                    decoration: BoxDecoration(
                      color: AppTheme.cream,
                      borderRadius: BorderRadius.circular(16.r),
                      border: AppTheme.border(),
                      boxShadow: AppTheme.paperShadow(h: 7.0),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12.r),
                      child: Container(
                        width: 88.w,
                        height: 88.w,
                        color: AppTheme.tealSoft,
                        child: (_cover != null && _cover!.isNotEmpty)
                            ? Image.network(
                                _cover!,
                                fit: BoxFit.cover,
                                headers: coverHeadersFor(_cover),
                                errorBuilder: (ctx, err, st) => Icon(
                                    Icons.queue_music_rounded,
                                    color: AppTheme.tomato,
                                    size: 36.sp),
                              )
                            : Icon(Icons.queue_music_rounded,
                                color: AppTheme.tomato, size: 36.sp),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 14.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _name,
                        style: TextStyle(
                          fontSize: 18.sp,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.ink,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 5.h),
                      Text(
                        '共 ${_tracks.length} 首 · 网易云精选电台',
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSub,
                        ),
                      ),
                      SizedBox(height: 10.h),
                      MemphisButton(
                        text: '播放全部',
                        leading: Icon(Icons.play_circle_fill_rounded,
                            size: 18.sp, color: AppTheme.paperWhite),
                        color: AppTheme.tomato,
                        textColor: AppTheme.paperWhite,
                        borderRadius: 999,
                        fontSize: 13.5.sp,
                        padding: EdgeInsets.symmetric(
                            horizontal: 16.w, vertical: 8.h),
                        onTap: _playAll,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.paperWhite,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
              border: AppTheme.border(),
              boxShadow: AppTheme.paperShadow(h: 8.0),
            ),
            child: ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(vertical: 8.h),
              itemCount: _tracks.length,
              itemBuilder: (context, index) {
                final track = _tracks[index];
                return _buildTrackTile(track, index);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTrackTile(MusicTrack track, int index) {
    return BouncyTap(
      pressedScale: 0.97,
      onTap: () {
        _controller.playWithList(_tracks, track);
        Get.to(() => const MusicPlayerPage());
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 7.h),
        child: Row(
          children: [
            SizedBox(
              width: 26.w,
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w900,
                  color: index < 3 ? AppTheme.tomato : AppTheme.textSub,
                ),
              ),
            ),
            SizedBox(width: 8.w),
            ClipRRect(
              borderRadius: BorderRadius.circular(9.r),
              child: Container(
                width: 44.w,
                height: 44.w,
                color: AppTheme.tealSoft,
                child: (track.coverUrl != null && track.coverUrl!.isNotEmpty)
                    ? Image.network(
                        track.coverUrl!,
                        fit: BoxFit.cover,
                        headers: coverHeadersFor(track.coverUrl),
                        errorBuilder: (ctx, err, st) => Icon(
                            Icons.music_note,
                            color: AppTheme.tomato,
                            size: 18.sp),
                      )
                    : Icon(Icons.music_note,
                        color: AppTheme.tomato, size: 18.sp),
              ),
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.ink,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    track.artist,
                    style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSub,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Obx(() {
              final isChildMode = _modeController.isChildMode;
              final isFav = _controller.isFavorite(track);
              return IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: isChildMode
                      ? Colors.grey[300]
                      : (isFav ? AppTheme.tomato : AppTheme.textSub),
                  size: 18.sp,
                ),
                onPressed: isChildMode
                    ? () {
                        ToastUtils.showInfo('儿童模式下无法修改收藏,请切换到家长模式');
                      }
                    : () => _controller.toggleFavorite(track),
              );
            }),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.library_add_outlined,
                color: AppTheme.teal,
                size: 19.sp,
              ),
              tooltip: '收藏到歌单',
              onPressed: () => showAddToPlaylistsSheet(context, track),
            ),
          ],
        ),
      ),
    );
  }
}
