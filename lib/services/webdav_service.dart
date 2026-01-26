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
          final poopBox = await Hive.openBox<dynamic>('poop_records');
          await poopBox.clear();
          for (var item in (backupData['poopRecords'] as List)) {
            // 使用 put 而不是 add，保留原 ID
            final id = item['id'] as String;
            await poopBox.put(id, item);
          }
        } catch (e) {
          print('恢复便便记录失败: $e');
        }
      }

      // 恢复 AI 聊天记录
      if (backupData['aiChats'] != null) {
        try {
          final chatBox = await Hive.openBox<dynamic>('ai_chats');
          await chatBox.clear();
          for (var item in (backupData['aiChats'] as List)) {
            // 使用 put 而不是 add，保留原 ID
            final id = item['id'] as String;
            await chatBox.put(id, item);
          }
        } catch (e) {
          print('恢复 AI 聊天记录失败: $e');
        }
      }

      // 恢复 OpenAI 配置
      if (backupData['openaiConfigs'] != null) {
        try {
          final openaiBox = await Hive.openBox<dynamic>('openai_configs');
          await openaiBox.clear();
          for (var item in (backupData['openaiConfigs'] as List)) {
            final id = item['id'] as String;
            await openaiBox.put(id, item);
          }
        } catch (e) {
          print('恢复 OpenAI 配置失败: $e');
        }
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
          final storySessionBox = await Hive.openBox<dynamic>('story_sessions');
          await storySessionBox.clear();
          for (var item in (backupData['storySessions'] as List)) {
            final id = item['id'] as String;
            await storySessionBox.put(id, item);
          }
        } catch (e) {
          print('恢复故事游戏会话失败: $e');
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
}
