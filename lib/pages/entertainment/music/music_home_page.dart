import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../controllers/music_player_controller.dart';
import '../../../services/tunehub_service.dart';
import '../../../services/webdav_service.dart';
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

  void _doSearch() async {
    if (_searchController.text.isEmpty) return;
    FocusScope.of(context).unfocus();
    _isSearching.value = true;
    _searchResults.clear();

    try {
      final results = await _tuneHubService.searchMusic(_searchController.text);
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
            decoration: const InputDecoration(labelText: 'API Key (Optional)'),
          ),
          SizedBox(height: 16.h),
          const Divider(),
          Text('数据备份 (WebDAV)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.sp)),
          SizedBox(height: 8.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.cloud_upload),
                label: const Text('备份'),
                onPressed: () async {
                  Get.back();
                  final success = await Get.find<WebDavService>().backupData();
                  if (success) _showSettings(); // Re-open or just stay closed
                },
              ),
              TextButton.icon(
                icon: const Icon(Icons.cloud_download),
                label: const Text('恢复'),
                onPressed: () async {
                  Get.back(); // Close first
                  final backups = await Get.find<WebDavService>().listBackups();
                  if (backups.isEmpty) {
                    Get.snackbar('提示', '未找到备份文件');
                    return;
                  }
                  // Show backup selection
                  Get.defaultDialog(
                    title: '选择备份',
                    content: SizedBox(
                      height: 300.h,
                      width: 300.w,
                      child: ListView(
                        children: backups.reversed
                            .map((path) => ListTile(
                                  title: Text(path.split('/').last),
                                  onTap: () async {
                                    Get.back();
                                    await Get.find<WebDavService>()
                                        .restoreData(path);
                                  },
                                ))
                            .toList(),
                      ),
                    ),
                  );
                },
              ),
            ],
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
                                  child: track.coverUrl == null
                                      ? const Icon(Icons.music_note)
                                      : null,
                                ),
                                title: Text(track.title),
                                subtitle: Text(track.artist),
                                trailing: IconButton(
                                  icon: const Icon(Icons.play_circle_fill,
                                      color: AppTheme.primary),
                                  onPressed: () {
                                    _controller.playTrack(track);
                                    Get.to(() => const MusicPlayerPage());
                                  },
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
                        image: track.coverUrl != null
                            ? DecorationImage(
                                image: NetworkImage(track.coverUrl!),
                                fit: BoxFit.cover)
                            : null,
                        color: Colors.grey[200],
                      ),
                      child: track.coverUrl == null
                          ? const Icon(Icons.music_note)
                          : null,
                    ),
                    title: Text(track.title),
                    subtitle: Text('${track.artist} - ${track.album ?? ""}'),
                    trailing: const Icon(Icons.play_circle_fill,
                        color: AppTheme.primary),
                    onTap: () {
                      _controller.playTrack(track);
                      Get.to(() => const MusicPlayerPage());
                    },
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
