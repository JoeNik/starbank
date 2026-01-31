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

  final RxList<String> backupFiles = <String>[].obs; // 所有备份文件
  final RxList<String> displayBackups = <String>[].obs; // 当前显示的备份文件
  final int _pageSize = 10; // 每页显示数量

  final RxBool isLoading = false.obs;
  final RxBool obscurePassword = true.obs; // 密码隐藏状态
  final RxBool isConnected = false.obs; // 连接状态
  final RxString connectionStatus = '未连接'.obs; // 连接状态文本

  @override
  void initState() {
    super.initState();
    urlController.text = webDavService.currentUrl.value;
    userController.text = webDavService.currentUser.value;

    // 从缓存中读取密码
    _loadCachedPassword();

    if (urlController.text.isNotEmpty) {
      _checkConnection();
    }
  }

  /// 从缓存读取密码
  void _loadCachedPassword() {
    try {
      final pwd = webDavService.getCachedPassword();
      if (pwd != null && pwd.isNotEmpty) {
        pwdController.text = pwd;
      }
    } catch (e) {
      debugPrint('读取缓存密码失败: $e');
    }
  }

  /// 检查连接状态
  Future<void> _checkConnection() async {
    connectionStatus.value = '连接中...';
    isConnected.value = false;

    try {
      final files = await webDavService.listBackups();
      backupFiles.assignAll(files.reversed.toList());

      // 初始化显示列表
      displayBackups.clear();
      _loadMore();

      isConnected.value = true;
      connectionStatus.value = '已连接';
    } catch (e) {
      isConnected.value = false;
      connectionStatus.value = '连接失败';
    }
  }

  Future<void> _loadBackups() async {
    isLoading.value = true;
    try {
      final files = await webDavService.listBackups();
      backupFiles.assignAll(files.reversed.toList());

      // 重置分页
      displayBackups.clear();
      _loadMore();
    } catch (e) {
      Get.snackbar("错误", "获取备份列表失败: $e");
    } finally {
      isLoading.value = false;
    }
  }

  /// 加载更多备份
  void _loadMore() {
    final currentLength = displayBackups.length;
    final total = backupFiles.length;
    if (currentLength >= total) return;

    final nextCount = (currentLength + _pageSize).clamp(0, total);
    displayBackups.addAll(backupFiles.sublist(currentLength, nextCount));
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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "WebDAV 配置",
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 16.sp),
                ),
                SizedBox(width: 8.w),
                // 连接状态指示器
                Obx(() => Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                      decoration: BoxDecoration(
                        color: isConnected.value
                            ? Colors.green.shade100
                            : (connectionStatus.value == '连接中...'
                                ? Colors.orange.shade100
                                : Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isConnected.value
                                ? Icons.cloud_done
                                : (connectionStatus.value == '连接中...'
                                    ? Icons.cloud_sync
                                    : Icons.cloud_off),
                            size: 12.sp,
                            color: isConnected.value
                                ? Colors.green
                                : (connectionStatus.value == '连接中...'
                                    ? Colors.orange
                                    : Colors.grey),
                          ),
                          SizedBox(width: 4.w),
                          Text(
                            connectionStatus.value,
                            style: TextStyle(
                              fontSize: 10.sp,
                              color: isConnected.value
                                  ? Colors.green
                                  : (connectionStatus.value == '连接中...'
                                      ? Colors.orange
                                      : Colors.grey),
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
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
            Obx(() => TextField(
                  controller: pwdController,
                  obscureText: obscurePassword.value,
                  decoration: InputDecoration(
                    labelText: "密码/应用令牌",
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscurePassword.value
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () {
                        obscurePassword.value = !obscurePassword.value;
                      },
                    ),
                  ),
                )),
            SizedBox(height: 16.h),
            ElevatedButton.icon(
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
                Get.snackbar("成功", "配置已保存");
                _checkConnection(); // 检查连接并刷新列表
              },
              icon: const Icon(Icons.save),
              label: const Text("保存并连接"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
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
                  child: Obx(() => ElevatedButton.icon(
                        onPressed: isLoading.value
                            ? null
                            : () async {
                                isLoading.value = true;
                                await webDavService.backupData();
                                isLoading.value = false;
                                _loadBackups();
                              },
                        icon: isLoading.value
                            ? SizedBox(
                                width: 14.w,
                                height: 14.w,
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : Icon(Icons.cloud_upload, size: 18.sp),
                        label: Text(isLoading.value ? "备份中" : "备份",
                            style: TextStyle(fontSize: 14.sp)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          padding: EdgeInsets.symmetric(vertical: 8.h),
                          minimumSize: Size(0, 36.h),
                        ),
                      )),
                ),
                SizedBox(width: 16.w),
                Expanded(
                  child: Obx(() => ElevatedButton.icon(
                        onPressed: isLoading.value ? null : _loadBackups,
                        icon: isLoading.value
                            ? SizedBox(
                                width: 14.w,
                                height: 14.w,
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : Icon(Icons.refresh, size: 18.sp),
                        label: Text(isLoading.value ? "读取中" : "刷新",
                            style: TextStyle(fontSize: 14.sp)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 8.h),
                          minimumSize: Size(0, 36.h),
                        ),
                      )),
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
              if (displayBackups.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Text("暂无备份文件"),
                  ),
                )
              else
                SizedBox(
                  height: 400.h,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (ScrollNotification scrollInfo) {
                      if (scrollInfo.metrics.pixels >=
                          scrollInfo.metrics.maxScrollExtent - 50) {
                        _loadMore();
                      }
                      return false;
                    },
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: displayBackups.length +
                          (displayBackups.length < backupFiles.length ? 1 : 0),
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, index) {
                        if (index == displayBackups.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          );
                        }
                        final filename = displayBackups[index];
                        return ListTile(
                          leading: const Icon(
                            Icons.restore_page,
                            color: Colors.orange,
                          ),
                          title: Text(filename),
                          subtitle: const Text("点击恢复此版本"),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _confirmDelete(filename),
                          ),
                          onTap: () => _confirmRestore(filename),
                        );
                      },
                    ),
                  ),
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

  void _confirmDelete(String filename) {
    Get.defaultDialog(
      title: "确认删除?",
      middleText: "删除后无法恢复,确定要删除这个备份吗?\n\n$filename",
      textConfirm: "确定删除",
      textCancel: "取消",
      confirmTextColor: Colors.white,
      buttonColor: Colors.red,
      onConfirm: () async {
        Get.back(); // close dialog
        isLoading.value = true;
        final success = await webDavService.deleteBackup(filename);
        isLoading.value = false;
        if (success) {
          _loadBackups(); // 刷新列表
        }
      },
    );
  }
}
