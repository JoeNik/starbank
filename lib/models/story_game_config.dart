import 'package:hive/hive.dart';

part 'story_game_config.g.dart';

/// 故事游戏配置
@HiveType(typeId: 14)
class StoryGameConfig extends HiveObject {
  /// 唯一标识
  @HiveField(0)
  String id;

  // ========== 图像生成配置 ==========

  /// 图像生成使用的 OpenAI 配置ID
  @HiveField(1, defaultValue: '')
  String imageGenerationConfigId;

  /// 图像生成模型（如 dall-e-3）
  @HiveField(2, defaultValue: 'dall-e-3')
  String imageGenerationModel;

  /// 图像生成 Prompt 模板
  @HiveField(3)
  String imageGenerationPrompt;

  // ========== 图像分析配置 ==========

  /// 图像分析使用的 OpenAI 配置ID（需要支持 Vision）
  @HiveField(4, defaultValue: '')
  String visionConfigId;

  /// 图像分析模型（如 gpt-4o, claude-3-sonnet）
  @HiveField(5, defaultValue: 'gpt-4o')
  String visionModel;

  /// 图像分析 Prompt（分析图片并引导开始讲故事）
  @HiveField(6)
  String visionAnalysisPrompt;

  // ========== 对话引导配置 ==========

  /// 对话使用的 OpenAI 配置ID
  @HiveField(7, defaultValue: '')
  String chatConfigId;

  /// 对话模型
  @HiveField(8, defaultValue: '')
  String chatModel;

  /// 对话系统 Prompt（引导宝宝扩展故事）
  @HiveField(9)
  String chatSystemPrompt;

  // ========== 评价配置 ==========

  /// 故事评价 Prompt
  @HiveField(10)
  String evaluationPrompt;

  // ========== 游戏设置 ==========

  /// 最大对话轮数
  @HiveField(11, defaultValue: 5)
  int maxRounds;

  /// 每日游戏次数限制
  @HiveField(12, defaultValue: 2)
  int dailyLimit;

  /// 完成故事获得的基础星星数
  @HiveField(13, defaultValue: 3)
  int baseStars;

  /// 是否启用星星奖励
  @HiveField(14, defaultValue: true)
  bool enableStarReward;

  /// 备用图片源URL列表（当图像生成不可用时使用）
  /// 支持格式：
  /// - 直接图片URL列表
  /// - 或者一个返回图片列表JSON的API地址
  @HiveField(15, defaultValue: const [])
  List<String> fallbackImageUrls;

  /// 远程图片API地址（可选，返回JSON格式的图片列表）
  @HiveField(16, defaultValue: '')
  String remoteImageApiUrl;

  // ========== TTS 语音播报配置 ==========

  /// TTS 语速（0.0-1.0，默认0.5）
  @HiveField(17, defaultValue: 0.5)
  double ttsRate;

  /// TTS 音量（0.0-1.0，默认1.0）
  @HiveField(18, defaultValue: 1.0)
  double ttsVolume;

  /// TTS 音调（0.5-2.0，默认1.0）
  @HiveField(19, defaultValue: 1.0)
  double ttsPitch;

  StoryGameConfig({
    required this.id,
    this.imageGenerationConfigId = '',
    this.imageGenerationModel = 'dall-e-3',
    this.imageGenerationPrompt =
        'Generate a cute, high-quality children\'s book illustration. Please RANDOMLY select one specific theme from the following options to create a unique scene: 1. Magical Forest adventure with animals 2. Space exploration with cute aliens 3. Underwater mermaid party 4. Dinosaur playground 5. Animal music festival 6. Candy kingdom 7. Flying car city in clouds 8. Tiny insect world. The image must feature adorable characters (animals or kids) interacting funnily. Style: 3D Pixar style or high-quality digital art. Vibrant colors, soft warm lighting, whimsical atmosphere, 8k resolution. Composition should be clear and focused, perfect for a 3-8 year old child to describe what is happening.',
    this.visionConfigId = '',
    this.visionModel = 'gpt-4o',
    this.visionAnalysisPrompt = '''你是一位温柔有趣的故事引导员，正在和3-8岁的小朋友玩"看图讲故事"游戏。

请仔细观察这张图片，然后用亲切、有趣的语气：
1. 简单描述图片中你看到的场景和角色
2. 用一两个问题引导小朋友开始讲故事

要求：
- 语言简单易懂，适合儿童理解
- 语气亲切温暖，像在和小朋友聊天
- 问题要开放性，激发想象力
- 控制在100字以内''',
    this.chatConfigId = '',
    this.chatModel = '',
    this.chatSystemPrompt = '''你是一位温柔有趣的故事引导员，正在和小朋友玩"看图讲故事"游戏。

你的任务是：
1. 认真倾听小朋友的故事内容
2. 用简短的话语表示肯定和鼓励
3. 用一个简单的问题引导故事继续发展

对话原则：
- 始终保持亲切、有趣的语气
- 用简单易懂的词汇
- 每次回复控制在50字以内
- 问题要有趣，能激发想象力
- 不要纠正孩子的"错误"，鼓励创意''',
    this.evaluationPrompt = '''你是一位温柔的故事评价员，刚刚听完小朋友的故事。

请根据以下对话记录，给出评价：

1. 用2-3句话总结故事内容
2. 真诚地夸奖小朋友的创意和表达（具体指出亮点）
3. 给出评分（0-100分），评分标准：
   - 故事完整性（有开头、发展）
   - 想象力和创意
   - 语言表达
4. 用一句鼓励的话结束

要求：
- 语气温暖、真诚
- 以鼓励为主，不批评
- 评分要合理，一般在70-95分之间
- 控制在150字以内

最后一行请单独输出：【得分：XX分】''',
    this.maxRounds = 5,
    this.dailyLimit = 2,
    this.baseStars = 3,
    this.enableStarReward = true,
    this.fallbackImageUrls = const [],
    this.remoteImageApiUrl = '',
    this.ttsRate = 0.5,
    this.ttsVolume = 1.0,
    this.ttsPitch = 1.0,
    this.enableImageGeneration = false,
  });

  /// 是否启用 AI 生成图片
  @HiveField(20, defaultValue: false)
  bool enableImageGeneration;

  /// 转换为 JSON
  Map<String, dynamic> toJson() => {
        'id': id,
        'imageGenerationConfigId': imageGenerationConfigId,
        'imageGenerationModel': imageGenerationModel,
        'imageGenerationPrompt': imageGenerationPrompt,
        'enableImageGeneration': enableImageGeneration,
        'visionConfigId': visionConfigId,
        'visionModel': visionModel,
        'visionAnalysisPrompt': visionAnalysisPrompt,
        'chatConfigId': chatConfigId,
        'chatModel': chatModel,
        'chatSystemPrompt': chatSystemPrompt,
        'evaluationPrompt': evaluationPrompt,
        'maxRounds': maxRounds,
        'dailyLimit': dailyLimit,
        'baseStars': baseStars,
        'enableStarReward': enableStarReward,
        'fallbackImageUrls': fallbackImageUrls,
        'remoteImageApiUrl': remoteImageApiUrl,
        'ttsRate': ttsRate,
        'ttsVolume': ttsVolume,
        'ttsPitch': ttsPitch,
      };

  /// 从 JSON 创建
  factory StoryGameConfig.fromJson(Map<String, dynamic> json) =>
      StoryGameConfig(
        id: json['id'] as String? ?? 'default',
        imageGenerationConfigId:
            json['imageGenerationConfigId'] as String? ?? '',
        imageGenerationModel:
            json['imageGenerationModel'] as String? ?? 'dall-e-3',
        imageGenerationPrompt: json['imageGenerationPrompt'] as String? ?? '',
        visionConfigId: json['visionConfigId'] as String? ?? '',
        visionModel: json['visionModel'] as String? ?? 'gpt-4o',
        visionAnalysisPrompt: json['visionAnalysisPrompt'] as String? ?? '',
        chatConfigId: json['chatConfigId'] as String? ?? '',
        chatModel: json['chatModel'] as String? ?? '',
        chatSystemPrompt: json['chatSystemPrompt'] as String? ?? '',
        evaluationPrompt: json['evaluationPrompt'] as String? ?? '',
        maxRounds: json['maxRounds'] as int? ?? 5,
        dailyLimit: json['dailyLimit'] as int? ?? 2,
        baseStars: json['baseStars'] as int? ?? 3,
        enableStarReward: json['enableStarReward'] as bool? ?? true,
        fallbackImageUrls: (json['fallbackImageUrls'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        remoteImageApiUrl: json['remoteImageApiUrl'] as String? ?? '',
        ttsRate: (json['ttsRate'] as num?)?.toDouble() ?? 0.5,
        ttsVolume: (json['ttsVolume'] as num?)?.toDouble() ?? 1.0,
        ttsPitch: (json['ttsPitch'] as num?)?.toDouble() ?? 1.0,
        enableImageGeneration: json['enableImageGeneration'] as bool? ?? false,
      );
}
