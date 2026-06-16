import 'package:hive/hive.dart';

part 'baby_cloud_media.g.dart';

@HiveType(typeId: 49)
class BabyCloudMedia extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String babyId;

  @HiveField(2)
  String dataSourceId;

  @HiveField(3)
  String sha256;

  @HiveField(4)
  String fileName;

  @HiveField(5)
  String mediaType; // photo / video

  @HiveField(6)
  String mimeType;

  @HiveField(7)
  String remotePath;

  @HiveField(8)
  String? thumbnailRemotePath;

  @HiveField(9)
  String? localPath;

  @HiveField(10)
  String? localThumbnailPath;

  @HiveField(11)
  int sizeBytes;

  @HiveField(12)
  int? width;

  @HiveField(13)
  int? height;

  @HiveField(14)
  int? durationSeconds;

  @HiveField(15)
  DateTime takenAt;

  @HiveField(16)
  DateTime uploadedAt;

  @HiveField(17)
  DateTime updatedAt;

  @HiveField(18)
  DateTime? deletedAt;

  @HiveField(19)
  String entryId;

  @HiveField(20)
  String? description;

  @HiveField(21)
  List<String> tags;

  @HiveField(22)
  String? locationName;

  @HiveField(23, defaultValue: 'family')
  String visibility;

  @HiveField(24, defaultValue: '')
  String libraryId;

  @HiveField(25, defaultValue: '')
  String cloudBabyId;

  /// singleFileDeleted / entryDeleted / replaced
  @HiveField(26)
  String? deleteReason;

  @HiveField(27)
  String? replacedByMediaId;

  /// Physical cloud file has been deleted by an explicit parent-only flow.
  @HiveField(28)
  DateTime? purgedAt;

  @HiveField(29)
  String? actorRole;

  BabyCloudMedia({
    required this.id,
    required this.babyId,
    required this.dataSourceId,
    this.libraryId = '',
    this.cloudBabyId = '',
    required this.sha256,
    required this.fileName,
    required this.mediaType,
    required this.mimeType,
    required this.remotePath,
    this.thumbnailRemotePath,
    this.localPath,
    this.localThumbnailPath,
    this.sizeBytes = 0,
    this.width,
    this.height,
    this.durationSeconds,
    DateTime? takenAt,
    DateTime? uploadedAt,
    DateTime? updatedAt,
    this.deletedAt,
    String? entryId,
    this.description,
    List<String>? tags,
    this.locationName,
    this.visibility = 'family',
    this.deleteReason,
    this.replacedByMediaId,
    this.purgedAt,
    this.actorRole,
  })  : takenAt = takenAt ?? DateTime.now(),
        uploadedAt = uploadedAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        entryId = entryId ?? id,
        tags = tags ?? const [];

  bool get isDeleted => deletedAt != null;
  bool get isPurged => purgedAt != null;
  bool get isVideo => mediaType == 'video';
  bool get isAudio => mediaType == 'audio';
  bool get isDiary => mediaType == 'diary';

  String get ref => '$dataSourceId|$babyId|$id';

  Map<String, dynamic> toJson() => {
        'id': id,
        'babyId': babyId,
        'dataSourceId': dataSourceId,
        'libraryId': libraryId,
        'cloudBabyId': cloudBabyId,
        'sha256': sha256,
        'fileName': fileName,
        'mediaType': mediaType,
        'mimeType': mimeType,
        'remotePath': remotePath,
        'thumbnailRemotePath': thumbnailRemotePath,
        'localPath': localPath,
        'localThumbnailPath': localThumbnailPath,
        'sizeBytes': sizeBytes,
        'width': width,
        'height': height,
        'durationSeconds': durationSeconds,
        'takenAt': takenAt.toIso8601String(),
        'uploadedAt': uploadedAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
        'entryId': entryId,
        'description': description,
        'tags': tags,
        'locationName': locationName,
        'visibility': visibility,
        'deleteReason': deleteReason,
        'replacedByMediaId': replacedByMediaId,
        'purgedAt': purgedAt?.toIso8601String(),
        'actorRole': actorRole,
      };

  factory BabyCloudMedia.fromJson(Map<String, dynamic> json) => BabyCloudMedia(
        id: json['id'] as String,
        babyId: json['babyId'] as String,
        dataSourceId: json['dataSourceId'] as String,
        libraryId: json['libraryId'] as String? ?? '',
        cloudBabyId: json['cloudBabyId'] as String? ?? '',
        sha256: json['sha256'] as String,
        fileName: json['fileName'] as String? ?? '',
        mediaType: json['mediaType'] as String? ?? 'photo',
        mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
        remotePath: json['remotePath'] as String? ?? '',
        thumbnailRemotePath: json['thumbnailRemotePath'] as String?,
        localPath: json['localPath'] as String?,
        localThumbnailPath: json['localThumbnailPath'] as String?,
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
        width: (json['width'] as num?)?.toInt(),
        height: (json['height'] as num?)?.toInt(),
        durationSeconds: (json['durationSeconds'] as num?)?.toInt(),
        takenAt: json['takenAt'] != null
            ? DateTime.parse(json['takenAt'] as String)
            : DateTime.now(),
        uploadedAt: json['uploadedAt'] != null
            ? DateTime.parse(json['uploadedAt'] as String)
            : DateTime.now(),
        updatedAt: json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'] as String)
            : DateTime.now(),
        deletedAt: json['deletedAt'] != null
            ? DateTime.parse(json['deletedAt'] as String)
            : null,
        entryId: json['entryId'] as String?,
        description: json['description'] as String?,
        tags: (json['tags'] as List?)?.map((e) => e.toString()).toList(),
        locationName: json['locationName'] as String?,
        visibility: json['visibility'] as String? ?? 'family',
        deleteReason: json['deleteReason'] as String?,
        replacedByMediaId: json['replacedByMediaId'] as String?,
        purgedAt: json['purgedAt'] != null
            ? DateTime.parse(json['purgedAt'] as String)
            : null,
        actorRole: json['actorRole'] as String?,
      );
}
