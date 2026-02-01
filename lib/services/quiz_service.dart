import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../models/quiz_config.dart';
import '../models/quiz_question.dart';
import '../models/openai_config.dart';
import '../data/quiz_data.dart';
import 'openai_service.dart';

/// 新年问答服务
class QuizService extends GetxService {
  late Box<QuizConfig> _configBox;
  late Box<QuizQuestion> _questionBox;

  final OpenAIService _openAIService = Get.find<OpenAIService>();

  // 当前配置
  final Rx<QuizConfig?> config = Rx<QuizConfig?>(null);

  // 题目列表
  final RxList<QuizQuestion> questions = <QuizQuestion>[].obs;

  // 图片生成队列
  final RxList<String> _generatingQueue = <String>[].obs;

  // 图片缓存目录
  late Directory _imageDir;

  // 游玩记录Box
  late Box<dynamic> _playRecordBox;

  // 今日已玩次数
  final RxInt todayPlayCount = 0.obs;

  Future<QuizService> init() async {
    // 注册适配器
    if (!Hive.isAdapterRegistered(20)) {
      Hive.registerAdapter(QuizConfigAdapter());
    }
    if (!Hive.isAdapterRegistered(21)) {
      Hive.registerAdapter(QuizQuestionAdapter());
    }

    _configBox = await Hive.openBox<QuizConfig>('quiz_config');
    _questionBox = await Hive.openBox<QuizQuestion>('quiz_questions');
    _playRecordBox = await Hive.openBox('quiz_play_record');

    // 初始化图片缓存目录
    final appDir = await getApplicationDocumentsDirectory();
    _imageDir = Directory('${appDir.path}/quiz_images');
    if (!await _imageDir.exists()) {
      await _imageDir.create(recursive: true);
    }

    // 加载配置
    _loadConfig();

    // 加载题目
    _loadQuestions();

    // 加载今日游玩次数
    _loadTodayPlayCount();

    return this;
  }

  /// 加载配置
  void _loadConfig() {
    if (_configBox.isNotEmpty) {
      config.value = _configBox.values.first;
    } else {
      // 创建默认配置
      final defaultConfig = QuizConfig();
      _configBox.add(defaultConfig);
      config.value = defaultConfig;
    }
  }

  /// 加载题目
  void _loadQuestions() {
    if (_questionBox.isEmpty) {
      // 首次使用,导入默认题库
      _importDefaultQuestions();
    } else {
      questions.assignAll(_questionBox.values.toList());
    }
  }

  /// 导入默认题库
  Future<void> _importDefaultQuestions() async {
    final defaultQuestions = QuizData.getAllQuestions();
    for (var q in defaultQuestions) {
      final question = QuizQuestion.fromLegacyMap(q);
      await _questionBox.put(question.id, question);
    }
    questions.assignAll(_questionBox.values.toList());
  }

  /// 更新配置
  Future<void> updateConfig(QuizConfig newConfig) async {
    await newConfig.save();
    config.value = newConfig;
  }

  /// 加载今日游玩次数
  void _loadTodayPlayCount() {
    final today = _getTodayKey();
    todayPlayCount.value = _playRecordBox.get(today, defaultValue: 0) as int;
  }

  /// 获取今日日期key
  String _getTodayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// 检查是否可以游玩
  bool canPlay() {
    final limit = config.value?.dailyPlayLimit ?? 0;
    if (limit == 0) return true; // 0表示不限制
    return todayPlayCount.value < limit;
  }

  /// 获取剩余次数
  int getRemainingPlays() {
    final limit = config.value?.dailyPlayLimit ?? 0;
    if (limit == 0) return -1; // -1表示不限制
    return (limit - todayPlayCount.value).clamp(0, limit);
  }

  /// 记录一次游玩
  Future<void> recordPlay() async {
    final today = _getTodayKey();
    final count = (_playRecordBox.get(today, defaultValue: 0) as int) + 1;
    await _playRecordBox.put(today, count);
    todayPlayCount.value = count;
  }

  /// 导入题库(JSON 格式)
  Future<void> importQuestions(String jsonStr) async {
    try {
      final List<dynamic> list = jsonDecode(jsonStr);
      int imported = 0;

      for (var item in list) {
        if (item is Map<String, dynamic>) {
          QuizQuestion question;

          // 尝试从新格式解析
          if (item.containsKey('id')) {
            question = QuizQuestion.fromJson(item);
          } else {
            // 从旧格式解析
            question = QuizQuestion.fromLegacyMap(item);
          }

          await _questionBox.put(question.id, question);
          imported++;
        }
      }

      questions.assignAll(_questionBox.values.toList());
      Get.snackbar('导入成功', '成功导入 $imported 道题目');
    } catch (e) {
      debugPrint('导入题库失败: $e');
      rethrow;
    }
  }

  /// 导出题库
  String exportQuestions() {
    final list = questions.map((q) => q.toJson()).toList();
    return jsonEncode(list);
  }

  /// 清空题库
  Future<void> clearQuestions() async {
    await _questionBox.clear();
    questions.clear();
  }

  /// 恢复默认题库
  Future<void> restoreDefaultQuestions() async {
    await clearQuestions();
    await _importDefaultQuestions();
  }

  /// 为单个题目生成图片
  Future<void> generateImageForQuestion(QuizQuestion question) async {
    if (!config.value!.enableImageGen) {
      throw Exception('未启用 AI 生成图片功能');
    }

    if (config.value!.imageGenConfigId == null) {
      throw Exception('未配置生图 AI');
    }

    // 检查是否已在队列中
    if (_generatingQueue.contains(question.id)) {
      return;
    }

    _generatingQueue.add(question.id);

    try {
      // 更新状态
      question.imageStatus = 'generating';
      question.updatedAt = DateTime.now();
      await question.save();
      questions.refresh();

      // 获取生图配置
      final imageGenConfig = _openAIService.configs
          .firstWhereOrNull((c) => c.id == config.value!.imageGenConfigId);

      if (imageGenConfig == null) {
        throw Exception('生图 AI 配置不存在');
      }

      // 构建提示词
      final knowledge =
          '${question.question}\n答案: ${question.options[question.correctIndex]}\n解释: ${question.explanation}';
      final prompt =
          config.value!.imageGenPrompt.replaceAll('{knowledge}', knowledge);

      // 调用 AI 生成图片提示词
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
        config: imageGenConfig,
      );

      debugPrint('生成的图片提示词: $imagePrompt');

      // 调用生图 API
      final imageUrl = await _generateImage(imagePrompt, imageGenConfig);

      // 下载并保存图片
      final imagePath = await _downloadAndSaveImage(imageUrl, question.id);

      // 更新题目
      question.imagePath = imagePath;
      question.imageStatus = 'success';
      question.imageError = null;
      question.updatedAt = DateTime.now();
      await question.save();
      questions.refresh();

      debugPrint('图片生成成功: $imagePath');
    } catch (e) {
      debugPrint('生成图片失败: $e');
      question.imageStatus = 'failed';
      question.imageError = e.toString();
      question.updatedAt = DateTime.now();
      await question.save();
      questions.refresh();
      rethrow;
    } finally {
      _generatingQueue.remove(question.id);
    }
  }

  /// 批量生成图片
  Future<void> batchGenerateImages({
    Function(int current, int total, String status)? onProgress,
  }) async {
    final questionsToGenerate =
        questions.where((q) => q.canGenerateImage).toList();

    if (questionsToGenerate.isEmpty) {
      Get.snackbar('提示', '没有需要生成图片的题目');
      return;
    }

    int total = questionsToGenerate.length;
    int success = 0;
    int failed = 0;

    for (int i = 0; i < questionsToGenerate.length; i++) {
      final question = questionsToGenerate[i];

      onProgress?.call(i + 1, total, '正在生成: ${question.question}');

      try {
        await generateImageForQuestion(question);
        success++;

        // API 调用频率控制,每次生成后等待 3 秒
        if (i < questionsToGenerate.length - 1) {
          await Future.delayed(const Duration(seconds: 3));
        }
      } catch (e) {
        failed++;
        debugPrint('题目 ${question.id} 生成失败: $e');
        // 继续下一个
      }
    }

    onProgress?.call(total, total, '完成: 成功 $success, 失败 $failed');
  }

  /// 调用生图 API
  Future<String> _generateImage(String prompt, OpenAIConfig config) async {
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
  Future<String> _downloadAndSaveImage(String url, String questionId) async {
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final file = File('${_imageDir.path}/$questionId.png');
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

  /// 删除题目图片
  Future<void> deleteQuestionImage(QuizQuestion question) async {
    if (question.imagePath != null) {
      final file = File(question.imagePath!);
      if (await file.exists()) {
        await file.delete();
      }

      question.imagePath = null;
      question.imageStatus = null;
      question.imageError = null;
      question.updatedAt = DateTime.now();
      await question.save();
      questions.refresh();
    }
  }

  /// 获取图片缓存大小
  Future<int> getImageCacheSize() async {
    int totalSize = 0;

    if (await _imageDir.exists()) {
      final files = await _imageDir.list().toList();
      for (var file in files) {
        if (file is File) {
          final stat = await file.stat();
          totalSize += stat.size;
        }
      }
    }

    return totalSize;
  }

  /// 清空图片缓存
  Future<void> clearImageCache() async {
    if (await _imageDir.exists()) {
      await _imageDir.delete(recursive: true);
      await _imageDir.create();
    }

    // 清除所有题目的图片路径
    for (var question in questions) {
      question.imagePath = null;
      question.imageStatus = null;
      question.imageError = null;
      question.updatedAt = DateTime.now();
      await question.save();
    }
    questions.refresh();
  }

  /// 导出配置和题库(用于备份)
  Map<String, dynamic> exportData() {
    return {
      'config': config.value?.toJson(),
      'questions': questions.map((q) => q.toJson()).toList(),
    };
  }

  /// 导入配置和题库(用于恢复)
  Future<void> importData(Map<String, dynamic> data) async {
    // 导入配置
    if (data['config'] != null) {
      final newConfig =
          QuizConfig.fromJson(data['config'] as Map<String, dynamic>);
      await _configBox.clear();
      await _configBox.add(newConfig);
      config.value = newConfig;
    }

    // 导入题库
    if (data['questions'] != null) {
      await _questionBox.clear();
      final questionsList = data['questions'] as List<dynamic>;
      for (var item in questionsList) {
        final question = QuizQuestion.fromJson(item as Map<String, dynamic>);
        await _questionBox.put(question.id, question);
      }
      questions.assignAll(_questionBox.values.toList());
    }
  }
}
