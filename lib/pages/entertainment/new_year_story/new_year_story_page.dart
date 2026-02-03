import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../../data/new_year_story_data.dart';
import '../../../theme/app_theme.dart';
import '../../../services/tts_service.dart';
import '../../../services/openai_service.dart';
import '../../../services/story_management_service.dart';
import '../../../controllers/app_mode_controller.dart';
import 'story_management_page.dart';
import '../../../models/new_year_story.dart';
import '../../../models/openai_config.dart';
import '../../../services/quiz_service.dart';

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
  final QuizService _quizService =
      Get.find<QuizService>(); // Added for AI Settings

  // 故事列表
  List<Map<String, dynamic>> _stories = [];

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

  // TTS 设置 - Removed local state to use TtsService global persistence

  @override
  void initState() {
    super.initState();
    _loadStories();
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
      );

      // 播放问题
      final question = page['question'] as Map<String, dynamic>;
      await Future.delayed(const Duration(milliseconds: 500)); // 短暂停顿
      await _tts.speak(
        question['text'] as String,
      );

      // 显示问题
      setState(() {
        _showQuestion = true;
      });
      // 暂停自动播放,等待用户回答
      return;
    }

    // 计算理论播放时长 (提前计算)
    final text = page['tts'] as String;

    // 1. 基础单字时长 (标准语速约 250ms)
    const baseCharMs = 260;

    // 2. 标点符号额外时长
    final punctuationCount = RegExp(r'[，。！？；：、,.!?;:]').allMatches(text).length;
    const punctuationMs = 400;

    // 3. 语速系数
    double rate = _tts.speechRate.value;
    if (rate <= 0.1) rate = 0.5;

    // 估算的总朗读时间 (ms)
    final estimatedDurationMs =
        ((text.length * baseCharMs + punctuationCount * punctuationMs) / rate)
            .toInt();

    // 4. 最小播放保障 (2秒)
    final minDurationMs = 2000;

    // 记录开始时间
    final startTime = DateTime.now();

    // 播放文本 (尝试等待播放完成)
    await _tts.speak(
      page['tts'],
    );

    // 计算实际已消耗时间
    final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;

    // 计算剩余需要等待的时间
    // 逻辑:
    // - 如果 await 生效(阻塞)，elapsedMs 会接近 estimatedDurationMs，剩余等待只需缓冲时间。
    // - 如果 await 不生效(非阻塞)，elapsedMs 很小，剩余等待需要补足 estimatedDurationMs。

    int waitMs = 0;
    // 目标总时长 = 估算时长(或最小保障) + 缓冲时间(1秒)
    final targetTotalMs = (estimatedDurationMs < minDurationMs
            ? minDurationMs
            : estimatedDurationMs) +
        1000;

    if (elapsedMs < targetTotalMs) {
      waitMs = targetTotalMs - elapsedMs;
    } else {
      // 如果实际播放时间已经超出了预期(例如语速极慢)，只给一个最小缓冲翻页
      waitMs = 500;
    }

    debugPrint(
        'TTS翻页逻辑: 字数${text.length} 估算${estimatedDurationMs}ms 实际耗时${elapsedMs}ms -> 额外等待${waitMs}ms');

    // 启动翻页定时器
    _autoPlayTimer = Timer(Duration(milliseconds: waitMs), () {
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
    );

    // 根据反馈文本长度计算等待时间
    // 正常语速(0.5)下，单字耗时约400ms(含停顿)
    // 基础系数设为 250ms (在rate=1.0时)
    final baseCharTimeMs = 250;
    final estimatedDurationMs =
        (feedbackText.length * baseCharTimeMs / _tts.speechRate.value).toInt();

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

  /// 播放问题和选项TTS
  Future<void> _playQuestionTts(Map<String, dynamic> question) async {
    if (_tts.isSpeaking.value) {
      await _tts.stop();
      return;
    }

    final text = question['text'] as String;
    final options = question['options'] as List;
    final sb = StringBuffer();
    sb.write(text);
    sb.write("。"); // Pause
    for (var opt in options) {
      sb.write(" $opt。");
    }

    await _tts.speak(sb.toString());
  }

  /// 加载故事列表
  Future<void> _loadStories() async {
    await _storyService.init();
    final stories = _storyService.getAllStoriesLegacy();

    // 如果为空（理论上不会，因为Service会导入内置），尝试手动加载静态
    if (stories.isEmpty) {
      final staticStories = NewYearStoryData.getAllStories();
      setState(() {
        _stories = staticStories;
      });
    } else {
      setState(() {
        _stories = stories;
      });
    }
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

      // 获取 AI 配置 (优先使用 QuizConfig 中的图片生成设置)
      final quizConfig = _quizService.config.value;
      OpenAIConfig? config;

      // 1. 尝试使用 QuizConfig 中保存的生图配置
      if (quizConfig?.imageGenConfigId != null) {
        config = _openAIService.configs
            .firstWhereOrNull((c) => c.id == quizConfig!.imageGenConfigId);
      }

      // 2. 如果没找到或没配置,尝试使用当前选中的全局配置
      if (config == null) {
        final currentGlobal = _openAIService.currentConfig.value;
        if (currentGlobal != null) {
          config = _openAIService.configs
              .firstWhereOrNull((c) => c.id == currentGlobal.id);
        }
      }

      // 3. 最后的兜底
      config ??= _openAIService.configs.first;

      final usedModel = quizConfig
          ?.imageGenModel; // 可能为 null, generateImages 会自动处理(用默认或dall-e-3)

      // 显示加载对话框 (Styled with Get.dialog)
      Get.dialog(
        AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              SizedBox(height: 16.h),
              const Text('正在优化提示词...',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        barrierDismissible: false,
      );

      // 构建提示词
      final pageText = page['text'] as String;
      final prompt = '请为以下儿童故事情节生成一张可爱的插画:\n$pageText';

      // 1. 调用AI生成图片提示词
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

      // 更新加载提示
      // 更新加载提示
      if (Get.isDialogOpen ?? false)
        Get.back(); // Close previous dialog safe check
      Get.dialog(
        AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              SizedBox(height: 16.h),
              const Text('正在生成备选图片...',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              if (usedModel != null)
                Text('模型: $usedModel',
                    style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
        ),
        barrierDismissible: false,
      );

      // 2. 调用生图API (生成4张)
      // 注意：OpenAIService 需要支持 generateImages 返回 List<String>
      // 如果不支持，需要先修改 OpenAIService (已完成)
      final imageUrls = await _openAIService.generateImages(
        prompt: imagePrompt,
        n: 4,
        config: config,
        model: usedModel,
      );

      // 关闭加载对话框
      if (Get.isDialogOpen ?? false) Get.back();

      if (imageUrls.isEmpty) {
        Get.snackbar(
          '错误',
          '未能生成图片',
          snackPosition: SnackPosition.TOP,
          backgroundColor: Colors.red.withOpacity(0.8),
          colorText: Colors.white,
        );
        return;
      }

      // 3. 显示图片选择对话框 (直接显示URL/Base64图片)
      final selectedIndex = await showDialog<int>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('请选择一张喜欢的图片'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400.h,
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 8.w,
                mainAxisSpacing: 8.h,
              ),
              itemCount: imageUrls.length,
              itemBuilder: (context, index) {
                final imageUrl = imageUrls[index];
                return GestureDetector(
                  onTap: () => Navigator.pop(context, index),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _buildImageWidget(imageUrl),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context), // 返回 null
              child: const Text('取消'),
            ),
          ],
        ),
      );

      if (selectedIndex == null) {
        // 用户取消
        return;
      }

      // 4. 下载选中的图片到本地
      Get.dialog(
        AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              SizedBox(height: 16.h),
              const Text('正在保存图片...',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        barrierDismissible: false,
      );

      final selectedUrl = imageUrls[selectedIndex];
      final finalPath = await _downloadAndSaveImage(
        selectedUrl,
        '${_currentStory!['id']}_${_currentPageIndex}_${DateTime.now().millisecondsSinceEpoch}',
      );

      // 更新当前页面的图片路径
      page['image'] = finalPath;

      // 5. 保存到数据库
      final storyId = _currentStory!['id'] as String;

      // 注意：这里需要根据 storyId 查找是在 Service 里的动态故事，还是静态故事
      // 静态故事无法持久化保存修改，必须先"另存为"动态故事，或者我们假定用户只能修改动态故事。
      // 如果用户修改静态故事，我们应该提示或者将其转存为动态故事。
      // 为简化逻辑，我们尝试在 StoryService 中查找。找不到则创建。

      var story = _storyService.getStoryById(storyId);
      if (story == null) {
        // 如果是静态故事，创建一个新的动态副本
        // 先提示用户
        // 但为了流畅体验，我们静默创建副本？或者只在内存中修改？
        // 简单起见，如果是在 storyService 中找不到，我们不做持久化（或者报错）。
        // 但通常 flow 是：用户玩静态故事 -> 重新生成图片 -> 期望保存。
        // 我们需要把当前 _currentStory 存入 storyService。

        // 这里的 _currentStory 是 Map。转 Save。
        // 暂不支持修改静态故事并保存为新故事的复杂逻辑，
        // 假设用户操作的是已经存在的动态故事，或者接受只能在内存中修改（重启丢失）。
        // 但用户肯定希望保存。

        // 尝试创建/更新
        final newStory = NewYearStory(
          id: storyId, // 保持ID? 如果ID与静态冲突，可能会有问题。但前面load逻辑是合并。
          title: _currentStory!['title'],
          emoji: _currentStory!['emoji'],
          duration: _currentStory!['duration'],
          pagesJson: jsonEncode(_currentStory!['pages']),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await _storyService.addStory(newStory);
      } else {
        // 更新现有故事
        final pages = _currentStory!['pages'] as List;
        story.pagesJson = jsonEncode(pages);
        story.updatedAt = DateTime.now();
        await _storyService.updateStory(story);
      }

      debugPrint('图片生成成功: $finalPath');

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

      // 显示错误提示 (显示原始错误信息)
      Get.snackbar(
        '生成失败',
        '$e'.replaceAll('Exception:', ''),
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red.withOpacity(0.9),
        colorText: Colors.white,
        duration: const Duration(seconds: 5), // 显示久一点
      );
    }
  }

  /// 构建图片Widget，支持URL、Base64和本地文件
  Widget _buildImageWidget(String imageSource, {BoxFit fit = BoxFit.cover}) {
    // 判断图片来源类型
    if (imageSource.startsWith('data:image')) {
      // Base64格式
      try {
        final base64Data = imageSource.split(',')[1];
        final bytes = base64Decode(base64Data);
        return Image.memory(
          bytes,
          fit: fit,
          errorBuilder: (ctx, error, stack) {
            return const Center(
              child: Icon(Icons.error, color: Colors.red),
            );
          },
        );
      } catch (e) {
        debugPrint('Base64图片解析失败: $e');
        return const Center(
          child: Icon(Icons.error, color: Colors.red),
        );
      }
    } else if (imageSource.startsWith('http://') ||
        imageSource.startsWith('https://')) {
      // URL格式
      return Image.network(
        imageSource,
        fit: fit,
        loadingBuilder: (ctx, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                      loadingProgress.expectedTotalBytes!
                  : null,
            ),
          );
        },
        errorBuilder: (ctx, error, stack) {
          return const Center(
            child: Icon(Icons.error, color: Colors.red),
          );
        },
      );
    } else {
      // 本地文件路径
      return Image.file(
        File(imageSource),
        fit: fit,
        errorBuilder: (ctx, error, stack) {
          return const Center(
            child: Icon(Icons.error, color: Colors.red),
          );
        },
      );
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

  /// 下载并保存图片
  /// 下载并转换为Base64 (保存到数据库)
  Future<String> _downloadAndSaveImage(
      String urlOrDataUri, String imageId) async {
    try {
      // 如果已是 Base64，直接返回
      if (urlOrDataUri.startsWith('data:image')) {
        return urlOrDataUri;
      }

      // 下载并转换为 Base64
      debugPrint('📥 从URL下载图片并转Base64: $urlOrDataUri');
      final response = await http
          .get(Uri.parse(urlOrDataUri))
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final base64String = base64Encode(response.bodyBytes);
        // 假设是 PNG
        return 'data:image/png;base64,$base64String';
      } else {
        throw Exception('下载图片失败: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('转换图片失败: $e');
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
            onPressed: () async {
              await Get.to(() => const StoryManagementPage());
              // 从管理页面返回后刷新数据
              _loadStories();
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
    final imagePath = page['image'] as String?;
    bool showImage = false;
    if (imagePath != null && imagePath.isNotEmpty) {
      if (kIsWeb) {
        showImage =
            imagePath.startsWith('http') || imagePath.startsWith('data:');
      } else {
        showImage = imagePath.startsWith('http') ||
            imagePath.startsWith('data:') ||
            File(imagePath).existsSync();
      }
    }

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
                // Emoji 插图或图片
                if (showImage)
                  Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16.r),
                        child: GestureDetector(
                          onTap: () =>
                              _showFullScreenImage(context, imagePath!),
                          child: AspectRatio(
                            aspectRatio: 1.0, // 使用 1:1 比例显示，避免裁剪过多
                            child: _buildImageWidget(imagePath!,
                                fit: BoxFit.cover),
                          ),
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
                Expanded(
                  child: Text(
                    question['text'],
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade900,
                    ),
                  ),
                ),
                Obx(() => IconButton(
                      onPressed: () => _playQuestionTts(question),
                      icon: Icon(
                        _tts.isSpeaking.value &&
                                _currentStory != null // 简单判断，或者需要更精确的状
                            ? Icons.pause_circle_filled
                            : Icons.volume_up,
                        color: Colors.blue,
                        size: 24.sp,
                      ),
                      tooltip: '朗读题目',
                    )),
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
                                '小朋友，新年快乐！这是一个精彩的故事。',
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
