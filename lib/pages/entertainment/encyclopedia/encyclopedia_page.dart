import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../../controllers/app_mode_controller.dart';
import '../../../data/hanzi_data.dart';
import '../../../models/encyclopedia_question.dart';
import '../../../services/encyclopedia_service.dart';
import '../../../services/tts_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/tts_engine_selector.dart';
import '../../../widgets/toast_utils.dart';
import 'encyclopedia_settings_page.dart';

class EncyclopediaPage extends StatefulWidget {
  const EncyclopediaPage({super.key});

  @override
  State<EncyclopediaPage> createState() => _EncyclopediaPageState();
}

class _EncyclopediaPageState extends State<EncyclopediaPage> {
  final EncyclopediaService _service = Get.find<EncyclopediaService>();
  final TtsService _tts = Get.find<TtsService>();
  final AppModeController _modeController = Get.find<AppModeController>();

  final List<EncyclopediaQuestion> _questions = [];
  int _currentIndex = 0;
  int? _selectedAnswer;
  bool _showResult = false;
  int _correctCount = 0;

  bool _isLoadingExplanation = false;
  bool _isInitialLoading = true;
  EncyclopediaExplanationResult? _explanation;
  DateTime? _lastFetchAt;
  Timer? _cooldownTimer;
  int _cooldownSeconds = 0;
  String? _ttsLoadingKey;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _tts.stop();
    super.dispose();
  }

  Future<void> _initData() async {
    try {
      await HanziData.loadFromAsset();

      if (!_service.canPlay()) {
        if (mounted) {
          setState(() => _isInitialLoading = false);
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Get.dialog(
            AlertDialog(
              title: const Text('今日已达上限'),
              content: const Text('今天的百科问答次数已用完，明天再来吧。'),
              actions: [
                TextButton(
                  onPressed: () {
                    Get.back();
                    Get.back();
                  },
                  child: const Text('知道了'),
                ),
              ],
            ),
            barrierDismissible: false,
          );
        });
        return;
      }

      final list = _service.questions.toList();
      list.shuffle(Random(DateTime.now().millisecondsSinceEpoch));
      if (!mounted) return;
      setState(() {
        _questions.clear();
        _questions.addAll(list.take(min(10, list.length)));
        _isInitialLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isInitialLoading = false);
      ToastUtils.showError('百科题库加载失败: $e');
    }
  }

  EncyclopediaQuestion? get _currentQuestion {
    if (_questions.isEmpty || _currentIndex >= _questions.length) return null;
    return _questions[_currentIndex];
  }

  Future<void> _speakQuestion() async {
    final q = _currentQuestion;
    if (q == null) return;
    await _speakText(q.question, 'question');
  }

  Future<void> _speakOptions() async {
    final q = _currentQuestion;
    if (q == null) return;
    final labels = ['A', 'B'];
    final text = q.options
        .take(2)
        .toList()
        .asMap()
        .entries
        .map((e) => '${labels[e.key]}、${e.value}')
        .join('，');
    await _speakText(text, 'options');
  }

  Future<void> _speakText(String text, String loadingKey) async {
    if (text.trim().isEmpty) return;
    final showLoading =
        _tts.shouldUseAudioBasedPlayback(featureKey: 'encyclopedia');
    try {
      if (showLoading && mounted) {
        setState(() => _ttsLoadingKey = loadingKey);
        await _tts.prefetchCftts(text, featureKey: 'encyclopedia');
        if (mounted && _ttsLoadingKey == loadingKey) {
          setState(() => _ttsLoadingKey = null);
        }
      }
      await _tts.speak(text, featureKey: 'encyclopedia');
    } catch (e) {
      ToastUtils.showWarning('语音播放失败: $e');
    } finally {
      if (mounted && _ttsLoadingKey == loadingKey) {
        setState(() => _ttsLoadingKey = null);
      }
    }
  }

  void _selectAnswer(int index) {
    if (_showResult) return;
    setState(() => _selectedAnswer = index);
    Future.delayed(const Duration(milliseconds: 220), _checkAnswer);
  }

  void _checkAnswer() {
    final q = _currentQuestion;
    if (!mounted || _showResult) return;
    if (q == null || _selectedAnswer == null) return;

    final isCorrect = _selectedAnswer == q.correctIndex;
    setState(() {
      _showResult = true;
      if (isCorrect) _correctCount++;
    });

    final feedbackText = _feedbackTextForAnswer(isCorrect);
    unawaited(_speakText(
      feedbackText,
      isCorrect ? 'feedback_correct' : 'feedback_wrong',
    ));
    _showExplanationAfterAnswer(q);
  }

  String _feedbackTextForAnswer(bool isCorrect) {
    final config = _service.config.value;
    final raw = isCorrect
        ? config?.correctFeedbackText ?? '恭喜答对了'
        : config?.wrongFeedbackText ?? '答错了，继续加油哦';
    final trimmed = raw.trim();
    if (trimmed.isNotEmpty) return trimmed;
    return isCorrect ? '恭喜答对了' : '答错了，继续加油哦';
  }

  void _showExplanationAfterAnswer(EncyclopediaQuestion question) {
    final builtInExplanation = question.explanation.trim();
    if (builtInExplanation.isNotEmpty) {
      setState(() {
        _explanation = EncyclopediaExplanationResult(
          shortAnswer: '正确答案是：${question.answer}',
          why: builtInExplanation,
          example: '生活中可以多观察类似现象，慢慢你会更理解这个知识点。',
          fromCache: false,
          fromBuiltIn: true,
        );
        _lastFetchAt = null;
      });
      return;
    }

    unawaited(_requestExplanation(
      forceRefresh: false,
      ignoreCooldown: true,
    ));
  }

  void _nextQuestion() {
    _tts.stop();
    if (_currentIndex >= _questions.length - 1) {
      _showFinalResult();
      return;
    }

    setState(() {
      _currentIndex++;
      _selectedAnswer = null;
      _showResult = false;
      _explanation = null;
      _isLoadingExplanation = false;
      _cooldownSeconds = 0;
      _lastFetchAt = null;
    });
    _cooldownTimer?.cancel();
  }

  void _showFinalResult() {
    _service.recordPlay();
    final score = (_correctCount / _questions.length * 100).toInt();
    Get.dialog(
      AlertDialog(
        title: const Text('本轮完成'),
        content:
            Text('答对了 $_correctCount / ${_questions.length} 题\n得分 $score 分'),
        actions: [
          TextButton(
            onPressed: () {
              Get.back();
              Get.back();
            },
            child: const Text('返回'),
          ),
          ElevatedButton(
            onPressed: () {
              Get.back();
              setState(() {
                _currentIndex = 0;
                _selectedAnswer = null;
                _showResult = false;
                _correctCount = 0;
                _explanation = null;
                _isLoadingExplanation = false;
              });
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: const Text('再来一轮'),
          ),
        ],
      ),
      barrierDismissible: false,
    );
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldownSeconds = 5);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_cooldownSeconds <= 1) {
        timer.cancel();
        setState(() => _cooldownSeconds = 0);
      } else {
        setState(() => _cooldownSeconds--);
      }
    });
  }

  Future<void> _requestExplanation({
    required bool forceRefresh,
    bool ignoreCooldown = false,
  }) async {
    final q = _currentQuestion;
    if (q == null) return;
    if (!_showResult) return;
    if (!ignoreCooldown && _cooldownSeconds > 0) return;
    final requestQuestionId = q.id;

    setState(() => _isLoadingExplanation = true);
    try {
      final result =
          await _service.getExplanation(q, forceRefresh: forceRefresh);
      if (!mounted) return;
      if (_currentQuestion?.id != requestQuestionId) return;
      setState(() {
        _explanation = result;
        _lastFetchAt = result.fromBuiltIn ? null : DateTime.now();
      });
      if (result.usedFallback) {
        ToastUtils.showWarning(
            result.fromBuiltIn ? 'AI 解析请求失败，已显示题库内置解析' : 'AI 解析请求失败，已显示基础解析');
      }
      _startCooldown();
    } catch (e) {
      if (mounted) {
        ToastUtils.showError('AI 解析请求失败: $e');
      }
    } finally {
      if (mounted && _currentQuestion?.id == requestQuestionId) {
        setState(() => _isLoadingExplanation = false);
      }
    }
  }

  Future<void> _speakExplanation() async {
    final text = _buildExplanationSpeechText();
    if (text == null) return;
    await _speakText(text, 'explanation_all');
  }

  String? _buildExplanationSpeechText() {
    final explanation = _explanation;
    if (explanation == null) return null;
    return [
      explanation.shortAnswer,
      explanation.why,
      explanation.example,
    ].where((text) => text.trim().isNotEmpty).join('\n\n');
  }

  @override
  Widget build(BuildContext context) {
    final q = _currentQuestion;
    if (q == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('生活科学百科')),
        body: Center(
          child: _isInitialLoading
              ? const CircularProgressIndicator()
              : _buildEmptyState(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFEFF8FF),
      appBar: AppBar(
        title: const Text('生活科学百科'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Container(
            margin: EdgeInsets.only(right: 8.w),
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
            decoration: BoxDecoration(
              color: Colors.blue.shade100,
              borderRadius: BorderRadius.circular(20.r),
            ),
            child: Center(
              child: Text(
                '${_currentIndex + 1}/${_questions.length}',
                style: TextStyle(
                  fontSize: 13.sp,
                  color: Colors.blue.shade900,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          Obx(() => IconButton(
                tooltip: _modeController.isParentMode ? '百科设置' : '儿童模式不可设置',
                onPressed: _modeController.isParentMode
                    ? () => Get.to(() => const EncyclopediaSettingsPage())
                    : () => ToastUtils.showInfo('请切换到家长模式'),
                icon: const Icon(Icons.settings),
              )),
          IconButton(
            tooltip: '语音设置',
            onPressed: _showTtsSettings,
            icon: const Icon(Icons.volume_up),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.all(16.w),
                child: Column(
                  children: [
                    _buildQuestionCard(q),
                    SizedBox(height: 10.h),
                    _buildOptions(q),
                    SizedBox(height: 10.h),
                    if (_showResult) _buildAnswerSummary(q),
                    if (_showResult) SizedBox(height: 10.h),
                    if (_showResult) _buildExplainPanel(q),
                  ],
                ),
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionCard(EncyclopediaQuestion q) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 22.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(q.emoji, style: TextStyle(fontSize: 22.sp)),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  q.category == 'science' ? '科学百科' : '生活常识',
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: Colors.grey[600],
                  ),
                ),
              ),
              _buildIconButton(
                tooltip: '朗读题目',
                onPressed: _speakQuestion,
                icon: Icons.volume_up,
                loadingKey: 'question',
              ),
              _buildIconButton(
                tooltip: '朗读选项',
                onPressed: _speakOptions,
                icon: Icons.record_voice_over,
                loadingKey: 'options',
              ),
            ],
          ),
          SizedBox(height: 10.h),
          _PinyinText(
            text: q.question,
            fontSize: 25.sp,
            pinyinSize: 11.sp,
            lineSpacing: 8.h,
            color: AppTheme.textMain,
            pinyinColor: Colors.grey[600]!,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: EdgeInsets.all(24.w),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('🌍', style: TextStyle(fontSize: 48.sp)),
          SizedBox(height: 12.h),
          Text(
            '还没有可用的百科题目',
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.bold,
              color: AppTheme.textMain,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            '请到百科设置中同步题库，或恢复预置题库。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.sp, color: Colors.grey[600]),
          ),
          SizedBox(height: 16.h),
          Obx(
            () => _modeController.isParentMode
                ? ElevatedButton.icon(
                    onPressed: () async {
                      await _service.restoreDefaultQuestions();
                      await _initData();
                    },
                    icon: const Icon(Icons.restore),
                    label: const Text('恢复预置题库'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildOptions(EncyclopediaQuestion q) {
    return Column(
      children: List.generate(q.options.take(2).length, (index) {
        final isSelected = _selectedAnswer == index;
        final isCorrect = index == q.correctIndex;
        final showCorrect = _showResult && isCorrect;
        final showWrong = _showResult && isSelected && !isCorrect;

        final borderColor = showCorrect
            ? Colors.green
            : showWrong
                ? Colors.red
                : isSelected
                    ? Colors.blue
                    : Colors.grey.shade300;
        final bgColor = showCorrect
            ? Colors.green.shade50
            : showWrong
                ? Colors.red.shade50
                : isSelected
                    ? Colors.blue.shade50
                    : Colors.white;

        return Padding(
          padding: EdgeInsets.only(bottom: 8.h),
          child: GestureDetector(
            onTap: () => _selectAnswer(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(color: borderColor, width: 1.8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 28.w,
                    height: 28.w,
                    decoration: BoxDecoration(
                      color: borderColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Center(
                      child: Text(
                        String.fromCharCode(65 + index),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: borderColor,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: _PinyinText(
                      text: q.options[index],
                      fontSize: 15.sp,
                      pinyinSize: 8.sp,
                      lineSpacing: 4.h,
                      color: AppTheme.textMain,
                      pinyinColor: Colors.grey[600]!,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildAnswerSummary(EncyclopediaQuestion q) {
    final isCorrect = _selectedAnswer == q.correctIndex;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: isCorrect ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: isCorrect ? Colors.green.shade300 : Colors.orange.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isCorrect ? '答对了' : '答错了',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: isCorrect ? Colors.green.shade800 : Colors.orange.shade900,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            '正确答案：${q.answer}',
            style: TextStyle(
              fontSize: 15.sp,
              color: AppTheme.textMain,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExplainPanel(EncyclopediaQuestion q) {
    final canRetry = _cooldownSeconds == 0;
    final hasExplanation = _explanation != null;
    final sourceLabel = _explanation?.fromBuiltIn == true
        ? '题库'
        : _explanation?.fromCache == true
            ? '缓存'
            : _lastFetchAt != null
                ? '实时'
                : null;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'AI 解析',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade900,
                ),
              ),
              const Spacer(),
              if (sourceLabel != null)
                Text(
                  sourceLabel,
                  style: TextStyle(fontSize: 12.sp, color: Colors.grey[600]),
                ),
              if (hasExplanation && !_isLoadingExplanation)
                _buildIconButton(
                  tooltip: '朗读解析',
                  onPressed: _speakExplanation,
                  icon: Icons.volume_up,
                  loadingKey: 'explanation_all',
                  size: 19.sp,
                ),
            ],
          ),
          SizedBox(height: 8.h),
          if (!hasExplanation && !_isLoadingExplanation)
            Text(
              '正在准备解析，稍等一下。',
              style: TextStyle(fontSize: 13.sp, color: Colors.grey[600]),
            ),
          if (_isLoadingExplanation)
            Row(
              children: [
                SizedBox(
                  width: 16.w,
                  height: 16.w,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8.w),
                Text(
                  '正在生成解析...',
                  style: TextStyle(fontSize: 13.sp, color: Colors.grey[700]),
                ),
              ],
            ),
          if (hasExplanation && !_isLoadingExplanation) ...[
            _buildExplainBlock('一句话答案', _explanation!.shortAnswer),
            _buildExplainBlock('为什么', _explanation!.why),
            _buildExplainBlock('生活例子', _explanation!.example),
          ],
          SizedBox(height: 8.h),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _isLoadingExplanation || !canRetry
                    ? null
                    : () => _requestExplanation(
                          forceRefresh: hasExplanation,
                        ),
                icon: Icon(hasExplanation ? Icons.refresh : Icons.auto_awesome),
                label: Text(
                  hasExplanation ? '重新解析' : '获取解析',
                  style: TextStyle(fontSize: 13.sp),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                ),
              ),
              SizedBox(width: 10.w),
              if (!canRetry)
                Text(
                  '$_cooldownSeconds 秒后可重试',
                  style: TextStyle(fontSize: 12.sp, color: Colors.grey[600]),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExplainBlock(String title, String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13.sp,
              color: Colors.blue.shade700,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 2.h),
          Text(
            text,
            style: TextStyle(
              fontSize: 14.sp,
              color: AppTheme.textMain,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22.r)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 12.h),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(14.r),
              ),
              child: Text(
                '答对 $_correctCount 题',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.sp,
                  color: Colors.amber.shade900,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: ElevatedButton(
              onPressed: _showResult ? _nextQuestion : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 14.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14.r),
                ),
              ),
              child: Text(
                _currentIndex < _questions.length - 1 ? '下一题' : '查看结果',
                style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required String tooltip,
    required VoidCallback onPressed,
    required IconData icon,
    required String loadingKey,
    double? size,
  }) {
    final isLoading = _ttsLoadingKey == loadingKey;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(icon, size: size),
          if (isLoading)
            Positioned(
              right: -2.w,
              top: -2.h,
              child: SizedBox(
                width: 9.w,
                height: 9.w,
                child: const CircularProgressIndicator(strokeWidth: 1.8),
              ),
            ),
        ],
      ),
    );
  }

  void _showTtsSettings() {
    Get.bottomSheet(
      Container(
        padding: EdgeInsets.all(24.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24.r),
            topRight: Radius.circular(24.r),
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '语音设置',
                    style: TextStyle(
                      fontSize: 20.sp,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textMain,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      _tts.setSpeechRate(0.5);
                      _tts.setPitch(1.0);
                      _tts.setVolume(1.0);
                    },
                    child: const Text('重置'),
                  ),
                ],
              ),
              SizedBox(height: 20.h),
              Container(
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20.r),
                  border: Border.all(color: Colors.grey.shade100),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '生活科学百科使用 TTS 引擎',
                        style: TextStyle(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _speakText(
                        '小朋友，一起来学习生活和科学百科吧。',
                        'tts_test',
                      ),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('试听'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 20.h),
              const TtsEngineSelector(
                featureKey: 'encyclopedia',
                title: '当前功能 TTS 引擎',
              ),
              SizedBox(height: 20.h),
              Obx(
                () => _tts.engines.isEmpty
                    ? const SizedBox.shrink()
                    : Column(
                        children: [
                          _buildSystemEngineControl(),
                          SizedBox(height: 14.h),
                        ],
                      ),
              ),
              _buildSliderControl(
                icon: Icons.speed,
                title: '语速',
                value: _tts.speechRate,
                min: 0.0,
                max: 1.0,
                label: '1.0 为正常语速',
                color: Colors.blue,
                onChanged: (val) => _tts.setSpeechRate(val),
              ),
              SizedBox(height: 14.h),
              _buildSliderControl(
                icon: Icons.music_note,
                title: '音调',
                value: _tts.pitch,
                min: 0.5,
                max: 2.0,
                label: '1.0 为正常音调',
                color: Colors.blue,
                onChanged: (val) => _tts.setPitch(val),
              ),
              SizedBox(height: 14.h),
              _buildSliderControl(
                icon: Icons.volume_up,
                title: '音量',
                value: _tts.volume,
                min: 0.0,
                max: 1.0,
                label: '1.0 为最大音量',
                color: Colors.blue,
                onChanged: (val) => _tts.setVolume(val),
              ),
            ],
          ),
        ),
      ),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  Widget _buildSystemEngineControl() {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.settings_voice, color: Colors.grey, size: 20.sp),
              SizedBox(width: 8.w),
              Text(
                '系统语音引擎',
                style: TextStyle(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textMain,
                ),
              ),
              const Spacer(),
              Obx(() => Text(
                    _tts.getEngineDisplayName(_tts.currentEngine.value),
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  )),
            ],
          ),
          SizedBox(height: 10.h),
          Obx(
            () => Wrap(
              spacing: 8.w,
              runSpacing: 8.h,
              children: _tts.engines.map((engine) {
                final selected = _tts.currentEngine.value == engine;
                return ChoiceChip(
                  label: Text(_tts.getEngineDisplayName(engine)),
                  selected: selected,
                  onSelected: (value) async {
                    if (!value) return;
                    await _tts.setEngine(engine);
                    await _speakText(
                      '已切换到 ${_tts.getEngineDisplayName(engine)}',
                      'tts_engine_$engine',
                    );
                  },
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderControl({
    required IconData icon,
    required String title,
    required RxDouble value,
    required double min,
    required double max,
    required String label,
    required Color color,
    Function(double)? onChanged,
  }) {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.grey, size: 20.sp),
              SizedBox(width: 8.w),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textMain,
                ),
              ),
              const Spacer(),
              Obx(() => Text(
                    value.value.toStringAsFixed(1),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  )),
            ],
          ),
          Obx(() => Slider(
                value: value.value,
                min: min,
                max: max,
                activeColor: color,
                onChanged: (v) {
                  value.value = v;
                  onChanged?.call(v);
                },
              )),
          Text(
            label,
            style: TextStyle(fontSize: 12.sp, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _PinyinText extends StatelessWidget {
  final String text;
  final double fontSize;
  final double pinyinSize;
  final double lineSpacing;
  final Color color;
  final Color pinyinColor;

  const _PinyinText({
    required this.text,
    required this.fontSize,
    required this.pinyinSize,
    required this.lineSpacing,
    required this.color,
    required this.pinyinColor,
  });

  @override
  Widget build(BuildContext context) {
    final chars = text.split('');
    final List<Widget> line = [];
    final List<Widget> blocks = [];

    void flushLine() {
      if (line.isEmpty) return;
      blocks.add(
        Wrap(
          spacing: 1.w,
          runSpacing: lineSpacing,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: List.of(line),
        ),
      );
      line.clear();
    }

    for (final c in chars) {
      if (c == '\n' || c == '\r') {
        flushLine();
        blocks.add(SizedBox(height: 10.h));
        continue;
      }
      final pinyin = RegExp(r'[\u4e00-\u9fff]').hasMatch(c)
          ? HanziData.getPinyin(c)
          : null;
      final hasPinyin = pinyin != null && pinyin.trim().isNotEmpty;
      line.add(
        Container(
          padding: EdgeInsets.symmetric(horizontal: 1.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(
                opacity: hasPinyin ? 1 : 0,
                child: Text(
                  hasPinyin ? pinyin : 'a',
                  style: TextStyle(
                    fontSize: pinyinSize,
                    color: pinyinColor,
                  ),
                ),
              ),
              Text(
                c,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                  color: color,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      );
    }
    flushLine();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }
}
