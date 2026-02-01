import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../models/new_year_story.dart';
import '../../../services/story_management_service.dart';
import '../../../widgets/toast_utils.dart';

/// 故事编辑对话框
class StoryEditDialog extends StatefulWidget {
  final NewYearStory story;

  const StoryEditDialog({super.key, required this.story});

  @override
  State<StoryEditDialog> createState() => _StoryEditDialogState();
}

class _StoryEditDialogState extends State<StoryEditDialog> {
  final StoryManagementService _storyService = StoryManagementService.instance;

  late TextEditingController _titleController;
  late TextEditingController _emojiController;
  late TextEditingController _durationController;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.story.title);
    _emojiController = TextEditingController(text: widget.story.emoji);
    _durationController = TextEditingController(text: widget.story.duration);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _emojiController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  /// 保存修改
  Future<void> _save() async {
    final title = _titleController.text.trim();
    final emoji = _emojiController.text.trim();
    final duration = _durationController.text.trim();

    if (title.isEmpty) {
      ToastUtils.showWarning('请输入故事标题');
      return;
    }

    if (emoji.isEmpty) {
      ToastUtils.showWarning('请输入 Emoji');
      return;
    }

    // 检查标题是否重复(排除自己)
    if (title != widget.story.title &&
        _storyService.isDuplicate(title, excludeId: widget.story.id)) {
      ToastUtils.showWarning('故事标题已存在');
      return;
    }

    setState(() => _isSaving = true);

    try {
      // 更新故事信息
      widget.story.title = title;
      widget.story.emoji = emoji;
      widget.story.duration = duration;

      await _storyService.updateStory(widget.story);

      ToastUtils.showSuccess('保存成功');
      Navigator.pop(context, true);
    } catch (e) {
      ToastUtils.showError('保存失败: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑故事'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: '故事标题',
                border: OutlineInputBorder(),
              ),
              enabled: !_isSaving,
            ),
            SizedBox(height: 16.h),
            TextField(
              controller: _emojiController,
              decoration: const InputDecoration(
                labelText: 'Emoji',
                hintText: '🎊',
                border: OutlineInputBorder(),
              ),
              enabled: !_isSaving,
              maxLength: 2,
            ),
            SizedBox(height: 16.h),
            TextField(
              controller: _durationController,
              decoration: const InputDecoration(
                labelText: '时长',
                hintText: '2分钟',
                border: OutlineInputBorder(),
              ),
              enabled: !_isSaving,
            ),
            SizedBox(height: 16.h),
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '故事信息',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8.h),
                  Text('页面数: ${widget.story.pageCount}'),
                  Text('创建时间: ${_formatDate(widget.story.createdAt)}'),
                  Text('更新时间: ${_formatDate(widget.story.updatedAt)}'),
                ],
              ),
            ),
            SizedBox(height: 8.h),
            const Text(
              '注意:当前仅支持编辑基本信息,故事内容暂不支持编辑',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }

  /// 格式化日期
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
