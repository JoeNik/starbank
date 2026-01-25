import 'package:hive/hive.dart';

part 'ai_chat.g.dart';

/// AI 对话记录
@HiveType(typeId: 12)
class AIChat extends HiveObject {
  /// 唯一标识
  @HiveField(0)
  String id;

  /// 关联的宝宝ID
  @HiveField(1)
  String babyId;

  /// 创建时间
  @HiveField(2)
  DateTime createdAt;

  /// 发送的内容/问题
  @HiveField(3)
  String prompt;

  /// AI 回复的内容
  @HiveField(4)
  String response;

  /// 对话类型: poop_analysis, feeding_analysis 等
  @HiveField(5)
  String chatType;

  AIChat({
    required this.id,
    required this.babyId,
    required this.createdAt,
    required this.prompt,
    required this.response,
    required this.chatType,
  });

  /// 转换为 JSON
  Map<String, dynamic> toJson() => {
        'id': id,
        'babyId': babyId,
        'createdAt': createdAt.toIso8601String(),
        'prompt': prompt,
        'response': response,
        'chatType': chatType,
      };

  /// 从 JSON 创建
  factory AIChat.fromJson(Map<String, dynamic> json) => AIChat(
        id: json['id'] as String,
        babyId: json['babyId'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        prompt: json['prompt'] as String,
        response: json['response'] as String,
        chatType: json['chatType'] as String,
      );
}
