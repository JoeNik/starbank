import 'package:hive/hive.dart';

part 'story_session.g.dart';

/// 故事会话记录
@HiveType(typeId: 13)
class StorySession extends HiveObject {
  /// 唯一标识
  @HiveField(0)
  String id;

  /// 宝宝ID
  @HiveField(1)
  String babyId;

  /// 创建时间
  @HiveField(2)
  DateTime createdAt;

  /// 图片URL或本地路径
  @HiveField(3)
  String imageUrl;

  /// 对话记录（JSON格式存储）
  @HiveField(4)
  List<Map<String, dynamic>> messages;

  /// 最终得分（0-100）
  @HiveField(5, defaultValue: 0)
  int score;

  /// 是否完成
  @HiveField(6, defaultValue: false)
  bool isCompleted;

  /// 家长是否已审核
  @HiveField(7, defaultValue: false)
  bool isReviewed;

  /// 家长审核后的额外奖励星星
  @HiveField(8, defaultValue: 0)
  int bonusStars;

  /// AI生成的故事总结
  @HiveField(9, defaultValue: '')
  String storySummary;

  StorySession({
    required this.id,
    required this.babyId,
    required this.createdAt,
    required this.imageUrl,
    this.messages = const [],
    this.score = 0,
    this.isCompleted = false,
    this.isReviewed = false,
    this.bonusStars = 0,
    this.storySummary = '',
  });

  /// 添加消息
  void addMessage(String role, String content) {
    messages = [
      ...messages,
      {
        'role': role,
        'content': content,
        'timestamp': DateTime.now().toIso8601String(),
      }
    ];
  }

  /// 获取对话轮数
  int get roundCount => messages.where((m) => m['role'] == 'child').length;

  /// 转换为 JSON
  Map<String, dynamic> toJson() => {
        'id': id,
        'babyId': babyId,
        'createdAt': createdAt.toIso8601String(),
        'imageUrl': imageUrl,
        'messages': messages,
        'score': score,
        'isCompleted': isCompleted,
        'isReviewed': isReviewed,
        'bonusStars': bonusStars,
        'storySummary': storySummary,
      };

  /// 从 JSON 创建
  factory StorySession.fromJson(Map<String, dynamic> json) => StorySession(
        id: json['id'] as String,
        babyId: json['babyId'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        imageUrl: json['imageUrl'] as String,
        messages: (json['messages'] as List<dynamic>?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [],
        score: json['score'] as int? ?? 0,
        isCompleted: json['isCompleted'] as bool? ?? false,
        isReviewed: json['isReviewed'] as bool? ?? false,
        bonusStars: json['bonusStars'] as int? ?? 0,
        storySummary: json['storySummary'] as String? ?? '',
      );
}
