import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../controllers/app_mode_controller.dart';
import '../models/cftts_config.dart';
import '../models/openai_config.dart';
import '../models/openai_tts_config.dart';
import '../models/poop_record.dart';
import '../services/encyclopedia_service.dart';
import '../services/quiz_service.dart';
import '../services/story_management_service.dart';
import 'storage_service.dart';

typedef V2RemoteRead = Future<Uint8List> Function(String path);
typedef V2RemoteWrite = Future<void> Function(String path, Uint8List bytes);
typedef V2RemoteRemove = Future<void> Function(String path);
typedef V2RemoteMkdir = Future<void> Function(String path);
typedef V2RemoteList = Future<List<V2RemoteFile>> Function(String path);
typedef V2Progress = void Function(String message);

const int webDavBackupV2FormatVersion = 2;
const String webDavBackupV2Root = '/starbank/v2';
const String webDavBackupV2ManifestDir = '$webDavBackupV2Root/manifests';
const String webDavBackupV2ObjectDir = '$webDavBackupV2Root/objects';

class V2RemoteFile {
  final String path;
  final int size;
  final DateTime? modifiedAt;

  const V2RemoteFile({
    required this.path,
    required this.size,
    this.modifiedAt,
  });
}

class V2BackupWarning {
  final String section;
  final String record;
  final String field;
  final String originalPath;
  final String reason;

  const V2BackupWarning({
    required this.section,
    required this.record,
    required this.field,
    required this.originalPath,
    required this.reason,
  });

  Map<String, dynamic> toJson() => {
        'section': section,
        'record': record,
        'field': field,
        'originalPath': originalPath,
        'reason': reason,
      };

  factory V2BackupWarning.fromJson(Map<String, dynamic> json) =>
      V2BackupWarning(
        section: json['section']?.toString() ?? '',
        record: json['record']?.toString() ?? '',
        field: json['field']?.toString() ?? '',
        originalPath: json['originalPath']?.toString() ?? '',
        reason: json['reason']?.toString() ?? '',
      );
}

class V2BackupObject {
  final String hash;
  final String kind; // json or media
  final String contentType;
  final String contentEncoding; // gzip or identity
  final int rawSize;
  final int storedSize;
  final String path;
  final Uint8List bytes;

  const V2BackupObject({
    required this.hash,
    required this.kind,
    required this.contentType,
    required this.contentEncoding,
    required this.rawSize,
    required this.storedSize,
    required this.path,
    required this.bytes,
  });

  Map<String, dynamic> toManifestJson() => {
        'hash': hash,
        'kind': kind,
        'contentType': contentType,
        'contentEncoding': contentEncoding,
        'rawSize': rawSize,
        'storedSize': storedSize,
        'path': path,
      };

  factory V2BackupObject.fromManifestJson(
    Map<String, dynamic> json,
    Uint8List bytes,
  ) =>
      V2BackupObject(
        hash: json['hash'] as String,
        kind: json['kind'] as String,
        contentType: json['contentType'] as String,
        contentEncoding: json['contentEncoding'] as String,
        rawSize: (json['rawSize'] as num).toInt(),
        storedSize: (json['storedSize'] as num).toInt(),
        path: json['path'] as String,
        bytes: bytes,
      );
}

class V2Snapshot {
  final Map<String, dynamic> manifest;
  final Map<String, V2BackupObject> objects;
  final List<V2BackupWarning> warnings;
  final Map<String, dynamic> backupData;
  final String snapshotHash;

  const V2Snapshot({
    required this.manifest,
    required this.objects,
    required this.warnings,
    required this.backupData,
    required this.snapshotHash,
  });
}

class V2RestoreBundle {
  final Map<String, dynamic> manifest;
  final Map<String, dynamic> backupData;
  final List<V2BackupWarning> warnings;

  const V2RestoreBundle({
    required this.manifest,
    required this.backupData,
    required this.warnings,
  });
}

class V2ManifestInfo {
  final String path;
  final int size;
  final DateTime? modifiedAt;
  final Map<String, dynamic> manifest;
  final List<V2BackupWarning> warnings;

  const V2ManifestInfo({
    required this.path,
    required this.size,
    required this.modifiedAt,
    required this.manifest,
    required this.warnings,
  });

  Map<String, dynamic> get summary =>
      Map<String, dynamic>.from(manifest['summary'] as Map? ?? {});
}

class V2MissingMediaException implements Exception {
  final List<V2BackupWarning> warnings;

  V2MissingMediaException(this.warnings);

  @override
  String toString() => 'Missing media: ${warnings.length}';
}

class WebDavBackupCancelledException implements Exception {
  const WebDavBackupCancelledException();

  @override
  String toString() => 'Backup cancelled.';
}

class WebDavBackupV2Service {
  WebDavBackupV2Service({
    required StorageService storage,
    required V2RemoteRead read,
    required V2RemoteWrite write,
    required V2RemoteRemove remove,
    required V2RemoteMkdir mkdir,
    required V2RemoteList list,
  })  : _storage = storage,
        _read = read,
        _write = write,
        _remove = remove,
        _mkdir = mkdir,
        _list = list;

  final StorageService _storage;
  final V2RemoteRead _read;
  final V2RemoteWrite _write;
  final V2RemoteRemove _remove;
  final V2RemoteMkdir _mkdir;
  final V2RemoteList _list;

  static const Set<String> settingsWhitelist = {
    'tunehub_base_url',
    'tunehub_api_key',
    'riddle_import_url',
  };

  Future<V2Snapshot> collectSnapshot({
    bool allowMissingMedia = false,
    V2Progress? onProgress,
    bool Function()? shouldCancel,
    bool includeLocalAppSettings = false,
  }) async {
    if (kIsWeb) {
      throw StateError('WebDAV v2 backup is not enabled on Web.');
    }

    _throwIfCancelled(shouldCancel);
    onProgress?.call('正在采集数据');
    final backupData = await _collectBackupData(
      includeLocalAppSettings: includeLocalAppSettings,
    );

    _throwIfCancelled(shouldCancel);
    final mediaObjects = <String, V2BackupObject>{};
    final warnings = <V2BackupWarning>[];
    onProgress?.call('正在扫描媒体');
    await _extractWhitelistedMedia(
      backupData,
      mediaObjects,
      warnings,
      allowMissingMedia: allowMissingMedia,
      shouldCancel: shouldCancel,
    );
    if (warnings.isNotEmpty && !allowMissingMedia) {
      throw V2MissingMediaException(warnings);
    }

    final objects = <String, V2BackupObject>{...mediaObjects};
    final sections = <String, dynamic>{};

    final sortedKeys = backupData.keys.toList()..sort();
    for (final key in sortedKeys) {
      _throwIfCancelled(shouldCancel);
      final value = backupData[key];
      sections[key] = _sectionToManifest(key, value, objects);
    }

    final snapshotHash = sha256Hex(
      utf8.encode(canonicalJson({'sections': sections})),
    );

    final info = await PackageInfo.fromPlatform();
    final now = DateTime.now();
    final summary = _buildSummary(backupData, objects, warnings);
    final manifest = <String, dynamic>{
      'type': 'starbank.webdav.v2.manifest',
      'formatVersion': webDavBackupV2FormatVersion,
      'appVersion': info.version,
      'createdAt': now.toIso8601String(),
      'snapshotHash': snapshotHash,
      'encryption': 'none',
      'sections': sections,
      'objects': objects.map((key, value) =>
          MapEntry(key, value.toManifestJson()..remove('bytes'))),
      'warnings': warnings.map((w) => w.toJson()).toList(),
      'summary': summary,
    };

    return V2Snapshot(
      manifest: manifest,
      objects: objects,
      warnings: warnings,
      backupData: backupData,
      snapshotHash: snapshotHash,
    );
  }

  Future<V2Snapshot> buildSnapshot({
    bool allowMissingMedia = false,
    V2Progress? onProgress,
    bool Function()? shouldCancel,
    bool includeLocalAppSettings = false,
  }) {
    return collectSnapshot(
      allowMissingMedia: allowMissingMedia,
      onProgress: onProgress,
      shouldCancel: shouldCancel,
      includeLocalAppSettings: includeLocalAppSettings,
    );
  }

  Future<String?> backup({
    required String deviceId,
    required int maxBackupCount,
    bool allowMissingMedia = false,
    V2Progress? onProgress,
    bool Function()? shouldCancel,
  }) async {
    final snapshot = await collectSnapshot(
      allowMissingMedia: allowMissingMedia,
      onProgress: onProgress,
      shouldCancel: shouldCancel,
    );

    _throwIfCancelled(shouldCancel);
    final latest = await readLatestManifest();
    if (latest != null && latest['snapshotHash'] == snapshot.snapshotHash) {
      return null;
    }

    _throwIfCancelled(shouldCancel);
    await _ensureRemoteDirs(snapshot.objects.keys);

    var uploaded = 0;
    for (final object in snapshot.objects.values) {
      _throwIfCancelled(shouldCancel);
      uploaded++;
      onProgress?.call('正在上传对象 $uploaded/${snapshot.objects.length}');
      await _uploadObjectIfNeeded(object);
    }

    onProgress?.call('正在发布备份清单');
    final timestamp = _formatTimestamp(DateTime.now());
    final randomPart = _randomToken();
    final manifestPath =
        '$webDavBackupV2ManifestDir/backup_${timestamp}_${deviceId}_$randomPart.manifest.json.gz';
    final manifestBytes =
        gzipBytes(utf8.encode(canonicalJson(snapshot.manifest)));
    await _write(manifestPath, Uint8List.fromList(manifestBytes));
    await _ensureRemoteSize(manifestPath, manifestBytes.length);

    onProgress?.call('正在清理旧备份');
    await cleanup(maxBackupCount: maxBackupCount);
    return manifestPath;
  }

  Future<String?> latestSnapshotHash({
    required V2RemoteList list,
    required V2RemoteRead read,
  }) async {
    final manifest = await readLatestManifest();
    return manifest?['snapshotHash']?.toString();
  }

  Future<String> uploadSnapshot({
    required V2Snapshot snapshot,
    required V2RemoteRead read,
    required V2RemoteWrite write,
    required V2RemoteMkdir mkdir,
    required V2RemoteList list,
    required V2Progress? onProgress,
    bool Function()? shouldCancel,
  }) async {
    _throwIfCancelled(shouldCancel);
    await _ensureRemoteDirs(snapshot.objects.keys);

    var uploaded = 0;
    for (final object in snapshot.objects.values) {
      _throwIfCancelled(shouldCancel);
      uploaded++;
      onProgress?.call('正在上传对象 $uploaded/${snapshot.objects.length}');
      await _uploadObjectIfNeeded(object);
    }

    _throwIfCancelled(shouldCancel);
    onProgress?.call('正在发布备份清单');
    final deviceId = await ensureDeviceId();
    final timestamp = _formatTimestamp(DateTime.now());
    final remotePath =
        '$webDavBackupV2ManifestDir/backup_${timestamp}_${deviceId}_${_randomToken()}.manifest.json.gz';
    final bytes = gzipBytes(utf8.encode(canonicalJson(snapshot.manifest)));
    await _write(remotePath, Uint8List.fromList(bytes));
    await _ensureRemoteSize(remotePath, bytes.length);
    return remotePath;
  }

  static void _throwIfCancelled(bool Function()? shouldCancel) {
    if (shouldCancel?.call() == true) {
      throw const WebDavBackupCancelledException();
    }
  }

  Future<void> cleanupRemote({
    required int maxCount,
    required V2RemoteList list,
    required V2RemoteRead read,
    required V2RemoteRemove remove,
  }) {
    return cleanup(maxBackupCount: maxCount);
  }

  Future<String> ensureDeviceId() async {
    const key = 'webdav_v2_device_id';
    final existing = _storage.settingsBox.get(key) as String?;
    if (existing != null && existing.isNotEmpty) return existing;
    final id = _randomToken() + _randomToken();
    await _storage.settingsBox.put(key, id);
    return id;
  }

  Future<Map<String, dynamic>?> readLatestManifest() async {
    final files = await listManifestFiles();
    if (files.isEmpty) return null;
    files.sort((a, b) => a.path.compareTo(b.path));
    return readManifest(files.last.path);
  }

  Future<Map<String, dynamic>> readManifest(String path) async {
    final bytes = await _read(path);
    final jsonString = utf8.decode(gunzipBytes(bytes));
    final raw = jsonDecode(jsonString);
    if (raw is! Map) {
      throw StateError('Invalid v2 manifest.');
    }
    final manifest = Map<String, dynamic>.from(raw);
    final version = manifest['formatVersion'];
    if (version is! int || version > webDavBackupV2FormatVersion) {
      throw StateError('备份格式版本过高，请升级应用后再恢复');
    }
    return manifest;
  }

  Future<List<V2RemoteFile>> listManifestFiles() async {
    try {
      final files = await _list(webDavBackupV2ManifestDir);
      return files.where((f) => f.path.endsWith('.manifest.json.gz')).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<V2ManifestInfo>> listRemoteManifests({
    required V2RemoteList list,
    required V2RemoteRead read,
  }) async {
    final files = await listManifestFiles();
    final result = <V2ManifestInfo>[];
    for (final file in files) {
      try {
        final manifest = await readManifest(file.path);
        final warnings = (manifest['warnings'] as List? ?? const [])
            .whereType<Map>()
            .map((w) => V2BackupWarning.fromJson(Map<String, dynamic>.from(w)))
            .toList();
        result.add(V2ManifestInfo(
          path: file.path,
          size: file.size,
          modifiedAt: file.modifiedAt,
          manifest: manifest,
          warnings: warnings,
        ));
      } catch (e) {
        debugPrint('跳过损坏的 v2 manifest ${file.path}: $e');
      }
    }
    result.sort((a, b) => a.path.compareTo(b.path));
    return result;
  }

  Future<V2RestoreBundle> restoreBundleFromRemote(
    String manifestPath, {
    V2Progress? onProgress,
  }) async {
    onProgress?.call('正在校验清单');
    final manifest = await readManifest(manifestPath);
    final objectBytes = <String, Uint8List>{};
    final objectMap = _manifestObjects(manifest);

    var downloaded = 0;
    for (final entry in objectMap.entries) {
      downloaded++;
      onProgress?.call('正在下载对象 $downloaded/${objectMap.length}');
      final meta = entry.value;
      final path = meta['path'] as String;
      final bytes = await _read(path);
      objectBytes[entry.key] = bytes;
    }

    return restoreBundleFromBytes(manifest, objectBytes);
  }

  Future<V2RestoreBundle> downloadRemoteBackupData({
    required String manifestPath,
    required V2RemoteRead read,
    required V2Progress? onProgress,
  }) {
    return restoreBundleFromRemote(manifestPath, onProgress: onProgress);
  }

  V2RestoreBundle restoreBundleFromBytes(
    Map<String, dynamic> manifest,
    Map<String, Uint8List> objectBytes,
  ) {
    final objectMap = _manifestObjects(manifest);
    final rawObjects = <String, dynamic>{};
    final mediaRaw = <String, Uint8List>{};

    for (final entry in objectMap.entries) {
      final hash = entry.key;
      final meta = entry.value;
      final bytes = objectBytes[hash];
      if (bytes == null) {
        throw StateError('缺少备份对象: $hash');
      }
      if (bytes.length != (meta['storedSize'] as num).toInt()) {
        throw StateError('备份对象大小不匹配: $hash');
      }

      final kind = meta['kind'] as String;
      final encoding = meta['contentEncoding'] as String;
      final Uint8List rawBytes;
      if (encoding == 'gzip') {
        rawBytes = Uint8List.fromList(gunzipBytes(bytes));
      } else {
        rawBytes = bytes;
      }
      final actualHash = sha256Hex(rawBytes);
      if (actualHash != hash) {
        throw StateError('备份对象校验失败: $hash');
      }

      if (kind == 'json') {
        rawObjects[hash] = jsonDecode(utf8.decode(rawBytes));
      } else if (kind == 'media') {
        mediaRaw[hash] = rawBytes;
      }
    }

    final sections = Map<String, dynamic>.from(manifest['sections'] as Map);
    final backupData = <String, dynamic>{};
    for (final entry in sections.entries) {
      backupData[entry.key] = _sectionFromManifest(entry.value, rawObjects);
    }
    _resolveMediaMarkers(backupData, mediaRaw);

    final warnings = (manifest['warnings'] as List? ?? const [])
        .whereType<Map>()
        .map((w) => V2BackupWarning.fromJson(Map<String, dynamic>.from(w)))
        .toList();

    return V2RestoreBundle(
      manifest: manifest,
      backupData: backupData,
      warnings: warnings,
    );
  }

  Future<File> createSafetySnapshot({
    required int keepCount,
    V2Progress? onProgress,
  }) async {
    final snapshot = await collectSnapshot(
      allowMissingMedia: true,
      onProgress: onProgress,
      includeLocalAppSettings: true,
    );
    final package = <String, dynamic>{
      'type': 'starbank.webdav.v2.safety',
      'formatVersion': webDavBackupV2FormatVersion,
      'createdAt': DateTime.now().toIso8601String(),
      'manifest': snapshot.manifest,
      'objects': snapshot.objects.map(
        (hash, object) => MapEntry(hash, base64Encode(object.bytes)),
      ),
    };
    final dir = await _safetyDir();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(
        '${dir.path}/restore_safety_${_formatTimestamp(DateTime.now())}.sbs.gz');
    await file.writeAsBytes(gzipBytes(utf8.encode(canonicalJson(package))));
    await _cleanupSafetySnapshots(dir, keepCount);
    return file;
  }

  Future<File> writeSafetySnapshot({
    bool allowMissingMedia = true,
    V2Progress? onProgress,
  }) {
    return createSafetySnapshot(
      keepCount: 3,
      onProgress: onProgress,
    );
  }

  Future<V2RestoreBundle> restoreBundleFromSafetySnapshot(File file) async {
    final bytes = await file.readAsBytes();
    final raw = jsonDecode(utf8.decode(gunzipBytes(bytes)));
    if (raw is! Map || raw['type'] != 'starbank.webdav.v2.safety') {
      throw StateError('Invalid local safety snapshot.');
    }
    final manifest = Map<String, dynamic>.from(raw['manifest'] as Map);
    final encodedObjects = Map<String, dynamic>.from(raw['objects'] as Map);
    final objectBytes = encodedObjects.map(
      (hash, value) => MapEntry(hash, base64Decode(value as String)),
    );
    return restoreBundleFromBytes(manifest, objectBytes);
  }

  Future<Map<String, dynamic>> readSafetySnapshot(File file) async {
    final bundle = await restoreBundleFromSafetySnapshot(file);
    return bundle.backupData;
  }

  Future<void> deleteManifestAndCleanup(
    String manifestPath, {
    required int maxBackupCount,
  }) async {
    await _remove(manifestPath);
    await cleanup(maxBackupCount: maxBackupCount);
  }

  Future<void> deleteManifestAndGc({
    required String manifestPath,
    required V2RemoteList list,
    required V2RemoteRead read,
    required V2RemoteRemove remove,
  }) {
    return deleteManifestAndCleanup(
      manifestPath,
      maxBackupCount: 0,
    );
  }

  Future<void> cleanup({required int maxBackupCount}) async {
    final manifests = await listManifestFiles();
    manifests.sort((a, b) => a.path.compareTo(b.path));

    final kept = <V2RemoteFile>[...manifests];
    if (maxBackupCount > 0 && kept.length > maxBackupCount) {
      final toDelete = kept.sublist(0, kept.length - maxBackupCount);
      for (final file in toDelete) {
        try {
          await _remove(file.path);
        } catch (_) {}
      }
      kept.removeRange(0, kept.length - maxBackupCount);
    }

    final referenced = <String>{};
    for (final file in kept) {
      try {
        final manifest = await readManifest(file.path);
        referenced.addAll(_manifestObjects(manifest).keys);
      } catch (_) {
        return; // Fail closed; never GC if a remaining manifest is unreadable.
      }
    }

    final dirs = await _listObjectPrefixDirs();
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    for (final dir in dirs) {
      List<V2RemoteFile> files;
      try {
        files = await _list(dir);
      } catch (_) {
        continue;
      }
      for (final file in files) {
        final hash = _hashFromObjectPath(file.path);
        if (hash == null || referenced.contains(hash)) continue;
        final modified = file.modifiedAt;
        if (modified == null || modified.isAfter(cutoff)) continue;
        try {
          await _remove(file.path);
        } catch (_) {}
      }
    }
  }

  Future<Map<String, dynamic>> _collectBackupData({
    bool includeLocalAppSettings = false,
  }) async {
    final backupData = <String, dynamic>{};

    backupData['user'] =
        _storage.userBox.values.map((e) => e.toJson()).toList();
    backupData['actions'] =
        _storage.actionBox.values.map((e) => e.toJson()).toList();
    backupData['logs'] = _storage.logBox.values.map((e) => e.toJson()).toList();
    backupData['products'] =
        _storage.productBox.values.map((e) => e.toJson()).toList();
    backupData['babies'] =
        _storage.babyBox.values.map((e) => e.toJson()).toList();

    try {
      final poopBox = await Hive.openBox<PoopRecord>('poop_records');
      backupData['poopRecords'] =
          poopBox.values.map((e) => e.toJson()).toList();
    } catch (_) {
      backupData['poopRecords'] = [];
    }

    try {
      final chatBox = await Hive.openBox<dynamic>('ai_chats');
      backupData['aiChats'] = chatBox.values
          .map((e) {
            try {
              if (e is Map) return Map<String, dynamic>.from(e);
              return (e as dynamic).toJson();
            } catch (_) {
              return null;
            }
          })
          .where((e) => e != null)
          .toList();
    } catch (_) {
      backupData['aiChats'] = [];
    }

    try {
      final openaiBox = await Hive.openBox<OpenAIConfig>('openai_configs');
      backupData['openaiConfigs'] =
          openaiBox.values.map((e) => e.toJson()).toList();
    } catch (_) {
      backupData['openaiConfigs'] = [];
    }

    backupData['genericSettings'] = _filteredSettings();
    if (includeLocalAppSettings) {
      try {
        final appSettingsBox = await Hive.openBox('app_settings');
        backupData['appSettings'] =
            Map<String, dynamic>.from(appSettingsBox.toMap());
      } catch (_) {}
    }
    try {
      final modeController = Get.find<AppModeController>();
      if (modeController.hasPassword) {
        backupData['passwordHash'] = modeController.passwordHash;
      }
    } catch (_) {}

    for (final entry in const {
      'ttsSettings': 'tts_settings',
      'poopAiSettings': 'poop_ai_settings',
      'storyGameConfig': 'story_game_config',
      'tuneHubConfig': 'tunehub_config',
      'playerSettings': 'player_settings',
      'hanziLearningConfig': 'hanzi_learning_config',
    }.entries) {
      try {
        final box = await Hive.openBox(entry.value);
        backupData[entry.key] = Map<String, dynamic>.from(box.toMap());
      } catch (_) {
        backupData[entry.key] = <String, dynamic>{};
      }
    }

    try {
      final storySessionBox = await Hive.openBox<dynamic>('story_sessions');
      backupData['storySessions'] = storySessionBox.values
          .map((e) {
            try {
              if (e is Map) return Map<String, dynamic>.from(e);
              return (e as dynamic).toJson();
            } catch (_) {
              return null;
            }
          })
          .where((e) => e != null)
          .toList();
    } catch (_) {
      backupData['storySessions'] = [];
    }

    try {
      final riddleBox = await Hive.openBox('custom_riddles');
      backupData['customRiddles'] = riddleBox.values.toList();
    } catch (_) {
      backupData['customRiddles'] = [];
    }

    backupData['musicPlaylists'] = _storage.playlistBox.values.map((p) {
      return {
        'id': p.id,
        'name': p.name,
        'coverUrl': p.coverUrl,
        'createdAt': p.createdAt.toIso8601String(),
        'tracks': p.tracks.map((t) => t.toJson()).toList(),
      };
    }).toList();

    try {
      backupData['newYearStories'] =
          await StoryManagementService.instance.backupStories();
    } catch (_) {
      backupData['newYearStories'] = [];
    }

    try {
      if (Get.isRegistered<QuizService>()) {
        final quizService = Get.find<QuizService>();
        backupData['quizQuestions'] = await quizService.backupQuestions();
        if (quizService.config.value != null) {
          backupData['quizConfig'] = quizService.config.value!.toJson();
        }
      }
    } catch (_) {
      backupData['quizQuestions'] = [];
    }

    try {
      if (Get.isRegistered<EncyclopediaService>()) {
        final data = await Get.find<EncyclopediaService>().exportData();
        data.remove('explanationCaches');
        backupData['encyclopediaData'] = data;
      }
    } catch (_) {}

    try {
      final cfttsBox = await Hive.openBox<CfttsConfig>('cftts_config_box');
      backupData['cfttsConfigBox'] =
          cfttsBox.values.map((e) => e.toJson()).toList();
    } catch (_) {
      backupData['cfttsConfigBox'] = [];
    }

    try {
      final openAITtsBox =
          await Hive.openBox<OpenAITtsConfig>('openai_tts_config_box');
      backupData['openAITtsConfigBox'] =
          openAITtsBox.values.map((e) => e.toJson()).toList();
    } catch (_) {
      backupData['openAITtsConfigBox'] = [];
    }

    return backupData;
  }

  Map<String, dynamic> _filteredSettings() {
    final result = <String, dynamic>{};
    for (final key in settingsWhitelist) {
      if (_storage.settingsBox.containsKey(key)) {
        result[key] = _storage.settingsBox.get(key);
      }
    }
    return result;
  }

  Future<void> _extractWhitelistedMedia(
    Map<String, dynamic> data,
    Map<String, V2BackupObject> objects,
    List<V2BackupWarning> warnings, {
    required bool allowMissingMedia,
    bool Function()? shouldCancel,
  }) async {
    Future<dynamic> media(
      dynamic value, {
      required String section,
      required String record,
      required String field,
      required String restoreStyle,
    }) {
      return _mediaValueToMarker(
        value,
        objects,
        warnings,
        section: section,
        record: record,
        field: field,
        restoreStyle: restoreStyle,
      );
    }

    for (final item in (data['user'] as List? ?? const [])) {
      _throwIfCancelled(shouldCancel);
      if (item is Map) {
        item['avatarPath'] = await media(
          item['avatarPath'],
          section: 'core.user',
          record: item['name']?.toString() ?? 'user',
          field: 'avatarPath',
          restoreStyle: 'rawBase64',
        );
      }
    }

    for (final item in (data['babies'] as List? ?? const [])) {
      _throwIfCancelled(shouldCancel);
      if (item is Map) {
        item['avatarPath'] = await media(
          item['avatarPath'],
          section: 'core.babies',
          record: item['id']?.toString() ?? item['name']?.toString() ?? 'baby',
          field: 'avatarPath',
          restoreStyle: 'rawBase64',
        );
      }
    }

    for (final item in (data['products'] as List? ?? const [])) {
      _throwIfCancelled(shouldCancel);
      if (item is Map) {
        item['imagePath'] = await media(
          item['imagePath'],
          section: 'core.products',
          record: item['name']?.toString() ?? 'product',
          field: 'imagePath',
          restoreStyle: 'rawBase64',
        );
      }
    }

    for (final item in (data['quizQuestions'] as List? ?? const [])) {
      _throwIfCancelled(shouldCancel);
      if (item is Map) {
        item['imagePath'] = await media(
          item['imagePath'],
          section: 'quiz.quizQuestions',
          record: item['id']?.toString() ?? item['question']?.toString() ?? '',
          field: 'imagePath',
          restoreStyle: 'dataUri',
        );
      }
    }

    for (final story in (data['newYearStories'] as List? ?? const [])) {
      _throwIfCancelled(shouldCancel);
      if (story is! Map || story['pages'] is! String) continue;
      try {
        final pagesRaw = jsonDecode(story['pages'] as String);
        if (pagesRaw is! List) continue;
        for (var i = 0; i < pagesRaw.length; i++) {
          final page = pagesRaw[i];
          if (page is Map) {
            page['image'] = await media(
              page['image'],
              section: 'story.newYearStories',
              record: '${story['id'] ?? story['title'] ?? 'story'}#$i',
              field: 'pages[$i].image',
              restoreStyle: 'dataUri',
            );
          }
        }
        story['pages'] = jsonEncode(pagesRaw);
      } catch (_) {}
    }

    if (!allowMissingMedia && warnings.isNotEmpty) {
      // The caller will decide whether to continue after showing warnings.
    }
  }

  Future<dynamic> _mediaValueToMarker(
    dynamic value,
    Map<String, V2BackupObject> objects,
    List<V2BackupWarning> warnings, {
    required String section,
    required String record,
    required String field,
    required String restoreStyle,
  }) async {
    if (value is! String || value.isEmpty) return value;
    if (value.startsWith('assets/') ||
        value.startsWith('http://') ||
        value.startsWith('https://')) {
      return value;
    }

    Uint8List? raw;
    var mimeType = 'image/png';
    if (value.startsWith('data:image')) {
      final comma = value.indexOf(',');
      if (comma <= 0) return value;
      final header = value.substring(0, comma);
      final match = RegExp(r'data:([^;]+);base64').firstMatch(header);
      mimeType = match?.group(1) ?? mimeType;
      raw = base64Decode(value.substring(comma + 1));
    } else if (_looksLikeBase64Image(value)) {
      raw = base64Decode(value);
    } else {
      try {
        final file = File(value);
        if (await file.exists()) {
          raw = await file.readAsBytes();
          mimeType = _mimeTypeFromPath(value);
        } else {
          warnings.add(V2BackupWarning(
            section: section,
            record: record,
            field: field,
            originalPath: value,
            reason: '文件不存在',
          ));
          return value;
        }
      } catch (e) {
        warnings.add(V2BackupWarning(
          section: section,
          record: record,
          field: field,
          originalPath: value,
          reason: '文件不可读: $e',
        ));
        return value;
      }
    }

    final hash = sha256Hex(raw);
    objects.putIfAbsent(hash, () => _mediaObject(hash, raw!, mimeType));
    return {
      '__starbankMediaRef': hash,
      'mimeType': mimeType,
      'restoreStyle': restoreStyle,
      'originalPath': value,
    };
  }

  dynamic _sectionToManifest(
    String key,
    dynamic value,
    Map<String, V2BackupObject> objects,
  ) {
    if (value is List) {
      return {
        'kind': 'list',
        'items':
            value.map((item) => _jsonRef('$key.item', item, objects)).toList(),
      };
    }
    return {
      'kind': 'value',
      'object': _jsonRef(key, value, objects),
    };
  }

  dynamic _sectionFromManifest(
      dynamic section, Map<String, dynamic> rawObjects) {
    final map = Map<String, dynamic>.from(section as Map);
    if (map['kind'] == 'list') {
      return (map['items'] as List)
          .map((item) => rawObjects[(item as Map)['hash']])
          .toList();
    }
    final object = Map<String, dynamic>.from(map['object'] as Map);
    return rawObjects[object['hash']];
  }

  Map<String, dynamic> _jsonRef(
    String label,
    dynamic value,
    Map<String, V2BackupObject> objects,
  ) {
    final jsonBytes = utf8.encode(canonicalJson(value));
    final hash = sha256Hex(jsonBytes);
    objects.putIfAbsent(hash, () => _jsonObject(hash, jsonBytes));
    return {'hash': hash, 'label': label};
  }

  V2BackupObject _jsonObject(String hash, List<int> rawBytes) {
    final stored = gzipBytes(rawBytes);
    return V2BackupObject(
      hash: hash,
      kind: 'json',
      contentType: 'application/json',
      contentEncoding: 'gzip',
      rawSize: rawBytes.length,
      storedSize: stored.length,
      path: _objectPath(hash, 'json.gz'),
      bytes: Uint8List.fromList(stored),
    );
  }

  V2BackupObject _mediaObject(
      String hash, Uint8List rawBytes, String mimeType) {
    return V2BackupObject(
      hash: hash,
      kind: 'media',
      contentType: mimeType,
      contentEncoding: 'identity',
      rawSize: rawBytes.length,
      storedSize: rawBytes.length,
      path: _objectPath(hash, _extensionForMime(mimeType)),
      bytes: rawBytes,
    );
  }

  Future<void> _ensureRemoteDirs(Iterable<String> hashes) async {
    for (final dir in const [
      '/starbank',
      webDavBackupV2Root,
      webDavBackupV2ManifestDir,
      webDavBackupV2ObjectDir,
    ]) {
      try {
        await _mkdir(dir);
      } catch (_) {}
    }
    for (final hash in hashes) {
      try {
        await _mkdir('$webDavBackupV2ObjectDir/${hash.substring(0, 2)}');
      } catch (_) {}
    }
  }

  Future<void> _uploadObjectIfNeeded(V2BackupObject object) async {
    final existing = await _remoteFile(object.path);
    if (existing != null && existing.size == object.storedSize) {
      return;
    }
    await _write(object.path, object.bytes);
    await _ensureRemoteSize(object.path, object.storedSize);
  }

  Future<void> _ensureRemoteSize(String path, int expectedSize) async {
    final file = await _remoteFile(path);
    if (file == null || file.size != expectedSize) {
      throw StateError('远端文件大小校验失败: $path');
    }
  }

  Future<V2RemoteFile?> _remoteFile(String path) async {
    try {
      final dir = path.substring(0, path.lastIndexOf('/'));
      final files = await _list(dir);
      for (final file in files) {
        if (file.path == path) return file;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<String>> _listObjectPrefixDirs() async {
    try {
      final files = await _list(webDavBackupV2ObjectDir);
      return files
          .map((f) => f.path)
          .where((p) => RegExp(r'/[a-f0-9]{2}$').hasMatch(p))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<Directory> _safetyDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return Directory('${dir.path}/restore_safety_snapshots');
  }

  Future<void> _cleanupSafetySnapshots(Directory dir, int keepCount) async {
    if (keepCount <= 0) return;
    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.sbs.gz'))
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    while (files.length > keepCount) {
      final file = files.removeAt(0);
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  Map<String, Map<String, dynamic>> _manifestObjects(
    Map<String, dynamic> manifest,
  ) {
    final objects = Map<String, dynamic>.from(manifest['objects'] as Map);
    return objects.map(
      (key, value) => MapEntry(key, Map<String, dynamic>.from(value as Map)),
    );
  }

  Map<String, dynamic> _buildSummary(
    Map<String, dynamic> backupData,
    Map<String, V2BackupObject> objects,
    List<V2BackupWarning> warnings,
  ) {
    int count(String key) {
      final value = backupData[key];
      return value is List
          ? value.length
          : value == null
              ? 0
              : 1;
    }

    final mediaCount = objects.values.where((o) => o.kind == 'media').length;
    final jsonCount = objects.values.where((o) => o.kind == 'json').length;
    final rawSize = objects.values.fold<int>(0, (sum, o) => sum + o.rawSize);
    final storedSize =
        objects.values.fold<int>(0, (sum, o) => sum + o.storedSize);
    return {
      'userCount': count('user'),
      'babyCount': count('babies'),
      'logCount': count('logs'),
      'productCount': count('products'),
      'storyCount': count('newYearStories'),
      'quizQuestionCount': count('quizQuestions'),
      'jsonObjectCount': jsonCount,
      'mediaObjectCount': mediaCount,
      'rawSize': rawSize,
      'storedSize': storedSize,
      'warningCount': warnings.length,
    };
  }

  static String canonicalJson(dynamic value) => jsonEncode(_canonical(value));

  static dynamic _canonical(dynamic value) {
    if (value is Map) {
      final keys = value.keys.map((e) => e.toString()).toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) {
      return value.map(_canonical).toList();
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    return value;
  }

  static String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

  static List<int> gzipBytes(List<int> bytes) => GZipEncoder().encode(bytes);

  static List<int> gunzipBytes(List<int> bytes) =>
      GZipDecoder().decodeBytes(bytes);

  static void _resolveMediaMarkers(
      dynamic value, Map<String, Uint8List> media) {
    if (value is Map) {
      if (value.containsKey('__starbankMediaRef')) {
        final hash = value['__starbankMediaRef'] as String;
        final bytes = media[hash];
        if (bytes == null) {
          throw StateError('缺少媒体对象: $hash');
        }
        final base64 = base64Encode(bytes);
        final style = value['restoreStyle']?.toString() ?? 'dataUri';
        if (style == 'rawBase64') {
          value
            ..clear()
            ..['__resolvedMediaValue'] = base64;
        } else {
          final mimeType = value['mimeType']?.toString() ?? 'image/png';
          value
            ..clear()
            ..['__resolvedMediaValue'] = 'data:$mimeType;base64,$base64';
        }
        return;
      }
      for (final entry in value.entries.toList()) {
        _resolveMediaMarkers(entry.value, media);
        final child = entry.value;
        if (child is Map && child.containsKey('__resolvedMediaValue')) {
          value[entry.key] = child['__resolvedMediaValue'];
        }
      }
    } else if (value is List) {
      for (var i = 0; i < value.length; i++) {
        _resolveMediaMarkers(value[i], media);
        final child = value[i];
        if (child is Map && child.containsKey('__resolvedMediaValue')) {
          value[i] = child['__resolvedMediaValue'];
        }
      }
    }
  }

  static String _objectPath(String hash, String extension) =>
      '$webDavBackupV2ObjectDir/${hash.substring(0, 2)}/$hash.$extension';

  static String _extensionForMime(String mime) {
    if (mime.contains('jpeg') || mime.contains('jpg')) return 'jpg';
    if (mime.contains('webp')) return 'webp';
    if (mime.contains('gif')) return 'gif';
    return 'png';
  }

  static String _mimeTypeFromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/png';
  }

  static bool _looksLikeBase64Image(String value) {
    if (value.length < 100) return false;
    return RegExp(r'^[A-Za-z0-9+/=\r\n]+$').hasMatch(value);
  }

  static String _formatTimestamp(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}${two(dt.month)}${two(dt.day)}${two(dt.hour)}${two(dt.minute)}${two(dt.second)}';
  }

  static String _randomToken() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  }

  static String? _hashFromObjectPath(String path) {
    final name = path.split('/').last;
    final match = RegExp(r'^([a-f0-9]{64})\.').firstMatch(name);
    return match?.group(1);
  }
}
