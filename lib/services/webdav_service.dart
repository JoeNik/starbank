import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;
import 'package:hive/hive.dart';
import 'dart:convert';
import 'storage_service.dart';
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

/// WebDAV备份服务
class WebDavService extends GetxService {
  webdav.Client? _client;
  final StorageService _storage = Get.find<StorageService>();

  final RxString currentUrl = ''.obs;
  final RxString currentUser = ''.obs;

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

  /// 备份所有Hive数据到WebDAV
  Future<bool> backupData() async {
    if (_client == null) {
      Get.snackbar('错误', '请先配置WebDAV');
      return false;
    }

    try {
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
        final poopBox = await Hive.openBox<dynamic>('poop_records');
        backupData['poopRecords'] = poopBox.values.map((e) {
          if (e is Map) return e;
          return (e as dynamic).toJson();
        }).toList();
      } catch (e) {
        print('备份便便记录失败: $e');
      }

      // 备份 AI 聊天记录
      try {
        final chatBox = await Hive.openBox<dynamic>('ai_chats');
        backupData['aiChats'] = chatBox.values.map((e) {
          if (e is Map) return e;
          return (e as dynamic).toJson();
        }).toList();
      } catch (e) {
        print('备份 AI 聊天记录失败: $e');
      }

      // 备份 OpenAI 配置
      try {
        final openaiBox = await Hive.openBox<dynamic>('openai_configs');
        backupData['openaiConfigs'] = openaiBox.values.map((e) {
          if (e is Map) return e;
          return (e as dynamic).toJson();
        }).toList();
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
        backupData['storySessions'] = storySessionBox.values.map((e) {
          if (e is Map) return e;
          return (e as dynamic).toJson();
        }).toList();
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
        // 先检查 Box 是否打开，如果没有则打开
        final playlistBox = await Hive.openBox<Playlist>('playlists');
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
        if (modeController.hasPassword) {
          backupData['passwordHash'] = modeController.passwordHash;
        }
      } catch (_) {}

      backupData['timestamp'] = DateTime.now().toIso8601String();

      final jsonString = jsonEncode(backupData);

      // Timestamp based filename: yyyyMMddHH
      final now = DateTime.now();
      final timestamp =
          "${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}";
      final remotePath = '/starbank/backup_$timestamp.json';

      // Ensure directory exists
      try {
        await _client!.mkdir('/starbank');
      } catch (_) {}

      // upload
      await _client!.write(remotePath, utf8.encode(jsonString));

      // 清理旧备份
      await _cleanupOldBackups();

      Get.snackbar('成功', '备份已存至: $remotePath');
      return true;
    } catch (e) {
      Get.snackbar('错误', '备份失败: $e');
      return false;
    }
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
    if (_client == null) {
      Get.snackbar('错误', '请先配置WebDAV');
      return false;
    }

    try {
      _checkAdapters();
      final data = await _client!.read(remotePath);
      final jsonString = utf8.decode(data);
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

      // 恢复便便记录
      if (backupData['poopRecords'] != null) {
        try {
          // 确保使用正确的泛型打开 Box，以便 Hive 知道它存储的是 PoopRecord
          // 注意：如果之前已经用 dynamic 打开过，这里复用实例可能还是 dynamic 泛型，
          // 但 put 进去的对象必须是 PoopRecord 类型
          final poopBox = await Hive.openBox<PoopRecord>('poop_records');
          await poopBox.clear();
          for (var item in (backupData['poopRecords'] as List)) {
            if (item is Map) {
              final map = Map<String, dynamic>.from(item);
              // Ensure ID is string
              if (map['id'] != null) map['id'] = map['id'].toString();
              if (map['babyId'] != null)
                map['babyId'] = map['babyId'].toString();

              final record = PoopRecord.fromJson(map);
              await poopBox.put(record.id, record);
            }
          }
        } catch (e) {
          print('恢复便便记录失败: $e');
          Get.snackbar('警告', '便便记录恢复失败: $e',
              duration: const Duration(seconds: 5),
              snackPosition: SnackPosition.BOTTOM,
              backgroundColor: Colors.orange.shade100);
        }
      }

      // 恢复 AI 聊天记录
      if (backupData['aiChats'] != null) {
        try {
          final chatBox = await Hive.openBox<AIChat>('ai_chats');
          await chatBox.clear();
          for (var item in (backupData['aiChats'] as List)) {
            if (item is Map) {
              final map = Map<String, dynamic>.from(item);
              if (map['id'] != null) map['id'] = map['id'].toString();
              if (map['babyId'] != null)
                map['babyId'] = map['babyId'].toString();

              final chat = AIChat.fromJson(map);
              await chatBox.put(chat.id, chat);
            }
          }
        } catch (e) {
          print('恢复 AI 聊天记录失败: $e');
          Get.snackbar('警告', 'AI 聊天记录恢复失败: $e',
              duration: const Duration(seconds: 5),
              snackPosition: SnackPosition.BOTTOM,
              backgroundColor: Colors.orange.shade100);
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
        } catch (e) {
          print('恢复 OpenAI 配置失败: $e');
          Get.snackbar('警告', 'OpenAI 配置恢复失败: $e',
              duration: const Duration(seconds: 5),
              snackPosition: SnackPosition.BOTTOM,
              backgroundColor: Colors.orange.shade100);
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
            if (item is Map) {
              final session =
                  StorySession.fromJson(Map<String, dynamic>.from(item));
              await storySessionBox.put(session.id, session);
            }
          }
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
        } catch (e) {
          print('恢复自定义脑筋急转弯失败: $e');
        }
      }

      // 恢复音乐数据
      if (backupData['musicPlaylists'] != null) {
        try {
          final playlistBox = await Hive.openBox<Playlist>('playlists');
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
        } catch (e) {
          print('恢复播放器设置失败: $e');
        }
      }

      // 恢复密码哈希
      if (backupData['passwordHash'] != null) {
        try {
          final modeController = Get.find<AppModeController>();
          await modeController.restorePasswordHash(backupData['passwordHash']);
        } catch (_) {}
      }

      Get.snackbar(
        '成功',
        '数据已恢复，请重启应用以生效',
        duration: const Duration(seconds: 5),
      );
      return true;
    } catch (e) {
      Get.snackbar('错误', '恢复失败: $e');
      return false;
    }
  }

  Future<List<String>> listBackups() async {
    if (_client == null) return [];
    try {
      final list = await _client!.readDir('/starbank');
      return list
          .map((f) => f.path ?? '')
          .where((p) => p.endsWith('.json'))
          .toList();
    } catch (_) {
      return [];
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
  }
}
