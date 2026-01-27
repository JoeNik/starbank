import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../controllers/music_player_controller.dart';
import '../../../services/tunehub_service.dart';
import '../../../theme/app_theme.dart';
import '../../../models/music/music_track.dart';
import 'music_player_page.dart';

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
  final RxString _selectedPlatform = 'kuwo'.obs;

  final Map<String, String> _platforms = {
    'kuwo': '酷我音乐',
    'netease': '网易云',
    'qq': 'QQ音乐',
  };

  void _doSearch() async {
    if (_searchController.text.isEmpty) return;
    FocusScope.of(context).unfocus();
    _isSearching.value = true;
    _searchResults.clear();

    try {
      final results = await _tuneHubService.searchMusic(_searchController.text,
          platform: _selectedPlatform.value);
      _searchResults.assignAll(results);
    } catch (e) {
      Get.snackbar('搜索失败', e.toString());
    } finally {
      _isSearching.value = false;
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
      body: Column(
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
                            if (_searchController.text.isNotEmpty) _doSearch();
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
              if (_searchResults.isEmpty) {
                if (_controller.favorites.isNotEmpty) {
                  return ListView(
                    padding: EdgeInsets.symmetric(horizontal: 16.w),
                    children: [
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 10.h),
                        child: Row(
                          children: [
                            const Icon(Icons.favorite, color: Colors.redAccent),
                            SizedBox(width: 8.w),
                            Text('我的收藏',
                                style: TextStyle(
                                    fontSize: 18.sp,
                                    fontWeight: FontWeight.bold)),
                            const Spacer(),
                            TextButton(
                              onPressed: _controller.playFavorites,
                              child: const Text('播放全部'),
                            )
                          ],
                        ),
                      ),
                      ..._controller.favorites
                          .map((track) => ListTile(
                                leading: Container(
                                  width: 50.w,
                                  height: 50.w,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8.r),
                                    image: track.coverUrl != null
                                        ? DecorationImage(
                                            image:
                                                NetworkImage(track.coverUrl!),
                                            fit: BoxFit.cover)
                                        : null,
                                    color: Colors.grey[200],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8.r),
                                    child: track.coverUrl != null
                                        ? Image.network(
                                            track.coverUrl!,
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, error,
                                                    stackTrace) =>
                                                const Icon(Icons.music_note),
                                          )
                                        : const Icon(Icons.music_note),
                                  ),
                                ),
                                title: Text(track.title),
                                subtitle: Text(track.artist),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.favorite,
                                          color: Colors.redAccent),
                                      onPressed: () =>
                                          _controller.toggleFavorite(track),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.play_circle_fill,
                                          color: AppTheme.primary),
                                      onPressed: () {
                                        _controller.playTrack(track);
                                        Get.to(() => const MusicPlayerPage());
                                      },
                                    ),
                                  ],
                                ),
                              ))
                          .toList(),
                    ],
                  );
                }

                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.music_note,
                          size: 60.sp, color: Colors.black26),
                      SizedBox(height: 10.h),
                      Text('收藏夹空空如也，快去搜歌吧~',
                          style: TextStyle(
                              color: Colors.black45, fontSize: 16.sp)),
                    ],
                  ),
                );
              }
              return ListView.builder(
                itemCount: _searchResults.length,
                itemBuilder: (context, index) {
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
            if (_controller.playlist.isNotEmpty) {
              return GestureDetector(
                onTap: () => Get.to(() => const MusicPlayerPage()),
                child: Container(
                  width: double.infinity,
                  height: 70.h,
                  color: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 12.w),
                  child: Row(
                    children: [
                      // Spinning Disc (mini)
                      CircleAvatar(
                        backgroundImage: _controller
                                    .playlist[_controller.currentIndex.value]
                                    .coverUrl !=
                                null
                            ? NetworkImage(_controller
                                .playlist[_controller.currentIndex.value]
                                .coverUrl!)
                            : null,
                      ),
                      SizedBox(width: 10.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                                _controller
                                    .playlist[_controller.currentIndex.value]
                                    .title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            Text(
                                _controller
                                    .playlist[_controller.currentIndex.value]
                                    .artist,
                                style: TextStyle(
                                    fontSize: 12.sp, color: Colors.grey)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(_controller.isPlaying.value
                            ? Icons.pause
                            : Icons.play_arrow),
                        onPressed: _controller.togglePlay,
                      ),
                    ],
                  ),
                ),
              );
            }
            return const SizedBox.shrink();
          }),
        ],
      ),
    );
  }
}
