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

  /// 默认 Prompt 模板（优化版：放宽约束，强调自然通顺）
  static String get defaultPrompt => '''【系统角色】
你是一位拥有20年经验的顶级儿童绘本作家。请为 {childAge} 岁的儿童创作一段100~150字的小故事。

【可用字库】（优先使用，非强制）
基础库：{whitelistChars}
孩子认识的字：{knownChars}

【必须包含的新字】
以下新字必须自然地出现在故事中：{newChars}

【核心原则】
1. 语句自然流畅是第一优先级！宁可用少量超纲字补充语义，也绝不能为了凑字库而写出生硬、语义不通的句子。
2. 如果不得不使用超纲字，尽量选择常见的高频字。
3. 故事必须有完整的起因→经过→结尾。
4. 语言必须符合 {childAge} 岁儿童的认知水平，口语化，像妈妈在讲故事。
5. 故事需要包含正向的教育意义（如分享、勇敢、懂礼貌等）。
6. 必须绝对安全，严禁暴力、恐怖、悲伤、敏感题材。

【本册风格参考】
{stageHint}

⚠️ 直接返回故事文本，不要加任何标题、解释或标注。''';

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
