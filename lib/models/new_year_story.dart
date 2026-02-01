import 'package:hive/hive.dart';
import 'dart:convert';

part 'new_year_story.g.dart';

/// 新年故事模型
@HiveType(typeId: 22)
class NewYearStory extends HiveObject {
  /// 故事 ID
  @HiveField(0)
  String id;

  /// 故事标题
  @HiveField(1)
  String title;

  /// Emoji 图标
  @HiveField(2)
  String emoji;

  /// 时长描述
  @HiveField(3)
  String duration;

  /// 故事页面列表 (JSON 字符串存储)
  @HiveField(4)
  String pagesJson;

  /// 创建时间
  @HiveField(5)
  DateTime createdAt;

  /// 更新时间
  @HiveField(6)
  DateTime updatedAt;

  NewYearStory({
    required this.id,
    required this.title,
    required this.emoji,
    required this.duration,
    required this.pagesJson,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// 转换为 JSON
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'emoji': emoji,
        'duration': duration,
        'pages': pagesJson,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  /// 从 JSON 创建
  factory NewYearStory.fromJson(Map<String, dynamic> json) => NewYearStory(
        id: json['id'] as String,
        title: json['title'] as String,
        emoji: json['emoji'] as String? ?? '📖',
        duration: json['duration'] as String? ?? '2分钟',
        pagesJson: json['pages'] as String,
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : DateTime.now(),
        updatedAt: json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'] as String)
            : DateTime.now(),
      );

  /// 从旧格式 Map 创建(兼容现有故事数据)
  factory NewYearStory.fromLegacyMap(Map<String, dynamic> map) {
    // 将 pages 列表转换为 JSON 字符串
    final pagesJson = _encodePagesToJson(map['pages'] as List<dynamic>);

    return NewYearStory(
      id: map['id'] as String,
      title: map['title'] as String,
      emoji: map['emoji'] as String? ?? '📖',
      duration: map['duration'] as String? ?? '2分钟',
      pagesJson: pagesJson,
    );
  }

  /// 转换为旧格式 Map (用于兼容现有代码)
  Map<String, dynamic> toLegacyMap() {
    return {
      'id': id,
      'title': title,
      'emoji': emoji,
      'duration': duration,
      'pages': _decodePagesFromJson(pagesJson),
    };
  }

  /// 将 pages 列表编码为 JSON 字符串
  static String _encodePagesToJson(List<dynamic> pages) {
    return jsonEncode(pages);
  }

  /// 从 JSON 字符串解码 pages 列表
  static List<Map<String, dynamic>> _decodePagesFromJson(String json) {
    try {
      final List<dynamic> decoded = jsonDecode(json);
      return decoded.map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      return [];
    }
  }

  /// 获取页面数量
  int get pageCount {
    try {
      final pages = _decodePagesFromJson(pagesJson);
      return pages.length;
    } catch (e) {
      return 0;
    }
  }
}
