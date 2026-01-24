import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../services/webdav_service.dart';
import '../theme/app_theme.dart';

class WebDavSettingsPage extends StatefulWidget {
  const WebDavSettingsPage({super.key});

  @override
  State<WebDavSettingsPage> createState() => _WebDavSettingsPageState();
}

class _WebDavSettingsPageState extends State<WebDavSettingsPage> {
  final WebDavService webDavService = Get.find<WebDavService>();
  final urlController = TextEditingController();
  final userController = TextEditingController();
  final pwdController = TextEditingController();

  final RxList<String> backupFiles = <String>[].obs;
  final RxBool isLoading = false.obs;

  @override
  void initState() {
    super.initState();
    urlController.text = webDavService.currentUrl.value;
    userController.text = webDavService.currentUser.value;

    if (urlController.text.isNotEmpty) {
      _loadBackups();
    }
  }

  Future<void> _loadBackups() async {
    isLoading.value = true;
    try {
      final files = await webDavService.listBackups();
      backupFiles.assignAll(files.reversed.toList()); // Newest first
    } catch (e) {
      Get.snackbar("错误", "获取备份列表失败: $e");
    } finally {
      isLoading.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("云端备份配置")),
      backgroundColor: AppTheme.bgBlue,
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildConfigCard(),
            SizedBox(height: 16.h),
            _buildBackupSettingsCard(),
            SizedBox(height: 16.h),
            _buildActionCard(),
            SizedBox(height: 16.h),
            _buildBackupListCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          children: [
            Text(
              "WebDAV 配置",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.sp),
            ),
            SizedBox(height: 16.h),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                labelText: "服务器地址",
                hintText: "https://dav.jianguoyun.com/dav/",
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 12.h),
            TextField(
              controller: userController,
              decoration: const InputDecoration(
                labelText: "账号",
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 12.h),
            TextField(
              controller: pwdController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "密码/应用令牌",
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 16.h),
            ElevatedButton(
              onPressed: () {
                if (urlController.text.isEmpty) {
                  Get.snackbar("错误", "请输入服务器地址");
                  return;
                }
                webDavService.initClient(
                  urlController.text,
                  userController.text,
                  pwdController.text,
                );
                Get.snackbar("成功", "配置已保存 (当前会话有效)");
                _loadBackups(); // Try to load backups directly
              },
              child: const Text("保存并连接"),
            ),
          ],
        ),
      ),
    );
  }

  /// 备份设置卡片
  Widget _buildBackupSettingsCard() {
    final maxCount = webDavService.maxBackupCount.obs;
    final options = [5, 10, 20, 50, 0]; // 0 表示不限制

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "备份设置",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.sp),
            ),
            SizedBox(height: 16.h),
            Row(
              children: [
                Icon(Icons.storage_outlined,
                    color: AppTheme.textSub, size: 20.sp),
                SizedBox(width: 12.w),
                Expanded(
                  child: Text(
                    "最大备份数量",
                    style: TextStyle(fontSize: 14.sp),
                  ),
                ),
                Obx(() => DropdownButton<int>(
                      value: maxCount.value,
                      underline: const SizedBox(),
                      borderRadius: BorderRadius.circular(12.r),
                      items: options.map((count) {
                        return DropdownMenuItem(
                          value: count,
                          child: Text(
                            count == 0 ? '不限制' : '$count 个',
                            style: TextStyle(fontSize: 14.sp),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          maxCount.value = value;
                          webDavService.setMaxBackupCount(value);
                          Get.snackbar(
                            '设置已保存',
                            value == 0 ? '备份数量不限制' : '最多保留 $value 个备份',
                            snackPosition: SnackPosition.BOTTOM,
                          );
                        }
                      },
                    )),
              ],
            ),
            SizedBox(height: 8.h),
            Text(
              '超过限制时会自动删除最早的备份',
              style: TextStyle(fontSize: 12.sp, color: AppTheme.textSub),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          children: [
            Text(
              "操作",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.sp),
            ),
            SizedBox(height: 16.h),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      isLoading.value = true;
                      await webDavService.backupData();
                      isLoading.value = false;
                      _loadBackups();
                    },
                    icon: const Icon(Icons.cloud_upload),
                    label: const Text("立即备份"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                    ),
                  ),
                ),
                SizedBox(width: 16.w),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loadBackups,
                    icon: const Icon(Icons.refresh),
                    label: const Text("刷新列表"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackupListCard() {
    return Obx(() {
      if (isLoading.value) {
        return const Center(child: CircularProgressIndicator());
      }
      return Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
        ),
        child: Padding(
          padding: EdgeInsets.all(16.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "可用备份",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.sp),
              ),
              SizedBox(height: 10.h),
              if (backupFiles.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Text("暂无备份文件"),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: backupFiles.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, index) {
                    final filename = backupFiles[index];
                    return ListTile(
                      leading: const Icon(
                        Icons.restore_page,
                        color: Colors.orange,
                      ),
                      title: Text(filename),
                      subtitle: Text("点击恢复此版本"),
                      onTap: () => _confirmRestore(filename),
                    );
                  },
                ),
            ],
          ),
        ),
      );
    });
  }

  void _confirmRestore(String filename) {
    Get.defaultDialog(
      title: "确认恢复?",
      middleText: "恢复数据将覆盖当前所有本地数据，且无法撤销！\n建议先备份当前数据。",
      textConfirm: "确定恢复",
      textCancel: "取消",
      confirmTextColor: Colors.white,
      onConfirm: () async {
        Get.back(); // close dialog
        isLoading.value = true;
        await webDavService.restoreData(filename);
        isLoading.value = false;
      },
    );
  }
}
