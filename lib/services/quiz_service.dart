import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
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
    // QuizQuestionAdapter and QuizConfigAdapter are registered in StorageService (main.dart ordering ensures StorageService runs first).
    // Avoiding duplicate registration check here as it might be flaky if hot restart happens.
    // We rely on StorageService.

    _configBox = await Hive.openBox<QuizConfig>('quiz_config');
    _questionBox = await Hive.openBox<QuizQuestion>('quiz_questions');
    _playRecordBox = await Hive.openBox('quiz_play_record');

    // 初始化图片缓存目录 (仅在非 Web 环境下)
    if (!kIsWeb) {
      final appDir = await getApplicationDocumentsDirectory();
      _imageDir = Directory('${appDir.path}/quiz_images');
      if (!await _imageDir.exists()) {
        await _imageDir.create(recursive: true);
      }
    }

    // 加载配置
    _loadConfig();

    // 加载题目
    _loadQuestions();

    // 加载今日游玩次数
    _loadTodayPlayCount();

    return this;
  }

  // ... (省略中间未变代码)

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
    // 如果配置已经在box中，使用save()
    // 否则使用putAt更新第一个配置
    if (newConfig.isInBox) {
      await newConfig.save();
    } else {
      // 更新box中的第一个配置
      if (_configBox.isNotEmpty) {
        await _configBox.putAt(0, newConfig);
      } else {
        await _configBox.add(newConfig);
      }
    }
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

  /// 添加题目
  Future<void> addQuestion(QuizQuestion question) async {
    await _questionBox.put(question.id, question);
    if (!questions.any((q) => q.id == question.id)) {
      questions.add(question);
    } else {
      final index = questions.indexWhere((q) => q.id == question.id);
      questions[index] = question;
    }
    questions.refresh();
  }

  /// 更新题目
  Future<void> updateQuestion(QuizQuestion question) async {
    question.updatedAt = DateTime.now();
    await _questionBox.put(question.id, question);
    final index = questions.indexWhere((q) => q.id == question.id);
    if (index != -1) {
      questions[index] = question;
      questions.refresh();
    }
  }

  /// 删除题目
  Future<void> deleteQuestion(String id) async {
    await _questionBox.delete(id);
    questions.removeWhere((q) => q.id == id);
  }

  /// 批量删除题目
  Future<void> deleteQuestions(List<String> ids) async {
    await _questionBox.deleteAll(ids);
    questions.removeWhere((q) => ids.contains(q.id));
  }

  /// 检查题目是否重复
  /// 采用更智能的匹配方案：规范化文本 + 字符相似度检查
  bool isDuplicate(String questionText, {String? excludeId}) {
    final newNormalized = _normalizeText(questionText);
    if (newNormalized.isEmpty) return false;

    for (var q in questions) {
      if (q.id == excludeId) continue;

      final existingNormalized = _normalizeText(q.question);

      // 1. 规范化后完全匹配
      if (newNormalized == existingNormalized) return true;

      // 2. 相似度匹配 (阈值设为 0.85)
      // 处理类似 "过年为什么要贴春联？" 和 "过年贴春联的原因是什么？" 的情况
      if (_calculateSimilarity(newNormalized, existingNormalized) > 0.85) {
        debugPrint('检测到疑似重复题目: \n新题: $questionText \n旧题: ${q.question}');
        return true;
      }
    }
    return false;
  }

  /// 文本规范化：移除标点符号、特殊字符、空格，并转为小写
  String _normalizeText(String text) {
    return text
        .replaceAll(RegExp(r'[^\u4e00-\u9fa5a-zA-Z0-9]'), '')
        .toLowerCase()
        .trim();
  }

  /// 计算两个文本的相似度 (综合 Jaccard 相似度和重叠系数)
  double _calculateSimilarity(String s1, String s2) {
    if (s1.isEmpty || s2.isEmpty) return 0.0;

    // 使用字符集合计算重叠度
    final set1 = s1.split('').toSet();
    final set2 = s2.split('').toSet();

    final intersection = set1.intersection(set2).length;
    if (intersection == 0) return 0.0;

    // Jaccard 相似度: 交集 / 并集
    final jaccard = intersection / set1.union(set2).length;

    // 重叠系数: 交集 / 较短字符串的长度 (对包含关系识别更好)
    final overlap =
        intersection / (set1.length < set2.length ? set1.length : set2.length);

    // 取两者中的较大值。如果一个题目是另一个题目的子集，或者两者用词高度接近，都会判定为相似
    return jaccard > overlap ? jaccard : overlap;
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

          // 处理图片导入: 如果是非Web环境且是Base64图片,转存为本地文件
          if (!kIsWeb &&
              question.imagePath != null &&
              question.imagePath!.startsWith('data:image')) {
            try {
              final base64Data = question.imagePath!.split(',')[1];
              final bytes = base64Decode(base64Data);
              // 确保存储目录存在
              if (!await _imageDir.exists()) {
                await _imageDir.create(recursive: true);
              }
              final file = File('${_imageDir.path}/${question.id}.png');
              await file.writeAsBytes(bytes);
              question.imagePath = file.path;
              debugPrint('已将导入的Base64图片转存为本地文件: ${file.path}');
            } catch (e) {
              debugPrint('转存Base64图片失败: $e');
              // 失败则保留Base64原样
            }
          }

          await _questionBox.put(question.id, question);

          // 如果列表中已有该ID，更新它；否则添加
          final index = questions.indexWhere((q) => q.id == question.id);
          if (index != -1) {
            questions[index] = question;
          } else {
            questions.add(question);
          }

          imported++;
        }
      }

      // 整体刷新一次列表以确保UI更新
      questions.refresh();
      Get.snackbar('导入成功', '成功导入 $imported 道题目');
    } catch (e) {
      debugPrint('导入题库失败: $e');
      rethrow;
    }
  }

  /// 备份所有题目(包含图片转Base64)
  Future<List<Map<String, dynamic>>> backupQuestions() async {
    final List<Map<String, dynamic>> list = [];

    for (var q in questions) {
      final json = q.toJson();

      // 处理图片导出: 将本地图片转换为Base64内联到JSON中
      if (q.imagePath != null) {
        if (kIsWeb) {
          // Web端直接使用现有的 path (Base64 or URL)
          json['imagePath'] = q.imagePath;
        } else {
          // 移动端：如果是文件路径，转为 Base64
          // 检查是否是 Base64 (如果之前导入失败保留了Base64)
          if (q.imagePath!.startsWith('data:image')) {
            json['imagePath'] = q.imagePath;
          } else {
            // 尝试读取文件
            final file = File(q.imagePath!);
            if (await file.exists()) {
              try {
                final bytes = await file.readAsBytes();
                final base64 = base64Encode(bytes);
                // 假设是 PNG, 后续可以根据文件头判断
                json['imagePath'] = 'data:image/png;base64,$base64';
              } catch (e) {
                debugPrint('导出图片失败: $e');
                // 读取失败，保留路径或者置空? 保留路径让用户知道有问题
                json['imagePath'] = q.imagePath;
              }
            } else {
              // 文件不存在或 URL
              json['imagePath'] = q.imagePath;
            }
          }
        }
      }
      list.add(json);
    }
    return list;
  }

  /// 导出题库(JSON字符串)
  Future<String> exportQuestions() async {
    final list = await backupQuestions();
    return jsonEncode(list);
  }

  /// 恢复题目数据(List)
  Future<void> restoreQuestions(List<dynamic> list) async {
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

        // 处理图片导入: 如果是非Web环境且是Base64图片,转存为本地文件
        if (!kIsWeb &&
            question.imagePath != null &&
            question.imagePath!.startsWith('data:image')) {
          try {
            final base64Data = question.imagePath!.split(',')[1];
            final bytes = base64Decode(base64Data);
            // 确保存储目录存在
            if (!await _imageDir.exists()) {
              await _imageDir.create(recursive: true);
            }
            final file = File('${_imageDir.path}/${question.id}.png');
            await file.writeAsBytes(bytes);
            question.imagePath = file.path;
            debugPrint('已将导入的Base64图片转存为本地文件: ${file.path}');
          } catch (e) {
            debugPrint('转存Base64图片失败: $e');
            // 失败则保留Base64原样
          }
        }

        await _questionBox.put(question.id, question);

        // 如果列表中已有该ID，更新它；否则添加
        final index = questions.indexWhere((q) => q.id == question.id);
        if (index != -1) {
          questions[index] = question;
        } else {
          questions.add(question);
        }

        imported++;
      }
    }
    questions.refresh();
    debugPrint('已恢复 $imported 道题目');
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
  Future<void> generateImageForQuestion(QuizQuestion question,
      {int imageCount = 3}) async {
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

      final rawPrompt =
          config.value!.imageGenPrompt.replaceAll('{knowledge}', knowledge);

      // 尝试获取用于生成提示词的 Chat 配置
      // 优先使用专门配置的 Chat AI，如果没有则使用全局默认，最后才尝试使用生图配置
      OpenAIConfig? chatConfig;
      if (config.value!.chatConfigId != null) {
        chatConfig = _openAIService.configs
            .firstWhereOrNull((c) => c.id == config.value!.chatConfigId);
      }
      chatConfig ??= _openAIService.currentConfig.value;
      chatConfig ??= imageGenConfig; // 最后的兜底

      debugPrint('使用配置[${chatConfig?.name}]优化生图提示词...');

      // 调用 AI 生成图片提示词
      String imagePrompt;
      try {
        imagePrompt = await _openAIService.chat(
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
          userMessage: rawPrompt,
          config: chatConfig,
        );
      } catch (e) {
        debugPrint('提示词优化失败，使用原始提示词: $e');
        // 如果优化失败，使用原始提示词并追加风格
        imagePrompt = rawPrompt;
        if (!imagePrompt.toLowerCase().contains('style:')) {
          imagePrompt +=
              '\n\nStyle: Cute, cartoon, children illustration, colorful, warm, flat vector art, simple background, Chinese New Year theme.';
        }
      }

      debugPrint('最终生图提示词: $imagePrompt');

      // 调用生图 API,生成多张图片
      final imageUrls = await _openAIService.generateImages(
        prompt: imagePrompt,
        n: imageCount,
        config: imageGenConfig,
        model: config.value!.imageGenModel,
      );

      if (imageUrls.isEmpty) {
        throw Exception('未能生成图片');
      }

      // 这里返回图片URL列表，让UI层处理选择
      // 但由于这是service层，我们需要一个回调或者直接使用第一张
      // 为了保持简单，我们使用第一张图片
      final imageUrl = imageUrls.first;

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

  // _generateImage is removed in favor of _openAIService.generateImages

  /// 下载并转换为Base64 (保存到数据库)
  Future<String> _downloadAndSaveImage(
      String urlOrDataUri, String questionId) async {
    try {
      // 如果已是 Base64，直接返回
      if (urlOrDataUri.startsWith('data:image')) {
        return urlOrDataUri;
      }

      // 下载并转换为 Base64
      final response = await http
          .get(Uri.parse(urlOrDataUri))
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final base64String = base64Encode(response.bodyBytes);
        // 假设是 PNG，通用头
        return 'data:image/png;base64,$base64String';
      } else {
        throw Exception('下载图片失败: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('转换图片失败: $e');
      rethrow;
    }
  }

  /// 删除题目图片
  Future<void> deleteQuestionImage(QuizQuestion question) async {
    if (question.imagePath != null) {
      if (!kIsWeb) {
        final file = File(question.imagePath!);
        if (await file.exists()) {
          await file.delete();
        }
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

    if (kIsWeb) {
      // Web 环境: 计算 Hive 中存储的 Base64 图片大小
      for (var q in questions) {
        if (q.imagePath != null && q.imagePath!.startsWith('data:image')) {
          totalSize += q.imagePath!.length;
        }
      }
      return totalSize;
    }

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
    if (kIsWeb) {
      // Web 清除逻辑 (如果有)
    } else if (await _imageDir.exists()) {
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
