import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

import '../data/encyclopedia_data.dart';
import '../models/encyclopedia_config.dart';
import '../models/encyclopedia_explanation_cache.dart';
import '../models/encyclopedia_question.dart';
import '../models/openai_config.dart';
import 'openai_service.dart';

class EncyclopediaExplanationResult {
  final String shortAnswer;
  final String why;
  final String example;
  final bool fromCache;
  final bool fromBuiltIn;
  final bool usedFallback;
  final String? errorMessage;

  const EncyclopediaExplanationResult({
    required this.shortAnswer,
    required this.why,
    required this.example,
    required this.fromCache,
    this.fromBuiltIn = false,
    this.usedFallback = false,
    this.errorMessage,
  });
}

class EncyclopediaService extends GetxService {
  late Box<EncyclopediaQuestion> _questionBox;
  late Box<EncyclopediaConfig> _configBox;
  late Box<EncyclopediaExplanationCache> _cacheBox;
  late Box<dynamic> _playRecordBox;

  final OpenAIService _openAIService = Get.find<OpenAIService>();

  final Rx<EncyclopediaConfig?> config = Rx<EncyclopediaConfig?>(null);
  final RxList<EncyclopediaQuestion> questions = <EncyclopediaQuestion>[].obs;
  final RxInt todayPlayCount = 0.obs;

  Future<EncyclopediaService> init() async {
    _configBox = await Hive.openBox<EncyclopediaConfig>('encyclopedia_config');
    _questionBox =
        await Hive.openBox<EncyclopediaQuestion>('encyclopedia_questions');
    _cacheBox = await Hive.openBox<EncyclopediaExplanationCache>(
        'encyclopedia_explanation_cache');
    _playRecordBox = await Hive.openBox('encyclopedia_play_record');

    _loadConfig();
    await _loadQuestions();
    _loadTodayPlayCount();
    return this;
  }

  void _loadConfig() {
    if (_configBox.isNotEmpty) {
      config.value = _configBox.values.first;
    } else {
      final defaultConfig = EncyclopediaConfig();
      _configBox.add(defaultConfig);
      config.value = defaultConfig;
    }
  }

  Future<void> _loadQuestions() async {
    if (_questionBox.isEmpty) {
      await restoreDefaultQuestions();
      return;
    }
    await _normalizeExistingQuestions();
    questions.assignAll(_questionBox.values.toList());
  }

  Future<void> _normalizeExistingQuestions() async {
    for (final q in _questionBox.values) {
      if (q.options.isEmpty) {
        q.options = [q.answer.isNotEmpty ? q.answer : '正确', '不正确'];
        q.correctIndex = 0;
        q.answer = q.options.first;
        q.updatedAt = DateTime.now();
        await q.save();
        continue;
      }

      if (q.options.length == 1) {
        final correct = q.options.first;
        q.options = [correct, correct == '不是这样' ? '是这样' : '不是这样'];
        q.correctIndex = 0;
        q.answer = correct;
        q.updatedAt = DateTime.now();
        await q.save();
        continue;
      }

      if (q.options.length == 2 &&
          q.correctIndex >= 0 &&
          q.correctIndex < q.options.length) {
        final correct = q.options[q.correctIndex];
        if (q.answer != correct) {
          q.answer = correct;
          q.updatedAt = DateTime.now();
          await q.save();
        }
        continue;
      }

      final safeIndex = q.correctIndex.clamp(0, q.options.length - 1).toInt();
      final correct = q.options.isNotEmpty ? q.options[safeIndex] : q.answer;
      final wrong = q.options.firstWhere(
        (option) => option != correct,
        orElse: () => correct == '不是这样' ? '是这样' : '不是这样',
      );

      if (safeIndex == 0) {
        q.options = [correct, wrong];
        q.correctIndex = 0;
      } else {
        q.options = [wrong, correct];
        q.correctIndex = 1;
      }
      q.answer = correct;
      q.updatedAt = DateTime.now();
      await q.save();
    }
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  void _loadTodayPlayCount() {
    todayPlayCount.value =
        (_playRecordBox.get(_todayKey(), defaultValue: 0) as num?)?.toInt() ??
            0;
  }

  bool canPlay() {
    final limit = config.value?.dailyPlayLimit ?? 0;
    if (limit == 0) return true;
    return todayPlayCount.value < limit;
  }

  Future<void> recordPlay() async {
    final key = _todayKey();
    final newCount =
        ((_playRecordBox.get(key, defaultValue: 0) as num?)?.toInt() ?? 0) + 1;
    await _playRecordBox.put(key, newCount);
    todayPlayCount.value = newCount;
  }

  int getRemainingPlays() {
    final limit = config.value?.dailyPlayLimit ?? 0;
    if (limit == 0) return -1;
    return (limit - todayPlayCount.value).clamp(0, limit).toInt();
  }

  Future<void> updateConfig(EncyclopediaConfig newConfig) async {
    if (newConfig.isInBox) {
      await newConfig.save();
    } else if (_configBox.isNotEmpty) {
      await _configBox.putAt(0, newConfig);
    } else {
      await _configBox.add(newConfig);
    }
    config.value = newConfig;
  }

  Future<void> restoreDefaultQuestions() async {
    await _questionBox.clear();
    await _cacheBox.clear();
    final defaults = EncyclopediaData.getDefaultQuestions();
    for (final raw in defaults) {
      final q = EncyclopediaQuestion.fromJson(raw);
      await _questionBox.put(q.id, q);
    }
    questions.assignAll(_questionBox.values.toList());
  }

  Future<int> importQuestionsFromJsonString(
    String jsonStr, {
    String source = 'remote',
  }) async {
    final parsed = _parseQuestionsFromJsonString(jsonStr, source: source);
    for (final q in parsed) {
      await _questionBox.put(q.id, q); // upsert by id
    }
    questions.assignAll(_questionBox.values.toList());
    return parsed.length;
  }

  Future<int> replaceQuestionsFromJsonString(
    String jsonStr, {
    String source = 'remote',
  }) async {
    final parsed = _parseQuestionsFromJsonString(jsonStr, source: source);
    if (parsed.isEmpty) {
      throw Exception('题库中没有可用题目，已保留本地题库');
    }

    await _questionBox.clear();
    await _cacheBox.clear();
    for (final q in parsed) {
      await _questionBox.put(q.id, q);
    }
    questions.assignAll(_questionBox.values.toList());
    return parsed.length;
  }

  List<EncyclopediaQuestion> _parseQuestionsFromJsonString(
    String jsonStr, {
    required String source,
  }) {
    final list = jsonDecode(jsonStr);
    if (list is! List) {
      throw Exception('题库 JSON 格式错误，顶层必须是数组');
    }

    final parsed = <EncyclopediaQuestion>[];
    for (final item in list) {
      if (item is! Map) continue;
      try {
        final q = EncyclopediaQuestion.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (q.question.isEmpty || q.options.length != 2) continue;
        q.source = source;
        q.updatedAt = DateTime.now();
        parsed.add(q);
      } catch (e) {
        debugPrint('导入百科题失败，已跳过一条: $e');
      }
    }
    return parsed;
  }

  Future<int> syncQuestionsFromUrl() async {
    final url = config.value?.importUrl?.trim() ?? '';
    if (url.isEmpty) {
      throw Exception('请先配置题库 URL');
    }
    final uri = Uri.parse(url);
    if (uri.scheme != 'https') {
      throw Exception('仅支持 HTTPS URL');
    }

    final resp = await http.get(uri).timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      throw Exception('同步失败: HTTP ${resp.statusCode}');
    }
    final body = utf8.decode(resp.bodyBytes);
    return replaceQuestionsFromJsonString(body, source: 'remote');
  }

  Future<int> generateQuestionsWithAI({
    required String category,
    required int count,
  }) async {
    final currentConfig = config.value;
    if (currentConfig == null) {
      throw Exception('百科配置未初始化');
    }
    if (count <= 0 || count > 50) {
      throw Exception('生成数量必须在 1-50 之间');
    }

    final prompt = currentConfig.questionGenPromptTemplate
        .replaceAll(
            '{category}', category.trim().isEmpty ? '生活科学百科' : category.trim())
        .replaceAll('{count}', count.toString());

    final chatConfig = _resolveChatConfig();
    final model = (currentConfig.chatModel?.isNotEmpty ?? false)
        ? currentConfig.chatModel!
        : (chatConfig.selectedModel.isNotEmpty
            ? chatConfig.selectedModel
            : 'gpt-4o-mini');

    final response = await _openAIService.chat(
      systemPrompt: '请严格按用户要求输出 JSON 数组。',
      userMessage: prompt,
      config: chatConfig,
      model: model,
    );

    final jsonArray = _extractJsonArray(response);
    final decoded = jsonDecode(jsonArray);
    if (decoded is! List) {
      throw Exception('AI 返回格式错误，顶层不是数组');
    }

    int imported = 0;
    final existingIds = _questionBox.keys.map((e) => e.toString()).toSet();
    for (final item in decoded) {
      if (item is! Map) continue;
      try {
        final q = EncyclopediaQuestion.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (q.question.isEmpty || q.options.length != 2) continue;
        q.source = 'ai';
        if (existingIds.contains(q.id)) {
          q.id = '${q.id}_${DateTime.now().microsecondsSinceEpoch}';
        }
        existingIds.add(q.id);
        q.updatedAt = DateTime.now();
        await _questionBox.put(q.id, q);
        imported++;
      } catch (e) {
        debugPrint('AI 生成百科题导入失败，已跳过一条: $e');
      }
    }

    questions.assignAll(_questionBox.values.toList());
    return imported;
  }

  String _promptVersion(String prompt) {
    return md5.convert(utf8.encode(prompt)).toString();
  }

  String _cacheKey({
    required EncyclopediaQuestion question,
    required String model,
    required String promptVersion,
  }) {
    return '${question.id}|$model|$promptVersion';
  }

  bool _isCacheExpired(EncyclopediaExplanationCache cache) {
    final currentConfig = config.value;
    if (currentConfig == null) return false;
    if (!currentConfig.enableAutoRefresh) return false;
    final expireDays = currentConfig.cacheExpiryDays;
    if (expireDays <= 0) return false;
    return DateTime.now().difference(cache.updatedAt).inDays >= expireDays;
  }

  OpenAIConfig _resolveChatConfig() {
    final currentConfig = config.value;
    if (currentConfig == null) {
      throw Exception('百科配置未初始化');
    }
    OpenAIConfig? chatConfig;
    if (currentConfig.chatConfigId != null) {
      chatConfig = _openAIService.configs
          .firstWhereOrNull((c) => c.id == currentConfig.chatConfigId);
    }
    chatConfig ??= _openAIService.currentConfig.value;
    if (chatConfig == null) {
      throw Exception('未配置 AI 接口');
    }
    return chatConfig;
  }

  String _extractJsonObject(String raw) {
    String cleaned = raw.trim();
    if (cleaned.startsWith('```json')) {
      cleaned = cleaned.substring(7);
    } else if (cleaned.startsWith('```')) {
      cleaned = cleaned.substring(3);
    }
    if (cleaned.endsWith('```')) {
      cleaned = cleaned.substring(0, cleaned.length - 3);
    }
    cleaned = cleaned.trim();

    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      return cleaned.substring(start, end + 1);
    }
    return cleaned;
  }

  String _extractJsonArray(String raw) {
    String cleaned = raw.trim();
    if (cleaned.startsWith('```json')) {
      cleaned = cleaned.substring(7);
    } else if (cleaned.startsWith('```')) {
      cleaned = cleaned.substring(3);
    }
    if (cleaned.endsWith('```')) {
      cleaned = cleaned.substring(0, cleaned.length - 3);
    }
    cleaned = cleaned.trim();

    final start = cleaned.indexOf('[');
    final end = cleaned.lastIndexOf(']');
    if (start != -1 && end != -1 && end > start) {
      return cleaned.substring(start, end + 1);
    }
    return cleaned;
  }

  EncyclopediaExplanationResult _fallbackFromQuestion(
    EncyclopediaQuestion question,
    String? errorMessage,
  ) {
    final fallback = question.explanation.isNotEmpty
        ? question.explanation
        : '这道题的正确答案是 ${question.answer}。';
    return EncyclopediaExplanationResult(
      shortAnswer: '正确答案是：${question.answer}',
      why: fallback,
      example: '生活中可以多观察类似现象，慢慢你会更理解这个知识点。',
      fromCache: false,
      fromBuiltIn: question.explanation.isNotEmpty,
      usedFallback: true,
      errorMessage: errorMessage,
    );
  }

  Future<EncyclopediaExplanationResult> getExplanation(
    EncyclopediaQuestion question, {
    bool forceRefresh = false,
  }) async {
    final currentConfig = config.value;
    if (currentConfig == null) {
      return _fallbackFromQuestion(question, '百科配置未初始化');
    }

    try {
      final chatConfig = _resolveChatConfig();
      final model = (currentConfig.chatModel?.isNotEmpty ?? false)
          ? currentConfig.chatModel!
          : (chatConfig.selectedModel.isNotEmpty
              ? chatConfig.selectedModel
              : 'gpt-4o-mini');
      final promptVersion = _promptVersion(currentConfig.promptTemplate);
      final key = _cacheKey(
        question: question,
        model: model,
        promptVersion: promptVersion,
      );

      final cached = _cacheBox.get(key);
      if (!forceRefresh && cached != null && !_isCacheExpired(cached)) {
        return EncyclopediaExplanationResult(
          shortAnswer: cached.shortAnswer,
          why: cached.why,
          example: cached.example,
          fromCache: true,
        );
      }

      final optionsText = question.options
          .asMap()
          .entries
          .map((e) => '${String.fromCharCode(65 + e.key)}. ${e.value}')
          .join('\n');
      final prompt = currentConfig.promptTemplate
          .replaceAll('{question}', question.question)
          .replaceAll('{options}', optionsText)
          .replaceAll('{answer}', question.answer)
          .replaceAll('{fallback}', question.explanation);

      final response = await _openAIService.chat(
        systemPrompt: '请严格按用户要求输出 JSON。',
        userMessage: prompt,
        config: chatConfig,
        model: model,
      );

      final jsonObject = _extractJsonObject(response);
      final data = jsonDecode(jsonObject) as Map<String, dynamic>;

      final shortAnswer = (data['short_answer'] as String? ?? '').trim();
      final why = (data['why'] as String? ?? '').trim();
      final example = (data['example'] as String? ?? '').trim();

      if (shortAnswer.isEmpty || why.isEmpty || example.isEmpty) {
        throw Exception('返回字段不完整');
      }

      // 事实基线约束：短答案必须包含标准答案文本，若不满足则回退。
      if (!shortAnswer.contains(question.answer)) {
        throw Exception('解析与标准答案不一致');
      }

      final entity = EncyclopediaExplanationCache(
        cacheKey: key,
        questionId: question.id,
        model: model,
        promptVersion: promptVersion,
        shortAnswer: shortAnswer,
        why: why,
        example: example,
      );
      await _cacheBox.put(key, entity);

      return EncyclopediaExplanationResult(
        shortAnswer: shortAnswer,
        why: why,
        example: example,
        fromCache: false,
      );
    } catch (e) {
      debugPrint('百科 AI 解析失败，回退内置解释: $e');
      return _fallbackFromQuestion(question, e.toString());
    }
  }

  Future<Map<String, dynamic>> exportData() async {
    return {
      'config': config.value?.toJson(),
      'questions': questions.map((q) => q.toJson()).toList(),
      'explanationCaches': _cacheBox.values.map((e) => e.toJson()).toList(),
      'playRecords': Map<String, dynamic>.from(_playRecordBox.toMap()),
    };
  }

  Future<void> importData(Map<String, dynamic> data) async {
    if (data['config'] != null) {
      final cfg = EncyclopediaConfig.fromJson(
          Map<String, dynamic>.from(data['config']));
      await _configBox.clear();
      await _configBox.add(cfg);
      config.value = cfg;
    }

    if (data['questions'] != null) {
      await _questionBox.clear();
      final list = data['questions'] as List<dynamic>;
      for (final item in list) {
        final q = EncyclopediaQuestion.fromJson(
            Map<String, dynamic>.from(item as Map));
        await _questionBox.put(q.id, q);
      }
      questions.assignAll(_questionBox.values.toList());
    }

    if (data['explanationCaches'] != null) {
      await _cacheBox.clear();
      for (final item in (data['explanationCaches'] as List<dynamic>)) {
        final c = EncyclopediaExplanationCache.fromJson(
          Map<String, dynamic>.from(item as Map),
        );
        await _cacheBox.put(c.cacheKey, c);
      }
    }

    if (data['playRecords'] != null) {
      await _playRecordBox.clear();
      final recordMap = Map<String, dynamic>.from(data['playRecords'] as Map);
      for (final entry in recordMap.entries) {
        await _playRecordBox.put(entry.key, entry.value);
      }
      _loadTodayPlayCount();
    }
  }

  Future<void> clearAllExplanationCache() async {
    await _cacheBox.clear();
  }
}
