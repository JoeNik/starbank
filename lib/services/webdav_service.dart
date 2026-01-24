import 'package:get/get.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;
import 'dart:convert';
import 'storage_service.dart';
import '../models/user_profile.dart';
import '../models/baby.dart';
import '../models/action_item.dart';
import '../models/log.dart';
import '../models/product.dart';

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
      backupData['user'] = _storage.userBox.values
          .map((e) => e.toJson())
          .toList();
      backupData['actions'] = _storage.actionBox.values
          .map((e) => e.toJson())
          .toList();
      backupData['logs'] = _storage.logBox.values
          .map((e) => e.toJson())
          .toList();
      backupData['products'] = _storage.productBox.values
          .map((e) => e.toJson())
          .toList();
      backupData['babies'] = _storage.babyBox.values
          .map((e) => e.toJson())
          .toList();

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

      Get.snackbar('成功', '备份已存至: $remotePath');
      return true;
    } catch (e) {
      Get.snackbar('错误', '备份失败: $e');
      return false;
    }
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
