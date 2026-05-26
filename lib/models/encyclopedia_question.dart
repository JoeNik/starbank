import 'package:hive/hive.dart';

part 'encyclopedia_question.g.dart';

/// 生活科学百科题目模型
@HiveType(typeId: 43)
class EncyclopediaQuestion extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String question;

  @HiveField(2)
  String emoji;

  @HiveField(3)
  List<String> options;

  @HiveField(4)
  int correctIndex;

  /// 标准答案文本（用于显示和校验）
  @HiveField(5)
  String answer;

  /// 内置解释（AI 失败时回退）
  @HiveField(6)
  String explanation;

  @HiveField(7)
  String category;

  /// 来源：builtin / remote
  @HiveField(8)
  String source;

  @HiveField(9)
  DateTime createdAt;

  @HiveField(10)
  DateTime updatedAt;

  EncyclopediaQuestion({
    required this.id,
    required this.question,
    required this.emoji,
    required this.options,
    required this.correctIndex,
    required this.answer,
    required this.explanation,
    required this.category,
    this.source = 'builtin',
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'question': question,
        'emoji': emoji,
        'options': options,
        'correctIndex': correctIndex,
        'answer': answer,
        'explanation': explanation,
        'category': category,
        'source': source,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory EncyclopediaQuestion.fromJson(Map<String, dynamic> json) {
    final rawOptions = (json['options'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        <String>[];
    final options =
        rawOptions.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final correctIndex = (json['correctIndex'] as num?)?.toInt() ?? 0;
    final answer = (json['answer'] as String?)?.trim();
    final safeIndex = _resolveCorrectIndex(options, correctIndex, answer);
    final fallbackAnswer =
        options.isNotEmpty ? options[safeIndex] : (answer ?? '正确');
    final normalized = _normalizeOptions(options, safeIndex, fallbackAnswer);
    final normalizedAnswer = normalized.options[normalized.correctIndex];

    return EncyclopediaQuestion(
      id: (json['id'] as String?)?.trim().isNotEmpty == true
          ? (json['id'] as String).trim()
          : DateTime.now().millisecondsSinceEpoch.toString(),
      question: (json['question'] as String? ?? '').trim(),
      emoji: (json['emoji'] as String?)?.trim().isNotEmpty == true
          ? (json['emoji'] as String).trim()
          : '🌍',
      options: normalized.options,
      correctIndex: normalized.correctIndex,
      answer: normalizedAnswer,
      explanation: (json['explanation'] as String? ?? '').trim(),
      category: (json['category'] as String? ?? 'general').trim(),
      source: (json['source'] as String? ?? 'remote').trim(),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : DateTime.now(),
    );
  }

  static int _resolveCorrectIndex(
    List<String> options,
    int correctIndex,
    String? answer,
  ) {
    if (options.isEmpty) return 0;
    if (answer != null && answer.isNotEmpty) {
      final answerIndex = options.indexOf(answer);
      if (answerIndex != -1) return answerIndex;
    }
    return correctIndex.clamp(0, options.length - 1).toInt();
  }

  static _NormalizedOptions _normalizeOptions(
    List<String> options,
    int correctIndex,
    String fallbackAnswer,
  ) {
    if (options.isEmpty) {
      final correct = fallbackAnswer.trim().isNotEmpty ? fallbackAnswer : '正确';
      return _NormalizedOptions([correct, '不正确'], 0);
    }

    if (options.length == 1) {
      final correct = options.first;
      final wrong = correct == '不是这样' ? '是这样' : '不是这样';
      return _NormalizedOptions([correct, wrong], 0);
    }

    if (options.length == 2) {
      return _NormalizedOptions(
        options,
        correctIndex.clamp(0, options.length - 1).toInt(),
      );
    }

    final correct = options[correctIndex];
    final wrong = options.firstWhere(
      (option) => option != correct,
      orElse: () => fallbackAnswer == correct ? '不是这样' : fallbackAnswer,
    );

    if (correctIndex == 0) {
      return _NormalizedOptions([correct, wrong], 0);
    }
    return _NormalizedOptions([wrong, correct], 1);
  }
}

class _NormalizedOptions {
  final List<String> options;
  final int correctIndex;

  const _NormalizedOptions(this.options, this.correctIndex);
}
