import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../data/new_year_story_data.dart';
import '../../../theme/app_theme.dart';
import '../../../services/tts_service.dart';

/// 新年故事听听页面
class NewYearStoryPage extends StatefulWidget {
  const NewYearStoryPage({super.key});

  @override
  State<NewYearStoryPage> createState() => _NewYearStoryPageState();
}

class _NewYearStoryPageState extends State<NewYearStoryPage>
    with TickerProviderStateMixin {
  // 使用全局 TTS 服务
  final TtsService _tts = Get.find<TtsService>();

  // 故事列表
  final List<Map<String, dynamic>> _stories = NewYearStoryData.getAllStories();

  // 当前选中的故事
  Map<String, dynamic>? _currentStory;

  // 当前页面索引
  int _currentPageIndex = 0;

  // 页面控制器
  late PageController _pageController;

  // 是否正在播放
  bool _isPlaying = false;

  // 定时器
  Timer? _autoPlayTimer;

  // 翻页动画控制器
  late AnimationController _pageFlipController;

  // 小年兽动画控制器
  late AnimationController _beastController;
  late Animation<double> _beastAnimation;

  // 是否显示互动问题
  bool _showQuestion = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();

    // 初始化翻页动画
    _pageFlipController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    // 初始化小年兽动画
    _beastController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);

    _beastAnimation = Tween<double>(begin: -5, end: 5).animate(
      CurvedAnimation(parent: _beastController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _tts.stop();
    _autoPlayTimer?.cancel();
    _pageController.dispose();
    _pageFlipController.dispose();
    _beastController.dispose();
    super.dispose();
  }

  /// 选择故事
  void _selectStory(Map<String, dynamic> story) {
    setState(() {
      _currentStory = story;
      _currentPageIndex = 0;
      _showQuestion = false;
    });
    _pageController.jumpToPage(0);
  }

  /// 开始播放故事
  void _startPlaying() {
    if (_currentStory == null) return;

    setState(() {
      _isPlaying = true;
    });

    _playCurrentPage();
  }

  /// 播放当前页
  void _playCurrentPage() async {
    if (!_isPlaying || _currentStory == null) return;

    final pages = _currentStory!['pages'] as List;
    if (_currentPageIndex >= pages.length) {
      _stopPlaying();
      _showCompletionDialog();
      return;
    }

    final page = pages[_currentPageIndex];

    // 检查是否有互动问题
    if (page['question'] != null) {
      // 先播放文本
      await _tts.speak(page['tts']);
      // 显示问题
      setState(() {
        _showQuestion = true;
      });
      // 暂停自动播放,等待用户回答
      return;
    }

    // 播放文本
    await _tts.speak(page['tts']);

    // 等待一段时间后翻页
    _autoPlayTimer = Timer(const Duration(seconds: 2), () {
      if (_isPlaying && _currentPageIndex < pages.length - 1) {
        _nextPage();
      } else {
        _stopPlaying();
        _showCompletionDialog();
      }
    });
  }

  /// 停止播放
  void _stopPlaying() {
    setState(() {
      _isPlaying = false;
    });
    _tts.stop();
    _autoPlayTimer?.cancel();
  }

  /// 下一页
  void _nextPage() {
    if (_currentStory == null) return;

    final pages = _currentStory!['pages'] as List;
    if (_currentPageIndex < pages.length - 1) {
      setState(() {
        _currentPageIndex++;
        _showQuestion = false;
      });
      _pageController.nextPage(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
      _pageFlipController.forward(from: 0);

      if (_isPlaying) {
        _playCurrentPage();
      }
    }
  }

  /// 上一页
  void _prevPage() {
    if (_currentPageIndex > 0) {
      setState(() {
        _currentPageIndex--;
        _showQuestion = false;
      });
      _pageController.previousPage(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
      _pageFlipController.forward(from: 0);
    }
  }

  /// 回答问题
  void _answerQuestion(int selectedIndex) {
    if (_currentStory == null) return;

    final pages = _currentStory!['pages'] as List;
    final page = pages[_currentPageIndex];
    final question = page['question'];
    final isCorrect = selectedIndex == question['correctIndex'];

    // 播放反馈
    if (isCorrect) {
      _tts.speak('答对啦!真棒!');
    } else {
      _tts.speak('再想想哦~正确答案是${question['options'][question['correctIndex']]}');
    }

    // 延迟后继续播放
    Future.delayed(const Duration(seconds: 2), () {
      setState(() {
        _showQuestion = false;
      });

      if (_isPlaying) {
        // 继续下一页
        Future.delayed(const Duration(seconds: 1), () {
          if (_currentPageIndex < pages.length - 1) {
            _nextPage();
          } else {
            _stopPlaying();
            _showCompletionDialog();
          }
        });
      }
    });
  }

  /// 显示完成对话框
  void _showCompletionDialog() {
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24.r),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '🎉',
              style: TextStyle(fontSize: 80.sp),
            ),
            SizedBox(height: 16.h),
            Text(
              '故事讲完啦!',
              style: TextStyle(
                fontSize: 24.sp,
                fontWeight: FontWeight.bold,
                color: AppTheme.textMain,
              ),
            ),
            SizedBox(height: 12.h),
            Text(
              '你学到新知识了吗?',
              style: TextStyle(
                fontSize: 16.sp,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Get.back();
              setState(() {
                _currentStory = null;
                _currentPageIndex = 0;
              });
            },
            child: const Text('选其他故事'),
          ),
          ElevatedButton(
            onPressed: () {
              Get.back();
              setState(() {
                _currentPageIndex = 0;
                _showQuestion = false;
              });
              _pageController.jumpToPage(0);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
            ),
            child: const Text('再听一遍'),
          ),
        ],
      ),
    );

    _tts.speak('故事讲完啦!你学到新知识了吗?');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8E1),
      appBar: AppBar(
        title: const Text('新年故事听听'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: _currentStory == null ? _buildStoryList() : _buildStoryReader(),
      ),
    );
  }

  /// 故事列表
  Widget _buildStoryList() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.all(20.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 欢迎卡片
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(20.w),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFB74D), Color(0xFFFF8A65)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24.r),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFB74D).withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                // 小年兽
                AnimatedBuilder(
                  animation: _beastAnimation,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(0, _beastAnimation.value),
                      child: Text(
                        '🧧',
                        style: TextStyle(fontSize: 60.sp),
                      ),
                    );
                  },
                ),
                SizedBox(width: 16.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '选一个故事听听吧!',
                        style: TextStyle(
                          fontSize: 20.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        '小年兽会给你讲故事哦~',
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 24.h),

          // 故事列表
          Text(
            '📚 故事列表',
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.bold,
              color: AppTheme.textMain,
            ),
          ),
          SizedBox(height: 12.h),

          ...List.generate(_stories.length, (index) {
            final story = _stories[index];
            return Padding(
              padding: EdgeInsets.only(bottom: 12.h),
              child: GestureDetector(
                onTap: () => _selectStory(story),
                child: Container(
                  padding: EdgeInsets.all(16.w),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20.r),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Emoji 图标
                      Container(
                        width: 56.w,
                        height: 56.w,
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(16.r),
                        ),
                        child: Center(
                          child: Text(
                            story['emoji'],
                            style: TextStyle(fontSize: 32.sp),
                          ),
                        ),
                      ),
                      SizedBox(width: 16.w),

                      // 故事信息
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              story['title'],
                              style: TextStyle(
                                fontSize: 16.sp,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textMain,
                              ),
                            ),
                            SizedBox(height: 4.h),
                            Row(
                              children: [
                                Icon(
                                  Icons.access_time,
                                  size: 14.sp,
                                  color: Colors.grey,
                                ),
                                SizedBox(width: 4.w),
                                Text(
                                  story['duration'],
                                  style: TextStyle(
                                    fontSize: 12.sp,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // 箭头
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 16.sp,
                        color: Colors.grey,
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
  }

  /// 故事阅读器
  Widget _buildStoryReader() {
    final pages = _currentStory!['pages'] as List;

    return Column(
      children: [
        // 进度条
        Container(
          padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
          child: Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: (_currentPageIndex + 1) / pages.length,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
                  minHeight: 6.h,
                  borderRadius: BorderRadius.circular(3.r),
                ),
              ),
              SizedBox(width: 12.w),
              Text(
                '${_currentPageIndex + 1}/${pages.length}',
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
        ),

        // 故事内容
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(), // 禁用手势滑动
            itemCount: pages.length,
            onPageChanged: (index) {
              setState(() {
                _currentPageIndex = index;
              });
            },
            itemBuilder: (context, index) {
              return _buildStoryPage(pages[index]);
            },
          ),
        ),

        // 控制按钮
        _buildControlButtons(),
      ],
    );
  }

  /// 故事页面
  Widget _buildStoryPage(Map<String, dynamic> page) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.all(20.w),
      child: Column(
        children: [
          // 书页效果
          Container(
            width: double.infinity,
            constraints: BoxConstraints(minHeight: 400.h),
            padding: EdgeInsets.all(32.w),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24.r),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Emoji 插图
                Text(
                  page['emoji'],
                  style: TextStyle(fontSize: 100.sp),
                ),
                SizedBox(height: 32.h),

                // 文本内容
                Text(
                  page['text'],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18.sp,
                    height: 1.8,
                    color: AppTheme.textMain,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // 互动问题
          if (_showQuestion && page['question'] != null)
            _buildQuestionCard(page['question']),
        ],
      ),
    );
  }

  /// 互动问题卡片
  Widget _buildQuestionCard(Map<String, dynamic> question) {
    return Padding(
      padding: EdgeInsets.only(top: 20.h),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(20.w),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade50, Colors.purple.shade50],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24.r),
          border: Border.all(color: Colors.blue.shade200, width: 2),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.help_outline, color: Colors.blue, size: 24.sp),
                SizedBox(width: 8.w),
                Text(
                  question['text'],
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade900,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16.h),

            // 选项
            ...List.generate(
              (question['options'] as List).length,
              (index) {
                return Padding(
                  padding: EdgeInsets.only(bottom: 8.h),
                  child: ElevatedButton(
                    onPressed: () => _answerQuestion(index),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.blue.shade900,
                      padding: EdgeInsets.symmetric(
                        horizontal: 20.w,
                        vertical: 12.h,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16.r),
                      ),
                      elevation: 2,
                    ),
                    child: Text(
                      question['options'][index],
                      style: TextStyle(fontSize: 14.sp),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 控制按钮
  Widget _buildControlButtons() {
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
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 上一页
          _buildControlButton(
            icon: Icons.arrow_back_ios,
            label: '上一页',
            onTap: _currentPageIndex > 0 ? _prevPage : null,
          ),

          // 播放/暂停
          _buildControlButton(
            icon: _isPlaying ? Icons.pause : Icons.play_arrow,
            label: _isPlaying ? '暂停' : '播放',
            color: AppTheme.primary,
            onTap: _isPlaying ? _stopPlaying : _startPlaying,
          ),

          // 下一页
          _buildControlButton(
            icon: Icons.arrow_forward_ios,
            label: '下一页',
            onTap:
                _currentPageIndex < (_currentStory!['pages'] as List).length - 1
                    ? _nextPage
                    : null,
          ),
        ],
      ),
    );
  }

  /// 控制按钮
  Widget _buildControlButton({
    required IconData icon,
    required String label,
    Color? color,
    VoidCallback? onTap,
  }) {
    final isDisabled = onTap == null;
    final buttonColor =
        isDisabled ? Colors.grey.shade300 : (color ?? Colors.deepOrange);

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
