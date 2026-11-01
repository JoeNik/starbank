import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../controllers/music_player_controller.dart';
import '../../../controllers/app_mode_controller.dart';
import '../../../services/chksz_music_service.dart';
import '../../../services/music_source.dart';
import '../../../services/tunehub_service.dart';
import '../../../theme/app_theme.dart';
import '../../../models/music/music_track.dart';
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

  // 折叠状态
  final RxBool _isFavExpanded = true.obs;
  final RxBool _isHistoryExpanded = false.obs;

  // 分页展示限制(初始显示数量)
  final RxInt _favLimit = 10.obs;
  final RxInt _historyLimit = 10.obs;

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
                      subtitle: Text('内置密钥 · 无损/Hi-Res 高音质解析',
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
                                    '${ChkSzMusicService.qualityLabel(level)} (${level})'),
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
      backgroundColor: AppTheme.bgPink,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('音乐乐园',
            style: TextStyle(
                fontSize: 22.sp, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: '音乐源设置',
            onPressed: _showSettings,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search Bar
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 8.h),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18.r),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 10)
                  ],
                ),
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _searchController,
                  builder: (context, value, _) {
                    return TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: '搜索歌曲、歌手...',
                        border: InputBorder.none,
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: value.text.isEmpty
                            ? const SizedBox.shrink()
                            : IconButton(
                                icon: const Icon(Icons.close_rounded,
                                    size: 20),
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

            // Platform + Source Selector
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
                              padding: EdgeInsets.only(right: 8.w),
                              child: ChoiceChip(
                                label: Text(entry.value),
                                selected: isSelected,
                                onSelected: (selected) {
                                  if (selected) {
                                    _selectedPlatform.value = entry.key;
                                    if (_searchController.text.isNotEmpty) {
                                      _doSearch();
                                    }
                                  }
                                },
                                selectedColor: AppTheme.primary,
                                labelStyle: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.black87,
                                  fontSize: 12.sp,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      if (_selectedPlatform.value == 'netease' &&
                          _sourceRegistry != null)
                        InkWell(
                          borderRadius: BorderRadius.circular(14.r),
                          onTap: _showSourceSwitcher,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 10.w, vertical: 5.h),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(14.r),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.swap_horiz,
                                    size: 14.sp,
                                    color: AppTheme.primary),
                                SizedBox(width: 4.w),
                                Obx(() => Text(
                                      _sourceRegistry?.active?.displayName ??
                                          '未选择',
                                      style: TextStyle(
                                          fontSize: 11.sp,
                                          color: AppTheme.primary,
                                          fontWeight: FontWeight.w600),
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

                // 未搜索时显示热门搜索 + 收藏和历史
                if (_searchResults.isEmpty) {
                  return ListView(
                    controller: _scrollController,
                    padding: EdgeInsets.symmetric(horizontal: 16.w),
                    children: [
                      Padding(
                        padding: EdgeInsets.only(top: 8.h, bottom: 10.h),
                        child: Row(
                          children: [
                            Icon(Icons.local_fire_department_rounded,
                                size: 18.sp, color: Colors.deepOrange),
                            SizedBox(width: 6.w),
                            Text('热门搜索',
                                style: TextStyle(
                                    fontSize: 15.sp,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                      Wrap(
                        spacing: 8.w,
                        runSpacing: 8.h,
                        children: _hotKeywords
                            .map((keyword) => InkWell(
                                  borderRadius: BorderRadius.circular(22.r),
                                  onTap: () {
                                    _searchController.text = keyword;
                                    _doSearch();
                                  },
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 14.w, vertical: 7.h),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius:
                                          BorderRadius.circular(22.r),
                                      boxShadow: const [
                                        BoxShadow(
                                            color: Colors.black12,
                                            blurRadius: 6)
                                      ],
                                    ),
                                    child: Text(keyword,
                                        style: TextStyle(
                                            fontSize: 13.sp,
                                            color: Colors.black87)),
                                  ),
                                ))
                            .toList(),
                      ),
                      SizedBox(height: 16.h),

                      // 发现歌单(网易精选推荐)
                      _buildDiscoverSection(),
                      SizedBox(height: 16.h),

                      // 我的收藏
                      _buildCollapsibleSection(
                        title: '我的收藏',
                        icon: Icons.favorite,
                        iconColor: Colors.redAccent,
                        isExpanded: _isFavExpanded,
                        tracks: _controller.favorites,
                        limit: _favLimit,
                        onPlayAll: _controller.playFavorites,
                      ),

                      SizedBox(height: 10.h),

                      // 播放记录
                      _buildCollapsibleSection(
                        title: '播放记录',
                        icon: Icons.history,
                        iconColor: Colors.blueAccent,
                        isExpanded: _isHistoryExpanded,
                        tracks: _controller.history,
                        limit: _historyLimit,
                      ),

                      if (_controller.favorites.isEmpty &&
                          _controller.history.isEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: 60.h, bottom: 40.h),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.music_note_rounded,
                                    size: 56.sp, color: Colors.black26),
                                SizedBox(height: 10.h),
                                Text('快去搜歌吧~',
                                    style: TextStyle(
                                        color: Colors.black45,
                                        fontSize: 15.sp)),
                              ],
                            ),
                          ),
                        ),
                      SizedBox(height: 20.h),
                    ],
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: EdgeInsets.symmetric(horizontal: 8.w),
                  itemCount:
                      _searchResults.length + (_isMoreLoading.value ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _searchResults.length) {
                      return Padding(
                        padding: EdgeInsets.symmetric(vertical: 20.h),
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }

                    final track = _searchResults[index];
                    return _buildSongTile(track, _searchResults);
                  },
                );
              }),
            ),

            // Mini Player(悬浮卡片)
            _buildMiniPlayer(),
          ],
        ),
      ),
    );
  }

  // === 通用歌曲行 ===

  Widget _buildSongTile(MusicTrack track, List<MusicTrack> sourceList) {
    return InkWell(
      borderRadius: BorderRadius.circular(14.r),
      onLongPress: () => _showTrackActions(track),
      onTap: () {
        // 播放功能在儿童模式下也可用
        _controller.playWithList(sourceList, track);
        Get.to(() => const MusicPlayerPage());
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
        child: Row(
          children: [
            ClipRRect(
                borderRadius: BorderRadius.circular(10.r),
                child: _coverImage(track.coverUrl, 48.w)),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(track.title,
                      style: TextStyle(
                          fontSize: 15.sp, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  SizedBox(height: 3.h),
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 4.w, vertical: 1.h),
                        decoration: BoxDecoration(
                          color: _getPlatformColor(track.platform),
                          borderRadius: BorderRadius.circular(3.r),
                        ),
                        child: Text(
                          _getPlatformName(track.platform),
                          style: TextStyle(
                            fontSize: 9.sp,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      SizedBox(width: 6.w),
                      Expanded(
                        child: Text(track.artist,
                            style: TextStyle(
                                fontSize: 12.sp, color: Colors.grey[600]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (track.durationMs != null && track.durationMs! > 0)
              Padding(
                padding: EdgeInsets.only(left: 8.w),
                child: Text(
                  _formatDuration(track.durationMs!),
                  style: TextStyle(fontSize: 11.sp, color: Colors.black38),
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
                  size: 20.sp,
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
              icon: const Icon(Icons.play_circle_fill,
                  color: AppTheme.primary),
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
      color: AppTheme.primary.withOpacity(0.12),
      child: (url != null && url.isNotEmpty)
          ? Image.network(
              url,
              fit: BoxFit.cover,
              headers: coverHeadersFor(url),
              errorBuilder: (ctx, err, stack) => Icon(Icons.music_note,
                  color: AppTheme.primary, size: size * 0.4),
            )
          : Icon(Icons.music_note,
              color: AppTheme.primary, size: size * 0.4),
    );
  }

  String _formatDuration(int ms) {
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  // === 迷你播放条(悬浮卡片 + 顶部细进度线) ===

  Widget _buildMiniPlayer() {
    return Obx(() {
      // 安全检查:列表为空或索引越界时隐藏
      final list = _controller.playlist;
      final index = _controller.currentIndex.value;

      if (list.isEmpty || index < 0 || index >= list.length) {
        return const SizedBox.shrink();
      }

      final track = list[index];
      final pos = _controller.position.value;
      final dur = _controller.duration.value;
      final progress = dur.inMilliseconds > 0
          ? pos.inMilliseconds / dur.inMilliseconds
          : 0.0;

      return Padding(
        padding: EdgeInsets.fromLTRB(12.w, 4.h, 12.w, 6.h),
        child: GestureDetector(
          onTap: () => Get.to(() => const MusicPlayerPage()),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18.r),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18.r),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    minHeight: 3,
                    backgroundColor: AppTheme.primary.withOpacity(0.1),
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppTheme.primary),
                  ),
                  Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10.r),
                          child: _coverImage(track.coverUrl, 42.w),
                        ),
                        SizedBox(width: 12.w),
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
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                              Text(
                                '${_getPlatformName(track.platform)} · ${track.artist}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11.sp, color: Colors.black45),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            _controller.isPlaying.value
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_fill,
                            color: AppTheme.primary,
                            size: 34.sp,
                          ),
                          onPressed: _controller.togglePlay,
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.skip_next_rounded,
                              color: Colors.black87, size: 26.sp),
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
            color: AppTheme.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(
                color: AppTheme.primary.withOpacity(0.3),
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

  Widget _buildCollapsibleSection({
    required String title,
    required IconData icon,
    required Color iconColor,
    required RxBool isExpanded,
    required List<MusicTrack> tracks,
    required RxInt limit,
    VoidCallback? onPlayAll,
  }) {
    return Obx(() {
      final displayedTracks = tracks.take(limit.value).toList();
      final hasMore = tracks.length > limit.value;

      return Column(
        children: [
          ListTile(
            onTap: () => isExpanded.toggle(),
            contentPadding: EdgeInsets.zero,
            leading: Icon(icon, color: iconColor),
            title: Text(title,
                style: TextStyle(
                    fontSize: 16.sp, fontWeight: FontWeight.w700)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onPlayAll != null && tracks.isNotEmpty)
                  TextButton(onPressed: onPlayAll, child: const Text('播放全部')),
                Icon(isExpanded.value
                    ? Icons.expand_less
                    : Icons.expand_more),
              ],
            ),
          ),
          if (isExpanded.value) ...[
            if (tracks.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 10.h),
                child: Text('暂无数据',
                    style:
                        TextStyle(color: Colors.grey, fontSize: 12.sp)),
              )
            else ...[
              ...displayedTracks
                  .map((track) => _buildSongTile(track, tracks)),
              if (hasMore)
                TextButton(
                  onPressed: () => limit.value += 10,
                  child:
                      Text('查看更多 (${tracks.length - limit.value})'),
                ),
            ],
          ],
        ],
      );
    });
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
