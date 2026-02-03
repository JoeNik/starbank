import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import '../../../models/new_year_story.dart';
import '../../../models/openai_config.dart';
import '../../../services/story_management_service.dart';
import '../../../services/ai_generation_service.dart';
import '../../../services/openai_service.dart';
import '../../../widgets/toast_utils.dart';
import '../../../services/quiz_service.dart';

import 'story_edit_dialog.dart';
import '../../../widgets/ai_generation_progress_dialog.dart';

/// 故事管理页面
class StoryManagementPage extends StatefulWidget {
  const StoryManagementPage({super.key});

  @override
  State<StoryManagementPage> createState() => _StoryManagementPageState();
}

class _StoryManagementPageState extends State<StoryManagementPage> {
  final StoryManagementService _storyService = StoryManagementService.instance;
  final AIGenerationService _aiService = AIGenerationService();
  final OpenAIService _openAIService = Get.find<OpenAIService>();
  final QuizService _quizService =
      Get.find<QuizService>(); // Add QuizService to access AI Settings

  // 选中的故事 ID 列表
  final Set<String> _selectedIds = {};

  // 是否处于选择模式
  bool _isSelectionMode = false;

  // 是否正在加载
  bool _isLoading = false;

  // 后台批量生成任务状态 (Moved to Service)
  // bool _isBatchGenerating = false;
  // final RxList<GenerationStep> _batchGenerationSteps = <GenerationStep>[].obs;

  @override
  void initState() {
    super.initState();
    _initService();
  }

  /// 初始化服务
  Future<void> _initService() async {
    setState(() => _isLoading = true);
    try {
      await _storyService.init();
    } catch (e) {
      ToastUtils.showError('初始化失败: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// 切换选择模式
  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedIds.clear();
      }
    });
  }

  /// 切换故事选中状态
  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  /// 全选/取消全选
  void _toggleSelectAll() {
    setState(() {
      if (_selectedIds.length == _storyService.storyCount) {
        _selectedIds.clear();
      } else {
        _selectedIds.clear();
        _selectedIds.addAll(_storyService.getAllStories().map((s) => s.id));
      }
    });
  }

  /// 删除选中的故事
  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) {
      ToastUtils.showWarning('请先选择要删除的故事');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除选中的 ${_selectedIds.length} 个故事吗?此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _storyService.deleteStories(_selectedIds.toList());
        ToastUtils.showSuccess('已删除 ${_selectedIds.length} 个故事');
        setState(() {
          _selectedIds.clear();
          _isSelectionMode = false;
        });
      } catch (e) {
        ToastUtils.showError('删除失败: $e');
      }
    }
  }

  /// 删除单个故事
  Future<void> _deleteStory(NewYearStory story) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除故事"${story.title}"吗?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _storyService.deleteStory(story.id);
        ToastUtils.showSuccess('已删除故事');
        setState(() {});
      } catch (e) {
        ToastUtils.showError('删除失败: $e');
      }
    }
  }

  /// 编辑故事
  Future<void> _editStory(NewYearStory story) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StoryEditDialog(story: story),
    );

    if (result == true) {
      setState(() {});
    }
  }

  /// 显示 AI 生成对话框
  Future<void> _showAIGenerateDialog() async {
    final configs = _openAIService.configs;
    if (configs.isEmpty) {
      ToastUtils.showWarning('请先在设置中配置 OpenAI');
      return;
    }

    // Check running task
    if (_aiService.isTaskRunning.value) {
      ToastUtils.showInfo('已有生成任务正在进行中');
      _showBatchGenerationProgress();
      return;
    }

    // 初始化状态: Story Config
    final quizConfig = _quizService.config.value;

    OpenAIConfig? textConfig;
    if (quizConfig?.chatConfigId != null) {
      textConfig =
          configs.firstWhereOrNull((c) => c.id == quizConfig!.chatConfigId);
    }
    // Fallback if not set or not found
    textConfig ??= _openAIService.currentConfig.value ?? configs.first;

    String? textModel = quizConfig?.chatModel;
    // Check if model valid for config
    if (textConfig != null &&
        (textModel == null || !textConfig.models.contains(textModel))) {
      textModel = textConfig.models.isNotEmpty ? textConfig.models.first : null;
    }

    // 初始化状态: Image Config
    OpenAIConfig? imageConfig;
    if (quizConfig?.imageGenConfigId != null) {
      imageConfig =
          configs.firstWhereOrNull((c) => c.id == quizConfig!.imageGenConfigId);
    }
    imageConfig ??= _openAIService.currentConfig.value ?? configs.first;

    String? imageModel = quizConfig?.imageGenModel;
    if (imageConfig != null &&
        (imageModel == null || !imageConfig.models.contains(imageModel))) {
      // Default to dall-e-3 or first
      try {
        imageModel = imageConfig.models
            .firstWhere((m) => m.toLowerCase().contains('dall-e-3'));
      } catch (_) {
        imageModel =
            imageConfig.models.isNotEmpty ? imageConfig.models.first : null;
      }
    }

    bool enableImageGen = true;
    int count = 1;
    String theme = '';
    String customPrompt = '';

    // 添加 TextEditingController
    final TextEditingController _promptController = TextEditingController();

    // 获取默认 Prompt 的函数
    String getDefaultPrompt(int c, String t) {
      return '''请生成 $c 个关于中国传统春节习俗及其由来的科普故事，适合儿童阅读。

重点：不要生成虚构的童话故事，而是要以生动有趣的方式讲解真实的民俗知识（如：为什么过年要吃饺子？春联的由来？压岁钱的寓意？）。

要求:
1. ${t.isNotEmpty ? '故事主题: $t' : '主题必须围绕春节传统习俗的由来、传说或具体礼仪（例如：年兽的传说、贴福字的由来、拜年的礼仪、元宵节的习俗等）'}
2. 每个故事包含 5-7 个页面
3. 每页包含: text(展示文本，简练有趣)、emoji(相关表情)、tts(口语化播报，语气亲切，适合讲给孩子听)
4. 至少包含 1 个互动问题，考察孩子对刚才科普知识的理解，问题包含: text(问题)、options(3个选项数组)、correctIndex(正确答案索引0-2)
5. 内容必须准确、有教育意义，弘扬传统文化
6. 时长控制在 1-2 分钟

返回格式(JSON数组):
[
{
  "id": "唯一标识(使用拼音_时间戳)",
  "title": "故事标题",
  "emoji": "🎊",
  "duration": "2分钟",
  "pages": [
    {
      "text": "故事文本",
      "emoji": "😊",
      "tts": "语音播报文本",
      "question": {
        "text": "问题文本",
        "options": ["选项1", "选项2", "选项3"],
        "correctIndex": 0
      }
    }
  ]
}
]

请直接返回 JSON 数组,不要添加任何解释文字。''';
    }

    // 初始化 Prompt
    _promptController.text = '';

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // 配置块构建器
          Widget buildConfigSection({
            required String title,
            required IconData icon,
            required OpenAIConfig? selectedConfig,
            required String? selectedModel,
            required Function(OpenAIConfig?) onConfigChanged,
            required Function(String?) onModelChanged,
            bool isImage = false,
          }) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题
                Row(
                  children: [
                    Icon(icon, color: Colors.blue, size: 18.sp),
                    SizedBox(width: 6.w),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12.h),

                // 选择接口
                Text(
                  '选择接口',
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 8.h),
                DropdownButtonFormField<OpenAIConfig>(
                  decoration: InputDecoration(
                    hintText: '请选择接口',
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    filled: true,
                    fillColor: Colors.grey[50],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.r),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.r),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16.w,
                      vertical: 14.h,
                    ),
                  ),
                  value: selectedConfig,
                  items: configs
                      .map((c) => DropdownMenuItem(
                            value: c,
                            child:
                                Text(c.name, overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: onConfigChanged,
                  isExpanded: true,
                ),

                SizedBox(height: 12.h),

                // 选择模型
                Text(
                  '选择模型',
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 8.h),
                // 模型选择 - 下拉框
                Builder(
                  builder: (context) {
                    // 获取推荐模型
                    String recommendedModel = '可选任意模型';
                    final models = selectedConfig?.models ?? [];

                    if (models.isNotEmpty) {
                      if (isImage) {
                        // 图片模型推荐逻辑
                        recommendedModel = models.firstWhere(
                          (m) =>
                              m.toLowerCase().contains('dall-e') ||
                              m.toLowerCase().contains('image') ||
                              m.toLowerCase().contains('flux'),
                          orElse: () => models.first,
                        );
                      } else {
                        // 文本模型推荐逻辑
                        recommendedModel = models.firstWhere(
                          (m) => m.toLowerCase().contains('gpt-4'),
                          orElse: () => models.firstWhere(
                            (m) => m.toLowerCase().contains('claude'),
                            orElse: () => models.first,
                          ),
                        );
                      }
                    }

                    return DropdownButtonFormField<String>(
                      decoration: InputDecoration(
                        hintText: recommendedModel == '可选任意模型'
                            ? recommendedModel
                            : '推荐: $recommendedModel',
                        hintStyle: TextStyle(color: Colors.grey[400]),
                        filled: true,
                        fillColor: Colors.grey[50],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.r),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.r),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16.w,
                          vertical: 14.h,
                        ),
                      ),
                      // 确保选中的值在列表中，否则为 null
                      value:
                          models.contains(selectedModel) ? selectedModel : null,
                      items: models
                          .map((m) => DropdownMenuItem(
                                value: m,
                                child: Text(m, overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: onModelChanged,
                      isExpanded: true,
                    );
                  },
                )
              ],
            );
          }

          return AlertDialog(
            title: const Text('AI 故事生成配置'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. 故事生成配置
                  buildConfigSection(
                    title: '故事生成配置 (Text)',
                    icon: Icons.chat_bubble_outline,
                    selectedConfig: textConfig,
                    selectedModel: textModel,
                    onConfigChanged: (val) {
                      if (val == null) return;
                      setDialogState(() {
                        textConfig = val;
                        textModel = val.selectedModel;
                        if ((textModel == null || textModel!.isEmpty) &&
                            val.models.isNotEmpty) {
                          textModel = val.models.first;
                        }
                      });
                    },
                    onModelChanged: (val) =>
                        setDialogState(() => textModel = val),
                  ),
                  SizedBox(height: 16.h),

                  // 2. 插图生成配置
                  Row(
                    children: [
                      Checkbox(
                        value: enableImageGen,
                        onChanged: (v) =>
                            setDialogState(() => enableImageGen = v ?? false),
                      ),
                      Text('同时生成插图', style: TextStyle(fontSize: 14.sp)),
                      Text(' (耗时较长)',
                          style:
                              TextStyle(fontSize: 12.sp, color: Colors.grey)),
                    ],
                  ),
                  if (enableImageGen) ...[
                    buildConfigSection(
                      title: '插图生成配置 (Image)',
                      icon: Icons.image_outlined,
                      selectedConfig: imageConfig,
                      selectedModel: imageModel,
                      onConfigChanged: (val) {
                        if (val == null) return;
                        setDialogState(() {
                          imageConfig = val;
                        });
                      },
                      onModelChanged: (val) =>
                          setDialogState(() => imageModel = val),
                      isImage: true,
                    ),
                    SizedBox(height: 16.h),
                  ],

                  // 3. 通用设置
                  const Divider(),
                  SizedBox(height: 8.h),
                  const Text('故事设置'),
                  Slider(
                    value: count.toDouble(),
                    min: 1,
                    max: 3,
                    divisions: 2,
                    label: count.toString(),
                    onChanged: (value) =>
                        setDialogState(() => count = value.toInt()),
                  ),
                  Text('$count 个故事'),
                  SizedBox(height: 12.h),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: '故事主题 (可选)',
                      hintText: '例如:元宵节、舞龙舞狮',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => theme = value,
                  ),
                  SizedBox(height: 12.h),

                  // 显示默认 Prompt (可折叠)
                  ExpansionTile(
                    title: Text(
                      '查看默认 Prompt 模板',
                      style: TextStyle(
                          fontSize: 13.sp, fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      '点击展开查看系统默认的故事生成提示词',
                      style:
                          TextStyle(fontSize: 11.sp, color: Colors.grey[600]),
                    ),
                    children: [
                      Container(
                        padding: EdgeInsets.all(12.w),
                        margin: EdgeInsets.symmetric(horizontal: 16.w),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                        child: Text(
                          '''请生成 {count} 个关于中国传统春节习俗及其由来的科普故事，适合儿童阅读。

重点：不要生成虚构的童话故事，而是要以生动有趣的方式讲解真实的民俗知识（如：为什么过年要吃饺子？春联的由来？压岁钱的寓意？）。

要求:
1. {theme != null ? '故事主题: {theme}' : '主题必须围绕春节传统习俗的由来、传说或具体礼仪（例如：年兽的传说、贴福字的由来、拜年的礼仪、元宵节的习俗等）'}
2. 每个故事包含 5-7 个页面
3. 每页包含: text(展示文本，简练有趣)、emoji(相关表情)、tts(口语化播报，语气亲切，适合讲给孩子听)
4. 至少包含 1 个互动问题，考察孩子对刚才科普知识的理解
5. 内容必须准确、有教育意义，弘扬传统文化
6. 时长控制在 1-2 分钟

注意: 自定义 Prompt 会完全替换此模板''',
                          style: TextStyle(
                            fontSize: 11.sp,
                            fontFamily: 'monospace',
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      SizedBox(height: 8.h),
                      Padding(
                        padding: EdgeInsets.only(bottom: 12.h, right: 16.w),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () {
                              final defaultPrompt =
                                  getDefaultPrompt(count, theme);
                              _promptController.text = defaultPrompt;
                              // 手动更新 customPrompt，因为设置 controller.text 不会触发 onChanged
                              customPrompt = defaultPrompt;
                            },
                            icon: const Icon(Icons.copy_all, size: 16),
                            label: const Text('复制模板到下方编辑'),
                          ),
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: 12.h),
                  TextField(
                    controller: _promptController,
                    decoration: const InputDecoration(
                      labelText: '自定义 Prompt (高级)',
                      helperText: '注意:将覆盖默认模板(含格式要求),请慎用',
                      helperMaxLines: 1,
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 4,
                    minLines: 2,
                    style: TextStyle(fontSize: 12.sp),
                    onChanged: (value) => customPrompt = value,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () async {
                  // 1. 关闭配置对话框
                  Navigator.pop(context);

                  // 2. 检查是否有任务正在运行 (Double check)
                  if (_aiService.isTaskRunning.value) {
                    ToastUtils.showInfo('已有生成任务正在进行中');
                    _showBatchGenerationProgress();
                    return;
                  }

                  // 3. 显示提示
                  ToastUtils.showSuccess('AI 故事生成任务已在后台启动');
                  _showBatchGenerationProgress();

                  try {
                    // 保存配置
                    final currentQuizConfig = _quizService.config.value;
                    if (currentQuizConfig != null) {
                      if (textConfig != null) {
                        currentQuizConfig.chatConfigId = textConfig!.id;
                        currentQuizConfig.chatModel = textModel;
                      }
                      if (enableImageGen && imageConfig != null) {
                        currentQuizConfig.imageGenConfigId = imageConfig!.id;
                        currentQuizConfig.imageGenModel = imageModel;
                      }
                      await _quizService.updateConfig(currentQuizConfig);
                    }

                    // 4. 开始生成任务 (通过 Service)
                    _aiService.startStoryGenerationTask(
                      count: count,
                      theme: theme.isEmpty ? null : theme,
                      customPrompt: customPrompt.isEmpty ? null : customPrompt,
                      textConfig: textConfig,
                      textModel: textModel,
                      imageConfig: enableImageGen ? imageConfig : null,
                      imageModel: imageModel,
                      enableImageGen: enableImageGen,
                    );

                    // 监听任务完成以刷新列表 (Task is async, but we can listen to its end if we want, or just wait for user interaction)
                    // With GetX, we can listen to taskSteps changes or isTaskRunning
                  } catch (e) {
                    ToastUtils.showError('启动任务失败: $e');
                  }
                },
                child: const Text('开始生成'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 显示批量生成进度对话框
  void _showBatchGenerationProgress() {
    if (_aiService.taskSteps.isEmpty) {
      ToastUtils.showInfo('暂无生成任务');
      return;
    }

    AIGenerationProgressDialog.show(
      steps: _aiService.taskSteps,
      onClose: () => Get.back(),
    );
  }

  /// 批量为选中的故事生成图片
  Future<void> _batchGenerateImagesForSelected() async {
    if (_selectedIds.isEmpty) {
      ToastUtils.showWarning('请先选择故事');
      return;
    }

    if (_aiService.isTaskRunning.value) {
      ToastUtils.showInfo('已有生成任务正在进行中');
      _showBatchGenerationProgress();
      return;
    }

    final selectedStories = _storyService
        .getAllStories()
        .where((s) => _selectedIds.contains(s.id))
        .toList();

    _startGenerationTask(selectedStories);
  }

  /// 为单个故事重新生成图片
  Future<void> _regenerateImagesForStory(NewYearStory story) async {
    if (_aiService.isTaskRunning.value) {
      ToastUtils.showInfo('已有生成任务正在进行中');
      _showBatchGenerationProgress();
      return;
    }

    _startGenerationTask([story]);
  }

  /// 启动生成任务
  Future<void> _startGenerationTask(List<NewYearStory> stories) async {
    // 检查配置
    final quizConfig = _quizService.config.value;
    if (quizConfig == null) {
      ToastUtils.showWarning('请先配置 AI 设置');
      return;
    }

    final imageGenConfigId = quizConfig.imageGenConfigId;
    OpenAIConfig? imageGenConfig;
    if (imageGenConfigId != null) {
      imageGenConfig = _openAIService.configs
          .firstWhereOrNull((c) => c.id == imageGenConfigId);
    }

    // 如果没有配置专用生图AI，尝试使用当前默认配置
    imageGenConfig ??= _openAIService.currentConfig.value;

    if (imageGenConfig == null) {
      ToastUtils.showWarning('未配置生图AI，请在设置中配置');
      return;
    }

    // 退出选择模式以便显示进度按钮
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });

    ToastUtils.showSuccess('生成任务已启动，可在后台运行');
    _showBatchGenerationProgress();

    // 调用 Service
    _aiService.startBatchImageGenerationTask(
        stories: stories,
        config: imageGenConfig,
        model: quizConfig.imageGenModel);
  }

  @override
  Widget build(BuildContext context) {
    // 自动监听 _storyService 的变化 (需确保 StoryManagementService 是 Observable 或者使用 GetBuilder)
    // 这里使用 setState 刷新，暂时保持原样。但是 _storyService.getAllStories() 返回的是普通List
    // 当 Service 完成任务后，应该刷新 UI。
    // 可以监听 _aiService.isTaskRunning 变为 false 时刷新

    // 简单起见，在 build 中也 Obx 监听一下 isTaskRunning，当它改变时触发重建及可能的刷新
    return Obx(() {
      // 监听任务状态变化，如果在运行 -> 结束，可能需要刷新列表
      // 但 Obx builder 必须是纯函数。
      // 实际上，Service 里的 importStories 会修改 StoryService 的数据。
      // 下面的 ListView 使用 getAllStories，如果 SetState 没调用，不会刷新。
      // 可以在 Obx 中放置一个 dummy 变量，或者使用 GetBuilder。
      // 更好的方式是 StoryManagementService 里的 stories 也是 reactive 的。
      // 假设目前是手动刷新。我们可以加个刷新按钮，或者...
      // 暂时保持原样，用户可能需要手动下拉刷新或者重新进入页面。

      // 为了让 AppBar 图标动态显示，我们在 AppBar action 里用 Obx

      final stories = _storyService.getAllStories();
      final isRunning = _aiService.isTaskRunning.value;

      return Scaffold(
        appBar: AppBar(
          title: const Text('故事管理'),
          actions: [
            // 正在后台生成时显示进度入口
            if (isRunning)
              TextButton.icon(
                onPressed: _showBatchGenerationProgress,
                icon: SizedBox(
                  width: 14.w,
                  height: 14.w,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                ),
                label: const Text('进度'),
              ),

            if (_isSelectionMode) ...[
              TextButton.icon(
                onPressed: _batchGenerateImagesForSelected,
                icon: const Icon(Icons.image_outlined),
                label: const Text('生成插图'),
              ),
              TextButton.icon(
                onPressed: _toggleSelectAll,
                icon: Icon(
                  _selectedIds.length == stories.length
                      ? Icons.deselect
                      : Icons.select_all,
                ),
                label:
                    Text(_selectedIds.length == stories.length ? '取消全选' : '全选'),
              ),
              IconButton(
                icon: const Icon(Icons.delete),
                onPressed: _deleteSelected,
                tooltip: '删除选中',
              ),
            ],
            IconButton(
              icon: Icon(_isSelectionMode ? Icons.close : Icons.checklist),
              onPressed: _toggleSelectionMode,
              tooltip: _isSelectionMode ? '退出选择' : '批量选择',
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : stories.isEmpty
                ? _buildEmptyState()
                : _buildStoryList(stories),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showAIGenerateDialog,
          icon: const Icon(Icons.auto_awesome),
          label: const Text('AI 生成'),
        ),
      );
    });
  }

  /// 空状态
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.book_outlined, size: 80.sp, color: Colors.grey),
          SizedBox(height: 16.h),
          const Text('还没有故事',
              style: TextStyle(fontSize: 18, color: Colors.grey)),
          SizedBox(height: 8.h),
          const Text('点击下方按钮使用 AI 生成故事', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  /// 故事列表
  Widget _buildStoryList(List<NewYearStory> stories) {
    return ListView.builder(
      padding: EdgeInsets.all(16.w),
      itemCount: stories.length,
      itemBuilder: (context, index) {
        final story = stories[index];
        final isSelected = _selectedIds.contains(story.id);

        return Card(
          margin: EdgeInsets.only(bottom: 12.h),
          child: ListTile(
            leading: _isSelectionMode
                ? Checkbox(
                    value: isSelected,
                    onChanged: (_) => _toggleSelection(story.id),
                  )
                : Text(
                    story.emoji,
                    style: TextStyle(fontSize: 32.sp),
                  ),
            title: Text(story.title),
            subtitle: Text(
              '${story.duration} • ${story.pageCount} 页',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: _isSelectionMode
                ? null
                : PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') {
                        _editStory(story);
                      } else if (value == 'delete') {
                        _deleteStory(story);
                      } else if (value == 'regenerate') {
                        _regenerateImagesForStory(story);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'regenerate',
                        child: Row(
                          children: [
                            Icon(Icons.image, size: 20, color: Colors.blue),
                            SizedBox(width: 8),
                            Text('重新生成图片',
                                style: TextStyle(color: Colors.blue)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 20),
                            SizedBox(width: 8),
                            Text('编辑'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 20, color: Colors.red),
                            SizedBox(width: 8),
                            Text('删除', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
            onTap: _isSelectionMode ? () => _toggleSelection(story.id) : null,
          ),
        );
      },
    );
  }
}
