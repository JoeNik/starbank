import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import '../../models/story_game_config.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../services/openai_service.dart';
import '../../theme/app_theme.dart';
import '../openai_settings_page.dart';

import '../../controllers/app_mode_controller.dart';
import '../../widgets/toast_utils.dart';
import '../../widgets/tts_engine_selector.dart';

/// 故事游戏设置页面
class StoryGameSettingsPage extends StatefulWidget {
  const StoryGameSettingsPage({super.key});

  @override
  State<StoryGameSettingsPage> createState() => _StoryGameSettingsPageState();
}

class _StoryGameSettingsPageState extends State<StoryGameSettingsPage> {
  late OpenAIService _openAIService;
  final AppModeController _appMode = Get.find<AppModeController>();
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
      ToastUtils.showError('加载配置失败: $e');
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

    ToastUtils.showSuccess('配置已保存');
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Obx(() {
      final isChildMode = _appMode.isChildMode;

      return Scaffold(
        appBar: AppBar(
          title: const Text('故事游戏设置'),
          actions: [
            if (!isChildMode)
              IconButton(
                onPressed: _saveConfig,
                icon: const Icon(Icons.check),
                tooltip: '保存',
              ),
          ],
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.all(16.w),
          child: AbsorbPointer(
            absorbing: isChildMode,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 儿童模式提示
                if (isChildMode)
                  Container(
                    width: double.infinity,
                    margin: EdgeInsets.only(bottom: 16.h),
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lock, color: Colors.orange, size: 20.sp),
                        SizedBox(width: 8.w),
                        Text(
                          '当前为儿童模式，设置不可修改',
                          style: TextStyle(
                              fontSize: 14.sp, color: Colors.orange.shade800),
                        ),
                      ],
                    ),
                  ),

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

                // 语音设置
                _buildSectionTitle('🗣️ 语音合成 (TTS) 设置'),
                _buildConfigCard(
                  children: [
                    const TtsEngineSelector(
                      featureKey: 'story_game',
                      title: '当前功能 TTS 引擎',
                    ),
                  ],
                ),

                SizedBox(height: 24.h),

                // 图像生成配置
                _buildSectionTitle('🎨 图像生成配置'),
                _buildConfigCard(
                  children: [
                    // 开关
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title:
                          Text('启用 AI 生图', style: TextStyle(fontSize: 14.sp)),
                      subtitle: Text(
                        _config!.enableImageGeneration
                            ? '开启后，游戏开始时将自动生成插图'
                            : '已关闭，将使用拍摄/选择的照片',
                        style: TextStyle(fontSize: 12.sp),
                      ),
                      value: _config!.enableImageGeneration,
                      onChanged: (v) =>
                          setState(() => _config!.enableImageGeneration = v),
                    ),
                    if (_config!.enableImageGeneration) ...[
                      const Divider(),
                      SizedBox(height: 12.h),
                      _buildConfigSelector(
                        label: '选择接口',
                        value: _config!.imageGenerationConfigId,
                        onChanged: (id) {
                          setState(() {
                            _config!.imageGenerationConfigId = id ?? '';
                            // 自动选择第一个模型
                            final cfg = _openAIService.configs
                                .firstWhereOrNull((c) => c.id == id);
                            if (cfg != null && cfg.models.isNotEmpty) {
                              _config!.imageGenerationModel = cfg.models.first;
                            }
                          });
                        },
                      ),
                      SizedBox(height: 12.h),
                      _buildModelSelector(
                        label: '选择模型',
                        hint: '推荐：dall-e-3',
                        configId: _config!.imageGenerationConfigId,
                        value: _config!.imageGenerationModel,
                        onChanged: (model) {
                          setState(() =>
                              _config!.imageGenerationModel = model ?? '');
                        },
                      ),
                      SizedBox(height: 12.h),
                      _buildPromptEditor(
                        label: '生图提示词',
                        controller: _imagePromptController,
                        hint: '描述想要生成的图片风格和内容...',
                      ),
                    ],
                  ],
                ),

                SizedBox(height: 24.h),
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
                        onChanged: (v) =>
                            setState(() => _config!.baseStars = v),
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
                        helperText:
                            '支持格式：["url1", "url2"] 或 {"images": ["url1"]}\n返回 JSON 列表或包含 images/data 字段的对象',
                        helperMaxLines: 3,
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

                SizedBox(height: 24.h),

                // TTS 语音播报设置
                _buildSectionTitle('🔊 语音播报设置'),
                _buildConfigCard(
                  children: [
                    Text(
                      'AI回复的语音播报参数（仅对当前故事游戏有效）',
                      style: TextStyle(fontSize: 12.sp, color: Colors.grey),
                    ),
                    SizedBox(height: 16.h),
                    // 语速
                    Row(
                      children: [
                        Expanded(
                          child: Text('语速', style: TextStyle(fontSize: 14.sp)),
                        ),
                        SizedBox(
                          width: 200.w,
                          child: Slider(
                            value: _config!.ttsRate,
                            min: 0.0,
                            max: 1.0,
                            divisions: 10,
                            label: _config!.ttsRate.toStringAsFixed(1),
                            onChanged: (v) =>
                                setState(() => _config!.ttsRate = v),
                          ),
                        ),
                        SizedBox(
                          width: 40.w,
                          child: Text(
                            _config!.ttsRate.toStringAsFixed(1),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8.h),
                    // 音量
                    Row(
                      children: [
                        Expanded(
                          child: Text('音量', style: TextStyle(fontSize: 14.sp)),
                        ),
                        SizedBox(
                          width: 200.w,
                          child: Slider(
                            value: _config!.ttsVolume,
                            min: 0.0,
                            max: 1.0,
                            divisions: 10,
                            label: _config!.ttsVolume.toStringAsFixed(1),
                            onChanged: (v) =>
                                setState(() => _config!.ttsVolume = v),
                          ),
                        ),
                        SizedBox(
                          width: 40.w,
                          child: Text(
                            _config!.ttsVolume.toStringAsFixed(1),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8.h),
                    // 音调
                    Row(
                      children: [
                        Expanded(
                          child: Text('音调', style: TextStyle(fontSize: 14.sp)),
                        ),
                        SizedBox(
                          width: 200.w,
                          child: Slider(
                            value: _config!.ttsPitch,
                            min: 0.5,
                            max: 2.0,
                            divisions: 15,
                            label: _config!.ttsPitch.toStringAsFixed(1),
                            onChanged: (v) =>
                                setState(() => _config!.ttsPitch = v),
                          ),
                        ),
                        SizedBox(
                          width: 40.w,
                          child: Text(
                            _config!.ttsPitch.toStringAsFixed(1),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
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
        ),
      );
    });
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
          height: 350.h,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '每行一个图片URL。支持格式：\n1. 直接输入URL，每行一个\n2. 导入 JSON 数组 ["url", "url"]',
                style: TextStyle(fontSize: 12.sp, color: Colors.grey),
              ),
              SizedBox(height: 8.h),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _importImagesFromUrl(tempController),
                      icon: const Icon(Icons.download, size: 16),
                      label:
                          const Text('从链接导入', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
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
                  .where((e) => e.isNotEmpty && e.startsWith('http'))
                  .toList();
              setState(() => _config!.fallbackImageUrls = urls);
              Navigator.pop(ctx);
              ToastUtils.showSuccess('已保存 ${urls.length} 张图片');
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _importImagesFromUrl(TextEditingController controller) {
    final urlController = TextEditingController();
    Get.dialog(
      AlertDialog(
        title: const Text('从链接导入'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('请输入包含图片URL列表的JSON地址', style: TextStyle(fontSize: 12.sp)),
            SizedBox(height: 8.h),
            Container(
              padding: EdgeInsets.all(8.w),
              decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4.r)),
              child: Text(
                '格式要求: ["url1", "url2", ...]',
                style: TextStyle(
                    fontSize: 11.sp,
                    fontFamily: 'monospace',
                    color: Colors.grey[800]),
              ),
            ),
            SizedBox(height: 8.h),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'http://...',
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              final url = urlController.text.trim();
              if (url.isEmpty || !url.startsWith('http')) {
                ToastUtils.showError('请输入有效的URL');
                return;
              }

              Get.dialog(const Center(child: CircularProgressIndicator()),
                  barrierDismissible: false);
              try {
                final response = await http.get(Uri.parse(url));
                Get.back(); // close loading
                Get.back(); // close input dialog

                if (response.statusCode == 200) {
                  final decoded = jsonDecode(utf8.decode(response.bodyBytes));
                  List<String> newUrls = [];
                  if (decoded is List) {
                    newUrls = decoded.map((e) => e.toString()).toList();
                  } else if (decoded is Map && decoded['images'] is List) {
                    newUrls = (decoded['images'] as List)
                        .map((e) => e.toString())
                        .toList();
                  } else {
                    throw Exception('格式不正确，需要 JSON 数组');
                  }

                  if (newUrls.isEmpty) throw Exception('未找到图片 URL');

                  // Replace existing content
                  controller.text = newUrls.join('\n');

                  ToastUtils.showSuccess('已导入 ${newUrls.length} 张图片URL',
                      title: '导入成功');
                } else {
                  throw Exception('HTTP ${response.statusCode}');
                }
              } catch (e) {
                if (Get.isDialogOpen ?? false) {
                  Get.back(); // ensure loading closed if logic failed inside
                }
                ToastUtils.showError('导入失败: $e');
              }
            },
            child: const Text('获取'),
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
