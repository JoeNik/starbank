import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../../models/openai_config.dart';
import '../../../services/quiz_service.dart';
import '../../../services/quiz_management_service.dart';
import '../../../services/ai_generation_service.dart';
import '../../../services/openai_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/toast_utils.dart';
import 'quiz_ai_settings_page.dart';
import 'question_edit_dialog.dart';
import '../../../widgets/ai_generation_progress_dialog.dart';

/// 题库管理页面
class QuizManagementPage extends StatefulWidget {
  const QuizManagementPage({super.key});

  @override
  State<QuizManagementPage> createState() => _QuizManagementPageState();
}

class _QuizManagementPageState extends State<QuizManagementPage> {
  final QuizService _quizService = Get.find<QuizService>();
  final AIGenerationService _aiService = AIGenerationService();
  final OpenAIService _openAIService = Get.find<OpenAIService>();
  final QuizManagementService _quizManagementService =
      QuizManagementService.instance;

  // 批量选择状态
  bool _isBatchMode = false;
  final Set<String> _selectedQuestionIds = {};

  // 后台批量生成任务状态 (Moved to Service)
  // bool _isBatchGenerating = false;
  // final RxList<GenerationStep> _batchGenerationSteps = <GenerationStep>[].obs;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPink,
      appBar: AppBar(
        title: const Text('题库管理'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () => Get.to(() => const QuizAISettingsPage()),
            icon: const Icon(Icons.settings),
            tooltip: 'AI 设置',
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.all(16.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 题库统计
              _buildStatisticsCard(),

              SizedBox(height: 16.h),

              // 题库操作
              _buildQuestionActions(),

              SizedBox(height: 16.h),

              // 图片管理
              _buildImageActions(),

              SizedBox(height: 16.h),

              // 题目列表
              _buildQuestionList(),
            ],
          ),
        ),
      ),
    );
  }

  /// 题库统计卡片
  Widget _buildStatisticsCard() {
    return Obx(() {
      final total = _quizService.questions.length;
      final withImage = _quizService.questions.where((q) => q.hasImage).length;
      final generating =
          _quizService.questions.where((q) => q.isGeneratingImage).length;

      return Container(
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF6B9D), Color(0xFFFF8E53)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16.r),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF6B9D).withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '📊 题库统计',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 16.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('总题数', total.toString(), Icons.quiz),
                _buildStatItem('有图片', withImage.toString(), Icons.image),
                _buildStatItem(
                    '生成中', generating.toString(), Icons.hourglass_empty),
              ],
            ),
          ],
        ),
      );
    });
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 32.sp),
        SizedBox(height: 8.h),
        Text(
          value,
          style: TextStyle(
            fontSize: 24.sp,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        SizedBox(height: 4.h),
        Text(
          label,
          style: TextStyle(
            fontSize: 12.sp,
            color: Colors.white.withOpacity(0.9),
          ),
        ),
      ],
    );
  }

  /// 题库操作
  Widget _buildQuestionActions() {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '📚 题库操作',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: AppTheme.textMain,
            ),
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  icon: Icons.upload_file,
                  label: '导入题库',
                  color: Colors.blue,
                  onTap: _showImportDialog,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.download,
                  label: '导出题库',
                  color: Colors.green,
                  onTap: _exportQuestions,
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  icon: Icons.restore,
                  label: '恢复默认',
                  color: Colors.orange,
                  onTap: _restoreDefault,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.delete_sweep,
                  label: '清空题库',
                  color: Colors.red,
                  onTap: _clearQuestions,
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          // AI 生成题目
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  icon: Icons.auto_awesome,
                  label: 'AI 生成题目',
                  color: const Color(0xFF9C27B0),
                  onTap: _showAIGenerateDialog,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 图片管理
  Widget _buildImageActions() {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '🎨 图片管理',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: AppTheme.textMain,
            ),
          ),
          SizedBox(height: 12.h),

          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  icon: Icons.auto_awesome,
                  label: '批量生成',
                  color: Colors.purple,
                  onTap: _batchGenerateImages,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.cleaning_services,
                  label: '清空缓存',
                  color: Colors.grey,
                  onTap: _clearImageCache,
                ),
              ),
            ],
          ),

          SizedBox(height: 12.h),

          // 缓存大小显示
          FutureBuilder<int>(
            future: _quizService.getImageCacheSize(),
            builder: (context, snapshot) {
              final size = snapshot.data ?? 0;
              final sizeStr = (size / 1024 / 1024).toStringAsFixed(2);
              return Text(
                '图片缓存: $sizeStr MB',
                style: TextStyle(
                  fontSize: 12.sp,
                  color: Colors.grey,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18.sp),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(vertical: 12.h),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.r),
        ),
      ),
    );
  }

  /// 题目列表
  Widget _buildQuestionList() {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题和批量操作按钮
          Row(
            children: [
              Text(
                '📝 题目列表',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textMain,
                ),
              ),
              const Spacer(),
              // 查看后台生成进度按钮
              Obx(() => _aiService.isTaskRunning.value
                  ? Container(
                      margin: EdgeInsets.only(right: 8.w),
                      child: ElevatedButton.icon(
                        onPressed: _showBatchGenerationProgress,
                        icon: const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        label: const Text('查看进度'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF9C27B0),
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            horizontal: 12.w,
                            vertical: 8.h,
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink()),
              if (!_isBatchMode)
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _isBatchMode = true;
                      _selectedQuestionIds.clear();
                    });
                  },
                  icon: const Icon(Icons.checklist, size: 18),
                  label: const Text('批量操作'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                  ),
                ),
            ],
          ),

          // 批量操作工具栏
          if (_isBatchMode) ...[
            SizedBox(height: 8.h),
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Row(
                children: [
                  Text(
                    '已选择 ${_selectedQuestionIds.length} 个题目',
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.primary,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedQuestionIds.clear();
                        _selectedQuestionIds.addAll(
                          _quizService.questions.map((q) => q.id),
                        );
                      });
                    },
                    child: const Text('全选'),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedQuestionIds.clear();
                      });
                    },
                    child: const Text('取消选择'),
                  ),
                  const Spacer(), // Optimize space: use spacer to push close button to far right
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _isBatchMode = false;
                        _selectedQuestionIds.clear();
                      });
                    },
                    icon: const Icon(Icons.close),
                    tooltip: '退出批量模式',
                  ),
                ],
              ),
            ),
          ],

          SizedBox(height: 12.h),
          Obx(() {
            if (_quizService.questions.isEmpty) {
              return Center(
                child: Padding(
                  padding: EdgeInsets.all(32.w),
                  child: Text(
                    '暂无题目',
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: Colors.grey,
                    ),
                  ),
                ),
              );
            }

            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _quizService.questions.length,
              itemBuilder: (context, index) {
                final question = _quizService.questions[index];
                return _buildQuestionItem(question);
              },
            );
          }),
        ],
      ),
    );
  }

  Widget _buildQuestionItem(question) {
    final isSelected = _selectedQuestionIds.contains(question.id);

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: isSelected
            ? AppTheme.primary.withOpacity(0.1)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: isSelected ? AppTheme.primary : Colors.grey.shade200,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          // 批量选择复选框
          if (_isBatchMode) ...[
            Checkbox(
              value: isSelected,
              onChanged: (value) {
                setState(() {
                  if (value == true) {
                    _selectedQuestionIds.add(question.id);
                  } else {
                    _selectedQuestionIds.remove(question.id);
                  }
                });
              },
              activeColor: AppTheme.primary,
            ),
            SizedBox(width: 8.w),
          ],

          // 图片状态
          Container(
            width: 48.w,
            height: 48.w,
            decoration: BoxDecoration(
              color: _getImageStatusColor(question),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Center(
              child: question.hasImage && question.imagePath != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8.r),
                      child: Builder(
                        builder: (context) {
                          final path = question.imagePath!;
                          if (kIsWeb) {
                            if (path.startsWith('data:image')) {
                              try {
                                final base64Data = path.split(',')[1];
                                final bytes = base64Decode(base64Data);
                                return Image.memory(
                                  bytes,
                                  width: 48.w,
                                  height: 48.w,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Icon(
                                      Icons.broken_image,
                                      color: Colors.grey,
                                      size: 24.sp),
                                );
                              } catch (e) {
                                return Icon(Icons.broken_image,
                                    color: Colors.grey, size: 24.sp);
                              }
                            } else {
                              return Image.network(
                                path,
                                width: 48.w,
                                height: 48.w,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Icon(
                                    Icons.broken_image,
                                    color: Colors.grey,
                                    size: 24.sp),
                              );
                            }
                          }
                          // Mobile/Desktop
                          return Image.file(
                            File(path),
                            width: 48.w,
                            height: 48.w,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(Icons.broken_image,
                                  color: Colors.grey, size: 24.sp);
                            },
                          );
                        },
                      ),
                    )
                  : Icon(
                      _getImageStatusIcon(question),
                      color: Colors.white,
                      size: 24.sp,
                    ),
            ),
          ),
          SizedBox(width: 12.w),

          // 题目信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  question.question,
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMain,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 4.h),
                Text(
                  '分类: ${question.category}',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),

          // 生成图片按钮(始终显示)
          Padding(
            padding: EdgeInsets.only(right: 8.w),
            child: IconButton(
              onPressed: () => _generateImageForQuestion(question),
              icon: Icon(
                Icons.auto_awesome,
                color: const Color(0xFF9C27B0),
                size: 20.sp,
              ),
              tooltip: '生成图片',
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF9C27B0).withOpacity(0.1),
                padding: EdgeInsets.all(8.w),
                minimumSize: Size(36.w, 36.w),
              ),
            ),
          ),

          // 操作按钮
          PopupMenuButton<String>(
            onSelected: (value) => _handleQuestionAction(value, question),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit, size: 18),
                    SizedBox(width: 8),
                    Text('编辑'),
                  ],
                ),
              ),
              if (question.hasImage)
                const PopupMenuItem(
                  value: 'delete_image',
                  child: Row(
                    children: [
                      Icon(Icons.image_not_supported, size: 18),
                      SizedBox(width: 8),
                      Text('删除图片'),
                    ],
                  ),
                ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, size: 18, color: Colors.red),
                    SizedBox(width: 8),
                    Text('删除题目', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getImageStatusColor(question) {
    if (question.hasImage) return Colors.green;
    if (question.isGeneratingImage) return Colors.orange;
    if (question.imageStatus == 'failed') return Colors.red;
    return Colors.grey;
  }

  IconData _getImageStatusIcon(question) {
    if (question.isGeneratingImage) return Icons.hourglass_empty;
    if (question.imageStatus == 'failed') return Icons.error;
    return Icons.image_not_supported;
  }

  /// 处理题目操作
  void _handleQuestionAction(String action, question) async {
    switch (action) {
      case 'edit':
        await _editQuestion(question);
        break;
      case 'generate':
        await _generateImageForQuestion(question);
        break;
      case 'delete_image':
        await _deleteQuestionImage(question);
        break;
      case 'delete':
        await _deleteQuestion(question);
        break;
    }
  }

  /// 导入题库
  void _showImportDialog() {
    final controller = TextEditingController();

    Get.dialog(
      AlertDialog(
        title: const Text('导入题库'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '支持 JSON 格式或 URL',
                  style: TextStyle(fontSize: 12.sp, color: Colors.grey),
                ),
                SizedBox(height: 8.h),
                TextField(
                  controller: controller,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '粘贴 JSON 内容或 http://... 链接',
                  ),
                ),
                SizedBox(height: 12.h),
                // 格式说明
                Container(
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8.r),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'JSON 格式示例:',
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade900,
                        ),
                      ),
                      SizedBox(height: 8.h),
                      Text(
                        '[\n'
                        '  {\n'
                        '    "question": "问题文本",\n'
                        '    "emoji": "🧧",\n'
                        '    "options": ["选项1", "选项2", "选项3", "选项4"],\n'
                        '    "correctIndex": 0,\n'
                        '    "explanation": "知识点解释",\n'
                        '    "category": "分类"\n'
                        '  }\n'
                        ']',
                        style: TextStyle(
                          fontSize: 10.sp,
                          fontFamily: 'monospace',
                          color: Colors.blue.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => _handleImport(controller.text),
            child: const Text('导入'),
          ),
        ],
      ),
    );
  }

  /// 处理导入
  Future<void> _handleImport(String input) async {
    if (input.trim().isEmpty) {
      ToastUtils.showWarning('请输入内容');
      return;
    }

    String jsonStr = input;

    // 检查是否是 URL
    if (input.trim().startsWith('http')) {
      try {
        Get.dialog(
          const Center(child: CircularProgressIndicator()),
          barrierDismissible: false,
        );

        final response = await http.get(Uri.parse(input.trim()));
        Get.back();

        if (response.statusCode == 200) {
          jsonStr = utf8.decode(response.bodyBytes);
        } else {
          throw Exception('HTTP ${response.statusCode}');
        }
      } catch (e) {
        if (Get.isDialogOpen ?? false) Get.back();
        ToastUtils.showError('下载失败: $e');
        return;
      }
    }

    try {
      await _quizService.importQuestions(jsonStr);
      Get.back();
      ToastUtils.showSuccess('导入成功');
    } catch (e) {
      ToastUtils.showError('导入失败: $e');
    }
  }

  /// 导出题库
  Future<void> _exportQuestions() async {
    try {
      final json = await _quizService.exportQuestions();
      // 这里可以保存到文件或复制到剪贴板
      Get.dialog(
        AlertDialog(
          title: const Text('导出题库'),
          content: SingleChildScrollView(
            child: SelectableText(json),
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (e) {
      ToastUtils.showError('导出失败: $e');
    }
  }

  /// 恢复默认题库
  void _restoreDefault() {
    Get.dialog(
      AlertDialog(
        title: const Text('确认恢复'),
        content: const Text('将清空当前题库并恢复为默认题库,此操作不可撤销!'),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              Get.back();
              try {
                await _quizService.restoreDefaultQuestions();
                ToastUtils.showSuccess('恢复成功');
              } catch (e) {
                ToastUtils.showError('恢复失败: $e');
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  /// 清空题库
  void _clearQuestions() {
    Get.dialog(
      AlertDialog(
        title: const Text('确认清空'),
        content: const Text('将清空所有题目,此操作不可撤销!'),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              Get.back();
              try {
                await _quizService.clearQuestions();
                ToastUtils.showSuccess('清空成功');
              } catch (e) {
                ToastUtils.showError('清空失败: $e');
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  /// 批量生成图片
  void _batchGenerateImages() async {
    if (!_quizService.config.value!.enableImageGen) {
      ToastUtils.showWarning('请先在 AI 设置中启用图片生成功能');
      return;
    }

    if (!_isBatchMode) {
      setState(() {
        _isBatchMode = true;
        _selectedQuestionIds.clear();
      });
      ToastUtils.showInfo('已进入批量模式，请勾选需要生成图片的题目，再次点击按钮开始生成');
      return;
    }

    if (_selectedQuestionIds.isEmpty) {
      ToastUtils.showWarning('请先选择至少一个题目');
      return;
    }

    // 确认对话框
    Get.dialog(
      AlertDialog(
        title: const Text('确认生成'),
        content: Text('将为选中的 ${_selectedQuestionIds.length} 个题目生成图片，是否继续?'),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              Get.back();
              // 调用现有的选中生成逻辑
              _batchGenerateImagesForSelected();
            },
            child: const Text('开始生成'),
          ),
        ],
      ),
    );
  }

  /// 为单个题目生成图片
  Future<void> _generateImageForQuestion(question) async {
    try {
      // 检查OpenAI配置
      if (_openAIService.configs.isEmpty) {
        ToastUtils.showWarning('请先配置OpenAI接口');
        return;
      }

      // 获取配置（优先使用QuizConfig中的图片生成配置）
      final quizConfig = _quizService.config.value;
      if (quizConfig == null || !quizConfig.enableImageGen) {
        ToastUtils.showWarning('未启用图片生成功能');
        return;
      }

      final imageGenConfig = _openAIService.configs
          .firstWhereOrNull((c) => c.id == quizConfig.imageGenConfigId);
      if (imageGenConfig == null) {
        ToastUtils.showWarning('未配置生图AI');
        return;
      }

      // 显示加载对话框
      Get.dialog(
        AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              SizedBox(height: 16.h),
              const Text("正在生成图片提示词...", style: TextStyle(fontSize: 16)),
              SizedBox(height: 8.h),
              Text(
                "生成过程可能需要 1-2 分钟，请耐心等待",
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        barrierDismissible: false,
      );

      // 构建知识点
      final knowledge =
          '${question.question}\n答案: ${question.options[question.correctIndex]}\n解释: ${question.explanation}';
      final userPrompt =
          quizConfig.imageGenPrompt.replaceAll('{knowledge}', knowledge);

      // 生成图片提示词
      final imagePrompt = await _openAIService.chat(
        systemPrompt:
            '你是一个专业的儿童插画提示词生成专家。请根据用户提供的内容生成适合 DALL-E 或 Stable Diffusion 的英文提示词。\n\n'
            '严格要求:\n'
            '1. 必须使用可爱、卡通、儿童插画风格\n'
            '2. 色彩明亮温暖,画面简洁清晰\n'
            '3. 严格禁止任何暴力、恐怖、成人或不适合儿童的内容\n'
            '4. 使用圆润可爱的造型,避免尖锐或恐怖元素\n'
            '5. 符合中国传统新年文化,展现节日喜庆氛围\n'
            '6. 适合3-8岁儿童观看\n\n'
            '只返回英文提示词本身,不要有其他说明。提示词中应包含: cute, cartoon, children illustration, colorful, warm, simple, Chinese New Year 等关键词。',
        userMessage: userPrompt,
        config: imageGenConfig,
      );

      debugPrint('生成的图片提示词: $imagePrompt');

      // 更新对话框提示
      if (Get.isDialogOpen ?? false) Get.back();
      Get.dialog(
        AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              SizedBox(height: 16.h),
              const Text("正在生成图片...", style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
        barrierDismissible: false,
      );

      // 直接调用生图API
      final imageUrls = await _openAIService.generateImages(
        prompt: imagePrompt,
        n: 1,
        config: imageGenConfig,
        model: quizConfig.imageGenModel,
      );

      if (imageUrls.isEmpty) {
        throw Exception('未能生成图片');
      }

      // 更新题目对象
      question.imagePath = imageUrls.first;
      question.imageStatus = 'success';
      question.imageError = null;
      question.updatedAt = DateTime.now();
      await question.save();
      _quizService.questions.refresh();

      // 关闭加载对话框
      if (Get.isDialogOpen ?? false) Get.back();

      // 刷新界面
      setState(() {});

      ToastUtils.showSuccess('图片生成成功!');
    } catch (e) {
      // 关闭加载对话框
      if (Get.isDialogOpen ?? false) Get.back();

      // 显示错误提示
      ToastUtils.showError('生成失败: $e');

      debugPrint('生成图片失败: $e');
    }
  }

  /// 批量为选中的题目生成图片（后台执行）
  Future<void> _batchGenerateImagesForSelected() async {
    if (_selectedQuestionIds.isEmpty) {
      ToastUtils.showWarning('请先选择题目');
      return;
    }

    if (_aiService.isTaskRunning.value) {
      ToastUtils.showInfo('已有批量生成任务正在进行中');
      _showBatchGenerationProgress();
      return;
    }

    // 获取选中的题目对象
    final selectedQuestions = _quizService.questions
        .where((q) => _selectedQuestionIds.contains(q.id))
        .toList();

    // 检查配置
    final quizConfig = _quizService.config.value;
    if (quizConfig == null || !quizConfig.enableImageGen) {
      ToastUtils.showWarning('未启用图片生成功能');
      return;
    }

    final imageGenConfig = _openAIService.configs
        .firstWhereOrNull((c) => c.id == quizConfig.imageGenConfigId);
    if (imageGenConfig == null) {
      ToastUtils.showWarning('未配置生图AI');
      return;
    }

    // 标记为正在生成
    setState(() {
      _isBatchMode = false; // 退出批量选择模式
      _selectedQuestionIds.clear();
    });

    // 显示提示并打开进度对话框
    ToastUtils.showSuccess('批量生成任务已启动，可在后台运行');
    _showBatchGenerationProgress();

    // 在后台执行生成任务
    _aiService.startBatchQuizImageGenerationTask(
      questions: selectedQuestions,
      imageGenConfig: imageGenConfig,
      imageGenModel: quizConfig.imageGenModel,
      promptTemplate: quizConfig.imageGenPrompt,
    );
  }

  /// 显示批量生成进度对话框
  void _showBatchGenerationProgress() {
    if (_aiService.taskSteps.isEmpty) {
      ToastUtils.showInfo('暂无批量生成任务');
      return;
    }

    AIGenerationProgressDialog.show(
      steps: _aiService.taskSteps,
      onClose: () => Get.back(),
    );
  }

  /// 删除题目图片
  Future<void> _deleteQuestionImage(question) async {
    try {
      await _quizService.deleteQuestionImage(question);
      ToastUtils.showSuccess('图片已删除');
    } catch (e) {
      ToastUtils.showError('删除失败: $e');
    }
  }

  /// 清空图片缓存
  void _clearImageCache() {
    Get.dialog(
      AlertDialog(
        title: const Text('确认清空'),
        content: const Text('将清空所有题目的图片缓存,此操作不可撤销!'),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              Get.back();
              try {
                await _quizService.clearImageCache();
                ToastUtils.showSuccess('缓存已清空');
              } catch (e) {
                ToastUtils.showError('清空失败: $e');
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  /// 编辑题目
  Future<void> _editQuestion(question) async {
    final result = await Get.dialog<bool>(
      QuestionEditDialog(question: question),
    );

    if (result == true) {
      setState(() {});
    }
  }

  /// 删除题目
  Future<void> _deleteQuestion(question) async {
    Get.dialog(
      AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除题目"${question.question}"吗?'),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              Get.back();
              try {
                await _quizManagementService.deleteQuestion(question.id);
                ToastUtils.showSuccess('删除成功');
              } catch (e) {
                ToastUtils.showError('删除失败: $e');
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  /// 显示 AI 生成对话框
  Future<void> _showAIGenerateDialog() async {
    final configs = _openAIService.configs;
    if (configs.isEmpty) {
      ToastUtils.showWarning('请先在 AI 设置中配置 OpenAI');
      return;
    }

    // 初始化配置
    final quizConfig = _quizService.config.value;
    OpenAIConfig? selectedConfig;

    // 1. 尝试使用问答设置中的配置
    if (quizConfig?.chatConfigId != null) {
      try {
        selectedConfig =
            configs.firstWhere((c) => c.id == quizConfig!.chatConfigId);
      } catch (_) {}
    }
    // 2. 尝试使用全局当前配置
    if (selectedConfig == null) {
      selectedConfig = _openAIService.currentConfig.value;
    }
    // 3. 默认使用第一个
    if (selectedConfig == null && configs.isNotEmpty) {
      selectedConfig = configs.first;
    }

    // 初始化模型
    String? selectedModel = quizConfig?.chatModel;
    if (selectedModel == null || selectedModel.isEmpty) {
      selectedModel = selectedConfig?.selectedModel;
    }

    // 确保模型在当前配置中存在
    if (selectedConfig != null && selectedModel != null) {
      if (!selectedConfig.models.contains(selectedModel)) {
        selectedModel = null;
      }
    }
    // 如果没有选中模型，默认选推荐的或第一个
    if (selectedModel == null &&
        selectedConfig != null &&
        selectedConfig.models.isNotEmpty) {
      // try recommended
      try {
        selectedModel = selectedConfig.models
            .firstWhere((m) => m.toLowerCase().contains('gpt-4'));
      } catch (_) {
        try {
          selectedModel = selectedConfig.models
              .firstWhere((m) => m.toLowerCase().contains('claude'));
        } catch (_) {
          selectedModel = selectedConfig.models.first;
        }
      }
    }

    // Check running task
    if (_aiService.isTaskRunning.value) {
      ToastUtils.showInfo('已有生成任务正在进行中');
      _showBatchGenerationProgress();
      return;
    }

    // Initialize state
    // ... config initialization code remains same ...

    int count = 1;
    String category = '';
    TextEditingController promptController = TextEditingController();
    bool isPromptModified = false;

    String getPrompt(int c, String cat) {
      return '''请生成 $c 道关于中国新年的问答题。

要求:
1. ${cat.isNotEmpty ? '题目分类: $cat' : '分类可以是习俗、美食、传说、文化等'}
2. 每题包含: 问题、emoji、4个选项、正确答案索引(0-3)、知识点解释
3. 难度适合 3-8 岁儿童
4. 知识点解释要简单易懂,有教育意义
5. 选项要有一定迷惑性,但不要太难

返回格式(JSON数组):
[
{
  "id": "唯一标识(使用拼音_时间戳)",
  "question": "问题文本",
  "emoji": "🎊",
  "options": ["选项1", "选项2", "选项3", "选项4"],
  "correctIndex": 0,
  "explanation": "知识点解释",
  "category": "${cat.isNotEmpty ? cat : 'general'}"
}
]

请直接返回 JSON 数组,不要添加任何解释文字。''';
    }

    // Initialize prompt
    promptController.text = getPrompt(count, category);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('AI 生成题目'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('生成数量'),
                Slider(
                  value: count.toDouble(),
                  min: 1,
                  max: 3,
                  divisions: 2,
                  label: count.toString(),
                  onChanged: (value) {
                    setDialogState(() {
                      count = value.toInt();
                      if (!isPromptModified) {
                        promptController.text = getPrompt(count, category);
                      }
                    });
                  },
                ),
                Text('$count 道题目'),
                SizedBox(height: 16.h),

                // 接口选择
                DropdownButtonFormField<OpenAIConfig>(
                  decoration: const InputDecoration(
                    labelText: '选择接口',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  ),
                  value: selectedConfig,
                  items: configs
                      .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text(c.name,
                                style: TextStyle(fontSize: 14.sp),
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (val) {
                    if (val == null) return;
                    setDialogState(() {
                      selectedConfig = val;
                      // Reset model
                      selectedModel = null;
                      if (selectedConfig!.models.isNotEmpty) {
                        // try recommended
                        try {
                          selectedModel = selectedConfig!.models.firstWhere(
                              (m) => m.toLowerCase().contains('gpt-4'));
                        } catch (_) {
                          selectedModel = selectedConfig!.models.first;
                        }
                      }
                    });
                  },
                  isExpanded: true,
                ),
                SizedBox(height: 16.h),

                // 模型选择
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: '选择模型',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  ),
                  value: selectedModel,
                  items: (selectedConfig?.models ?? [])
                      .map((m) => DropdownMenuItem(
                            value: m,
                            child: Text(m,
                                style: TextStyle(fontSize: 14.sp),
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (val) => setDialogState(() => selectedModel = val),
                  isExpanded: true,
                ),

                SizedBox(height: 16.h),
                TextField(
                  decoration: const InputDecoration(
                    labelText: '题目分类(可选)',
                    hintText: '例如:习俗、美食、传说',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    category = value;
                    if (!isPromptModified) {
                      // Update default prompt (no setState needed for controller update, but category var needs to be current)
                      promptController.text = getPrompt(count, category);
                    }
                  },
                ),

                SizedBox(height: 16.h),
                TextField(
                  controller: promptController,
                  decoration: InputDecoration(
                    labelText: '自定义 Prompt (可选)',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.copy),
                      onPressed: () {
                        Clipboard.setData(
                            ClipboardData(text: promptController.text));
                        ToastUtils.showSuccess('已复制 Prompt');
                      },
                      tooltip: '复制 Prompt',
                    ),
                    hintText: '完全覆盖默认 Prompt，需小心使用',
                    border: OutlineInputBorder(),
                    helperText: '如果不填则使用默认模板',
                  ),
                  maxLines: 8,
                  style: TextStyle(fontSize: 12.sp),
                  onChanged: (value) => isPromptModified = true,
                ),

                SizedBox(height: 16.h),
                const Text(
                  '提示:AI 将生成适合儿童的新年知识问答题,重复的题目会自动跳过。',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                // 1. 关闭配置对话框
                Get.back();

                try {
                  // Save config
                  if (selectedConfig != null) {
                    final currentCfg = _quizService.config.value;
                    if (currentCfg != null) {
                      currentCfg.chatConfigId = selectedConfig!.id;
                      currentCfg.chatModel = selectedModel;
                      await _quizService.updateConfig(currentCfg);
                    }
                  }

                  // 2. 显示进度对话框 (Prior to starting, or rely on service to update)
                  // It's better to show it immediately so user knows something is happening.
                  // Since we are about to call startQuizGenerationTask which clears steps,
                  // we should call it after start?
                  // Best flow:
                  // Call start -> Service init steps -> Show Dialog (which observes service steps)

                  // 3. Start Task
                  await _aiService.startQuizGenerationTask(
                    count: count,
                    category: category.isEmpty ? null : category,
                    customPrompt: promptController.text.isEmpty
                        ? null
                        : promptController.text,
                    config: selectedConfig,
                    model: selectedModel,
                  );

                  // 4. Show Progress
                  _showBatchGenerationProgress();
                } catch (e) {
                  ToastUtils.showError('启动任务失败: $e');
                }
              },
              child: const Text('开始生成'),
            ),
          ],
        ),
      ),
    );
  }
}
