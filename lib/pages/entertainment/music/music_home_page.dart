import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../controllers/music_player_controller.dart';
import '../../../services/tunehub_service.dart';
import '../../../theme/app_theme.dart';
import '../../../models/music/music_track.dart';
import 'music_player_page.dart';
import '../../../widgets/toast_utils.dart';

class MusicHomePage extends StatefulWidget {
  const MusicHomePage({super.key});

  @override
  State<MusicHomePage> createState() => _MusicHomePageState();
}

class _MusicHomePageState extends State<MusicHomePage> {
  final MusicPlayerController _controller = Get.find<MusicPlayerController>();
  final TuneHubService _tuneHubService = Get.find<TuneHubService>();
  final TextEditingController _searchController = TextEditingController();

  final RxList<MusicTrack> _searchResults = <MusicTrack>[].obs;
  final RxBool _isSearching = false.obs;
  final RxBool _isMoreLoading = false.obs; // 是否正在加载更多
  final RxString _selectedPlatform = 'kuwo'.obs;
  final ScrollController _scrollController = ScrollController();
  int _currentPage = 1; // 当前页码

  // 折叠状态
  final RxBool _isFavExpanded = true.obs;
  final RxBool _isHistoryExpanded = false.obs;

  // 分页展示限制（初始显示数量）
  final RxInt _favLimit = 10.obs;
  final RxInt _historyLimit = 10.obs;

  final Map<String, String> _platforms = {
    'kuwo': '酷我音乐',
    'netease': '网易云',
    'qq': 'QQ音乐',
  };

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
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
      final results = await _tuneHubService.searchMusic(_searchController.text,
          platform: _selectedPlatform.value, page: _currentPage);

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
          ToastUtils.showInfo('未找到相关歌曲，请尝试其他关键词或平台');
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

  void _showSettings() {
    final urlCtrl = TextEditingController(text: _tuneHubService.baseUrl.value);
    final keyCtrl = TextEditingController(text: _tuneHubService.apiKey.value);

    Get.defaultDialog(
      title: 'TuneHub 设置',
      content: Column(
        children: [
          TextField(
            controller: urlCtrl,
            decoration: const InputDecoration(labelText: 'API Base URL'),
          ),
          TextField(
            controller: keyCtrl,
            decoration:
                const InputDecoration(labelText: 'API Keys (用;分隔多个Key)'),
          ),
        ],
      ),
      textConfirm: '保存',
      onConfirm: () {
        _tuneHubService.updateConfig(urlCtrl.text, keyCtrl.text);
        Get.back();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPink,
      appBar: AppBar(
        title: const Text('音乐乐园'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettings,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search Bar
            Padding(
              padding: EdgeInsets.all(16.w),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20.r),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 10)
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: '搜索歌曲、歌手...',
                    border: InputBorder.none,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: _doSearch,
                    ),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                  ),
                  onSubmitted: (_) => _doSearch(),
                ),
              ),
            ),

            // Platform Selector
            Obx(() => Container(
                  height: 40.h,
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: _platforms.entries.map((entry) {
                      final isSelected = _selectedPlatform.value == entry.key;
                      return Padding(
                        padding: EdgeInsets.only(right: 8.w),
                        child: ChoiceChip(
                          label: Text(entry.value),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) {
                              _selectedPlatform.value = entry.key;
                              if (_searchController.text.isNotEmpty)
                                _doSearch();
                            }
                          },
                          selectedColor: AppTheme.primary,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : Colors.black87,
                            fontSize: 12.sp,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                )),

            // Results
            Expanded(
              child: Obx(() {
                if (_isSearching.value) {
                  return const Center(child: CircularProgressIndicator());
                }

                // 优先检查：搜索结果为空且有搜索关键词时显示调试信息
                if (_searchResults.isEmpty &&
                    _searchController.text.isNotEmpty) {
                  return Center(
                    child: Padding(
                      padding: EdgeInsets.all(20.w),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off,
                              size: 60.sp, color: Colors.grey),
                          SizedBox(height: 16.h),
                          Text(
                            '未找到搜索结果',
                            style: TextStyle(
                                fontSize: 18.sp, color: Colors.black87),
                          ),
                          SizedBox(height: 8.h),
                          Text(
                            '关键词: "${_searchController.text}"',
                            style:
                                TextStyle(fontSize: 14.sp, color: Colors.grey),
                          ),
                          SizedBox(height: 20.h),
                          ElevatedButton.icon(
                            onPressed: () {
                              final tuneHub = Get.find<TuneHubService>();
                              Get.dialog(
                                AlertDialog(
                                  title: const Text('搜索调试信息'),
                                  content: SingleChildScrollView(
                                    child: SelectableText(
                                      tuneHub.lastSearchDebugInfo.isEmpty
                                          ? '暂无调试信息'
                                          : tuneHub.lastSearchDebugInfo,
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
                            icon: const Icon(Icons.bug_report),
                            label: const Text('查看调试信息'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // 未搜索时显示收藏和历史
                if (_searchResults.isEmpty) {
                  return ListView(
                    padding: EdgeInsets.symmetric(horizontal: 16.w),
                    children: [
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
                          padding: EdgeInsets.only(top: 100.h),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.music_note,
                                    size: 60.sp, color: Colors.black26),
                                SizedBox(height: 10.h),
                                Text('快去搜歌吧~',
                                    style: TextStyle(
                                        color: Colors.black45,
                                        fontSize: 16.sp)),
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
                    return ListTile(
                      leading: Container(
                        width: 50.w,
                        height: 50.w,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8.r),
                          color: Colors.grey[200],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8.r),
                          child: track.coverUrl != null
                              ? Image.network(
                                  track.coverUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(Icons.music_note),
                                )
                              : const Icon(Icons.music_note),
                        ),
                      ),
                      title: Text(track.title),
                      subtitle: Text('${track.artist} - ${track.album ?? ""}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Obx(() => IconButton(
                                icon: Icon(
                                  _controller.isFavorite(track)
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color: _controller.isFavorite(track)
                                      ? Colors.redAccent
                                      : Colors.grey,
                                  size: 20.sp,
                                ),
                                onPressed: () =>
                                    _controller.toggleFavorite(track),
                              )),
                          IconButton(
                            icon: const Icon(Icons.play_circle_fill,
                                color: AppTheme.primary),
                            onPressed: () {
                              // 只添加当前歌曲到播放列表 (临时添加，不保存)
                              _controller.playTrack(track);
                              Get.to(() => const MusicPlayerPage());
                            },
                          ),
                        ],
                      ),
                    );
                  },
                );
              }),
            ),

            // Mini Player Placeholder
            Obx(() {
              // 安全检查：列表为空或索引越界时隐藏
              final list = _controller.playlist;
              final index = _controller.currentIndex.value;

              if (list.isEmpty || index < 0 || index >= list.length) {
                return const SizedBox.shrink();
              }

              final track = list[index];

              return GestureDetector(
                onTap: () => Get.to(() => const MusicPlayerPage()),
                child: Container(
                  width: double.infinity,
                  height: 70.h,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        offset: const Offset(0, -2),
                        blurRadius: 10,
                      )
                    ],
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 12.w),
                  child: Row(
                    children: [
                      // Spinning Disc (mini)
                      CircleAvatar(
                        backgroundColor: Colors.grey[200],
                        backgroundImage: (track.coverUrl != null &&
                                track.coverUrl!.isNotEmpty)
                            ? NetworkImage(track.coverUrl!)
                            : null,
                        child: (track.coverUrl == null ||
                                track.coverUrl!.isEmpty)
                            ? const Icon(Icons.music_note, color: Colors.grey)
                            : null,
                      ),
                      SizedBox(width: 10.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.sp,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12.sp, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          _controller.isPlaying.value
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_filled,
                          color: AppTheme.primary,
                          size: 36.sp,
                        ),
                        onPressed: _controller.togglePlay,
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
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
      // 总是显示 Header，除非是真的完全没数据且不是搜索结果页
      final displayedTracks = tracks.take(limit.value).toList();
      final hasMore = tracks.length > limit.value;

      return Column(
        children: [
          ListTile(
            onTap: () => isExpanded.toggle(),
            leading: Icon(icon, color: iconColor),
            title: Text(title,
                style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onPlayAll != null && tracks.isNotEmpty)
                  TextButton(onPressed: onPlayAll, child: const Text('播放全部')),
                Icon(isExpanded.value ? Icons.expand_less : Icons.expand_more),
              ],
            ),
          ),
          if (isExpanded.value) ...[
            if (tracks.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 10.h),
                child: Text('暂无数据',
                    style: TextStyle(color: Colors.grey, fontSize: 12.sp)),
              )
            else ...[
              ...displayedTracks.map((track) => _buildTrackTile(track, tracks)),
              if (hasMore)
                TextButton(
                  onPressed: () => limit.value += 10,
                  child: Text('查看更多 (${tracks.length - limit.value})'),
                ),
            ],
          ],
        ],
      );
    });
  }

  Widget _buildTrackTile(MusicTrack track, List<MusicTrack> sourceList) {
    return ListTile(
      leading: Container(
        width: 40.w,
        height: 40.w,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8.r),
          color: Colors.grey[200],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8.r),
          child: (track.coverUrl != null && track.coverUrl!.isNotEmpty)
              ? Image.network(
                  track.coverUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, err, stack) =>
                      const Icon(Icons.music_note, color: Colors.grey),
                )
              : const Icon(Icons.music_note, color: Colors.grey),
        ),
      ),
      title: Text(track.title,
          style: TextStyle(fontSize: 14.sp),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      subtitle: Row(
        children: [
          // 音乐来源标识
          Container(
            padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 1.h),
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
          // 歌手名称
          Expanded(
            child: Text(
              track.artist,
              style: TextStyle(fontSize: 12.sp, color: Colors.grey[600]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Obx(() => IconButton(
                icon: Icon(
                  _controller.isFavorite(track)
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: _controller.isFavorite(track)
                      ? Colors.redAccent
                      : Colors.grey,
                  size: 20.sp,
                ),
                onPressed: () => _controller.toggleFavorite(track),
              )),
          IconButton(
            icon: const Icon(Icons.play_circle_fill, color: AppTheme.primary),
            onPressed: () {
              // 从本地列表播放时，加载整个源列表
              _controller.playWithList(sourceList, track);
              Get.to(() => const MusicPlayerPage());
            },
          ),
        ],
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
