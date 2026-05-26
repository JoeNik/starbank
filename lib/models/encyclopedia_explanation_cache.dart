import 'package:hive/hive.dart';

part 'encyclopedia_explanation_cache.g.dart';

/// AI 解析缓存
@HiveType(typeId: 45)
class EncyclopediaExplanationCache extends HiveObject {
  /// cacheKey = questionId|model|promptVersion
  @HiveField(0)
  String cacheKey;

  @HiveField(1)
  String questionId;

  @HiveField(2)
  String model;

  @HiveField(3)
  String promptVersion;

  /// 按约定三段
  @HiveField(4)
  String shortAnswer;

  @HiveField(5)
  String why;

  @HiveField(6)
  String example;

  @HiveField(7)
  DateTime createdAt;

  @HiveField(8)
  DateTime updatedAt;

  EncyclopediaExplanationCache({
    required this.cacheKey,
    required this.questionId,
    required this.model,
    required this.promptVersion,
    required this.shortAnswer,
    required this.why,
    required this.example,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'cacheKey': cacheKey,
        'questionId': questionId,
        'model': model,
        'promptVersion': promptVersion,
        'shortAnswer': shortAnswer,
        'why': why,
        'example': example,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory EncyclopediaExplanationCache.fromJson(Map<String, dynamic> json) {
    return EncyclopediaExplanationCache(
      cacheKey: json['cacheKey'] as String,
      questionId: json['questionId'] as String,
      model: json['model'] as String,
      promptVersion: json['promptVersion'] as String,
      shortAnswer: json['shortAnswer'] as String? ?? '',
      why: json['why'] as String? ?? '',
      example: json['example'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : DateTime.now(),
    );
  }
}
