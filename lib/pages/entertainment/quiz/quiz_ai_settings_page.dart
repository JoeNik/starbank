import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../models/quiz_config.dart';
import '../../services/quiz_service.dart';
import '../../services/openai_service.dart';
import '../../theme/app_theme.dart';
import '../../../widgets/toast_utils.dart';
import '../../../controllers/app_mode_controller.dart';

/// 问答 AI 设置页面
class QuizAISettingsPage extends StatefulWidget {
  const QuizAISettingsPage({super.key});

  @override
  State<QuizAISettingsPage> createState() => _QuizAISettingsPageState();
}

class _QuizAISettingsPageState extends State<QuizAISettingsPage> {
  final QuizService _quizService = Get.find<QuizService>();
  final OpenAIService _openAIService = Get.find<OpenAIService>();

  late QuizConfig _config;
  late TextEditingController _imagePromptController;
  late TextEditingController _chatPromptController;

  @override
  void initState() {
    super.initState();
    _config = _quizService.config.value ?? QuizConfig();
    _imagePromptController =
        TextEditingController(text: _config.imageGenPrompt);
    _chatPromptController = TextEditingController(text: _config.chatPrompt);
  }

  @override
  void dispose() {
    _imagePromptController.dispose();
    _chatPromptController.dispose();
    super.dispose();
  }

  /// 保存配置
  Future<void> _saveConfig() async {
    _config.imageGenPrompt = _imagePromptController.text;
    _config.chatPrompt = _chatPromptController.text;

    await _quizService.updateConfig(_config);
    ToastUtils.showSuccess('保存成功');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPink,
      appBar: AppBar(
        title: const Text('问答 AI 设置'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: _saveConfig,
            icon: const Icon(Icons.save),
            label: const Text('保存'),
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
              // AI 配置选择
              _buildAIConfigSection(),

              SizedBox(height: 20.h),

              // 提示词配置
              _buildPromptSection(),

              SizedBox(height: 20.h),

              // 功能开关
              _buildFeatureSection(),

              SizedBox(height: 20.h),

              // 帮助说明
              _buildHelpSection(),
            ],
          ),
        ),
      ),
    );
  }

  /// AI 配置选择区域
  Widget _buildAIConfigSection() {
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
          Row(
            children: [
              Icon(Icons.settings, color: AppTheme.primary, size: 20.sp),
              SizedBox(width: 8.w),
              Text(
                'AI 配置选择',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textMain,
                ),
              ),
            ],
          ),
          SizedBox(height: 16.h),

          // 生图 AI 选择
          Obx(() {
            final configs = _openAIService.configs;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '生图 AI',
                  style: TextStyle(
                    fontSize: 14.sp,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 8.h),
                DropdownButtonFormField<String>(
                  value: _config.imageGenConfigId,
                  decoration: InputDecoration(
                    hintText: '请选择生图 AI 配置',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12.w,
                      vertical: 12.h,
                    ),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('未选择'),
                    ),
                    ...configs.map((config) {
                      return DropdownMenuItem<String>(
                        value: config.id,
                        child: Text(config.name),
                      );
                    }),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _config.imageGenConfigId = value;
                    });
                  },
                ),
              ],
            );
          }),

          SizedBox(height: 16.h),

          // 问答 AI 选择
          Obx(() {
            final configs = _openAIService.configs;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '问答 AI',
                  style: TextStyle(
                    fontSize: 14.sp,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 8.h),
                DropdownButtonFormField<String>(
                  value: _config.chatConfigId,
                  decoration: InputDecoration(
                    hintText: '请选择问答 AI 配置',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12.w,
                      vertical: 12.h,
                    ),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('未选择'),
                    ),
                    ...configs.map((config) {
                      return DropdownMenuItem<String>(
                        value: config.id,
                        child: Text(config.name),
                      );
                    }),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _config.chatConfigId = value;
                    });
                  },
                ),
              ],
            );
          }),

          if (_openAIService.configs.isEmpty) ...[
            SizedBox(height: 12.h),
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange, size: 20.sp),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Text(
                      '请先在 主页 → 设置 → AI设置 中添加 AI 配置',
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 提示词配置区域
  Widget _buildPromptSection() {
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
          Row(
            children: [
              Icon(Icons.edit_note, color: AppTheme.primary, size: 20.sp),
              SizedBox(width: 8.w),
              Text(
                '提示词配置',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textMain,
                ),
              ),
            ],
          ),
          SizedBox(height: 16.h),

          // 生图提示词
          Text(
            '生图提示词模板',
            style: TextStyle(
              fontSize: 14.sp,
              color: Colors.grey[700],
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8.h),
          TextField(
            controller: _imagePromptController,
            maxLines: 6,
            decoration: InputDecoration(
              hintText: '输入生图提示词模板,使用 {knowledge} 作为知识点占位符',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
              contentPadding: EdgeInsets.all(12.w),
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            '提示: 使用 {knowledge} 作为知识点占位符',
            style: TextStyle(
              fontSize: 12.sp,
              color: Colors.grey,
            ),
          ),

          SizedBox(height: 16.h),

          // 问答提示词
          Text(
            '问答提示词模板',
            style: TextStyle(
              fontSize: 14.sp,
              color: Colors.grey[700],
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8.h),
          TextField(
            controller: _chatPromptController,
            maxLines: 6,
            decoration: InputDecoration(
              hintText: '输入问答提示词模板,使用 {knowledge} 作为知识点占位符',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
              contentPadding: EdgeInsets.all(12.w),
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            '提示: 使用 {knowledge} 作为知识点占位符',
            style: TextStyle(
              fontSize: 12.sp,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  /// 功能开关区域
  Widget _buildFeatureSection() {
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
          Row(
            children: [
              Icon(Icons.toggle_on, color: AppTheme.primary, size: 20.sp),
              SizedBox(width: 8.w),
              Text(
                '功能开关',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textMain,
                ),
              ),
            ],
          ),
          SizedBox(height: 16.h),

          // 启用 AI 生成图片
          SwitchListTile(
            title: const Text('启用 AI 生成图片'),
            subtitle: const Text('为题目自动生成配图'),
            value: _config.enableImageGen,
            onChanged: (value) {
              setState(() {
                _config.enableImageGen = value;
              });
            },
            activeColor: AppTheme.primary,
          ),

          // 启用 AI 生成题目
          SwitchListTile(
            title: const Text('启用 AI 生成题目'),
            subtitle: const Text('使用 AI 自动生成问答题'),
            value: _config.enableQuestionGen,
            onChanged: (value) {
              setState(() {
                _config.enableQuestionGen = value;
              });
            },
            activeColor: AppTheme.primary,
          ),

          Divider(height: 32.h),

          // 每日限玩次数 (仅家长模式可编辑)
          ListTile(
            title: const Text('每日限玩次数'),
            subtitle: Text(_config.dailyPlayLimit == 0
                ? '不限制'
                : '每天${_config.dailyPlayLimit}次'),
            trailing: IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _showPlayLimitDialog(),
            ),
          ),
        ],
      ),
    );
  }

  /// 帮助说明区域
  Widget _buildHelpSection() {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.help_outline, color: Colors.blue, size: 20.sp),
              SizedBox(width: 8.w),
              Text(
                '使用说明',
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade900,
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Text(
            '1. AI 配置: 请先在 主页 → 设置 → AI设置 中添加 AI 提供商配置\n'
            '2. 生图 AI: 用于生成题目配图,需要支持图片生成的模型(如 DALL-E)\n'
            '3. 问答 AI: 用于生成问答题目,使用对话模型即可\n'
            '4. 提示词模板: 使用 {knowledge} 作为占位符,系统会自动替换为题目内容\n'
            '5. 批量生成时会自动控制 API 调用频率,避免超限\n'
            '6. 默认提示词已包含儿童安全要求,建议保留',
            style: TextStyle(
              fontSize: 12.sp,
              color: Colors.blue.shade900,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  /// 显示每日限玩次数设置对话框
  void _showPlayLimitDialog() {
    final modeController = Get.find<AppModeController>();

    // 检查是否是家长模式
    if (!modeController.isParentMode) {
      ToastUtils.showWarning('请先切换到家长模式');
      return;
    }

    final controller = TextEditingController(
      text:
          _config.dailyPlayLimit == 0 ? '' : _config.dailyPlayLimit.toString(),
    );

    Get.dialog(
      AlertDialog(
        title: const Text('设置每日限玩次数'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '每日次数',
                hintText: '输入0表示不限制',
                suffixText: '次',
              ),
            ),
            SizedBox(height: 12.h),
            Text(
              '设置为0表示不限制每日游玩次数',
              style: TextStyle(
                fontSize: 12.sp,
                color: Colors.grey,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final value = int.tryParse(controller.text) ?? 0;
              if (value < 0) {
                ToastUtils.showError('请输入有效的数字');
                return;
              }
              setState(() {
                _config.dailyPlayLimit = value;
              });
              Get.back();
              ToastUtils.showSuccess('设置成功');
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
