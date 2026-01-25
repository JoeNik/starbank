import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
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
    // 读取上次的模式（默认家长模式）
    final savedMode = _settingsBox.get(_modeKey, defaultValue: 'parent');
    currentMode.value = savedMode == 'child' ? AppMode.child : AppMode.parent;
  }

  /// 是否是家长模式
  bool get isParentMode => currentMode.value == AppMode.parent;

  /// 是否是儿童模式
  bool get isChildMode => currentMode.value == AppMode.child;

  /// 是否已设置密码
  bool get hasPassword => _settingsBox.containsKey(_passwordKey);

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
    if (storedHash == null) return true; // 未设置密码，直接通过
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
    if (isChildMode) {
      // 从儿童模式切换到家长模式，需要输入密码
      _showPasswordDialog();
    } else {
      // 从家长模式切换到儿童模式
      Get.defaultDialog(
        title: '切换到儿童模式',
        middleText: '儿童模式下将无法编辑数据，只能查看。确定要切换吗？',
        textConfirm: '确定',
        textCancel: '取消',
        confirmTextColor: Colors.white,
        onConfirm: () {
          switchToChildMode();
          Get.back();
          Get.snackbar(
            '👶 儿童模式',
            '已切换到儿童模式',
            snackPosition: SnackPosition.BOTTOM,
          );
        },
      );
    }
  }

  /// 密码验证对话框
  void _showPasswordDialog() {
    final passwordController = TextEditingController();
    final RxBool obscureText = true.obs;

    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: Container(
          padding: EdgeInsets.all(24.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '🔐',
                style: TextStyle(fontSize: 40.sp),
              ),
              SizedBox(height: 16.h),
              Text(
                '输入家长密码',
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                '请输入密码以切换到家长模式',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 13.sp,
                ),
              ),
              SizedBox(height: 20.h),
              Obx(() => TextField(
                    controller: passwordController,
                    obscureText: obscureText.value,
                    decoration: InputDecoration(
                      hintText: '请输入密码',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureText.value
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () => obscureText.toggle(),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                  )),
              SizedBox(height: 20.h),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Get.back(),
                      child: const Text('取消'),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final success = await switchToParentMode(
                          passwordController.text,
                        );
                        if (success) {
                          Get.back();
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
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                      ),
                      child: const Text('确定'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 显示设置密码对话框（仅家长模式可用）
  void showSetPasswordDialog() {
    if (!isParentMode) {
      Get.snackbar('⚠️ 无权限', '请先切换到家长模式');
      return;
    }

    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    final RxBool obscureText = true.obs;

    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: Container(
          padding: EdgeInsets.all(24.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '🔑',
                style: TextStyle(fontSize: 40.sp),
              ),
              SizedBox(height: 16.h),
              Text(
                hasPassword ? '修改密码' : '设置密码',
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 20.h),
              Obx(() => TextField(
                    controller: passwordController,
                    obscureText: obscureText.value,
                    decoration: InputDecoration(
                      hintText: '请输入新密码',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                  )),
              SizedBox(height: 12.h),
              Obx(() => TextField(
                    controller: confirmController,
                    obscureText: obscureText.value,
                    decoration: InputDecoration(
                      hintText: '确认密码',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureText.value
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () => obscureText.toggle(),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                  )),
              SizedBox(height: 20.h),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Get.back(),
                      child: const Text('取消'),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        if (passwordController.text.isEmpty) {
                          Get.snackbar('⚠️ 提示', '密码不能为空');
                          return;
                        }
                        if (passwordController.text.length < 4) {
                          Get.snackbar('⚠️ 提示', '密码至少4位');
                          return;
                        }
                        if (passwordController.text != confirmController.text) {
                          Get.snackbar('⚠️ 提示', '两次密码不一致');
                          return;
                        }
                        await setPassword(passwordController.text);
                        Get.back();
                        Get.snackbar(
                          '✅ 成功',
                          '密码已设置',
                          snackPosition: SnackPosition.BOTTOM,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                      ),
                      child: const Text('保存'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
