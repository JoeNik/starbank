import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../data/riddle_data.dart';
import '../theme/app_theme.dart';

/// 脑筋急转弯页面
class RiddlePage extends StatefulWidget {
  const RiddlePage({super.key});

  @override
  State<RiddlePage> createState() => _RiddlePageState();
}

class _RiddlePageState extends State<RiddlePage> {
  // TTS 语音引擎
  late FlutterTts _flutterTts;

  // 题目列表
  late List<Map<String, String>> _riddles;

  // 当前题目索引
  final RxInt _currentIndex = 0.obs;

  // 是否显示答案
  final RxBool _showAnswer = false.obs;

  // 是否正在播放语音
  final RxBool _isSpeaking = false.obs;

  // 语速设置 (0.3 - 0.7)
  final RxDouble _speechRate = 0.4.obs;

  // 页面控制器
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _initTts();
    _loadRiddles();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _flutterTts.stop();
    _pageController.dispose();
    super.dispose();
  }

  /// 初始化语音引擎
  Future<void> _initTts() async {
    _flutterTts = FlutterTts();

    // 设置语音参数 - 儿童女声设置
    await _flutterTts.setLanguage('zh-CN');
    await _flutterTts.setSpeechRate(_speechRate.value); // 语速较慢
    await _flutterTts.setPitch(1.5); // 音调更高，更像儿童声音
    await _flutterTts.setVolume(1.0);

    // 尝试设置女性声音（如果平台支持）
    try {
      // 获取可用的声音列表
      final voices = await _flutterTts.getVoices;
      if (voices != null && voices is List) {
        // 尝试找到女性/儿童声音
        for (var voice in voices) {
          if (voice is Map) {
            final name = voice['name']?.toString().toLowerCase() ?? '';
            final locale = voice['locale']?.toString() ?? '';
            // 优先选择中文女声
            if (locale.contains('zh') &&
                (name.contains('female') ||
                    name.contains('woman') ||
                    name.contains('xiaoxiao') ||
                    name.contains('yaoyao'))) {
              await _flutterTts
                  .setVoice({"name": voice['name'], "locale": voice['locale']});
              break;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('设置声音失败: $e');
    }

    // 监听播放状态
    _flutterTts.setStartHandler(() {
      _isSpeaking.value = true;
    });

    _flutterTts.setCompletionHandler(() {
      _isSpeaking.value = false;
    });

    _flutterTts.setErrorHandler((msg) {
      _isSpeaking.value = false;
      debugPrint('TTS Error: $msg');
    });
  }

  /// 更新语速
  Future<void> _updateSpeechRate(double rate) async {
    _speechRate.value = rate;
    await _flutterTts.setSpeechRate(rate);
  }

  /// 加载题目
  void _loadRiddles() {
    _riddles = RiddleData.getAllRiddles();
    _riddles.shuffle(); // 随机打乱顺序
  }

  /// 播放题目语音
  Future<void> _speakQuestion() async {
    if (_isSpeaking.value) {
      await _flutterTts.stop();
      _isSpeaking.value = false;
      return;
    }
    final question = _riddles[_currentIndex.value]['q']!;
    await _flutterTts.speak(question);
  }

  /// 播放答案语音
  Future<void> _speakAnswer() async {
    if (_isSpeaking.value) {
      await _flutterTts.stop();
      _isSpeaking.value = false;
      return;
    }
    final answer = _riddles[_currentIndex.value]['a']!;
    await _flutterTts.speak('答案是：$answer');
  }

  /// 下一题
  void _nextRiddle() {
    _flutterTts.stop();
    _showAnswer.value = false;
    if (_currentIndex.value < _riddles.length - 1) {
      _currentIndex.value++;
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      // 重新开始
      _riddles.shuffle();
      _currentIndex.value = 0;
      _pageController.animateToPage(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  /// 上一题
  void _prevRiddle() {
    _flutterTts.stop();
    _showAnswer.value = false;
    if (_currentIndex.value > 0) {
      _currentIndex.value--;
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8E1),
      appBar: AppBar(
        title: const Text('脑筋急转弯'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          // 题目计数
          Obx(() => Container(
                margin: EdgeInsets.only(right: 16.w),
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(20.r),
                ),
                child: Text(
                  '${_currentIndex.value + 1}/${_riddles.length}',
                  style: TextStyle(
                    color: Colors.amber.shade800,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 主内容区域
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  _currentIndex.value = index;
                  _showAnswer.value = false;
                  _flutterTts.stop();
                },
                itemCount: _riddles.length,
                itemBuilder: (context, index) {
                  return _buildRiddleCard(index);
                },
              ),
            ),

            // 底部控制区域
            _buildControlPanel(),
          ],
        ),
      ),
    );
  }

  /// 题目卡片
  Widget _buildRiddleCard(int index) {
    final riddle = _riddles[index];

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.all(20.w),
      child: Column(
        children: [
          // 题目卡片
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(24.w),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28.r),
              boxShadow: [
                BoxShadow(
                  color: Colors.amber.withOpacity(0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                // 问题图标
                Container(
                  width: 80.w,
                  height: 80.w,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.amber.shade300,
                        Colors.orange.shade300,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24.r),
                  ),
                  child: Center(
                    child: Text(
                      '🤔',
                      style: TextStyle(fontSize: 40.sp),
                    ),
                  ),
                ),
                SizedBox(height: 20.h),

                // 问题文本
                Text(
                  riddle['q']!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22.sp,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textMain,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 16.h),

                // 语音播放按钮 - 题目
                Obx(() => ElevatedButton.icon(
                      onPressed: _speakQuestion,
                      icon: Icon(
                        _isSpeaking.value ? Icons.stop : Icons.volume_up,
                        size: 20.sp,
                      ),
                      label: Text(_isSpeaking.value ? '停止' : '读题目'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          horizontal: 20.w,
                          vertical: 10.h,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20.r),
                        ),
                      ),
                    )),
              ],
            ),
          ),
          SizedBox(height: 20.h),

          // 答案区域
          Obx(() => AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _showAnswer.value
                    ? _buildAnswerCard(riddle['a']!)
                    : _buildShowAnswerButton(),
              )),
        ],
      ),
    );
  }

  /// 显示答案按钮
  Widget _buildShowAnswerButton() {
    return GestureDetector(
      onTap: () => _showAnswer.value = true,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(20.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24.r),
          border: Border.all(
            color: Colors.green.withOpacity(0.3),
            width: 2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lightbulb_outline,
              color: Colors.green,
              size: 24.sp,
            ),
            SizedBox(width: 8.w),
            Text(
              '点击查看答案',
              style: TextStyle(
                fontSize: 16.sp,
                color: Colors.green,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 答案卡片
  Widget _buildAnswerCard(String answer) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(24.w),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.green.shade50,
            Colors.teal.shade50,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(
          color: Colors.green.shade200,
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.check_circle,
                color: Colors.green,
                size: 24.sp,
              ),
              SizedBox(width: 8.w),
              Text(
                '答案揭晓',
                style: TextStyle(
                  fontSize: 16.sp,
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: 16.h),
          Text(
            answer,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20.sp,
              fontWeight: FontWeight.bold,
              color: Colors.green.shade800,
              height: 1.5,
            ),
          ),
          SizedBox(height: 16.h),
          // 语音播放按钮 - 答案
          Obx(() => OutlinedButton.icon(
                onPressed: _speakAnswer,
                icon: Icon(
                  _isSpeaking.value ? Icons.stop : Icons.volume_up,
                  size: 18.sp,
                ),
                label: Text(_isSpeaking.value ? '停止' : '读答案'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.green,
                  side: BorderSide(color: Colors.green.shade300),
                  padding: EdgeInsets.symmetric(
                    horizontal: 16.w,
                    vertical: 8.h,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16.r),
                  ),
                ),
              )),
        ],
      ),
    );
  }

  /// 底部控制面板
  Widget _buildControlPanel() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 语速调节
          Obx(() => Row(
                children: [
                  Icon(Icons.speed, size: 18.sp, color: Colors.grey),
                  SizedBox(width: 8.w),
                  Text(
                    '语速',
                    style: TextStyle(fontSize: 12.sp, color: Colors.grey),
                  ),
                  Expanded(
                    child: Slider(
                      value: _speechRate.value,
                      min: 0.2,
                      max: 0.7,
                      divisions: 5,
                      activeColor: Colors.amber,
                      onChanged: (value) => _updateSpeechRate(value),
                    ),
                  ),
                  Text(
                    _speechRate.value < 0.35
                        ? '慢'
                        : _speechRate.value > 0.55
                            ? '快'
                            : '中',
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: Colors.amber.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              )),
          SizedBox(height: 8.h),
          // 控制按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // 上一题
              Obx(() => _buildControlButton(
                    icon: Icons.arrow_back_ios,
                    label: '上一题',
                    onTap: _currentIndex.value > 0 ? _prevRiddle : null,
                  )),
              // 换一批
              _buildControlButton(
                icon: Icons.refresh,
                label: '换一批',
                color: Colors.amber,
                onTap: () {
                  _flutterTts.stop();
                  _loadRiddles();
                  _currentIndex.value = 0;
                  _showAnswer.value = false;
                  _pageController.jumpToPage(0);
                },
              ),
              // 下一题
              _buildControlButton(
                icon: Icons.arrow_forward_ios,
                label: '下一题',
                color: Colors.green,
                onTap: _nextRiddle,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    Color? color,
    VoidCallback? onTap,
  }) {
    final isDisabled = onTap == null;
    final buttonColor =
        isDisabled ? Colors.grey.shade300 : (color ?? AppTheme.primary);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56.w,
            height: 56.w,
            decoration: BoxDecoration(
              color: buttonColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(18.r),
            ),
            child: Icon(
              icon,
              color: buttonColor,
              size: 24.sp,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.sp,
              color: isDisabled ? Colors.grey : buttonColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
