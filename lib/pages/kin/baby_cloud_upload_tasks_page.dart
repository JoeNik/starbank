import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../models/baby_cloud_upload_task.dart';
import '../../services/baby_cloud_service.dart';
import '../../widgets/toast_utils.dart';

class BabyCloudUploadTasksPage extends StatefulWidget {
  const BabyCloudUploadTasksPage({super.key});

  @override
  State<BabyCloudUploadTasksPage> createState() =>
      _BabyCloudUploadTasksPageState();
}

class _BabyCloudUploadTasksPageState extends State<BabyCloudUploadTasksPage> {
  final _selectedIds = <String>{};

  BabyCloudService get _cloud => Get.find<BabyCloudService>();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final tasks = _cloud.uploadTasks.toList();
      final visibleIds = tasks.map((task) => task.id).toSet();
      final selectedIds = _selectedIds.intersection(visibleIds);
      final selectedCount = selectedIds.length;

      return Scaffold(
        appBar: AppBar(
          title: Text(selectedCount == 0 ? '后台任务' : '已选择 $selectedCount 项'),
          actions: [
            if (tasks.isNotEmpty)
              IconButton(
                tooltip: '全选',
                icon: const Icon(Icons.select_all),
                onPressed: () => _selectAll(tasks),
              ),
            IconButton(
              tooltip: '清理已成功',
              icon: const Icon(Icons.done_all_outlined),
              onPressed: tasks.any((task) => task.status == 'completed')
                  ? _clearSuccessful
                  : null,
            ),
            IconButton(
              tooltip: '清理失败',
              icon: const Icon(Icons.error_outline),
              onPressed: tasks.any((task) => task.status == 'failed')
                  ? _clearFailed
                  : null,
            ),
          ],
        ),
        body: _buildBody(tasks, selectedIds),
      );
    });
  }

  Widget _buildBody(
    List<BabyCloudUploadTask> tasks,
    Set<String> selectedIds,
  ) {
    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_done_outlined,
              size: 58.sp,
              color: Colors.grey.shade300,
            ),
            SizedBox(height: 10.h),
            Text('暂无后台任务', style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      );
    }

    return Column(
      children: [
        _BulkActionBar(
          taskCount: tasks.length,
          selectedCount: selectedIds.length,
          hasFailed: tasks.any((task) => task.status == 'failed'),
          canStartSelected: _selectedTasks(tasks, selectedIds).any(
            (task) => task.status == 'paused' || task.status == 'failed',
          ),
          canPauseSelected: _selectedTasks(tasks, selectedIds).any(
            (task) => task.status == 'queued' || task.status == 'running',
          ),
          onSelectAll: () => _selectAll(tasks),
          onInvert: () => _invertSelection(tasks),
          onRetryFailed: () => _retryFailed(tasks),
          onStartSelected: () => _startSelected(tasks, selectedIds),
          onPauseSelected: () => _pauseSelected(tasks, selectedIds),
        ),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(10.w, 8.h, 10.w, 18.h),
            itemCount: tasks.length,
            separatorBuilder: (_, __) => SizedBox(height: 8.h),
            itemBuilder: (_, index) {
              final task = tasks[index];
              return _TaskTile(
                task: task,
                selected: selectedIds.contains(task.id),
                selectionActive: selectedIds.isNotEmpty,
                onSelectedChanged: (_) => _toggleSelection(task.id),
              );
            },
          ),
        ),
      ],
    );
  }

  List<BabyCloudUploadTask> _selectedTasks(
    List<BabyCloudUploadTask> tasks,
    Set<String> selectedIds,
  ) {
    return tasks.where((task) => selectedIds.contains(task.id)).toList();
  }

  void _toggleSelection(String taskId) {
    setState(() {
      if (!_selectedIds.add(taskId)) {
        _selectedIds.remove(taskId);
      }
    });
  }

  void _selectAll(List<BabyCloudUploadTask> tasks) {
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(tasks.map((task) => task.id));
    });
  }

  void _invertSelection(List<BabyCloudUploadTask> tasks) {
    final ids = tasks.map((task) => task.id).toSet();
    final current = _selectedIds.intersection(ids);
    final inverted = ids.difference(current);
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(inverted);
    });
  }

  Future<void> _retryFailed(List<BabyCloudUploadTask> tasks) async {
    final failed = tasks.where((task) => task.status == 'failed').toList();
    if (failed.isEmpty) {
      ToastUtils.showInfo('没有失败任务需要重试');
      return;
    }
    await _cloud.retryFailedTasks(failed);
    ToastUtils.showSuccess('已重新开始 ${failed.length} 个失败任务');
  }

  Future<void> _startSelected(
    List<BabyCloudUploadTask> tasks,
    Set<String> selectedIds,
  ) async {
    final selected = _selectedTasks(tasks, selectedIds)
        .where((task) => task.status == 'paused' || task.status == 'failed')
        .toList();
    if (selected.isEmpty) {
      ToastUtils.showInfo('选中的任务没有可开始项');
      return;
    }
    await _cloud.resumeTasks(selected);
    ToastUtils.showSuccess('已开始 ${selected.length} 个任务');
  }

  Future<void> _pauseSelected(
    List<BabyCloudUploadTask> tasks,
    Set<String> selectedIds,
  ) async {
    final selected = _selectedTasks(tasks, selectedIds)
        .where((task) => task.status == 'queued' || task.status == 'running')
        .toList();
    if (selected.isEmpty) {
      ToastUtils.showInfo('选中的任务没有可暂停项');
      return;
    }
    await _cloud.pauseTasks(selected);
    ToastUtils.showSuccess('已暂停 ${selected.length} 个任务');
  }

  Future<void> _clearSuccessful() async {
    final count = await _cloud.clearSuccessfulTasks();
    _pruneSelection();
    if (count == 0) {
      ToastUtils.showInfo('没有已成功任务可清理');
      return;
    }
    ToastUtils.showSuccess('已清理 $count 个成功任务');
  }

  Future<void> _clearFailed() async {
    final count = await _cloud.clearFailedTasks();
    _pruneSelection();
    if (count == 0) {
      ToastUtils.showInfo('没有失败任务可清理');
      return;
    }
    ToastUtils.showSuccess('已清理 $count 个失败任务');
  }

  void _pruneSelection() {
    if (!mounted) return;
    final visibleIds = _cloud.uploadTasks.map((task) => task.id).toSet();
    setState(() => _selectedIds.removeWhere((id) => !visibleIds.contains(id)));
  }
}

class _BulkActionBar extends StatelessWidget {
  const _BulkActionBar({
    required this.taskCount,
    required this.selectedCount,
    required this.hasFailed,
    required this.canStartSelected,
    required this.canPauseSelected,
    required this.onSelectAll,
    required this.onInvert,
    required this.onRetryFailed,
    required this.onStartSelected,
    required this.onPauseSelected,
  });

  final int taskCount;
  final int selectedCount;
  final bool hasFailed;
  final bool canStartSelected;
  final bool canPauseSelected;
  final VoidCallback onSelectAll;
  final VoidCallback onInvert;
  final VoidCallback onRetryFailed;
  final VoidCallback onStartSelected;
  final VoidCallback onPauseSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(10.w, 8.h, 10.w, 6.h),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Text(
              '$selectedCount/$taskCount',
              style: TextStyle(
                fontSize: 12.sp,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(width: 8.w),
            _barButton(
              tooltip: '全选',
              icon: Icons.select_all,
              onPressed: onSelectAll,
            ),
            _barButton(
              tooltip: '反选',
              icon: Icons.flip_to_back_outlined,
              onPressed: onInvert,
            ),
            _barButton(
              tooltip: '重试失败',
              icon: Icons.refresh,
              onPressed: hasFailed ? onRetryFailed : null,
            ),
            _barButton(
              tooltip: '开始选中',
              icon: Icons.play_circle_outline,
              onPressed: canStartSelected ? onStartSelected : null,
            ),
            _barButton(
              tooltip: '暂停选中',
              icon: Icons.pause_circle_outline,
              onPressed: canPauseSelected ? onPauseSelected : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _barButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        iconSize: 22,
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tightFor(width: 36.w, height: 34.h),
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.task,
    required this.selected,
    required this.selectionActive,
    required this.onSelectedChanged,
  });

  final BabyCloudUploadTask task;
  final bool selected;
  final bool selectionActive;
  final ValueChanged<bool?> onSelectedChanged;

  @override
  Widget build(BuildContext context) {
    final cloud = Get.find<BabyCloudService>();
    final progress = task.progress.clamp(0.0, 1.0).toDouble();
    final color = _statusColor(task.status);
    final visibleError = _visibleErrorMessage(task);
    final canDelete = !task.isActive;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(10.r),
        onTap: () {
          if (selectionActive) {
            onSelectedChanged(!selected);
            return;
          }
          if (visibleError != null) _showError(context, visibleError);
        },
        onLongPress: () => onSelectedChanged(!selected),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 9.h),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(
              color: selected ? Colors.blue.shade300 : Colors.grey.shade200,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Checkbox(
                value: selected,
                visualDensity: VisualDensity.compact,
                onChanged: onSelectedChanged,
              ),
              Container(
                width: 38.w,
                height: 38.w,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9.r),
                ),
                child: Icon(_taskIcon(task), color: color, size: 21),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _taskTitle(task),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Text(
                          _statusText(task),
                          style: TextStyle(
                            color: color,
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 5.h),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              minHeight: 4.h,
                              value: progress,
                              backgroundColor: Colors.grey.shade100,
                              color: color,
                            ),
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Text(
                          '${(progress * 100).round()}%',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 11.sp,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      visibleError ?? _taskSubtitle(task),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: visibleError == null
                            ? Colors.grey.shade500
                            : Colors.red.shade500,
                        fontSize: 11.sp,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 4.w),
              _actionButton(
                tooltip: task.status == 'paused'
                    ? '继续'
                    : task.status == 'failed'
                        ? '重试'
                        : '停止',
                icon: task.status == 'paused'
                    ? Icons.play_circle_outline
                    : task.status == 'failed'
                        ? Icons.refresh
                        : Icons.pause_circle_outline,
                enabled: task.status == 'running' ||
                    task.status == 'queued' ||
                    task.status == 'paused' ||
                    task.status == 'failed',
                onPressed: () {
                  if (task.status == 'paused' || task.status == 'failed') {
                    cloud.resumeTask(task);
                  } else {
                    cloud.pauseTask(task);
                  }
                },
              ),
              _actionButton(
                tooltip: '清理任务',
                icon: Icons.delete_outline,
                enabled: canDelete,
                disabledTooltip: '正在进行的任务不能清理',
                onPressed: () => cloud.deleteTask(task),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showError(BuildContext context, String message) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('任务错误'),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String tooltip,
    required IconData icon,
    required bool enabled,
    required VoidCallback onPressed,
    String? disabledTooltip,
  }) {
    return Tooltip(
      message: enabled ? tooltip : (disabledTooltip ?? '当前状态不能执行'),
      child: IconButton(
        visualDensity: VisualDensity.compact,
        iconSize: 22,
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tightFor(width: 32.w, height: 32.w),
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon),
      ),
    );
  }

  IconData _taskIcon(BabyCloudUploadTask task) {
    switch (task.taskType) {
      case 'metadata':
        return Icons.sync_outlined;
      case 'purgeMedia':
      case 'purgeEntry':
        return Icons.delete_forever_outlined;
    }
    switch (task.mediaType) {
      case 'video':
        return Icons.videocam_outlined;
      case 'audio':
        return Icons.mic_none_outlined;
      case 'diary':
        return Icons.notes_outlined;
      default:
        return Icons.image_outlined;
    }
  }

  String _taskTitle(BabyCloudUploadTask task) {
    if (task.taskType == 'metadata') return '同步动态修改';
    if (task.taskType == 'purgeEntry') return '永久删除动态';
    if (task.taskType == 'purgeMedia') return '永久删除文件';
    return task.fileName;
  }

  String _taskSubtitle(BabyCloudUploadTask task) {
    if (task.taskType == 'metadata') return '动态信息已保存，正在同步云端索引';
    if (task.taskType == 'purgeEntry') return '后台删除动态关联的云端原文件';
    if (task.taskType == 'purgeMedia') return '后台删除单个云端原文件';
    return '${_mediaText(task.mediaType)} · ${_formatBytes(task.sizeBytes)} · 支持断点续传';
  }

  String? _visibleErrorMessage(BabyCloudUploadTask task) {
    final message = task.errorMessage?.trim();
    if (message == null || message.isEmpty) return null;
    if (task.status == 'failed') return message;
    if (task.status == 'queued' && task.retryCount > 0) return message;
    return null;
  }

  String _mediaText(String mediaType) {
    switch (mediaType) {
      case 'video':
        return '视频';
      case 'audio':
        return '录音';
      case 'diary':
        return '文字';
      default:
        return '照片';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'running':
        return Colors.orange.shade700;
      case 'completed':
        return Colors.green.shade600;
      case 'failed':
        return Colors.red.shade600;
      case 'paused':
        return Colors.blueGrey.shade600;
      case 'cancelled':
        return Colors.grey.shade600;
      default:
        return Colors.blue.shade600;
    }
  }

  String _statusText(BabyCloudUploadTask task) {
    switch (task.status) {
      case 'queued':
        return '等待中';
      case 'running':
        if (task.taskType == 'metadata') return '同步中';
        if (task.taskType == 'purgeMedia' || task.taskType == 'purgeEntry') {
          return '删除中';
        }
        return '上传中';
      case 'paused':
        return '已停止';
      case 'completed':
        return '已完成';
      case 'failed':
        return '失败';
      case 'cancelled':
        return '已取消';
      default:
        return task.status;
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '未知大小';
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(1)} KB';
    return '$bytes B';
  }
}
