import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../services/music_cache_service.dart';
import '../theme/app_theme.dart';

class MusicCacheSettingsPage extends StatefulWidget {
  const MusicCacheSettingsPage({super.key});

  @override
  State<MusicCacheSettingsPage> createState() => _MusicCacheSettingsPageState();
}

class _MusicCacheSettingsPageState extends State<MusicCacheSettingsPage> {
  final MusicCacheService _cacheService = Get.find<MusicCacheService>();
  CacheStats? _stats;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    final stats = await _cacheService.getCacheStats();
    if (mounted) {
      setState(() {
        _stats = stats;
        _isLoading = false;
      });
    }
  }

  Future<void> _clearCache() async {
    // Show confirmation dialog
    final confirmed = await Get.defaultDialog<bool>(
      title: '清理缓存',
      content: const Text('确定要删除所有已缓存的音乐文件吗？\n此操作不可撤销。'),
      textConfirm: '清理',
      textCancel: '取消',
      confirmTextColor: Colors.white,
      onConfirm: () => Get.back(result: true),
    );

    if (confirmed == true) {
      // 这里的清理是异步且非阻塞的，我们可以显示一个 Loading
      Get.dialog(
        const Center(child: CircularProgressIndicator()),
        barrierDismissible: false,
      );

      await _cacheService.clearAllCache();

      Get.back(); // Check off loading
      Get.snackbar('成功', '所有音乐缓存已清理',
          backgroundColor: Colors.green, colorText: Colors.white);

      // Reload stats
      _loadStats();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('音乐缓存管理'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.all(16.w),
              children: [
                _buildInfoCard(),
                SizedBox(height: 16.h),
                _buildSettingsCard(),
                SizedBox(height: 24.h),
                // 如果有缓存，显示平台分布
                if (_stats != null && _stats!.totalFiles > 0)
                  _buildDistributionCard(),
              ],
            ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
      child: Padding(
        padding: EdgeInsets.all(20.w),
        child: Column(
          children: [
            Icon(Icons.sd_storage, size: 48.sp, color: AppTheme.primary),
            SizedBox(height: 16.h),
            Text(
              _stats?.formattedSize ?? '0 B',
              style: TextStyle(fontSize: 32.sp, fontWeight: FontWeight.bold),
            ),
            Text(
              '已占用空间',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14.sp),
            ),
            SizedBox(height: 24.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatItem('缓存歌曲', '${_stats?.totalFiles ?? 0} 首'),
                // 可以加更多统计
              ],
            ),
            SizedBox(height: 24.h),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_stats?.totalFiles ?? 0) > 0 ? _clearCache : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  padding: EdgeInsets.symmetric(vertical: 12.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                ),
                icon: const Icon(Icons.delete_outline, color: Colors.white),
                label: const Text('一键清理所有缓存',
                    style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600)),
        SizedBox(height: 4.h),
        Text(label, style: TextStyle(color: Colors.grey, fontSize: 12.sp)),
      ],
    );
  }

  Widget _buildSettingsCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
      child: Column(
        children: [
          Obx(() => SwitchListTile(
                title: const Text('启用自动缓存'),
                subtitle: const Text('播放时自动下载并缓存音乐'),
                value: _cacheService.cacheEnabled.value,
                onChanged: (val) async {
                  await _cacheService.saveSettings(enabled: val);
                },
              )),
        ],
      ),
    );
  }

  Widget _buildDistributionCard() {
    if (_stats == null) return const SizedBox.shrink();

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('来源分布',
                style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
            SizedBox(height: 16.h),
            ..._stats!.platformCounts.entries.map((e) {
              return Padding(
                padding: EdgeInsets.only(bottom: 8.h),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_getPlatformName(e.key),
                        style: TextStyle(fontSize: 14.sp)),
                    Text('${e.value} 首',
                        style: TextStyle(
                            fontSize: 14.sp, fontWeight: FontWeight.w500)),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  String _getPlatformName(String key) {
    switch (key.toLowerCase()) {
      case 'netease':
        return '网易云音乐';
      case 'kuwo':
        return '酷我音乐';
      case 'qq':
        return 'QQ音乐';
      case 'kugou':
        return '酷狗音乐';
      case 'migu':
        return '咪咕音乐';
      default:
        return key;
    }
  }
}
