import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../data/quiz_data.dart';
import '../../../theme/app_theme.dart';
import '../../../services/tts_service.dart';
import '../../../services/quiz_service.dart';
import '../../../widgets/toast_utils.dart';
import '../../../services/openai_service.dart';
import '../../../controllers/app_mode_controller.dart';
import 'quiz_ai_settings_page.dart';
import 'package:http/http.dart' as http;
import '../../../models/quiz_question.dart';
import 'quiz_management_page.dart';
import '../../../widgets/tts_engine_selector.dart';

/// 小年兽问答页面
class QuizPage extends StatefulWidget {
  const QuizPage({super.key});

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> with TickerProviderStateMixin {
  // 使用全局 TTS 服务
  final TtsService _tts = Get.find<TtsService>();
  final QuizService _quizService = Get.find<QuizService>();
  final OpenAIService _openAIService = Get.find<OpenAIService>();
  final AppModeController _modeController = Get.find<AppModeController>();

  // 题目列表
  late List<Map<String, dynamic>> _questions;

  // 当前题目索引
  int _currentIndex = 0;

  // 是否已选择答案
  int? _selectedAnswer;

  // 是否显示结果
  bool _showResult = false;

  // 答对题数
  int _correctCount = 0;

  // 小年兽动画控制器
  late AnimationController _beastController;
  late Animation<double> _beastAnimation;

  // 烟花动画控制器
  late AnimationController _fireworkController;

  // 答案卡片动画控制器
  late AnimationController _cardController;

  @override
  void initState() {
    super.initState();

    // 检查游玩次数
    if (!_quizService.canPlay()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Get.dialog(
          AlertDialog(
            title: const Text('今日已达上限'),
            content: Text('今日游玩次数已用完\n明天再来挑战吧!'),
            actions: [
              TextButton(
                onPressed: () {
                  Get.back(); // 关闭对话框
                  Get.back(); // 返回上一页
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

    // 从QuizService获取题目并转换为Map格式
    if (_quizService.questions.isEmpty) {
      // 如果QuizService的题目列表为空,使用QuizData的默认题目
      _questions = QuizData.getRandomQuestions(10);
    } else {
      // 从QuizService获取题目并转换为Map格式
      final quizQuestions = _quizService.questions.toList()..shuffle();
      _questions = quizQuestions.take(10).map((q) {
        return {
          'id': q.id,
          'question': q.question,
          'emoji': q.emoji,
          'imagePath': q.imagePath,
          'options': q.options,
          'correctIndex': q.correctIndex,
          'explanation': q.explanation,
          'category': q.category,
        };
      }).toList();
    }

    // 最终检查:如果_questions仍然为空,显示错误并返回
    if (_questions.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Get.dialog(
          AlertDialog(
            title: const Text('初始化失败'),
            content: const Text('无法加载题目,请检查题库配置'),
            actions: [
              TextButton(
                onPressed: () {
                  Get.back(); // 关闭对话框
                  Get.back(); // 返回上一页
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

    // 初始化小年兽动画(跳跃)
    _beastController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _beastAnimation = Tween<double>(begin: 0, end: -20).animate(
      CurvedAnimation(parent: _beastController, curve: Curves.easeInOut),
    );

    // 初始化烟花动画
    _fireworkController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    // 初始化卡片动画
    _cardController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    // 小年兽欢迎跳跃
    _playBeastJump();
  }

  @override
  void dispose() {
    _tts.stop();
    _beastController.dispose();
    _fireworkController.dispose();
    _cardController.dispose();
    super.dispose();
  }

  /// 小年兽跳跃动画
  void _playBeastJump() {
    _beastController.forward().then((_) {
      _beastController.reverse();
    });
  }

  /// 播放题目(只播报题目内容)
  Future<void> _speakQuestion() async {
    final question = _questions[_currentIndex];
    // 只播报题目
    await _tts.speak(question['question'], featureKey: 'quiz');
  }

  /// 播放答案
  Future<void> _speakAnswer() async {
    final question = _questions[_currentIndex];
    final options = question['options'] as List;
    final correctIndex = question['correctIndex'] as int;
    final correctAnswer = options[correctIndex];

    // 播报正确答案
    await _tts.speak('正确答案是: $correctAnswer', featureKey: 'quiz');
  }

  /// 播放答案选项(只播报选项,不播报题目)
  Future<void> _speakOptions() async {
    final question = _questions[_currentIndex];
    final options = question['options'] as List;

    // 将所有选项合并成一句话播放,避免被中断
    final optionLabels = ['A', 'B', 'C', 'D'];
    final optionsText = StringBuffer();
    for (int i = 0; i < options.length; i++) {
      if (i > 0) optionsText.write(',  ');
      optionsText.write('${optionLabels[i]}、${options[i]}');
    }

    await _tts.speak(optionsText.toString(), featureKey: 'quiz');
  }

  /// 重播知识点
  Future<void> _replayExplanation() async {
    final question = _questions[_currentIndex];
    await _tts.speak(question['explanation'], featureKey: 'quiz');
  }

  /// 重新生成当前题目的图片
  Future<void> _regenerateCurrentImage() async {
    try {
      // 获取当前题目数据
      final currentQuestion = _questions[_currentIndex];
      final questionId = currentQuestion['id'] as String?;

      // 检查OpenAI配置
      if (_openAIService.configs.isEmpty) {
        ToastUtils.showWarning('请先配置OpenAI接口');
        return;
      }

      // 获取配置（优先使用QuizConfig中的图片生成配置）
      final quizConfig = _quizService.config.value;
      if (quizConfig == null || !quizConfig.enableImageGen) {
        ToastUtils.showWarning('未启用图片生成功能');
        return;
      }

      final imageGenConfig = _openAIService.configs
          .firstWhereOrNull((c) => c.id == quizConfig.imageGenConfigId);
      if (imageGenConfig == null) {
        ToastUtils.showWarning('未配置生图AI');
        return;
      }

      // 显示加载对话框
      Get.dialog(
        AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              SizedBox(height: 16.h),
              const Text("正在生成图片提示词...", style: TextStyle(fontSize: 16)),
              SizedBox(height: 8.h),
              Text(
                "生成过程可能需要 1-2 分钟，请耐心等待",
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        barrierDismissible: false,
      );

      // 构建知识点
      final questionText = currentQuestion['question'] as String? ?? '';
      final options = currentQuestion['options'] as List? ?? [];
      final correctIndex = currentQuestion['correctIndex'] as int? ?? 0;
      final explanation = currentQuestion['explanation'] as String? ?? '';

      final knowledge =
          '$questionText\n答案: ${options.isNotEmpty && correctIndex < options.length ? options[correctIndex] : ''}\n解释: $explanation';
      final userPrompt =
          quizConfig.imageGenPrompt.replaceAll('{knowledge}', knowledge);

      // 生成图片提示词
      final imagePrompt = await _openAIService.chat(
        systemPrompt:
            '你是一个专业的儿童插画提示词生成专家。请根据用户提供的内容生成适合 DALL-E 或 Stable Diffusion 的英文提示词。\n\n'
            '严格要求:\n'
            '1. 必须使用可爱、卡通、儿童插画风格\n'
            '2. 色彩明亮温暖,画面简洁清晰\n'
            '3. 严格禁止任何暴力、恐怖、成人或不适合儿童的内容\n'
            '4. 使用圆润可爱的造型,避免尖锐或恐怖元素\n'
            '5. 符合中国传统新年文化,展现节日喜庆氛围\n'
            '6. 适合3-8岁儿童观看\n\n'
            '只返回英文提示词本身,不要有其他说明。提示词中应包含: cute, cartoon, children illustration, colorful, warm, simple, Chinese New Year 等关键词。',
        userMessage: userPrompt,
        config: imageGenConfig,
      );

      debugPrint('生成的图片提示词: $imagePrompt');

      // 更新对话框提示
      if (Get.isDialogOpen ?? false) Get.back();
      Get.dialog(
        AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              SizedBox(height: 16.h),
              const Text("正在生成图片...", style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
        barrierDismissible: false,
      );

      // 直接调用生图API
      final imageUrls = await _openAIService.generateImages(
        prompt: imagePrompt,
        n: 1,
        config: imageGenConfig,
        model: quizConfig.imageGenModel,
      );

      if (imageUrls.isEmpty) {
        throw Exception('未能生成图片');
      }

      final rawImageUrl = imageUrls.first;
      String savedImagePath = rawImageUrl;

      // 如果返回的是 URL，下载并转换为 Base64 以防止过期
      if (!rawImageUrl.startsWith('data:image')) {
        try {
          final response = await http
              .get(Uri.parse(rawImageUrl))
              .timeout(const Duration(seconds: 60));
          if (response.statusCode == 200) {
            final base64String = base64Encode(response.bodyBytes);
            savedImagePath = 'data:image/png;base64,$base64String';
          }
        } catch (e) {
          debugPrint('图片转存失败，将使用原始URL: $e');
        }
      }

      // 查找或创建 QuizQuestion 对象
      // 如果是默认题目（不在数据库中），则新建并加入数据库
      QuizQuestion? quizQuestion;
      if (questionId != null) {
        quizQuestion =
            _quizService.questions.firstWhereOrNull((q) => q.id == questionId);
      }

      if (quizQuestion == null) {
        // 创建新题目对象
        final newId =
            questionId ?? DateTime.now().millisecondsSinceEpoch.toString();
        quizQuestion = QuizQuestion(
          id: newId,
          question: questionText,
          emoji: currentQuestion['emoji'] ?? '🧧',
          options: List<String>.from(options.map((e) => e.toString())),
          correctIndex: correctIndex,
          explanation: explanation,
          category: currentQuestion['category'] ?? '默认',
          createdAt: DateTime.now(),
        );
        // 添加到服务（保存到 Hive）
        await _quizService.addQuestion(quizQuestion);

        // 更新当前 map 的 ID，以免下次再次创建
        currentQuestion['id'] = newId;
      }

      // 更新题目图片
      quizQuestion.imagePath = savedImagePath;
      quizQuestion.imageStatus = 'success';
      quizQuestion.imageError = null;
      quizQuestion.updatedAt = DateTime.now();
      await quizQuestion.save();
      _quizService.questions.refresh();

      // 关闭加载对话框
      if (Get.isDialogOpen ?? false) Get.back();

      // 更新当前界面显示的图片路径
      setState(() {
        currentQuestion['imagePath'] = quizQuestion!.imagePath;
      });

      ToastUtils.showSuccess('图片生成成功!');
    } catch (e) {
      // 关闭加载对话框
      if (Get.isDialogOpen ?? false) Get.back();

      // 显示错误提示
      ToastUtils.showError('生成失败: $e');

      debugPrint('生成图片失败: $e');
    }
  }

  /// 选择答案
  void _selectAnswer(int index) {
    if (_showResult) return;

    setState(() {
      _selectedAnswer = index;
    });

    // 延迟显示结果
    Future.delayed(const Duration(milliseconds: 300), () {
      _checkAnswer();
    });
  }

  /// 检查答案
  void _checkAnswer() {
    final question = _questions[_currentIndex];
    final isCorrect = _selectedAnswer == question['correctIndex'];

    setState(() {
      _showResult = true;
      if (isCorrect) {
        _correctCount++;
      }
    });

    // 播放动画和语音
    if (isCorrect) {
      _playBeastJump();
      _fireworkController.forward(from: 0);
      _tts.speak('答对啦!真棒!${question['explanation']}', featureKey: 'quiz');
    } else {
      // 答错后先说鼓励的话,停顿1秒,再播放知识点
      _speakWrongAnswer();
    }
  }

  /// 播放答错提示(带停顿)
  Future<void> _speakWrongAnswer() async {
    final question = _questions[_currentIndex];
    await _tts.speak('没关系,再听听', featureKey: 'quiz');
    await Future.delayed(const Duration(seconds: 1)); // 停顿1秒
    await _tts.speak(question['explanation'], featureKey: 'quiz');
  }

  /// 下一题
  void _nextQuestion() {
    _tts.stop();

    if (_currentIndex < _questions.length - 1) {
      setState(() {
        _currentIndex++;
        _selectedAnswer = null;
        _showResult = false;
      });
      _cardController.forward(from: 0);
      _playBeastJump();
    } else {
      _showFinalResult();
    }
  }

  /// 显示最终结果
  void _showFinalResult() {
    final score = (_correctCount / _questions.length * 100).toInt();

    // 记录一次游玩
    _quizService.recordPlay();

    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24.r),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 小年兽庆祝
            Text(
              '🎉',
              style: TextStyle(fontSize: 80.sp),
            ),
            SizedBox(height: 16.h),
            Text(
              '太棒啦!',
              style: TextStyle(
                fontSize: 24.sp,
                fontWeight: FontWeight.bold,
                color: AppTheme.textMain,
              ),
            ),
            SizedBox(height: 12.h),
            Text(
              '答对了 $_correctCount / ${_questions.length} 题',
              style: TextStyle(
                fontSize: 18.sp,
                color: Colors.grey[700],
              ),
            ),

            SizedBox(height: 20.h),
            // 评价
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Text(
                _getComment(score),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.sp,
                  color: Colors.amber.shade900,
                ),
              ),
            ),
          ],
        ),
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
                _questions = QuizData.getRandomQuestions(10);
                _currentIndex = 0;
                _selectedAnswer = null;
                _showResult = false;
                _correctCount = 0;
              });
              _playBeastJump();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
            ),
            child: const Text('再玩一次'),
          ),
        ],
      ),
      barrierDismissible: false,
    );

    _tts.speak('太棒啦!你答对了$_correctCount题!${_getComment(score)}', featureKey: 'quiz');
  }

  /// 根据分数获取评价
  String _getComment(int score) {
    if (score >= 90) {
      return '你真是新年知识小达人!';
    } else if (score >= 70) {
      return '很不错哦,继续加油!';
    } else if (score >= 50) {
      return '还不错,多学习就会更棒!';
    } else {
      return '没关系,慢慢来,每天都在进步!';
    }
  }

  @override
  Widget build(BuildContext context) {
    final question = _questions[_currentIndex];

    return Scaffold(
      backgroundColor: const Color(0xFFFFF3E0),
      appBar: AppBar(
        title: const Text('新年知多少'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          // 进度显示
          Container(
            margin: EdgeInsets.only(right: 16.w),
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
            decoration: BoxDecoration(
              color: Colors.deepOrange.shade100,
              borderRadius: BorderRadius.circular(20.r),
            ),
            child: Text(
              '${_currentIndex + 1}/${_questions.length}',
              style: TextStyle(
                color: Colors.deepOrange.shade800,
                fontWeight: FontWeight.bold,
                fontSize: 14.sp,
              ),
            ),
          ),
          // 题库管理按钮
          IconButton(
            onPressed: () {
              Get.to(() => const QuizManagementPage());
            },
            icon: const Icon(Icons.library_books),
            tooltip: '题库管理',
          ),
          // 语音设置按钮
          IconButton(
            icon: const Icon(Icons.volume_up),
            tooltip: '语音设置',
            onPressed: _showTtsSettings,
          ),
          // AI设置按钮
          IconButton(
            onPressed: () {
              Get.to(() => const QuizAISettingsPage());
            },
            icon: const Icon(Icons.settings),
            tooltip: 'AI设置',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 小年兽
            // _buildBeast(),

            // SizedBox(height: 20.h),

            // 主内容区域
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: Column(
                  children: [
                    // 题目卡片
                    _buildQuestionCard(question),

                    SizedBox(height: 20.h),

                    // 选项列表
                    _buildOptions(question),

                    SizedBox(height: 20.h),

                    // 结果区域
                    if (_showResult) _buildResultCard(question),

                    SizedBox(height: 20.h),
                  ],
                ),
              ),
            ),

            // 底部按钮
            _buildBottomButtons(),
          ],
        ),
      ),
    );
  }

  /// 小年兽
  Widget _buildBeast() {
    return AnimatedBuilder(
      animation: _beastAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _beastAnimation.value),
          child: Container(
            padding: EdgeInsets.symmetric(
                horizontal: 20.w, vertical: 8.h), // 减小垂直padding
            child: Column(
              children: [
                // 小年兽表情 - 缩小
                Text(
                  _showResult
                      ? (_selectedAnswer ==
                              _questions[_currentIndex]['correctIndex']
                          ? '😊' // 开心
                          : '🤗') // 鼓励
                      : '🧧', // 默认
                  style: TextStyle(fontSize: 32.sp), // 从40进一步减小到32
                ),
                SizedBox(height: 6.h), // 从4减小到6保持视觉平衡
                // 小年兽说话 - 缩小
                Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: 10.w, vertical: 4.h), // 缩小padding
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12.r), // 缩小圆角
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    _showResult
                        ? (_selectedAnswer ==
                                _questions[_currentIndex]['correctIndex']
                            ? '答对啦!真棒!'
                            : '没关系,再听听~')
                        : '来挑战新年知识吧!',
                    style: TextStyle(
                      fontSize: 11.sp, // 从12减小到11
                      color: AppTheme.textMain,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 构建图片组件
  Widget _buildImageWidget(String path,
      {String? emoji, BoxFit fit = BoxFit.cover}) {
    Widget errorWidget = Center(
      child: emoji != null
          ? Text(emoji, style: TextStyle(fontSize: 64.sp))
          : const Icon(Icons.error, color: Colors.grey),
    );

    try {
      // 1. Base64 格式 (Web 或 Android/iOS 保存的 Base64 字符串)
      if (path.startsWith('data:image')) {
        final base64Data = path.split(',')[1];
        final bytes = base64Decode(base64Data);
        return Image.memory(
          bytes,
          fit: fit,
          errorBuilder: (_, __, ___) => errorWidget,
        );
      }
      // 2. 网络图片
      else if (path.startsWith('http://') || path.startsWith('https://')) {
        return Image.network(
          path,
          fit: fit,
          errorBuilder: (_, __, ___) => errorWidget,
        );
      }
      // 3. 本地文件 (旧数据或特定导入)
      else {
        return Image.file(
          File(path),
          fit: fit,
          errorBuilder: (_, __, ___) => errorWidget,
        );
      }
    } catch (e) {
      debugPrint('图片加载失败: $path, error: $e');
      return errorWidget;
    }
  }

  /// 查看大图
  void _showFullScreenImage(BuildContext context, String imageSource) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            iconTheme: const IconThemeData(color: Colors.white),
            elevation: 0,
          ),
          extendBodyBehindAppBar: true,
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: _buildImageWidget(imageSource, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  /// 题目卡片
  Widget _buildQuestionCard(Map<String, dynamic> question) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(24.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24.r),
        boxShadow: [
          BoxShadow(
            color: Colors.deepOrange.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          // Emoji 图标 或 图片
          if (question['imagePath'] != null)
            Container(
              width: double.infinity,
              margin: EdgeInsets.only(bottom: 16.h),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16.r),
                child: GestureDetector(
                  onTap: () => _showFullScreenImage(
                      context, question['imagePath'] as String),
                  child: AspectRatio(
                    aspectRatio: 1.0,
                    child: _buildImageWidget(
                      question['imagePath'] as String,
                      emoji: question['emoji'],
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            )
          else
            Text(
              question['emoji'],
              style: TextStyle(fontSize: 64.sp),
            ),
          SizedBox(height: 16.h),

          // 问题文本
          Text(
            question['question'],
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20.sp,
              fontWeight: FontWeight.bold,
              color: AppTheme.textMain,
              height: 1.5,
            ),
          ),
          SizedBox(height: 16.h),

          // 语音播放按钮组
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 听题目按钮
              Obx(() => OutlinedButton.icon(
                    onPressed: _speakQuestion,
                    icon: Icon(
                      _tts.isSpeaking.value ? Icons.stop : Icons.volume_up,
                      size: 18.sp,
                    ),
                    label: Text(_tts.isSpeaking.value ? '停止' : '听题目'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.deepOrange,
                      side: BorderSide(color: Colors.deepOrange.shade200),
                      padding: EdgeInsets.symmetric(
                        horizontal: 16.w,
                        vertical: 8.h,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20.r),
                      ),
                    ),
                  )),
              SizedBox(width: 12.w),
              // 听选项按钮
              OutlinedButton.icon(
                onPressed: _speakOptions,
                icon: Icon(
                  Icons.list_alt,
                  size: 18.sp,
                ),
                label: const Text('听选项'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue,
                  side: BorderSide(color: Colors.blue.shade200),
                  padding: EdgeInsets.symmetric(
                    horizontal: 16.w,
                    vertical: 8.h,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                ),
              ),
            ],
          ),

          // 重新生成图片按钮(仅家长模式)
          Obx(() {
            if (!_modeController.isParentMode) {
              return const SizedBox.shrink();
            }

            return Padding(
              padding: EdgeInsets.only(top: 12.h),
              child: OutlinedButton.icon(
                onPressed: _regenerateCurrentImage,
                icon: Icon(
                  Icons.auto_awesome,
                  size: 18.sp,
                  color: const Color(0xFF9C27B0),
                ),
                label: const Text('重新生成图片'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF9C27B0),
                  side: BorderSide(
                      color: const Color(0xFF9C27B0).withOpacity(0.5)),
                  padding: EdgeInsets.symmetric(
                    horizontal: 16.w,
                    vertical: 8.h,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  /// 选项列表
  Widget _buildOptions(Map<String, dynamic> question) {
    final options = question['options'] as List;
    final correctIndex = question['correctIndex'] as int;

    return Column(
      children: List.generate(options.length, (index) {
        final isSelected = _selectedAnswer == index;
        final isCorrect = index == correctIndex;
        final showCorrect = _showResult && isCorrect;
        final showWrong = _showResult && isSelected && !isCorrect;

        Color backgroundColor;
        Color borderColor;
        Color textColor;
        String emoji;

        if (showCorrect) {
          backgroundColor = Colors.green.shade50;
          borderColor = Colors.green;
          textColor = Colors.green.shade900;
          emoji = '✅';
        } else if (showWrong) {
          backgroundColor = Colors.red.shade50;
          borderColor = Colors.red;
          textColor = Colors.red.shade900;
          emoji = '❌';
        } else if (isSelected) {
          backgroundColor = Colors.deepOrange.shade50;
          borderColor = Colors.deepOrange;
          textColor = Colors.deepOrange.shade900;
          emoji = '';
        } else {
          backgroundColor = Colors.white;
          borderColor = Colors.grey.shade300;
          textColor = AppTheme.textMain;
          emoji = '';
        }

        return Padding(
          padding: EdgeInsets.only(bottom: 12.h),
          child: GestureDetector(
            onTap: () => _selectAnswer(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: double.infinity,
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(20.r),
                border: Border.all(color: borderColor, width: 2),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: borderColor.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : [],
              ),
              child: Row(
                children: [
                  // 选项标签
                  Container(
                    width: 32.w,
                    height: 32.w,
                    decoration: BoxDecoration(
                      color: borderColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Center(
                      child: Text(
                        String.fromCharCode(65 + index), // A, B, C, D
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12.w),

                  // 选项文本
                  Expanded(
                    child: Text(
                      options[index],
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ),

                  // 结果图标
                  if (emoji.isNotEmpty)
                    Text(
                      emoji,
                      style: TextStyle(fontSize: 24.sp),
                    ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  /// 结果卡片
  Widget _buildResultCard(Map<String, dynamic> question) {
    final isCorrect = _selectedAnswer == question['correctIndex'];

    return AnimatedOpacity(
      opacity: _showResult ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 500),
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(20.w),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isCorrect
                    ? [Colors.green.shade50, Colors.teal.shade50]
                    : [Colors.orange.shade50, Colors.amber.shade50],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24.r),
              border: Border.all(
                color:
                    isCorrect ? Colors.green.shade200 : Colors.orange.shade200,
                width: 2,
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isCorrect ? Icons.check_circle : Icons.lightbulb,
                      color: isCorrect ? Colors.green : Colors.orange,
                      size: 24.sp,
                    ),
                    SizedBox(width: 8.w),
                    Text(
                      isCorrect ? '答对啦!' : '知识点',
                      style: TextStyle(
                        fontSize: 18.sp,
                        fontWeight: FontWeight.bold,
                        color: isCorrect
                            ? Colors.green.shade800
                            : Colors.orange.shade800,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12.h),
                Text(
                  question['explanation'],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15.sp,
                    color: AppTheme.textMain,
                    height: 1.6,
                  ),
                ),
                SizedBox(height: 12.h),
                // 按钮组
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 播放答案按钮
                    OutlinedButton.icon(
                      onPressed: _speakAnswer,
                      icon: Icon(Icons.volume_up, size: 16.sp),
                      label: const Text('播放答案'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green,
                        side: BorderSide(color: Colors.green.shade200),
                        padding: EdgeInsets.symmetric(
                          horizontal: 12.w,
                          vertical: 6.h,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16.r),
                        ),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    // 重播知识点按钮
                    OutlinedButton.icon(
                      onPressed: _replayExplanation,
                      icon: Icon(Icons.replay, size: 16.sp),
                      label: const Text('重播知识点'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blue,
                        side: BorderSide(color: Colors.blue.shade200),
                        padding: EdgeInsets.symmetric(
                          horizontal: 12.w,
                          vertical: 6.h,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16.r),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 烟花效果(答对时)
          if (isCorrect)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _fireworkController,
                builder: (context, child) {
                  return Opacity(
                    opacity: 1 - _fireworkController.value,
                    child: CustomPaint(
                      painter: FireworkPainter(_fireworkController.value),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  /// 底部按钮
  Widget _buildBottomButtons() {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        children: [
          // 答对计数
          Expanded(
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 12.h),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(16.r),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '⭐',
                    style: TextStyle(fontSize: 20.sp),
                  ),
                  SizedBox(width: 8.w),
                  Text(
                    '答对 $_correctCount 题',
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(width: 12.w),

          // 下一题按钮
          Expanded(
            child: ElevatedButton(
              onPressed: _showResult ? _nextQuestion : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 14.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16.r),
                ),
                elevation: 0,
              ),
              child: Text(
                _currentIndex < _questions.length - 1 ? '下一题' : '查看结果',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 显示 TTS 设置对话框
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
              // 标题栏
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
              SizedBox(height: 24.h),

              // 试听区域
              Container(
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24.r),
                  border: Border.all(color: Colors.grey.shade100),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.hearing, color: Colors.blue, size: 24.sp),
                        SizedBox(width: 8.w),
                        Text(
                          '试听效果',
                          style: TextStyle(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16.h),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              await _tts.speak(
                                '小朋友，新年快乐！一起来猜灯谜吧！',
                                featureKey: 'quiz',
                              );
                            },
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('试听'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20.r),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: 24.h),

              const TtsEngineSelector(
                featureKey: 'quiz',
                title: '脑筋急转弯使用 TTS 引擎',
              ),
              SizedBox(height: 24.h),

              // 语速控制
              _buildSliderControl(
                icon: Icons.speed,
                title: '语速',
                value: _tts.speechRate,
                min: 0.0,
                max: 1.0,
                label: '1.0 为正常语速',
                color: Colors.amber,
                onChanged: (val) => _tts.setSpeechRate(val),
              ),
              SizedBox(height: 16.h),

              // 音调控制
              _buildSliderControl(
                icon: Icons.music_note,
                title: '音调',
                value: _tts.pitch,
                min: 0.5,
                max: 2.0,
                label: '1.0 为正常音调',
                color: Colors.amber,
                onChanged: (val) => _tts.setPitch(val),
              ),
              SizedBox(height: 16.h),

              // 音量控制
              _buildSliderControl(
                icon: Icons.volume_up,
                title: '音量',
                value: _tts.volume,
                min: 0.0,
                max: 1.0,
                label: '1.0 为最大音量',
                color: Colors.amber,
                onChanged: (val) => _tts.setVolume(val),
              ),
              SizedBox(height: 24.h),
            ],
          ),
        ),
      ),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  /// 构建滑块控制组件
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
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.r),
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
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textMain,
                ),
              ),
              const Spacer(),
              Obx(() => Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Text(
                      value.value.toStringAsFixed(1),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: color.withOpacity(0.8),
                      ),
                    ),
                  )),
            ],
          ),
          SizedBox(height: 8.h),
          Obx(() => SliderTheme(
                data: SliderTheme.of(Get.context!).copyWith(
                  activeTrackColor: color,
                  inactiveTrackColor: color.withOpacity(0.2),
                  thumbColor: color,
                  trackHeight: 4.h,
                ),
                child: Slider(
                  value: value.value,
                  min: min,
                  max: max,
                  onChanged: (v) => value.value = v,
                ),
              )),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.sp,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}

/// 烟花绘制器
class FireworkPainter extends CustomPainter {
  final double progress;

  FireworkPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    // 绘制多个烟花粒子
    for (int i = 0; i < 12; i++) {
      final distance = maxRadius * progress;
      final x = center.dx + distance * (i % 2 == 0 ? 1 : -1) * 0.5;
      final y = center.dy + distance * (i % 3 == 0 ? 1 : -1) * 0.5;

      paint.color = [
        Colors.red,
        Colors.orange,
        Colors.yellow,
        Colors.pink,
      ][i % 4]
          .withOpacity(0.8);

      canvas.drawCircle(
        Offset(x, y),
        (1 - progress) * 8,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(FireworkPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
