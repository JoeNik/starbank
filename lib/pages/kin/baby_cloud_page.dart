import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../controllers/user_controller.dart';
import '../../models/baby_cloud_media.dart';
import '../../services/baby_cloud_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/baby_profile_utils.dart';
import '../../widgets/baby_cloud_media_thumbnail.dart';
import '../../widgets/image_utils.dart';
import '../../widgets/module_background_scene.dart';
import '../../widgets/toast_utils.dart';
import 'baby_cloud_media_detail_page.dart';
import 'baby_cloud_media_picker_page.dart';
import 'baby_cloud_recycle_bin_page.dart';
import 'baby_cloud_source_page.dart';
import 'baby_cloud_upload_tasks_page.dart';

class BabyCloudPage extends StatefulWidget {
  const BabyCloudPage({super.key});

  @override
  State<BabyCloudPage> createState() => _BabyCloudPageState();
}

class _BabyCloudPageState extends State<BabyCloudPage> {
  final _user = Get.find<UserController>();
  final _cloud = Get.find<BabyCloudService>();

  @override
  void initState() {
    super.initState();
    Future.microtask(_syncCurrent);
  }

  Future<void> _syncCurrent() async {
    final baby = _user.currentBaby.value;
    if (baby != null && _cloud.currentSource.value != null) {
      await _cloud.syncBaby(baby);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(
            child: ModuleBackgroundScene(theme: ModuleBackgroundTheme.record),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildAppBar(),
                Expanded(
                  child: Obx(() {
                    final baby = _user.currentBaby.value;
                    if (baby == null) {
                      return const Center(child: Text('请先在主页选择宝宝'));
                    }
                    return RefreshIndicator(
                      onRefresh: () => _cloud.syncBaby(baby),
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverToBoxAdapter(child: _buildHeader(baby)),
                          SliverToBoxAdapter(child: _buildSourceBar()),
                          _buildTimeline(baby.id),
                        ],
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 8.w, 6.h),
      child: Row(
        children: [
          Text(
            '亲宝宝',
            style: TextStyle(
              fontSize: 24.sp,
              fontWeight: FontWeight.w900,
              color: AppTheme.textMain,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: '数据源',
            icon: const Icon(Icons.storage_outlined),
            onPressed: () => Get.to(() => const BabyCloudSourcePage()),
          ),
          IconButton(
            tooltip: '回收站',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => Get.to(() => const BabyCloudRecycleBinPage()),
          ),
          IconButton(
            tooltip: '上传',
            icon: const Icon(Icons.add_a_photo),
            onPressed: _showUploadMenu,
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(baby) {
    return Container(
      margin: EdgeInsets.all(16.w),
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18.r),
        gradient: const LinearGradient(
          colors: [Color(0xFFFFC371), Color(0xFFFF9A9E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 34.r,
            backgroundColor: Colors.white,
            child: ClipOval(
              child: ImageUtils.displayImage(
                baby.avatarPath,
                width: 64.w,
                height: 64.w,
                fit: BoxFit.cover,
              ),
            ),
          ),
          SizedBox(width: 14.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  baby.name,
                  style: TextStyle(
                    fontSize: 22.sp,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  '${BabyProfileUtils.ageText(baby)} · ${BabyProfileUtils.genderText(baby.gender)}',
                  style: TextStyle(color: Colors.white, fontSize: 13.sp),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '同步',
            color: Colors.white,
            icon: Obx(
              () => _cloud.isSyncing.value
                  ? SizedBox(
                      width: 20.w,
                      height: 20.w,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.sync),
            ),
            onPressed: () => _cloud.syncBaby(baby),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceBar() {
    return Obx(() {
      if (_cloud.sources.isEmpty) {
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          child: OutlinedButton.icon(
            onPressed: () => Get.to(() => const BabyCloudSourcePage()),
            icon: const Icon(Icons.add),
            label: const Text('配置亲宝宝数据源'),
          ),
        );
      }
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w),
        child: Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _cloud.currentSource.value?.id,
                decoration: InputDecoration(
                  labelText: '数据源',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  isDense: true,
                ),
                items: _cloud.sources
                    .map(
                      (source) => DropdownMenuItem(
                        value: source.id,
                        child: Text(source.name),
                      ),
                    )
                    .toList(),
                onChanged: (id) async {
                  if (id == null) return;
                  await _cloud.selectSource(id);
                  await _syncCurrent();
                },
              ),
            ),
            SizedBox(width: 10.w),
            IconButton.filledTonal(
              tooltip: '后台任务',
              onPressed: () => Get.to(() => const BabyCloudUploadTasksPage()),
              icon: const Icon(Icons.task_alt_outlined),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildTimeline(String babyId) {
    return Obx(() {
      final items = _cloud.mediaForBaby(babyId);
      if (_cloud.currentSource.value == null) {
        return SliverFillRemaining(
          hasScrollBody: false,
          child: _emptyBlock('先配置亲宝宝数据源，再开始备份照片和视频'),
        );
      }
      if (items.isEmpty) {
        final tasks = _cloud.uploadTasks
            .where((task) =>
                task.babyId == babyId &&
                task.dataSourceId == _cloud.currentSource.value?.id)
            .toList();
        final activeTasks = tasks.where((task) => task.isActive).length;
        final failedTasks =
            tasks.where((task) => task.status == 'failed').toList();
        if (activeTasks > 0) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: _taskBlock(
              icon: Icons.task_alt_outlined,
              title: '正在后台处理',
              message: '$activeTasks 个任务正在处理，完成后会自动同步到相册时间轴',
            ),
          );
        }
        if (failedTasks.isNotEmpty) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: _taskBlock(
              icon: Icons.error_outline,
              title: '后台任务失败',
              message: failedTasks.first.errorMessage ?? '未知错误',
            ),
          );
        }
        return SliverFillRemaining(
          hasScrollBody: false,
          child: _emptyBlock('还没有上传照片或视频'),
        );
      }
      final groups = <String, List<BabyCloudMedia>>{};
      for (final item in items) {
        final key = DateFormat('yyyy-MM-dd').format(item.takenAt);
        groups.putIfAbsent(key, () => []).add(item);
      }
      final entries = groups.entries.toList();
      return SliverPadding(
        padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 24.h),
        sliver: SliverList.builder(
          itemCount: entries.length,
          itemBuilder: (_, index) {
            final entry = entries[index];
            final date = DateTime.parse(entry.key);
            return _buildDayGroup(date, entry.value);
          },
        ),
      );
    });
  }

  Widget _buildDayGroup(DateTime date, List<BabyCloudMedia> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 8.h, bottom: 10.h),
          child: Row(
            children: [
              Container(
                width: 10.w,
                height: 10.w,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.amber, width: 3),
                ),
              ),
              SizedBox(width: 10.w),
              Text(
                DateFormat('M月d日').format(date),
                style: TextStyle(
                  fontSize: 20.sp,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textMain,
                ),
              ),
              SizedBox(width: 8.w),
              Text('${items.length}项',
                  style: TextStyle(color: Colors.grey.shade600)),
            ],
          ),
        ),
        _buildMediaWrap(items),
        SizedBox(height: 12.h),
      ],
    );
  }

  Widget _buildMediaWrap(List<BabyCloudMedia> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = 5.w;
        final tileSize = (constraints.maxWidth - gap * 2) / 3;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var index = 0; index < items.length; index++)
              SizedBox(
                width: tileSize,
                height: tileSize,
                child: _buildMediaTile(items, index),
              ),
          ],
        );
      },
    );
  }

  Widget _buildMediaTile(List<BabyCloudMedia> items, int index) {
    final item = items[index];
    return Material(
      color: Colors.grey.shade200,
      borderRadius: BorderRadius.circular(8.r),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Get.to(
          () => BabyCloudMediaDetailPage(
            items: items,
            initialIndex: index,
          ),
        ),
        child: BabyCloudMediaThumbnail(
          item: item,
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _emptyBlock(String text) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 72.h),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.photo_library_outlined,
                size: 68.sp, color: Colors.grey.shade300),
            SizedBox(height: 12.h),
            Text(text, style: TextStyle(color: Colors.grey.shade700)),
            SizedBox(height: 16.h),
            ElevatedButton.icon(
              onPressed: _showUploadMenu,
              icon: const Icon(Icons.add_a_photo),
              label: const Text('上传照片/视频'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _taskBlock({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 72.h, horizontal: 28.w),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 52.sp, color: Colors.grey.shade500),
            SizedBox(height: 14.h),
            Text(
              title,
              style: TextStyle(
                color: Colors.grey.shade800,
                fontSize: 16.sp,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              message,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            SizedBox(height: 16.h),
            OutlinedButton.icon(
              onPressed: () => Get.to(() => const BabyCloudUploadTasksPage()),
              icon: const Icon(Icons.task_alt_outlined),
              label: const Text('查看后台任务'),
            ),
          ],
        ),
      ),
    );
  }

  void _showUploadMenu() {
    if (_user.currentBaby.value == null) {
      ToastUtils.showWarning('请先在主页选择宝宝');
      return;
    }
    if (!_cloud.hasUsableCurrentSource) {
      _showSourceRequiredSheet();
      return;
    }
    Get.bottomSheet(
      Container(
        padding: EdgeInsets.all(20.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('上传照片/视频'),
              onTap: () async {
                Get.back();
                await Future<void>.delayed(const Duration(milliseconds: 120));
                final result = await Get.to(
                  () => const BabyCloudMediaPickerPage(),
                );
                if (result == true) {
                  _cloud.reloadLocalMedia();
                  unawaited(_cloud.processQueue());
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.task_alt_outlined),
              title: const Text('查看后台任务'),
              onTap: () {
                Get.back();
                Get.to(() => const BabyCloudUploadTasksPage());
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showSourceRequiredSheet() {
    Get.bottomSheet(
      Container(
        padding: EdgeInsets.fromLTRB(20.w, 18.h, 20.w, 24.h),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 44.sp, color: Colors.grey.shade500),
            SizedBox(height: 10.h),
            Text(
              _cloud.currentSourceSetupMessage,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 16.h),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: Get.back,
                    child: const Text('取消'),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Get.back();
                      Get.to(() => const BabyCloudSourcePage());
                    },
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('去配置'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
