import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../data/quiz_data.dart';
import '../../../theme/app_theme.dart';
import '../../../services/tts_service.dart';
import '../../../services/quiz_service.dart';
import 'quiz_ai_settings_page.dart';
import 'quiz_management_page.dart';

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

    _questions = QuizData.getRandomQuestions(10); // 每次10道题

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

  /// 播放题目和选项语音
  Future<void> _speakQuestion() async {
    final question = _questions[_currentIndex];
    final options = question['options'] as List;

    // 播放题目
    await _tts.speak(question['question']);
    await Future.delayed(const Duration(milliseconds: 500));

    // 播放选项
    for (int i = 0; i < options.length; i++) {
      await _tts.speak('选项${i + 1}: ${options[i]}');
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  /// 重播知识点
  Future<void> _replayExplanation() async {
    final question = _questions[_currentIndex];
    await _tts.speak(question['explanation']);
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
      _tts.speak('答对啦!真棒!${question['explanation']}');
    } else {
      // 答错后先说鼓励的话,停顿1秒,再播放知识点
      _speakWrongAnswer();
    }
  }

  /// 播放答错提示(带停顿)
  Future<void> _speakWrongAnswer() async {
    final question = _questions[_currentIndex];
    await _tts.speak('没关系,再听听');
    await Future.delayed(const Duration(seconds: 1)); // 停顿1秒
    await _tts.speak(question['explanation']);
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

    _tts.speak('太棒啦!你答对了$_correctCount题!${_getComment(score)}');
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
            _buildBeast(),

            SizedBox(height: 20.h),

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
            padding: EdgeInsets.all(20.w),
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
                  style: TextStyle(fontSize: 40.sp), // 从60减小到40
                ),
                SizedBox(height: 4.h), // 从8减小到4
                // 小年兽说话 - 缩小
                Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: 12.w, vertical: 6.h), // 缩小padding
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
                  child: Text(
                    _showResult
                        ? (_selectedAnswer ==
                                _questions[_currentIndex]['correctIndex']
                            ? '答对啦!真棒!'
                            : '没关系,再听听~')
                        : '来挑战新年知识吧!',
                    style: TextStyle(
                      fontSize: 12.sp, // 从14减小到12
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
          // Emoji 图标
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

          // 语音播放按钮
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
