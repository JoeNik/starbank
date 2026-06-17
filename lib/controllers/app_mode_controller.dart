import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../services/storage_service.dart';
import '../theme/app_theme.dart';

/// 应用模式枚举
enum AppMode {
  parent, // 家长模式 - 完全控制
  child, // 儿童模式 - 只读
}

/// 应用模式控制器
/// 管理家长/儿童模式切换，密码验证等
class AppModeController extends GetxController {
  AppModeController();

  static const String _primaryBoxName = 'settings';
  static const String _legacyBoxName = 'app_settings';
  static const String _passwordKey = 'parent_password_hash';
  static const String _modeKey = 'current_mode';
  static const String _defaultPasswordMigrationKey =
      'parent_password_reset_20260617_135790';
  static const String _defaultRecoveryPassword = '135790';

  final Rx<AppMode> currentMode = AppMode.parent.obs;
  final RxBool _hasPassword = false.obs;
  final RxnString _passwordHash = RxnString();

  Box? _settingsBox;
  Box? _legacySettingsBox;
  Future<void>? _initFuture;
  bool _isInitialized = false;

  @override
  void onInit() {
    super.onInit();
    _initFuture = _initSettings();
  }

  Future<void> _initSettings() async {
    if (_isInitialized) return;
    _settingsBox = await _openPrimaryBox();
    _legacySettingsBox = await _openLegacyBox();

    await _migrateLegacySettings();
    await _applyDefaultPasswordRecoveryIfNeeded();
    _refreshCachedState();
    _isInitialized = true;
  }

  Future<Box> _openPrimaryBox() async {
    if (Get.isRegistered<StorageService>()) {
      return Get.find<StorageService>().settingsBox;
    }
    if (Hive.isBoxOpen(_primaryBoxName)) {
      return Hive.box(_primaryBoxName);
    }
    return Hive.openBox(_primaryBoxName);
  }

  Future<Box> _openLegacyBox() async {
    if (Hive.isBoxOpen(_legacyBoxName)) {
      return Hive.box(_legacyBoxName);
    }
    return Hive.openBox(_legacyBoxName);
  }

  Future<void> _migrateLegacySettings() async {
    final mergedPassword = _readMergedString(_passwordKey);
    final mergedMode = _readMergedMode();

    if (mergedPassword != null && mergedPassword.isNotEmpty) {
      await _writeToBoth(_passwordKey, mergedPassword);
    }
    await _writeToBoth(_modeKey, mergedMode.name);
  }

  Future<void> _applyDefaultPasswordRecoveryIfNeeded() async {
    final applied = _readMergedBool(_defaultPasswordMigrationKey);
    if (applied) return;
    final hasExistingState =
        (_settingsBox?.containsKey(_passwordKey) ?? false) ||
            (_legacySettingsBox?.containsKey(_passwordKey) ?? false);
    if (!hasExistingState) return;

    final hash = _hashPassword(_defaultRecoveryPassword);
    await _writeToBoth(_passwordKey, hash);
    await _writeToBoth(_modeKey, AppMode.parent.name);
    await _writeToBoth(_defaultPasswordMigrationKey, true);
  }

  void _refreshCachedState() {
    final password = _readMergedString(_passwordKey);
    final mode = _readMergedMode();
    _passwordHash.value = password;
    _hasPassword.value = password?.isNotEmpty == true;
    currentMode.value = mode;
  }

  String? _readMergedString(String key) {
    final primary = _settingsBox?.get(key);
    if (primary is String && primary.trim().isNotEmpty) {
      return primary;
    }
    final legacy = _legacySettingsBox?.get(key);
    if (legacy is String && legacy.trim().isNotEmpty) {
      return legacy;
    }
    return null;
  }

  bool _readMergedBool(String key) {
    final primary = _settingsBox?.get(key);
    if (primary is bool) return primary;
    final legacy = _legacySettingsBox?.get(key);
    if (legacy is bool) return legacy;
    return false;
  }

  AppMode _readMergedMode() {
    final raw = _settingsBox?.get(_modeKey) ?? _legacySettingsBox?.get(_modeKey);
    return raw?.toString() == AppMode.child.name ? AppMode.child : AppMode.parent;
  }

  Future<void> _writeToBoth(String key, dynamic value) async {
    final boxes = <Box>{
      if (_settingsBox != null) _settingsBox!,
      if (_legacySettingsBox != null) _legacySettingsBox!,
    };
    for (final box in boxes) {
      await box.put(key, value);
    }
  }

  Future<void> _persistMode(AppMode mode) async {
    currentMode.value = mode;
    await _writeToBoth(_modeKey, mode.name);
  }

  Future<void> _persistPasswordHash(String? hash) async {
    final boxes = <Box>{
      if (_settingsBox != null) _settingsBox!,
      if (_legacySettingsBox != null) _legacySettingsBox!,
    };
    for (final box in boxes) {
      if (hash == null || hash.isEmpty) {
        await box.delete(_passwordKey);
      } else {
        await box.put(_passwordKey, hash);
      }
    }
    _passwordHash.value = hash;
    _hasPassword.value = hash?.isNotEmpty == true;
  }

  /// 确保初始化完成（公开方法，供外部调用）
  Future<void> ensureInitialized() async {
    await (_initFuture ??= _initSettings());
  }

  /// 是否是家长模式
  bool get isParentMode => currentMode.value == AppMode.parent;

  /// 是否是儿童模式
  bool get isChildMode => currentMode.value == AppMode.child;

  /// 是否已设置密码
  bool get hasPassword => _hasPassword.value;

  /// 获取密码哈希（用于云端备份）
  String? get passwordHash => _passwordHash.value ?? _readMergedString(_passwordKey);

  /// 设置密码（SHA256 加密）
  Future<void> setPassword(String password) async {
    await ensureInitialized();
    final hash = _hashPassword(password);
    await _persistPasswordHash(hash);
  }

  /// 直接重置为恢复密码，并切回家长模式
  Future<void> resetPasswordToDefault() async {
    await ensureInitialized();
    await _persistPasswordHash(_hashPassword(_defaultRecoveryPassword));
    await _persistMode(AppMode.parent);
    await _writeToBoth(_defaultPasswordMigrationKey, true);
  }

  /// 从云端恢复密码哈希
  Future<void> restorePasswordHash(String hash) async {
    await ensureInitialized();
    await _persistPasswordHash(hash);
  }

  /// 验证密码
  bool verifyPassword(String password) {
    final storedHash = passwordHash;
    if (storedHash == null || storedHash.isEmpty) return true;
    return _hashPassword(password) == storedHash;
  }

  /// 切换到家长模式（需要密码验证）
  Future<bool> switchToParentMode(String password) async {
    await ensureInitialized();
    if (!hasPassword || verifyPassword(password)) {
      await _persistMode(AppMode.parent);
      return true;
    }
    return false;
  }

  /// 切换到儿童模式
  Future<void> switchToChildMode() async {
    await ensureInitialized();
    await _persistMode(AppMode.child);
  }

  /// 密码哈希函数
  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// 显示切换模式对话框
  void showModeSwitchDialog() {
    unawaited(_showModeSwitchDialogAsync());
  }

  Future<void> _showModeSwitchDialogAsync() async {
    await ensureInitialized();
    final context = Get.overlayContext;
    if (context == null) return;

    if (!isChildMode && !hasPassword) {
      _showSimpleDialog(
        context: context,
        title: '⚠️ 未设置密码',
        content: '为了防止宝宝误操作退出儿童模式，请先设置家长密码。',
        confirmText: '去设置',
        onConfirm: () {
          Navigator.of(context).pop();
          showSetPasswordDialog();
        },
      );
      return;
    }

    if (isChildMode) {
      _showPasswordInputDialog(context);
    } else {
      _showSimpleDialog(
        context: context,
        title: '切换到儿童模式',
        content: '儿童模式下将无法编辑数据，只能查看。确定要切换吗？',
        confirmText: '确定',
        onConfirm: () {
          Navigator.of(context).pop();
          switchToChildMode().then((_) {
            Get.snackbar(
              '👶 儿童模式',
              '已切换到儿童模式',
              snackPosition: SnackPosition.BOTTOM,
            );
          });
        },
      );
    }
  }

  /// 简单确认对话框
  void _showSimpleDialog({
    required BuildContext context,
    required String title,
    required String content,
    required String confirmText,
    required VoidCallback onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: onConfirm,
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }

  /// 密码输入对话框（用于从儿童模式切换到家长模式）
  void _showPasswordInputDialog(BuildContext context) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🔐 输入家长密码'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '请输入密码',
            prefixIcon: Icon(Icons.lock_outline),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final password = controller.text;
              final success = await switchToParentMode(password);
              if (success) {
                if (ctx.mounted) {
                  Navigator.of(ctx).pop();
                }
                Get.snackbar(
                  '👨‍👩‍👧 家长模式',
                  '已切换到家长模式',
                  snackPosition: SnackPosition.BOTTOM,
                );
              } else {
                Get.snackbar(
                  '❌ 密码错误',
                  '请输入正确的密码',
                  snackPosition: SnackPosition.BOTTOM,
                  backgroundColor: Colors.red.shade100,
                );
                controller.clear();
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 显示设置密码对话框（仅家长模式可用）
  void showSetPasswordDialog() {
    unawaited(_showSetPasswordDialogAsync());
  }

  Future<void> _showSetPasswordDialogAsync() async {
    await ensureInitialized();
    if (!isParentMode) {
      Get.snackbar('⚠️ 无权限', '请先切换到家长模式');
      return;
    }

    final context = Get.overlayContext;
    if (context == null) return;

    final pwdController = TextEditingController();
    final confirmController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(hasPassword ? '🔑 修改密码' : '🔑 设置密码'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pwdController,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '新密码',
                  hintText: '至少4位',
                  prefixIcon: Icon(Icons.lock_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: confirmController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '确认密码',
                  hintText: '再次输入密码',
                  prefixIcon: Icon(Icons.lock_outline),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final pwd = pwdController.text;
              final confirm = confirmController.text;

              if (pwd.isEmpty) {
                Get.snackbar('⚠️', '密码不能为空',
                    snackPosition: SnackPosition.BOTTOM);
                return;
              }
              if (pwd.length < 4) {
                Get.snackbar('⚠️', '密码至少4位',
                    snackPosition: SnackPosition.BOTTOM);
                return;
              }
              if (pwd != confirm) {
                Get.snackbar('⚠️', '两次密码不一致',
                    snackPosition: SnackPosition.BOTTOM);
                return;
              }

              try {
                await setPassword(pwd);
                if (ctx.mounted) {
                  Navigator.of(ctx).pop();
                }
                Get.snackbar(
                  '✅ 成功',
                  '密码已设置',
                  snackPosition: SnackPosition.BOTTOM,
                  backgroundColor: Colors.green.withValues(alpha: 0.1),
                );
              } catch (e) {
                Get.snackbar(
                  '❌ 错误',
                  '密码设置失败: $e',
                  snackPosition: SnackPosition.BOTTOM,
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
