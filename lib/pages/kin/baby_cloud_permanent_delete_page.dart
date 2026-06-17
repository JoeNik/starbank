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

class BabyCloudPermanentDeletePage extends StatefulWidget {
  const BabyCloudPermanentDeletePage({super.key});

  @override
  State<BabyCloudPermanentDeletePage> createState() =>
      _BabyCloudPermanentDeletePageState();
}

class _BabyCloudPermanentDeletePageState
    extends State<BabyCloudPermanentDeletePage> {
  final _cloud = Get.find<BabyCloudService>();
  final _user = Get.find<UserController>();
  final _mode = Get.find<AppModeController>();
  final _selectedEntries = <String>{};
  final _selectedMedia = <String>{};
  final _queuedEntryIds = <String>{};
  final _queuedMediaIds = <String>{};
  bool _deleting = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('永久删除云端原文件')),
      body: Obx(() {
        final babyId = _user.currentBaby.value?.id;
        if (babyId == null) return const Center(child: Text('请先选择宝宝'));

        final activePurgeEntryIds = <String>{
          ..._queuedEntryIds,
          for (final task in _cloud.uploadTasks)
            if (task.taskType == 'purgeEntry' &&
                _isActivePurgeTask(task.status) &&
                task.targetId?.isNotEmpty == true)
              task.targetId!,
        };
        final activePurgeMediaIds = <String>{
          ..._queuedMediaIds,
          for (final task in _cloud.uploadTasks)
            if (task.taskType == 'purgeMedia' &&
                _isActivePurgeTask(task.status) &&
                task.targetId?.isNotEmpty == true)
              task.targetId!,
        };
        final allMedia = _cloud.mediaForBaby(babyId, includeDeleted: true);
        final deletedEntries = _cloud
            .entriesForBaby(babyId, includeDeleted: true)
            .where((entry) =>
                entry.isDeleted &&
                !entry.isPurged &&
                !activePurgeEntryIds.contains(entry.id))
            .toList()
          ..sort((a, b) => (b.deletedAt ?? b.updatedAt)
              .compareTo(a.deletedAt ?? a.updatedAt));
        final singleFiles = allMedia
            .where((item) =>
                item.isDeleted &&
                !item.isPurged &&
                !activePurgeMediaIds.contains(item.id) &&
                item.deleteReason != 'entryDeleted')
            .toList()
          ..sort((a, b) => (b.deletedAt ?? b.updatedAt)
              .compareTo(a.deletedAt ?? a.updatedAt));

        if (deletedEntries.isEmpty && singleFiles.isEmpty) {
          return const Center(child: Text('没有可永久删除的云端原文件'));
        }

        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 92.h),
                children: [
                  _warningBlock(),
                  if (deletedEntries.isNotEmpty) ...[
                    _sectionTitle('整条动态', '会删除动态关联的所有云端媒体文件'),
                    for (final entry in deletedEntries)
                      _entryTile(entry, _mediaForEntry(allMedia, entry)),
                  ],
                  if (singleFiles.isNotEmpty) ...[
                    _sectionTitle('单文件', '只删除该文件和对应缩略图'),
                    for (final item in singleFiles) _mediaTile(item),
                  ],
                ],
              ),
            ),
            _bottomBar(deletedEntries, singleFiles),
          ],
        );
      }),
    );
  }

  Widget _warningBlock() {
    return Container(
      margin: EdgeInsets.only(bottom: 14.h),
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Text(
        '这里才会真正删除云端原文件。普通回收站删除只做标记，不会碰云端原文件。',
        style: TextStyle(
          fontSize: 13.sp,
          height: 1.35,
          color: const Color(0xFF8A5200),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, String subtitle) {
    return Padding(
      padding: EdgeInsets.only(top: 12.h, bottom: 8.h),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w900),
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.sp, color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _entryTile(BabyCloudEntry entry, List<BabyCloudMedia> mediaItems) {
    final selected = _selectedEntries.contains(entry.id);
    final firstMedia = mediaItems.firstOrNull;
    final title = entry.description?.trim().isNotEmpty == true
        ? entry.description!.trim()
        : '已删除动态';
    final remotePaths = mediaItems
        .where((item) => item.remotePath.trim().isNotEmpty)
        .map((item) => item.remotePath)
        .toList();
    return Card(
      child: CheckboxListTile(
        value: selected,
        onChanged: _deleting
            ? null
            : (value) {
                setState(() {
                  value == true
                      ? _selectedEntries.add(entry.id)
                      : _selectedEntries.remove(entry.id);
                });
              },
        secondary: _preview(firstMedia),
        title: Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${mediaItems.length} 个文件 · 删除于 ${_timeText(entry.deletedAt)}\n${remotePaths.take(2).join('\n')}',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _mediaTile(BabyCloudMedia item) {
    final selected = _selectedMedia.contains(item.id);
    return Card(
      child: CheckboxListTile(
        value: selected,
        onChanged: _deleting
            ? null
            : (value) {
                setState(() {
                  value == true
                      ? _selectedMedia.add(item.id)
                      : _selectedMedia.remove(item.id);
                });
              },
        secondary: _preview(item),
        title: Text(
          item.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '删除于 ${_timeText(item.deletedAt)}\n${item.remotePath}',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
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

  Widget _bottomBar(
    List<BabyCloudEntry> entries,
    List<BabyCloudMedia> mediaItems,
  ) {
    final entryIds = entries.map((entry) => entry.id).toSet();
    final mediaIds = mediaItems.map((item) => item.id).toSet();
    final count = _selectedEntries.intersection(entryIds).length +
        _selectedMedia.intersection(mediaIds).length;
    final total = entryIds.length + mediaIds.length;
    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 12.h),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  total == 0 ? '没有可删除项目' : '已选 $count/$total',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: total == 0 || _deleting
                      ? null
                      : () => _selectAll(entries, mediaItems),
                  child: const Text('全选'),
                ),
                TextButton(
                  onPressed: total == 0 || _deleting
                      ? null
                      : () => _invertSelection(entries, mediaItems),
                  child: const Text('反选'),
                ),
              ],
            ),
            SizedBox(height: 8.h),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: count == 0 || _deleting
                    ? null
                    : () => _confirmAndDelete(entries, mediaItems),
                icon: _deleting
                    ? SizedBox.square(
                        dimension: 18.w,
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_forever),
                label: Text(count == 0 ? '请选择要永久删除的项目' : '加入后台删除 $count 项'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isActivePurgeTask(String status) {
    return status == 'queued' || status == 'running' || status == 'paused';
  }

  void _selectAll(
    List<BabyCloudEntry> entries,
    List<BabyCloudMedia> mediaItems,
  ) {
    setState(() {
      _selectedEntries.addAll(entries.map((entry) => entry.id));
      _selectedMedia.addAll(mediaItems.map((item) => item.id));
    });
  }

  void _invertSelection(
    List<BabyCloudEntry> entries,
    List<BabyCloudMedia> mediaItems,
  ) {
    setState(() {
      for (final entry in entries) {
        _selectedEntries.contains(entry.id)
            ? _selectedEntries.remove(entry.id)
            : _selectedEntries.add(entry.id);
      }
      for (final item in mediaItems) {
        _selectedMedia.contains(item.id)
            ? _selectedMedia.remove(item.id)
            : _selectedMedia.add(item.id);
      }
    });
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

  Future<void> _confirmAndDelete(
    List<BabyCloudEntry> entries,
    List<BabyCloudMedia> mediaItems,
  ) async {
    if (!_mode.isParentMode) {
      ToastUtils.showWarning('请先切换到家长模式');
      return;
    }
    final ok = await _verifyParentPassword();
    if (!ok || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认永久删除'),
        content: const Text('将删除所选项目的云端原文件和缩略图。这个动作无法从回收站恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final selectedEntries =
        entries.where((entry) => _selectedEntries.contains(entry.id)).toList();
    final selectedMedia =
        mediaItems.where((item) => _selectedMedia.contains(item.id)).toList();
    if (selectedEntries.isEmpty && selectedMedia.isEmpty) {
      ToastUtils.showInfo('当前没有选中的可删除项目');
      return;
    }

    setState(() => _deleting = true);
    try {
      var queued = 0;
      final queuedEntryIds = <String>{};
      final queuedMediaIds = <String>{};
      for (final entry in selectedEntries) {
        if (await _cloud.queueHardDeleteEntry(entry)) {
          queued++;
          queuedEntryIds.add(entry.id);
        }
      }
      for (final item in selectedMedia) {
        if (await _cloud.queueHardDeleteMedia(item)) {
          queued++;
          queuedMediaIds.add(item.id);
        }
      }
      if (!mounted) return;
      setState(() {
        _queuedEntryIds.addAll(queuedEntryIds);
        _queuedMediaIds.addAll(queuedMediaIds);
        _selectedEntries.clear();
        _selectedMedia.clear();
      });
      ToastUtils.showSuccess(
        queued > 0 ? '已加入 $queued 个后台删除任务' : '删除任务已在后台处理',
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<bool> _verifyParentPassword() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _ParentPasswordDialog(mode: _mode),
    );
    return result == true;
  }

  String _timeText(DateTime? value) {
    if (value == null) return '未知时间';
    return DateFormat('yyyy-MM-dd HH:mm').format(value);
  }
}

class _ParentPasswordDialog extends StatefulWidget {
  const _ParentPasswordDialog({required this.mode});

  final AppModeController mode;

  @override
  State<_ParentPasswordDialog> createState() => _ParentPasswordDialogState();
}

class _ParentPasswordDialogState extends State<_ParentPasswordDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    _submitAsync();
  }

  Future<void> _submitAsync() async {
    await widget.mode.ensureInitialized();
    if (!mounted) return;
    if (widget.mode.verifyPassword(_controller.text)) {
      Navigator.of(context).pop(true);
    } else {
      ToastUtils.showError('密码错误');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('验证家长密码'),
      content: TextField(
        controller: _controller,
        obscureText: true,
        autofocus: true,
        onSubmitted: (_) => _submit(),
        decoration: const InputDecoration(
          labelText: '密码',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('确认'),
        ),
      ],
    );
  }
}
