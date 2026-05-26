import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../../controllers/app_mode_controller.dart';
import '../../../models/encyclopedia_config.dart';
import '../../../services/encyclopedia_service.dart';
import '../../../services/openai_service.dart';
import '../../../services/tts_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/toast_utils.dart';

class EncyclopediaSettingsPage extends StatefulWidget {
  const EncyclopediaSettingsPage({super.key});

  @override
  State<EncyclopediaSettingsPage> createState() =>
      _EncyclopediaSettingsPageState();
}

class _EncyclopediaSettingsPageState extends State<EncyclopediaSettingsPage> {
  final EncyclopediaService _service = Get.find<EncyclopediaService>();
  final OpenAIService _openAIService = Get.find<OpenAIService>();
  final AppModeController _modeController = Get.find<AppModeController>();
  final TtsService _tts = Get.find<TtsService>();

  late EncyclopediaConfig _config;
  late TextEditingController _promptController;
  late TextEditingController _questionGenPromptController;
  late TextEditingController _urlController;
  late TextEditingController _generateCategoryController;
  late TextEditingController _generateCountController;
  late TextEditingController _correctFeedbackController;
  late TextEditingController _wrongFeedbackController;

  bool _isSyncing = false;
  bool _isGenerating = false;
  String? _ttsLoadingKey;

  @override
  void initState() {
    super.initState();
    _config = _service.config.value ?? EncyclopediaConfig();
    _promptController = TextEditingController(text: _config.promptTemplate);
    _questionGenPromptController =
        TextEditingController(text: _config.questionGenPromptTemplate);
    _urlController = TextEditingController(text: _config.importUrl ?? '');
    _generateCategoryController = TextEditingController(text: '生活科学');
    _generateCountController = TextEditingController(text: '5');
    _correctFeedbackController =
        TextEditingController(text: _config.correctFeedbackText);
    _wrongFeedbackController =
        TextEditingController(text: _config.wrongFeedbackText);
  }

  @override
  void dispose() {
    _promptController.dispose();
    _questionGenPromptController.dispose();
    _urlController.dispose();
    _generateCategoryController.dispose();
    _generateCountController.dispose();
    _correctFeedbackController.dispose();
    _wrongFeedbackController.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _save({bool showToast = true}) async {
    _config.promptTemplate = _promptController.text.trim().isEmpty
        ? kDefaultEncyclopediaPromptTemplate
        : _promptController.text.trim();
    _config.questionGenPromptTemplate =
        _questionGenPromptController.text.trim().isEmpty
            ? kDefaultEncyclopediaQuestionGenPromptTemplate
            : _questionGenPromptController.text.trim();
    _config.importUrl = _urlController.text.trim();
    _config.correctFeedbackText =
        _normalizedFeedback(_correctFeedbackController.text, '恭喜答对了');
    _config.wrongFeedbackText =
        _normalizedFeedback(_wrongFeedbackController.text, '答错了，继续加油哦');
    await _service.updateConfig(_config);
    if (showToast) {
      ToastUtils.showSuccess('百科设置已保存');
    }
  }

  String _normalizedFeedback(String value, String fallback) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }

  Future<void> _previewFeedback(String text, String loadingKey) async {
    final content = text.trim();
    if (content.isEmpty) {
      ToastUtils.showWarning('请先填写语音反馈文案');
      return;
    }

    final showLoading =
        _tts.shouldUseAudioBasedPlayback(featureKey: 'encyclopedia');
    try {
      if (showLoading && mounted) {
        setState(() => _ttsLoadingKey = loadingKey);
        await _tts.prefetchCftts(content, featureKey: 'encyclopedia');
        if (mounted && _ttsLoadingKey == loadingKey) {
          setState(() => _ttsLoadingKey = null);
        }
      }
      await _tts.speak(content, featureKey: 'encyclopedia');
    } catch (e) {
      ToastUtils.showWarning('语音播放失败: $e');
    } finally {
      if (mounted && _ttsLoadingKey == loadingKey) {
        setState(() => _ttsLoadingKey = null);
      }
    }
  }

  Future<void> _syncFromUrl() async {
    if (_urlController.text.trim().isEmpty) {
      ToastUtils.showWarning('请先填写题库 URL');
      return;
    }
    setState(() => _isSyncing = true);
    try {
      _config.importUrl = _urlController.text.trim();
      await _service.updateConfig(_config);
      final count = await _service.syncQuestionsFromUrl();
      ToastUtils.showSuccess('同步完成，已覆盖为 $count 道题');
    } catch (e) {
      ToastUtils.showError('同步失败: $e');
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _generateQuestions() async {
    final count = int.tryParse(_generateCountController.text.trim()) ?? 0;
    final category = _generateCategoryController.text.trim();
    if (category.isEmpty) {
      ToastUtils.showWarning('请输入题目类目');
      return;
    }
    if (count <= 0 || count > 50) {
      ToastUtils.showWarning('生成数量请输入 1-50');
      return;
    }

    await _save(showToast: false);
    setState(() => _isGenerating = true);
    try {
      final imported = await _service.generateQuestionsWithAI(
        category: category,
        count: count,
      );
      ToastUtils.showSuccess('已新增 $imported 道百科题');
    } catch (e) {
      ToastUtils.showError('生成题库失败: $e');
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgBlue,
      appBar: AppBar(
        title: const Text('百科设置'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('保存'),
          ),
        ],
      ),
      body: Obx(() {
        if (!_modeController.isParentMode) {
          return Center(
            child: Text(
              '请先切换到家长模式',
              style: TextStyle(fontSize: 16.sp, color: Colors.grey[700]),
            ),
          );
        }

        return SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.all(16.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAiConfigCard(),
                SizedBox(height: 14.h),
                _buildFeedbackTtsCard(),
                SizedBox(height: 14.h),
                _buildGenerateCard(),
                SizedBox(height: 14.h),
                _buildUrlSyncCard(),
                SizedBox(height: 14.h),
                _buildCacheCard(),
                SizedBox(height: 14.h),
                _buildPromptCard(),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildAiConfigCard() {
    return _sectionCard(
      title: 'AI 配置',
      icon: Icons.smart_toy,
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            initialValue: _config.chatConfigId,
            decoration: InputDecoration(
              labelText: '解析接口',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
            ),
            items: [
              const DropdownMenuItem<String>(value: null, child: Text('默认配置')),
              ..._openAIService.configs.map(
                (e) => DropdownMenuItem<String>(
                  value: e.id,
                  child: Text(e.name),
                ),
              ),
            ],
            onChanged: (value) {
              setState(() {
                _config.chatConfigId = value;
                _config.chatModel = null;
              });
            },
          ),
          SizedBox(height: 10.h),
          Builder(
            builder: (context) {
              final selected = _openAIService.configs.firstWhereOrNull(
                (e) => e.id == _config.chatConfigId,
              );
              final models = selected?.models ?? const <String>[];
              return DropdownButtonFormField<String>(
                key: ValueKey(_config.chatConfigId),
                initialValue: models.contains(_config.chatModel)
                    ? _config.chatModel
                    : null,
                decoration: InputDecoration(
                  labelText: '解析模型（可选）',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                ),
                items: [
                  const DropdownMenuItem<String>(
                      value: null, child: Text('跟随接口默认模型')),
                  ...models.map(
                    (m) => DropdownMenuItem<String>(
                      value: m,
                      child: Text(m),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setState(() => _config.chatModel = value);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackTtsCard() {
    return _sectionCard(
      title: '答题语音反馈',
      icon: Icons.record_voice_over,
      child: Column(
        children: [
          _buildFeedbackField(
            controller: _correctFeedbackController,
            label: '答对反馈',
            fallback: '恭喜答对了',
            loadingKey: 'feedback_correct_preview',
          ),
          SizedBox(height: 10.h),
          _buildFeedbackField(
            controller: _wrongFeedbackController,
            label: '答错反馈',
            fallback: '答错了，继续加油哦',
            loadingKey: 'feedback_wrong_preview',
          ),
          SizedBox(height: 8.h),
          Text(
            '试听和答题反馈会使用生活科学百科的 TTS 引擎；在线 TTS 会保留临时缓存。',
            style: TextStyle(fontSize: 12.sp, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackField({
    required TextEditingController controller,
    required String label,
    required String fallback,
    required String loadingKey,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            minLines: 1,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: label,
              hintText: fallback,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
            ),
          ),
        ),
        SizedBox(width: 8.w),
        SizedBox(
          height: 56.h,
          child: OutlinedButton(
            onPressed: () => _previewFeedback(
              _normalizedFeedback(controller.text, fallback),
              loadingKey,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                const Icon(Icons.play_arrow),
                if (_ttsLoadingKey == loadingKey)
                  Positioned(
                    right: -8.w,
                    top: 4.h,
                    child: SizedBox(
                      width: 9.w,
                      height: 9.w,
                      child: const CircularProgressIndicator(strokeWidth: 1.8),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUrlSyncCard() {
    return _sectionCard(
      title: '题库同步与重置',
      icon: Icons.cloud_download,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _urlController,
            decoration: InputDecoration(
              labelText: '题库 URL（公开 HTTPS GET）',
              hintText: 'https://example.com/encyclopedia.json',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
            ),
          ),
          SizedBox(height: 10.h),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isSyncing ? null : _syncFromUrl,
                  icon: _isSyncing
                      ? SizedBox(
                          width: 14.w,
                          height: 14.w,
                          child:
                              const CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(_isSyncing ? '同步中...' : '覆盖同步'),
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await _service.restoreDefaultQuestions();
                    ToastUtils.showSuccess('已恢复预置 20 题');
                  },
                  icon: const Icon(Icons.restore),
                  label: const Text('重置题库'),
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Text(
            'URL 同步会覆盖本地百科题库；AI 生成题目会追加到现有题库。',
            style: TextStyle(fontSize: 12.sp, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildGenerateCard() {
    return _sectionCard(
      title: 'AI 生成题库',
      icon: Icons.auto_awesome,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _generateCategoryController,
                  decoration: InputDecoration(
                    labelText: '类目',
                    hintText: '如：昆虫、交通安全、宇宙',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: TextField(
                  controller: _generateCountController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: '数量',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          TextField(
            controller: _questionGenPromptController,
            maxLines: 10,
            decoration: InputDecoration(
              labelText: '生成题库 Prompt',
              hintText: '支持占位符：{category} {count}',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
            ),
          ),
          SizedBox(height: 8.h),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isGenerating ? null : _generateQuestions,
                  icon: _isGenerating
                      ? SizedBox(
                          width: 14.w,
                          height: 14.w,
                          child:
                              const CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                  label: Text(_isGenerating ? '生成中...' : '生成并新增'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              SizedBox(width: 8.w),
              OutlinedButton.icon(
                onPressed: () {
                  _questionGenPromptController.text =
                      kDefaultEncyclopediaQuestionGenPromptTemplate;
                },
                icon: const Icon(Icons.restart_alt),
                label: const Text('默认'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCacheCard() {
    return _sectionCard(
      title: '缓存与次数',
      icon: Icons.tune,
      child: Column(
        children: [
          SwitchListTile(
            value: _config.enableAutoRefresh,
            onChanged: (v) => setState(() => _config.enableAutoRefresh = v),
            title: const Text('启用缓存自动过期'),
            subtitle: const Text('关闭后仅手动“重新获取解析”才刷新'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('缓存过期天数'),
            subtitle: Text('当前：${_config.cacheExpiryDays} 天'),
            trailing: IconButton(
              onPressed: () => _showNumberInputDialog(
                title: '设置缓存过期天数',
                initial: _config.cacheExpiryDays,
                min: 1,
                max: 365,
                onConfirm: (v) => setState(() => _config.cacheExpiryDays = v),
              ),
              icon: const Icon(Icons.edit),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('每日限玩次数'),
            subtitle: Text(_config.dailyPlayLimit == 0
                ? '不限制'
                : '当前：${_config.dailyPlayLimit} 次'),
            trailing: IconButton(
              onPressed: () => _showNumberInputDialog(
                title: '设置每日限玩次数（0=不限制）',
                initial: _config.dailyPlayLimit,
                min: 0,
                max: 100,
                onConfirm: (v) => setState(() => _config.dailyPlayLimit = v),
              ),
              icon: const Icon(Icons.edit),
            ),
          ),
          SizedBox(height: 6.h),
          OutlinedButton.icon(
            onPressed: () async {
              await _service.clearAllExplanationCache();
              ToastUtils.showSuccess('已清空百科解析缓存');
            },
            icon: const Icon(Icons.delete_outline),
            label: const Text('清空解析缓存'),
          ),
        ],
      ),
    );
  }

  Widget _buildPromptCard() {
    return _sectionCard(
      title: '解析 Prompt（家长可编辑）',
      icon: Icons.edit_note,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _promptController,
            maxLines: 14,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
              hintText: '支持占位符：{question} {options} {answer} {fallback}',
            ),
          ),
          SizedBox(height: 8.h),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  _promptController.text = kDefaultEncyclopediaPromptTemplate;
                },
                icon: const Icon(Icons.restart_alt),
                label: const Text('恢复默认模板'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20.sp, color: AppTheme.primaryDark),
              SizedBox(width: 8.w),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textMain,
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          child,
        ],
      ),
    );
  }

  Future<void> _showNumberInputDialog({
    required String title,
    required int initial,
    required int min,
    required int max,
    required ValueChanged<int> onConfirm,
  }) async {
    final controller = TextEditingController(text: initial.toString());
    await Get.dialog(
      AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              if (value == null || value < min || value > max) {
                ToastUtils.showWarning('请输入 $min-$max 的数字');
                return;
              }
              onConfirm(value);
              Get.back();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
