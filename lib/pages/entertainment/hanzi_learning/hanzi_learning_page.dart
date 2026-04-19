import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import '../../../data/hanzi_data.dart';
import '../../../services/hanzi_learning_service.dart';
import '../../../services/tts_service.dart';
import '../../../controllers/app_mode_controller.dart';
import '../../../widgets/toast_utils.dart';
import '../../../widgets/tts_engine_selector.dart';
import 'hanzi_library_page.dart';
import 'hanzi_learning_settings_page.dart';

/// 星海识字主页面
/// 包含：AI内容展示、TTS整句朗读（卡拉OK高亮）、单字点读（含拼音）
class HanziLearningPage extends StatefulWidget {
  const HanziLearningPage({super.key});

  @override
  State<HanziLearningPage> createState() => _HanziLearningPageState();
}

class _HanziLearningPageState extends State<HanziLearningPage>
    with TickerProviderStateMixin {
  final TtsService _tts = Get.find<TtsService>();
  final HanziLearningService _service = Get.find<HanziLearningService>();
  final AppModeController _modeController = Get.find<AppModeController>();

  /// 当前显示的文本
  String _displayText = '';

  /// 文本中的字符列表（用于逐字渲染）
  List<String> _characters = [];

  /// 当前高亮的字符索引（卡拉OK效果）
  int _highlightIndex = -1;

  /// 是否正在整句朗读
  bool _isPlayingFull = false;

  /// 是否正在加载（AI生成中）
  bool _isLoading = false;

  /// 卡拉OK定时器（系统TTS兜底方案）
  Timer? _karaokeTimer;

  /// CFTTS 播放进度订阅（音频比例方案）
  StreamSubscription<Duration>? _positionSubscription;

  /// 字符权重列表（用于按比例推算高亮位置）
  List<double> _charWeights = [];

  /// 字符权重累积数组（前缀和，用于快速二分查找）
  List<double> _charWeightPrefixSum = [];

  /// 弹跳动画控制器（单字点读效果）
  AnimationController? _bounceController;
  Animation<double>? _bounceAnimation;

  /// 当前被点击的字的索引
  int _tappedCharIndex = -1;

  /// 点击波纹动画控制器
  AnimationController? _rippleController;
  Animation<double>? _rippleAnimation;
  Animation<double>? _rippleOpacity;

  /// 漂浮动画控制器
  late AnimationController _floatController;
  late Animation<double> _floatAnimation;

  @override
  void initState() {
    super.initState();

    // 初始化漂浮动画
    _floatController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _floatAnimation = Tween<double>(begin: -4, end: 4).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );

    // 初始化弹跳动画
    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _bounceAnimation = Tween<double>(begin: 1.0, end: 1.4).animate(
      CurvedAnimation(parent: _bounceController!, curve: Curves.elasticOut),
    );

    // 初始化波纹动画
    _rippleController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _rippleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _rippleController!, curve: Curves.easeOut),
    );
    _rippleOpacity = Tween<double>(begin: 0.6, end: 0.0).animate(
      CurvedAnimation(parent: _rippleController!, curve: Curves.easeOut),
    );

    // 检查首次启动
    _checkFirstLaunch();
  }

  @override
  void dispose() {
    _karaokeTimer?.cancel();
    _positionSubscription?.cancel();
    _tts.onProgressCallback = null;
    _floatController.dispose();
    _bounceController?.dispose();
    _rippleController?.dispose();
    _tts.stop();
    super.dispose();
  }

  /// 检查是否首次启动，引导设置
  void _checkFirstLaunch() {
    final config = _service.config.value;
    if (config == null || config.isFirstLaunch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showFirstLaunchGuide();
      });
    }
  }

  /// 显示首次启动引导
  void _showFirstLaunchGuide() {
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24.r),
        ),
        backgroundColor: const Color(0xFFFFF8E1),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🎓', style: TextStyle(fontSize: 60.sp)),
            SizedBox(height: 16.h),
            Text(
              '欢迎来到星海识字！',
              style: TextStyle(
                fontSize: 20.sp,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF333333),
              ),
            ),
            SizedBox(height: 12.h),
            Text(
              '请先选择要学习的册别，\n然后勾选已经认识的字，\n就可以开始学习啦！',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.sp,
                color: Colors.grey[700],
                height: 1.6,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('稍后设置'),
          ),
          ElevatedButton(
            onPressed: () {
              Get.back();
              _showLevelSelector();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B6B),
            ),
            child: const Text('开始设置'),
          ),
        ],
      ),
      barrierDismissible: false,
    );
  }

  /// 显示册别选择对话框（替代原来的年龄选择）
  void _showLevelSelector() {
    int selectedLevel = _service.config.value?.unlockedMaxLevel ?? 1;
    final allLevels = HanziData.allBookLevels;

    // 每册的颜色和 Emoji
    const levelColors = [
      Color(0xFFFF6B6B),
      Color(0xFFFFB347),
      Color(0xFF87CEEB),
      Color(0xFF98D8C8),
      Color(0xFFC39BD3),
      Color(0xFFFFD700),
      Color(0xFF77DD77),
    ];
    const levelEmojis = ['🌱', '🌿', '🌻', '🌈', '⭐', '🎯', '🏆'];

    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24.r),
        ),
        backgroundColor: const Color(0xFFFFF8E1),
        title: Row(
          children: [
            Text('📖', style: TextStyle(fontSize: 24.sp)),
            SizedBox(width: 8.w),
            const Text('选择学习册别'),
          ],
        ),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '选择最高解锁册别\n（包含所有低于该册的字）',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: Colors.grey[600],
                    ),
                  ),
                  SizedBox(height: 12.h),
                  ...allLevels.map((level) {
                    final isSelected = level <= selectedLevel;
                    final isMax = level == selectedLevel;
                    final idx = (level - 1).clamp(0, levelColors.length - 1);
                    final color = levelColors[idx];
                    final emoji = levelEmojis[idx];
                    final entries = HanziData.getEntriesByLevel(level);
                    final stageName = entries.isNotEmpty
                        ? entries.first.stageName
                        : '第$level册';

                    return Padding(
                      padding: EdgeInsets.only(bottom: 8.h),
                      child: GestureDetector(
                        onTap: () =>
                            setDialogState(() => selectedLevel = level),
                        child: Container(
                          width: double.infinity,
                          padding: EdgeInsets.symmetric(
                            horizontal: 14.w,
                            vertical: 10.h,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? color.withOpacity(0.15)
                                : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(14.r),
                            border: Border.all(
                              color: isMax ? color : Colors.grey.shade200,
                              width: isMax ? 2.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Text(emoji, style: TextStyle(fontSize: 20.sp)),
                              SizedBox(width: 10.w),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '第$level册 · $stageName',
                                      style: TextStyle(
                                        fontSize: 13.sp,
                                        fontWeight: isMax
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: isMax
                                            ? color
                                            : const Color(0xFF333333),
                                      ),
                                    ),
                                    Text(
                                      '${entries.length}字 · ${entries.isNotEmpty ? entries.first.recommendedAge : ""}',
                                      style: TextStyle(
                                        fontSize: 11.sp,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                Icon(
                                  isMax
                                      ? Icons.check_circle
                                      : Icons.check_circle_outline,
                                  color: color,
                                  size: 20.sp,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _service.setUnlockedMaxLevel(selectedLevel);
              Get.back();
              // 进入字库筛选
              final result = await Get.to(() => const HanziLibraryPage());
              if (result == true) {
                setState(() {});
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B6B),
            ),
            child: const Text('下一步'),
          ),
        ],
      ),
    );
  }

  /// 生成新内容
  Future<void> _generateContent() async {
    final config = _service.config.value;
    if (config == null || config.knownHanziList.isEmpty) {
      ToastUtils.showWarning('请先在设置中完成字库配置');
      return;
    }

    setState(() {
      _isLoading = true;
      _displayText = '';
      _characters = [];
      _highlightIndex = -1;
    });

    try {
      final text = await _service.generateContent();

      setState(() {
        _displayText = text;
        _characters = text.split('');
        _isLoading = false;
      });

      // 预计算字符权重（用于卡拉OK按比例同步）
      _buildCharWeights();

      // 异步在后台预加载此段文本的 CFTTS，如果使用的是 API 方案
      _tts.clearCfttsCache().then((_) {
        _tts.prefetchCftts(text, featureKey: 'hanzi_learning_full');
      });

      final coverage = _service.calculateCoverage(text);
      debugPrint('📊 字库覆盖率: ${(coverage * 100).toStringAsFixed(1)}%');
    } catch (e) {
      setState(() => _isLoading = false);
      ToastUtils.showError(
          '生成失败: ${e.toString().replaceAll('Exception:', '')}');
    }
  }

  /// 构建字符权重列表和前缀和（用于卡拉OK比例推算）
  /// 汉字权重 1.0，标点/空白权重 0.3（朗读时标点只有短停顿），换行权重 0.5
  void _buildCharWeights() {
    final punctuationRegex = RegExp(r'[，。！？、：；（）《》""'']');

    _charWeights = _characters.map((char) {
      if (char == '\n' || char == '\r') return 0.5;
      if (RegExp(r'\s').hasMatch(char)) return 0.2;
      if (punctuationRegex.hasMatch(char)) return 0.3;
      return 1.0; // 汉字和其他文字字符
    }).toList();

    // 构建前缀和：_charWeightPrefixSum[i] = 前 i 个字符的权重总和
    _charWeightPrefixSum = [0.0];
    double sum = 0.0;
    for (final w in _charWeights) {
      sum += w;
      _charWeightPrefixSum.add(sum);
    }
  }

  /// 根据播放进度比例（0.0~1.0）推算对应的字符索引
  /// 使用权重前缀和进行二分查找
  int _progressToCharIndex(double progress) {
    if (_charWeightPrefixSum.isEmpty || _characters.isEmpty) return 0;

    final totalWeight = _charWeightPrefixSum.last;
    if (totalWeight <= 0) return 0;

    final targetWeight = progress * totalWeight;

    // 二分查找：找到第一个前缀和 >= targetWeight 的位置
    int lo = 0, hi = _characters.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (_charWeightPrefixSum[mid + 1] < targetWeight) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo.clamp(0, _characters.length - 1);
  }

  /// 整句朗读（带卡拉OK效果）
  /// 系统TTS：使用 flutter_tts 的精确进度回调
  /// CFTTS：使用 just_audio 的 positionStream 按比例推算高亮位置
  Future<void> _playFullText() async {
    if (_displayText.isEmpty) return;

    // 如果正在播放，则停止
    if (_isPlayingFull) {
      await _stopFullPlay();
      return;
    }

    // 确保权重已计算
    if (_charWeights.isEmpty) _buildCharWeights();

    setState(() {
      _isPlayingFull = true;
      _highlightIndex = 0;
    });

    // 判断当前使用的是 CFTTS 还是系统 TTS
    bool isCftts = _tts.useCftts.value;
    final override = _tts.getFeatureTtsEngine('hanzi_learning_full');
    if (override == 'cftts') isCftts = true;
    if (override == 'system') isCftts = false;

    // 检查 CFTTS 是否实际可用
    if (isCftts && (_tts.cfttsConfig.value == null ||
        _tts.cfttsConfig.value!.baseUrl.isEmpty)) {
      isCftts = false;
    }

    if (isCftts) {
      await _playWithCfttsSync();
    } else {
      await _playWithSystemTtsSync();
    }

    // 播放结束后清理
    await _cleanupFullPlay();
  }

  /// CFTTS 方案：监听 just_audio positionStream，按时间比例推算高亮位置
  Future<void> _playWithCfttsSync() async {
    debugPrint('🎵 使用 CFTTS 音频比例同步方案');

    bool durationReady = false;
    Duration? totalDuration;

    // 先启动 TTS 播放（异步，让音频开始加载）
    final speakFuture =
        _tts.speak(_displayText, featureKey: 'hanzi_learning_full');

    // 轮询等待音频加载完成并获取总时长（最多5秒）
    for (int i = 0; i < 50; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!_isPlayingFull || !mounted) return;

      totalDuration = _tts.audioPlayer.duration;
      if (totalDuration != null && totalDuration.inMilliseconds > 0) {
        durationReady = true;
        break;
      }
    }

    if (!durationReady || totalDuration == null) {
      debugPrint('⚠️ 无法获取音频时长，回退到估算定时器');
      _startFallbackKaraoke();
      try {
        await speakFuture;
      } catch (_) {}
      return;
    }

    debugPrint('⏱️ 音频总时长: ${totalDuration.inMilliseconds}ms, '
        '文本${_characters.length}字');

    // 监听播放位置流，实时推算高亮索引
    _positionSubscription?.cancel();
    _positionSubscription =
        _tts.audioPlayer.positionStream.listen((position) {
      if (!_isPlayingFull || !mounted || totalDuration == null) return;

      final progress =
          position.inMilliseconds / totalDuration!.inMilliseconds;
      final clampedProgress = progress.clamp(0.0, 1.0);
      final newIndex = _progressToCharIndex(clampedProgress);

      if (newIndex != _highlightIndex) {
        setState(() => _highlightIndex = newIndex);
      }
    });

    // 等待播放完成
    try {
      await speakFuture;
    } catch (e) {
      debugPrint('CFTTS speak failed: $e');
    }
  }

  /// 系统 TTS 方案：使用 flutter_tts 的精确进度回调
  Future<void> _playWithSystemTtsSync() async {
    debugPrint('🔊 使用系统 TTS 精确回调同步方案');

    bool receivedProgress = false;
    _karaokeTimer?.cancel();
    _tts.onProgressCallback = null;
    _tts.onStartCallback = null;

    // 设置进度回调 - 精确同步
    _tts.onProgressCallback = (int start, int end) {
      receivedProgress = true;
      if (mounted && _isPlayingFull && start < _characters.length) {
        setState(() => _highlightIndex = start);
      }
    };

    // 当语音开始播放后，检查进度回调是否可用
    _tts.onStartCallback = () {
      if (!mounted || !_isPlayingFull) return;

      Future.delayed(const Duration(milliseconds: 500), () {
        if (!receivedProgress && _isPlayingFull && mounted) {
          _startFallbackKaraoke();
        }
      });
    };

    try {
      await _tts.speak(_displayText, featureKey: 'hanzi_learning_full');
    } catch (e) {
      debugPrint('TTS speak failed: $e');
    }
  }

  /// 兜底方案：使用固定速率的定时器估算逐字高亮
  void _startFallbackKaraoke() {
    final rate = _tts.speechRate.value;
    final normalMs = 280;
    final msPerChar = (normalMs / (rate <= 0.05 ? 0.3 : rate * 1.5))
        .toInt()
        .clamp(150, 1000);

    debugPrint('⏱️ 兜底定时器: $msPerChar ms/字');

    void step() {
      if (!_isPlayingFull || !mounted) return;
      if (_highlightIndex >= _characters.length - 1) return;

      final char = _characters[_highlightIndex];
      int waitMs = msPerChar;
      if (RegExp(r'[，。！？、：；（）《》""''\n\s]').hasMatch(char)) {
        waitMs = 10;
      }

      _karaokeTimer = Timer(Duration(milliseconds: waitMs), () {
        if (mounted && _isPlayingFull) {
          setState(() => _highlightIndex++);
          step();
        }
      });
    }

    step();
  }

  /// 停止整句朗读
  Future<void> _stopFullPlay() async {
    await _tts.stop();
    await _cleanupFullPlay();
  }

  /// 清理播放状态和回调
  Future<void> _cleanupFullPlay() async {
    _karaokeTimer?.cancel();
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _tts.onProgressCallback = null;
    _tts.onStartCallback = null;
    if (mounted) {
      setState(() {
        _isPlayingFull = false;
        _highlightIndex = -1;
      });
    }
  }

  /// 单字点读
  Future<void> _tapChar(int index) async {
    if (index < 0 || index >= _characters.length) return;

    final char = _characters[index];
    final hanziRegex = RegExp(r'[\u4e00-\u9fff]');
    if (!hanziRegex.hasMatch(char)) return;

    if (_isPlayingFull) {
      await _tts.stop();
      _karaokeTimer?.cancel();
      setState(() {
        _isPlayingFull = false;
        _highlightIndex = -1;
      });
    }

    setState(() => _tappedCharIndex = index);
    _bounceController?.forward(from: 0);
    _rippleController?.forward(from: 0);

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() => _tappedCharIndex = -1);
      }
    });

    await _tts.speak(char, featureKey: 'hanzi_learning_single');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _displayText.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_displayText.isNotEmpty) {
          setState(() {
            _displayText = '';
            _tts.stop();
          });
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFFFF8E1), // 卡通暖黄底色
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('📝', style: TextStyle(fontSize: 22.sp)),
              SizedBox(width: 8.w),
              const Text(
                '星海识字',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          leading: _displayText.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    setState(() {
                      _displayText = '';
                      _tts.stop();
                    });
                  },
                )
              : null,
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            // 语音设置按钮
            IconButton(
              icon: const Icon(Icons.volume_up),
              tooltip: '语音设置',
              onPressed: _showTtsSettings,
            ),
            // 设置按钮（家长模式）
            Obx(() {
              if (_modeController.isParentMode) {
                return IconButton(
                  icon: const Icon(Icons.settings),
                  tooltip: '学习设置',
                  onPressed: () async {
                    await Get.to(() => const HanziLearningSettingsPage());
                    setState(() {});
                  },
                );
              }
              return const SizedBox.shrink();
            }),
          ],
        ),
        body: SafeArea(
          child: _displayText.isEmpty ? _buildWelcomeView() : _buildGameView(),
        ),
      ),
    );
  }

  /// 欢迎/初始界面
  Widget _buildWelcomeView() {
    final config = _service.config.value;
    final knownCount = config?.knownHanziList.length ?? 0;
    final maxLevel = config?.unlockedMaxLevel ?? 1;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 24.w),
      child: Column(
        children: [
          SizedBox(height: 20.h),
          // 重新设计的“星海”主题吉祥物/动画 - 缩小尺寸以节省空间
          SizedBox(
            height: 160.h,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 底层光晕 - 呼吸灯效果
                AnimatedBuilder(
                  animation: _floatAnimation,
                  builder: (context, child) {
                    final scale = 1.0 + (_floatAnimation.value / 40);
                    return Container(
                      width: 110.w * scale,
                      height: 110.w * scale,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xFFFFB347).withOpacity(0.35),
                            const Color(0xFFFFB347).withOpacity(0.0),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                // 星星装饰
                ...List.generate(5, (index) {
                  final angle = (index * 72.0) * (3.14159 / 180);
                  return AnimatedBuilder(
                    animation: _floatAnimation,
                    builder: (context, child) {
                      final offset = 65.w + _floatAnimation.value;
                      return Transform.translate(
                        offset: Offset(
                          offset * (index.isEven ? 1 : 1.1) * (index % 3 == 0 ? 0.8 : 1) * (angle > 1.5 ? -1 : 1), // 错开位置
                          offset * (angle < 3 ? 0.5 : -0.5),
                        ),
                        child: Text(
                          index.isEven ? '✨' : '⭐',
                          style: TextStyle(fontSize: (14 + index * 2).sp),
                        ),
                      );
                    },
                  );
                }),
                // 核心视觉：星海中的书
                AnimatedBuilder(
                  animation: _floatAnimation,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(0, _floatAnimation.value),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Text('📔', style: TextStyle(fontSize: 72.sp)),
                          Positioned(
                            top: 15.h,
                            child: Text('🌟', style: TextStyle(fontSize: 20.sp)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          
          SizedBox(height: 15.h),
          Text(
            '星海识字',
            style: TextStyle(
              fontSize: 28.sp,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF333333),
              letterSpacing: 1.5,
            ),
          ),
          SizedBox(height: 10.h),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 6.h),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.6),
              borderRadius: BorderRadius.circular(20.r),
            ),
            child: Text(
              '在星海中偶遇每一个文字 ✨',
              style: TextStyle(
                fontSize: 14.sp,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(height: 24.h),

          // 字库状态卡片 - 重新设计
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(24.w),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28.r),
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(10.w),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6B6B).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Text('📊', style: TextStyle(fontSize: 18.sp)),
                    ),
                    SizedBox(width: 12.w),
                    Text(
                      '进度概览',
                      style: TextStyle(
                        fontSize: 18.sp,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF333333),
                      ),
                    ),
                    const Spacer(),
                    if (knownCount > 0)
                      Text(
                        '解锁至第$maxLevel册',
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: const Color(0xFFFF6B6B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
                SizedBox(height: 20.h),
                if (knownCount > 0) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem('已认识', '$knownCount', Colors.orange),
                      Container(width: 1, height: 30, color: Colors.grey.shade100),
                      _buildStatItem('书册', '第$maxLevel册', Colors.blue),
                    ],
                  ),
                ] else ...[
                  Text(
                    '开启星海之旅，勾选你认识的字',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15.sp,
                      color: Colors.grey[600],
                      height: 1.5,
                    ),
                  ),
                  SizedBox(height: 16.h),
                  ElevatedButton(
                    onPressed: _showLevelSelector,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B6B),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 12.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16.r),
                      ),
                      elevation: 0,
                    ),
                    child: const Text('去设置', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: 24.h),

          // 开始学习按钮 - 更加醒目
          if (knownCount > 0)
            Container(
              width: double.infinity,
              height: 64.h,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22.r),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF6B6B).withOpacity(0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _isLoading ? null : _generateContent,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B6B),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22.r),
                  ),
                  elevation: 0,
                ),
                child: _isLoading
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 22.w,
                            height: 22.w,
                            child: const CircularProgressIndicator(
                              strokeWidth: 3,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 12.w),
                          Text('✨ 正在召唤文字...', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
                        ],
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.rocket_launch, size: 24.sp),
                          SizedBox(width: 12.w),
                          Text(
                            '开启今日识字',
                            style: TextStyle(
                              fontSize: 20.sp,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
              ),
            ),

          // 历史记录按钮
          if (knownCount > 0) _buildLastRecordButton(),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 22.sp,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12.sp,
            color: Colors.grey[500],
          ),
        ),
      ],
    );
  }

  /// 构建“上次记录”按钮
  Widget _buildLastRecordButton() {
    final record = _service.getLastRecord();
    if (record == null) return const SizedBox.shrink();

    final text = record['text'] as String? ?? '';
    if (text.isEmpty) return const SizedBox.shrink();

    // 解析时间
    final timestamp = record['timestamp'] as String?;
    String timeLabel = '';
    if (timestamp != null) {
      try {
        final dt = DateTime.parse(timestamp);
        timeLabel =
            '· ${dt.month}月${dt.day}日 ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    }

    // 截取预览（最多20字）
    final preview = text.length > 20 ? '${text.substring(0, 20)}...' : text;

    return Padding(
      padding: EdgeInsets.only(top: 16.h),
      child: GestureDetector(
        onTap: _loadLastRecord,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
          decoration: BoxDecoration(
            color: const Color(0xFF7C4DFF).withOpacity(0.08),
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(
              color: const Color(0xFF7C4DFF).withOpacity(0.25),
            ),
          ),
          child: Row(
            children: [
              Text('📖', style: TextStyle(fontSize: 24.sp)),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '上次记录 $timeLabel',
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF7C4DFF),
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      preview,
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: Colors.grey[600],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.play_circle_outline,
                color: const Color(0xFF7C4DFF),
                size: 28.sp,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 加载上次记录并直接进入游戏界面
  void _loadLastRecord() {
    final text = _service.loadLastRecord();
    if (text != null && text.isNotEmpty) {
      setState(() {
        _displayText = text;
        _characters = text.split('');
        _highlightIndex = -1;
      });
      ToastUtils.showSuccess('已加载上次记录 📖');
    } else {
      ToastUtils.showWarning('没有可恢复的记录');
    }
  }

  /// 游戏主界面
  Widget _buildGameView() {
    return Column(
      children: [
        // 信息栏
        _buildInfoBar(),
        // 文本内容区域
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16.w),
            child: _buildTextDisplay(),
          ),
        ),
        // 底部控制栏
        _buildBottomBar(),
      ],
    );
  }

  /// 信息栏（显示覆盖率和本次新字）
  Widget _buildInfoBar() {
    final coverage = _service.calculateCoverage(_displayText);
    final newChars = _service.currentNewChars;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 覆盖率
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
            decoration: BoxDecoration(
              color: coverage >= 0.85
                  ? const Color(0xFF4CAF50).withOpacity(0.1)
                  : Colors.orange.shade50,
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  coverage >= 0.85 ? '🌟' : '📊',
                  style: TextStyle(fontSize: 14.sp),
                ),
                SizedBox(width: 4.w),
                Text(
                  '${(coverage * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.bold,
                    color: coverage >= 0.85
                        ? const Color(0xFF4CAF50)
                        : Colors.orange,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 8.w),

          // 新字提示
          if (newChars.isNotEmpty) ...[
            Text(
              '新字：',
              style: TextStyle(fontSize: 12.sp, color: Colors.grey),
            ),
            ...newChars.map((c) {
              final pinyin = HanziData.getPinyin(c);
              return Container(
                margin: EdgeInsets.only(left: 4.w),
                padding: EdgeInsets.symmetric(
                  horizontal: 6.w,
                  vertical: 2.h,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8.r),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      pinyin ?? ' ',
                      style: TextStyle(
                        fontSize: 8.sp,
                        color: Colors.orange.shade700,
                      ),
                    ),
                    Text(
                      c,
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  /// 文本内容展示区（支持拼音、点读和卡拉OK高亮）
  Widget _buildTextDisplay() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(
          color: const Color(0xFFFFE0B2),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _buildParagraphs(),
      ),
    );
  }

  List<Widget> _buildParagraphs() {
    final List<Widget> paragraphs = [];
    List<Widget> currentLine = [];

    for (int index = 0; index < _characters.length; index++) {
      final char = _characters[index];

      // 当遇到换行符时，将之前收集的一行文字组合成 Wrap 成为一个段落
      if (char == '\n' || char == '\r') {
        if (currentLine.isNotEmpty) {
          paragraphs.add(Wrap(
            spacing: 2.w,
            runSpacing: 6.h,
            alignment: WrapAlignment.start,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: List.from(currentLine),
          ));
          currentLine.clear();
        }
        if (char == '\n') {
          // 添加真实的段落间距（空出舒适间隔）
          paragraphs.add(SizedBox(height: 16.h));
        }
        continue;
      }

      currentLine.add(_buildCharWidget(index, char));
    }

    // 结尾若未在换行处结束，需要把最后一句收尾
    if (currentLine.isNotEmpty) {
      paragraphs.add(Wrap(
        spacing: 2.w,
        runSpacing: 6.h,
        alignment: WrapAlignment.start,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: currentLine,
      ));
    }

    return paragraphs;
  }

  Widget _buildCharWidget(int index, String char) {
    final hanziRegex = RegExp(r'[\u4e00-\u9fff]');
    final isHanzi = hanziRegex.hasMatch(char);
    final isNewChar = isHanzi && _service.isNewChar(char);
    final isHighlighted = _highlightIndex == index;
    final isTapped = _tappedCharIndex == index;

    // 获取拼音
    final pinyin = isHanzi ? HanziData.getPinyin(char) : null;
    final hasPinyin = pinyin != null && pinyin.trim().isNotEmpty;

    // 核心修复：无论是标点还是无拼音汉字，均使用一个不可见的占位符维持相同的物理高度
    Widget pinyinWidget = Opacity(
      opacity: hasPinyin ? 1.0 : 0.0,
      child: Text(
        hasPinyin ? pinyin : 'a',
        style: TextStyle(
          fontSize: 9.sp,
          color: isHighlighted
              ? const Color(0xFFFF6B6B)
              : isNewChar
                  ? Colors.orange.shade600
                  : Colors.grey[400],
          fontWeight: FontWeight.w500,
        ),
      ),
    );

    // 非汉字字符（标点符号）同样包裹一层与汉字完全等高的结构
    if (!isHanzi) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 2.w, vertical: 1.h),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.transparent, width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            pinyinWidget,
            Text(
              char,
              style: TextStyle(
                fontSize: 24.sp,
                fontWeight: FontWeight.bold,
                height: 1.3,
                color: isHighlighted
                    ? const Color(0xFFFF6B6B)
                    : const Color(0xFF333333),
              ),
            ),
          ],
        ),
      );
    }

    // 汉字字符 - 支持点读 + 拼音标注
    Widget charWidget = GestureDetector(
      onTap: () => _tapChar(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: 2.w,
          vertical: 1.h,
        ),
        decoration: BoxDecoration(
          color: isHighlighted
              ? const Color(0xFFFF6B6B).withOpacity(0.15)
              : isNewChar
                  ? Colors.orange.shade50
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(8.r),
          // 核心修复：即使不是新字，也保留透明的 1.5px 边框占位，防止高度突变
          border: Border.all(
            color: isNewChar ? Colors.orange.shade300 : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            pinyinWidget,
            // 汉字
            Text(
              char,
              style: TextStyle(
                fontSize: 24.sp,
                fontWeight: FontWeight.bold,
                height: 1.3,
                color: isHighlighted
                    ? const Color(0xFFFF6B6B)
                    : isNewChar
                        ? Colors.orange.shade800
                        : const Color(0xFF333333),
              ),
            ),
          ],
        ),
      ),
    );

    // 添加弹跳 + 水波纹动画
    if (isTapped && _bounceAnimation != null && _rippleAnimation != null) {
      charWidget = AnimatedBuilder(
        animation: _bounceAnimation!,
        builder: (context, child) {
          return Transform.scale(
            scale: _bounceAnimation!.value,
            child: child,
          );
        },
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            charWidget,
            // 水波纹扩散层
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _rippleAnimation!,
                builder: (context, _) {
                  final rippleColor = isNewChar
                      ? Colors.orange.shade400
                      : const Color(0xFF7C4DFF);
                  return CustomPaint(
                    painter: _RipplePainter(
                      progress: _rippleAnimation!.value,
                      opacity: _rippleOpacity!.value,
                      color: rippleColor,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    }

    return charWidget;
  }

  /// 底部控制栏
  Widget _buildBottomBar() {
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
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // 播放/暂停按钮
            _buildActionButton(
              icon: _isPlayingFull ? Icons.pause_circle : Icons.play_circle,
              label: _isPlayingFull ? '暂停' : '朗读',
              color: const Color(0xFFFF6B6B),
              onTap: _playFullText,
            ),

            // 换一篇按钮
            _buildActionButton(
              icon: Icons.refresh,
              label: '换一篇',
              color: const Color(0xFF87CEEB),
              onTap: _isLoading ? null : _generateContent,
            ),

            // 编辑字库按钮（仅家长模式）
            Obx(() {
              if (_modeController.isParentMode) {
                return _buildActionButton(
                  icon: Icons.edit_note,
                  label: '字库',
                  color: const Color(0xFFFFB347),
                  onTap: () async {
                    final result = await Get.to(() => const HanziLibraryPage());
                    if (result == true) {
                      setState(() {});
                    }
                  },
                );
              }
              return const SizedBox.shrink();
            }),
          ],
        ),
      ),
    );
  }

  /// 构建操作按钮
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    final isDisabled = onTap == null;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56.w,
            height: 56.w,
            decoration: BoxDecoration(
              color:
                  isDisabled ? Colors.grey.shade200 : color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(18.r),
              border: Border.all(
                color:
                    isDisabled ? Colors.grey.shade300 : color.withOpacity(0.4),
                width: 2,
              ),
            ),
            child: Icon(
              icon,
              color: isDisabled ? Colors.grey.shade400 : color,
              size: 28.sp,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.sp,
              color: isDisabled ? Colors.grey : color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// 显示 TTS 设置
  void _showTtsSettings() {
    Get.bottomSheet(
      Container(
        padding: EdgeInsets.all(24.w),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E1),
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
                  Row(
                    children: [
                      Text('🔊', style: TextStyle(fontSize: 22.sp)),
                      SizedBox(width: 8.w),
                      Text(
                        '语音设置',
                        style: TextStyle(
                          fontSize: 20.sp,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF333333),
                        ),
                      ),
                    ],
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
                  borderRadius: BorderRadius.circular(20.r),
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
                        Icon(Icons.hearing,
                            color: const Color(0xFFFF6B6B), size: 24.sp),
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
                              await _tts.speak('小朋友，今天学习了新的汉字真棒！');
                            },
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('试听'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF6B6B),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20.r),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 16.w),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              _tts.speak('小猫咪在花园里追蝴蝶');
                            },
                            icon: const Icon(Icons.face),
                            label: const Text('故事测试'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFFFB347),
                              side: const BorderSide(color: Color(0xFFFFB347)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20.r),
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
              SizedBox(height: 24.h),

              const TtsEngineSelector(
                featureKey: 'hanzi_learning_full',
                title: '播放全文默认引擎',
              ),
              SizedBox(height: 16.h),
              const TtsEngineSelector(
                featureKey: 'hanzi_learning_single',
                title: '点读默认引擎',
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
                color: const Color(0xFFFF6B6B),
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
                color: const Color(0xFFFFB347),
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
                color: const Color(0xFF87CEEB),
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
                  color: const Color(0xFF333333),
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
                        color: color,
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

/// 水波纹涟漪自定义画笔
/// 在被点击的汉字上层绘制一个从中心向外扩散的圆环，不断增加半径、同时透明度渐隐
class _RipplePainter extends CustomPainter {
  final double progress; // 0.0 ~ 1.0 动画进度
  final double opacity; // 0.6 ~ 0.0 透明度
  final Color color; // 涟漪颜色

  _RipplePainter({
    required this.progress,
    required this.opacity,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width * 0.9;

    // 绘制外圈涟漪
    final paint = Paint()
      ..color = color.withOpacity(opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, maxRadius * progress, paint);

    // 绘制内圈（稍微延迟的第二圈涟漪）
    if (progress > 0.2) {
      final innerProgress = (progress - 0.2) / 0.8;
      final innerPaint = Paint()
        ..color = color.withOpacity(opacity * 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(center, maxRadius * 0.6 * innerProgress, innerPaint);
    }
  }

  @override
  bool shouldRepaint(_RipplePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.opacity != opacity;
  }
}
