import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 应用模式枚举
enum AppMode {
  parent, // 家长模式 - 完全控制
  child, // 儿童模式 - 只读
}

/// 应用模式控制器
/// 管理家长/儿童模式切换，密码验证等
class AppModeController extends GetxController {
  // 当前模式
  final Rx<AppMode> currentMode = AppMode.parent.obs;

  // 存储 box
  late Box _settingsBox;
  bool _isInitialized = false;

  // 密码存储的 key
  static const String _passwordKey = 'parent_password_hash';
  static const String _modeKey = 'current_mode';

  @override
  void onInit() {
    super.onInit();
    _initSettings();
  }

  Future<void> _initSettings() async {
    _settingsBox = await Hive.openBox('app_settings');
    final savedMode = _settingsBox.get(_modeKey, defaultValue: 'parent');
    currentMode.value = savedMode == 'child' ? AppMode.child : AppMode.parent;
    _isInitialized = true;
  }

  /// 是否是家长模式
  bool get isParentMode => currentMode.value == AppMode.parent;

  /// 是否是儿童模式
  bool get isChildMode => currentMode.value == AppMode.child;

  /// 是否已设置密码
  bool get hasPassword {
    if (!_isInitialized) return false;
    return _settingsBox.containsKey(_passwordKey);
  }

  /// 获取密码哈希（用于云端备份）
  String? get passwordHash => _settingsBox.get(_passwordKey);

  /// 设置密码（SHA256 加密）
  Future<void> setPassword(String password) async {
    final hash = _hashPassword(password);
    await _settingsBox.put(_passwordKey, hash);
  }

  /// 从云端恢复密码哈希
  Future<void> restorePasswordHash(String hash) async {
    await _settingsBox.put(_passwordKey, hash);
  }

  /// 验证密码
  bool verifyPassword(String password) {
    final storedHash = _settingsBox.get(_passwordKey);
    if (storedHash == null) return true;
    return _hashPassword(password) == storedHash;
  }

  /// 切换到家长模式（需要密码验证）
  Future<bool> switchToParentMode(String password) async {
    if (!hasPassword || verifyPassword(password)) {
      currentMode.value = AppMode.parent;
      await _settingsBox.put(_modeKey, 'parent');
      return true;
    }
    return false;
  }

  /// 切换到儿童模式
  Future<void> switchToChildMode() async {
    currentMode.value = AppMode.child;
    await _settingsBox.put(_modeKey, 'child');
  }

  /// 密码哈希函数
  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// 显示切换模式对话框
  void showModeSwitchDialog() {
    final context = Get.overlayContext;
    if (context == null) return;

    // 如果当前是家长模式，准备切换到儿童模式，必须先检查是否设置了密码
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
          switchToChildMode();
          Get.snackbar('👶 儿童模式', '已切换到儿童模式',
              snackPosition: SnackPosition.BOTTOM);
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
            onPressed: () {
              final password = controller.text;
              switchToParentMode(password).then((success) {
                if (success) {
                  Navigator.of(ctx).pop();
                  Get.snackbar('👨‍👩‍👧 家长模式', '已切换到家长模式',
                      snackPosition: SnackPosition.BOTTOM);
                } else {
                  Get.snackbar('❌ 密码错误', '请输入正确的密码',
                      snackPosition: SnackPosition.BOTTOM,
                      backgroundColor: Colors.red.shade100);
                  controller.clear();
                }
              });
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
      barrierDismissible: false, // 防止误触关闭
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
            onPressed: () {
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

              // 使用 then 避免 async 问题
              setPassword(pwd).then((_) {
                Navigator.of(ctx).pop();
                Get.snackbar('✅ 成功', '密码已设置',
                    snackPosition: SnackPosition.BOTTOM,
                    backgroundColor: Colors.green.withOpacity(0.1));
              }).catchError((e) {
                Get.snackbar('❌ 错误', '密码设置失败: $e',
                    snackPosition: SnackPosition.BOTTOM);
              });
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
