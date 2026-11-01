import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../controllers/music_player_controller.dart';
import '../../../controllers/app_mode_controller.dart';
import '../../../services/chksz_music_service.dart';
import '../../../models/music/music_track.dart';
import '../../../theme/app_theme.dart';
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
        // 歌单头部
        Padding(
          padding: EdgeInsets.all(16.w),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14.r),
                child: Container(
                  width: 96.w,
                  height: 96.w,
                  color: AppTheme.primary.withOpacity(0.12),
                  child: (_cover != null && _cover!.isNotEmpty)
                      ? Image.network(
                          _cover!,
                          fit: BoxFit.cover,
                          headers: coverHeadersFor(_cover),
                          errorBuilder: (ctx, err, st) => Icon(
                              Icons.queue_music_rounded,
                              color: AppTheme.primary,
                              size: 36.sp),
                        )
                      : Icon(Icons.queue_music_rounded,
                          color: AppTheme.primary, size: 36.sp),
                ),
              ),
              SizedBox(width: 14.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_name,
                        style: TextStyle(
                            fontSize: 19.sp, fontWeight: FontWeight.w800),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    SizedBox(height: 6.h),
                    Text('共 ${_tracks.length} 首 · 来自网易云音乐',
                        style: TextStyle(
                            fontSize: 12.sp, color: Colors.black45)),
                    SizedBox(height: 12.h),
                    ElevatedButton.icon(
                      onPressed: _playAll,
                      icon: const Icon(Icons.play_circle_fill, size: 20),
                      label: const Text('播放全部'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                            horizontal: 16.w, vertical: 8.h),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20.r)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(20.r)),
            ),
            child: ListView.builder(
              padding: EdgeInsets.symmetric(vertical: 8.h),
              itemCount: _tracks.length,
              itemBuilder: (context, index) {
                final track = _tracks[index];
                return _buildTrackTile(track);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTrackTile(MusicTrack track) {
    return InkWell(
      onTap: () {
        _controller.playWithList(_tracks, track);
        Get.to(() => const MusicPlayerPage());
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 6.h),
        child: Row(
          children: [
            SizedBox(
              width: 24.w,
              child: Text('${_tracks.indexOf(track) + 1}',
                  style:
                      TextStyle(fontSize: 13.sp, color: Colors.black26)),
            ),
            SizedBox(width: 8.w),
            ClipRRect(
              borderRadius: BorderRadius.circular(8.r),
              child: Container(
                width: 44.w,
                height: 44.w,
                color: AppTheme.primary.withOpacity(0.1),
                child: (track.coverUrl != null &&
                        track.coverUrl!.isNotEmpty)
                    ? Image.network(
                        track.coverUrl!,
                        fit: BoxFit.cover,
                        headers: coverHeadersFor(track.coverUrl),
                        errorBuilder: (ctx, err, st) => Icon(
                            Icons.music_note,
                            color: AppTheme.primary,
                            size: 18.sp),
                      )
                    : Icon(Icons.music_note,
                        color: AppTheme.primary, size: 18.sp),
              ),
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(track.title,
                      style: TextStyle(
                          fontSize: 14.sp, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  SizedBox(height: 2.h),
                  Text(track.artist,
                      style: TextStyle(
                          fontSize: 11.sp, color: Colors.black45),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Obx(() {
              final isChildMode = _modeController.isChildMode;
              final isFav = _controller.isFavorite(track);
              return IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  isFav ? Icons.favorite : Icons.favorite_border,
                  color: isChildMode
                      ? Colors.grey[300]
                      : (isFav ? Colors.redAccent : Colors.grey),
                  size: 18.sp,
                ),
                onPressed: isChildMode
                    ? () {
                        ToastUtils.showInfo('儿童模式下无法修改收藏,请切换到家长模式');
                      }
                    : () => _controller.toggleFavorite(track),
              );
            }),
          ],
        ),
      ),
    );
  }
}
