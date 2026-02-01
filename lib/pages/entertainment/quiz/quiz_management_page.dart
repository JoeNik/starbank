import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../services/quiz_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/toast_utils.dart';
import 'quiz_ai_settings_page.dart';

/// 题库管理页面
class QuizManagementPage extends StatefulWidget {
  const QuizManagementPage({super.key});

  @override
  State<QuizManagementPage> createState() => _QuizManagementPageState();
}

class _QuizManagementPageState extends State<QuizManagementPage> {
  final QuizService _quizService = Get.find<QuizService>();

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
          Text(
            '📝 题目列表',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: AppTheme.textMain,
            ),
          ),
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
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
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
                      child: Image.file(
                        File(question.imagePath!),
                        width: 48.w,
                        height: 48.w,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(Icons.broken_image,
                              color: Colors.grey, size: 24.sp);
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

          // 操作按钮
          PopupMenuButton<String>(
            onSelected: (value) => _handleQuestionAction(value, question),
            itemBuilder: (context) => [
              if (question.canGenerateImage)
                const PopupMenuItem(
                  value: 'generate',
                  child: Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 18),
                      SizedBox(width: 8),
                      Text('生成图片'),
                    ],
                  ),
                ),
              if (question.hasImage)
                const PopupMenuItem(
                  value: 'delete_image',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 18),
                      SizedBox(width: 8),
                      Text('删除图片'),
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
      case 'generate':
        await _generateImageForQuestion(question);
        break;
      case 'delete_image':
        await _deleteQuestionImage(question);
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
            ],
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
  void _exportQuestions() {
    try {
      final json = _quizService.exportQuestions();
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

    Get.dialog(
      AlertDialog(
        title: const Text('批量生成图片'),
        content: const Text('将为所有未生成图片的题目生成配图,可能需要较长时间,是否继续?'),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              Get.back();
              _showBatchGenerateProgress();
            },
            child: const Text('开始生成'),
          ),
        ],
      ),
    );
  }

  /// 显示批量生成进度
  void _showBatchGenerateProgress() {
    final RxString status = '准备中...'.obs;
    final RxInt current = 0.obs;
    final RxInt total = 0.obs;

    Get.dialog(
      WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          title: const Text('正在生成图片'),
          content: Obx(() => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    value: total.value > 0 ? current.value / total.value : 0,
                  ),
                  SizedBox(height: 16.h),
                  Text('${current.value}/${total.value}'),
                  SizedBox(height: 8.h),
                  Text(
                    status.value,
                    style: TextStyle(fontSize: 12.sp, color: Colors.grey),
                  ),
                ],
              )),
        ),
      ),
      barrierDismissible: false,
    );

    _quizService.batchGenerateImages(
      onProgress: (c, t, s) {
        current.value = c;
        total.value = t;
        status.value = s;

        if (c >= t) {
          Future.delayed(const Duration(seconds: 1), () {
            Get.back();
            ToastUtils.showSuccess('批量生成完成');
          });
        }
      },
    );
  }

  /// 为单个题目生成图片
  Future<void> _generateImageForQuestion(question) async {
    if (!_quizService.config.value!.enableImageGen) {
      ToastUtils.showWarning('请先在 AI 设置中启用图片生成功能');
      return;
    }

    try {
      Get.dialog(
        const Center(child: CircularProgressIndicator()),
        barrierDismissible: false,
      );

      await _quizService.generateImageForQuestion(question);
      Get.back();
      ToastUtils.showSuccess('图片生成成功');
    } catch (e) {
      if (Get.isDialogOpen ?? false) Get.back();
      ToastUtils.showError('生成失败: $e');
    }
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
}
