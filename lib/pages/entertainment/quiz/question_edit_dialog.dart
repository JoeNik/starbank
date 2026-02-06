import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import '../../../models/quiz_question.dart';
import '../../../services/quiz_service.dart';
import '../../../widgets/toast_utils.dart';

/// 题目编辑对话框
class QuestionEditDialog extends StatefulWidget {
  final QuizQuestion question;

  const QuestionEditDialog({super.key, required this.question});

  @override
  State<QuestionEditDialog> createState() => _QuestionEditDialogState();
}

class _QuestionEditDialogState extends State<QuestionEditDialog> {
  final QuizService _quizService = Get.find<QuizService>();

  late TextEditingController _questionController;
  late TextEditingController _emojiController;
  late TextEditingController _explanationController;
  late TextEditingController _categoryController;
  late List<TextEditingController> _optionControllers;
  late int _correctIndex;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _questionController = TextEditingController(text: widget.question.question);
    _emojiController = TextEditingController(text: widget.question.emoji);
    _explanationController =
        TextEditingController(text: widget.question.explanation);
    _categoryController = TextEditingController(text: widget.question.category);
    _correctIndex = widget.question.correctIndex;

    // 初始化选项控制器
    _optionControllers = widget.question.options
        .map((option) => TextEditingController(text: option))
        .toList();
  }

  @override
  void dispose() {
    _questionController.dispose();
    _emojiController.dispose();
    _explanationController.dispose();
    _categoryController.dispose();
    for (var controller in _optionControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  /// 保存修改
  Future<void> _save() async {
    final question = _questionController.text.trim();
    final emoji = _emojiController.text.trim();
    final explanation = _explanationController.text.trim();
    final category = _categoryController.text.trim();
    final options = _optionControllers.map((c) => c.text.trim()).toList();

    // 验证
    if (question.isEmpty) {
      ToastUtils.showWarning('请输入问题');
      return;
    }

    if (emoji.isEmpty) {
      ToastUtils.showWarning('请输入 Emoji');
      return;
    }

    if (options.any((o) => o.isEmpty)) {
      ToastUtils.showWarning('所有选项都不能为空');
      return;
    }

    if (explanation.isEmpty) {
      ToastUtils.showWarning('请输入知识点解释');
      return;
    }

    if (category.isEmpty) {
      ToastUtils.showWarning('请输入分类');
      return;
    }

    // 检查问题是否重复(排除自己)
    if (question != widget.question.question &&
        _quizService.isDuplicate(question, excludeId: widget.question.id)) {
      ToastUtils.showWarning('该问题已存在');
      return;
    }

    setState(() => _isSaving = true);

    try {
      // 更新题目信息
      widget.question.question = question;
      widget.question.emoji = emoji;
      widget.question.options = options;
      widget.question.correctIndex = _correctIndex;
      widget.question.explanation = explanation;
      widget.question.category = category;

      await _quizService.updateQuestion(widget.question);

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
      title: const Text('编辑题目'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 问题
              TextField(
                controller: _questionController,
                decoration: const InputDecoration(
                  labelText: '问题',
                  border: OutlineInputBorder(),
                ),
                enabled: !_isSaving,
                maxLines: 2,
              ),
              SizedBox(height: 16.h),

              // Emoji 和分类
              Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: TextField(
                      controller: _emojiController,
                      decoration: const InputDecoration(
                        labelText: 'Emoji',
                        hintText: '🎊',
                        border: OutlineInputBorder(),
                      ),
                      enabled: !_isSaving,
                      maxLength: 2,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _categoryController,
                      decoration: const InputDecoration(
                        labelText: '分类',
                        hintText: '习俗',
                        border: OutlineInputBorder(),
                      ),
                      enabled: !_isSaving,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16.h),

              // 选项
              const Text(
                '选项',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8.h),
              ...List.generate(_optionControllers.length, (index) {
                return Padding(
                  padding: EdgeInsets.only(bottom: 8.h),
                  child: Row(
                    children: [
                      Radio<int>(
                        value: index,
                        groupValue: _correctIndex,
                        onChanged: _isSaving
                            ? null
                            : (value) {
                                setState(() => _correctIndex = value!);
                              },
                      ),
                      Expanded(
                        child: TextField(
                          controller: _optionControllers[index],
                          decoration: InputDecoration(
                            labelText: '选项 ${index + 1}',
                            border: const OutlineInputBorder(),
                            suffixIcon: _correctIndex == index
                                ? const Icon(Icons.check_circle,
                                    color: Colors.green)
                                : null,
                          ),
                          enabled: !_isSaving,
                        ),
                      ),
                    ],
                  ),
                );
              }),
              SizedBox(height: 16.h),

              // 知识点解释
              TextField(
                controller: _explanationController,
                decoration: const InputDecoration(
                  labelText: '知识点解释',
                  border: OutlineInputBorder(),
                ),
                enabled: !_isSaving,
                maxLines: 3,
              ),
              SizedBox(height: 16.h),

              // 题目信息
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
                      '题目信息',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8.h),
                    Text('ID: ${widget.question.id}'),
                    Text('创建时间: ${_formatDate(widget.question.createdAt)}'),
                    Text('更新时间: ${_formatDate(widget.question.updatedAt)}'),
                    if (widget.question.hasImage)
                      const Text('图片: 已生成',
                          style: TextStyle(color: Colors.green)),
                  ],
                ),
              ),
            ],
          ),
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
