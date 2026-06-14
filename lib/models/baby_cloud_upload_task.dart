import 'package:hive/hive.dart';

part 'baby_cloud_upload_task.g.dart';

@HiveType(typeId: 50)
class BabyCloudUploadTask extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String babyId;

  @HiveField(2)
  String dataSourceId;

  @HiveField(3)
  String localPath;

  @HiveField(4)
  String fileName;

  @HiveField(5)
  String mediaType;

  @HiveField(6)
  String mimeType;

  @HiveField(7)
  int sizeBytes;

  @HiveField(8)
  String? sha256;

  @HiveField(9)
  String status; // queued / running / paused / completed / failed / cancelled

  @HiveField(10)
  double progress;

  @HiveField(11)
  String? remotePath;

  @HiveField(12)
  String? errorMessage;

  @HiveField(13)
  DateTime createdAt;

  @HiveField(14)
  DateTime updatedAt;

  @HiveField(15)
  DateTime? takenAt;

  @HiveField(16)
  String? localThumbnailPath;

  @HiveField(17)
  String entryId;

  @HiveField(18)
  String? description;

  @HiveField(19)
  List<String> tags;

  @HiveField(20)
  String? locationName;

  @HiveField(21)
  String visibility;

  /// upload / metadata / purgeMedia / purgeEntry
  @HiveField(22)
  String taskType;

  @HiveField(23)
  String? targetId;

  @HiveField(24)
  String? actorRole;

  @HiveField(25)
  int retryCount;

  BabyCloudUploadTask({
    required this.id,
    required this.babyId,
    required this.dataSourceId,
    required this.localPath,
    required this.fileName,
    required this.mediaType,
    required this.mimeType,
    this.sizeBytes = 0,
    this.sha256,
    this.status = 'queued',
    this.progress = 0,
    this.remotePath,
    this.errorMessage,
    this.takenAt,
    this.localThumbnailPath,
    String? entryId,
    this.description,
    List<String>? tags,
    this.locationName,
    this.visibility = 'family',
    this.taskType = 'upload',
    this.targetId,
    this.actorRole,
    this.retryCount = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        entryId = entryId ?? id,
        tags = tags ?? const [];

  bool get isDone => status == 'completed';
  bool get isActive => status == 'queued' || status == 'running';

  Map<String, dynamic> toJson() => {
        'id': id,
        'babyId': babyId,
        'dataSourceId': dataSourceId,
        'localPath': localPath,
        'fileName': fileName,
        'mediaType': mediaType,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
        'sha256': sha256,
        'status': status,
        'progress': progress,
        'remotePath': remotePath,
        'errorMessage': errorMessage,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'takenAt': takenAt?.toIso8601String(),
        'localThumbnailPath': localThumbnailPath,
        'entryId': entryId,
        'description': description,
        'tags': tags,
        'locationName': locationName,
        'visibility': visibility,
        'taskType': taskType,
        'targetId': targetId,
        'actorRole': actorRole,
        'retryCount': retryCount,
      };

  factory BabyCloudUploadTask.fromJson(Map<String, dynamic> json) =>
      BabyCloudUploadTask(
        id: json['id'] as String,
        babyId: json['babyId'] as String,
        dataSourceId: json['dataSourceId'] as String,
        localPath: json['localPath'] as String? ?? '',
        fileName: json['fileName'] as String? ?? '',
        mediaType: json['mediaType'] as String? ?? 'photo',
        mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
        sha256: json['sha256'] as String?,
        status: json['status'] as String? ?? 'queued',
        progress: (json['progress'] as num?)?.toDouble() ?? 0,
        remotePath: json['remotePath'] as String?,
        errorMessage: json['errorMessage'] as String?,
        localThumbnailPath: json['localThumbnailPath'] as String?,
        entryId: json['entryId'] as String?,
        description: json['description'] as String?,
        tags: (json['tags'] as List?)?.map((e) => e.toString()).toList(),
        locationName: json['locationName'] as String?,
        visibility: json['visibility'] as String? ?? 'family',
        taskType: json['taskType'] as String? ?? 'upload',
        targetId: json['targetId'] as String?,
        actorRole: json['actorRole'] as String?,
        retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
        takenAt: json['takenAt'] != null
            ? DateTime.parse(json['takenAt'] as String)
            : null,
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : DateTime.now(),
        updatedAt: json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'] as String)
            : DateTime.now(),
      );
}
