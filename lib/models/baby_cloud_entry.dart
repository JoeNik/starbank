import 'package:hive/hive.dart';

part 'baby_cloud_entry.g.dart';

@HiveType(typeId: 51)
class BabyCloudEntry extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String babyId;

  @HiveField(2)
  String dataSourceId;

  @HiveField(3)
  String libraryId;

  @HiveField(4)
  String cloudBabyId;

  /// media / diary / mixed / audio
  @HiveField(5)
  String entryType;

  @HiveField(6)
  String? description;

  @HiveField(7)
  List<String> tags;

  @HiveField(8)
  String? locationName;

  @HiveField(9)
  String visibility;

  @HiveField(10)
  DateTime takenAt;

  @HiveField(11)
  DateTime createdAt;

  @HiveField(12)
  DateTime updatedAt;

  @HiveField(13)
  DateTime? deletedAt;

  /// entryDeleted / userDeleted / importedConflict
  @HiveField(14)
  String? deleteReason;

  @HiveField(15)
  List<String> mediaIds;

  /// After explicit permanent cloud deletion. Kept as a marker so another
  /// device will not revive stale deleted content from an older index.
  @HiveField(16)
  DateTime? purgedAt;

  @HiveField(17)
  String? actorRole;

  BabyCloudEntry({
    required this.id,
    required this.babyId,
    required this.dataSourceId,
    this.libraryId = '',
    this.cloudBabyId = '',
    this.entryType = 'media',
    this.description,
    List<String>? tags,
    this.locationName,
    this.visibility = 'family',
    DateTime? takenAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
    this.deleteReason,
    List<String>? mediaIds,
    this.purgedAt,
    this.actorRole,
  })  : tags = tags ?? const [],
        mediaIds = mediaIds ?? const [],
        takenAt = takenAt ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  bool get isDeleted => deletedAt != null;
  bool get isPurged => purgedAt != null;

  String get ref => '$libraryId|$dataSourceId|$babyId|$id';

  Map<String, dynamic> toJson() => {
        'id': id,
        'babyId': babyId,
        'dataSourceId': dataSourceId,
        'libraryId': libraryId,
        'cloudBabyId': cloudBabyId,
        'entryType': entryType,
        'description': description,
        'tags': tags,
        'locationName': locationName,
        'visibility': visibility,
        'takenAt': takenAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
        'deleteReason': deleteReason,
        'mediaIds': mediaIds,
        'purgedAt': purgedAt?.toIso8601String(),
        'actorRole': actorRole,
      };

  factory BabyCloudEntry.fromJson(Map<String, dynamic> json) => BabyCloudEntry(
        id: json['id'] as String,
        babyId: json['babyId'] as String? ?? '',
        dataSourceId: json['dataSourceId'] as String? ?? '',
        libraryId: json['libraryId'] as String? ?? '',
        cloudBabyId: json['cloudBabyId'] as String? ?? '',
        entryType: json['entryType'] as String? ?? 'media',
        description: json['description'] as String?,
        tags: (json['tags'] as List?)?.map((e) => e.toString()).toList(),
        locationName: json['locationName'] as String?,
        visibility: json['visibility'] as String? ?? 'family',
        takenAt: json['takenAt'] != null
            ? DateTime.parse(json['takenAt'] as String)
            : DateTime.now(),
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : DateTime.now(),
        updatedAt: json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'] as String)
            : DateTime.now(),
        deletedAt: json['deletedAt'] != null
            ? DateTime.parse(json['deletedAt'] as String)
            : null,
        deleteReason: json['deleteReason'] as String?,
        mediaIds:
            (json['mediaIds'] as List?)?.map((e) => e.toString()).toList(),
        purgedAt: json['purgedAt'] != null
            ? DateTime.parse(json['purgedAt'] as String)
            : null,
        actorRole: json['actorRole'] as String?,
      );
}
