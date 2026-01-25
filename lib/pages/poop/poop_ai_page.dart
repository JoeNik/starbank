import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import '../../models/poop_record.dart';
import '../../models/ai_chat.dart';
import '../../controllers/user_controller.dart';
import '../../services/openai_service.dart';
import '../../theme/app_theme.dart';

/// 便便 AI 分析页面
class PoopAIPage extends StatefulWidget {
  const PoopAIPage({super.key});

  @override
  State<PoopAIPage> createState() => _PoopAIPageState();
}

class _PoopAIPageState extends State<PoopAIPage> {
  final UserController _userController = Get.find<UserController>();

  // AI 服务（全局）
  late OpenAIService _openAIService;

  // 时间范围
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _endDate = DateTime.now();

  // 记录
  List<PoopRecord> _records = [];

  // 对话历史
  List<AIChat> _chatHistory = [];

  // 当前分析结果
  String _currentResponse = '';

  // 加载状态
  bool _isLoading = true;
  bool _isAnalyzing = false;

  // 自定义 Prompt（保存到 Hive）
  String _customPrompt = '''你是一位专业的儿科健康顾问。请根据宝宝的排便记录，分析以下内容：
1. 排便频率是否正常
2. 排便时间规律性
3. 便便类型和颜色是否健康
4. 给出改善建议

请用通俗易懂的语言回答，便于家长理解。''';

  // 当前选择的模型
  String _selectedModel = '';

  late Box<PoopRecord> _recordBox;
  late Box<AIChat> _chatBox;
  late Box _settingsBox;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    setState(() => _isLoading = true);

    // 获取 OpenAI 服务（全局已初始化）
    _openAIService = Get.find<OpenAIService>();

    // 打开数据库
    if (!Hive.isAdapterRegistered(11)) {
      Hive.registerAdapter(PoopRecordAdapter());
    }
    if (!Hive.isAdapterRegistered(12)) {
      Hive.registerAdapter(AIChatAdapter());
    }

    _recordBox = await Hive.openBox<PoopRecord>('poop_records');
    _chatBox = await Hive.openBox<AIChat>('ai_chats');
    _settingsBox = await Hive.openBox('poop_ai_settings');

    // 加载保存的 prompt
    _customPrompt = _settingsBox.get('prompt', defaultValue: _customPrompt);
    _selectedModel = _settingsBox.get('selected_model', defaultValue: '');

    // 如果没有选择模型，使用默认配置的模型
    if (_selectedModel.isEmpty && _openAIService.currentConfig.value != null) {
      _selectedModel = _openAIService.currentConfig.value!.selectedModel;
    }

    _loadRecords();
    _loadChatHistory();

    setState(() => _isLoading = false);
  }

  void _loadRecords() {
    final babyId = _userController.currentBaby.value?.id;
    if (babyId == null) return;

    final records = _recordBox.values
        .where((r) =>
            r.babyId == babyId &&
            r.dateTime.isAfter(_startDate.subtract(const Duration(days: 1))) &&
            r.dateTime.isBefore(_endDate.add(const Duration(days: 1))))
        .toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

    setState(() => _records = records);
  }

  void _loadChatHistory() {
    final babyId = _userController.currentBaby.value?.id;
    if (babyId == null) return;

    final chats = _chatBox.values
        .where((c) => c.babyId == babyId && c.chatType == 'poop_analysis')
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    setState(() => _chatHistory = chats);
  }

  /// 执行 AI 分析
  Future<void> _analyzeWithAI() async {
    final config = _openAIService.currentConfig.value;
    if (config == null) {
      _showConfigMissingDialog();
      return;
    }

    if (_records.isEmpty) {
      Get.snackbar('提示', '所选时间范围内暂无记录', snackPosition: SnackPosition.BOTTOM);
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _currentResponse = '';
    });

    try {
      // 构建用户消息
      final baby = _userController.currentBaby.value!;
      final recordsText = _records.map((r) {
        return '- ${DateFormat('MM月dd日 HH:mm').format(r.dateTime)}: ${r.typeDesc}, ${r.colorDesc}${r.note.isNotEmpty ? ", 备注: ${r.note}" : ""}';
      }).join('\n');

      final userMessage = '''宝宝信息：${baby.name}
记录时间范围：${DateFormat('yyyy年MM月dd日').format(_startDate)} 至 ${DateFormat('yyyy年MM月dd日').format(_endDate)}
共 ${_records.length} 条记录

排便记录：
$recordsText''';

      // 调用 AI
      final response = await _openAIService.chat(
        systemPrompt: _customPrompt,
        userMessage: userMessage,
      );

      setState(() => _currentResponse = response);

      // 保存对话记录
      final chat = AIChat(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        babyId: baby.id,
        createdAt: DateTime.now(),
        prompt: userMessage,
        response: response,
        chatType: 'poop_analysis',
      );
      await _chatBox.put(chat.id, chat);
      _loadChatHistory();
    } catch (e) {
      Get.snackbar('分析失败', e.toString(), snackPosition: SnackPosition.BOTTOM);
    } finally {
      setState(() => _isAnalyzing = false);
    }
  }

  void _showConfigMissingDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('未配置 AI'),
        content: const Text('请先在「设置 → AI 设置」中配置 OpenAI API'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
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
        title: const Text('AI 便便分析'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: '历史记录',
            onPressed: _showHistoryDialog,
          ),
          IconButton(
            icon: const Icon(Icons.edit_note),
            tooltip: '编辑智能体',
            onPressed: _showPromptEditor,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // AI 配置状态
            _buildAIConfigStatus(),

            SizedBox(height: 16.h),

            // 时间范围选择
            _buildDateRangeSelector(),

            SizedBox(height: 16.h),

            // 记录统计
            _buildRecordsSummary(),

            SizedBox(height: 16.h),

            // 分析按钮
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isAnalyzing ? null : _analyzeWithAI,
                icon: _isAnalyzing
                    ? SizedBox(
                        width: 20.w,
                        height: 20.w,
                        child: const CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.psychology),
                label: Text(_isAnalyzing ? '分析中...' : '开始 AI 分析'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                ),
              ),
            ),

            SizedBox(height: 24.h),

            // 分析结果
            if (_currentResponse.isEmpty)
              _buildEmptyState()
            else
              _buildAnalysisResult(),
          ],
        ),
      ),
    );
  }

  /// AI 配置状态
  Widget _buildAIConfigStatus() {
    final config = _openAIService.currentConfig.value;
    final models = config?.models ?? [];

    return Card(
      child: Padding(
        padding: EdgeInsets.all(12.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  config != null ? Icons.check_circle : Icons.warning,
                  color: config != null ? Colors.green : Colors.orange,
                  size: 20.sp,
                ),
                SizedBox(width: 8.w),
                Text(
                  config != null ? '已配置: ${config.name}' : '未配置 AI',
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (models.isNotEmpty) ...[
              SizedBox(height: 12.h),
              Text('选择模型:',
                  style: TextStyle(fontSize: 12.sp, color: Colors.grey)),
              SizedBox(height: 8.h),
              SizedBox(
                height: 36.h,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: models.length,
                  itemBuilder: (context, index) {
                    final model = models[index];
                    final isSelected = model == _selectedModel;
                    return Padding(
                      padding: EdgeInsets.only(right: 8.w),
                      child: ChoiceChip(
                        label: Text(
                          model.length > 15
                              ? '${model.substring(0, 15)}...'
                              : model,
                          style: TextStyle(fontSize: 11.sp),
                        ),
                        selected: isSelected,
                        onSelected: (s) async {
                          if (s) {
                            setState(() => _selectedModel = model);
                            await _settingsBox.put('selected_model', model);
                            // 同步更新全局配置
                            config!.selectedModel = model;
                            await _openAIService.updateConfig(config);
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDateRangeSelector() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '选择分析时间范围',
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 12.h),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(true),
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(DateFormat('MM/dd').format(_startDate)),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12.w),
                  child: const Text('至'),
                ),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(false),
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(DateFormat('MM/dd').format(_endDate)),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8.h),
            // 快捷选项
            Wrap(
              spacing: 8.w,
              children: [
                _buildQuickDateChip('最近7天', 7),
                _buildQuickDateChip('最近14天', 14),
                _buildQuickDateChip('最近30天', 30),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickDateChip(String label, int days) {
    return ActionChip(
      label: Text(label),
      onPressed: () {
        setState(() {
          _endDate = DateTime.now();
          _startDate = DateTime.now().subtract(Duration(days: days));
        });
        _loadRecords();
      },
    );
  }

  Future<void> _pickDate(bool isStart) async {
    final date = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (date != null) {
      setState(() {
        if (isStart) {
          _startDate = date;
        } else {
          _endDate = date;
        }
      });
      _loadRecords();
    }
  }

  Widget _buildRecordsSummary() {
    final days = _endDate.difference(_startDate).inDays + 1;
    return Card(
      color: Colors.brown.shade50,
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Row(
          children: [
            Icon(Icons.analytics, color: Colors.brown, size: 32.sp),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '共 ${_records.length} 条记录',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_records.isNotEmpty)
                    Text(
                      '平均每天 ${(_records.length / days).toStringAsFixed(1)} 次',
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: Colors.grey,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        children: [
          Icon(Icons.psychology, size: 64.sp, color: Colors.grey.shade300),
          SizedBox(height: 16.h),
          Text(
            '点击上方按钮开始 AI 分析',
            style: TextStyle(fontSize: 14.sp, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysisResult() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: AppTheme.primary, size: 20.sp),
                SizedBox(width: 8.w),
                Text(
                  'AI 分析结果',
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Divider(height: 24.h),
            SelectableText(
              _currentResponse,
              style: TextStyle(
                fontSize: 14.sp,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showHistoryDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('历史分析记录'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400.h,
          child: _chatHistory.isEmpty
              ? const Center(child: Text('暂无历史记录'))
              : ListView.builder(
                  itemCount: _chatHistory.length,
                  itemBuilder: (context, index) {
                    final chat = _chatHistory[index];
                    return Card(
                      margin: EdgeInsets.only(bottom: 8.h),
                      child: ListTile(
                        title: Text(
                          DateFormat('yyyy-MM-dd HH:mm').format(chat.createdAt),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          chat.response.length > 50
                              ? '${chat.response.substring(0, 50)}...'
                              : chat.response,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          setState(() => _currentResponse = chat.response);
                        },
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showPromptEditor() {
    final controller = TextEditingController(text: _customPrompt);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑智能体提示词'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            maxLines: 10,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '输入系统提示词...',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newPrompt = controller.text;
              await _settingsBox.put('prompt', newPrompt);
              setState(() => _customPrompt = newPrompt);
              Navigator.of(ctx).pop();
              Get.snackbar('成功', '提示词已保存', snackPosition: SnackPosition.BOTTOM);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
