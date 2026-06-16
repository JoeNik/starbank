import 'package:get/get.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;
import 'package:hive/hive.dart';
import 'dart:async';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'storage_service.dart';
import 'webdav_backup_v2_service.dart';
import '../widgets/toast_utils.dart';
import '../models/user_profile.dart';
import '../models/baby.dart';
import '../models/action_item.dart';
import '../models/log.dart';
import '../models/product.dart';
import '../controllers/app_mode_controller.dart';
import '../models/poop_record.dart';
import '../models/ai_chat.dart';
import '../models/openai_config.dart';
import '../services/openai_service.dart';
import '../models/story_session.dart';
import '../models/music/playlist.dart';
import '../models/music/music_track.dart';
import '../models/story_game_config.dart';
import '../services/story_management_service.dart';
import '../services/quiz_service.dart';
import '../models/quiz_config.dart';
import '../models/hanzi_learning_config.dart';
import '../models/cftts_config.dart';
import '../models/openai_tts_config.dart';
import '../services/tts_service.dart';
import '../services/encyclopedia_service.dart';
import '../models/encyclopedia_question.dart';
import '../models/encyclopedia_config.dart';
import '../models/encyclopedia_explanation_cache.dart';
import '../models/growth_record.dart';
import '../models/milestone_record.dart';

/// 备份文件信息
class BackupFileInfo {
  final String path; // 完整路径（用于操作）
  final String filename; // 文件名（用于显示）
  final int size; // 文件大小（字节）
  final String strategy; // full / v2
  final int warningCount;
  final Map<String, dynamic>? summary;

  BackupFileInfo({
    required this.path,
    required this.filename,
    required this.size,
    this.strategy = 'full',
    this.warningCount = 0,
    this.summary,
  });

  /// 格式化文件大小显示
  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / 1024 / 1024).toStringAsFixed(2)} MB';
  }
}

enum WebDavBackupStrategy { full, efficientV2 }

/// WebDAV备份服务
class WebDavService extends GetxService {
  webdav.Client? _client;
  final StorageService _storage = Get.find<StorageService>();

  final RxString currentUrl = ''.obs;
  final RxString currentUser = ''.obs;
  final Rx<WebDavBackupStrategy> backupStrategy = WebDavBackupStrategy.full.obs;
  final RxString operationProgress = ''.obs;
  final RxBool isOperationRunning = false.obs;
  final RxBool isBackupRunning = false.obs;
  bool _backupCancelRequested = false;
  static const int _v2RemoteMaxAttempts = 3;
  static const Duration _v2RemoteMutationPause = Duration(milliseconds: 120);
  late final WebDavBackupV2Service _v2 = WebDavBackupV2Service(
    storage: _storage,
    read: _readRemoteV2,
    write: _writeRemoteV2,
    remove: _removeRemoteV2,
    mkdir: _mkdirRemoteV2,
    list: _listRemoteV2,
  );

  @override
  void onInit() {
    super.onInit();
    _loadConfig();
  }

  void _loadConfig() {
    final box = _storage.settingsBox;
    final url = box.get('webdav_url') as String?;
    final user = box.get('webdav_user') as String?;
    final pwd = box.get('webdav_pwd') as String?;

    if (url != null && user != null && pwd != null) {
      currentUrl.value = url;
      currentUser.value = user;
      initClient(url, user, pwd, save: false);
    }

    final strategy = box.get('webdav_backup_strategy') as String?;
    backupStrategy.value = strategy == 'v2'
        ? WebDavBackupStrategy.efficientV2
        : WebDavBackupStrategy.full;
  }

  /// 初始化WebDAV客户端
  void initClient(
    String url,
    String username,
    String password, {
    bool save = true,
  }) {
    _client = webdav.newClient(
      url,
      user: username,
      password: password,
      debug: false,
    );

    if (save) {
      final box = _storage.settingsBox;
      box.put('webdav_url', url);
      box.put('webdav_user', username);
      box.put('webdav_pwd', password);

      currentUrl.value = url;
      currentUser.value = username;
    }
  }

  /// 获取缓存的密码
  String? getCachedPassword() {
    return _storage.settingsBox.get('webdav_pwd') as String?;
  }

  /// 是否已配置WebDAV
  bool get isConfigured => _client != null;

  bool get isEfficientBackupSupported => !kIsWeb;

  Future<void> setBackupStrategy(WebDavBackupStrategy strategy) async {
    backupStrategy.value = strategy;
    await _storage.settingsBox.put(
      'webdav_backup_strategy',
      strategy == WebDavBackupStrategy.efficientV2 ? 'v2' : 'full',
    );
  }

  bool get hasAcknowledgedV2Experiment =>
      _storage.settingsBox.get('webdav_v2_experiment_ack') == true;

  Future<void> acknowledgeV2Experiment() async {
    await _storage.settingsBox.put('webdav_v2_experiment_ack', true);
  }

  void cancelBackup() {
    if (!isBackupRunning.value) return;
    _backupCancelRequested = true;
    operationProgress.value = '正在取消备份';
  }

  bool get _shouldCancelBackup => _backupCancelRequested;

  void _throwIfBackupCancelled() {
    if (_shouldCancelBackup) {
      throw const WebDavBackupCancelledException();
    }
  }

  /// 备份所有Hive数据到WebDAV
  Future<bool> backupData() async {
    if (_client == null) {
      ToastUtils.showError('请先配置WebDAV');
      return false;
    }
    if (isOperationRunning.value) {
      ToastUtils.showWarning('已有备份或恢复任务正在进行');
      return false;
    }
    if (backupStrategy.value == WebDavBackupStrategy.efficientV2) {
      return _backupDataV2();
    }

    try {
      _backupCancelRequested = false;
      isOperationRunning.value = true;
      isBackupRunning.value = true;
      operationProgress.value = '正在采集数据';
      _checkAdapters();
      final Map<String, dynamic> backupData = {};

      // Convert objects to JSON maps
      backupData['user'] =
          _storage.userBox.values.map((e) => e.toJson()).toList();
      backupData['actions'] =
          _storage.actionBox.values.map((e) => e.toJson()).toList();
      backupData['logs'] =
          _storage.logBox.values.map((e) => e.toJson()).toList();
      backupData['products'] =
          _storage.productBox.values.map((e) => e.toJson()).toList();
      backupData['babies'] =
          _storage.babyBox.values.map((e) => e.toJson()).toList();

      // 备份便便记录
      try {
        if (!Hive.isAdapterRegistered(11)) {
          Hive.registerAdapter(PoopRecordAdapter());
        }
        final poopBox = await Hive.openBox<PoopRecord>('poop_records');
        final recordCount = poopBox.length;
        debugPrint('Backup: Found $recordCount poop records');

        if (recordCount > 0) {
          List<Map<String, dynamic>> serialized = [];
          for (var record in poopBox.values) {
            try {
              serialized.add(record.toJson());
            } catch (e) {
              debugPrint('Backup skip invalid record: $e');
            }
          }
          backupData['poopRecords'] = serialized;
          debugPrint(
              'Backup: Successfully serialized ${serialized.length} records');
        } else {
          backupData['poopRecords'] = [];
        }
      } catch (e) {
        debugPrint('备份便便记录失败: $e');
        ToastUtils.showError('备份便便记录失败: $e');
      }

      // 备份生长记录和大事记（主应用结构化数据，使用主备份逻辑）
      try {
        backupData['growthRecords'] =
            _storage.growthRecordBox.values.map((e) => e.toJson()).toList();
        backupData['milestoneRecords'] =
            _storage.milestoneRecordBox.values.map((e) => e.toJson()).toList();
      } catch (e) {
        print('备份宝宝记录失败: $e');
      }

      // 备份 AI 聊天记录
      try {
        final chatBox = await Hive.openBox<dynamic>('ai_chats');
        backupData['aiChats'] = chatBox.values
            .map((e) {
              try {
                if (e is Map) return e;
                return (e as dynamic).toJson();
              } catch (e) {
                print('Skipping invalid AI chat: $e');
                return null;
              }
            })
            .where((e) => e != null)
            .toList();
      } catch (e) {
        print('备份 AI 聊天记录失败: $e');
      }

      // 备份 OpenAI 配置
      try {
        final openaiBox = await Hive.openBox<OpenAIConfig>('openai_configs');
        backupData['openaiConfigs'] =
            openaiBox.values.map((e) => e.toJson()).toList();
      } catch (e) {
        print('备份 OpenAI 配置失败: $e');
      }

      // 备份应用设置（包括 TTS、便便 AI 设置等）
      try {
        final appSettingsBox = await Hive.openBox('app_settings');
        backupData['appSettings'] =
            Map<String, dynamic>.from(appSettingsBox.toMap());
      } catch (e) {
        print('备份应用设置失败: $e');
      }

      try {
        final ttsSettingsBox = await Hive.openBox('tts_settings');
        backupData['ttsSettings'] =
            Map<String, dynamic>.from(ttsSettingsBox.toMap());
      } catch (e) {
        print('备份 TTS 设置失败: $e');
      }

      try {
        final poopAiSettingsBox = await Hive.openBox('poop_ai_settings');
        backupData['poopAiSettings'] =
            Map<String, dynamic>.from(poopAiSettingsBox.toMap());
      } catch (e) {
        print('备份便便 AI 设置失败: $e');
      }

      // 备份故事游戏配置
      try {
        final storyConfigBox = await Hive.openBox('story_game_config');
        backupData['storyGameConfig'] =
            Map<String, dynamic>.from(storyConfigBox.toMap());
      } catch (e) {
        print('备份故事游戏配置失败: $e');
      }

      // 备份故事游戏会话记录
      try {
        final storySessionBox = await Hive.openBox<dynamic>('story_sessions');
        backupData['storySessions'] = storySessionBox.values
            .map((e) {
              try {
                if (e is Map) return e;
                return (e as dynamic).toJson();
              } catch (e) {
                print('Skipping invalid story session: $e');
                return null;
              }
            })
            .where((e) => e != null)
            .toList();
      } catch (e) {
        print('备份故事游戏会话失败: $e');
      }

      // 备份自定义脑筋急转弯
      try {
        final riddleBox = await Hive.openBox('custom_riddles');
        if (riddleBox.isNotEmpty) {
          backupData['customRiddles'] = riddleBox.values.toList();
        }
      } catch (e) {
        print('备份自定义脑筋急转弯失败: $e');
      }

      // 备份音乐数据 (歌单 & 收藏)
      try {
        // 使用 StorageService 中的实例，确保 Box 名称一致 ('playlistBox')
        final playlistBox = _storage.playlistBox;
        backupData['musicPlaylists'] = playlistBox.values.map((p) {
          return {
            'id': p.id,
            'name': p.name,
            'coverUrl': p.coverUrl,
            'createdAt': p.createdAt.toIso8601String(),
            'tracks': p.tracks.map((t) => t.toJson()).toList(),
          };
        }).toList();
      } catch (e) {
        print('备份音乐数据失败: $e');
      }

      // 备份通用设置 (包括 TuneHub Config)
      try {
        final settingsBox = await Hive.openBox('settings');
        // 过滤掉不应该备份的本地配置（如 WebDAV 自身的账号密码，避免恢复时覆盖当前连接信息导致连接断开）
        // 但用户可能希望备份这些以便迁移。折中方案：全部备份，恢复时让用户小心。
        // 或者保留 WebDAV 配置不覆盖。这里先全部备份。
        backupData['genericSettings'] =
            Map<String, dynamic>.from(settingsBox.toMap());
      } catch (e) {
        print('备份通用设置失败: $e');
      }

      // 备份 TuneHub 设置
      try {
        final tuneHubBox = await Hive.openBox('tunehub_config');
        backupData['tuneHubConfig'] =
            Map<String, dynamic>.from(tuneHubBox.toMap());
      } catch (e) {
        print('备份 TuneHub 设置失败: $e');
      }

      // 备份播放器设置
      try {
        final playerSettingsBox = await Hive.openBox('player_settings');
        backupData['playerSettings'] =
            Map<String, dynamic>.from(playerSettingsBox.toMap());
      } catch (e) {
        print('备份播放器设置失败: $e');
      }

      // 备份密码哈希
      try {
        final modeController = Get.find<AppModeController>();
        await modeController.ensureInitialized(); // 🔧 确保初始化完成
        if (modeController.hasPassword) {
          backupData['passwordHash'] = modeController.passwordHash;
        }
      } catch (_) {}

      // 备份新年故事 (NewYearStory)
      try {
        final storyService = StoryManagementService.instance;
        backupData['newYearStories'] = await storyService.backupStories();
      } catch (e) {
        print('备份新年故事失败: $e');
      }

      // 备份新年问答 (Quiz)
      try {
        if (Get.isRegistered<QuizService>()) {
          final quizService = Get.find<QuizService>();
          backupData['quizQuestions'] = await quizService.backupQuestions();
          if (quizService.config.value != null) {
            backupData['quizConfig'] = quizService.config.value!.toJson();
          }
        }
      } catch (e) {
        print('备份新年问答失败: $e');
      }

      // 备份汉字学习配置
      try {
        final hanziBox = await Hive.openBox('hanzi_learning_config');
        backupData['hanziLearningConfig'] =
            Map<String, dynamic>.from(hanziBox.toMap());
      } catch (e) {
        print('备份汉字学习配置失败: $e');
      }

      // 备份生活科学百科
      try {
        if (Get.isRegistered<EncyclopediaService>()) {
          final encyclopediaService = Get.find<EncyclopediaService>();
          final data = await encyclopediaService.exportData();
          backupData['encyclopediaData'] = data;
        }
      } catch (e) {
        print('备份生活科学百科失败: $e');
      }

      // 备份 CFTTS 配置
      try {
        final cfttsBox = await Hive.openBox<CfttsConfig>('cftts_config_box');
        backupData['cfttsConfigBox'] =
            cfttsBox.values.map((e) => e.toJson()).toList();
      } catch (e) {
        print('备份 CFTTS 配置失败: $e');
      }

      // 备份 OpenAI TTS Provider 配置
      try {
        final openAITtsBox =
            await Hive.openBox<OpenAITtsConfig>('openai_tts_config_box');
        backupData['openAITtsConfigBox'] =
            openAITtsBox.values.map((e) => e.toJson()).toList();
      } catch (e) {
        print('备份 OpenAI TTS 配置失败: $e');
      }

      backupData['timestamp'] = DateTime.now().toIso8601String();

      _throwIfBackupCancelled();
      operationProgress.value = '正在压缩备份';
      final jsonString = jsonEncode(backupData);
      final jsonBytes = utf8.encode(jsonString);

      // 压缩数据 (GZIP)
      final compressedBytes = GZipEncoder().encode(jsonBytes);

      // Timestamp based filename: yyyyMMddHH
      final now = DateTime.now();
      final timestamp =
          "${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}";

      // 使用 .json.gz 后缀
      final remotePath = '/starbank/backup_$timestamp.json.gz';

      // Ensure directory exists
      try {
        await _client!.mkdir('/starbank');
      } catch (_) {}

      _throwIfBackupCancelled();
      operationProgress.value = '正在上传备份';
      // upload
      await _client!.write(remotePath, Uint8List.fromList(compressedBytes));

      _throwIfBackupCancelled();
      operationProgress.value = '正在清理旧备份';
      // 清理旧备份
      await _cleanupOldBackups();

      Get.back();
      ToastUtils.showSuccess('备份已存至: $remotePath');
      return true;
    } on WebDavBackupCancelledException {
      ToastUtils.showWarning('已取消备份');
      return false;
    } catch (e) {
      ToastUtils.showError('备份失败: $e');
      return false;
    } finally {
      isOperationRunning.value = false;
      isBackupRunning.value = false;
      _backupCancelRequested = false;
      operationProgress.value = '';
    }
  }

  Future<bool> _backupDataV2() async {
    if (!isEfficientBackupSupported) {
      ToastUtils.showError('高效备份暂不支持 Web 平台');
      return false;
    }

    try {
      _backupCancelRequested = false;
      isOperationRunning.value = true;
      isBackupRunning.value = true;
      _checkAdapters();
      V2Snapshot snapshot;
      try {
        snapshot = await _v2.buildSnapshot(
          allowMissingMedia: false,
          onProgress: (message) => operationProgress.value = message,
          shouldCancel: () => _shouldCancelBackup,
        );
      } on V2MissingMediaException catch (e) {
        final shouldContinue =
            await _confirmContinueWithMissingMedia(e.warnings);
        if (!shouldContinue) {
          ToastUtils.showWarning('已取消备份');
          return false;
        }
        snapshot = await _v2.buildSnapshot(
          allowMissingMedia: true,
          onProgress: (message) => operationProgress.value = message,
          shouldCancel: () => _shouldCancelBackup,
        );
      }

      _throwIfBackupCancelled();
      final latestHash = await _v2.latestSnapshotHash(
        list: _listRemoteV2,
        read: _readRemoteV2,
      );
      if (latestHash == snapshot.snapshotHash) {
        ToastUtils.showSuccess('自上次高效备份后数据无变化');
        return true;
      }

      final remotePath = await _v2.uploadSnapshot(
        snapshot: snapshot,
        read: _readRemoteV2,
        write: _writeRemoteV2,
        mkdir: _mkdirRemoteV2,
        list: _listRemoteV2,
        onProgress: (message) => operationProgress.value = message,
        shouldCancel: () => _shouldCancelBackup,
      );
      _throwIfBackupCancelled();
      operationProgress.value = '正在清理旧备份';
      await _v2.cleanupRemote(
        maxCount: maxBackupCount,
        list: _listRemoteV2,
        read: _readRemoteV2,
        remove: _removeRemoteV2,
      );
      Get.back();
      ToastUtils.showSuccess('高效备份已存至: $remotePath');
      return true;
    } on WebDavBackupCancelledException {
      ToastUtils.showWarning('已取消备份');
      return false;
    } catch (e) {
      ToastUtils.showError('高效备份失败: $e');
      return false;
    } finally {
      isOperationRunning.value = false;
      isBackupRunning.value = false;
      _backupCancelRequested = false;
      operationProgress.value = '';
    }
  }

  Future<bool> _confirmContinueWithMissingMedia(
    List<V2BackupWarning> warnings,
  ) async {
    final preview = warnings.take(5).map((w) {
      final label = w.record.isEmpty ? w.field : '${w.record} / ${w.field}';
      return '$label\n${w.originalPath}';
    }).join('\n\n');
    final result = await Get.defaultDialog<bool>(
      title: '发现缺失媒体',
      middleText: '有 ${warnings.length} 个图片文件缺失或不可读。默认取消备份。\n\n$preview',
      textConfirm: '忽略这些媒体并继续',
      textCancel: '取消备份',
      confirmTextColor: Colors.white,
      onConfirm: () {
        Get.back(result: true);
      },
      onCancel: () {
        Get.back(result: false);
      },
    );
    return result == true;
  }

  Future<Uint8List> _readRemoteV2(String path) async {
    return _runRemoteV2(
      operation: '读取',
      path: path,
      action: () async => Uint8List.fromList(await _client!.read(path)),
    );
  }

  Future<void> _writeRemoteV2(String path, Uint8List bytes) async {
    await _runRemoteV2(
      operation: '上传',
      path: path,
      action: () => _client!.write(path, bytes),
    );
    await Future.delayed(_v2RemoteMutationPause);
  }

  Future<void> _removeRemoteV2(String path) async {
    await _runRemoteV2(
      operation: '删除',
      path: path,
      action: () => _client!.remove(path),
    );
  }

  Future<void> _mkdirRemoteV2(String path) async {
    await _runRemoteV2(
      operation: '创建目录',
      path: path,
      action: () => _client!.mkdir(path),
    );
    await Future.delayed(_v2RemoteMutationPause);
  }

  Future<List<V2RemoteFile>> _listRemoteV2(String path) async {
    final files = await _runRemoteV2(
      operation: '列目录',
      path: path,
      action: () => _client!.readDir(path),
    );
    return files
        .map((f) => V2RemoteFile(
              path: f.path ?? '',
              size: f.size ?? 0,
              modifiedAt: _remoteModifiedAt(f),
            ))
        .toList();
  }

  Future<T> _runRemoteV2<T>({
    required String operation,
    required String path,
    required Future<T> Function() action,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= _v2RemoteMaxAttempts; attempt++) {
      try {
        _throwIfBackupCancelled();
        return await action();
      } on WebDavBackupCancelledException {
        rethrow;
      } catch (e) {
        lastError = e;
        if (!_isRetryableV2RemoteError(e) ||
            attempt == _v2RemoteMaxAttempts) {
          break;
        }
        final delay = Duration(milliseconds: 450 * attempt);
        debugPrint(
          'WebDAV v2 $operation failed for $path '
          '(attempt $attempt/$_v2RemoteMaxAttempts): $e; retrying...',
        );
        await Future.delayed(delay);
      }
    }

    throw V2RemoteOperationException(
      operation: operation,
      path: path,
      cause: lastError ?? '未知错误',
    );
  }

  bool _isRetryableV2RemoteError(Object error) {
    final lower = error.toString().toLowerCase();
    return lower.contains('service unavailable') ||
        lower.contains('too many requests') ||
        lower.contains('timed out') ||
        lower.contains('timeout') ||
        lower.contains('connection reset') ||
        lower.contains('connection refused') ||
        lower.contains('connection closed') ||
        lower.contains('network') ||
        lower.contains('429') ||
        lower.contains('502') ||
        lower.contains('503') ||
        lower.contains('504');
  }

  DateTime? _remoteModifiedAt(dynamic file) {
    for (final getter in <DateTime? Function()>[
      () => file.mTime as DateTime?,
      () => file.modified as DateTime?,
      () => file.lastModified as DateTime?,
    ]) {
      try {
        final value = getter();
        if (value != null) return value;
      } catch (_) {}
    }
    return null;
  }

  /// 获取最大备份数量设置
  int get maxBackupCount {
    return _storage.settingsBox.get('max_backup_count', defaultValue: 10)
        as int;
  }

  /// 设置最大备份数量
  void setMaxBackupCount(int count) {
    _storage.settingsBox.put('max_backup_count', count);
  }

  /// 清理超过数量限制的旧备份
  Future<void> _cleanupOldBackups() async {
    if (_client == null) return;

    try {
      final maxCount = maxBackupCount;
      if (maxCount <= 0) return; // 0 表示不限制

      final files = await listBackups();
      if (files.length <= maxCount) return;

      // 按文件名排序（时间戳格式，越新越大）
      files.sort();

      // 删除最早的备份，直到达到限制
      final toDelete = files.sublist(0, files.length - maxCount);
      for (final path in toDelete) {
        try {
          await _client!.remove(path);
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// 从WebDAV恢复数据
  Future<bool> restoreData(String remotePath) async {
    if (isOperationRunning.value) {
      ToastUtils.showWarning('已有备份或恢复任务正在进行');
      return false;
    }
    if (remotePath.endsWith('.manifest.json.gz')) {
      return _restoreDataV2(remotePath);
    }
    try {
      isOperationRunning.value = true;
      return await _restoreDataFullWithRollback(remotePath);
    } catch (e) {
      ToastUtils.showError('恢复失败: $e');
      return false;
    } finally {
      isOperationRunning.value = false;
      operationProgress.value = '';
    }
  }

  Future<bool> _restoreDataFullWithRollback(String remotePath) async {
    final safetyFile = isEfficientBackupSupported
        ? await _v2.writeSafetySnapshot(
            allowMissingMedia: true,
            onProgress: (message) => operationProgress.value = message,
          )
        : null;
    operationProgress.value = '正在写入恢复数据';
    final success = await _restoreDataFull(
      remotePath,
      createSafety: false,
      showSuccess: false,
      showError: false,
    );
    if (success) {
      ToastUtils.showSuccess('数据已恢复，请重启应用以生效');
      return true;
    }

    if (safetyFile != null) {
      operationProgress.value = '正在回滚到恢复前状态';
      final safetyData = await _v2.readSafetySnapshot(safetyFile);
      final rollback = await _restoreBackupMapViaTempFile(safetyData);
      if (rollback) {
        ToastUtils.showError('恢复失败，已回滚到恢复前状态');
      } else {
        ToastUtils.showError('恢复失败，回滚也失败，请保留安全快照: ${safetyFile.path}');
      }
      return false;
    }

    ToastUtils.showError('恢复失败');
    return false;
  }

  Future<bool> _restoreDataV2(String remotePath) async {
    if (_client == null) {
      ToastUtils.showError('请先配置WebDAV');
      return false;
    }
    if (isOperationRunning.value) {
      ToastUtils.showWarning('已有备份或恢复任务正在进行');
      return false;
    }
    try {
      isOperationRunning.value = true;
      _checkAdapters();
      final bundle = await _v2.downloadRemoteBackupData(
        manifestPath: remotePath,
        read: _readRemoteV2,
        onProgress: (message) => operationProgress.value = message,
      );
      if (bundle.warnings.isNotEmpty) {
        final proceed = await _confirmRestoreWithWarnings(bundle.warnings);
        if (!proceed) return false;
      }
      operationProgress.value = '正在创建恢复前安全快照';
      final safetyFile = await _v2.writeSafetySnapshot(
        allowMissingMedia: true,
        onProgress: (message) => operationProgress.value = message,
      );
      operationProgress.value = '正在写入恢复数据';
      final success = await _restoreBackupMapViaTempFile(bundle.backupData);
      if (!success) {
        operationProgress.value = '正在回滚到恢复前状态';
        final safetyData = await _v2.readSafetySnapshot(safetyFile);
        final rollback = await _restoreBackupMapViaTempFile(safetyData);
        if (rollback) {
          ToastUtils.showError('恢复失败，已回滚到恢复前状态');
        } else {
          ToastUtils.showError('恢复失败，回滚也失败，请保留安全快照: ${safetyFile.path}');
        }
        return false;
      }
      ToastUtils.showSuccess('数据已恢复，请重启应用以生效');
      return true;
    } catch (e) {
      ToastUtils.showError('高效备份恢复失败: $e');
      return false;
    } finally {
      isOperationRunning.value = false;
      operationProgress.value = '';
    }
  }

  Future<bool> _restoreBackupMapViaTempFile(
    Map<String, dynamic> backupData,
  ) async {
    final jsonBytes = utf8.encode(jsonEncode(backupData));
    final compressed = GZipEncoder().encode(jsonBytes);
    final path =
        '$webDavBackupV2Root/restore_tmp/restore_${DateTime.now().millisecondsSinceEpoch}.json.gz';
    try {
      try {
        await _client!.mkdir('$webDavBackupV2Root/restore_tmp');
      } catch (_) {}
      await _client!.write(path, Uint8List.fromList(compressed));
      return _restoreDataFull(
        path,
        createSafety: false,
        showSuccess: false,
        showError: false,
      );
    } finally {
      try {
        await _client!.remove(path);
      } catch (_) {}
    }
  }

  Future<bool> _confirmRestoreWithWarnings(
    List<V2BackupWarning> warnings,
  ) async {
    final preview = warnings.take(5).map((w) {
      final label = w.record.isEmpty ? w.field : '${w.record} / ${w.field}';
      return '$label\n${w.originalPath}';
    }).join('\n\n');
    final result = await Get.defaultDialog<bool>(
      title: '备份包含警告',
      middleText: '这份备份创建时忽略了 ${warnings.length} 个媒体文件。\n\n$preview',
      textConfirm: '继续恢复',
      textCancel: '取消恢复',
      confirmTextColor: Colors.white,
      onConfirm: () {
        Get.back(result: true);
      },
      onCancel: () {
        Get.back(result: false);
      },
    );
    return result == true;
  }

  Future<bool> _restoreDataFull(
    String remotePath, {
    bool createSafety = true,
    bool showSuccess = true,
    bool showError = true,
  }) async {
    if (_client == null) {
      ToastUtils.showError('请先配置WebDAV');
      return false;
    }

    try {
      _checkAdapters();
      if (createSafety && isEfficientBackupSupported) {
        operationProgress.value = '正在创建恢复前安全快照';
        await _v2.writeSafetySnapshot(
          allowMissingMedia: true,
          onProgress: (message) => operationProgress.value = message,
        );
      }
      final data = await _client!.read(remotePath);

      String jsonString;
      if (remotePath.endsWith('.gz')) {
        // 解压数据
        final decompressed = GZipDecoder().decodeBytes(data);
        jsonString = utf8.decode(decompressed);
      } else {
        jsonString = utf8.decode(data);
      }

      final Map<String, dynamic> backupData = jsonDecode(jsonString);

      // Clear existing data
      await _storage.userBox.clear();
      await _storage.actionBox.clear();
      await _storage.logBox.clear();
      await _storage.productBox.clear();
      await _storage.babyBox.clear();

      // Restore User Profile
      if (backupData['user'] != null) {
        for (var item in (backupData['user'] as List)) {
          await _storage.userBox.add(UserProfile.fromJson(item));
        }
      }

      // Restore Actions
      if (backupData['actions'] != null) {
        for (var item in (backupData['actions'] as List)) {
          await _storage.actionBox.add(ActionItem.fromJson(item));
        }
      }

      // Restore Logs
      if (backupData['logs'] != null) {
        for (var item in (backupData['logs'] as List)) {
          await _storage.logBox.add(Log.fromJson(item));
        }
      }

      // Restore Products
      if (backupData['products'] != null) {
        for (var item in (backupData['products'] as List)) {
          await _storage.productBox.add(Product.fromJson(item));
        }
      }

      // Restore Babies
      if (backupData['babies'] != null) {
        for (var item in (backupData['babies'] as List)) {
          await _storage.babyBox.add(Baby.fromJson(item));
        }
      }

      // 核心数据持久化
      await Future.wait([
        _storage.userBox.flush(),
        _storage.actionBox.flush(),
        _storage.logBox.flush(),
        _storage.productBox.flush(),
        _storage.babyBox.flush(),
      ]);
      debugPrint('核心数据已恢复并刷新到磁盘');

      // 恢复便便记录
      if (backupData['poopRecords'] != null) {
        int successCount = 0;
        int failCount = 0;
        String? lastError;

        try {
          final poopBox = await Hive.openBox<PoopRecord>('poop_records');
          await poopBox.clear();

          final list = backupData['poopRecords'] as List;
          debugPrint('Found ${list.length} poop records to restore');

          for (var item in list) {
            try {
              if (item is Map) {
                final map = Map<String, dynamic>.from(item);

                // 健壮性处理：确保非空及类型转换
                if (map['id'] == null)
                  map['id'] = DateTime.now().millisecondsSinceEpoch.toString();
                if (map['babyId'] == null) map['babyId'] = 'default_baby';

                // 强制转 String
                map['id'] = map['id'].toString();
                map['babyId'] = map['babyId'].toString();

                // 兼容性处理：防止 type/color 被错误存储为 String
                if (map['type'] is String) {
                  map['type'] = int.tryParse(map['type']) ?? 0;
                }
                if (map['color'] is String) {
                  map['color'] = int.tryParse(map['color']) ?? 0;
                }

                final record = PoopRecord.fromJson(map);
                await poopBox.put(record.id, record);
                successCount++;
              }
            } catch (e) {
              failCount++;
              lastError = e.toString();
              debugPrint('恢复单个便便记录失败: $e');
            }
          }

          // 关键修复：确保数据被持久化到磁盘
          await poopBox.flush();
          debugPrint('便便记录已刷新到磁盘');

          if (failCount > 0) {
            ToastUtils.showWarning('便便记录恢复：成功 $successCount 条，失败 $failCount 条');
            debugPrint('Last restore error: $lastError');
          } else if (successCount > 0) {
            debugPrint('成功恢复 $successCount 条便便记录');
            ToastUtils.showSuccess('成功恢复 $successCount 条便便记录');
          } else {
            debugPrint('无便便记录可恢复');
          }
        } catch (e) {
          debugPrint('恢复便便记录失败: $e');
          ToastUtils.showWarning('便便记录恢复失败: $e');
        }
      }

      if (backupData['growthRecords'] != null) {
        try {
          await _storage.growthRecordBox.clear();
          for (var item in (backupData['growthRecords'] as List)) {
            if (item is Map) {
              final record =
                  GrowthRecord.fromJson(Map<String, dynamic>.from(item));
              await _storage.growthRecordBox.put(record.id, record);
            }
          }
          await _storage.growthRecordBox.flush();
        } catch (e) {
          debugPrint('恢复生长记录失败: $e');
          ToastUtils.showWarning('生长记录恢复失败: $e');
        }
      }

      if (backupData['milestoneRecords'] != null) {
        try {
          await _storage.milestoneRecordBox.clear();
          for (var item in (backupData['milestoneRecords'] as List)) {
            if (item is Map) {
              final record =
                  MilestoneRecord.fromJson(Map<String, dynamic>.from(item));
              await _storage.milestoneRecordBox.put(record.id, record);
            }
          }
          await _storage.milestoneRecordBox.flush();
        } catch (e) {
          debugPrint('恢复大事记失败: $e');
          ToastUtils.showWarning('大事记恢复失败: $e');
        }
      }

      // 恢复 AI 聊天记录
      if (backupData['aiChats'] != null) {
        try {
          final chatBox = await Hive.openBox<AIChat>('ai_chats');
          await chatBox.clear();
          for (var item in (backupData['aiChats'] as List)) {
            try {
              if (item is Map) {
                final map = Map<String, dynamic>.from(item);
                if (map['id'] != null) map['id'] = map['id'].toString();
                if (map['babyId'] != null)
                  map['babyId'] = map['babyId'].toString();

                final chat = AIChat.fromJson(map);
                await chatBox.put(chat.id, chat);
              }
            } catch (e) {
              print('恢复单个 AI 聊天记录失败: $e');
            }
          }
          // 确保数据持久化
          await chatBox.flush();
        } catch (e) {
          print('恢复 AI 聊天记录失败: $e');
          ToastUtils.showWarning('AI 聊天记录恢复失败: $e');
        }
      }

      // 恢复 OpenAI 配置
      if (backupData['openaiConfigs'] != null) {
        try {
          final openaiBox = await Hive.openBox<OpenAIConfig>('openai_configs');
          await openaiBox.clear();
          for (var item in (backupData['openaiConfigs'] as List)) {
            if (item is Map) {
              final map = Map<String, dynamic>.from(item);
              if (map['id'] != null) map['id'] = map['id'].toString();

              final config = OpenAIConfig.fromJson(map);
              await openaiBox.put(config.id, config);
            }
          }
          // 确保数据持久化
          await openaiBox.flush();
        } catch (e) {
          print('恢复 OpenAI 配置失败: $e');
          ToastUtils.showWarning('OpenAI 配置恢复失败: $e');
        }

        // 尝试刷新 OpenAIService
        try {
          if (Get.isRegistered<OpenAIService>()) {
            Get.find<OpenAIService>().loadConfigs();
          }
        } catch (_) {}
      }

      // 恢复应用设置
      if (backupData['appSettings'] != null) {
        try {
          final appSettingsBox = await Hive.openBox('app_settings');
          await appSettingsBox.clear();
          final settings = backupData['appSettings'] as Map;
          for (var entry in settings.entries) {
            await appSettingsBox.put(entry.key, entry.value);
          }
          await appSettingsBox.flush();
        } catch (e) {
          print('恢复应用设置失败: $e');
        }
      }

      if (backupData['ttsSettings'] != null) {
        try {
          final ttsSettingsBox = await Hive.openBox('tts_settings');
          await ttsSettingsBox.clear();
          final settings = backupData['ttsSettings'] as Map;
          for (var entry in settings.entries) {
            await ttsSettingsBox.put(entry.key, entry.value);
          }
          await ttsSettingsBox.flush();
        } catch (e) {
          print('恢复 TTS 设置失败: $e');
        }
      }

      if (backupData['poopAiSettings'] != null) {
        try {
          final poopAiSettingsBox = await Hive.openBox('poop_ai_settings');
          await poopAiSettingsBox.clear();
          final settings = backupData['poopAiSettings'] as Map;
          for (var entry in settings.entries) {
            await poopAiSettingsBox.put(entry.key, entry.value);
          }
          await poopAiSettingsBox.flush();
        } catch (e) {
          print('恢复便便 AI 设置失败: $e');
        }
      }

      // 恢复故事游戏配置
      if (backupData['storyGameConfig'] != null) {
        try {
          final storyConfigBox = await Hive.openBox('story_game_config');
          await storyConfigBox.clear();
          final config = backupData['storyGameConfig'] as Map;
          for (var entry in config.entries) {
            await storyConfigBox.put(entry.key, entry.value);
          }
          await storyConfigBox.flush();
        } catch (e) {
          print('恢复故事游戏配置失败: $e');
        }
      }

      // 恢复故事游戏会话记录
      if (backupData['storySessions'] != null) {
        try {
          final storySessionBox =
              await Hive.openBox<StorySession>('story_sessions');
          await storySessionBox.clear();
          for (var item in (backupData['storySessions'] as List)) {
            try {
              if (item is Map) {
                final session =
                    StorySession.fromJson(Map<String, dynamic>.from(item));
                await storySessionBox.put(session.id, session);
              }
            } catch (e) {
              print('恢复单个故事会话失败: $e');
            }
          }
          // 确保数据持久化
          await storySessionBox.flush();
        } catch (e) {
          print('恢复故事游戏会话失败: $e');
        }
      }

      // 恢复自定义脑筋急转弯
      if (backupData['customRiddles'] != null) {
        try {
          final riddleBox = await Hive.openBox('custom_riddles');
          await riddleBox.clear();
          for (var item in (backupData['customRiddles'] as List)) {
            await riddleBox.add(item);
          }
          await riddleBox.flush();
        } catch (e) {
          print('恢复自定义脑筋急转弯失败: $e');
        }
      }

      // 恢复音乐数据
      if (backupData['musicPlaylists'] != null) {
        try {
          final playlistBox = _storage.playlistBox;
          await playlistBox.clear();
          for (var item in (backupData['musicPlaylists'] as List)) {
            if (item is Map) {
              final List<MusicTrack> tracks = (item['tracks'] as List? ?? [])
                  .map((t) => MusicTrack.fromJson(Map<String, dynamic>.from(t)))
                  .toList();

              final pl = Playlist(
                id: item['id'],
                name: item['name'],
                coverUrl: item['coverUrl'],
                createdAt: DateTime.parse(item['createdAt']),
                tracks: tracks,
              );
              await playlistBox.put(pl.id, pl);
            }
          }
          // 确保数据持久化
          await playlistBox.flush();
        } catch (e) {
          print('恢复音乐数据失败: $e');
        }
      }

      // 恢复通用设置 (settings box)
      if (backupData['genericSettings'] != null) {
        try {
          final settingsBox = await Hive.openBox('settings');
          final settings = backupData['genericSettings'] as Map;

          // 获取当前的 WebDAV 配置，避免被覆盖后断开连接
          final currentWebDavUrl = settingsBox.get('webdav_url');
          final currentWebDavUser = settingsBox.get('webdav_user');
          final currentWebDavPwd = settingsBox.get('webdav_pwd');

          for (var entry in settings.entries) {
            await settingsBox.put(entry.key, entry.value);
          }

          // 恢复 WebDAV 连接信息 (如果之前存在)
          // 这样用户恢复其他设置时不会把自己踢下线，除非是全新安装后的恢复
          if (currentWebDavUrl != null) {
            await settingsBox.put('webdav_url', currentWebDavUrl);
            await settingsBox.put('webdav_user', currentWebDavUser);
            await settingsBox.put('webdav_pwd', currentWebDavPwd);
          }

          await settingsBox.flush();
          // Reload config related if needed
          _loadConfig();
        } catch (e) {
          print('恢复通用设置失败: $e');
        }
      }

      // 恢复 TuneHub 设置
      if (backupData['tuneHubConfig'] != null) {
        try {
          final tuneHubBox = await Hive.openBox('tunehub_config');
          await tuneHubBox.clear();
          final config = backupData['tuneHubConfig'] as Map;
          for (var entry in config.entries) {
            await tuneHubBox.put(entry.key, entry.value);
          }
          await tuneHubBox.flush();
        } catch (e) {
          print('恢复 TuneHub 设置失败: $e');
        }
      }

      // 恢复播放器设置
      if (backupData['playerSettings'] != null) {
        try {
          final playerSettingsBox = await Hive.openBox('player_settings');
          await playerSettingsBox.clear();
          final settings = backupData['playerSettings'] as Map;
          for (var entry in settings.entries) {
            await playerSettingsBox.put(entry.key, entry.value);
          }
          await playerSettingsBox.flush();
        } catch (e) {
          print('恢复播放器设置失败: $e');
        }
      }

      // 恢复密码哈希
      if (backupData['passwordHash'] != null) {
        try {
          final modeController = Get.find<AppModeController>();
          await modeController.ensureInitialized(); // 🔧 确保初始化完成
          await modeController.restorePasswordHash(backupData['passwordHash']);
        } catch (_) {}
      }

      // 恢复新年故事
      if (backupData['newYearStories'] != null) {
        try {
          // 先清空旧数据? 根据需求"完美融合"，通常全量恢复会覆盖。
          // StoryManagementService 没有 clearAll 方法?
          // 检查: StoryManagementService 有 deleteStories(all ids) 或 resetToBuiltIn
          // 这里可以先尝试直接 restore，因为 restore 会 add/overwrite
          // 为了避免残留旧数据，建议先清空。
          // 检查 StoryManagementService.resetToBuiltIn();
          // 但那是重置为内置。
          // 最好是保留用户现有的，还是覆盖? 备份/恢复通常是覆盖或合并.
          // 现有 WebDavService 逻辑是 clear then add.
          // StoryManagementService 有 deleteStory.
          // 我需要一个 clearAllStories 方法。
          // 暂时先调用 deleteStories(allIds).
          final storyService = StoryManagementService.instance;
          final allIds = storyService.getAllStories().map((s) => s.id).toList();
          await storyService.deleteStories(allIds);

          await storyService.restoreStories(backupData['newYearStories']);
        } catch (e) {
          print('恢复新年故事失败: $e');
        }
      }

      // 恢复新年问答
      if (backupData['quizQuestions'] != null ||
          backupData['quizConfig'] != null) {
        try {
          if (Get.isRegistered<QuizService>()) {
            final quizService = Get.find<QuizService>();

            // 恢复配置
            if (backupData['quizConfig'] != null) {
              try {
                final config = QuizConfig.fromJson(
                    Map<String, dynamic>.from(backupData['quizConfig']));
                await quizService.updateConfig(config);
              } catch (e) {
                print('恢复新年问答配置失败: $e');
              }
            }

            // 恢复题目
            if (backupData['quizQuestions'] != null) {
              await quizService.clearQuestions();
              await quizService.restoreQuestions(backupData['quizQuestions']);
            }
          }
        } catch (e) {
          print('恢复新年问答失败: $e');
        }
      }

      // 恢复汉字学习配置
      if (backupData['hanziLearningConfig'] != null) {
        try {
          final hanziBox = await Hive.openBox('hanzi_learning_config');
          await hanziBox.clear();
          final config = backupData['hanziLearningConfig'] as Map;
          for (var entry in config.entries) {
            await hanziBox.put(entry.key, entry.value);
          }
          await hanziBox.flush();
        } catch (e) {
          print('恢复汉字学习配置失败: $e');
        }
      }

      // 恢复生活科学百科
      if (backupData['encyclopediaData'] != null) {
        try {
          if (Get.isRegistered<EncyclopediaService>()) {
            final encyclopediaService = Get.find<EncyclopediaService>();
            await encyclopediaService.importData(
              Map<String, dynamic>.from(backupData['encyclopediaData'] as Map),
            );
          } else {
            // 服务未注册时，直接写入相关 Box，保证数据不丢失
            final configBox =
                await Hive.openBox<EncyclopediaConfig>('encyclopedia_config');
            final questionBox = await Hive.openBox<EncyclopediaQuestion>(
                'encyclopedia_questions');
            final cacheBox = await Hive.openBox<EncyclopediaExplanationCache>(
                'encyclopedia_explanation_cache');
            final playRecordBox =
                await Hive.openBox('encyclopedia_play_record');

            final raw = Map<String, dynamic>.from(
                backupData['encyclopediaData'] as Map);

            if (raw['config'] != null) {
              await configBox.clear();
              await configBox.add(EncyclopediaConfig.fromJson(
                Map<String, dynamic>.from(raw['config'] as Map),
              ));
            }

            if (raw['questions'] != null) {
              await questionBox.clear();
              for (final item in (raw['questions'] as List)) {
                final q = EncyclopediaQuestion.fromJson(
                    Map<String, dynamic>.from(item as Map));
                await questionBox.put(q.id, q);
              }
            }

            if (raw['explanationCaches'] != null) {
              await cacheBox.clear();
              for (final item in (raw['explanationCaches'] as List)) {
                final c = EncyclopediaExplanationCache.fromJson(
                    Map<String, dynamic>.from(item as Map));
                await cacheBox.put(c.cacheKey, c);
              }
            }

            if (raw['playRecords'] != null) {
              await playRecordBox.clear();
              final m = Map<String, dynamic>.from(raw['playRecords'] as Map);
              for (final entry in m.entries) {
                await playRecordBox.put(entry.key, entry.value);
              }
            }
          }
        } catch (e) {
          print('恢复生活科学百科失败: $e');
        }
      }

      // 恢复 CFTTS 配置
      if (backupData['cfttsConfigBox'] != null) {
        try {
          final cfttsBox = await Hive.openBox<CfttsConfig>('cftts_config_box');
          await cfttsBox.clear();
          for (var item in (backupData['cfttsConfigBox'] as List)) {
            if (item is Map) {
              final map = Map<String, dynamic>.from(item);
              final config = CfttsConfig.fromJson(map);
              await cfttsBox.add(config);
            }
          }
          await cfttsBox.flush();
        } catch (e) {
          print('恢复 CFTTS 配置失败: $e');
        }
      }

      // 恢复 OpenAI TTS Provider 配置
      if (backupData['openAITtsConfigBox'] != null) {
        try {
          final openAITtsBox =
              await Hive.openBox<OpenAITtsConfig>('openai_tts_config_box');
          await openAITtsBox.clear();
          for (var item in (backupData['openAITtsConfigBox'] as List)) {
            if (item is Map) {
              final map = Map<String, dynamic>.from(item);
              final config = OpenAITtsConfig.fromJson(map);
              await openAITtsBox.put(config.id, config);
            }
          }
          await openAITtsBox.flush();
        } catch (e) {
          print('恢复 OpenAI TTS 配置失败: $e');
        }
      }

      // 所有的 TTS 及 CFTTS 恢复完成后，在内存中重新加载它
      try {
        if (Get.isRegistered<TtsService>()) {
          Get.find<TtsService>().reloadSettings();
        }
      } catch (_) {}

      if (showSuccess) {
        ToastUtils.showSuccess('数据已恢复，请重启应用以生效');
      }
      return true;
    } catch (e) {
      if (showError) {
        ToastUtils.showError('恢复失败: $e');
      }
      return false;
    }
  }

  /// 获取备份文件列表（包含详细信息）
  Future<List<BackupFileInfo>> listBackupsDetailed() async {
    if (_client == null) return [];
    if (backupStrategy.value == WebDavBackupStrategy.efficientV2) {
      try {
        final files = await _v2.listRemoteManifests(
          list: _listRemoteV2,
          read: _readRemoteV2,
        );
        return files
            .map((info) => BackupFileInfo(
                  path: info.path,
                  filename: _extractFilename(info.path),
                  size: info.size,
                  strategy: 'v2',
                  warningCount: info.warnings.length,
                  summary: info.summary,
                ))
            .toList();
      } catch (e) {
        debugPrint('List v2 backups failed: $e');
        return [];
      }
    }
    try {
      final list = await _client!.readDir('/starbank');
      return list
          .where((f) =>
              ((f.path ?? '').endsWith('.json') ||
                  (f.path ?? '').endsWith('.json.gz')) &&
              !(f.path ?? '').contains('/v2/'))
          .map((f) => BackupFileInfo(
                path: f.path ?? '',
                filename: _extractFilename(f.path ?? ''),
                size: f.size ?? 0,
                strategy: 'full',
              ))
          .toList();
    } catch (e) {
      debugPrint('WebDAV list error: $e');
      if (e.toString().contains('XmlHttpRequest') ||
          e.toString().contains('CORS')) {
        ToastUtils.showError('WebDAV连接失败(可能是CORS问题): $e');
      } else {
        debugPrint('List backups failed (maybe dir not exists): $e');
      }
      return [];
    }
  }

  /// 旧版兼容方法（仅返回路径列表）
  Future<List<String>> listBackups() async {
    final detailed = await listBackupsDetailed();
    return detailed.map((f) => f.path).toList();
  }

  /// 从路径中提取文件名
  String _extractFilename(String path) {
    if (path.isEmpty) return '';
    final parts = path.split('/');
    return parts.isNotEmpty ? parts.last : path;
  }

  /// 删除指定的备份文件
  Future<bool> deleteBackup(String remotePath) async {
    if (_client == null) {
      ToastUtils.showError('请先配置WebDAV');
      return false;
    }

    try {
      if (remotePath.endsWith('.manifest.json.gz')) {
        await _v2.deleteManifestAndGc(
          manifestPath: remotePath,
          list: _listRemoteV2,
          read: _readRemoteV2,
          remove: _removeRemoteV2,
        );
      } else {
        await _client!.remove(remotePath);
      }
      ToastUtils.showSuccess('备份已删除');
      return true;
    } catch (e) {
      ToastUtils.showError('删除失败: $e');
      return false;
    }
  }

  /// 检查并注册适配器
  void _checkAdapters() {
    // OpenAIConfig (10)
    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(OpenAIConfigAdapter());
    }
    // PoopRecord (11)
    if (!Hive.isAdapterRegistered(11)) {
      Hive.registerAdapter(PoopRecordAdapter());
    }
    // AIChat (12)
    if (!Hive.isAdapterRegistered(12)) {
      Hive.registerAdapter(AIChatAdapter());
    }
    // StorySession (13)
    if (!Hive.isAdapterRegistered(13)) {
      Hive.registerAdapter(StorySessionAdapter());
    }
    // StoryGameConfig (14)
    if (!Hive.isAdapterRegistered(14)) {
      Hive.registerAdapter(StoryGameConfigAdapter());
    }
    // HanziLearningConfig (40)
    if (!Hive.isAdapterRegistered(40)) {
      Hive.registerAdapter(HanziLearningConfigAdapter());
    }
    // CfttsConfig (41)
    if (!Hive.isAdapterRegistered(41)) {
      Hive.registerAdapter(CfttsConfigAdapter());
    }
    // OpenAITtsConfig (42)
    if (!Hive.isAdapterRegistered(42)) {
      Hive.registerAdapter(OpenAITtsConfigAdapter());
    }
    // EncyclopediaQuestion (43)
    if (!Hive.isAdapterRegistered(43)) {
      Hive.registerAdapter(EncyclopediaQuestionAdapter());
    }
    // EncyclopediaConfig (44)
    if (!Hive.isAdapterRegistered(44)) {
      Hive.registerAdapter(EncyclopediaConfigAdapter());
    }
    // EncyclopediaExplanationCache (45)
    if (!Hive.isAdapterRegistered(45)) {
      Hive.registerAdapter(EncyclopediaExplanationCacheAdapter());
    }
    // GrowthRecord (46)
    if (!Hive.isAdapterRegistered(46)) {
      Hive.registerAdapter(GrowthRecordAdapter());
    }
    // MilestoneRecord (47)
    if (!Hive.isAdapterRegistered(47)) {
      Hive.registerAdapter(MilestoneRecordAdapter());
    }
  }
}
