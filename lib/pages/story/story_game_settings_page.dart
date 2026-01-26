import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import '../../models/story_game_config.dart';
import '../../services/openai_service.dart';
import '../../theme/app_theme.dart';
import '../openai_settings_page.dart';

/// 故事游戏设置页面
class StoryGameSettingsPage extends StatefulWidget {
  const StoryGameSettingsPage({super.key});

  @override
  State<StoryGameSettingsPage> createState() => _StoryGameSettingsPageState();
}

class _StoryGameSettingsPageState extends State<StoryGameSettingsPage> {
  late OpenAIService _openAIService;
  late Box _configBox;
  StoryGameConfig? _config;
  bool _isLoading = true;

  // 控制器
  late TextEditingController _imagePromptController;
  late TextEditingController _visionPromptController;
  late TextEditingController _chatPromptController;
  late TextEditingController _evalPromptController;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _imagePromptController.dispose();
    _visionPromptController.dispose();
    _chatPromptController.dispose();
    _evalPromptController.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    try {
      // 初始化服务
      if (!Get.isRegistered<OpenAIService>()) {
        await Get.putAsync(() => OpenAIService().init());
      }
      _openAIService = Get.find<OpenAIService>();

      // 打开配置数据库
      _configBox = await Hive.openBox('story_game_config');

      // 加载或创建配置
      final configMap = _configBox.get('config');
      if (configMap != null) {
        _config =
            StoryGameConfig.fromJson(Map<String, dynamic>.from(configMap));
      } else {
        _config = StoryGameConfig(id: 'default');
      }

      // 初始化控制器
      _imagePromptController =
          TextEditingController(text: _config!.imageGenerationPrompt);
      _visionPromptController =
          TextEditingController(text: _config!.visionAnalysisPrompt);
      _chatPromptController =
          TextEditingController(text: _config!.chatSystemPrompt);
      _evalPromptController =
          TextEditingController(text: _config!.evaluationPrompt);

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('加载配置失败: $e');
      setState(() => _isLoading = false);
      Get.snackbar('错误', '加载配置失败: $e', snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _saveConfig() async {
    if (_config == null) return;

    // 更新 Prompt
    _config!.imageGenerationPrompt = _imagePromptController.text;
    _config!.visionAnalysisPrompt = _visionPromptController.text;
    _config!.chatSystemPrompt = _chatPromptController.text;
    _config!.evaluationPrompt = _evalPromptController.text;

    // 保存到 Hive
    await _configBox.put('config', _config!.toJson());

    Get.snackbar('成功', '配置已保存', snackPosition: SnackPosition.BOTTOM);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('故事游戏设置'),
        actions: [
          IconButton(
            onPressed: _saveConfig,
            icon: const Icon(Icons.check),
            tooltip: '保存',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 提示信息
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue, size: 20.sp),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Text(
                      '配置不同的 AI 模型来完成图像生成、分析和对话功能',
                      style: TextStyle(
                          fontSize: 13.sp, color: Colors.blue.shade700),
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 24.h),

            // 图像分析配置（必需）
            _buildSectionTitle('📸 图像分析配置', required: true),
            _buildConfigCard(
              children: [
                _buildConfigSelector(
                  label: '选择接口',
                  value: _config!.visionConfigId,
                  onChanged: (id) {
                    setState(() {
                      _config!.visionConfigId = id ?? '';
                      // 自动选择第一个模型
                      final cfg = _openAIService.configs
                          .firstWhereOrNull((c) => c.id == id);
                      if (cfg != null && cfg.models.isNotEmpty) {
                        _config!.visionModel = cfg.models.first;
                      }
                    });
                  },
                ),
                SizedBox(height: 12.h),
                _buildModelSelector(
                  label: '选择模型',
                  hint: '推荐：gpt-4o, claude-3-sonnet',
                  configId: _config!.visionConfigId,
                  value: _config!.visionModel,
                  onChanged: (model) {
                    setState(() => _config!.visionModel = model ?? '');
                  },
                ),
                SizedBox(height: 12.h),
                _buildPromptEditor(
                  label: '图像分析提示词',
                  controller: _visionPromptController,
                  hint: '引导 AI 分析图片并开始故事...',
                ),
              ],
            ),

            SizedBox(height: 24.h),

            // 对话配置
            _buildSectionTitle('💬 对话引导配置'),
            _buildConfigCard(
              children: [
                _buildConfigSelector(
                  label: '选择接口',
                  value: _config!.chatConfigId,
                  onChanged: (id) {
                    setState(() {
                      _config!.chatConfigId = id ?? '';
                      final cfg = _openAIService.configs
                          .firstWhereOrNull((c) => c.id == id);
                      if (cfg != null && cfg.models.isNotEmpty) {
                        _config!.chatModel = cfg.models.first;
                      }
                    });
                  },
                ),
                SizedBox(height: 12.h),
                _buildModelSelector(
                  label: '选择模型',
                  hint: '可选任意 LLM',
                  configId: _config!.chatConfigId,
                  value: _config!.chatModel,
                  onChanged: (model) {
                    setState(() => _config!.chatModel = model ?? '');
                  },
                ),
                SizedBox(height: 12.h),
                _buildPromptEditor(
                  label: '对话系统提示词',
                  controller: _chatPromptController,
                  hint: '引导孩子扩展故事...',
                ),
              ],
            ),

            SizedBox(height: 24.h),

            // 评价配置
            _buildSectionTitle('⭐ 故事评价配置'),
            _buildConfigCard(
              children: [
                _buildPromptEditor(
                  label: '评价提示词',
                  controller: _evalPromptController,
                  hint: '评价故事并给出分数...',
                ),
              ],
            ),

            SizedBox(height: 24.h),

            // 游戏设置
            _buildSectionTitle('🎮 游戏设置'),
            _buildConfigCard(
              children: [
                _buildNumberSetting(
                  label: '最大对话轮数',
                  value: _config!.maxRounds,
                  min: 3,
                  max: 10,
                  onChanged: (v) => setState(() => _config!.maxRounds = v),
                ),
                SizedBox(height: 12.h),
                _buildNumberSetting(
                  label: '每日游戏次数限制',
                  value: _config!.dailyLimit,
                  min: 1,
                  max: 10,
                  onChanged: (v) => setState(() => _config!.dailyLimit = v),
                ),
                SizedBox(height: 16.h),
                const Divider(),
                SizedBox(height: 8.h),
                // 星星奖励开关
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('启用星星奖励', style: TextStyle(fontSize: 14.sp)),
                  subtitle: Text(
                    _config!.enableStarReward ? '完成故事将获得星星奖励' : '仅游戏，不发放星星',
                    style: TextStyle(fontSize: 12.sp),
                  ),
                  value: _config!.enableStarReward,
                  onChanged: (v) =>
                      setState(() => _config!.enableStarReward = v),
                ),
                if (_config!.enableStarReward)
                  _buildNumberSetting(
                    label: '完成奖励星星数',
                    value: _config!.baseStars,
                    min: 1,
                    max: 10,
                    onChanged: (v) => setState(() => _config!.baseStars = v),
                  ),
              ],
            ),

            SizedBox(height: 24.h),

            // 图片源配置
            _buildSectionTitle('🖼️ 图片源配置'),
            _buildConfigCard(
              children: [
                Text(
                  '配置故事图片来源（优先级：远程API > 备用图片列表 > 内置图片）',
                  style: TextStyle(fontSize: 12.sp, color: Colors.grey),
                ),
                SizedBox(height: 12.h),
                TextFormField(
                  initialValue: _config!.remoteImageApiUrl,
                  decoration: InputDecoration(
                    labelText: '远程图片API地址（可选）',
                    hintText: 'https://api.example.com/images',
                    helperText: '返回JSON格式的图片URL列表',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                  ),
                  onChanged: (v) => _config!.remoteImageApiUrl = v,
                ),
                SizedBox(height: 16.h),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '备用图片URL列表',
                      style: TextStyle(fontSize: 13.sp, color: Colors.grey),
                    ),
                    TextButton(
                      onPressed: _editFallbackImages,
                      child: const Text('编辑'),
                    ),
                  ],
                ),
                Container(
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8.r),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Text(
                    _config!.fallbackImageUrls.isEmpty
                        ? '未配置，将使用内置图片'
                        : '已配置 ${_config!.fallbackImageUrls.length} 张图片',
                    style: TextStyle(fontSize: 12.sp),
                  ),
                ),
              ],
            ),

            SizedBox(height: 32.h),

            // 快速添加配置入口
            Center(
              child: TextButton.icon(
                onPressed: () {
                  Get.to(() => const OpenAISettingsPage())?.then((_) {
                    setState(() {});
                  });
                },
                icon: const Icon(Icons.add),
                label: const Text('管理 AI 接口配置'),
              ),
            ),

            SizedBox(height: 32.h),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title,
      {bool required = false, String? subtitle}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: AppTheme.textMain,
            ),
          ),
          if (required)
            Text(
              ' *',
              style: TextStyle(color: Colors.red, fontSize: 16.sp),
            ),
          if (subtitle != null)
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12.sp,
                color: Colors.grey,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildConfigCard({required List<Widget> children}) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  Widget _buildConfigSelector({
    required String label,
    required String value,
    required ValueChanged<String?> onChanged,
  }) {
    final configs = _openAIService.configs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 13.sp, color: Colors.grey)),
        SizedBox(height: 4.h),
        DropdownButtonFormField<String>(
          value: value.isEmpty ? null : value,
          decoration: InputDecoration(
            contentPadding:
                EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.r),
            ),
            hintText: '请选择接口',
          ),
          items: configs.map((config) {
            return DropdownMenuItem(
              value: config.id,
              child: Text(config.name),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildModelSelector({
    required String label,
    required String hint,
    required String configId,
    required String value,
    required ValueChanged<String?> onChanged,
  }) {
    final config =
        _openAIService.configs.firstWhereOrNull((c) => c.id == configId);
    final models = config?.models ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 13.sp, color: Colors.grey)),
        SizedBox(height: 4.h),
        DropdownButtonFormField<String>(
          value: models.contains(value) ? value : null,
          decoration: InputDecoration(
            contentPadding:
                EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.r),
            ),
            hintText: hint,
          ),
          isExpanded: true,
          items: models.map((model) {
            return DropdownMenuItem(
              value: model,
              child: Text(model, overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildPromptEditor({
    required String label,
    required TextEditingController controller,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 13.sp, color: Colors.grey)),
            TextButton(
              onPressed: () => _showPromptEditor(label, controller),
              child: const Text('编辑'),
            ),
          ],
        ),
        Container(
          padding: EdgeInsets.all(12.w),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8.r),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Text(
            controller.text.length > 100
                ? '${controller.text.substring(0, 100)}...'
                : controller.text,
            style: TextStyle(fontSize: 12.sp),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  void _showPromptEditor(String label, TextEditingController controller) {
    final tempController = TextEditingController(text: controller.text);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('编辑 $label'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300.h,
          child: TextField(
            controller: tempController,
            maxLines: null,
            expands: true,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.r),
              ),
              hintText: '输入提示词...',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              controller.text = tempController.text;
              Navigator.pop(ctx);
              setState(() {});
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 编辑备用图片列表
  void _editFallbackImages() {
    final tempController = TextEditingController(
      text: _config!.fallbackImageUrls.join('\n'),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑备用图片URL'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300.h,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '每行一个图片URL',
                style: TextStyle(fontSize: 12.sp, color: Colors.grey),
              ),
              SizedBox(height: 8.h),
              Expanded(
                child: TextField(
                  controller: tempController,
                  maxLines: null,
                  expands: true,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    hintText:
                        'https://example.com/image1.jpg\nhttps://example.com/image2.jpg',
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final urls = tempController.text
                  .split('\n')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
              setState(() => _config!.fallbackImageUrls = urls);
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberSetting({
    required String label,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: TextStyle(fontSize: 14.sp)),
        ),
        IconButton(
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
          color: AppTheme.primary,
        ),
        SizedBox(
          width: 40.w,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        IconButton(
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline),
          color: AppTheme.primary,
        ),
      ],
    );
  }
}
