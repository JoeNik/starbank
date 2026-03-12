import 'dart:convert';
import 'package:flutter/services.dart';

/// 单个汉字条目（包含字符、拼音、册别等信息）
class HanziEntry {
  /// 唯一标识，如 "L1_001"
  final String id;

  /// 汉字字符
  final String character;

  /// 拼音（带声调）
  final String pinyin;

  /// 所属册别（1-7）
  final int bookLevel;

  /// 阶段名称
  final String stageName;

  /// 推荐年龄
  final String recommendedAge;

  /// 是否默认解锁
  final bool isUnlockedDefault;

  const HanziEntry({
    required this.id,
    required this.character,
    required this.pinyin,
    required this.bookLevel,
    required this.stageName,
    required this.recommendedAge,
    this.isUnlockedDefault = false,
  });

  /// 从 JSON 解析
  factory HanziEntry.fromJson(Map<String, dynamic> json) {
    return HanziEntry(
      id: json['id'] as String,
      character: json['character'] as String,
      pinyin: json['pinyin'] as String,
      bookLevel: json['book_level'] as int,
      stageName: json['stage_name'] as String,
      recommendedAge: json['recommended_age'] as String,
      isUnlockedDefault: json['is_unlocked_default'] as bool? ?? false,
    );
  }
}

/// 汉字分级数据管理器
/// 从 JSON 资源文件加载字库数据，按册（book_level）组织
class HanziData {
  /// 所有汉字条目
  static List<HanziEntry> _allEntries = [];

  /// 按册分组的汉字条目缓存
  static Map<int, List<HanziEntry>> _levelCache = {};

  /// 拼音映射缓存（字符 -> 拼音）
  static Map<String, String> _pinyinCache = {};

  /// 是否已加载
  static bool _isLoaded = false;

  /// 系统白名单兜底字库
  /// 包含超高频连词、代词、动词、助词等，确保即使初学者只解锁了第一册（多为名词），
  /// AI 也能利用这些基础功能词造出完整通顺的句子
  static const List<Map<String, String>> systemWhitelistEntries = [
    // === 代词/指代 ===
    {'char': '我', 'pinyin': 'wǒ'}, {'char': '你', 'pinyin': 'nǐ'},
    {'char': '他', 'pinyin': 'tā'}, {'char': '她', 'pinyin': 'tā'},
    {'char': '它', 'pinyin': 'tā'}, {'char': '这', 'pinyin': 'zhè'},
    {'char': '那', 'pinyin': 'nà'}, {'char': '哪', 'pinyin': 'nǎ'},
    {'char': '谁', 'pinyin': 'shéi'}, {'char': '些', 'pinyin': 'xiē'},
    {'char': '什', 'pinyin': 'shén'}, {'char': '么', 'pinyin': 'me'},
    {'char': '自', 'pinyin': 'zì'}, {'char': '己', 'pinyin': 'jǐ'},
    
    // === 基础动词 ===
    {'char': '是', 'pinyin': 'shì'}, {'char': '有', 'pinyin': 'yǒu'},
    {'char': '在', 'pinyin': 'zài'}, {'char': '来', 'pinyin': 'lái'},
    {'char': '去', 'pinyin': 'qù'}, {'char': '看', 'pinyin': 'kàn'},
    {'char': '吃', 'pinyin': 'chī'}, {'char': '喝', 'pinyin': 'hē'},
    {'char': '跑', 'pinyin': 'pǎo'}, {'char': '走', 'pinyin': 'zǒu'},
    {'char': '飞', 'pinyin': 'fēi'}, {'char': '说', 'pinyin': 'shuō'},
    {'char': '做', 'pinyin': 'zuò'}, {'char': '玩', 'pinyin': 'wán'},
    {'char': '想', 'pinyin': 'xiǎng'}, {'char': '要', 'pinyin': 'yào'},
    {'char': '给', 'pinyin': 'gěi'}, {'char': '爱', 'pinyin': 'ài'},
    {'char': '会', 'pinyin': 'huì'}, {'char': '能', 'pinyin': 'néng'},
    {'char': '叫', 'pinyin': 'jiào'}, {'char': '让', 'pinyin': 'ràng'},
    {'char': '帮', 'pinyin': 'bāng'}, {'char': '听', 'pinyin': 'tīng'},
    {'char': '找', 'pinyin': 'zhǎo'}, {'char': '拿', 'pinyin': 'ná'},
    {'char': '见', 'pinyin': 'jiàn'}, {'char': '笑', 'pinyin': 'xiào'},
    {'char': '哭', 'pinyin': 'kū'}, {'char': '睡', 'pinyin': 'shuì'},
    {'char': '起', 'pinyin': 'qǐ'}, {'char': '开', 'pinyin': 'kāi'},
    {'char': '关', 'pinyin': 'guān'},

    // === 连词/助词/副词 ===
    {'char': '和', 'pinyin': 'hé'}, {'char': '的', 'pinyin': 'de'},
    {'char': '了', 'pinyin': 'le'}, {'char': '不', 'pinyin': 'bù'},
    {'char': '也', 'pinyin': 'yě'}, {'char': '很', 'pinyin': 'hěn'},
    {'char': '都', 'pinyin': 'dōu'}, {'char': '把', 'pinyin': 'bǎ'},
    {'char': '着', 'pinyin': 'zhe'}, {'char': '过', 'pinyin': 'guò'},
    {'char': '就', 'pinyin': 'jiù'}, {'char': '才', 'pinyin': 'cái'},
    {'char': '又', 'pinyin': 'yòu'}, {'char': '更', 'pinyin': 'gèng'},
    {'char': '最', 'pinyin': 'zuì'}, {'char': '还', 'pinyin': 'hái'},
    {'char': '真', 'pinyin': 'zhēn'}, {'char': '太', 'pinyin': 'tài'},
    {'char': '得', 'pinyin': 'de'}, {'char': '地', 'pinyin': 'de'},
    {'char': '但', 'pinyin': 'dàn'}, {'char': '跟', 'pinyin': 'gēn'},
    {'char': '到', 'pinyin': 'dào'}, {'char': '从', 'pinyin': 'cóng'},

    // === 语气词 ===
    {'char': '呢', 'pinyin': 'ne'}, {'char': '吗', 'pinyin': 'ma'},
    {'char': '吧', 'pinyin': 'ba'}, {'char': '啊', 'pinyin': 'a'},
    {'char': '呀', 'pinyin': 'ya'}, {'char': '哦', 'pinyin': 'ò'},

    // === 基础形容词 ===
    {'char': '好', 'pinyin': 'hǎo'}, {'char': '多', 'pinyin': 'duō'},
    {'char': '少', 'pinyin': 'shǎo'}, {'char': '大', 'pinyin': 'dà'},
    {'char': '小', 'pinyin': 'xiǎo'}, {'char': '高', 'pinyin': 'gāo'},
    {'char': '长', 'pinyin': 'cháng'}, {'char': '快', 'pinyin': 'kuài'},
    {'char': '慢', 'pinyin': 'màn'}, {'char': '新', 'pinyin': 'xīn'},
    {'char': '冷', 'pinyin': 'lěng'}, {'char': '热', 'pinyin': 'rè'},
    {'char': '远', 'pinyin': 'yuǎn'}, {'char': '近', 'pinyin': 'jìn'},

    // === 基础名词/方位/量词 ===
    {'char': '个', 'pinyin': 'gè'}, {'char': '只', 'pinyin': 'zhī'},
    {'char': '条', 'pinyin': 'tiáo'}, {'char': '里', 'pinyin': 'lǐ'},
    {'char': '上', 'pinyin': 'shàng'}, {'char': '下', 'pinyin': 'xià'},
    {'char': '中', 'pinyin': 'zhōng'}, {'char': '外', 'pinyin': 'wài'},
    {'char': '前', 'pinyin': 'qián'}, {'char': '后', 'pinyin': 'hòu'},
    {'char': '左', 'pinyin': 'zuǒ'}, {'char': '右', 'pinyin': 'yòu'},
    {'char': '边', 'pinyin': 'biān'}, {'char': '天', 'pinyin': 'tiān'},
    {'char': '人', 'pinyin': 'rén'},

    // === 数字 ===
    {'char': '一', 'pinyin': 'yī'}, {'char': '二', 'pinyin': 'èr'},
    {'char': '三', 'pinyin': 'sān'}, {'char': '四', 'pinyin': 'sì'},
    {'char': '五', 'pinyin': 'wǔ'}, {'char': '六', 'pinyin': 'liù'},
    {'char': '七', 'pinyin': 'qī'}, {'char': '八', 'pinyin': 'bā'},
    {'char': '九', 'pinyin': 'jiǔ'}, {'char': '十', 'pinyin': 'shí'},
  ];

  /// 获取系统白名单的纯字符列表
  static List<String> get systemWhitelistChars =>
      systemWhitelistEntries.map((e) => e['char']!).toList();

  /// 获取系统白名单的拼音映射
  static Map<String, String> get systemWhitelistPinyinMap =>
      {for (var e in systemWhitelistEntries) e['char']!: e['pinyin']!};

  /// 初始化：从 JSON 资源文件加载字库
  static Future<void> loadFromAsset() async {
    if (_isLoaded) return;

    final jsonStr =
        await rootBundle.loadString('assets/data/kids_chinese_chars_bank.json');
    final List<dynamic> jsonList = json.decode(jsonStr);

    _allEntries = jsonList.map((e) => HanziEntry.fromJson(e)).toList();

    // 构建按册分组缓存
    _levelCache.clear();
    for (final entry in _allEntries) {
      _levelCache.putIfAbsent(entry.bookLevel, () => []).add(entry);
    }

    // 构建拼音映射缓存
    _pinyinCache.clear();
    for (final entry in _allEntries) {
      _pinyinCache[entry.character] = entry.pinyin;
    }
    // 把白名单里的也加入拼音缓存
    for (final e in systemWhitelistEntries) {
      _pinyinCache.putIfAbsent(e['char']!, () => e['pinyin']!);
    }

    _isLoaded = true;
  }

  /// 获取所有册别编号（已排序）
  static List<int> get allBookLevels {
    final levels = _levelCache.keys.toList()..sort();
    return levels;
  }

  /// 获取指定册别的汉字条目
  static List<HanziEntry> getEntriesByLevel(int level) {
    return _levelCache[level] ?? [];
  }

  /// 获取指定册别到某一册的累计汉字条目（包含所有低于等于该册的字）
  static List<HanziEntry> getEntriesUpToLevel(int level) {
    final result = <HanziEntry>[];
    for (int l = 1; l <= level; l++) {
      result.addAll(_levelCache[l] ?? []);
    }
    return result;
  }

  /// 获取指定册别的纯字符列表
  static List<String> getCharsByLevel(int level) {
    return getEntriesByLevel(level).map((e) => e.character).toList();
  }

  /// 获取累计到某一册的纯字符列表
  static List<String> getCharsUpToLevel(int level) {
    return getEntriesUpToLevel(level).map((e) => e.character).toList();
  }

  /// 获取默认解锁的字符列表（is_unlocked_default == true）
  static List<String> getDefaultUnlockedChars() {
    return _allEntries
        .where((e) => e.isUnlockedDefault)
        .map((e) => e.character)
        .toList();
  }

  /// 查询单个汉字的拼音
  static String? getPinyin(String character) {
    return _pinyinCache[character];
  }

  /// 查询单个汉字的完整条目信息
  static HanziEntry? getEntry(String character) {
    try {
      return _allEntries.firstWhere((e) => e.character == character);
    } catch (_) {
      return null;
    }
  }

  /// 获取册别描述信息
  static String getLevelDescription(int level) {
    final entries = getEntriesByLevel(level);
    if (entries.isEmpty) return '第$level册';
    final first = entries.first;
    return '第$level册 · ${first.stageName}（${first.recommendedAge}）';
  }

  /// 获取册别的简短名称
  static String getLevelShortName(int level) {
    final entries = getEntriesByLevel(level);
    if (entries.isEmpty) return '第$level册';
    return '第$level册 · ${entries.first.stageName}';
  }

  /// 每册的 AI 造句阶段提示
  /// 根据各册字库特征，给 AI 造句时提供适合该阶段的风格和结构指引
  static const Map<int, String> stagePromptHints = {
    1: '【第1册·启蒙期】字库以极高频名词、数字、自然事物为主。'
        '请用这些名词作为句子主语，造极其简单的短句（主语+谓语），'
        '例如"大山有水"、"月亮亮了"。每句不超过8个字。',
    2: '【第2册·探索期】字库新增了常用动词、动物、方位词。'
        '请用动词作为句子核心，让动物和人物"动起来"，'
        '例如"小鸟飞上天"、"我在花园里跑"。每句不超过10个字。',
    3: '【第3册·社交期】字库新增了生活物品和社交用语。'
        '请生成贴近日常生活的小故事，包含打招呼、分享、感谢等情节，'
        '例如"谢谢你给我一个苹果"。可以出现简单对话。',
    4: '【第4册·认知期】字库新增了情绪词和复杂动作。'
        '请让故事有简单的情绪变化（先开心后惊讶、先害怕后勇敢），'
        '让情节有小小的起伏和转折。',
    5: '【第5册·进阶期】字库新增了形容词、色彩词和科学词汇。'
        '请在故事中加入丰富的描写细节（颜色、大小、形状），'
        '让画面感更强，例如"蓝蓝的天上飘着白白的云"。',
    6: '【第6册·衔接期】字库达到幼小衔接水平。'
        '可以写稍长的复合句和简短的童话故事，包含因果关系和时间顺序，'
        '例如"因为下雨了，小兔子躲在大树下"。',
    7: '【第7册·学霸期】字库包含丰富的情感词汇和高频字。'
        '请写一段有情感起伏、包含角色对话的完整小童话。'
        '可以有"开头-冲突-解决"的简单三段式结构。',
  };

  /// 获取指定册别的 AI 造句阶段提示
  /// 如果解锁了多册，取最高册别的提示
  static String getStageHint(int maxLevel) {
    // 取解锁的最高册别提示
    final clampedLevel = maxLevel.clamp(1, 7);
    return stagePromptHints[clampedLevel] ?? stagePromptHints[1]!;
  }

  /// 获取所有汉字条目
  static List<HanziEntry> get allEntries => _allEntries;
}
