import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../pages/settings_page.dart'; // 获取 appVersion 常量

/// GitHub Release 信息模型
class ReleaseInfo {
  final String tagName; // 版本标签，如 v1.2.0-20260124
  final String version; // 提取的版本号，如 1.2.0
  final String name; // Release 名称
  final String body; // Release 描述
  final String downloadUrl; // APK 下载链接
  final DateTime publishedAt;

  ReleaseInfo({
    required this.tagName,
    required this.version,
    required this.name,
    required this.body,
    required this.downloadUrl,
    required this.publishedAt,
  });

  factory ReleaseInfo.fromJson(Map<String, dynamic> json) {
    // 从 tag_name 提取版本号 (v1.2.0-xxx -> 1.2.0)
    final tagName = json['tag_name'] as String? ?? '';
    String version = tagName;
    if (version.startsWith('v')) {
      version = version.substring(1);
    }
    // 移除时间戳后缀 (1.2.0-20260124 -> 1.2.0)
    if (version.contains('-')) {
      version = version.split('-').first;
    }

    // 查找 APK 下载链接
    String downloadUrl = '';
    final assets = json['assets'] as List? ?? [];
    for (var asset in assets) {
      final name = asset['name'] as String? ?? '';
      if (name.endsWith('.apk')) {
        downloadUrl = asset['browser_download_url'] as String? ?? '';
        break;
      }
    }

    return ReleaseInfo(
      tagName: tagName,
      version: version,
      name: json['name'] as String? ?? '',
      body: json['body'] as String? ?? '',
      downloadUrl: downloadUrl,
      publishedAt:
          DateTime.tryParse(json['published_at'] ?? '') ?? DateTime.now(),
    );
  }
}

/// 更新检查服务
class UpdateService extends GetxService {
  // GitHub 仓库信息
  static const String owner = 'JoeNik';
  static const String repo = 'starbank';

  final RxBool isChecking = false.obs;
  final Rx<ReleaseInfo?> latestRelease = Rx<ReleaseInfo?>(null);

  /// 检查更新
  Future<bool> checkForUpdate({bool showNoUpdateMessage = false}) async {
    isChecking.value = true;

    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$owner/$repo/releases/latest'),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final release = ReleaseInfo.fromJson(json);
        latestRelease.value = release;

        // 比较版本号
        if (_isNewerVersion(release.version, appVersion)) {
          _showUpdateDialog(release);
          return true;
        } else if (showNoUpdateMessage) {
          Get.snackbar(
            '已是最新版本',
            '当前版本 v$appVersion 已是最新',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.green.withOpacity(0.9),
            colorText: Colors.white,
          );
        }
      } else if (showNoUpdateMessage) {
        Get.snackbar(
          '检查失败',
          '无法获取版本信息',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } catch (e) {
      if (showNoUpdateMessage) {
        Get.snackbar(
          '检查失败',
          '网络错误: $e',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } finally {
      isChecking.value = false;
    }

    return false;
  }

  /// 比较版本号，判断 newVersion 是否比 currentVersion 更新
  bool _isNewerVersion(String newVersion, String currentVersion) {
    try {
      final newParts = newVersion.split('.').map(int.parse).toList();
      final currentParts = currentVersion.split('.').map(int.parse).toList();

      // 补齐长度
      while (newParts.length < 3) newParts.add(0);
      while (currentParts.length < 3) currentParts.add(0);

      // 逐位比较
      for (int i = 0; i < 3; i++) {
        if (newParts[i] > currentParts[i]) return true;
        if (newParts[i] < currentParts[i]) return false;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// 显示更新对话框
  void _showUpdateDialog(ReleaseInfo release) {
    Get.dialog(
      AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
        title: Row(
          children: [
            Icon(Icons.system_update, color: Colors.blue, size: 28.sp),
            SizedBox(width: 10.w),
            const Text('发现新版本'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'v$appVersion',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14.sp,
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.w),
                    child: const Icon(Icons.arrow_forward, size: 16),
                  ),
                  Text(
                    'v${release.version}',
                    style: TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                      fontSize: 14.sp,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16.h),
            Text(
              '更新内容:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14.sp,
              ),
            ),
            SizedBox(height: 8.h),
            Container(
              constraints: BoxConstraints(maxHeight: 150.h),
              child: SingleChildScrollView(
                child: Text(
                  release.body.isNotEmpty ? release.body : '暂无更新说明',
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('稍后再说'),
          ),
          ElevatedButton(
            onPressed: () {
              Get.back();
              _downloadUpdate(release);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
            ),
            child: const Text('立即更新'),
          ),
        ],
      ),
      barrierDismissible: false,
    );
  }

  /// 下载更新
  Future<void> _downloadUpdate(ReleaseInfo release) async {
    if (release.downloadUrl.isEmpty) {
      Get.snackbar('错误', '未找到下载链接');
      return;
    }

    try {
      final uri = Uri.parse(release.downloadUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        Get.snackbar('错误', '无法打开下载链接');
      }
    } catch (e) {
      Get.snackbar('错误', '下载失败: $e');
    }
  }
}
