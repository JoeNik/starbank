import 'package:hive/hive.dart';

part 'growth_record.g.dart';

@HiveType(typeId: 46)
class GrowthRecord extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String babyId;

  @HiveField(2)
  DateTime recordDate;

  @HiveField(3)
  double? heightCm;

  @HiveField(4)
  double? weightKg;

  @HiveField(5)
  double? headCircumferenceCm;

  @HiveField(6)
  String note;

  @HiveField(7)
  String? sourceImagePath;

  @HiveField(8)
  DateTime createdAt;

  @HiveField(9)
  DateTime updatedAt;

  @HiveField(10)
  DateTime? deletedAt;

  GrowthRecord({
    required this.id,
    required this.babyId,
    required this.recordDate,
    this.heightCm,
    this.weightKg,
    this.headCircumferenceCm,
    this.note = '',
    this.sourceImagePath,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  bool get isDeleted => deletedAt != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'babyId': babyId,
        'recordDate': recordDate.toIso8601String(),
        'heightCm': heightCm,
        'weightKg': weightKg,
        'headCircumferenceCm': headCircumferenceCm,
        'note': note,
        'sourceImagePath': sourceImagePath,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
      };

  factory GrowthRecord.fromJson(Map<String, dynamic> json) => GrowthRecord(
        id: json['id'] as String,
        babyId: json['babyId'] as String,
        recordDate: DateTime.parse(json['recordDate'] as String),
        heightCm: (json['heightCm'] as num?)?.toDouble(),
        weightKg: (json['weightKg'] as num?)?.toDouble(),
        headCircumferenceCm: (json['headCircumferenceCm'] as num?)?.toDouble(),
        note: json['note'] as String? ?? '',
        sourceImagePath: json['sourceImagePath'] as String?,
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
