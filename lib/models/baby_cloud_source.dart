import 'package:hive/hive.dart';

part 'baby_cloud_source.g.dart';

enum BabyCloudSourceType {
  webDav,
  aliyunDrive,
}

enum BabyCloudSourceStatus {
  normal,
  notInitialized,
  syncing,
  invalid,
  readOnly,
}

@HiveType(typeId: 48)
class BabyCloudSource extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  /// webdav / aliyunDrive
  @HiveField(2)
  String type;

  @HiveField(3)
  String status;

  @HiveField(4)
  String rootPath;

  @HiveField(5)
  String? webDavUrl;

  @HiveField(6)
  String? webDavUsername;

  @HiveField(7)
  String? webDavPassword;

  @HiveField(8)
  String? aliyunDriveRefreshToken;

  @HiveField(9)
  DateTime createdAt;

  @HiveField(10)
  DateTime updatedAt;

  /// Optional LAN endpoint. When available on local Wi-Fi, the cloud service
  /// tries this before the public endpoint.
  @HiveField(11)
  String? webDavLanUrl;

  /// Last endpoint that passed availability check.
  @HiveField(12)
  String? activeWebDavUrl;

  /// none / lan / external
  @HiveField(13)
  String activeWebDavEndpoint;

  @HiveField(14)
  DateTime? lastCheckedAt;

  @HiveField(15)
  String? lastCheckMessage;

  /// Stable identity read from library_manifest.json under the configured root.
  @HiveField(16)
  String? libraryId;

  @HiveField(17)
  String? libraryName;

  BabyCloudSource({
    required this.id,
    required this.name,
    this.type = 'webdav',
    this.status = 'notInitialized',
    this.rootPath = 'starbank_baby_cloud',
    this.webDavUrl,
    this.webDavUsername,
    this.webDavPassword,
    this.aliyunDriveRefreshToken,
    this.webDavLanUrl,
    this.activeWebDavUrl,
    this.activeWebDavEndpoint = 'none',
    this.lastCheckedAt,
    this.lastCheckMessage,
    this.libraryId,
    this.libraryName,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  bool get isWebDav => type == 'webdav';
  bool get isAliyunDrive => type == 'aliyunDrive';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'status': status,
        'rootPath': rootPath,
        'webDavUrl': webDavUrl,
        'webDavUsername': webDavUsername,
        'webDavPassword': webDavPassword,
        'aliyunDriveRefreshToken': aliyunDriveRefreshToken,
        'webDavLanUrl': webDavLanUrl,
        'activeWebDavUrl': activeWebDavUrl,
        'activeWebDavEndpoint': activeWebDavEndpoint,
        'lastCheckedAt': lastCheckedAt?.toIso8601String(),
        'lastCheckMessage': lastCheckMessage,
        'libraryId': libraryId,
        'libraryName': libraryName,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory BabyCloudSource.fromJson(Map<String, dynamic> json) =>
      BabyCloudSource(
        id: json['id'] as String,
        name: json['name'] as String? ?? '亲宝宝 WebDAV',
        type: json['type'] as String? ?? 'webdav',
        status: json['status'] as String? ?? 'notInitialized',
        rootPath: json['rootPath'] as String? ?? 'starbank_baby_cloud',
        webDavUrl: json['webDavUrl'] as String?,
        webDavUsername: json['webDavUsername'] as String?,
        webDavPassword: json['webDavPassword'] as String?,
        aliyunDriveRefreshToken: json['aliyunDriveRefreshToken'] as String?,
        webDavLanUrl: json['webDavLanUrl'] as String?,
        activeWebDavUrl: json['activeWebDavUrl'] as String?,
        activeWebDavEndpoint: json['activeWebDavEndpoint'] as String? ?? 'none',
        lastCheckedAt: json['lastCheckedAt'] != null
            ? DateTime.parse(json['lastCheckedAt'] as String)
            : null,
        lastCheckMessage: json['lastCheckMessage'] as String?,
        libraryId: json['libraryId'] as String?,
        libraryName: json['libraryName'] as String?,
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : DateTime.now(),
        updatedAt: json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'] as String)
            : DateTime.now(),
      );
}
