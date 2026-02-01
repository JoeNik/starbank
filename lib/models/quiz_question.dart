import 'package:hive/hive.dart';

part 'quiz_question.g.dart';

/// 问答题目模型
@HiveType(typeId: 21)
class QuizQuestion extends HiveObject {
  /// 题目 ID
  @HiveField(0)
  String id;

  /// 问题文本
  @HiveField(1)
  String question;

  /// Emoji 图标
  @HiveField(2)
  String emoji;

  /// 选项列表
  @HiveField(3)
  List<String> options;

  /// 正确答案索引
  @HiveField(4)
  int correctIndex;

  /// 知识点解释
  @HiveField(5)
  String explanation;

  /// 分类
  @HiveField(6)
  String category;

  /// 图片本地路径(缓存)
  @HiveField(7)
  String? imagePath;

  /// 图片生成状态: null-未生成, 'generating'-生成中, 'success'-成功, 'failed'-失败
  @HiveField(8)
  String? imageStatus;

  /// 图片生成失败原因
  @HiveField(9)
  String? imageError;

  /// 创建时间
  @HiveField(10)
  DateTime createdAt;

  /// 更新时间
  @HiveField(11)
  DateTime updatedAt;

  QuizQuestion({
    required this.id,
    required this.question,
    required this.emoji,
    required this.options,
    required this.correctIndex,
    required this.explanation,
    required this.category,
    this.imagePath,
    this.imageStatus,
    this.imageError,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// 转换为 JSON
  Map<String, dynamic> toJson() => {
        'id': id,
        'question': question,
        'emoji': emoji,
        'options': options,
        'correctIndex': correctIndex,
        'explanation': explanation,
        'category': category,
        'imagePath': imagePath,
        'imageStatus': imageStatus,
        'imageError': imageError,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  /// 从 JSON 创建
  factory QuizQuestion.fromJson(Map<String, dynamic> json) => QuizQuestion(
        id: json['id'] as String,
        question: json['question'] as String,
        emoji: json['emoji'] as String? ?? '❓',
        options:
            (json['options'] as List<dynamic>).map((e) => e as String).toList(),
        correctIndex: json['correctIndex'] as int,
        explanation: json['explanation'] as String,
        category: json['category'] as String? ?? 'general',
        imagePath: json['imagePath'] as String?,
        imageStatus: json['imageStatus'] as String?,
        imageError: json['imageError'] as String?,
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : DateTime.now(),
        updatedAt: json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'] as String)
            : DateTime.now(),
      );

  /// 从旧格式 Map 创建(兼容现有题库)
  factory QuizQuestion.fromLegacyMap(Map<String, dynamic> map, {String? id}) {
    return QuizQuestion(
      id: id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      question: map['question'] as String,
      emoji: map['emoji'] as String? ?? '❓',
      options:
          (map['options'] as List<dynamic>).map((e) => e as String).toList(),
      correctIndex: map['correctIndex'] as int,
      explanation: map['explanation'] as String,
      category: map['category'] as String? ?? 'general',
    );
  }

  /// 是否有图片
  bool get hasImage => imagePath != null && imagePath!.isNotEmpty;

  /// 是否可以生成图片
  bool get canGenerateImage => imageStatus == null || imageStatus == 'failed';

  /// 是否正在生成图片
  bool get isGeneratingImage => imageStatus == 'generating';
}
