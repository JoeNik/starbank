import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import '../utils/remote_json.dart';

import '../data/encyclopedia_data.dart';
import '../models/encyclopedia_config.dart';
import '../models/encyclopedia_explanation_cache.dart';
import '../models/encyclopedia_question.dart';
import '../models/openai_config.dart';
import 'android_background_network_service.dart';
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
    final list = tryDecodeJsonList(jsonStr);
    if (list == null) {
      throw Exception('题库 JSON 格式错误，顶层必须是数组（或内容为空）');
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

    final resp = await AndroidBackgroundNetworkService.protect(
      'encyclopedia_sync_${DateTime.now().microsecondsSinceEpoch}',
      () => http.get(uri).timeout(const Duration(seconds: 30)),
      title: 'StarBank 百科',
      text: '正在同步题库',
    );
    if (resp.statusCode != 200) {
      throw Exception('同步失败: HTTP ${resp.statusCode}');
    }
    final body = utf8.decode(resp.bodyBytes);
    if (body.trim().isEmpty) {
      throw Exception('同步失败: 远端返回空内容');
    }
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
    final decoded = tryDecodeJsonList(jsonArray);
    if (decoded == null) {
      throw Exception('AI 返回格式错误，顶层不是数组（或内容为空）');
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

  String buildBuiltInExample(EncyclopediaQuestion question) {
    final text = '${question.question} ${question.answer}';
    final category = question.category.toLowerCase();

    bool has(Iterable<String> words) => words.any(text.contains);

    if (has(['月亮', '月相'])) {
      return '可以连续几晚在同一时间看看月亮，记录亮面变大还是变小，就能看到月相变化。';
    }
    if (has(['星星', '太阳', '白天', '黑夜'])) {
      return '白天和晚上分别看看天空亮度，你会发现强光会让微弱的星光不容易被看见。';
    }
    if (has(['四季', '季节', '夏天', '冬天'])) {
      return '同一棵树在春夏秋冬的样子不同，是观察季节变化的好线索。';
    }
    if (has(['雨', '云', '雾', '露', '霜'])) {
      return '下雨前后观察云、地面水迹和空气湿度，可以把水循环和天气联系起来。';
    }
    if (has(['彩虹', '折射', '反射'])) {
      return '雨后太阳出来时，背对太阳看看有水滴的天空方向，有机会看到彩虹。';
    }
    if (has(['雷', '闪电'])) {
      return '看到闪电后再听雷声，常常会发现声音来得更晚，因为光传播得比声音快。';
    }
    if (has(['风', '气压'])) {
      return '看看旗子、树叶或风车朝哪里动，就能判断空气正在往哪个方向流动。';
    }
    if (has(['汗', '体温', '热'])) {
      return '运动后摸摸额头和手臂，再感受汗水蒸发时的凉意，就能理解身体怎样散热。';
    }
    if (has(['牙', '刷牙', '蛀牙'])) {
      return '吃完东西后照照镜子，牙缝里可能有残渣，刷牙就是在清理这些地方。';
    }
    if (has(['睡', '哈欠', '困'])) {
      return '如果前一晚睡得少，第二天更容易打哈欠或走神，这说明身体需要休息。';
    }
    if (has(['伤口', '血', '结痂'])) {
      return '小擦伤恢复时不要抠痂，观察它慢慢变干脱落，就是皮肤修复的过程。';
    }
    if (has(['叶', '植物', '种子', '花', '根'])) {
      return '把一盆植物放在窗边，隔几天看看新叶和茎的方向，能观察到植物对环境的反应。';
    }
    if (has(['鸟', '羽毛', '翅膀'])) {
      return '观察鸟起飞和降落时翅膀的动作，可以看到它们怎样推动空气。';
    }
    if (has(['鱼', '水里', '鳃'])) {
      return '看鱼游动时嘴巴和鳃盖一开一合，就是水流经过鳃帮助呼吸。';
    }
    if (has(['猫', '狗', '眼睛', '夜里'])) {
      return '傍晚光线变暗时，动物的瞳孔变化能帮助它们更好地利用微弱光线。';
    }
    if (has(['影子', '光线'])) {
      return '用台灯照一本书，移动书的位置和角度，影子的大小和方向会跟着改变。';
    }
    if (has(['磁铁', '铁', '指南针'])) {
      return '用磁铁分别靠近回形针、纸片和塑料尺，就能比较哪些材料会被吸引。';
    }
    if (has(['冰', '浮', '水面'])) {
      return '把冰块放进清水里，观察它浮在水面上，就能看到密度不同带来的结果。';
    }
    if (has(['声音', '振动'])) {
      return '轻轻拨动橡皮筋，听声音的同时看它振动，能明白声音和振动有关。';
    }
    if (has(['垃圾', '回收', '污染'])) {
      return '把纸盒、果皮和旧电池分开放，能看到不同垃圾需要不同处理方法。';
    }
    if (has(['电灯', '电流', '电池'])) {
      return '在家长帮助下观察手电筒，开关闭合后灯亮，断开后灯灭，这就是电路在工作。';
    }
    if (has(['冰箱', '制冷', '食物'])) {
      return '摸摸冰箱背面或侧面会有些热，因为冰箱正在把里面的热量搬到外面。';
    }

    switch (category) {
      case 'astronomy':
      case 'space':
        return '晚上观察天空时，可以把看到的现象和地球、月亮、太阳的位置关系联系起来。';
      case 'weather':
        return '天气变化常能从云、风、温度和地面水迹里找到线索，出门前可以一起观察。';
      case 'body':
        return '身体的感觉常常在提醒我们发生了什么，比如热、累、饿、困都值得认真听一听。';
      case 'animal':
        return '观察动物的身体结构和动作，常能发现它们怎样适应自己的生活环境。';
      case 'plant':
        return '照顾植物时记录浇水、光照和生长变化，可以把植物知识看得更清楚。';
      case 'physics':
        return '用安全的小实验观察光、声音、冷热或运动，能把抽象的物理现象变得直观。';
      case 'chemistry':
        return '厨房和清洁用品里有很多化学现象，但观察时一定要有大人陪同，不能随意混合材料。';
      case 'earth':
      case 'environment':
        return '把身边的水、土壤、垃圾和天气联系起来看，会更容易理解地球环境怎样运转。';
      case 'technology':
        return '看看家里的电器什么时候工作、什么时候停止，能帮助理解科技怎样服务生活。';
      case 'food':
        return '做饭和吃饭时可以观察颜色、气味、软硬变化，很多食物知识都藏在这些变化里。';
      case 'math':
        return '把数量、形状和规律放到积木、棋盘或日常物品里看，数学会更容易理解。';
      case 'safety':
        return '遇到安全问题时先停下来观察环境，再按正确方法行动，比着急乱动更可靠。';
      case 'ocean':
        return '看海洋纪录片或水族箱时，留意水流、动物身体和生活环境之间的关系。';
    }

    return '可以把“${question.answer}”当作线索，和家长一起找一个安全、容易观察的场景来验证。';
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
      example: buildBuiltInExample(question),
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
      final data = tryDecodeJsonObject(jsonObject);
      if (data == null) {
        throw Exception('返回内容为空或不是 JSON 对象');
      }

      final shortAnswer = (asNonEmptyString(data['short_answer']) ?? '').trim();
      final why = (asNonEmptyString(data['why']) ?? '').trim();
      final example = (asNonEmptyString(data['example']) ?? '').trim();

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
