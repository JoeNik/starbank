import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import '../../../data/hanzi_data.dart';
import '../../../services/hanzi_learning_service.dart';
import '../../../services/tts_service.dart';
import '../../../controllers/app_mode_controller.dart';
import '../../../widgets/toast_utils.dart';
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

  /// 卡拉OK定时器
  Timer? _karaokeTimer;

  /// 弹跳动画控制器（单字点读效果）
  AnimationController? _bounceController;
  Animation<double>? _bounceAnimation;

  /// 当前被点击的字的索引
  int _tappedCharIndex = -1;

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

    // 检查首次启动
    _checkFirstLaunch();
  }

  @override
  void dispose() {
    _karaokeTimer?.cancel();
    _tts.onProgressCallback = null; // 清理进度回调
    _floatController.dispose();
    _bounceController?.dispose();
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
      Color(0xFFFF6B6B), Color(0xFFFFB347), Color(0xFF87CEEB),
      Color(0xFF98D8C8), Color(0xFFC39BD3), Color(0xFFFFD700),
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
                                        color: isMax ? color : const Color(0xFF333333),
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

      final coverage = _service.calculateCoverage(text);
      debugPrint('📊 字库覆盖率: ${(coverage * 100).toStringAsFixed(1)}%');
    } catch (e) {
      setState(() => _isLoading = false);
      ToastUtils.showError(
          '生成失败: ${e.toString().replaceAll('Exception:', '')}');
    }
  }

  /// 整句朗读（带卡拉OK效果）
  /// 优先使用 TTS 进度回调精确同步高亮，兜底使用定时器
  Future<void> _playFullText() async {
    if (_displayText.isEmpty) return;

    if (_isPlayingFull) {
      await _tts.stop();
      _karaokeTimer?.cancel();
      _tts.onProgressCallback = null;
      setState(() {
        _isPlayingFull = false;
        _highlightIndex = -1;
      });
      return;
    }

    setState(() {
      _isPlayingFull = true;
      _highlightIndex = 0;
    });

    // 标记是否收到过进度回调（用于判断引擎是否支持）
    bool receivedProgress = false;

    // 设置 TTS 进度回调 —— 精确同步高亮位置
    _tts.onProgressCallback = (int start, int end) {
      receivedProgress = true;
      // start 是当前朗读到文本的字符偏移，直接对应 _characters 的索引
      if (mounted && _isPlayingFull && start < _characters.length) {
        setState(() => _highlightIndex = start);
      }
    };

    // 启动兜底定时器（延迟 500ms 后，如果没收到进度回调才启用）
    _karaokeTimer?.cancel();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!receivedProgress && _isPlayingFull && mounted) {
        // 引擎不支持 progress 回调，使用估算定时器兜底
        final rate = _tts.speechRate.value;
        // speechRate 0.5 = 正常速度（约250ms/字），0 = 最慢，1 = 最快
        final normalMs = 250;
        final msPerChar = (normalMs / (rate <= 0.05 ? 0.1 : rate * 2)).toInt().clamp(80, 1000);
        debugPrint('⏱️ TTS 进度回调不可用，使用兜底定时器: ${msPerChar}ms/字');
        _karaokeTimer = Timer.periodic(
          Duration(milliseconds: msPerChar),
          (timer) {
            if (!_isPlayingFull || _highlightIndex >= _characters.length - 1) {
              timer.cancel();
              return;
            }
            if (mounted) {
              setState(() => _highlightIndex++);
            }
          },
        );
      }
    });

    // 播放 TTS
    await _tts.speak(_displayText);

    // 播放结束后清理
    _karaokeTimer?.cancel();
    _tts.onProgressCallback = null;
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

    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        setState(() => _tappedCharIndex = -1);
      }
    });

    await _tts.speak(char);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
    );
  }

  /// 欢迎/初始界面
  Widget _buildWelcomeView() {
    final config = _service.config.value;
    final knownCount = config?.knownHanziList.length ?? 0;
    final maxLevel = config?.unlockedMaxLevel ?? 1;

    return SingleChildScrollView(
      padding: EdgeInsets.all(20.w),
      child: Column(
        children: [
          SizedBox(height: 30.h),
          // 漂浮的卡通 Emoji
          AnimatedBuilder(
            animation: _floatAnimation,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, _floatAnimation.value),
                child: Text('🧒📖', style: TextStyle(fontSize: 64.sp)),
              );
            },
          ),
          SizedBox(height: 20.h),
          Text(
            '星海识字',
            style: TextStyle(
              fontSize: 28.sp,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF333333),
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            '在有趣的故事中读字、认字 ✨',
            style: TextStyle(
              fontSize: 14.sp,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 28.h),

          // 字库状态卡片
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(20.w),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFFF6B6B).withOpacity(0.12),
                  const Color(0xFFFFB347).withOpacity(0.12),
                ],
              ),
              borderRadius: BorderRadius.circular(22.r),
              border: Border.all(
                color: const Color(0xFFFF6B6B).withOpacity(0.25),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('📚', style: TextStyle(fontSize: 20.sp)),
                    SizedBox(width: 8.w),
                    Text(
                      '字库状态',
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFFFF6B6B),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12.h),
                if (knownCount > 0) ...[
                  Text(
                    '已解锁到第$maxLevel册',
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: Colors.grey[700],
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    '已认识 $knownCount 个字 ⭐',
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF333333),
                    ),
                  ),
                ] else ...[
                  Text(
                    '还没有设置字库哦 😊',
                    style: TextStyle(
                      fontSize: 16.sp,
                      color: const Color(0xFF333333),
                    ),
                  ),
                  SizedBox(height: 12.h),
                  ElevatedButton.icon(
                    onPressed: _showLevelSelector,
                    icon: const Icon(Icons.add),
                    label: const Text('开始设置'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B6B),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16.r),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: 28.h),

          // 开始学习按钮
          if (knownCount > 0)
            SizedBox(
              width: double.infinity,
              height: 56.h,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _generateContent,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B6B),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22.r),
                  ),
                  elevation: 6,
                  shadowColor: const Color(0xFFFF6B6B).withOpacity(0.4),
                ),
                child: _isLoading
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 20.w,
                            height: 20.w,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 12.w),
                          Text('✨ 魔法生成中...',
                              style: TextStyle(fontSize: 16.sp)),
                        ],
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('🚀', style: TextStyle(fontSize: 22.sp)),
                          SizedBox(width: 8.w),
                          Text(
                            '开始学习',
                            style: TextStyle(
                              fontSize: 18.sp,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
        ],
      ),
    );
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
                    color: coverage >= 0.85 ? const Color(0xFF4CAF50) : Colors.orange,
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
      child: Wrap(
        spacing: 2.w,
        runSpacing: 6.h,
        alignment: WrapAlignment.start,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: List.generate(_characters.length, (index) {
          final char = _characters[index];
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

          // 添加弹跳动画
          if (isTapped && _bounceAnimation != null) {
            charWidget = AnimatedBuilder(
              animation: _bounceAnimation!,
              builder: (context, child) {
                return Transform.scale(
                  scale: _bounceAnimation!.value,
                  child: child,
                );
              },
              child: charWidget,
            );
          }

          return charWidget;
        }),
      ),
    );
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
                    final result =
                        await Get.to(() => const HanziLibraryPage());
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
              color: isDisabled
                  ? Colors.grey.shade200
                  : color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(18.r),
              border: Border.all(
                color: isDisabled
                    ? Colors.grey.shade300
                    : color.withOpacity(0.4),
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
                    padding: EdgeInsets.symmetric(
                        horizontal: 8.w, vertical: 4.h),
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
