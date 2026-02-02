import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import '../../../data/new_year_story_data.dart';
import '../../../theme/app_theme.dart';
import '../../../services/tts_service.dart';
import '../../../services/openai_service.dart';
import '../../../services/story_management_service.dart';
import '../../../controllers/app_mode_controller.dart';
import 'story_management_page.dart';

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
  final OpenAIService _openAIService = Get.find<OpenAIService>();
  final AppModeController _modeController = Get.find<AppModeController>();
  final StoryManagementService _storyService = StoryManagementService.instance;

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

  // TTS 设置
  final RxDouble _ttsRate = 0.5.obs; // 语速 0.0 - 1.0
  final RxDouble _ttsPitch = 1.0.obs; // 音调 0.5 - 2.0
  final RxDouble _ttsVolume = 1.0.obs; // 音量 0.0 - 1.0

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
      await _tts.speak(
        page['tts'],
        rate: _ttsRate.value,
        pitch: _ttsPitch.value,
        volume: _ttsVolume.value,
      );

      // 播放问题
      final question = page['question'] as Map<String, dynamic>;
      await Future.delayed(const Duration(milliseconds: 500)); // 短暂停顿
      await _tts.speak(
        question['text'] as String,
        rate: _ttsRate.value,
        pitch: _ttsPitch.value,
        volume: _ttsVolume.value,
      );

      // 显示问题
      setState(() {
        _showQuestion = true;
      });
      // 暂停自动播放,等待用户回答
      return;
    }

    // 播放文本
    await _tts.speak(
      page['tts'],
      rate: _ttsRate.value,
      pitch: _ttsPitch.value,
      volume: _ttsVolume.value,
    );

    // 根据文本长度和语速估算播放时间
    final text = page['tts'] as String;

    // 计算公式: (字数 * 单字耗时) / 语速
    // 正常语速(0.5)下，每个字约需400-500ms(含停顿)
    // 基础系数设为 250ms (在rate=1.0时)
    // 当 rate=0.5时，时间 = 250 / 0.5 = 500ms/字
    final baseCharTimeMs = 250;
    final estimatedDurationMs =
        (text.length * baseCharTimeMs / _ttsRate.value).toInt();

    // 额外等待1.5秒确保播放完成(尾部的停顿)
    final waitDuration = Duration(milliseconds: estimatedDurationMs + 1500);

    // 等待TTS播放完成后翻页
    _autoPlayTimer = Timer(waitDuration, () {
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
  Future<void> _answerQuestion(int selectedIndex) async {
    if (_currentStory == null) return;

    final pages = _currentStory!['pages'] as List;
    final page = pages[_currentPageIndex];
    final question = page['question'];
    final isCorrect = selectedIndex == question['correctIndex'];

    String feedbackText;
    if (isCorrect) {
      feedbackText = '答对啦!真棒!';
    } else {
      feedbackText =
          '再想想哦~正确答案是${question['options'][question['correctIndex']]}';
    }

    await _tts.speak(
      feedbackText,
      rate: _ttsRate.value,
      pitch: _ttsPitch.value,
      volume: _ttsVolume.value,
    );

    // 根据反馈文本长度计算等待时间
    // 正常语速(0.5)下，单字耗时约400ms(含停顿)
    // 基础系数设为 250ms (在rate=1.0时)
    final baseCharTimeMs = 250;
    final estimatedDurationMs =
        (feedbackText.length * baseCharTimeMs / _ttsRate.value).toInt();

    // 额外等待1秒
    final waitDuration = Duration(milliseconds: estimatedDurationMs + 1000);

    // 延迟后继续播放
    Future.delayed(waitDuration, () {
      setState(() {
        _showQuestion = false;
      });

      // 回答完问题后,继续下一页
      if (_currentPageIndex < pages.length - 1) {
        _nextPage();
      } else {
        _stopPlaying();
        _showCompletionDialog();
      }
    });
  }

  /// 重新生成当前页面的图片
  Future<void> _regenerateCurrentPageImage(Map<String, dynamic> page) async {
    if (_currentStory == null) return;

    try {
      // 检查是否配置了OpenAI
      if (_openAIService.configs.isEmpty) {
        Get.snackbar(
          '提示',
          '请先在故事管理中配置AI生成',
          snackPosition: SnackPosition.TOP,
          backgroundColor: Colors.orange.withOpacity(0.8),
          colorText: Colors.white,
        );
        return;
      }

      // 显示加载对话框
      Get.dialog(
        const Center(child: CircularProgressIndicator()),
        barrierDismissible: false,
      );

      // 获取第一个可用的配置
      final config = _openAIService.configs.first;

      // 构建提示词
      final pageText = page['text'] as String;
      final prompt = '请为以下儿童故事情节生成一张可爱的插画:\n$pageText';

      // 调用AI生成图片提示词
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
        userMessage: prompt,
        config: config,
      );

      debugPrint('生成的图片提示词: $imagePrompt');

      // 调用生图API
      final imageUrl = await _generateImage(imagePrompt, config);

      // 下载并保存图片
      final imagePath = await _downloadAndSaveImage(
        imageUrl,
        '${_currentStory!['id']}_${_currentPageIndex}',
      );

      // 更新当前页面的图片路径
      page['image'] = imagePath;

      // 保存到数据库
      final storyId = _currentStory!['id'] as String;
      final story = _storyService.getStoryById(storyId);
      if (story != null) {
        // 更新story的pages数据
        final pages = _currentStory!['pages'] as List;
        story.pagesJson = jsonEncode(pages);
        await _storyService.updateStory(story);
        debugPrint('故事图片已保存到数据库: $imagePath');
      }

      // 关闭加载对话框
      if (Get.isDialogOpen ?? false) Get.back();

      // 显示成功提示
      Get.snackbar(
        '成功',
        '图片生成成功并已保存',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.green.withOpacity(0.8),
        colorText: Colors.white,
      );

      // 刷新界面
      setState(() {});
    } catch (e) {
      // 关闭加载对话框
      if (Get.isDialogOpen ?? false) Get.back();

      // 显示错误提示
      Get.snackbar(
        '错误',
        '生成失败: $e',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red.withOpacity(0.8),
        colorText: Colors.white,
      );
    }
  }

  /// 调用生图 API
  Future<String> _generateImage(String prompt, dynamic config) async {
    try {
      final uri = Uri.parse('${config.baseUrl}/v1/images/generations');
      final response = await http
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer ${config.apiKey}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': config.selectedModel.isNotEmpty
                  ? config.selectedModel
                  : 'dall-e-3',
              'prompt': prompt,
              'n': 1,
              'size': '1024x1024',
              'quality': 'standard',
            }),
          )
          .timeout(const Duration(seconds: 120));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final imageUrl = data['data'][0]['url'] as String;
        return imageUrl;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(
            error['error']?['message'] ?? '生成图片失败: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('生图 API 调用失败: $e');
      rethrow;
    }
  }

  /// 下载并保存图片
  Future<String> _downloadAndSaveImage(String url, String imageId) async {
    try {
      // 获取应用文档目录
      final appDir = await getApplicationDocumentsDirectory();
      final imageDir = Directory('${appDir.path}/story_images');

      // 确保目录存在
      if (!await imageDir.exists()) {
        await imageDir.create(recursive: true);
      }

      // 下载图片
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final file = File('${imageDir.path}/$imageId.png');
        await file.writeAsBytes(response.bodyBytes);
        return file.path;
      } else {
        throw Exception('下载图片失败: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('下载图片失败: $e');
      rethrow;
    }
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

    _tts.speak(
      '故事讲完啦!你学到新知识了吗?',
      rate: _ttsRate.value,
      pitch: _ttsPitch.value,
      volume: _ttsVolume.value,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8E1),
      appBar: AppBar(
        title: const Text('新年故事听听'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          // 语音设置按钮
          IconButton(
            icon: const Icon(Icons.volume_up),
            tooltip: '语音设置',
            onPressed: _showTtsSettings,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '故事管理',
            onPressed: () {
              Get.to(() => const StoryManagementPage());
            },
          ),
        ],
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
                // Emoji 插图或图片
                if (page['image'] != null &&
                    page['image'].isNotEmpty &&
                    File(page['image']).existsSync())
                  Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16.r),
                        child: Image.file(
                          File(page['image']),
                          height: 250.h,
                          fit: BoxFit.cover,
                        ),
                      ),
                      SizedBox(height: 32.h),
                    ],
                  )
                else ...[
                  Text(
                    page['emoji'],
                    style: TextStyle(fontSize: 100.sp),
                  ),
                  SizedBox(height: 32.h),
                ],

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

          // 重新生成图片按钮(仅家长模式)
          Obx(() {
            if (!_modeController.isParentMode) {
              return const SizedBox.shrink();
            }

            return Padding(
              padding: EdgeInsets.only(top: 16.h, bottom: 8.h),
              child: OutlinedButton.icon(
                onPressed: () => _regenerateCurrentPageImage(page),
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
                    horizontal: 20.w,
                    vertical: 12.h,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24.r),
                  ),
                ),
              ),
            );
          }),

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
              color: isDisabled
                  ? Colors.grey.shade200
                  : buttonColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(18.r),
              border: Border.all(
                color: isDisabled
                    ? Colors.grey.shade300
                    : buttonColor.withOpacity(0.3),
                width: 2,
              ),
            ),
            child: Icon(
              icon,
              color: isDisabled ? Colors.grey.shade400 : buttonColor,
              size: 28.sp,
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
                      _ttsRate.value = 0.5;
                      _ttsPitch.value = 1.0;
                      _ttsVolume.value = 1.0;
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
                                '小朋友，新年快乐！这是一个精彩的故事。',
                                rate: _ttsRate.value,
                                pitch: _ttsPitch.value,
                                volume: _ttsVolume.value,
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
                        SizedBox(width: 16.w),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              _tts.speak(
                                '谜语测试: 什么动物跑得最快?',
                                rate: _ttsRate.value,
                                pitch: _ttsPitch.value,
                                volume: _ttsVolume.value,
                              );
                            },
                            icon: const Icon(Icons.face),
                            label: const Text('谜语测试'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.pink,
                              side: BorderSide(color: Colors.pink.shade200),
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
                value: _ttsRate,
                min: 0.0,
                max: 1.0,
                label: '1.0 为正常语速',
                color: Colors.amber,
              ),
              SizedBox(height: 16.h),

              // 音调控制
              _buildSliderControl(
                icon: Icons.music_note,
                title: '音调',
                value: _ttsPitch,
                min: 0.5,
                max: 2.0,
                label: '1.0 为正常音调',
                color: Colors.amber,
              ),
              SizedBox(height: 16.h),

              // 音量控制
              _buildSliderControl(
                icon: Icons.volume_up,
                title: '音量',
                value: _ttsVolume,
                min: 0.0,
                max: 1.0,
                label: '1.0 为最大音量',
                color: Colors.amber,
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
