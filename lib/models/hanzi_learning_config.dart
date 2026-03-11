import 'package:hive/hive.dart';

part 'hanzi_learning_config.g.dart';

/// 汉字学习配置模型
/// typeId: 40，避免与现有模型冲突
@HiveType(typeId: 40)
class HanziLearningConfig extends HiveObject {
  /// 唯一标识
  @HiveField(0)
  String id;

  // ========== 字库设置 ==========

  /// 儿童年龄（保留兼容，默认5岁）
  @HiveField(1, defaultValue: 5)
  int childAge;

  /// 专属字库（已认识的汉字列表）
  @HiveField(2, defaultValue: [])
  List<String> knownHanziList;

  // ========== AI 配置 ==========

  /// 对话使用的 OpenAI 配置ID
  @HiveField(3, defaultValue: '')
  String chatConfigId;

  /// 对话模型
  @HiveField(4, defaultValue: '')
  String chatModel;

  /// AI 生成 Prompt 模板
  @HiveField(5)
  String aiPrompt;

  // ========== 游戏设置 ==========

  /// 每次抽取的已知字数量
  @HiveField(6, defaultValue: 10)
  int knownHanziCount;

  /// 每次加入的新字数量
  @HiveField(7, defaultValue: 2)
  int newHanziCount;

  /// 目标覆盖率（0.85-0.95）
  @HiveField(8, defaultValue: 0.85)
  double targetCoverageRate;

  /// 是否首次启动（需要完成设置）
  @HiveField(9, defaultValue: true)
  bool isFirstLaunch;

  /// 最高解锁册别（1-7，控制可用字库范围）
  @HiveField(10, defaultValue: 1)
  int unlockedMaxLevel;

  /// 默认 Prompt 模板（包含系统白名单占位符）
  static String get defaultPrompt => '''请你为一位小朋友写一段有趣的小故事或一组有趣的句子。

⚠️ 安全警告（最高优先级）：
- 你正在为3-8岁幼儿生成内容，必须绝对安全
- 严禁任何暴力、恐怖、悲伤、死亡、疾病相关内容
- 严禁任何歧视、偏见、负面情绪引导
- 严禁任何政治敏感、宗教争议内容
- 严禁任何不雅、低俗、危险行为描述
- 严禁任何情爱、成人话题（如爱情、情侣、约会等早熟题材）
- 内容必须积极向上、充满阳光和童趣

📝 字库覆盖率要求（严格执行）：
1. 你的故事中，所有用到的汉字必须有 {coverageRate}% 以上来自下方三个字库的合集
2. 超出字库范围的汉字（即不在下方三个列表中的字）总数不得超过 3 个
3. 每个"新字"都必须出现在故事中，且通过上下文能让孩子猜到含义

🎯 当前阶段风格指引：
{stageHint}

📖 内容格式要求：
1. 故事长度控制在 50-100 字
2. 每句话不超过 15 个字，句式简单
4. 故事设定和情节发展必须符合常识与逻辑，语句通顺连贯
5. 直接返回故事文本，不加标题、编号或任何解释

【用户专属字库】（已掌握的字）：{knownChars}
【新字】（必须出现在故事中）：{newChars}
【系统白名单字库】（常用功能词，可自由使用）：{whitelistChars}

请直接输出故事，不要有任何额外内容。''';

  HanziLearningConfig({
    required this.id,
    this.childAge = 5,
    this.knownHanziList = const [],
    this.chatConfigId = '',
    this.chatModel = '',
    String? aiPrompt,
    this.knownHanziCount = 10,
    this.newHanziCount = 2,
    this.targetCoverageRate = 0.85,
    this.isFirstLaunch = true,
    this.unlockedMaxLevel = 1,
  }) : aiPrompt = aiPrompt ?? defaultPrompt;

  /// 转换为 JSON
  Map<String, dynamic> toJson() => {
        'id': id,
        'childAge': childAge,
        'knownHanziList': knownHanziList,
        'chatConfigId': chatConfigId,
        'chatModel': chatModel,
        'aiPrompt': aiPrompt,
        'knownHanziCount': knownHanziCount,
        'newHanziCount': newHanziCount,
        'targetCoverageRate': targetCoverageRate,
        'isFirstLaunch': isFirstLaunch,
        'unlockedMaxLevel': unlockedMaxLevel,
      };

  /// 从 JSON 创建
  factory HanziLearningConfig.fromJson(Map<String, dynamic> json) =>
      HanziLearningConfig(
        id: json['id'] as String? ?? 'default',
        childAge: json['childAge'] as int? ?? 5,
        knownHanziList: (json['knownHanziList'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        chatConfigId: json['chatConfigId'] as String? ?? '',
        chatModel: json['chatModel'] as String? ?? '',
        aiPrompt: json['aiPrompt'] as String?,
        knownHanziCount: json['knownHanziCount'] as int? ?? 10,
        newHanziCount: json['newHanziCount'] as int? ?? 2,
        targetCoverageRate:
            (json['targetCoverageRate'] as num?)?.toDouble() ?? 0.85,
        isFirstLaunch: json['isFirstLaunch'] as bool? ?? true,
        unlockedMaxLevel: json['unlockedMaxLevel'] as int? ?? 1,
      );
}
