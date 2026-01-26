import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../controllers/user_controller.dart';
import '../controllers/app_mode_controller.dart';
import '../services/update_service.dart';
import 'webdav_settings_page.dart';
import 'openai_settings_page.dart';

/// 应用版本号 - 每次更新时同步修改 pubspec.yaml 中的 version
const String appVersion = '2.1.4';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final UserController userController = Get.find<UserController>();
    final AppModeController modeController = Get.find<AppModeController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text("系统设置"),
        actions: [
          // 当前模式指示器
          Obx(() => Container(
                margin: EdgeInsets.only(right: 16.w),
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: modeController.isParentMode
                      ? Colors.blue.shade50
                      : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(20.r),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      modeController.isParentMode
                          ? Icons.admin_panel_settings
                          : Icons.child_care,
                      size: 16.sp,
                      color: modeController.isParentMode
                          ? Colors.blue
                          : Colors.green,
                    ),
                    SizedBox(width: 4.w),
                    Text(
                      modeController.isParentMode ? '家长' : '儿童',
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: modeController.isParentMode
                            ? Colors.blue
                            : Colors.green,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.all(16.w),
        children: [
          // 模式切换区域
          _buildSection("👨‍👩‍👧 模式控制"),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16.r),
            ),
            child: Column(
              children: [
                Obx(() => ListTile(
                      leading: Icon(
                        modeController.isParentMode
                            ? Icons.admin_panel_settings
                            : Icons.child_care,
                        color: modeController.isParentMode
                            ? Colors.blue
                            : Colors.green,
                      ),
                      title:
                          Text(modeController.isParentMode ? "家长模式" : "儿童模式"),
                      subtitle: Text(modeController.isParentMode
                          ? "可编辑所有数据"
                          : "仅可查看，无法编辑"),
                      trailing: TextButton(
                        onPressed: () => modeController.showModeSwitchDialog(),
                        child: Text(modeController.isParentMode
                            ? "切换到儿童模式"
                            : "切换到家长模式"),
                      ),
                    )),
                // 密码设置（仅家长模式显示）
                Obx(() => modeController.isParentMode
                    ? Column(
                        children: [
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.lock_outline,
                                color: Colors.purple),
                            title: Text(
                                modeController.hasPassword ? "修改密码" : "设置密码"),
                            subtitle: Text(modeController.hasPassword
                                ? "已设置密码保护"
                                : "建议设置密码保护儿童模式"),
                            trailing:
                                const Icon(Icons.arrow_forward_ios, size: 16),
                            onTap: () => modeController.showSetPasswordDialog(),
                          ),
                        ],
                      )
                    : const SizedBox()),
              ],
            ),
          ),
          SizedBox(height: 20.h),

          _buildSection("个人信息"),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16.r),
            ),
            child: Column(
              children: [
                // 家长模式才能编辑
                Obx(() => ListTile(
                      leading:
                          const Icon(Icons.person_outline, color: Colors.blue),
                      title: const Text("家长称呼"),
                      subtitle: Text(userController.parentName.value),
                      trailing: modeController.isParentMode
                          ? const Icon(Icons.arrow_forward_ios, size: 16)
                          : const Icon(Icons.lock,
                              size: 16, color: Colors.grey),
                      onTap: modeController.isParentMode
                          ? () => _updateNameDialog(userController)
                          : null,
                    )),
              ],
            ),
          ),
          SizedBox(height: 20.h),
          _buildSection("银行设置"),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16.r),
            ),
            child: Column(
              children: [
                Obx(() => ListTile(
                      leading: const Icon(Icons.percent, color: Colors.orange),
                      title: const Text("年化收益率"),
                      subtitle: Text(
                        "${(userController.currentInterestRate.value * 100).toStringAsFixed(1)}%",
                      ),
                      trailing: modeController.isParentMode
                          ? const Icon(Icons.arrow_forward_ios, size: 16)
                          : const Icon(Icons.lock,
                              size: 16, color: Colors.grey),
                      onTap: modeController.isParentMode
                          ? () => _updateInterestDialog(userController)
                          : null,
                    )),
              ],
            ),
          ),
          SizedBox(height: 20.h),
          _buildSection("数据与安全"),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16.r),
            ),
            child: Column(
              children: [
                Obx(() => ListTile(
                      leading:
                          const Icon(Icons.cloud_sync, color: Colors.purple),
                      title: const Text("云端备份 (WebDAV)"),
                      subtitle: const Text("配置 WebDAV 服务以备份和恢复数据"),
                      trailing: modeController.isParentMode
                          ? const Icon(Icons.arrow_forward_ios, size: 16)
                          : const Icon(Icons.lock,
                              size: 16, color: Colors.grey),
                      onTap: modeController.isParentMode
                          ? () => Get.to(() => const WebDavSettingsPage())
                          : null,
                    )),
                const Divider(height: 1),
                Obx(() => ListTile(
                      leading: const Icon(Icons.psychology, color: Colors.blue),
                      title: const Text("AI 设置"),
                      subtitle: const Text("配置 OpenAI 兼容的 API"),
                      trailing: modeController.isParentMode
                          ? const Icon(Icons.arrow_forward_ios, size: 16)
                          : const Icon(Icons.lock,
                              size: 16, color: Colors.grey),
                      onTap: modeController.isParentMode
                          ? () => Get.to(() => const OpenAISettingsPage())
                          : null,
                    )),
              ],
            ),
          ),
          SizedBox(height: 20.h),
          _buildSection("关于"),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16.r),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.system_update, color: Colors.blue),
                  title: const Text("检查更新"),
                  subtitle: Text("当前版本 v$appVersion"),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Get.find<UpdateService>()
                        .checkForUpdate(showNoUpdateMessage: true);
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.info_outline, color: Colors.teal),
                  title: const Text("关于应用"),
                  subtitle: const Text("Star Bank - 儿童星星银行"),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => _showAboutDialog(),
                ),
              ],
            ),
          ),
          SizedBox(height: 30.h),
          Center(
            child: Column(
              children: [
                Text(
                  "Star Bank v$appVersion",
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4.h),
                const Text(
                  "Made with ❤️ for Kids",
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          SizedBox(height: 20.h),
        ],
      ),
    );
  }

  Widget _buildSection(String title) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 16.w),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.orange.shade700,
          fontWeight: FontWeight.bold,
          fontSize: 14.sp,
        ),
      ),
    );
  }

  void _updateNameDialog(UserController controller) {
    final textController = TextEditingController(
      text: controller.parentName.value,
    );
    Get.dialog(
      AlertDialog(
        title: const Text("修改名称"),
        content: TextField(controller: textController),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text("取消")),
          TextButton(
            onPressed: () {
              controller.updateParentName(textController.text);
              Get.back();
            },
            child: const Text("确认"),
          ),
        ],
      ),
    );
  }

  void _updateInterestDialog(UserController controller) {
    final textController = TextEditingController(
      text: (controller.currentInterestRate.value * 100).toString(),
    );
    Get.defaultDialog(
      title: "设置年化收益率",
      content: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: TextField(
          controller: textController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: "百分比 (%)",
            suffixText: "%",
          ),
        ),
      ),
      textConfirm: "保存",
      textCancel: "取消",
      onConfirm: () {
        final val = double.tryParse(textController.text);
        if (val != null) {
          controller.updateInterestRate(val / 100.0);
          Get.back();
        } else {
          Get.snackbar("错误", "请输入有效的数字");
        }
      },
    );
  }

  void _showAboutDialog() {
    Get.dialog(
      AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
        title: Row(
          children: [
            Text('⭐', style: TextStyle(fontSize: 28.sp)),
            SizedBox(width: 10.w),
            const Text('Star Bank'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '儿童星星银行',
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 12.h),
            Text(
              '一款帮助家长培养孩子良好行为习惯的应用。\n\n'
              '通过星星奖励机制，让孩子在完成任务后获得虚拟星星，'
              '积累星星可以兑换心愿礼物。',
              style: TextStyle(
                fontSize: 14.sp,
                color: Colors.grey.shade700,
                height: 1.5,
              ),
            ),
            SizedBox(height: 16.h),
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Row(
                children: [
                  Icon(Icons.verified, color: Colors.blue, size: 20.sp),
                  SizedBox(width: 8.w),
                  Text(
                    '版本 v$appVersion',
                    style: TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
