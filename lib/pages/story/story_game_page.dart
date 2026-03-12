import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
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
import '../../widgets/toast_utils.dart';

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
  String? _aiError; // AI 错误信息
  int get _maxRounds => _gameConfig?.maxRounds ?? 5;
  bool _isImageCollapsed = false; // 图片折叠状态
  int _requestGenerationId = 0; // 请求生成ID,用于取消过期的请求回调
  int _imageAnalysisRetryCount = 0; // 图片分析重试次数
  static const int _maxImageAnalysisRetries = 2; // 最大重试次数

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
          debugPrint('开始初识化语音识别服务...');
          // 增加重试机制，特别是针对国产手机可能存在的服务唤醒延迟
          int retryCount = 0;
          while (retryCount < 3 && !_speechAvailable) {
            if (retryCount > 0) {
              debugPrint('语音初始化重试第 $retryCount 次...');
              await Future.delayed(const Duration(milliseconds: 1000));
            }
            _speechAvailable = await _speech.initialize(
              onError: (error) => debugPrint('Initial speech error: $error'),
              onStatus: (status) {
                debugPrint('Initial speech status: $status');
                if (status == 'available' && !_speechAvailable) {
                  setState(() => _speechAvailable = true);
                }
              },
              debugLogging: true,
            );
            if (_speechAvailable) break;
            retryCount++;
          }
        } else {
          debugPrint('麦克风权限未授予: $status');
          _speechAvailable = false;
        }

        if (!_speechAvailable) {
          debugPrint('语音识别初始化失败，可能缺少 Google 服务或麦克风权限');
          _useKeyboard = true; // 自动启用键盘

          ToastUtils.showError(
            '请检查是否安装了 Google App 或开启了麦克风权限',
            title: '语音不可用',
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
      ToastUtils.showError('初始化失败: $e');
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
      ToastUtils.showInfo('请先配置游戏设置');
      return;
    }

    // 检查每日限制
    if (_todayPlayCount >= _gameConfig!.dailyLimit) {
      ToastUtils.showInfo('今天已经玩了${_gameConfig!.dailyLimit}次啦，明天再来吧！');
      return;
    }

    // 检查是否配置了必要的模型
    if (_gameConfig!.visionConfigId.isEmpty) {
      ToastUtils.showWarning('请先配置图像分析模型');
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
      ToastUtils.showError('开始游戏失败: $e');
      setState(() {
        _isGeneratingImage = false;
        _gameStarted = false;
      });
    }
  }

  /// 生成图片
  Future<void> _generateImage() async {
    // 0. 尝试 AI 生成
    // 0. 尝试 AI 生成
    if (_gameConfig!.enableImageGeneration) {
      try {
        final imageConfigId = _gameConfig!.imageGenerationConfigId;
        final OpenAIConfig? imageConfig = _openAIService.configs
            .firstWhereOrNull((c) => c.id == imageConfigId);

        if (imageConfig != null) {
          debugPrint(
              '配置检查: enableImageGeneration=true, configId=$imageConfigId');

          // 1. 优化提示词
          String imagePrompt = _gameConfig!.imageGenerationPrompt;

          // 尝试获取 Chat 配置用于优化提示词
          OpenAIConfig? chatConfig;
          if (_gameConfig!.chatConfigId.isNotEmpty) {
            chatConfig = _openAIService.configs
                .firstWhereOrNull((c) => c.id == _gameConfig!.chatConfigId);
          }
          chatConfig ??= _openAIService.currentConfig.value; // Fallback

          if (chatConfig != null) {
            debugPrint('正在优化生图提示词...');
            try {
              imagePrompt = await _openAIService.chat(
                systemPrompt:
                    '你是一个专业的儿童插画提示词生成专家。请根据用户提供的内容生成适合 DALL-E 或 Stable Diffusion 的英文提示词。\n\n'
                    '严格要求:\n'
                    '1. 必须使用可爱、卡通、儿童插画风格\n'
                    '2. 色彩明亮温暖,画面简洁清晰\n'
                    '3. 严格禁止任何暴力、恐怖、成人或不适合儿童的内容\n'
                    '4. 使用圆润可爱的造型,避免尖锐或恐怖元素\n'
                    '5. 适合3-8岁儿童观看\n\n'
                    '只返回英文提示词本身,不要有其他说明。提示词中应包含: cute, cartoon, children illustration, colorful, warm, simple 等关键词。',
                userMessage: _gameConfig!.imageGenerationPrompt,
                config: chatConfig,
              );
              debugPrint('优化后的提示词: $imagePrompt');
            } catch (e) {
              debugPrint('提示词优化失败，使用原始提示词: $e');
            }
          }

          // 2. 调用生图 API
          debugPrint(
              '正在尝试 AI 生图 (Model: ${_gameConfig!.imageGenerationModel})...');
          final imageUrls = await _openAIService.generateImages(
            prompt: imagePrompt,
            n: 1,
            config: imageConfig,
            model: _gameConfig!.imageGenerationModel,
          );

          if (imageUrls.isNotEmpty) {
            final url = imageUrls.first;
            // 下载并转为 Base64 (如果是 URL)
            final base64Image = await _downloadAndConvertImage(url);
            _currentImageUrl = base64Image;
            setState(() => _isGeneratingImage = false);
            return;
          }
        } else {
          debugPrint('未找到生图配置 (ID: $imageConfigId)');
          ToastUtils.showWarning('未找到生图配置，请检查设置');
        }
      } catch (e) {
        debugPrint('AI 生图失败，降级使用备用图片源: $e');
        ToastUtils.showError('AI 生图失败: $e');
      }
    }

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

  /// 下载并转换图片为 Base64
  Future<String> _downloadAndConvertImage(String urlOrData) async {
    try {
      if (urlOrData.startsWith('data:image')) {
        return urlOrData;
      }

      // 如果是 http 链接，下载并转 base64
      if (urlOrData.startsWith('http')) {
        final response = await http
            .get(Uri.parse(urlOrData))
            .timeout(const Duration(seconds: 60));
        if (response.statusCode == 200) {
          final base64Data = base64Encode(response.bodyBytes);
          // 简单判断类型，默认 png
          return 'data:image/png;base64,$base64Data';
        } else {
          throw Exception('下载图片失败: ${response.statusCode}');
        }
      }
      return urlOrData;
    } catch (e) {
      debugPrint('图片转换失败: $e');
      rethrow;
    }
  }

  /// 分析图片并开始引导
  Future<void> _analyzeImageAndStart() async {
    setState(() {
      _isAIResponding = true;
      _aiError = null;
    });

    final currentGenId = ++_requestGenerationId;

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

      if (currentGenId != _requestGenerationId) return;

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
          featureKey: 'story_game',
          rate: _gameConfig?.ttsRate,
          volume: _gameConfig?.ttsVolume,
          pitch: _gameConfig?.ttsPitch);
    } catch (e) {
      if (currentGenId != _requestGenerationId) return;
      debugPrint('图片分析失败: $e');

      _imageAnalysisRetryCount++;

      // 如果重试次数超过限制,使用默认引导语
      if (_imageAnalysisRetryCount > _maxImageAnalysisRetries) {
        debugPrint('图片分析重试次数已达上限,使用默认引导语');
        setState(() => _isAIResponding = false);

        final defaultResponse = '哇,这是一张很有趣的图片呢!小朋友,你看到了什么?能给我讲讲这个故事吗?';
        _messages.add({
          'role': 'ai',
          'content': defaultResponse,
          'timestamp': DateTime.now().toIso8601String(),
        });

        // 保存会话
        if (_currentSession != null) {
          _currentSession!.messages =
              List<Map<String, dynamic>>.from(_messages);
          await _currentSession!.save();
        }

        await _ttsService.speak(defaultResponse,
            featureKey: 'story_game',
            rate: _gameConfig?.ttsRate,
            volume: _gameConfig?.ttsVolume,
            pitch: _gameConfig?.ttsPitch);

        ToastUtils.showInfo('已使用默认引导语开始游戏');
      } else {
        // 还可以重试,显示错误和重试按钮
        setState(() {
          _isAIResponding = false;
          _aiError =
              '图片分析失败($_imageAnalysisRetryCount/$_maxImageAnalysisRetries): ${_formatError(e)}';
        });
        ToastUtils.showWarning('图片分析失败,请点击重试按钮');
      }
    }
  }

  /// 格式化错误信息
  String _formatError(dynamic error) {
    final errorStr = error.toString();
    if (errorStr.contains('Exception:')) {
      return errorStr.split('Exception:').last.trim();
    }
    return errorStr;
  }

  /// 通用 API 请求方法，带重试逻辑
  Future<http.Response> _sendApiRequestWithRetry(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    int maxRetries = 2,
    Duration timeout = const Duration(seconds: 40),
  }) async {
    int retryCount = 0;
    while (retryCount <= maxRetries) {
      try {
        if (retryCount > 0) {
          debugPrint('正在进行第 $retryCount 次重试...');
          // 显示简短提示告知用户正在重试
          ToastUtils.showInfo('网络请求较慢，正在重试 ($retryCount/$maxRetries)...');
        }

        final response =
            await http.post(uri, headers: headers, body: body).timeout(timeout);

        return response;
      } catch (e) {
        retryCount++;
        if (retryCount > maxRetries) {
          rethrow;
        }
        // 指数退避等待
        await Future.delayed(Duration(seconds: retryCount * 2));
      }
    }
    throw Exception('请求失败，已达到最大重试次数');
  }

  /// 调用 Vision API
  Future<String> _callVisionAPI(
      OpenAIConfig config, String model, String prompt, String imageUrl) async {
    final uri = Uri.parse('${config.baseUrl}/v1/chat/completions');
    final response = await _sendApiRequestWithRetry(
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
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return data['choices'][0]['message']['content'] as String;
    } else {
      throw Exception(
          'Vision API 请求失败 (${response.statusCode}): ${response.body}');
    }
  }

  /// 重试语音初始化
  Future<void> _retrySpeechInit() async {
    try {
      // 再次显式请求权限
      var status = await Permission.microphone.status;
      if (!status.isGranted) {
        status = await Permission.microphone.request();
      }

      if (!status.isGranted) {
        ToastUtils.showError('请在设置中开启麦克风权限以使用语音功能', title: '权限不足');
        return;
      }

      Get.dialog(const Center(child: CircularProgressIndicator()),
          barrierDismissible: false);

      bool available = await _speech.initialize(
        onError: (e) => debugPrint('Retry error: $e'),
        onStatus: (s) => debugPrint('Retry status: $s'),
        debugLogging: true,
      );

      if (Get.isDialogOpen ?? false) Get.back(); // 关闭加载框

      if (available) {
        setState(() {
          _speechAvailable = true;
          _useKeyboard = false;
        });
        ToastUtils.showSuccess('语音服务已就绪');
      } else {
        ToastUtils.showError('语音转文字服务初始化失败。请确认手机已安装语音引擎，并允许系统麦克风访问权限。');
      }
    } catch (e) {
      if (Get.isDialogOpen ?? false) Get.back();
      debugPrint('重试语音初始化失败: $e');
    }
  }

  /// 开始录音
  void _startListening() async {
    if (!_speechAvailable) {
      ToastUtils.showError('请在系统设置中允许应用使用麦克风权限', title: '语音识别不可用');
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
      // 停止录音后，将文字填入输入框并切换到键盘模式，方便用户修改发送
      setState(() {
        _textController.text = _recognizedText;
        _useKeyboard = true;
      });
      ToastUtils.showSuccess('已转为文字，可编辑后发送', title: '识别成功');
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
      // _isAIResponding = true; // 移至 _getAIResponse 中设置,否则会被拦截
      _aiError = null;
      _recognizedText = '';
    });

    // 更新并保存会话
    if (_currentSession != null) {
      _currentSession!.messages = List<Map<String, dynamic>>.from(_messages);
      await _currentSession!.save();
      debugPrint('会话已更新(Child): 第$_currentRound轮');
    }

    // 检查是否达到最大轮数
    if (_currentRound >= (_gameConfig?.maxRounds ?? 5)) {
      debugPrint('达到最大轮数，强制结束游戏');
      // 不再调用 _getAIResponse，直接调用评价
      await _endGameWithEvaluation();
    } else {
      await _getAIResponse();
    }
  }

  /// 重新生成最后一条 AI 回复
  Future<void> _retryLastAIResponse() async {
    if (_messages.isEmpty || _isAIResponding) return;

    // 如果最后一条是 AI 消息，删除它
    if (_messages.last['role'] == 'ai') {
      _messages.removeLast();
    }

    setState(() {
      // _isAIResponding = true; // 移至 _getAIResponse 中设置
      _aiError = null;
    });

    if (_messages.isEmpty) {
      await _analyzeImageAndStart();
    } else {
      await _getAIResponse();
    }
  }

  /// 统一处理 AI 动作（引导、对话或总结）
  Future<void> _handleAIAction() async {
    if (_isAIResponding) return;

    if (_messages.isEmpty) {
      await _analyzeImageAndStart();
    } else if (_currentRound >= (_gameConfig?.maxRounds ?? 5)) {
      await _endGameWithEvaluation();
    } else {
      await _getAIResponse();
    }
  }

  /// 获取 AI 对话回复
  Future<void> _getAIResponse() async {
    if (_isAIResponding) return;
    setState(() {
      _isAIResponding = true;
      _aiError = null;
    });

    final currentGenId = ++_requestGenerationId;

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
      final response = await _sendApiRequestWithRetry(
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
      );

      if (currentGenId != _requestGenerationId) return;

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
            featureKey: 'story_game',
            rate: _gameConfig?.ttsRate,
            volume: _gameConfig?.ttsVolume,
            pitch: _gameConfig?.ttsPitch);
      } else {
        throw Exception('对话请求失败');
      }
    } catch (e) {
      if (currentGenId != _requestGenerationId) return;
      debugPrint('获取 AI 回复失败: $e');
      setState(() {
        _isAIResponding = false;
        _aiError =
            'AI 暂时没反应过来 (${e.toString().contains('Timeout') ? '超时' : '错误'})';
      });
      ToastUtils.showError('AI 请求失败，请重试');
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

      // 动态增强评价提示词，避免分数过于固定
      String systemPrompt = _gameConfig!.evaluationPrompt;
      // 如果提示词中没有包含特定的差异化指令，则追加（避免重复添加）
      if (!systemPrompt.contains('区分度')) {
        systemPrompt +=
            '\n\n重要：请根据小朋友回答的长度、逻辑性和互动轮数给出有区分度的分数（如83、87、94、96等），不要总是给出88或92分。如果故事很短或非常简单，分数应适当降低（如70-80）；如果故事很精彩，可以给高分（95+）。';
      }

      final messagesForAPI = [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': '以下是故事对话记录：\n\n$storyContent'},
      ];

      final uri = Uri.parse('${chatConfig.baseUrl}/v1/chat/completions');
      final response = await _sendApiRequestWithRetry(
        uri,
        headers: {
          'Authorization': 'Bearer ${chatConfig.apiKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': chatModel,
          'messages': messagesForAPI,
          'max_tokens': 300,
          'temperature': 0.85, // 增加随机性以避免分数固定
        }),
      );

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
            featureKey: 'story_game',
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
          featureKey: 'story_game',
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
      body: Stack(
        children: [
          _gameStarted ? _buildGameUI() : _buildStartUI(),
          if (_isListening) _buildListeningOverlay(),
        ],
      ),
    );
  }

  /// 录音时的全屏遮罩
  Widget _buildListeningOverlay() {
    return Positioned.fill(
      child: GestureDetector(
        onLongPressEnd: (_) => _stopListening(),
        child: Container(
          color: Colors.black.withOpacity(0.7),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 波动动画效果（简化版，使用图标缩放模拟）
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 1.0, end: 1.2),
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeInOutSine,
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: value,
                        child: Container(
                          padding: EdgeInsets.all(30.w),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Container(
                            padding: EdgeInsets.all(20.w),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.mic,
                              color: Colors.white,
                              size: 60.sp,
                            ),
                          ),
                        ),
                      );
                    },
                    onEnd: () {
                      // 简单的无限循环动画逻辑
                      setState(() {});
                    },
                  ),
                  SizedBox(height: 40.h),
                  Text(
                    '正在倾听...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 16.h),
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20.r),
                    ),
                    child: Text(
                      '倒计时 $_recordingSecondsLeft 秒',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16.sp,
                      ),
                    ),
                  ),
                  SizedBox(height: 60.h),
                  Text(
                    '松开发送',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16.sp,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
        // 图片区域 (支持折叠)
        if (_currentImageUrl.isNotEmpty || _isGeneratingImage)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            height: _isImageCollapsed ? 60.h : 220.h,
            width: double.infinity,
            margin: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16.r),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              children: [
                // 背景高斯模糊
                if (_currentImageUrl.isNotEmpty)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16.r),
                      child: ImageFiltered(
                        imageFilter:
                            ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                        child: Opacity(
                          opacity: 0.6,
                          child: buildStoryImage(
                            _currentImageUrl,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),
                // 图片主体
                InkWell(
                  onTap: _currentImageUrl.isNotEmpty
                      ? () => _showFullImage(_currentImageUrl)
                      : null,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16.r),
                    child: _isGeneratingImage
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(),
                                SizedBox(height: 16.h),
                                Text(
                                  'AI 正在生成图片...',
                                  style: TextStyle(
                                    color: AppTheme.primary,
                                    fontSize: 14.sp,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 8.h),
                                Text(
                                  '请耐心等待...',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12.sp,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Hero(
                            tag: 'story_image',
                            child: SizedBox(
                              width: double.infinity,
                              height: double.infinity,
                              child: buildStoryImage(
                                _currentImageUrl,
                                fit: BoxFit.contain, // 确保完整显示
                                errorWidget: Container(
                                  color: Colors.grey.shade200,
                                  child: const Icon(Icons.image, size: 48),
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
                // 折叠/展开 按钮
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _isImageCollapsed = !_isImageCollapsed;
                      });
                    },
                    child: Container(
                      padding: EdgeInsets.all(4.w),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isImageCollapsed
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_up,
                        color: Colors.white,
                        size: 20.sp,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

        // 对话区域
        Expanded(
          child: ListView.builder(
            reverse: true, // 聊天模式由下往上加载，解决键盘遮挡布局不跟随问题
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              // 反转索引：ListView反转后，视觉上的第0个其实是_messages最后一条
              final messageIndex = _messages.length - 1 - index;
              final message = _messages[messageIndex];
              final isAI = message['role'] == 'ai';
              final isLast = messageIndex == _messages.length - 1;

              return _buildMessageBubble(
                messageIndex,
                message['content'] as String,
                isAI: isAI,
                isLast: isLast,
              );
            },
          ),
        ),

        // AI 正在回复
        // AI 正在回复或显示错误/重试
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
                Expanded(
                    child:
                        Text('AI 正在思考...', style: TextStyle(fontSize: 14.sp))),
                // 取消按钮
                TextButton.icon(
                  onPressed: () {
                    // 取消当前等待
                    setState(() {
                      _isAIResponding = false;
                      _requestGenerationId++; // 增加 ID 以立即使之前的回调失效
                      // 如果消息为空(第一次分析被取消),显示重试提示
                      if (_messages.isEmpty) {
                        _aiError = '已取消图片分析,点击重试继续';
                      }
                    });
                  },
                  icon: const Icon(Icons.stop_circle_outlined,
                      color: Colors.grey, size: 20),
                  label: const Text('取消', style: TextStyle(color: Colors.grey)),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 8.w),
                  ),
                ),
              ],
            ),
          )
        else if (_aiError != null)
          Padding(
            padding: EdgeInsets.all(16.w),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red, size: 20.sp),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    _aiError!,
                    style: TextStyle(color: Colors.red, fontSize: 14.sp),
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _aiError = null;
                    });
                    // 如果消息为空,说明是第一次图片分析被取消,需要重新分析图片
                    if (_messages.isEmpty) {
                      _analyzeImageAndStart();
                    } else {
                      _handleAIAction();
                    }
                  },
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('重试'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                    backgroundColor: Colors.red.shade50,
                  ),
                ),
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
  Widget _buildMessageBubble(int index, String content,
      {required bool isAI, bool isLast = false}) {
    return Align(
      alignment: isAI ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(maxWidth: 290.w),
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
          mainAxisSize: MainAxisSize.min,
          children: [
            // 头部：角色标识
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isAI ? Icons.smart_toy : Icons.child_care,
                  size: 14.sp,
                  color: isAI ? Colors.blue : AppTheme.primary,
                ),
                SizedBox(width: 4.w),
                Text(
                  isAI ? 'AI 老师' : '宝宝',
                  style: TextStyle(
                    fontSize: 11.sp,
                    fontWeight: FontWeight.bold,
                    color: isAI ? Colors.blue : AppTheme.primary,
                  ),
                ),
              ],
            ),
            SizedBox(height: 6.h),
            // 内容
            Text(
              content,
              style: TextStyle(fontSize: 14.sp, color: AppTheme.textMain),
            ),
            SizedBox(height: 8.h),
            // 底部操作按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isAI) ...[
                  // 播放按钮
                  _buildBubbleAction(Icons.volume_up, () {
                    _ttsService.speak(
                      content,
                      rate: _gameConfig?.ttsRate,
                      volume: _gameConfig?.ttsVolume,
                      pitch: _gameConfig?.ttsPitch,
                    );
                  }),
                  _buildBubbleAction(Icons.copy, () {
                    Clipboard.setData(ClipboardData(text: content));
                    Get.snackbar('提示', '已复制到剪贴板',
                        snackPosition: SnackPosition.BOTTOM);
                  }),
                  if (!_isAIResponding)
                    _buildBubbleAction(
                        Icons.refresh, () => _handleRetryAIResponse(index)),
                ] else ...[
                  // 播放按钮
                  _buildBubbleAction(Icons.volume_up, () {
                    _ttsService.speak(
                      content,
                      rate: _gameConfig?.ttsRate,
                      volume: _gameConfig?.ttsVolume,
                      pitch: _gameConfig?.ttsPitch,
                    );
                  }),
                  _buildBubbleAction(Icons.copy, () {
                    Clipboard.setData(ClipboardData(text: content));
                    Get.snackbar('提示', '已复制到剪贴板',
                        snackPosition: SnackPosition.BOTTOM);
                  }),
                  _buildBubbleAction(
                      Icons.edit, () => _showEditDialog(content)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 气泡内的小动作按钮
  Widget _buildBubbleAction(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.r),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
        child: Icon(
          icon,
          size: 16.sp,
          color: Colors.grey.shade400,
        ),
      ),
    );
  }

  /// 显示编辑对话框
  void _showEditDialog(String oldContent) {
    final editController = TextEditingController(text: oldContent);
    Get.dialog(
      AlertDialog(
        title: const Text('编辑消息'),
        content: TextField(
          controller: editController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入新的内容...',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final newText = editController.text.trim();
              if (newText.isNotEmpty) {
                Get.back();
                _handleEditMessage(oldContent, newText);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 处理消息编辑
  void _handleEditMessage(String oldContent, String newContent) async {
    // 找到该消息的索引
    final index = _messages
        .indexWhere((m) => m['role'] == 'child' && m['content'] == oldContent);
    if (index == -1) return;

    setState(() {
      // 更新该消息内容
      _messages[index]['content'] = newContent;

      // 删除该消息之后的所有消息（通常是 AI 的回复及后续）
      if (index < _messages.length - 1) {
        _messages.removeRange(index + 1, _messages.length);
        // 如果删除了消息，需要相应调整轮数
        // 简单做法：重新计算轮数
        _currentRound = _messages.where((m) => m['role'] == 'child').length;
      }

      // _isAIResponding = true; // 移至 _getAIResponse 中设置
    });

    // 重新触发 AI 回复
    await _getAIResponse();
  }

  /// 处理重新请求 AI 回复
  void _handleRetryAIResponse(int index) {
    if (_isAIResponding) return;

    // 如果是最后一条，直接使用现有逻辑
    if (index == _messages.length - 1) {
      _retryLastAIResponse();
      return;
    }

    // 如果不是最后一条，需要询问是否截断后续对话
    Get.defaultDialog(
      title: '重新请求',
      middleText: '这将删除此条回复及之后的所有对话记录，并重新生成回答。\n确定要继续吗？',
      textConfirm: '确定',
      textCancel: '取消',
      confirmTextColor: Colors.white,
      onConfirm: () async {
        Get.back(); // 关闭对话框

        setState(() {
          // 删除从该索引开始的所有消息
          _messages.removeRange(index, _messages.length);
          // 重新计算轮数
          _currentRound = _messages.where((m) => m['role'] == 'child').length;
          // 这一步不需要手动设 _isAIResponding，因为 _getAIResponse 会设
        });

        if (_messages.isEmpty) {
          await _analyzeImageAndStart();
        } else {
          await _getAIResponse();
        }
      },
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_useKeyboard)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 轮次
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(16.r),
                    ),
                    child: Text(
                      '第 $_currentRound / ${_gameConfig?.maxRounds ?? 5} 轮',
                      style: TextStyle(fontSize: 12.sp),
                    ),
                  ),
                  // 结束按钮
                  TextButton(
                    onPressed: (_currentRound > 0 && !_isAIResponding)
                        ? _endGameWithEvaluation
                        : null,
                    child: Text(
                      '提前结束',
                      style: TextStyle(
                        color: (_currentRound > 0 && !_isAIResponding)
                            ? Colors.red.shade300
                            : Colors.grey.shade300,
                        fontSize: 12.sp,
                      ),
                    ),
                  ),
                ],
              ),
            if (!_useKeyboard) SizedBox(height: 12.h),
            Row(
              children: [
                // 切换按钮 (语音模式显示键盘图标，键盘模式显示麦克风图标)
                IconButton(
                  icon: Icon(_useKeyboard ? Icons.mic : Icons.keyboard,
                      color: _useKeyboard ? Colors.blue : Colors.grey.shade600),
                  onPressed: () {
                    setState(() => _useKeyboard = !_useKeyboard);
                    // 如果切换到语音且未初始化，尝试静默初始化
                    if (!_useKeyboard && !_speechAvailable) {
                      _retrySpeechInit();
                    }
                  },
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _useKeyboard
                        ? TextField(
                            key: const ValueKey('keyboard_input'),
                            controller: _textController,
                            decoration: InputDecoration(
                              hintText: '写下你想说的...',
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16.w, vertical: 10.h),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24.r),
                                borderSide:
                                    BorderSide(color: Colors.grey.shade300),
                              ),
                            ),
                            onSubmitted: (_) => _submitText(),
                          )
                        : GestureDetector(
                            key: const ValueKey('voice_input'),
                            onTap: () {
                              if (!_speechAvailable) {
                                _retrySpeechInit();
                              } else {
                                Get.snackbar('提示', '请长按按钮进行说话',
                                    snackPosition: SnackPosition.BOTTOM,
                                    duration: const Duration(seconds: 1));
                              }
                            },
                            onLongPressStart: (_) {
                              if (!_isAIResponding) {
                                if (!_speechAvailable) {
                                  _retrySpeechInit();
                                } else {
                                  _startListening();
                                }
                              }
                            },
                            onLongPressEnd: (_) {
                              if (!_isAIResponding && _isListening) {
                                _stopListening();
                              }
                            },
                            child: Container(
                              height: 48.h,
                              decoration: BoxDecoration(
                                color: _isAIResponding
                                    ? Colors.grey.shade200
                                    : (_isListening
                                        ? Colors.red.shade400
                                        : (_speechAvailable
                                            ? AppTheme.primary
                                            : Colors.grey.shade400)),
                                borderRadius: BorderRadius.circular(24.r),
                              ),
                              child: Center(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (!_speechAvailable && !_isAIResponding)
                                      Padding(
                                        padding: EdgeInsets.only(right: 8.w),
                                        child: Icon(Icons.warning_amber,
                                            color: Colors.white, size: 16.sp),
                                      ),
                                    Text(
                                      _isAIResponding
                                          ? 'AI回复中...'
                                          : (!_speechAvailable
                                              ? '语音不可用(点击重试)'
                                              : (_isListening
                                                  ? '正在倾听...'
                                                  : '按住说话')),
                                      style: TextStyle(
                                        color: _isAIResponding
                                            ? Colors.grey
                                            : Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
                if (_useKeyboard) ...[
                  SizedBox(width: 8.w),
                  IconButton(
                    icon: const Icon(Icons.send, color: AppTheme.primary),
                    onPressed: _submitText,
                  ),
                ],
              ],
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
      _aiError = null;
    });

    debugPrint('继续会话: ${session.id}, 轮次: $_currentRound');

    // 如果最后一条消息是孩子发的，或者轮次达到上限，触发相应动作
    if (_messages.isNotEmpty && _messages.last['role'] == 'child') {
      _handleAIAction();
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
                InkWell(
                  onTap: () => _showFullImage(session.imageUrl),
                  child: buildStoryImage(
                    session.imageUrl,
                    fit: BoxFit.cover,
                    errorWidget: Container(
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.image, size: 50),
                    ),
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
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: buildStoryImage(
                    imageUrl,
                    fit: BoxFit.contain,
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
}

/// 构建图片组件（支持网络、Base64和本地资源）
Widget buildStoryImage(String url,
    {double? width, double? height, BoxFit? fit, Widget? errorWidget}) {
  if (url.startsWith('data:image')) {
    try {
      final base64Data = url.split(',')[1];
      final bytes = base64Decode(base64Data);
      return Image.memory(
        bytes,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) =>
            errorWidget ?? const Icon(Icons.broken_image),
      );
    } catch (e) {
      return errorWidget ?? const Icon(Icons.broken_image);
    }
  } else if (url.startsWith('http')) {
    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) =>
          errorWidget ?? const Icon(Icons.broken_image),
    );
  } else {
    // 视为本地资源 (Asset)
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
