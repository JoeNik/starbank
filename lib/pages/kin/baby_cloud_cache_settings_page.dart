import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../services/baby_cloud_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/toast_utils.dart';

class BabyCloudCacheSettingsPage extends StatefulWidget {
  const BabyCloudCacheSettingsPage({super.key});

  @override
  State<BabyCloudCacheSettingsPage> createState() =>
      _BabyCloudCacheSettingsPageState();
}

class _BabyCloudCacheSettingsPageState
    extends State<BabyCloudCacheSettingsPage> {
  final _cloud = Get.find<BabyCloudService>();
  BabyCloudCacheStats? _stats;
  bool _loading = true;
  bool _working = false;
  late int _autoDays;
  int _manualDays = 60;

  static const _dayChoices = [7, 15, 30, 60, 90, 180];

  @override
  void initState() {
    super.initState();
    _autoDays = _cloud.autoCacheCleanupDays;
    _manualDays = _autoDays;
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final stats = await _cloud.getLocalCacheStats();
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _loading = false;
    });
  }

  Future<void> _clearOlder(int days, {required String confirmText}) async {
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('清理云相册缓存'),
        content: Text(confirmText),
        actions: [
          TextButton(onPressed: () => Get.back(result: false), child: const Text('取消')),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _working = true);
    try {
      final result = await _cloud.clearLocalCacheOlderThan(days);
      if (!mounted) return;
      ToastUtils.showSuccess(
        result.deletedFiles == 0
            ? '没有可清理的缓存'
            : '已清理 ${result.deletedFiles} 个文件，释放 ${result.formattedFreedSize}',
      );
      await _reload();
    } catch (e) {
      ToastUtils.showError('清理失败: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _saveAutoDays(int days) async {
    setState(() => _autoDays = days);
    await _cloud.setAutoCacheCleanupDays(days);
    ToastUtils.showSuccess('已设置自动清理 $days 天前缓存');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F3EA),
      appBar: AppBar(
        title: const Text('云相册缓存'),
        backgroundColor: const Color(0xFFFFFCF4),
        foregroundColor: AppTheme.textMain,
        elevation: 0,
      ),
      body: Stack(
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else
            ListView(
              padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 28.h),
              children: [
                _buildSummaryCard(),
                SizedBox(height: 14.h),
                _buildAutoCard(),
                SizedBox(height: 14.h),
                _buildManualCard(),
              ],
            ),
          if (_working)
            Container(
              color: Colors.black.withValues(alpha: 0.18),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    final stats = _stats;
    return Container(
      padding: EdgeInsets.all(18.w),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF4),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: const Color(0xFFE8D7B0)),
      ),
      child: Column(
        children: [
          Icon(Icons.photo_library_outlined,
              size: 42.sp, color: const Color(0xFFE09B00)),
          SizedBox(height: 10.h),
          Text(
            stats?.formattedSize ?? '0 B',
            style: TextStyle(
              fontSize: 30.sp,
              fontWeight: FontWeight.w900,
              color: AppTheme.textMain,
            ),
          ),
          Text(
            '云相册本地下载缓存',
            style: TextStyle(
              fontSize: 13.sp,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 16.h),
          Row(
            children: [
              Expanded(
                child: _statTile('文件数', '${stats?.fileCount ?? 0}'),
              ),
              Expanded(
                child: _statTile(
                  '自动策略',
                  '$_autoDays 天',
                ),
              ),
            ],
          ),
          SizedBox(height: 14.h),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
              label: const Text('刷新统计'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statTile(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.w900,
            color: AppTheme.textMain,
          ),
        ),
        SizedBox(height: 2.h),
        Text(
          label,
          style: TextStyle(
            fontSize: 12.sp,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildAutoCard() {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: const Color(0xFFEAEAEA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '自动清理',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            '启动应用时自动清理超过设定天数的下载缓存（缩略图/原图缓存）。不会删除云端动态与元数据。',
            style: TextStyle(
              fontSize: 12.sp,
              height: 1.35,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 12.h),
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: [
              for (final days in _dayChoices)
                ChoiceChip(
                  label: Text('$days 天'),
                  selected: _autoDays == days,
                  selectedColor: const Color(0xFFFFE8A6),
                  onSelected: (_) => _saveAutoDays(days),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildManualCard() {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: const Color(0xFFEAEAEA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '手动清理',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            '立即清理指定天数前下载的本地缓存。',
            style: TextStyle(
              fontSize: 12.sp,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 12.h),
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: [
              for (final days in _dayChoices)
                ChoiceChip(
                  label: Text('$days 天前'),
                  selected: _manualDays == days,
                  selectedColor: const Color(0xFFFFE8A6),
                  onSelected: (_) => setState(() => _manualDays = days),
                ),
            ],
          ),
          SizedBox(height: 14.h),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_stats?.fileCount ?? 0) == 0
                  ? null
                  : () => _clearOlder(
                        _manualDays,
                        confirmText:
                            '将删除 $_manualDays 天前的云相册本地缓存文件，此操作不可撤销。',
                      ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE09B00),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 12.h),
              ),
              icon: const Icon(Icons.cleaning_services_outlined),
              label: Text('清理 $_manualDays 天前缓存'),
            ),
          ),
          SizedBox(height: 8.h),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: (_stats?.fileCount ?? 0) == 0
                  ? null
                  : () => _clearOlder(
                        36500,
                        confirmText: '将删除全部云相册本地缓存文件，此操作不可撤销。',
                      ),
              icon: const Icon(Icons.delete_outline),
              label: const Text('清理全部缓存'),
            ),
          ),
        ],
      ),
    );
  }
}
