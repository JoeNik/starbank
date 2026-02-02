import 'package:hive/hive.dart';

part 'quiz_config.g.dart';

/// 新年问答配置模型
/// typeId 改为 30 以避免与 MusicTrack (20) 冲突
@HiveType(typeId: 30)
class QuizConfig extends HiveObject {
  /// 生图 AI 配置 ID
  @HiveField(0)
  String? imageGenConfigId;

  /// 问答 AI 配置 ID
  @HiveField(1)
  String? chatConfigId;

  /// 生图模型
  @HiveField(7)
  String? imageGenModel;

  /// 问答模型
  @HiveField(8)
  String? chatModel;

  /// 生图提示词模板
  @HiveField(2,
      defaultValue:
          '请为以下新年知识点生成一张可爱的儿童插画:\n{knowledge}\n\n要求:\n1. 儿童插画风格,色彩明亮温暖,画面可爱有趣\n2. 符合中国传统新年文化,展现节日喜庆氛围\n3. 适合3-8岁儿童观看,内容健康积极\n4. 画面简洁清晰,主题突出,避免复杂细节\n5. 使用卡通风格,圆润可爱的造型\n6. 严格禁止任何暴力、恐怖、成人或不适合儿童的内容')
  String imageGenPrompt;

  /// 问答提示词模板
  @HiveField(3,
      defaultValue:
          '你是一个儿童教育专家,请为以下新年知识点生成一个适合儿童的问答题:\n{knowledge}\n\n要求:\n1. 问题简单易懂,适合3-8岁儿童\n2. 提供4个选项,其中1个正确\n3. 包含详细的知识点解释\n4. 语言生动有趣')
  String chatPrompt;

  /// 是否启用 AI 生成图片
  @HiveField(4, defaultValue: false)
  bool enableImageGen;

  /// 是否启用 AI 生成题目
  @HiveField(5, defaultValue: false)
  bool enableQuestionGen;

  /// 每日限玩次数 (0表示不限制)
  @HiveField(6, defaultValue: 0)
  int dailyPlayLimit;

  QuizConfig({
    this.imageGenConfigId,
    this.chatConfigId,
    this.imageGenModel,
    this.chatModel,
    this.imageGenPrompt =
        '请为以下新年知识点生成一张可爱的儿童插画:\n{knowledge}\n\n要求:\n1. 儿童插画风格,色彩明亮温暖,画面可爱有趣\n2. 符合中国传统新年文化,展现节日喜庆氛围\n3. 适合3-8岁儿童观看,内容健康积极\n4. 画面简洁清晰,主题突出,避免复杂细节\n5. 使用卡通风格,圆润可爱的造型\n6. 严格禁止任何暴力、恐怖、成人或不适合儿童的内容',
    this.chatPrompt =
        '你是一个儿童教育专家,请为以下新年知识点生成一个适合儿童的问答题:\n{knowledge}\n\n要求:\n1. 问题简单易懂,适合3-8岁儿童\n2. 提供4个选项,其中1个正确\n3. 包含详细的知识点解释\n4. 语言生动有趣',
    this.enableImageGen = false,
    this.enableQuestionGen = false,
    this.dailyPlayLimit = 0,
  });

  /// 转换为 JSON
  Map<String, dynamic> toJson() => {
        'imageGenConfigId': imageGenConfigId,
        'chatConfigId': chatConfigId,
        'imageGenModel': imageGenModel,
        'chatModel': chatModel,
        'imageGenPrompt': imageGenPrompt,
        'chatPrompt': chatPrompt,
        'enableImageGen': enableImageGen,
        'enableQuestionGen': enableQuestionGen,
        'dailyPlayLimit': dailyPlayLimit,
      };

  /// 从 JSON 创建
  factory QuizConfig.fromJson(Map<String, dynamic> json) => QuizConfig(
        imageGenConfigId: json['imageGenConfigId'] as String?,
        chatConfigId: json['chatConfigId'] as String?,
        imageGenModel: json['imageGenModel'] as String?,
        chatModel: json['chatModel'] as String?,
        imageGenPrompt: json['imageGenPrompt'] as String? ??
            '请为以下新年知识点生成一张可爱的儿童插画:\n{knowledge}\n\n要求:\n1. 儿童插画风格,色彩明亮温暖,画面可爱有趣\n2. 符合中国传统新年文化,展现节日喜庆氛围\n3. 适合3-8岁儿童观看,内容健康积极\n4. 画面简洁清晰,主题突出,避免复杂细节\n5. 使用卡通风格,圆润可爱的造型\n6. 严格禁止任何暴力、恐怖、成人或不适合儿童的内容',
        chatPrompt: json['chatPrompt'] as String? ??
            '你是一个儿童教育专家,请为以下新年知识点生成一个适合儿童的问答题:\n{knowledge}\n\n要求:\n1. 问题简单易懂,适合3-8岁儿童\n2. 提供4个选项,其中1个正确\n3. 包含详细的知识点解释\n4. 语言生动有趣',
        enableImageGen: json['enableImageGen'] as bool? ?? false,
        enableQuestionGen: json['enableQuestionGen'] as bool? ?? false,
        dailyPlayLimit: json['dailyPlayLimit'] as int? ?? 0,
      );
}
