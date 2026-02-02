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
import '../../../models/quiz_config.dart';
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

    // 初始化状态: Story Config
    // Use QuizConfig for defaults (mapped as 'Chat' -> Text, 'ImageGen' -> Image)
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
    bool isGenerating = false;

    // 添加 TextEditingController
    final TextEditingController _promptController = TextEditingController();

    // 获取默认 Prompt 的函数
    String getDefaultPrompt(int c, String t) {
      return '''请生成 $c 个适合儿童的中国新年相关故事。

要求:
1. ${t.isNotEmpty ? '故事主题: $t' : '主题可以是春节习俗、传统文化、民间传说等'}
2. 每个故事包含 5-7 个页面
3. 每页包含: text(文本内容)、emoji(表情符号)、tts(语音播报文本)
4. 至少包含 1 个互动问题,问题包含: text(问题)、options(3个选项数组)、correctIndex(正确答案索引0-2)
5. 故事要有教育意义,语言简单易懂
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
                  onChanged: isGenerating ? null : onConfigChanged,
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
                      onChanged: isGenerating ? null : onModelChanged,
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
                        onChanged: isGenerating
                            ? null
                            : (v) => setDialogState(
                                () => enableImageGen = v ?? false),
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
                    onChanged: isGenerating
                        ? null
                        : (value) =>
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
                    enabled: !isGenerating,
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
                          '''请生成 {count} 个适合儿童的中国新年相关故事。

要求:
1. {theme != null ? '故事主题: {theme}' : '主题可以是春节习俗、传统文化、民间传说等'}
2. 每个故事包含 5-7 个页面
3. 每页包含: text(文本内容)、emoji(表情符号)、tts(语音播报文本)
4. 至少包含 1 个互动问题
5. 故事要有教育意义,语言简单易懂
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
                    enabled: !isGenerating,
                    style: TextStyle(fontSize: 12.sp),
                    onChanged: (value) => customPrompt = value,
                  ),
                ],
              ),
            ),
            actions: [
              if (!isGenerating)
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
              ElevatedButton(
                onPressed: isGenerating
                    ? null
                    : () async {
                        // 1. 关闭配置对话框
                        Navigator.pop(context);

                        // 2. 准备进度步骤
                        final steps = <GenerationStep>[
                          GenerationStep(
                            title: '生成故事文本',
                            description: '正在连接 AI 生成故事内容...',
                            status: StepStatus.running,
                          ),
                          if (enableImageGen)
                            GenerationStep(
                              title: '生成插图',
                              description: '等待文本生成完成...',
                              status: StepStatus.pending,
                            ),
                          GenerationStep(
                            title: '验证与保存',
                            description: '等待生成完成...',
                            status: StepStatus.pending,
                          ),
                        ].obs;

                        // 3. 显示进度对话框
                        AIGenerationProgressDialog.show(
                          steps: steps,
                          onClose: () => Get.back(),
                        );

                        try {
                          // 保存配置
                          final currentQuizConfig = _quizService.config.value;
                          if (currentQuizConfig != null) {
                            if (textConfig != null) {
                              currentQuizConfig.chatConfigId = textConfig!.id;
                              currentQuizConfig.chatModel = textModel;
                            }
                            if (enableImageGen && imageConfig != null) {
                              currentQuizConfig.imageGenConfigId =
                                  imageConfig!.id;
                              currentQuizConfig.imageGenModel = imageModel;
                            }
                            await _quizService.updateConfig(currentQuizConfig);
                          }

                          // 4. 开始生成
                          final result =
                              await _aiService.generateAndImportStories(
                            count: count,
                            theme: theme.isEmpty ? null : theme,
                            customPrompt:
                                customPrompt.isEmpty ? null : customPrompt,
                            textConfig: textConfig,
                            textModel: textModel,
                            imageConfig: enableImageGen ? imageConfig : null,
                            imageModel: imageModel,
                            onProgress: (step, message,
                                {Map<String, dynamic>? details}) {
                              switch (step) {
                                case 'text':
                                  steps[0].setRunning(description: message);
                                  break;
                                case 'text_done':
                                  steps[0].setSuccess(
                                    description: message,
                                    details: details?['raw']?.toString(),
                                  );
                                  // 如果有图片生成，开启第二步
                                  if (enableImageGen && steps.length > 2) {
                                    steps[1]
                                        .setRunning(description: '准备生成插图...');
                                  } else {
                                    // 否则直接跳到最后一步
                                    steps.last
                                        .setRunning(description: '正在保存数据...');
                                  }
                                  break;
                                case 'image':
                                  if (enableImageGen && steps.length > 2) {
                                    steps[1].setRunning(description: message);
                                  }
                                  break;
                                case 'image_download':
                                  if (enableImageGen && steps.length > 2) {
                                    steps[1].setRunning(description: message);
                                  }
                                  break;
                                case 'import':
                                  // 如果有图片步，先完成它
                                  if (enableImageGen && steps.length > 2) {
                                    steps[1].setSuccess(description: '插图生成完成');
                                  }
                                  steps.last.setRunning(description: message);
                                  break;
                                case 'done':
                                  steps.last.setSuccess(description: '流程结束');
                                  break;
                                case 'error':
                                  // 找到当前正在运行的步骤报错
                                  final currentStep = steps.firstWhere(
                                    (s) => s.status.value == StepStatus.running,
                                    orElse: () => steps.last,
                                  );
                                  currentStep.setError(message);
                                  break;
                              }
                            },
                          );

                          // 5. 添加结果汇总
                          final (success, skip, fail, errors) = result;
                          final summary =
                              '生成完成\n成功: $success\n跳过: $skip\n失败: $fail';

                          if (fail > 0 || errors.isNotEmpty) {
                            steps.add(GenerationStep(
                              title: '生成结果',
                              status: StepStatus
                                  .error, // Partial error implies warning/error
                              description: summary,
                              details: errors.join('\n'),
                            ));
                          } else {
                            steps.add(GenerationStep(
                              title: '生成结果',
                              status: StepStatus.success,
                              description: summary,
                            ));
                          }

                          // 刷新列表
                          setState(() {});
                        } catch (e) {
                          steps.add(GenerationStep(
                            title: '发生异常',
                            status: StepStatus.error,
                            error: e.toString(),
                          ));
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

  @override
  Widget build(BuildContext context) {
    final stories = _storyService.getAllStories();

    return Scaffold(
      appBar: AppBar(
        title: const Text('故事管理'),
        actions: [
          if (_isSelectionMode) ...[
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
                      }
                    },
                    itemBuilder: (context) => [
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
