import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import '../../../data/hanzi_data.dart';
import '../../../models/hanzi_learning_config.dart';
import '../../../services/hanzi_learning_service.dart';
import '../../../services/openai_service.dart';
import '../../../theme/app_theme.dart';
import '../../../controllers/app_mode_controller.dart';
import '../../../widgets/toast_utils.dart';
import '../../openai_settings_page.dart';
import 'hanzi_library_page.dart';

/// 星海识字设置页面
/// 参考 StoryGameSettingsPage 的交互风格保持体验一致
class HanziLearningSettingsPage extends StatefulWidget {
  const HanziLearningSettingsPage({super.key});

  @override
  State<HanziLearningSettingsPage> createState() =>
      _HanziLearningSettingsPageState();
}

class _HanziLearningSettingsPageState extends State<HanziLearningSettingsPage> {
  late OpenAIService _openAIService;
  final AppModeController _appMode = Get.find<AppModeController>();
  late HanziLearningService _service;
  HanziLearningConfig? _config;
  bool _isLoading = true;

  // Prompt 编辑控制器
  late TextEditingController _promptController;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  /// 初始化数据
  Future<void> _initData() async {
    try {
      _openAIService = Get.find<OpenAIService>();
      _service = Get.find<HanziLearningService>();

      _config = _service.config.value;
      _config ??= HanziLearningConfig(id: 'default');

      // 初始化控制器
      _promptController = TextEditingController(text: _config!.aiPrompt);

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('加载配置失败: $e');
      setState(() => _isLoading = false);
      ToastUtils.showError('加载配置失败: $e');
    }
  }

  /// 保存配置
  Future<void> _saveConfig() async {
    if (_config == null) return;

    // 更新 Prompt
    _config!.aiPrompt = _promptController.text;

    // 更新到 Service
    await _service.updateAIConfig(
      chatConfigId: _config!.chatConfigId,
      chatModel: _config!.chatModel,
      aiPrompt: _config!.aiPrompt,
    );
    await _service.updateGameSettings(
      knownHanziCount: _config!.knownHanziCount,
      newHanziCount: _config!.newHanziCount,
      targetCoverageRate: _config!.targetCoverageRate,
    );

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
          title: const Text('星海识字设置'),
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
                      Icon(Icons.info_outline,
                          color: Colors.blue, size: 20.sp),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: Text(
                          '配置AI模型来生成趣味星海识字内容',
                          style: TextStyle(
                              fontSize: 13.sp, color: Colors.blue.shade700),
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 24.h),

                // ========== 字库管理 ==========
                _buildSectionTitle('📖 字库管理'),
                _buildConfigCard(
                  children: [
                    // 册别设置
                    Row(
                      children: [
                        Expanded(
                          child: Text('解锁册别',
                              style: TextStyle(fontSize: 14.sp)),
                        ),
                        DropdownButton<int>(
                          value: _config!.unlockedMaxLevel,
                          items: HanziData.allBookLevels
                              .map((level) => DropdownMenuItem(
                                    value: level,
                                    child: Text(
                                      HanziData.getLevelShortName(level),
                                      style: TextStyle(fontSize: 13.sp),
                                    ),
                                  ))
                              .toList(),
                          onChanged: (level) {
                            if (level == null) return;
                            setState(() => _config!.unlockedMaxLevel = level);
                            _service.setUnlockedMaxLevel(level);
                          },
                        ),
                      ],
                    ),
                    SizedBox(height: 12.h),
                    const Divider(),
                    SizedBox(height: 12.h),
                    // 字库信息与编辑入口
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('专属字库',
                                  style: TextStyle(fontSize: 14.sp)),
                              SizedBox(height: 4.h),
                              Text(
                                '已选 ${_config!.knownHanziList.length} 个已认识的字',
                                style: TextStyle(
                                    fontSize: 12.sp, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () async {
                            final result =
                                await Get.to(() => const HanziLibraryPage());
                            if (result == true) {
                              // 刷新页面
                              setState(() {
                                _config = _service.config.value;
                              });
                            }
                          },
                          icon: Icon(Icons.edit, size: 16.sp),
                          label: const Text('编辑字库'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF7C4DFF),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              horizontal: 16.w,
                              vertical: 8.h,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                SizedBox(height: 24.h),

                // ========== AI 内容生成配置 ==========
                _buildSectionTitle('🤖 AI 内容生成配置'),
                _buildConfigCard(
                  children: [
                    _buildConfigSelector(
                      label: '选择接口',
                      value: _config!.chatConfigId,
                      onChanged: (id) {
                        setState(() {
                          _config!.chatConfigId = id ?? '';
                          // 自动选择第一个模型
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
                      hint: '推荐：GPT-4o / Claude 3.5',
                      configId: _config!.chatConfigId,
                      value: _config!.chatModel,
                      onChanged: (model) {
                        setState(() => _config!.chatModel = model ?? '');
                      },
                    ),
                    SizedBox(height: 12.h),
                    _buildPromptEditor(
                      label: 'AI 生成提示词',
                      controller: _promptController,
                      hint: '控制AI生成内容的约束和风格...',
                    ),
                    SizedBox(height: 12.h),
                    // 给用户一个明确的提示：他们的 {stageHint} 和阶段有关
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(12.w),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8.r),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('✨ 当前应用的动态阶段提示（生成时替换至 {stageHint} ）：', 
                               style: TextStyle(fontSize: 12.sp, color: Colors.green.shade800, fontWeight: FontWeight.bold)),
                          SizedBox(height: 6.h),
                          Text(HanziData.getStageHint(_config!.unlockedMaxLevel), 
                               style: TextStyle(fontSize: 12.sp, color: Colors.green.shade700)),
                        ],
                      ),
                    ),
                  ],
                ),

                SizedBox(height: 24.h),

                // ========== 游戏参数设置 ==========
                _buildSectionTitle('🎮 游戏参数'),
                _buildConfigCard(
                  children: [
                    _buildNumberSetting(
                      label: '每次复习字数',
                      value: _config!.knownHanziCount,
                      min: 5,
                      max: 30,
                      onChanged: (v) =>
                          setState(() => _config!.knownHanziCount = v),
                    ),
                    SizedBox(height: 12.h),
                    _buildNumberSetting(
                      label: '每次新字数量',
                      value: _config!.newHanziCount,
                      min: 0,
                      max: 5,
                      onChanged: (v) =>
                          setState(() => _config!.newHanziCount = v),
                    ),
                    SizedBox(height: 16.h),
                    const Divider(),
                    SizedBox(height: 8.h),
                    // 覆盖率设置
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('目标覆盖率',
                                  style: TextStyle(fontSize: 14.sp)),
                              Text(
                                '生成文本中已知字的占比目标',
                                style: TextStyle(
                                    fontSize: 12.sp, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${(_config!.targetCoverageRate * 100).toInt()}%',
                          style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF7C4DFF),
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: _config!.targetCoverageRate,
                      min: 0.7,
                      max: 0.95,
                      divisions: 25,
                      activeColor: const Color(0xFF7C4DFF),
                      label:
                          '${(_config!.targetCoverageRate * 100).toInt()}%',
                      onChanged: (v) =>
                          setState(() => _config!.targetCoverageRate = v),
                    ),
                  ],
                ),

                SizedBox(height: 24.h),

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

  // ========== 通用UI组件（与 StoryGameSettingsPage 保持一致）==========

  /// 章节标题
  Widget _buildSectionTitle(String title, {bool required = false}) {
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
        ],
      ),
    );
  }

  /// 配置卡片容器
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

  /// 接口选择器（与 StoryGameSettingsPage 一致）
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

  /// 模型选择器（与 StoryGameSettingsPage 一致）
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

  /// Prompt 编辑器（与 StoryGameSettingsPage 一致）
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
            Text(label,
                style: TextStyle(fontSize: 13.sp, color: Colors.grey)),
            Row(
              children: [
                TextButton(
                  onPressed: () {
                    // 重置为默认 Prompt
                    controller.text = HanziLearningConfig.defaultPrompt;
                    setState(() {});
                  },
                  child: const Text('重置'),
                ),
                TextButton(
                  onPressed: () => _showPromptEditor(label, controller),
                  child: const Text('编辑'),
                ),
              ],
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

  /// 全屏 Prompt 编辑对话框
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

  /// 数字设置项（与 StoryGameSettingsPage 一致）
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
          color: const Color(0xFF7C4DFF),
        ),
        Container(
          width: 40.w,
          alignment: Alignment.center,
          child: Text(
            '$value',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF7C4DFF),
            ),
          ),
        ),
        IconButton(
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline),
          color: const Color(0xFF7C4DFF),
        ),
      ],
    );
  }
}
