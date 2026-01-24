import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../controllers/user_controller.dart';
import 'webdav_settings_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final UserController userController = Get.find<UserController>();

    return Scaffold(
      appBar: AppBar(title: const Text("系统设置")),
      body: ListView(
        padding: EdgeInsets.all(16.w),
        children: [
          _buildSection("个人信息"),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16.r),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline, color: Colors.blue),
                  title: const Text("家长称呼"),
                  subtitle: Obx(() => Text(userController.parentName.value)),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => _updateNameDialog(userController),
                ),
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
                ListTile(
                  leading: const Icon(Icons.percent, color: Colors.orange),
                  title: const Text("年化收益率"),
                  subtitle: Obx(
                    () => Text(
                      "${(userController.currentInterestRate.value * 100).toStringAsFixed(1)}%",
                    ),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => _updateInterestDialog(userController),
                ),
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
                ListTile(
                  leading: const Icon(Icons.cloud_sync, color: Colors.purple),
                  title: const Text("云端备份 (WebDAV)"),
                  subtitle: const Text("配置 WebDAV 服务以备份和恢复数据"),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => Get.to(() => const WebDavSettingsPage()),
                ),
              ],
            ),
          ),

          SizedBox(height: 40.h),
          const Center(
            child: Text(
              "Star Bank v1.0.0\nMade with ❤️ for Kids",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
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
}
