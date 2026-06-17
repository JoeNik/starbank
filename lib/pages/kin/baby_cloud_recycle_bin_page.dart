import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../controllers/app_mode_controller.dart';
import '../../controllers/user_controller.dart';
import '../../models/baby_cloud_entry.dart';
import '../../models/baby_cloud_media.dart';
import '../../services/baby_cloud_service.dart';
import '../../widgets/baby_cloud_media_thumbnail.dart';
import '../../widgets/toast_utils.dart';
import 'baby_cloud_permanent_delete_page.dart';

class BabyCloudRecycleBinPage extends StatelessWidget {
  const BabyCloudRecycleBinPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cloud = Get.find<BabyCloudService>();
    final babyId = Get.find<UserController>().currentBaby.value?.id;
    final mode = Get.find<AppModeController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('亲宝宝回收站'),
        actions: [
          IconButton(
            tooltip: '永久删除云端原文件',
            icon: const Icon(Icons.delete_forever_outlined),
            onPressed: () => Get.to(() => const BabyCloudPermanentDeletePage()),
          ),
        ],
      ),
      body: Obx(() {
        if (babyId == null) return const Center(child: Text('请先选择宝宝'));

        final allMedia = cloud.mediaForBaby(babyId, includeDeleted: true);
        final deletedEntries = cloud
            .entriesForBaby(babyId, includeDeleted: true)
            .where((entry) => entry.isDeleted && !entry.isPurged)
            .toList()
          ..sort((a, b) => (b.deletedAt ?? b.updatedAt)
              .compareTo(a.deletedAt ?? a.updatedAt));
        final singleFiles = allMedia
            .where((item) =>
                item.isDeleted &&
                !item.isPurged &&
                item.deleteReason != 'entryDeleted')
            .toList()
          ..sort((a, b) => (b.deletedAt ?? b.updatedAt)
              .compareTo(a.deletedAt ?? a.updatedAt));

        if (deletedEntries.isEmpty && singleFiles.isEmpty) {
          return const Center(child: Text('回收站为空'));
        }

        return ListView(
          padding: EdgeInsets.all(16.w),
          children: [
            if (deletedEntries.isNotEmpty) ...[
              _sectionTitle('整条动态'),
              for (final entry in deletedEntries)
                _EntryRecycleTile(
                  entry: entry,
                  mediaItems: _mediaForEntry(allMedia, entry),
                  enabled: mode.isParentMode,
                  onRestore: () async {
                    await cloud.restoreEntry(entry);
                    ToastUtils.showSuccess('动态已恢复');
                  },
                ),
            ],
            if (singleFiles.isNotEmpty) ...[
              _sectionTitle('单文件'),
              for (final item in singleFiles)
                _MediaRecycleTile(
                  item: item,
                  enabled: mode.isParentMode,
                  onRestore: () async {
                    await cloud.restoreMedia(item);
                    ToastUtils.showSuccess('文件已恢复');
                  },
                ),
            ],
          ],
        );
      }),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: EdgeInsets.fromLTRB(2.w, 12.h, 2.w, 8.h),
      child: Text(
        title,
        style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w900),
      ),
    );
  }
}

List<BabyCloudMedia> _mediaForEntry(
  List<BabyCloudMedia> allMedia,
  BabyCloudEntry entry,
) {
  final mediaIds = entry.mediaIds.toSet();
  return allMedia
      .where((item) => item.entryId == entry.id || mediaIds.contains(item.id))
      .toList();
}

class _EntryRecycleTile extends StatelessWidget {
  const _EntryRecycleTile({
    required this.entry,
    required this.mediaItems,
    required this.enabled,
    required this.onRestore,
  });

  final BabyCloudEntry entry;
  final List<BabyCloudMedia> mediaItems;
  final bool enabled;
  final Future<void> Function() onRestore;

  @override
  Widget build(BuildContext context) {
    final firstMedia = mediaItems.firstOrNull;
    final title = entry.description?.trim().isNotEmpty == true
        ? entry.description!.trim()
        : '已删除动态';
    return Card(
      child: ListTile(
        leading: _preview(firstMedia),
        title: Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${mediaItems.length} 个文件 · 删除于 ${_timeText(entry.deletedAt)}',
        ),
        trailing: IconButton(
          tooltip: '恢复整条动态',
          icon: const Icon(Icons.restore),
          onPressed: enabled
              ? () async {
                  try {
                    await onRestore();
                  } catch (e) {
                    ToastUtils.showError('恢复失败: $e');
                  }
                }
              : () => ToastUtils.showWarning('请先切换到家长模式'),
        ),
      ),
    );
  }
}

class _MediaRecycleTile extends StatelessWidget {
  const _MediaRecycleTile({
    required this.item,
    required this.enabled,
    required this.onRestore,
  });

  final BabyCloudMedia item;
  final bool enabled;
  final Future<void> Function() onRestore;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: _preview(item),
        title: Text(
          item.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text('删除于 ${_timeText(item.deletedAt)}'),
        trailing: IconButton(
          tooltip: '恢复文件',
          icon: const Icon(Icons.restore),
          onPressed: () async {
            if (!enabled) {
              ToastUtils.showWarning('请先切换到家长模式');
              return;
            }
            try {
              await onRestore();
            } catch (e) {
              ToastUtils.showError('恢复失败: $e');
            }
          },
        ),
      ),
    );
  }
}

Widget _preview(BabyCloudMedia? item) {
  if (item == null) {
    return SizedBox.square(
      dimension: 54.w,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8.r),
        ),
        child: const Icon(Icons.notes_outlined),
      ),
    );
  }
  return SizedBox.square(
    dimension: 54.w,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(8.r),
      child: BabyCloudMediaThumbnail(item: item, fit: BoxFit.cover),
    ),
  );
}

String _timeText(DateTime? value) {
  if (value == null) return '未知时间';
  return DateFormat('yyyy-MM-dd HH:mm').format(value);
}
