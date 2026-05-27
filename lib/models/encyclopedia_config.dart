import 'package:hive/hive.dart';

part 'encyclopedia_config.g.dart';

const String kDefaultEncyclopediaPromptTemplate = '''
你是一位严谨的儿童科学老师。请基于题目内容，输出 JSON，且仅输出 JSON，不要输出多余文本。

硬性要求：
1. 不能修改题目标准答案，不能自创与标准答案冲突的结论。
2. 表达面向 6-12 岁儿童，简单、准确、易懂。
3. 每段 1-2 句，总字数约 120-180 字。
4. example 必须紧扣本题具体知识点，给出孩子能安全观察或理解的生活场景；禁止使用“多观察类似现象”“慢慢理解”这类空泛句。
5. 输出必须包含以下 3 个字段：
   - short_answer: 一句话答案
   - why: 为什么是这个答案
   - example: 生活中的小例子

题目信息：
问题：{question}
选项：{options}
标准答案：{answer}
内置解释：{fallback}

请返回：
{
  "short_answer": "...",
  "why": "...",
  "example": "..."
}
''';

const String kDefaultEncyclopediaQuestionGenPromptTemplate = '''
你是一位严谨的儿童百科题库编辑。请根据用户给定的类目，生成适合 6-12 岁儿童的一问一答选择题。

硬性要求：
1. 必须输出 JSON 数组，且仅输出 JSON，不要解释。
2. 每题只有 2 个选项，其中 1 个正确。
3. 正确答案位置要随机分布，不要总是第一个。
4. 内容必须科学、准确、无争议，适合儿童。
5. 题目语言简短清楚，解释简单易懂。
6. explanation 必须写具体原因，不能使用“多观察类似现象”这类空泛句。
7. id 使用英文小写、数字和下划线，必须尽量唯一。

生成数量：{count}
类目：{category}

返回格式：
[
  {
    "id": "life_science_001",
    "question": "问题文本",
    "emoji": "🌍",
    "options": ["选项1", "选项2"],
    "correctIndex": 0,
    "answer": "正确答案文本",
    "explanation": "内置解释",
    "category": "{category}"
  }
]
''';

/// 生活科学百科配置
@HiveType(typeId: 44)
class EncyclopediaConfig extends HiveObject {
  @HiveField(0)
  String? chatConfigId;

  @HiveField(1)
  String? chatModel;

  /// AI 解析提示词模板
  @HiveField(2, defaultValue: kDefaultEncyclopediaPromptTemplate)
  String promptTemplate;

  /// 缓存过期天数（默认 30）
  @HiveField(3, defaultValue: 30)
  int cacheExpiryDays;

  /// 是否启用自动过期
  @HiveField(4, defaultValue: true)
  bool enableAutoRefresh;

  /// URL 同步地址（公开 HTTPS GET）
  @HiveField(5)
  String? importUrl;

  /// 每日限玩次数（0 不限制）
  @HiveField(6, defaultValue: 0)
  int dailyPlayLimit;

  /// AI 生成题目提示词模板
  @HiveField(7, defaultValue: kDefaultEncyclopediaQuestionGenPromptTemplate)
  String questionGenPromptTemplate;

  /// 答对后的语音反馈
  @HiveField(8, defaultValue: '恭喜答对了')
  String correctFeedbackText;

  /// 答错后的语音反馈
  @HiveField(9, defaultValue: '答错了，继续加油哦')
  String wrongFeedbackText;

  EncyclopediaConfig({
    this.chatConfigId,
    this.chatModel,
    this.promptTemplate = kDefaultEncyclopediaPromptTemplate,
    this.cacheExpiryDays = 30,
    this.enableAutoRefresh = true,
    this.importUrl,
    this.dailyPlayLimit = 0,
    this.questionGenPromptTemplate =
        kDefaultEncyclopediaQuestionGenPromptTemplate,
    this.correctFeedbackText = '恭喜答对了',
    this.wrongFeedbackText = '答错了，继续加油哦',
  });

  Map<String, dynamic> toJson() => {
        'chatConfigId': chatConfigId,
        'chatModel': chatModel,
        'promptTemplate': promptTemplate,
        'cacheExpiryDays': cacheExpiryDays,
        'enableAutoRefresh': enableAutoRefresh,
        'importUrl': importUrl,
        'dailyPlayLimit': dailyPlayLimit,
        'questionGenPromptTemplate': questionGenPromptTemplate,
        'correctFeedbackText': correctFeedbackText,
        'wrongFeedbackText': wrongFeedbackText,
      };

  factory EncyclopediaConfig.fromJson(Map<String, dynamic> json) {
    return EncyclopediaConfig(
      chatConfigId: json['chatConfigId'] as String?,
      chatModel: json['chatModel'] as String?,
      promptTemplate: (json['promptTemplate'] as String?) ??
          kDefaultEncyclopediaPromptTemplate,
      cacheExpiryDays: (json['cacheExpiryDays'] as num?)?.toInt() ?? 30,
      enableAutoRefresh: json['enableAutoRefresh'] as bool? ?? true,
      importUrl: json['importUrl'] as String?,
      dailyPlayLimit: (json['dailyPlayLimit'] as num?)?.toInt() ?? 0,
      questionGenPromptTemplate:
          (json['questionGenPromptTemplate'] as String?) ??
              kDefaultEncyclopediaQuestionGenPromptTemplate,
      correctFeedbackText: (json['correctFeedbackText'] as String?) ?? '恭喜答对了',
      wrongFeedbackText: (json['wrongFeedbackText'] as String?) ?? '答错了，继续加油哦',
    );
  }
}
