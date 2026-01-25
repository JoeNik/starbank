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

  // 当前使用的引擎
  final RxString _currentEngine = ''.obs;

  @override
  void initState() {
    super.initState();
    _initTts();
    _loadRiddles();
    _pageController = PageController();
  }

  /// 初始化语音引擎
  Future<void> _initTts() async {
    _flutterTts = FlutterTts();

    // 1. 尝试设置最佳引擎 (Android)
    try {
      if (GetPlatform.isAndroid) {
        final engines = await _flutterTts.getEngines;
        if (engines != null && engines is List) {
          debugPrint('可用 TTS 引擎: $engines');
          // 优先寻找 Google TTS
          for (var engine in engines) {
            final engineName = engine.toString();
            if (engineName.contains('google')) {
              await _flutterTts.setEngine(engineName);
              _currentEngine.value = 'Google 引擎';
              debugPrint('已切换到 Google TTS 引擎');
              break;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('设置引擎失败: $e');
    }

    // 2. 设置通用参数
    await _flutterTts.setLanguage('zh-CN');
    await _flutterTts.setSpeechRate(_speechRate.value);
    await _flutterTts.setPitch(1.5);
    await _flutterTts.setVolume(1.0);

    // 3. 尝试寻找更自然的声音 (针对选定引擎)
    try {
      final voices = await _flutterTts.getVoices;
      if (voices != null && voices is List) {
        for (var voice in voices) {
          if (voice is Map) {
            final name = voice['name']?.toString().toLowerCase() ?? '';
            final locale = voice['locale']?.toString() ?? '';
            // 优先选择中文女声 (xiaoxiao, yaoyao 等是常见的高质量中文语音包名)
            if (locale.contains('zh') &&
                (name.contains('female') ||
                    name.contains('woman') ||
                    name.contains('xiaoxiao') || // 微软/Google 常用名
                    name.contains('yaoyao') ||
                    name.contains('hi-cn-st'))) {
              // Google 某些版本的标识
              await _flutterTts
                  .setVoice({"name": voice['name'], "locale": voice['locale']});
              debugPrint('已设置声音: $name');
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

  @override
  void dispose() {
    _flutterTts.stop();
    _pageController.dispose();
    super.dispose();
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
          // 语速和引擎设置
          Row(
            children: [
              // 语速调节
              Expanded(
                child: Obx(() => Row(
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
                      ],
                    )),
              ),
              // 引擎指示器
              GestureDetector(
                onTap: _showEngineSelectionDialog,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.settings_voice,
                          size: 14.sp, color: Colors.blue),
                      SizedBox(width: 4.w),
                      Text(
                        '语音设置',
                        style: TextStyle(
                          fontSize: 10.sp,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
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

  /// 显示引擎选择对话框
  Future<void> _showEngineSelectionDialog() async {
    if (!GetPlatform.isAndroid) {
      Get.snackbar('提示', '引擎切换仅支持 Android 设备');
      return;
    }

    try {
      final engines = await _flutterTts.getEngines;
      if (engines == null || engines.isEmpty) {
        // 没有找到 TTS 引擎，显示引导对话框
        _showNoTtsEngineDialog();
        return;
      }

      Get.bottomSheet(
        Container(
          padding: EdgeInsets.all(20.w),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '选择语音引擎',
                style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8.h),
              Text(
                '推荐使用 Google 语音服务 (com.google.android.tts) 以获得最佳效果。',
                style: TextStyle(fontSize: 12.sp, color: Colors.grey),
              ),
              SizedBox(height: 16.h),
              // 使用 ListView 展示引擎列表
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: engines.length,
                  itemBuilder: (context, index) {
                    final engine = engines[index].toString();
                    final isGoogle = engine.contains('google');

                    return ListTile(
                      title: Text(engine),
                      subtitle: isGoogle
                          ? const Text('Google 官方引擎 (推荐)',
                              style: TextStyle(color: Colors.green))
                          : null,
                      trailing: isGoogle
                          ? const Icon(Icons.star, color: Colors.amber)
                          : null,
                      onTap: () async {
                        await _flutterTts.setEngine(engine);
                        _currentEngine.value = isGoogle ? 'Google 引擎' : '其他引擎';

                        // 重新初始化语音设置
                        await _flutterTts.setLanguage('zh-CN');
                        await _flutterTts.setSpeechRate(_speechRate.value);
                        await _flutterTts.setPitch(1.5);

                        Get.back();
                        Get.snackbar(
                          '设置成功',
                          '已切换到 $engine',
                          snackPosition: SnackPosition.BOTTOM,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        isScrollControlled: true,
      );
    } catch (e) {
      debugPrint('获取引擎列表失败: $e');
      Get.snackbar('错误', '无法获取引擎列表: $e');
    }
  }

  /// 显示无 TTS 引擎时的引导对话框
  void _showNoTtsEngineDialog() {
    final context = Get.overlayContext;
    if (context == null) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🔊 语音功能不可用'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('未检测到可用的 TTS 引擎。\n\n可能的原因：'),
              const SizedBox(height: 8),
              const Text('• 系统 TTS 服务未启用'),
              const Text('• 需要在系统设置中开启语音播报权限'),
              const Text('• 未安装中文语音包'),
              const SizedBox(height: 16),
              const Text('解决方法：',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('1. 打开手机【设置】→【辅助功能】→【文字转语音】'),
              const Text('2. 选择并启用一个 TTS 引擎'),
              const Text('3. 下载中文语音包'),
              const Text('4. 重启应用'),
              const SizedBox(height: 16),
              TextButton.icon(
                icon: const Icon(Icons.info_outline),
                label: const Text('点击查看诊断信息'),
                onPressed: () => _showTtsDiagnostics(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  /// 显示 TTS 诊断信息
  Future<void> _showTtsDiagnostics() async {
    String diagnostics = '正在收集诊断信息...\n';

    try {
      // 检查引擎
      final engines = await _flutterTts.getEngines;
      diagnostics += '\n引擎列表: ${engines ?? "null"}';

      // 检查语言
      final languages = await _flutterTts.getLanguages;
      diagnostics += '\n\n可用语言: ${languages ?? "null"}';

      // 检查声音
      final voices = await _flutterTts.getVoices;
      diagnostics += '\n\n可用声音数量: ${voices?.length ?? 0}';

      // 尝试直接播放测试
      diagnostics += '\n\n正在尝试播放测试音...';
      final result = await _flutterTts.speak('测试');
      diagnostics += '\n播放结果: $result';
    } catch (e) {
      diagnostics += '\n\n错误: $e';
    }

    final context = Get.overlayContext;
    if (context == null) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('TTS 诊断信息'),
        content: SingleChildScrollView(
          child: SelectableText(diagnostics),
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
}
