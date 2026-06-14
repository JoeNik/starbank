import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../models/baby_cloud_upload_task.dart';
import '../../services/baby_cloud_service.dart';

class BabyCloudUploadTasksPage extends StatelessWidget {
  const BabyCloudUploadTasksPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cloud = Get.find<BabyCloudService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('后台任务'),
        actions: [
          IconButton(
            tooltip: '清除已完成',
            icon: const Icon(Icons.cleaning_services_outlined),
            onPressed: cloud.clearCompletedTasks,
          ),
        ],
      ),
      body: Obx(() {
        final tasks = cloud.uploadTasks;
        if (tasks.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_done_outlined,
                    size: 58.sp, color: Colors.grey.shade300),
                SizedBox(height: 10.h),
                Text('暂无后台任务', style: TextStyle(color: Colors.grey.shade600)),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: EdgeInsets.fromLTRB(10.w, 8.h, 10.w, 18.h),
          itemCount: tasks.length,
          separatorBuilder: (_, __) => SizedBox(height: 8.h),
          itemBuilder: (_, index) => _TaskTile(task: tasks[index]),
        );
      }),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task});

  final BabyCloudUploadTask task;

  @override
  Widget build(BuildContext context) {
    final cloud = Get.find<BabyCloudService>();
    final progress = task.progress.clamp(0.0, 1.0).toDouble();
    final color = _statusColor(task.status);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(10.r),
        onTap: task.errorMessage == null ? null : () => _showError(context),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 9.h),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Container(
                width: 38.w,
                height: 38.w,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
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
                          task.errorMessage?.isNotEmpty == true
                              ? task.errorMessage!
                          : _taskSubtitle(task),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: task.errorMessage == null
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
                tooltip: '删除任务',
                icon: Icons.delete_outline,
                enabled: true,
                onPressed: () => cloud.deleteTask(task),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showError(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('任务错误'),
        content: SingleChildScrollView(child: Text(task.errorMessage ?? '')),
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
  }) {
    return Tooltip(
      message: enabled ? tooltip : '当前状态不能执行',
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
    if (task.taskType == 'purgeEntry') return '后台删除动态关联的 WebDAV 原文件';
    if (task.taskType == 'purgeMedia') return '后台删除单个 WebDAV 原文件';
    return '${_mediaText(task.mediaType)} · ${_formatBytes(task.sizeBytes)} · 支持断点续传';
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
