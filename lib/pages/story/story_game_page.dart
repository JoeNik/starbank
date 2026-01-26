import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import '../../models/story_session.dart';
import '../../models/story_game_config.dart';
import '../../models/openai_config.dart';
import '../../controllers/user_controller.dart';
import '../../services/openai_service.dart';
import '../../services/tts_service.dart';
import '../../theme/app_theme.dart';
import 'story_game_settings_page.dart';
import 'story_images.dart';

/// 图片描述故事游戏页面
class StoryGamePage extends StatefulWidget {
  const StoryGamePage({super.key});

  @override
  State<StoryGamePage> createState() => _StoryGamePageState();
}

class _StoryGamePageState extends State<StoryGamePage> {
  final UserController _userController = Get.find<UserController>();
  late OpenAIService _openAIService;
  late TtsService _ttsService;

  // 语音识别
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;
  String _recognizedText = '';

  // 录音时长限制（最长30秒）
  static const int _maxRecordingSeconds = 30;
  int _recordingSecondsLeft = _maxRecordingSeconds;
  DateTime? _recordingStartTime;

  // 游戏状态
  bool _isLoading = true;
  bool _isGeneratingImage = false;
  bool _isAIResponding = false;
  String _currentImageUrl = '';
  List<Map<String, dynamic>> _messages = [];
  int _currentRound = 0;
  bool _gameStarted = false;
  bool _gameEnded = false;
  int _finalScore = 0;

  // 输入控制
  final TextEditingController _textController = TextEditingController();
  bool _useKeyboard = false;

  // 配置
  late Box<StorySession> _sessionBox;
  late Box _configBox;
  StoryGameConfig? _gameConfig;
  StorySession? _currentSession;

  // 今日游戏次数
  int _todayPlayCount = 0;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _speech.stop();
    _ttsService.stop();
    _textController.dispose();

    // 保存未完成的会话
    if (_currentSession != null && !_gameEnded && _messages.isNotEmpty) {
      _currentSession!.messages = List<Map<String, dynamic>>.from(_messages);
      _currentSession!.save(); // 使用 save() 方法
      debugPrint(
          '退出时保存未完成会话: ${_currentSession!.id}, 消息数: ${_messages.length}');
    }

    super.dispose();
  }

  Future<void> _initData() async {
    try {
      setState(() => _isLoading = true);

      // 初始化服务
      if (!Get.isRegistered<OpenAIService>()) {
        await Get.putAsync(() => OpenAIService().init());
      }
      _openAIService = Get.find<OpenAIService>();

      if (!Get.isRegistered<TtsService>()) {
        await Get.putAsync(() => TtsService().init());
      }
      _ttsService = Get.find<TtsService>();

      // 注册 Hive 适配器
      if (!Hive.isAdapterRegistered(13)) {
        Hive.registerAdapter(StorySessionAdapter());
      }
      if (!Hive.isAdapterRegistered(14)) {
        Hive.registerAdapter(StoryGameConfigAdapter());
      }

      // 打开数据库
      _sessionBox = await Hive.openBox<StorySession>('story_sessions');
      _configBox = await Hive.openBox('story_game_config');

      // 加载配置
      _loadConfig();

      // 计算今日游戏次数
      _calculateTodayPlayCount();

      // 初始化语音识别（需要麦克风权限）
      try {
        var status = await Permission.microphone.status;
        if (!status.isGranted) {
          status = await Permission.microphone.request();
        }

        if (status.isGranted) {
          _speechAvailable = await _speech.initialize(
            onError: (error) {
              debugPrint('Speech error: $error');
              // 如果错误是永久性的，禁用语音
              if (error.permanent) {
                setState(() {
                  _speechAvailable = false;
                  _useKeyboard = true;
                });
              }
            },
            onStatus: (status) => debugPrint('Speech status: $status'),
            debugLogging: true, // 开启调试日志
          );
        } else {
          debugPrint('麦克风权限被拒绝');
          _speechAvailable = false;
        }

        if (!_speechAvailable) {
          debugPrint('语音识别初始化失败，可能缺少 Google 服务或麦克风权限');
          _useKeyboard = true; // 自动启用键盘

          Get.snackbar(
            '语音不可用',
            '请检查是否安装了 Google App 或开启了麦克风权限',
            snackPosition: SnackPosition.BOTTOM,
            duration: const Duration(seconds: 5),
            mainButton: TextButton(
              onPressed: () => openAppSettings(),
              child: const Text('去设置', style: TextStyle(color: Colors.blue)),
            ),
          );
        }
      } catch (e) {
        debugPrint('语音识别初始化异常: $e');
        _speechAvailable = false;
        _useKeyboard = true;
      }

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('初始化故事游戏失败: $e');
      setState(() => _isLoading = false);
      Get.snackbar('错误', '初始化失败: $e', snackPosition: SnackPosition.BOTTOM);
    }
  }

  void _loadConfig() {
    final configMap = _configBox.get('config');
    if (configMap != null) {
      _gameConfig =
          StoryGameConfig.fromJson(Map<String, dynamic>.from(configMap));
    } else {
      // 使用默认配置
      _gameConfig = StoryGameConfig(id: 'default');
    }
  }

  void _calculateTodayPlayCount() {
    final today = DateTime.now();
    final babyId = _userController.currentBaby.value?.id;
    if (babyId == null) return;

    _todayPlayCount = _sessionBox.values
        .where((s) =>
            s.babyId == babyId &&
            s.createdAt.year == today.year &&
            s.createdAt.month == today.month &&
            s.createdAt.day == today.day)
        .length;
  }

  /// 开始新游戏
  Future<void> _startNewGame() async {
    if (_gameConfig == null) {
      Get.snackbar('提示', '请先配置游戏设置', snackPosition: SnackPosition.BOTTOM);
      return;
    }

    // 检查每日限制
    if (_todayPlayCount >= _gameConfig!.dailyLimit) {
      Get.snackbar('提示', '今天已经玩了${_gameConfig!.dailyLimit}次啦，明天再来吧！',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    // 检查是否配置了必要的模型
    if (_gameConfig!.visionConfigId.isEmpty) {
      Get.snackbar('提示', '请先配置图像分析模型', snackPosition: SnackPosition.BOTTOM);
      Get.to(() => const StoryGameSettingsPage());
      return;
    }

    setState(() {
      _isGeneratingImage = true;
      _gameStarted = true;
      _gameEnded = false;
      _messages = [];
      _currentRound = 0;
      _finalScore = 0;
    });

    try {
      // 生成或获取图片
      await _generateImage();

      // 创建会话
      final baby = _userController.currentBaby.value;
      if (baby == null) return;

      _currentSession = StorySession(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        babyId: baby.id,
        createdAt: DateTime.now(),
        imageUrl: _currentImageUrl,
      );

      // 立即保存会话（未完成状态）
      await _sessionBox.put(_currentSession!.id, _currentSession!);
      debugPrint('会话已创建: ${_currentSession!.id}');

      // 让 AI 分析图片并引导开始
      await _analyzeImageAndStart();
    } catch (e) {
      debugPrint('开始游戏失败: $e');
      Get.snackbar('错误', '开始游戏失败: $e', snackPosition: SnackPosition.BOTTOM);
      setState(() {
        _isGeneratingImage = false;
        _gameStarted = false;
      });
    }
  }

  /// 生成图片
  Future<void> _generateImage() async {
    List<String> imagePool = [];

    // 1. 尝试从远程API获取图片列表
    if (_gameConfig!.remoteImageApiUrl.isNotEmpty) {
      try {
        final response = await http
            .get(Uri.parse(_gameConfig!.remoteImageApiUrl))
            .timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          // 支持多种返回格式
          if (data is List) {
            imagePool = data.map((e) => e.toString()).toList();
          } else if (data is Map && data['images'] != null) {
            imagePool =
                (data['images'] as List).map((e) => e.toString()).toList();
          } else if (data is Map && data['data'] != null) {
            imagePool =
                (data['data'] as List).map((e) => e.toString()).toList();
          }
        }
      } catch (e) {
        debugPrint('从远程API获取图片失败: $e');
      }
    }

    // 2. 如果远程API没有返回图片，使用配置的备用图片列表
    if (imagePool.isEmpty && _gameConfig!.fallbackImageUrls.isNotEmpty) {
      imagePool = List.from(_gameConfig!.fallbackImageUrls);
    }

    // 3. 如果仍然没有图片，使用内置图片 (网络 + 本地)
    if (imagePool.isEmpty) {
      imagePool = [
        ...defaultStoryImages,
        ...localStoryImages,
      ];
    }

    // 随机选择一张图片
    imagePool.shuffle();
    _currentImageUrl = imagePool.first;

    setState(() => _isGeneratingImage = false);
  }

  /// 分析图片并开始引导
  Future<void> _analyzeImageAndStart() async {
    setState(() => _isAIResponding = true);

    try {
      // 获取配置的模型
      final visionConfig = _openAIService.configs
          .firstWhereOrNull((c) => c.id == _gameConfig!.visionConfigId);

      if (visionConfig == null) {
        throw Exception('未找到图像分析配置');
      }

      // 调用 Vision API 分析图片
      final response = await _callVisionAPI(
        visionConfig,
        _gameConfig!.visionModel,
        _gameConfig!.visionAnalysisPrompt,
        _currentImageUrl,
      );

      // 添加 AI 回复
      _messages.add({
        'role': 'ai',
        'content': response,
        'timestamp': DateTime.now().toIso8601String(),
      });

      // 保存会话（初始引导）
      if (_currentSession != null) {
        _currentSession!.messages = List<Map<String, dynamic>>.from(_messages);
        await _currentSession!.save();
      }

      setState(() => _isAIResponding = false);

      // 语音播放
      await _ttsService.speak(response,
          rate: _gameConfig?.ttsRate,
          volume: _gameConfig?.ttsVolume,
          pitch: _gameConfig?.ttsPitch);
    } catch (e) {
      debugPrint('图片分析失败: $e');
      setState(() => _isAIResponding = false);

      // 使用默认引导语
      final defaultResponse = '哇，这是一张很有趣的图片呢！小朋友，你看到了什么？能给我讲讲这个故事吗？';
      _messages.add({
        'role': 'ai',
        'content': defaultResponse,
        'timestamp': DateTime.now().toIso8601String(),
      });
      await _ttsService.speak(defaultResponse,
          rate: _gameConfig?.ttsRate,
          volume: _gameConfig?.ttsVolume,
          pitch: _gameConfig?.ttsPitch);
    }
  }

  /// 调用 Vision API
  Future<String> _callVisionAPI(
      OpenAIConfig config, String model, String prompt, String imageUrl) async {
    // 使用 OpenAI 格式调用 Vision API
    final uri = Uri.parse('${config.baseUrl}/v1/chat/completions');
    final response = await http
        .post(
          uri,
          headers: {
            'Authorization': 'Bearer ${config.apiKey}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': model,
            'messages': [
              {
                'role': 'user',
                'content': [
                  {'type': 'text', 'text': prompt},
                  {
                    'type': 'image_url',
                    'image_url': {'url': imageUrl}
                  },
                ],
              }
            ],
            'max_tokens': 500,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return data['choices'][0]['message']['content'] as String;
    } else {
      throw Exception('Vision API 请求失败: ${response.statusCode}');
    }
  }

  /// 重试语音初始化
  Future<void> _retrySpeechInit() async {
    try {
      bool available = await _speech.initialize(
        onError: (e) => debugPrint('Retry error: $e'),
      );
      if (available) {
        setState(() {
          _speechAvailable = true;
          _useKeyboard = false;
        });
        Get.snackbar('成功', '语音服务已恢复', snackPosition: SnackPosition.BOTTOM);
      } else {
        Get.snackbar('提示', '语音识别仍然不可用，请检查设置',
            snackPosition: SnackPosition.BOTTOM);
      }
    } catch (e) {
      debugPrint('重试语音初始化失败: $e');
    }
  }

  /// 开始录音
  void _startListening() async {
    if (!_speechAvailable) {
      Get.snackbar(
        '语音识别不可用',
        '请在系统设置中允许应用使用麦克风权限',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 4),
      );
      return;
    }

    setState(() {
      _isListening = true;
      _recognizedText = '';
      _recordingSecondsLeft = _maxRecordingSeconds;
      _recordingStartTime = DateTime.now();
    });

    // 启动倒计时
    _startRecordingTimer();

    await _speech.listen(
      onResult: (result) {
        setState(() {
          _recognizedText = result.recognizedWords;
        });
      },
      localeId: 'zh_CN',
      listenMode: stt.ListenMode.dictation,
      listenFor: const Duration(seconds: _maxRecordingSeconds), // 最长录音时间
    );
  }

  /// 录音倒计时
  void _startRecordingTimer() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!_isListening) return false;

      final elapsed = DateTime.now().difference(_recordingStartTime!).inSeconds;
      final remaining = _maxRecordingSeconds - elapsed;

      if (remaining <= 0) {
        _stopListening();
        return false;
      }

      setState(() => _recordingSecondsLeft = remaining);
      return true;
    });
  }

  /// 停止录音
  void _stopListening() async {
    await _speech.stop();
    setState(() {
      _isListening = false;
      _recordingSecondsLeft = _maxRecordingSeconds;
    });

    if (_recognizedText.isNotEmpty) {
      await _sendChildMessage(_recognizedText);
    }
  }

  /// 发送孩子的消息
  Future<void> _sendChildMessage(String message) async {
    if (message.trim().isEmpty) return;

    // 添加孩子的消息
    _messages.add({
      'role': 'child',
      'content': message,
      'timestamp': DateTime.now().toIso8601String(),
    });
    _currentRound++;

    setState(() {
      _isAIResponding = true;
      _recognizedText = '';
    });

    // 更新并保存会话
    if (_currentSession != null) {
      _currentSession!.messages = List<Map<String, dynamic>>.from(_messages);
      await _currentSession!.save();
      debugPrint('会话已更新(Child): 第$_currentRound轮');
    }

    // 检查是否达到最大轮数
    if (_currentRound >= _gameConfig!.maxRounds) {
      await _endGameWithEvaluation();
    } else {
      await _getAIResponse();
    }
  }

  /// 获取 AI 对话回复
  Future<void> _getAIResponse() async {
    try {
      // 获取对话配置
      OpenAIConfig? chatConfig;
      String chatModel = '';

      if (_gameConfig!.chatConfigId.isNotEmpty) {
        chatConfig = _openAIService.configs
            .firstWhereOrNull((c) => c.id == _gameConfig!.chatConfigId);
        chatModel = _gameConfig!.chatModel;
      }

      // 如果没有配置，使用默认配置
      chatConfig ??= _openAIService.currentConfig.value;
      if (chatModel.isEmpty) {
        chatModel = chatConfig?.selectedModel ?? '';
      }

      if (chatConfig == null) {
        throw Exception('未配置对话模型');
      }

      // 构建对话历史
      final messagesForAPI = [
        {'role': 'system', 'content': _gameConfig!.chatSystemPrompt},
        ..._messages.map((m) => {
              'role': m['role'] == 'ai' ? 'assistant' : 'user',
              'content': m['content'],
            }),
      ];

      // 调用 API
      final uri = Uri.parse('${chatConfig.baseUrl}/v1/chat/completions');
      final response = await http
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer ${chatConfig.apiKey}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': chatModel,
              'messages': messagesForAPI,
              'max_tokens': 200,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final aiResponse = data['choices'][0]['message']['content'] as String;

        _messages.add({
          'role': 'ai',
          'content': aiResponse,
          'timestamp': DateTime.now().toIso8601String(),
        });

        // 保存会话
        if (_currentSession != null) {
          _currentSession!.messages =
              List<Map<String, dynamic>>.from(_messages);
          await _currentSession!.save();
        }

        setState(() => _isAIResponding = false);
        await _ttsService.speak(aiResponse,
            rate: _gameConfig?.ttsRate,
            volume: _gameConfig?.ttsVolume,
            pitch: _gameConfig?.ttsPitch);
      } else {
        throw Exception('对话请求失败');
      }
    } catch (e) {
      debugPrint('获取 AI 回复失败: $e');
      setState(() => _isAIResponding = false);

      final fallbackResponse = '嗯嗯，真有趣！然后呢？';
      _messages.add({
        'role': 'ai',
        'content': fallbackResponse,
        'timestamp': DateTime.now().toIso8601String(),
      });

      // 保存会话
      if (_currentSession != null) {
        _currentSession!.messages = List<Map<String, dynamic>>.from(_messages);
        await _currentSession!.save();
      }

      await _ttsService.speak(fallbackResponse,
          rate: _gameConfig?.ttsRate,
          volume: _gameConfig?.ttsVolume,
          pitch: _gameConfig?.ttsPitch);
    }
  }

  /// 结束游戏并进行评价
  Future<void> _endGameWithEvaluation() async {
    if (_isAIResponding) return;
    setState(() => _isAIResponding = true);

    try {
      // 获取评价配置（使用对话配置）
      OpenAIConfig? chatConfig;
      String chatModel = '';

      if (_gameConfig!.chatConfigId.isNotEmpty) {
        chatConfig = _openAIService.configs
            .firstWhereOrNull((c) => c.id == _gameConfig!.chatConfigId);
        chatModel = _gameConfig!.chatModel;
      }

      chatConfig ??= _openAIService.currentConfig.value;
      if (chatModel.isEmpty) {
        chatModel = chatConfig?.selectedModel ?? '';
      }

      if (chatConfig == null) {
        throw Exception('未配置对话模型');
      }

      // 构建评价请求
      final storyContent = _messages
          .map((m) => '${m['role'] == 'ai' ? 'AI' : '小朋友'}: ${m['content']}')
          .join('\n');

      final messagesForAPI = [
        {'role': 'system', 'content': _gameConfig!.evaluationPrompt},
        {'role': 'user', 'content': '以下是故事对话记录：\n\n$storyContent'},
      ];

      final uri = Uri.parse('${chatConfig.baseUrl}/v1/chat/completions');
      final response = await http
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer ${chatConfig.apiKey}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': chatModel,
              'messages': messagesForAPI,
              'max_tokens': 300,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final evaluation = data['choices'][0]['message']['content'] as String;

        // 解析分数
        final scoreMatch =
            RegExp(r'【得分[：:]?\s*(\d+)分?】').firstMatch(evaluation);
        if (scoreMatch != null) {
          _finalScore = int.tryParse(scoreMatch.group(1) ?? '80') ?? 80;
        } else {
          _finalScore = 80;
        }

        _messages.add({
          'role': 'ai',
          'content': evaluation,
          'timestamp': DateTime.now().toIso8601String(),
        });

        // 保存会话
        _currentSession?.messages = List<Map<String, dynamic>>.from(_messages);
        _currentSession?.score = _finalScore;
        _currentSession?.isCompleted = true;
        _currentSession?.storySummary = evaluation;

        if (_currentSession != null) {
          await _currentSession!.save();
        }

        setState(() {
          _isAIResponding = false;
          _gameEnded = true;
        });

        // 语音播放评价
        await _ttsService.speak(evaluation,
            rate: _gameConfig?.ttsRate,
            volume: _gameConfig?.ttsVolume,
            pitch: _gameConfig?.ttsPitch);

        // 奖励星星
        _awardStars();
      } else {
        throw Exception('评价请求失败');
      }
    } catch (e) {
      debugPrint('评价失败: $e');
      setState(() {
        _isAIResponding = false;
        _gameEnded = true;
        _finalScore = 75;
      });

      final fallbackEval = '小朋友讲得真棒！故事很有趣，继续加油哦！【得分：75分】';
      _messages.add({
        'role': 'ai',
        'content': fallbackEval,
        'timestamp': DateTime.now().toIso8601String(),
      });

      await _ttsService.speak(fallbackEval,
          rate: _gameConfig?.ttsRate,
          volume: _gameConfig?.ttsVolume,
          pitch: _gameConfig?.ttsPitch);
      _awardStars();
    }
  }

  /// 奖励星星
  void _awardStars() {
    // 检查是否启用星星奖励
    if (_gameConfig?.enableStarReward != true) {
      Get.snackbar(
        '🎉 完成故事',
        '太棒了！故事讲得真精彩！',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 3),
      );
      _calculateTodayPlayCount();
      return;
    }

    final stars = _gameConfig?.baseStars ?? 3;
    _userController.updateStars(stars, '完成看图讲故事');

    Get.snackbar(
      '🎉 获得奖励',
      '恭喜获得 $stars 颗星星！',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 3),
    );

    _calculateTodayPlayCount();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('看图讲故事'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: '历史记录',
            onPressed: _showHistory,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: () {
              Get.to(() => const StoryGameSettingsPage())?.then((_) {
                _loadConfig();
                setState(() {});
              });
            },
          ),
        ],
      ),
      body: _gameStarted ? _buildGameUI() : _buildStartUI(),
    );
  }

  /// 开始界面
  Widget _buildStartUI() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 游戏图标
            Icon(
              Icons.auto_stories,
              size: 80.sp,
              color: AppTheme.primary,
            ),
            SizedBox(height: 24.h),
            Text(
              '看图讲故事',
              style: TextStyle(
                fontSize: 28.sp,
                fontWeight: FontWeight.bold,
                color: AppTheme.textMain,
              ),
            ),
            SizedBox(height: 12.h),
            Text(
              '一起来看图片，发挥想象力讲故事吧！',
              style: TextStyle(
                fontSize: 16.sp,
                color: AppTheme.textSub,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 32.h),

            // 今日次数
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(20.r),
              ),
              child: Text(
                '今日已玩 $_todayPlayCount / ${_gameConfig?.dailyLimit ?? 2} 次',
                style: TextStyle(
                  fontSize: 14.sp,
                  color: Colors.orange.shade700,
                ),
              ),
            ),
            SizedBox(height: 32.h),

            // 开始按钮
            ElevatedButton.icon(
              onPressed: _todayPlayCount < (_gameConfig?.dailyLimit ?? 2)
                  ? _startNewGame
                  : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('开始游戏'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 16.h),
                textStyle: TextStyle(fontSize: 18.sp),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30.r),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 游戏界面
  Widget _buildGameUI() {
    return Column(
      children: [
        // 图片区域
        if (_currentImageUrl.isNotEmpty)
          Container(
            height: 200.h,
            width: double.infinity,
            margin: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16.r),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: InkWell(
              onTap: () => _showFullImage(_currentImageUrl),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16.r),
                child: _isGeneratingImage
                    ? const Center(child: CircularProgressIndicator())
                    : Hero(
                        tag: 'story_image',
                        child: buildStoryImage(
                          _currentImageUrl,
                          fit: BoxFit.cover,
                          errorWidget: Container(
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.image, size: 48),
                          ),
                        ),
                      ),
              ),
            ),
          ),

        // 对话区域
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final message = _messages[index];
              final isAI = message['role'] == 'ai';

              return _buildMessageBubble(
                message['content'] as String,
                isAI: isAI,
              );
            },
          ),
        ),

        // AI 正在回复
        if (_isAIResponding)
          Padding(
            padding: EdgeInsets.all(16.w),
            child: Row(
              children: [
                SizedBox(
                  width: 20.w,
                  height: 20.w,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12.w),
                Text('AI 正在思考...', style: TextStyle(fontSize: 14.sp)),
              ],
            ),
          ),

        // 录音识别文字显示
        if (_recognizedText.isNotEmpty)
          Container(
            margin: EdgeInsets.symmetric(horizontal: 16.w),
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Text(
              _recognizedText,
              style: TextStyle(fontSize: 14.sp),
            ),
          ),

        // 底部操作区
        _buildBottomBar(),
      ],
    );
  }

  /// 消息气泡
  Widget _buildMessageBubble(String content, {required bool isAI}) {
    return Align(
      alignment: isAI ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(maxWidth: 280.w),
        margin: EdgeInsets.only(bottom: 12.h),
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
          color: isAI ? Colors.white : AppTheme.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16.r),
          boxShadow: isAI
              ? [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isAI ? Icons.smart_toy : Icons.child_care,
                      size: 16.sp,
                      color: isAI ? Colors.blue : AppTheme.primary,
                    ),
                    SizedBox(width: 4.w),
                    Text(
                      isAI ? 'AI 老师' : '宝宝',
                      style: TextStyle(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.bold,
                        color: isAI ? Colors.blue : AppTheme.primary,
                      ),
                    ),
                  ],
                ),
                if (isAI)
                  GestureDetector(
                    onTap: () => _ttsService.speak(
                      content,
                      rate: _gameConfig?.ttsRate,
                      volume: _gameConfig?.ttsVolume,
                      pitch: _gameConfig?.ttsPitch,
                    ),
                    child: Icon(
                      Icons.volume_up,
                      size: 18.sp,
                      color: Colors.blue.withOpacity(0.6),
                    ),
                  ),
              ],
            ),
            SizedBox(height: 8.h),
            Text(
              content,
              style: TextStyle(fontSize: 14.sp),
            ),
          ],
        ),
      ),
    );
  }

  /// 显示全屏图片缩放
  void _showFullImage(String imageUrl) {
    Get.dialog(
      GestureDetector(
        onTap: () => Get.back(),
        child: Container(
          color: Colors.black,
          child: Stack(
            children: [
              Center(
                child: Hero(
                  tag: 'story_image',
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: buildStoryImage(
                      imageUrl,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 40.h,
                right: 20.w,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Get.back(),
                ),
              ),
            ],
          ),
        ),
      ),
      useSafeArea: false,
    );
  }

  /// 底部操作栏
  /// 发送文本输入
  void _submitText() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    _textController.clear();
    FocusScope.of(context).unfocus(); // 收起键盘
    _sendChildMessage(text);
  }

  /// 底部操作栏
  Widget _buildBottomBar() {
    if (_gameEnded) {
      return Container(
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          children: [
            // 分数展示
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.star, color: Colors.amber, size: 32.sp),
                SizedBox(width: 8.w),
                Text(
                  '得分：$_finalScore 分',
                  style: TextStyle(
                    fontSize: 24.sp,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16.h),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      if (_currentRound > 0) {
                        Navigator.pop(context);
                      } else {
                        setState(() {
                          _gameStarted = false;
                          _gameEnded = false;
                        });
                      }
                    },
                    child: const Text('返回'),
                  ),
                ),
                SizedBox(width: 16.w),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _startNewGame,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                    ),
                    child: const Text('再玩一次'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: _useKeyboard
            ? Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.mic, color: Colors.blue),
                    tooltip: '切换语音输入',
                    onPressed: () {
                      if (_speechAvailable) {
                        setState(() => _useKeyboard = false);
                      } else {
                        // 尝试重试
                        _retrySpeechInit();
                      }
                    },
                  ),
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: InputDecoration(
                        hintText: '输入你想说的...',
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 16.w, vertical: 10.h),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24.r),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24.r),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24.r),
                          borderSide: BorderSide(color: AppTheme.primary),
                        ),
                      ),
                      onSubmitted: (_) => _submitText(),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  IconButton(
                    icon: const Icon(Icons.send, color: AppTheme.primary),
                    onPressed: _submitText,
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // 轮次
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 12.w, vertical: 6.h),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(16.r),
                        ),
                        child: Text(
                          '第 $_currentRound / ${_gameConfig?.maxRounds ?? 5} 轮',
                          style: TextStyle(fontSize: 12.sp),
                        ),
                      ),

                      // 键盘切换按钮
                      TextButton.icon(
                        onPressed: () => setState(() => _useKeyboard = true),
                        icon: const Icon(Icons.keyboard, size: 18),
                        label: const Text('键盘输入'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey.shade700,
                        ),
                      ),

                      TextButton(
                        onPressed: (_currentRound > 0 && !_isAIResponding)
                            ? _endGameWithEvaluation
                            : null,
                        child: Text(
                          '结束故事',
                          style: TextStyle(
                            color: (_currentRound > 0 && !_isAIResponding)
                                ? Colors.grey.shade700
                                : Colors.grey.shade300,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16.h),
                  // 录音按钮
                  GestureDetector(
                    onLongPressStart:
                        _isAIResponding ? null : (_) => _startListening(),
                    onLongPressEnd:
                        _isAIResponding ? null : (_) => _stopListening(),
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(vertical: 16.h),
                      decoration: BoxDecoration(
                        color: _isAIResponding
                            ? Colors.grey.shade300
                            : (_isListening
                                ? Colors.red.shade400
                                : AppTheme.primary),
                        borderRadius: BorderRadius.circular(30.r),
                        boxShadow: [
                          if (!_isAIResponding)
                            BoxShadow(
                              color:
                                  (_isListening ? Colors.red : AppTheme.primary)
                                      .withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                        ],
                      ),
                      child: Center(
                        child: _isAIResponding
                            ? Text(
                                'AI 正在回复中...',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 16.sp),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                      _isListening ? Icons.mic : Icons.mic_none,
                                      color: Colors.white),
                                  SizedBox(width: 8.w),
                                  Text(
                                    _isListening
                                        ? '松开 结束 ($_recordingSecondsLeft)'
                                        : '按住 说话',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16.sp,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                  SizedBox(height: 8.h),
                  // 提示文字
                  Text(
                    _isListening ? '松开手指发送' : '长按开始讲故事',
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  /// 显示历史记录
  void _showHistory() {
    final babyId = _userController.currentBaby.value?.id;
    if (babyId == null) return;

    // 获取所有会话并按时间倒序
    final allSessions = _sessionBox.values
        .where((s) => s.babyId == babyId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // 分为已完成和未完成
    final incompleteSessions =
        allSessions.where((s) => !s.isCompleted).toList();
    final completedSessions = allSessions.where((s) => s.isCompleted).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: EdgeInsets.all(16.w),
              child: Text(
                '故事记录',
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: allSessions.isEmpty
                  ? const Center(child: Text('暂无记录'))
                  : ListView(
                      controller: scrollController,
                      children: [
                        // 未完成的会话
                        if (incompleteSessions.isNotEmpty) ...[
                          _buildHistorySectionTitle('未完成的故事', Colors.orange),
                          ...incompleteSessions
                              .map((s) => _buildHistoryItem(s, isResume: true)),
                        ],

                        // 已完成的会话
                        if (completedSessions.isNotEmpty) ...[
                          _buildHistorySectionTitle('已完成的故事', Colors.green),
                          ...completedSessions.map(
                              (s) => _buildHistoryItem(s, isResume: false)),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistorySectionTitle(String title, Color color) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14.sp,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildHistoryItem(StorySession session, {required bool isResume}) {
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8.r),
        child: Stack(
          children: [
            buildStoryImage(
              session.imageUrl,
              width: 50.w,
              height: 50.w,
              fit: BoxFit.cover,
              errorWidget: Container(
                width: 50.w,
                height: 50.w,
                color: Colors.grey.shade200,
                child: const Icon(Icons.image, color: Colors.grey),
              ),
            ),
            if (isResume)
              Positioned.fill(
                child: Container(
                  color: Colors.black26,
                  child:
                      Icon(Icons.play_arrow, color: Colors.white, size: 24.sp),
                ),
              ),
          ],
        ),
      ),
      title: Text(
        DateFormat('MM月dd日 HH:mm').format(session.createdAt),
        style: TextStyle(fontSize: 14.sp),
      ),
      subtitle: Text(
        isResume
            ? '进行到第 ${session.messages.where((m) => m['role'] == 'child').length} 轮'
            : '得分：${session.score} 分',
        style: TextStyle(fontSize: 12.sp),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.grey),
            onPressed: () => _deleteSession(session),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () {
        if (isResume) {
          Navigator.pop(context);
          _continueSession(session);
        } else {
          // 不关闭弹窗，直接跳转详情，返回时还在列表
          _showSessionDetail(session);
        }
      },
    );
  }

  /// 删除会话
  void _deleteSession(StorySession session) {
    Get.dialog(
      AlertDialog(
        title: const Text('删除记录'),
        content: const Text('确定要删除这条故事记录吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await session.delete(); // HiveObject 的 delete 方法
              Get.back(); // 关闭对话框
              // 刷新列表（_showHistory 会重新构建）
              Navigator.pop(context); // 关闭历史列表
              _showHistory(); // 重新打开历史列表以刷新
              Get.snackbar('提示', '记录已删除', snackPosition: SnackPosition.BOTTOM);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  /// 继续会话
  void _continueSession(StorySession session) {
    setState(() {
      _currentSession = session;
      _messages = List<Map<String, dynamic>>.from(session.messages);
      _currentRound = _messages.where((m) => m['role'] == 'child').length;
      _currentImageUrl = session.imageUrl;
      _gameStarted = true;
      _gameEnded = false;
      _isAIResponding = false;
    });

    debugPrint('继续会话: ${session.id}, 轮次: $_currentRound');

    // 如果最后一条消息是孩子发的，或者会话刚开始，可能需要触发 AI 回复
    if (_messages.isNotEmpty && _messages.last['role'] == 'child') {
      _getAIResponse();
    }
  }

  /// 显示会话详情
  void _showSessionDetail(StorySession session) {
    Get.to(() => _SessionDetailPage(session: session));
  }
}

/// 故事详情页面
class _SessionDetailPage extends StatelessWidget {
  final StorySession session;
  final TtsService _ttsService = Get.find<TtsService>();

  _SessionDetailPage({required this.session});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('故事详情'),
        actions: [
          IconButton(
            icon: const Icon(Icons.volume_up),
            tooltip: '朗读完整故事',
            onPressed: () => _speakFullStory(),
          ),
        ],
      ),
      body: Column(
        children: [
          // 顶部图片
          SizedBox(
            height: 200.h,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                buildStoryImage(
                  session.imageUrl,
                  fit: BoxFit.cover,
                  errorWidget: Container(
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.image, size: 50),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withOpacity(0.7),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          DateFormat('yyyy-MM-dd HH:mm')
                              .format(session.createdAt),
                          style:
                              TextStyle(color: Colors.white, fontSize: 12.sp),
                        ),
                        if (session.isCompleted)
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 8.w, vertical: 2.h),
                            decoration: BoxDecoration(
                              color: Colors.amber,
                              borderRadius: BorderRadius.circular(4.r),
                            ),
                            child: Text(
                              '${session.score}分',
                              style: TextStyle(
                                  fontSize: 12.sp, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 故事内容列表
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.all(16.w),
              itemCount:
                  session.messages.length + (session.isCompleted ? 1 : 0),
              itemBuilder: (context, index) {
                // 最后显示总结
                if (index == session.messages.length) {
                  return _buildSummaryCard();
                }

                final message = session.messages[index];
                final isAI = message['role'] == 'ai';
                return Padding(
                  padding: EdgeInsets.only(bottom: 16.h),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment:
                        isAI ? MainAxisAlignment.start : MainAxisAlignment.end,
                    children: [
                      if (isAI) ...[
                        CircleAvatar(
                          backgroundColor: Colors.blue.shade100,
                          radius: 16.r,
                          child: Icon(Icons.smart_toy,
                              size: 20.sp, color: Colors.blue),
                        ),
                        SizedBox(width: 8.w),
                      ],
                      Flexible(
                        child: Container(
                          padding: EdgeInsets.all(12.w),
                          decoration: BoxDecoration(
                            color: isAI ? Colors.white : AppTheme.primary,
                            borderRadius: BorderRadius.circular(16.r).copyWith(
                              topLeft: isAI ? Radius.zero : null,
                              topRight: !isAI ? Radius.zero : null,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.1),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            message['content'] as String,
                            style: TextStyle(
                              color: isAI ? Colors.black87 : Colors.white,
                              fontSize: 14.sp,
                            ),
                          ),
                        ),
                      ),
                      if (!isAI) ...[
                        SizedBox(width: 8.w),
                        CircleAvatar(
                          backgroundColor: AppTheme.primary.withOpacity(0.2),
                          radius: 16.r,
                          child: Icon(Icons.face,
                              size: 20.sp, color: AppTheme.primary),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    if (session.storySummary.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: EdgeInsets.only(top: 16.h),
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.stars, color: Colors.amber, size: 24.sp),
              SizedBox(width: 8.w),
              Text(
                '故事点评',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16.sp,
                  color: Colors.amber.shade900,
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Text(
            session.storySummary,
            style: TextStyle(
              fontSize: 14.sp,
              color: Colors.brown.shade800,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  void _speakFullStory() {
    final storyContent = session.messages
        .map((m) => '${m['role'] == 'ai' ? '' : ''}${m['content']}')
        .join('\n');

    // 如果有总结，也读出来
    final fullText = session.storySummary.isNotEmpty
        ? '$storyContent\n\nAI老师点评：${session.storySummary}'
        : storyContent;

    _ttsService.speak(fullText);
  }
}

/// 构建图片组件（支持网络和本地）
Widget buildStoryImage(String url,
    {double? width, double? height, BoxFit? fit, Widget? errorWidget}) {
  if (url.startsWith('http')) {
    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) =>
          errorWidget ?? const Icon(Icons.broken_image),
    );
  } else {
    // 简单的本地图片检查，如果文件已存在
    return Image.asset(
      url,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) =>
          errorWidget ?? const Icon(Icons.broken_image),
    );
  }
}
