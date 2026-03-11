import 'dart:math';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import '../data/hanzi_data.dart';
import '../models/hanzi_learning_config.dart';
import '../services/openai_service.dart';

/// 汉字学习服务
/// 负责字库管理、抽字逻辑、AI内容生成
class HanziLearningService extends GetxService {
  late Box _configBox;
  final OpenAIService _openAIService = Get.find<OpenAIService>();

  /// 当前配置（可观察）
  final Rx<HanziLearningConfig?> config = Rx<HanziLearningConfig?>(null);

  /// 是否正在生成
  final RxBool isGenerating = false.obs;

  /// 当前生成的文本
  final RxString generatedText = ''.obs;

  /// 当前混合字列表（已知字 + 新字的混合）
  final RxList<String> currentKnownChars = <String>[].obs;

  /// 当前新字列表
  final RxList<String> currentNewChars = <String>[].obs;

  /// 初始化服务
  Future<HanziLearningService> init() async {
    // 注册适配器
    if (!Hive.isAdapterRegistered(40)) {
      Hive.registerAdapter(HanziLearningConfigAdapter());
      debugPrint('✅ HanziLearningConfigAdapter 已注册 (typeId: 40)');
    }

    _configBox = await Hive.openBox('hanzi_learning_config');

    // 加载 JSON 字库数据
    await HanziData.loadFromAsset();
    debugPrint('📚 汉字字库已加载: ${HanziData.allEntries.length} 个字, '
        '${HanziData.allBookLevels.length} 册');

    // 加载配置
    _loadConfig();
    return this;
  }

  /// 加载配置
  void _loadConfig() {
    final configMap = _configBox.get('config');
    if (configMap != null) {
      config.value =
          HanziLearningConfig.fromJson(Map<String, dynamic>.from(configMap));
          
      // 强制升级旧版的 Prompt（如果没有阶段特征占位符，意味着是老数据）
      if (!config.value!.aiPrompt.contains('{stageHint}')) {
        config.value!.aiPrompt = HanziLearningConfig.defaultPrompt;
        saveConfig();
        debugPrint('🔄 检测到旧版 Prompt，已自动升级为带安全警告和阶段特征的新模板');
      }
    } else {
      config.value = HanziLearningConfig(id: 'default');
    }
    debugPrint('📚 汉字学习配置已加载: 最高解锁册=${config.value?.unlockedMaxLevel}, '
        '已知字数=${config.value?.knownHanziList.length}');
  }

  /// 保存配置
  Future<void> saveConfig() async {
    if (config.value == null) return;
    await _configBox.put('config', config.value!.toJson());
    debugPrint('💾 汉字学习配置已保存');
  }

  /// 设置最高解锁册别
  Future<void> setUnlockedMaxLevel(int level) async {
    if (config.value == null) return;
    config.value!.unlockedMaxLevel = level;
    config.update((val) {});
    await saveConfig();
  }

  /// 获取当前解锁范围内的全部汉字条目
  List<HanziEntry> getUnlockedEntries() {
    final maxLevel = config.value?.unlockedMaxLevel ?? 1;
    return HanziData.getEntriesUpToLevel(maxLevel);
  }

  /// 获取当前解锁范围内的全部汉字（纯字符）
  List<String> getUnlockedChars() {
    return getUnlockedEntries().map((e) => e.character).toList();
  }

  /// 更新专属字库（已认识的汉字列表）
  Future<void> updateKnownHanziList(List<String> hanziList) async {
    if (config.value == null) return;
    config.value!.knownHanziList = List<String>.from(hanziList);
    config.update((val) {});
    await saveConfig();
    debugPrint('📝 专属字库已更新: ${hanziList.length} 个字');
  }

  /// 标记首次启动完成
  Future<void> markFirstLaunchDone() async {
    if (config.value == null) return;
    config.value!.isFirstLaunch = false;
    config.update((val) {});
    await saveConfig();
  }

  /// 抽取汉字（核心逻辑）
  /// 从专属字库中随机抽取已知字 + 从解锁字库中未掌握的字抽取新字
  Map<String, List<String>> sampleHanzi() {
    final cfg = config.value;
    if (cfg == null) return {'known': [], 'new': []};

    final knownList = cfg.knownHanziList;
    final unlockedList = getUnlockedChars();
    final random = Random();

    // 已知字抽取
    final knownCount = min(cfg.knownHanziCount, knownList.length);
    final sampledKnown = List<String>.from(knownList)..shuffle(random);
    final selectedKnown = sampledKnown.take(knownCount).toList();

    // 新字抽取（从解锁字库中排除已知字）
    final unknownList =
        unlockedList.where((c) => !knownList.contains(c)).toList();
    final newCount = min(cfg.newHanziCount, unknownList.length);
    final sampledNew = List<String>.from(unknownList)..shuffle(random);
    final selectedNew = sampledNew.take(newCount).toList();

    // 更新当前状态
    currentKnownChars.assignAll(selectedKnown);
    currentNewChars.assignAll(selectedNew);

    debugPrint('🎲 抽字结果: 已知${selectedKnown.length}个, 新字${selectedNew.length}个');
    debugPrint('  已知字: $selectedKnown');
    debugPrint('  新  字: $selectedNew');

    return {
      'known': selectedKnown,
      'new': selectedNew,
    };
  }

  /// 调用AI生成趣味文本
  Future<String> generateContent() async {
    final cfg = config.value;
    if (cfg == null) throw Exception('未初始化配置');

    isGenerating.value = true;
    generatedText.value = '';

    try {
      // 抽取汉字
      final sampled = sampleHanzi();
      final knownChars = sampled['known']!;
      final newChars = sampled['new']!;

      if (knownChars.isEmpty && newChars.isEmpty) {
        throw Exception('字库为空，请先完成字库设置');
      }

      // 获取系统白名单字符
      final whitelistChars = HanziData.systemWhitelistChars;

      // 构建 Prompt（使用更新后的模板）
      String prompt = cfg.aiPrompt;
      prompt = prompt.replaceAll('{knownChars}', knownChars.join('、'));
      prompt = prompt.replaceAll('{newChars}', newChars.join('、'));
      prompt =
          prompt.replaceAll('{whitelistChars}', whitelistChars.join('、'));
      // 替换覆盖率占位符
      prompt = prompt.replaceAll(
          '{coverageRate}', (cfg.targetCoverageRate * 100).toInt().toString());
      // 替换阶段风格提示占位符
      prompt = prompt.replaceAll(
          '{stageHint}', HanziData.getStageHint(cfg.unlockedMaxLevel));

      // 获取AI配置
      final openAIConfigs = _openAIService.configs;
      if (openAIConfigs.isEmpty) {
        throw Exception('请先在设置中配置 AI 接口');
      }

      // 选择配置
      var aiConfig = openAIConfigs
          .firstWhereOrNull((c) => c.id == cfg.chatConfigId);
      aiConfig ??= _openAIService.currentConfig.value ?? openAIConfigs.first;

      // 选择模型
      String? model = cfg.chatModel.isNotEmpty ? cfg.chatModel : null;

      // 调用 AI
      final response = await _openAIService.chat(
        systemPrompt: '你是一位儿童文学创作专家，擅长为小朋友创作简单有趣、积极向上的小故事和句子。'
            '你的创作必须严格使用指定的汉字，确保文本中的汉字覆盖率达到要求。'
            '直接返回故事文本，不要添加任何解释说明。',
        userMessage: prompt,
        config: aiConfig,
        model: model,
      );

      generatedText.value = response.trim();
      debugPrint('✅ AI生成完成: ${generatedText.value}');

      // 自动保存为历史记录（最近一次）
      await _saveLastRecord(generatedText.value);

      return generatedText.value;
    } catch (e) {
      debugPrint('❌ AI生成失败: $e');
      rethrow;
    } finally {
      isGenerating.value = false;
    }
  }

  /// 计算生成文本的字库覆盖率
  double calculateCoverage(String text) {
    if (text.isEmpty) return 0.0;

    // 可用字 = 用户专属字库 + 系统白名单
    final allAvailableChars = <String>{
      ...currentKnownChars,
      ...currentNewChars,
      ...HanziData.systemWhitelistChars,
    };
    if (allAvailableChars.isEmpty) return 0.0;

    // 提取文本中的汉字
    final hanziRegex = RegExp(r'[\u4e00-\u9fff]');
    final textHanzi =
        hanziRegex.allMatches(text).map((m) => m.group(0)!).toList();

    if (textHanzi.isEmpty) return 0.0;

    // 计算覆盖率
    final coveredCount =
        textHanzi.where((c) => allAvailableChars.contains(c)).length;
    return coveredCount / textHanzi.length;
  }

  /// 判断一个字符是否为新字
  bool isNewChar(String char) {
    return currentNewChars.contains(char);
  }

  /// 判断一个字符是否为已知字
  bool isKnownChar(String char) {
    return currentKnownChars.contains(char);
  }

  /// 判断一个字符是否在系统白名单中
  bool isWhitelistChar(String char) {
    return HanziData.systemWhitelistChars.contains(char);
  }

  // ========== 历史记录（仅保留最近一次） ==========

  /// 保存最近一次生成的记录
  Future<void> _saveLastRecord(String text) async {
    try {
      await _configBox.put('last_record', {
        'text': text,
        'knownChars': currentKnownChars.toList(),
        'newChars': currentNewChars.toList(),
        'timestamp': DateTime.now().toIso8601String(),
      });
      debugPrint('💾 已保存最近一次学习记录');
    } catch (e) {
      debugPrint('保存历史记录失败: $e');
    }
  }

  /// 读取最近一次的记录（返回 null 表示无记录）
  Map<String, dynamic>? getLastRecord() {
    final raw = _configBox.get('last_record');
    if (raw == null) return null;
    return Map<String, dynamic>.from(raw as Map);
  }

  /// 从历史记录恢复状态（已知字列表、新字列表），返回文本
  String? loadLastRecord() {
    final record = getLastRecord();
    if (record == null) return null;

    final text = record['text'] as String? ?? '';
    if (text.isEmpty) return null;

    // 恢复当前字列表状态
    final known = (record['knownChars'] as List?)?.cast<String>() ?? [];
    final newC = (record['newChars'] as List?)?.cast<String>() ?? [];
    currentKnownChars.assignAll(known);
    currentNewChars.assignAll(newC);
    generatedText.value = text;

    debugPrint('📖 已恢复上次记录: ${text.length}字, 已知${known.length}个, 新字${newC.length}个');
    return text;
  }

  /// 更新AI配置
  Future<void> updateAIConfig({
    String? chatConfigId,
    String? chatModel,
    String? aiPrompt,
  }) async {
    if (config.value == null) return;
    if (chatConfigId != null) config.value!.chatConfigId = chatConfigId;
    if (chatModel != null) config.value!.chatModel = chatModel;
    if (aiPrompt != null) config.value!.aiPrompt = aiPrompt;
    config.update((val) {});
    await saveConfig();
  }

  /// 更新游戏设置
  Future<void> updateGameSettings({
    int? knownHanziCount,
    int? newHanziCount,
    double? targetCoverageRate,
  }) async {
    if (config.value == null) return;
    if (knownHanziCount != null) {
      config.value!.knownHanziCount = knownHanziCount;
    }
    if (newHanziCount != null) config.value!.newHanziCount = newHanziCount;
    if (targetCoverageRate != null) {
      config.value!.targetCoverageRate = targetCoverageRate;
    }
    config.update((val) {});
    await saveConfig();
  }

  /// 导出配置（用于备份）
  Map<String, dynamic>? exportConfig() {
    return config.value?.toJson();
  }

  /// 导入配置（用于恢复）
  Future<void> importConfig(Map<String, dynamic> data) async {
    config.value = HanziLearningConfig.fromJson(data);
    await saveConfig();
  }
}
