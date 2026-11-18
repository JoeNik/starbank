import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../controllers/music_player_controller.dart';
import '../../../controllers/app_mode_controller.dart';
import '../../../services/chksz_music_service.dart';
import '../../../services/music_source.dart';
import '../../../services/tunehub_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/memphis_widgets.dart';
import '../../../widgets/module_background_scene.dart';
import '../../../models/music/music_track.dart';
import '../../../models/music/playlist.dart';
import 'music_player_page.dart';
import 'playlist_detail_page.dart';
import '../../../widgets/music_cover_image.dart';
import '../../../widgets/toast_utils.dart';

class MusicHomePage extends StatefulWidget {
  const MusicHomePage({super.key});

  @override
  State<MusicHomePage> createState() => _MusicHomePageState();
}

class _MusicHomePageState extends State<MusicHomePage> {
  // 服务以 late/可空方式获取:热重载或初始化异常时优雅降级,而不是整页崩溃
  late final MusicPlayerController _controller =
      Get.find<MusicPlayerController>();
  final AppModeController _modeController = Get.find<AppModeController>();
  TuneHubService? get _tuneHubService =>
      Get.isRegistered<TuneHubService>() ? Get.find<TuneHubService>() : null;
  MusicSourceRegistry? get _sourceRegistry =>
      Get.isRegistered<MusicSourceRegistry>()
          ? Get.find<MusicSourceRegistry>()
          : null;
  ChkSzMusicService? get _chkszService =>
      Get.isRegistered<ChkSzMusicService>()
          ? Get.find<ChkSzMusicService>()
          : null;
  final TextEditingController _searchController = TextEditingController();

  final RxList<MusicTrack> _searchResults = <MusicTrack>[].obs;
  final RxBool _isSearching = false.obs;
  final RxBool _isMoreLoading = false.obs; // 是否正在加载更多
  final RxString _selectedPlatform = 'netease'.obs;
  final ScrollController _scrollController = ScrollController();
  int _currentPage = 1; // 当前页码

  // 音乐舱四大分区 Tab：0=发现热榜, 1=我的歌单(多歌单), 2=最爱单曲, 3=播放记录
  final RxInt _activeHubTab = 0.obs;

  final Map<String, String> _platforms = {
    'netease': '网易',
    'kuwo': '酷我',
    'qq': 'QQ音乐',
  };

  // 儿童向热门搜索词
  static const List<String> _hotKeywords = [
    '儿歌',
    '孤勇者',
    '小星星',
    '汪汪队立大功',
    '生日快乐歌',
    '超级飞侠',
  ];

  // 网易云官方精选歌单(ChKSz 歌单接口可直达)
  static const List<Map<String, String>> _curatedPlaylists = [
    {'id': '3778678', 'name': '云音乐热歌榜'},
    {'id': '3779629', 'name': '云音乐新歌榜'},
    {'id': '19723756', 'name': '云音乐飙升榜'},
    {'id': '745956260', 'name': '原创歌曲榜'},
  ];

  bool _isImportingPlaylist = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadCuratedPlaylists();
  }

  /// 错峰懒加载精选歌单的封面与名称(结果与详情页共享缓存)
  void _loadCuratedPlaylists() {
    final chksz = _chkszService;
    if (chksz == null) return;
    Future(() async {
      // 逐个串行 + 间隔,避免开屏时并发轰炸网络与主线程
      for (final preset in _curatedPlaylists) {
        final id = preset['id']!;
        if (!PlaylistDetailPage.cache.containsKey(id)) {
          try {
            final result = await chksz.fetchPlaylist(id);
            final tracks = result['tracks'];
            if (mounted && tracks is List && tracks.isNotEmpty) {
              setState(() {
                PlaylistDetailPage.cache[id] = result;
              });
            }
          } catch (_) {
            // 加载失败时卡片保留占位图,不打扰用户
          }
        }
        await Future.delayed(const Duration(milliseconds: 400));
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200.h &&
        !_isSearching.value &&
        !_isMoreLoading.value &&
        _searchResults.isNotEmpty) {
      _doSearch(loadMore: true);
    }
  }

  /// 按平台路由搜索音源:网易走当前激活音源(ChKSz/TuneHub),酷我/QQ 走 TuneHub。
  /// 激活音源无结果时自动回退 TuneHub,保证搜索尽量有产出。
  Future<List<MusicTrack>> _routeSearch(
      String keyword, String platform, int page) async {
    if (platform == 'netease') {
      final active = _sourceRegistry?.active;
      if (active != null && active.isConfigured && active.id != 'tunehub') {
        final results =
            await active.searchMusic(keyword, platform: platform, page: page);
        if (results.isNotEmpty) return results;
        debugPrint('⚠️ [Search] ${active.displayName} 无结果,回退 TuneHub');
      }
    }
    final tunehub = _tuneHubService;
    if (tunehub == null) return const [];
    return tunehub.searchMusic(keyword, platform: platform, page: page);
  }

  void _doSearch({bool loadMore = false}) async {
    if (_searchController.text.isEmpty) return;

    if (!loadMore) {
      FocusScope.of(context).unfocus();
      _isSearching.value = true;
      _searchResults.clear();
      _currentPage = 1;
    } else {
      _isMoreLoading.value = true;
      _currentPage++;
    }

    try {
      final results = await _routeSearch(_searchController.text,
          _selectedPlatform.value, _currentPage);

      if (loadMore) {
        if (results.isEmpty) {
          ToastUtils.showInfo('已经到底啦');
          _currentPage--; // 恢复页码
        } else {
          _searchResults.addAll(results);
        }
      } else {
        _searchResults.assignAll(results);
        // 首次搜索无结果时提示
        if (results.isEmpty) {
          ToastUtils.showInfo('未找到相关歌曲,请尝试其他关键词或平台');
        }
      }
    } catch (e) {
      ToastUtils.showError('搜索失败: $e');
      if (loadMore) _currentPage--;
    } finally {
      _isSearching.value = false;
      _isMoreLoading.value = false;
    }
  }

  String _activeSourceDebugInfo() {
    if (_selectedPlatform.value != 'netease') {
      return _tuneHubService?.lastSearchDebugInfo ?? '';
    }
    return _sourceRegistry?.active?.lastDebugInfo ?? '';
  }

  void _playTrackNow(MusicTrack track) {
    _controller.playWithList(_searchResults.toList(), track);
    Get.to(() => const MusicPlayerPage());
  }

  /// 长按歌曲弹出的操作面板
  void _showTrackActions(MusicTrack track) {
    final isChildMode = _modeController.isChildMode;
    final isFav = _controller.isFavorite(track);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          margin: EdgeInsets.all(12.w),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20.r),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.all(16.w),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8.r),
                      child: _coverImage(track.coverUrl, 42.w),
                    ),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: Text(
                        '${track.title} - ${track.artist}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14.sp, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.play_circle_fill,
                    color: AppTheme.primary),
                title: const Text('立即播放'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _playTrackNow(track);
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.queue_music, color: Colors.deepPurple),
                title: const Text('下一首播放'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _controller.playNextInQueue(track);
                },
              ),
              ListTile(
                leading: Icon(
                  isFav ? Icons.favorite : Icons.favorite_border,
                  color: Colors.redAccent,
                ),
                title: Text(isFav ? '取消收藏' : '加入收藏'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  if (isChildMode) {
                    ToastUtils.showInfo('儿童模式下无法修改收藏,请切换到家长模式');
                    return;
                  }
                  _controller.toggleFavorite(track);
                },
              ),
              SizedBox(height: 10.h),
            ],
          ),
        );
      },
    );
  }

  // === 快捷音源切换面板 ===

  void _showSourceSwitcher() {
    final registry = _sourceRegistry;
    if (registry == null) {
      ToastUtils.showInfo('音源管理未就绪,请完全退出应用后重新打开');
      return;
    }
    final sources = registry.sources;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          margin: EdgeInsets.all(12.w),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20.r),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 4.h),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('选择音源',
                          style: TextStyle(
                              fontSize: 16.sp, fontWeight: FontWeight.w700)),
                      SizedBox(width: 8.w),
                      Padding(
                        padding: EdgeInsets.only(bottom: 2.h),
                        child: Text('对网易平台的搜索与解析生效',
                            style: TextStyle(
                                fontSize: 11.sp, color: Colors.black38)),
                      ),
                    ],
                  ),
                ),
                ...sources.map((source) {
                  final isActive =
                      registry.activeSourceId.value == source.id;
                  return ListTile(
                    leading: Icon(
                      isActive
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color:
                          isActive ? AppTheme.primary : Colors.black26,
                    ),
                    title: Text(
                      source.displayName,
                      style: TextStyle(
                          fontSize: 15.sp,
                          fontWeight: isActive
                              ? FontWeight.w700
                              : FontWeight.w500),
                    ),
                    subtitle: Text(
                      source.isConfigured ? '已就绪' : '未配置,请先在设置中完善',
                      style: TextStyle(fontSize: 12.sp),
                    ),
                    trailing: isActive
                        ? Icon(Icons.check_rounded,
                            color: AppTheme.primary)
                        : null,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _switchSource(source.id);
                    },
                  );
                }),
                const Divider(height: 1),
                ListTile(
                  leading:
                      Icon(Icons.settings_outlined, color: Colors.black45),
                  title: Text('音乐源设置 / 歌单导入',
                      style: TextStyle(fontSize: 14.sp)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showSettings();
                  },
                ),
                SizedBox(height: 8.h),
              ],
            ),
          ),
        );
      },
    );
  }

  void _switchSource(String id) {
    final registry = _sourceRegistry;
    if (registry == null) return;
    if (registry.activeSourceId.value == id) return;
    registry.setActive(id);
    ToastUtils.showSuccess('已切换到 ${registry.byId(id)?.displayName ?? id}');
    // 当前正在网易平台搜索时,立即用新音源重搜
    if (_selectedPlatform.value == 'netease' &&
        _searchController.text.isNotEmpty) {
      _doSearch();
    }
  }

  // === 设置面板(音源 / TuneHub / ChKSz / 歌单导入) ===

  void _showSettings() {
    final tunehub = _tuneHubService;
    final chksz = _chkszService;
    if (tunehub == null || chksz == null) {
      ToastUtils.showInfo('音乐服务未就绪,请完全退出应用后重新打开');
      return;
    }
    final urlCtrl = TextEditingController(text: tunehub.baseUrl.value);
    final keyCtrl = TextEditingController(text: tunehub.apiKey.value);
    final chkszKeyCtrl = TextEditingController(text: chksz.apiKey.value);
    final playlistCtrl = TextEditingController();
    String selectedSource =
        _sourceRegistry?.activeSourceId.value ?? 'chksz';
    String selectedQuality = chksz.quality.value;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(builder: (context, setSheetState) {
          Future<void> importPlaylist() async {
            if (_isImportingPlaylist) return;
            if (playlistCtrl.text.trim().isEmpty) {
              ToastUtils.showInfo('请输入网易云歌单链接或 ID');
              return;
            }
            setSheetState(() => _isImportingPlaylist = true);
            final result = await chksz.fetchPlaylist(playlistCtrl.text);
            setSheetState(() => _isImportingPlaylist = false);
            final tracks = result['tracks'];
            if (tracks is! List<MusicTrack> || tracks.isEmpty) {
              ToastUtils.showError('歌单导入失败,请检查链接');
              return;
            }
            if (mounted && sheetContext.mounted) Navigator.pop(sheetContext);
            _controller.playWithList(tracks, tracks.first);
            ToastUtils.showSuccess(
                '已导入「${result['name']}」共 ${tracks.length} 首');
          }

          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
            child: Container(
              constraints: BoxConstraints(maxHeight: 0.85.sh),
              margin: EdgeInsets.all(12.w),
              padding: EdgeInsets.all(20.w),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24.r),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('音乐源设置',
                        style: TextStyle(
                            fontSize: 18.sp, fontWeight: FontWeight.w800)),
                    SizedBox(height: 8.h),
                    RadioListTile<String>(
                      value: 'chksz',
                      groupValue: selectedSource,
                      onChanged: (v) =>
                          setSheetState(() => selectedSource = v ?? 'chksz'),
                      title: Text('ChKSz·网易',
                          style: TextStyle(
                              fontSize: 15.sp, fontWeight: FontWeight.w600)),
                      subtitle: Text('需自行填入 API Key · 无损/Hi-Res 高音质解析',
                          style: TextStyle(fontSize: 12.sp)),
                      activeColor: AppTheme.primary,
                      contentPadding: EdgeInsets.zero,
                    ),
                    RadioListTile<String>(
                      value: 'tunehub',
                      groupValue: selectedSource,
                      onChanged: (v) =>
                          setSheetState(() => selectedSource = v ?? 'tunehub'),
                      title: Text('TuneHub',
                          style: TextStyle(
                              fontSize: 15.sp, fontWeight: FontWeight.w600)),
                      subtitle: Text('自建服务 · 支持酷我/QQ/网易',
                          style: TextStyle(fontSize: 12.sp)),
                      activeColor: AppTheme.primary,
                      contentPadding: EdgeInsets.zero,
                    ),
                    const Divider(),
                    Text('TuneHub 配置',
                        style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w700,
                            color: Colors.black54)),
                    SizedBox(height: 8.h),
                    TextField(
                      controller: urlCtrl,
                      decoration:
                          const InputDecoration(labelText: 'API Base URL'),
                    ),
                    TextField(
                      controller: keyCtrl,
                      decoration: const InputDecoration(
                          labelText: 'API Keys (用;分隔多个Key)'),
                    ),
                    SizedBox(height: 12.h),
                    const Divider(),
                    Text('ChKSz 配置',
                        style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w700,
                            color: Colors.black54)),
                    SizedBox(height: 8.h),
                    TextField(
                      controller: chkszKeyCtrl,
                      decoration:
                          const InputDecoration(labelText: 'API Key'),
                    ),
                    DropdownButtonFormField<String>(
                      value: selectedQuality,
                      decoration: const InputDecoration(labelText: '音质偏好'),
                      items: ChkSzMusicService.kQualityLevels
                          .map((level) => DropdownMenuItem(
                                value: level,
                                child: Text(
                                    '${ChkSzMusicService.qualityLabel(level)} ($level)'),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setSheetState(() => selectedQuality = v);
                      },
                    ),
                    SizedBox(height: 12.h),
                    const Divider(),
                    Text('导入网易云歌单',
                        style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w700,
                            color: Colors.black54)),
                    SizedBox(height: 8.h),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: playlistCtrl,
                            decoration: const InputDecoration(
                                hintText: '粘贴歌单链接或 ID'),
                          ),
                        ),
                        SizedBox(width: 10.w),
                        ElevatedButton.icon(
                          onPressed:
                              _isImportingPlaylist ? null : importPlaylist,
                          icon: _isImportingPlaylist
                              ? SizedBox(
                                  width: 14.w,
                                  height: 14.w,
                                  child: const CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Icon(Icons.playlist_add, size: 18),
                          label: const Text('导入'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 20.h),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          _tuneHubService?.updateConfig(urlCtrl.text, keyCtrl.text);
                          chksz.updateConfig(chkszKeyCtrl.text, selectedQuality);
                          _sourceRegistry?.setActive(selectedSource);
                          Navigator.pop(sheetContext);
                          ToastUtils.showSuccess('音乐源设置已保存');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 12.h),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14.r)),
                        ),
                        child: Text('保存',
                            style: TextStyle(
                                fontSize: 15.sp, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    SizedBox(height: 8.h),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<MusicPlayerController>()) {
      return _buildServiceMissingPage();
    }
    return _buildHomePage(context);
  }

  Widget _buildServiceMissingPage() {
    return Scaffold(
      backgroundColor: AppTheme.bgPink,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('音乐乐园',
            style: TextStyle(
                fontSize: 22.sp, fontWeight: FontWeight.w800)),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_off_rounded, size: 56.sp, color: Colors.black26),
            SizedBox(height: 12.h),
            Text('音乐服务未就绪',
                style: TextStyle(
                    fontSize: 16.sp, fontWeight: FontWeight.w600)),
            SizedBox(height: 6.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 32.w),
              child: Text(
                '请完全退出应用后重新打开,以完成音乐模块初始化',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.sp, color: Colors.black45),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomePage(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.cream,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          '音乐乐园',
          style: TextStyle(
            fontSize: 21.sp,
            fontWeight: FontWeight.w900,
            color: AppTheme.ink,
            letterSpacing: 0.5,
          ),
        ),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: 12.w),
            child: MemphisIconButton(
              icon: Icons.tune_rounded,
              size: 38.w,
              iconSize: 20.sp,
              tooltip: '音乐源设置',
              onTap: _showSettings,
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: ModuleBackgroundScene(
              theme: ModuleBackgroundTheme.entertainment,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // 中世纪现代剪纸搜索栏（暖白纸 + 暖棕高度阴影 h=8）
                Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 8.h),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.paperWhite,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(20.r),
                        topRight: Radius.circular(15.r),
                        bottomLeft: Radius.circular(16.r),
                        bottomRight: Radius.circular(22.r),
                      ),
                      border: AppTheme.border(),
                      boxShadow: AppTheme.paperShadow(h: 8.0),
                    ),
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _searchController,
                      builder: (context, value, _) {
                        return TextField(
                          controller: _searchController,
                          textInputAction: TextInputAction.search,
                          style: TextStyle(
                            color: AppTheme.ink,
                            fontWeight: FontWeight.w800,
                            fontSize: 14.sp,
                          ),
                          decoration: InputDecoration(
                            hintText: '搜索儿歌、故事、歌手...',
                            hintStyle: TextStyle(
                              color: AppTheme.textSub,
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5.sp,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            prefixIcon: const Icon(Icons.search_rounded,
                                color: AppTheme.tomato),
                            suffixIcon: value.text.isEmpty
                                ? IconButton(
                                    icon: const Icon(
                                        Icons.arrow_forward_rounded,
                                        color: AppTheme.tomato),
                                    onPressed: _doSearch,
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.close_rounded,
                                        size: 20, color: AppTheme.textSub),
                                    onPressed: () {
                                      _searchController.clear();
                                      _searchResults.clear();
                                      setState(() {});
                                    },
                                  ),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 16.w, vertical: 14.h),
                          ),
                          onSubmitted: (_) => _doSearch(),
                        );
                      },
                    ),
                  ),
                ),

                // 平台切换剪纸胶囊 + 快捷音源切换
                Obx(() => Container(
                      height: 44.h,
                      padding: EdgeInsets.symmetric(horizontal: 16.w),
                      child: Row(
                        children: [
                          Expanded(
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: _platforms.entries.map((entry) {
                                final isSelected =
                                    _selectedPlatform.value == entry.key;
                                return Padding(
                                  padding: EdgeInsets.only(
                                      right: 8.w, top: 4.h, bottom: 4.h),
                                  child: BouncyTap(
                                    onTap: () {
                                      if (!isSelected) {
                                        _selectedPlatform.value = entry.key;
                                        if (_searchController.text.isNotEmpty) {
                                          _doSearch();
                                        }
                                      }
                                    },
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 220),
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 14.w, vertical: 6.h),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? AppTheme.tomato
                                            : AppTheme.paperWhite,
                                        borderRadius:
                                            BorderRadius.circular(999),
                                        border: AppTheme.border(),
                                        boxShadow: AppTheme.paperShadow(
                                            h: isSelected ? 6.0 : 3.0),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        entry.value,
                                        style: TextStyle(
                                          color: isSelected
                                              ? AppTheme.paperWhite
                                              : AppTheme.ink,
                                          fontSize: 12.sp,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          if (_selectedPlatform.value == 'netease' &&
                              _sourceRegistry != null)
                            BouncyTap(
                              onTap: _showSourceSwitcher,
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 10.w, vertical: 5.h),
                                decoration: BoxDecoration(
                                  color: AppTheme.yellow,
                                  borderRadius: BorderRadius.circular(999),
                                  border: AppTheme.border(),
                                  boxShadow: AppTheme.paperShadow(h: 4.0),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.swap_horiz_rounded,
                                        size: 14.sp, color: AppTheme.ink),
                                    SizedBox(width: 4.w),
                                    Obx(() => Text(
                                          _sourceRegistry
                                                  ?.active?.displayName ??
                                              '未选择',
                                          style: TextStyle(
                                            fontSize: 11.sp,
                                            color: AppTheme.ink,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        )),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    )),

            // Results
            Expanded(
              child: Obx(() {
                if (_isSearching.value) {
                  return Center(
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: AppTheme.primary),
                  );
                }

                // 搜索无结果:空态 + 调试信息
                if (_searchResults.isEmpty &&
                    _searchController.text.isNotEmpty) {
                  return Center(
                    child: Padding(
                      padding: EdgeInsets.all(20.w),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.music_off,
                              size: 60.sp, color: Colors.black26),
                          SizedBox(height: 16.h),
                          Text('没有找到结果',
                              style: TextStyle(
                                  fontSize: 17.sp,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87)),
                          SizedBox(height: 6.h),
                          Text('换个关键词或平台试试吧',
                              style: TextStyle(
                                  fontSize: 13.sp, color: Colors.black45)),
                          SizedBox(height: 16.h),
                          TextButton.icon(
                            onPressed: () {
                              final info = _activeSourceDebugInfo();
                              Get.dialog(
                                AlertDialog(
                                  title: const Text('搜索调试信息'),
                                  content: SingleChildScrollView(
                                    child: SelectableText(
                                      info.isEmpty ? '暂无调试信息' : info,
                                      style: TextStyle(
                                        fontSize: 12.sp,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Get.back(),
                                      child: const Text('关闭'),
                                    ),
                                  ],
                                ),
                              );
                            },
                            icon: const Icon(Icons.bug_report, size: 18),
                            label: const Text('查看调试信息'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // 未搜索时：展示中世纪现代四大音乐舱 Tab（发现 / 我的歌单 / 最爱单曲 / 播放记录）
                if (_searchResults.isEmpty) {
                  return Column(
                    children: [
                      _buildHubTabsRow(),
                      Expanded(
                        child: Obx(() {
                          switch (_activeHubTab.value) {
                            case 1:
                              return _buildPlaylistsTab(context);
                            case 2:
                              return _buildFavoritesTab(context);
                            case 3:
                              return _buildHistoryTab(context);
                            case 0:
                            default:
                              return _buildDiscoverTab(context);
                          }
                        }),
                      ),
                    ],
                  );
                }

                // 搜索结果列表（顶部带一键返回音乐库条）
                return Column(
                  children: [
                    Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
                      child: Row(
                        children: [
                          Text(
                            '🔍 搜索结果 (${_searchResults.length})',
                            style: TextStyle(
                              fontSize: 13.5.sp,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.ink,
                            ),
                          ),
                          const Spacer(),
                          BouncyTap(
                            onTap: () {
                              _searchController.clear();
                              _searchResults.clear();
                              setState(() {});
                            },
                            child: MemphisTag(
                              text: '← 返回音乐库',
                              color: AppTheme.yellow,
                              fontSize: 11.sp,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: _scrollController,
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.symmetric(horizontal: 12.w),
                        itemCount: _searchResults.length +
                            (_isMoreLoading.value ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _searchResults.length) {
                            return Padding(
                              padding: EdgeInsets.symmetric(vertical: 20.h),
                              child: const Center(
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            );
                          }
                          final track = _searchResults[index];
                          return _buildSongTile(track, _searchResults);
                        },
                      ),
                    ),
                  ],
                );
              }),
            ),

            // Mini Player(悬浮卡片)
            _buildMiniPlayer(),
          ],
        ),
      ),
        ],
      ),
    );
  }

  // ==================== 四大音乐舱 Tab 导航与内容 ====================

  Widget _buildHubTabsRow() {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 8.h),
      child: Obx(() {
        final cur = _activeHubTab.value;
        final plCount = _controller.customPlaylists.length;
        final favCount = _controller.favorites.length;
        final histCount = _controller.history.length;
        final tabs = [
          (idx: 0, label: '🔥 发现', badge: ''),
          (idx: 1, label: '📁 歌单', badge: '$plCount'),
          (idx: 2, label: '❤️ 最爱', badge: '$favCount'),
          (idx: 3, label: '🕒 记录', badge: '$histCount'),
        ];

        return Row(
          children: tabs.map((t) {
            final active = cur == t.idx;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: t.idx < 3 ? 6.w : 0),
                child: BouncyTap(
                  onTap: () => _activeHubTab.value = t.idx,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutBack,
                    padding: EdgeInsets.symmetric(vertical: 8.h),
                    decoration: BoxDecoration(
                      color: active ? AppTheme.yellow : AppTheme.paperWhite,
                      borderRadius: BorderRadius.circular(14.r),
                      border: AppTheme.border(),
                      boxShadow: AppTheme.paperShadow(h: active ? 6.0 : 3.0),
                    ),
                    alignment: Alignment.center,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6.w),
                        child: Text(
                          t.badge.isEmpty ? t.label : '${t.label}(${t.badge})',
                          style: TextStyle(
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      }),
    );
  }

  /// Tab 0：发现与热榜（热门搜索词 + 网易精选歌单 + 快捷音乐库入口）
  Widget _buildDiscoverTab(BuildContext context) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      children: [
        Padding(
          padding: EdgeInsets.only(top: 4.h, bottom: 8.h),
          child: Row(
            children: [
              Icon(Icons.local_fire_department_rounded,
                  size: 18.sp, color: AppTheme.tomato),
              SizedBox(width: 6.w),
              Text(
                '热门儿歌搜索',
                style: TextStyle(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.ink,
                ),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 8.w,
          runSpacing: 8.h,
          children: _hotKeywords
              .map((keyword) => BouncyTap(
                    onTap: () {
                      _searchController.text = keyword;
                      _doSearch();
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: 14.w, vertical: 7.h),
                      decoration: BoxDecoration(
                        color: AppTheme.paperWhite,
                        borderRadius: BorderRadius.circular(999),
                        border: AppTheme.border(),
                        boxShadow: AppTheme.paperShadow(h: 4.5),
                      ),
                      child: Text(
                        keyword,
                        style: TextStyle(
                          fontSize: 12.5.sp,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.ink,
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ),
        SizedBox(height: 18.h),
        _buildDiscoverSection(),
        SizedBox(height: 16.h),

        // 快捷歌单与最近播放概览入口卡
        Row(
          children: [
            Expanded(
              child: MemphisCard(
                color: AppTheme.tealSoft,
                borderRadius: 18.r,
                padding: EdgeInsets.all(12.w),
                onTap: () => _activeHubTab.value = 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '📁 我的收藏歌单',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.ink,
                      ),
                    ),
                    SizedBox(height: 3.h),
                    Obx(() => Text(
                          '${_controller.customPlaylists.length} 个分类歌单 · 点此管理',
                          style: TextStyle(
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textSub,
                          ),
                        )),
                  ],
                ),
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: MemphisCard(
                color: AppTheme.pinkSoft,
                borderRadius: 18.r,
                padding: EdgeInsets.all(12.w),
                onTap: () => _activeHubTab.value = 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🕒 最近播放记录',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.ink,
                      ),
                    ),
                    SizedBox(height: 3.h),
                    Obx(() => Text(
                          '已记录 ${_controller.history.length} 首 · 点此续播',
                          style: TextStyle(
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textSub,
                          ),
                        )),
                  ],
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 20.h),
      ],
    );
  }

  /// Tab 1：我的歌单（支持创建多个收藏歌单、重命名、删除、查看与一键播放）
  Widget _buildPlaylistsTab(BuildContext context) {
    return Obx(() {
      final list = _controller.customPlaylists;
      final favCount = _controller.favorites.length;

      return ListView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
        children: [
          // 顶部操作栏：新建自定义歌单
          Row(
            children: [
              Text(
                '共 ${list.length + 1} 个收藏歌单',
                style: TextStyle(
                  fontSize: 13.5.sp,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.ink,
                ),
              ),
              const Spacer(),
              MemphisButton(
                text: '＋ 新建歌单',
                color: AppTheme.tomato,
                textColor: AppTheme.paperWhite,
                borderRadius: 999,
                fontSize: 12.sp,
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
                onTap: () => _promptCreateOrRenamePlaylist(context),
              ),
            ],
          ),
          SizedBox(height: 10.h),

          // 默认主歌单：「❤️ 我的最爱」置顶大卡片
          MemphisCard(
            color: AppTheme.pinkSoft,
            borderRadius: 18.r,
            padding: EdgeInsets.all(14.w),
            onTap: () => _activeHubTab.value = 2,
            child: Row(
              children: [
                Container(
                  width: 54.w,
                  height: 54.w,
                  decoration: BoxDecoration(
                    color: AppTheme.tomato,
                    borderRadius: BorderRadius.circular(14.r),
                    boxShadow: AppTheme.paperShadow(h: 5.0),
                  ),
                  child: Icon(Icons.favorite_rounded,
                      color: AppTheme.paperWhite, size: 28.sp),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '❤️ 我的最爱（默认收藏）',
                        style: TextStyle(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.ink,
                        ),
                      ),
                      SizedBox(height: 3.h),
                      Text(
                        '已收藏 $favCount 首单曲 · 点击查看完整列表',
                        style: TextStyle(
                          fontSize: 11.5.sp,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSub,
                        ),
                      ),
                    ],
                  ),
                ),
                MemphisIconButton(
                  icon: Icons.play_arrow_rounded,
                  bgColor: AppTheme.tomato,
                  iconColor: AppTheme.paperWhite,
                  size: 38.w,
                  onTap: () {
                    _controller.playFavorites();
                    if (_controller.favorites.isNotEmpty) {
                      Get.to(() => const MusicPlayerPage());
                    }
                  },
                ),
              ],
            ),
          ),
          SizedBox(height: 10.h),

          // 用户所有自定义分类歌单
          ...list.map((pl) {
            return Padding(
              padding: EdgeInsets.only(bottom: 10.h),
              child: MemphisCard(
                color: AppTheme.paperWhite,
                borderRadius: 18.r,
                padding: EdgeInsets.all(12.w),
                onTap: () => _openCustomPlaylistSheet(context, pl.id),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12.r),
                      child: _coverImage(pl.coverUrl, 52.w),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pl.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15.sp,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.ink,
                            ),
                          ),
                          SizedBox(height: 3.h),
                          Text(
                            pl.tracks.isEmpty
                                ? '空歌单 · 在歌曲旁点「📁」即可加入'
                                : '共 ${pl.tracks.length} 首 · 点开管理或播放',
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
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.edit_outlined,
                          size: 19.sp, color: AppTheme.textSub),
                      tooltip: '重命名歌单',
                      onPressed: () =>
                          _promptCreateOrRenamePlaylist(context, existing: pl),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.delete_outline_rounded,
                          size: 19.sp, color: AppTheme.textSub),
                      tooltip: '删除歌单',
                      onPressed: () {
                        _controller.deleteCustomPlaylist(pl.id);
                        ToastUtils.showInfo('已删除歌单「${pl.name}」');
                      },
                    ),
                    MemphisIconButton(
                      icon: Icons.play_arrow_rounded,
                      bgColor: pl.tracks.isEmpty
                          ? AppTheme.creamDeep
                          : AppTheme.teal,
                      iconColor: pl.tracks.isEmpty
                          ? AppTheme.textSub
                          : AppTheme.paperWhite,
                      size: 36.w,
                      onTap: pl.tracks.isEmpty
                          ? () => ToastUtils.showInfo('这个歌单还没有添加歌曲哦～')
                          : () {
                              _controller.playWithList(
                                  pl.tracks, pl.tracks.first);
                              Get.to(() => const MusicPlayerPage());
                            },
                    ),
                  ],
                ),
              ),
            );
          }),
          SizedBox(height: 20.h),
        ],
      );
    });
  }

  /// Tab 2：最爱单曲（清爽不折叠，支持一键播放全部、随机播放、加入其他歌单）
  Widget _buildFavoritesTab(BuildContext context) {
    return Obx(() {
      final favs = _controller.favorites;
      if (favs.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.favorite_border_rounded,
                  size: 52.sp, color: AppTheme.textSub),
              SizedBox(height: 10.h),
              Text(
                '还没有最爱单曲哦',
                style: TextStyle(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.ink,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                '在播放器或搜索列表中点 ❤️ 即可快速收藏到这里',
                style: TextStyle(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSub,
                ),
              ),
            ],
          ),
        );
      }

      return Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
            child: Row(
              children: [
                MemphisButton(
                  text: '▶ 播放全部 (${favs.length})',
                  color: AppTheme.tomato,
                  textColor: AppTheme.paperWhite,
                  borderRadius: 999,
                  fontSize: 12.5.sp,
                  padding:
                      EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
                  onTap: () {
                    _controller.playWithList(favs, favs.first);
                    Get.to(() => const MusicPlayerPage());
                  },
                ),
                SizedBox(width: 8.w),
                MemphisButton(
                  text: '🔀 随机播放',
                  color: AppTheme.yellow,
                  textColor: AppTheme.ink,
                  borderRadius: 999,
                  fontSize: 12.5.sp,
                  padding:
                      EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
                  onTap: () {
                    _controller.playMode.value = PlayMode.shuffle;
                    final rndTrack =
                        favs[DateTime.now().millisecond % favs.length];
                    _controller.playWithList(favs, rndTrack);
                    Get.to(() => const MusicPlayerPage());
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
              itemCount: favs.length,
              itemBuilder: (context, index) {
                return _buildSongTile(favs[index], favs);
              },
            ),
          ),
        ],
      );
    });
  }

  /// Tab 3：播放记录（支持一键续播、单条删除、一键清空、一键加歌单）
  Widget _buildHistoryTab(BuildContext context) {
    return Obx(() {
      final hist = _controller.history;
      if (hist.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history_rounded, size: 52.sp, color: AppTheme.textSub),
              SizedBox(height: 10.h),
              Text(
                '暂无播放记录',
                style: TextStyle(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.ink,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                '听过的儿歌和故事会自动保存在这里，方便随时重温',
                style: TextStyle(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSub,
                ),
              ),
            ],
          ),
        );
      }

      return Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
            child: Row(
              children: [
                MemphisButton(
                  text: '▶ 播放全部记录 (${hist.length})',
                  color: AppTheme.teal,
                  textColor: AppTheme.paperWhite,
                  borderRadius: 999,
                  fontSize: 12.5.sp,
                  padding:
                      EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
                  onTap: () {
                    _controller.playWithList(hist, hist.first);
                    Get.to(() => const MusicPlayerPage());
                  },
                ),
                const Spacer(),
                BouncyTap(
                  onTap: () {
                    _controller.clearHistory();
                    ToastUtils.showInfo('已清空播放记录');
                  },
                  child: Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                    decoration: BoxDecoration(
                      color: AppTheme.tomatoSoft,
                      borderRadius: BorderRadius.circular(999),
                      border: AppTheme.border(),
                    ),
                    child: Text(
                      '🧹 清空记录',
                      style: TextStyle(
                        fontSize: 11.5.sp,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.tomato,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
              itemCount: hist.length,
              itemBuilder: (context, index) {
                final track = hist[index];
                return _buildSongTile(
                  track,
                  hist,
                  onDeleteHistory: () => _controller.removeFromHistory(track),
                );
              },
            ),
          ),
        ],
      );
    });
  }

  /// 新建或重命名自定义歌单弹窗
  void _promptCreateOrRenamePlaylist(BuildContext context,
      {Playlist? existing}) {
    if (_modeController.isChildMode) {
      ToastUtils.showInfo('儿童模式下无法修改歌单，请先切换到家长模式');
      return;
    }
    final ctrl = TextEditingController(text: existing?.name ?? '');
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
                  existing == null ? '📁 新建收藏歌单' : '✏️ 重命名歌单',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.ink,
                  ),
                ),
                SizedBox(height: 12.h),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: '输入歌单名称（如：睡前哄睡儿歌）',
                    filled: true,
                    fillColor: AppTheme.paperWhite,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                  ),
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
                        text: existing == null ? '创建' : '保存',
                        color: AppTheme.tomato,
                        textColor: AppTheme.paperWhite,
                        onTap: () {
                          if (existing == null) {
                            final pl =
                                _controller.createCustomPlaylist(ctrl.text);
                            ToastUtils.showSuccess('已创建歌单「${pl.name}」');
                          } else {
                            _controller.renameCustomPlaylist(
                                existing.id, ctrl.text);
                            ToastUtils.showSuccess('歌单已重命名');
                          }
                          Navigator.of(dlgCtx).pop();
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

  /// 打开自定义收藏歌单详情底部面板（查看曲目、一键播放、移除曲目）
  void _openCustomPlaylistSheet(BuildContext context, String playlistId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.72,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          builder: (ctx, scrollCtrl) {
            return Container(
              decoration: BoxDecoration(
                color: AppTheme.cream,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
                border: AppTheme.border(),
                boxShadow: AppTheme.paperShadow(h: 16.0),
              ),
              child: Obx(() {
                final pl = _controller.customPlaylists
                    .firstWhereOrNull((p) => p.id == playlistId);
                if (pl == null) {
                  return const Center(child: Text('歌单不存在'));
                }
                return Column(
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
                      padding: EdgeInsets.symmetric(horizontal: 18.w),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  pl.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 18.sp,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.ink,
                                  ),
                                ),
                                Text(
                                  '共 ${pl.tracks.length} 首歌曲',
                                  style: TextStyle(
                                    fontSize: 12.sp,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textSub,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (pl.tracks.isNotEmpty)
                            MemphisButton(
                              text: '▶ 播放全部',
                              color: AppTheme.tomato,
                              textColor: AppTheme.paperWhite,
                              borderRadius: 999,
                              fontSize: 12.5.sp,
                              padding: EdgeInsets.symmetric(
                                  horizontal: 14.w, vertical: 7.h),
                              onTap: () {
                                Navigator.of(sheetCtx).pop();
                                _controller.playWithList(
                                    pl.tracks, pl.tracks.first);
                                Get.to(() => const MusicPlayerPage());
                              },
                            ),
                        ],
                      ),
                    ),
                    SizedBox(height: 10.h),
                    const Divider(height: 1),
                    Expanded(
                      child: pl.tracks.isEmpty
                          ? Center(
                              child: Padding(
                                padding: EdgeInsets.all(24.w),
                                child: Text(
                                  '歌单还是空的哦～\n在任意歌曲旁点击「📁 加歌单」图标，即可把歌曲收进这里！',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13.5.sp,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textSub,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: scrollCtrl,
                              physics: const BouncingScrollPhysics(),
                              padding: EdgeInsets.all(12.w),
                              itemCount: pl.tracks.length,
                              itemBuilder: (ctx, i) {
                                final track = pl.tracks[i];
                                return _buildSongTile(
                                  track,
                                  pl.tracks,
                                  onDeleteHistory: () => _controller
                                      .removeTrackFromCustomPlaylist(pl.id, i),
                                );
                              },
                            ),
                    ),
                  ],
                );
              }),
            );
          },
        );
      },
    );
  }

  // === 通用歌曲行（支持一键红心、一键加多歌单、单条移除、点击播放） ===

  Widget _buildSongTile(
    MusicTrack track,
    List<MusicTrack> sourceList, {
    VoidCallback? onDeleteHistory,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: MemphisCard(
        color: AppTheme.paperWhite,
        borderRadius: 16.r,
        shadowOffset: 3.0,
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
        onLongPress: () => _showTrackActions(track),
        onTap: () {
          _controller.playWithList(sourceList, track);
          Get.to(() => const MusicPlayerPage());
        },
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10.r),
              child: _coverImage(track.coverUrl, 46.w),
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    style: TextStyle(
                      fontSize: 14.5.sp,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.ink,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 3.h),
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 5.w, vertical: 1.5.h),
                        decoration: BoxDecoration(
                          color: _getPlatformColor(track.platform),
                          borderRadius: BorderRadius.circular(4.r),
                        ),
                        child: Text(
                          _getPlatformName(track.platform),
                          style: TextStyle(
                            fontSize: 9.sp,
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      SizedBox(width: 6.w),
                      Expanded(
                        child: Text(
                          track.durationMs != null && track.durationMs! > 0
                              ? '${track.artist} · ${_formatDuration(track.durationMs!)}'
                              : track.artist,
                          style: TextStyle(
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textSub,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // 1. 一键最爱红心
            Obx(() {
              final isChildMode = _modeController.isChildMode;
              final isFav = _controller.isFavorite(track);
              return IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  isFav
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: isChildMode
                      ? Colors.grey[300]
                      : (isFav ? AppTheme.tomato : AppTheme.textSub),
                  size: 20.sp,
                ),
                tooltip: '加入最爱',
                onPressed: isChildMode
                    ? () {
                        ToastUtils.showInfo('儿童模式下无法修改收藏,请切换到家长模式');
                      }
                    : () => _controller.toggleFavorite(track),
              );
            }),
            // 2. 一键收藏到多个歌单
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.library_add_outlined,
                color: AppTheme.teal,
                size: 20.sp,
              ),
              tooltip: '收藏到歌单',
              onPressed: () => showAddToPlaylistsSheet(context, track),
            ),
            // 3. 若在播放记录或自定义歌单内，显示单条移除按钮；否则显示播放按钮
            if (onDeleteHistory != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close_rounded,
                    color: AppTheme.textSub, size: 19.sp),
                tooltip: '移除',
                onPressed: onDeleteHistory,
              )
            else
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.play_circle_fill_rounded,
                    color: AppTheme.tomato),
                onPressed: () {
                  _controller.playWithList(sourceList, track);
                  Get.to(() => const MusicPlayerPage());
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _coverImage(String? url, double size) {
    return Container(
      width: size,
      height: size,
      color: AppTheme.tealSoft,
      child: (url != null && url.isNotEmpty)
          ? Image.network(
              url,
              fit: BoxFit.cover,
              headers: coverHeadersFor(url),
              errorBuilder: (ctx, err, stack) => Icon(Icons.music_note,
                  color: AppTheme.tomato, size: size * 0.4),
            )
          : Icon(Icons.music_note,
              color: AppTheme.tomato, size: size * 0.4),
    );
  }

  String _formatDuration(int ms) {
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  // === 中世纪现代黑胶唱机风迷你播放舱（局部 Obx 进度条隔离，零高频重建） ===

  Widget _buildMiniPlayer() {
    return Obx(() {
      final list = _controller.playlist;
      final index = _controller.currentIndex.value;

      if (list.isEmpty || index < 0 || index >= list.length) {
        return const SizedBox.shrink();
      }

      final track = list[index];

      return Padding(
        padding: EdgeInsets.fromLTRB(12.w, 4.h, 12.w, 8.h),
        child: BouncyTap(
          pressedScale: 0.96,
          onTap: () => Get.to(() => const MusicPlayerPage()),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.paperWhite,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20.r),
                topRight: Radius.circular(16.r),
                bottomLeft: Radius.circular(18.r),
                bottomRight: Radius.circular(22.r),
              ),
              border: AppTheme.border(),
              boxShadow: AppTheme.paperShadow(h: 10.0),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18.r),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 性能优化：仅此 3.5px 进度线监听高频 position 变化
                  Obx(() {
                    final pos = _controller.position.value;
                    final dur = _controller.duration.value;
                    final progress = dur.inMilliseconds > 0
                        ? pos.inMilliseconds / dur.inMilliseconds
                        : 0.0;
                    return LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 3.5,
                      backgroundColor: AppTheme.creamDeep,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          AppTheme.tomato),
                    );
                  }),
                  Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10.r),
                          child: _coverImage(track.coverUrl, 44.w),
                        ),
                        SizedBox(width: 10.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.ink,
                                ),
                              ),
                              Text(
                                '${_getPlatformName(track.platform)} · ${track.artist}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.sp,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textSub,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.skip_previous_rounded,
                              color: AppTheme.ink, size: 24.sp),
                          onPressed: _controller.playPrevious,
                        ),
                        Obx(() => IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                _controller.isPlaying.value
                                    ? Icons.pause_circle_filled_rounded
                                    : Icons.play_circle_fill_rounded,
                                color: AppTheme.tomato,
                                size: 36.sp,
                              ),
                              onPressed: _controller.togglePlay,
                            )),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.skip_next_rounded,
                              color: AppTheme.ink, size: 24.sp),
                          onPressed: () => _controller.playNext(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  // === 发现歌单(横向卡片推荐) ===

  Widget _buildDiscoverSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 10.h),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Icon(Icons.explore_rounded,
                  size: 18.sp, color: Colors.teal),
              SizedBox(width: 6.w),
              Text('发现歌单',
                  style: TextStyle(
                      fontSize: 15.sp, fontWeight: FontWeight.w700)),
              SizedBox(width: 8.w),
              Flexible(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 2.h),
                  child: Text('网易精选 · 点开即听',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.sp, color: Colors.black38)),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 152.h,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: _curatedPlaylists.length + 1,
            itemBuilder: (context, index) {
              if (index == _curatedPlaylists.length) {
                return _buildImportPlaylistCard();
              }
              final preset = _curatedPlaylists[index];
              return _buildPlaylistCard(preset['id']!, preset['name']!);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPlaylistCard(String id, String fallbackName) {
    final meta = PlaylistDetailPage.cache[id];
    final cover = meta?['cover'] as String?;
    final name = (meta?['name'] as String?) ?? fallbackName;
    final trackCount = meta?['trackCount'];

    return Padding(
      padding: EdgeInsets.only(right: 12.w),
      child: InkWell(
        borderRadius: BorderRadius.circular(14.r),
        onTap: () => Get.to(() => PlaylistDetailPage(
              playlistId: id,
              fallbackName: fallbackName,
            )),
        child: SizedBox(
          width: 104.w,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12.r),
                    child: _coverImage(cover, 104.w),
                  ),
                  if (trackCount is num)
                    Positioned(
                      right: 6.w,
                      bottom: 6.w,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 6.w, vertical: 1.h),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                        child: Text('${trackCount.toInt()}首',
                            style: TextStyle(
                                fontSize: 9.sp, color: Colors.white)),
                      ),
                    ),
                ],
              ),
              SizedBox(height: 6.h),
              Flexible(
                child: Text(name,
                    style: TextStyle(
                        fontSize: 12.sp, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImportPlaylistCard() {
    return Padding(
      padding: EdgeInsets.only(right: 12.w),
      child: InkWell(
        borderRadius: BorderRadius.circular(12.r),
        onTap: _showSettings,
        child: Container(
          width: 104.w,
          height: 104.w,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(
                color: AppTheme.primary.withValues(alpha: 0.3),
                width: 1.5,
                strokeAlign: BorderSide.strokeAlignInside),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_circle_outline_rounded,
                  color: AppTheme.primary, size: 28.sp),
              SizedBox(height: 6.h),
              Text('导入歌单',
                  style: TextStyle(
                      fontSize: 12.sp,
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w600)),
              SizedBox(height: 2.h),
              Text('粘贴链接或ID',
                  style:
                      TextStyle(fontSize: 10.sp, color: Colors.black38)),
            ],
          ),
        ),
      ),
    );
  }

  // 获取平台显示名称
  String _getPlatformName(String platform) {
    const platformNames = {
      'kuwo': '酷我',
      'netease': '网易',
      'qq': 'QQ',
    };
    return platformNames[platform] ?? platform.toUpperCase();
  }

  // 获取平台主题色
  Color _getPlatformColor(String platform) {
    const platformColors = {
      'kuwo': Color(0xFFFF6B35), // 橙红色
      'netease': Color(0xFFD43C33), // 网易云红
      'qq': Color(0xFF31C27C), // QQ音乐绿
    };
    return platformColors[platform] ?? Colors.grey;
  }
}
