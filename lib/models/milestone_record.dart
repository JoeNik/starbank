import 'package:hive/hive.dart';

part 'milestone_record.g.dart';

@HiveType(typeId: 47)
class MilestoneRecord extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String babyId;

  @HiveField(2)
  DateTime recordDate;

  @HiveField(3)
  String title;

  @HiveField(4)
  String category;

  @HiveField(5)
  String description;

  /// Encoded refs: dataSourceId|babyId|mediaId
  @HiveField(6, defaultValue: [])
  List<String> mediaRefs;

  @HiveField(7)
  String? coverMediaRef;

  @HiveField(8)
  String? sourceImagePath;

  @HiveField(9)
  DateTime createdAt;

  @HiveField(10)
  DateTime updatedAt;

  @HiveField(11)
  DateTime? deletedAt;

  @HiveField(12, defaultValue: [])
  List<String> tags;

  MilestoneRecord({
    required this.id,
    required this.babyId,
    required this.recordDate,
    required this.title,
    this.category = '第一次',
    this.description = '',
    List<String>? mediaRefs,
    this.coverMediaRef,
    this.sourceImagePath,
    List<String>? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
  })  : mediaRefs = mediaRefs ?? <String>[],
        tags = tags ?? <String>[],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  bool get isDeleted => deletedAt != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'babyId': babyId,
        'recordDate': recordDate.toIso8601String(),
        'title': title,
        'category': category,
        'description': description,
        'mediaRefs': mediaRefs,
        'coverMediaRef': coverMediaRef,
        'sourceImagePath': sourceImagePath,
        'tags': tags,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
      };

  factory MilestoneRecord.fromJson(Map<String, dynamic> json) =>
      MilestoneRecord(
        id: json['id'] as String,
        babyId: json['babyId'] as String,
        recordDate: DateTime.parse(json['recordDate'] as String),
        title: json['title'] as String? ?? '',
        category: json['category'] as String? ?? '第一次',
        description: json['description'] as String? ?? '',
        mediaRefs: (json['mediaRefs'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
        coverMediaRef: json['coverMediaRef'] as String?,
        sourceImagePath: json['sourceImagePath'] as String?,
        tags: (json['tags'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : DateTime.now(),
        updatedAt: json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'] as String)
            : DateTime.now(),
        deletedAt: json['deletedAt'] != null
            ? DateTime.parse(json['deletedAt'] as String)
            : null,
      );
}
