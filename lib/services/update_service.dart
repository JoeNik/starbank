import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';

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

    // 移除 v 前缀
    if (version.startsWith('v')) {
      version = version.substring(1);
    }

    // 移除时间戳后缀 (1.2.0-20260124 -> 1.2.0)
    if (version.contains('-')) {
      version = version.split('-').first;
    }

    // 移除 build number (+5 等)
    if (version.contains('+')) {
      version = version.split('+').first;
    }

    debugPrint('UpdateService: tagName=$tagName, version=$version');

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
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$owner/$repo/releases/latest'),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final release = ReleaseInfo.fromJson(json);
        latestRelease.value = release;

        // 比较版本号
        if (_isNewerVersion(release.version, currentVersion)) {
          _showUpdateDialog(release, currentVersion);
          return true;
        } else if (showNoUpdateMessage) {
          Get.snackbar(
            '已是最新版本',
            '当前版本 v$currentVersion 已是最新',
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
  void _showUpdateDialog(ReleaseInfo release, String currentVersion) {
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
                    'v$currentVersion',
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

    // 显示下载选项
    final context = Get.overlayContext;
    if (context == null) return;

    showModalBottomSheet(
      context: context,
      builder: (ctx) => Container(
        padding: EdgeInsets.all(20.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '选择下载方式',
              style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16.h),

            // 应用内下载 (推荐)
            ListTile(
              leading: const Icon(Icons.download, color: Colors.blue),
              title: const Text('应用内下载'),
              subtitle: const Text('显示下载进度，完成后可直接安装'),
              onTap: () {
                Navigator.of(ctx).pop();
                _startInAppDownload(release);
              },
            ),

            // 镜像下载 (ghproxy)
            ListTile(
              leading: const Icon(Icons.speed, color: Colors.green),
              title: const Text('镜像加速下载'),
              subtitle: const Text('使用 ghproxy 加速（推荐国内用户）'),
              onTap: () {
                Navigator.of(ctx).pop();
                _startInAppDownload(release, useMirror: true);
              },
            ),

            // 浏览器下载
            ListTile(
              leading: const Icon(Icons.open_in_browser, color: Colors.orange),
              title: const Text('在浏览器中下载'),
              subtitle: const Text('跳转到浏览器下载'),
              onTap: () async {
                Navigator.of(ctx).pop();
                try {
                  final mirrorUrl =
                      'https://ghproxy.com/${release.downloadUrl}';
                  final uri = Uri.parse(mirrorUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                } catch (e) {
                  Get.snackbar('错误', '无法打开浏览器: $e');
                }
              },
            ),

            // 复制链接
            ListTile(
              leading: const Icon(Icons.copy, color: Colors.grey),
              title: const Text('复制下载链接'),
              subtitle: const Text('手动下载'),
              onTap: () async {
                Navigator.of(ctx).pop();
                await Clipboard.setData(
                    ClipboardData(text: release.downloadUrl));
                Get.snackbar(
                  '已复制',
                  '下载链接已复制到剪贴板',
                  snackPosition: SnackPosition.BOTTOM,
                );
              },
            ),

            SizedBox(height: 16.h),
          ],
        ),
      ),
    );
  }

  /// 应用内下载
  Future<void> _startInAppDownload(ReleaseInfo release,
      {bool useMirror = false}) async {
    // 下载进度状态
    final RxDouble progress = 0.0.obs;
    final RxString status = '准备下载...'.obs;
    final RxBool isDownloading = true.obs;
    String? downloadedFilePath;

    // 显示下载进度对话框
    Get.dialog(
      WillPopScope(
        onWillPop: () async => !isDownloading.value,
        child: AlertDialog(
          title: Row(
            children: [
              Icon(Icons.download, color: Colors.blue, size: 24.sp),
              SizedBox(width: 8.w),
              const Text('下载更新'),
            ],
          ),
          content: Obx(() => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(status.value),
                  SizedBox(height: 16.h),
                  LinearProgressIndicator(
                    value: progress.value > 0 ? progress.value : null,
                    backgroundColor: Colors.grey.shade200,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.blue),
                  ),
                  SizedBox(height: 8.h),
                  if (progress.value > 0)
                    Text(
                      '${(progress.value * 100).toStringAsFixed(1)}%',
                      style: TextStyle(fontSize: 12.sp, color: Colors.grey),
                    ),
                ],
              )),
          actions: [
            Obx(() => isDownloading.value
                ? TextButton(
                    onPressed: () {
                      isDownloading.value = false;
                      Get.back();
                    },
                    child: const Text('取消'),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Get.back(),
                        child: const Text('关闭'),
                      ),
                      if (downloadedFilePath != null)
                        ElevatedButton(
                          onPressed: () {
                            Get.back();
                            _installApk(downloadedFilePath!);
                          },
                          child: const Text('安装'),
                        ),
                    ],
                  )),
          ],
        ),
      ),
      barrierDismissible: false,
    );

    try {
      // 构建下载链接
      String downloadUrl = release.downloadUrl;
      if (useMirror) {
        downloadUrl = 'https://ghproxy.com/$downloadUrl';
      }

      status.value = '正在连接服务器...';

      // 获取下载目录
      Directory? dir;
      if (Platform.isAndroid) {
        // Android Specific: Try modern approach first
        try {
          dir = await getDownloadsDirectory();
        } catch (e) {
          dir = null;
        }

        // Fallback or specific handling
        if (dir == null) {
          // Verify SDK version isn't easily possible without device_info,
          // but we can try permissions if we really want strict public access.
          // However, for updates, app-specific storage is safer and guaranteed writable.

          // Try app-specific external storage first (Backwards compatible & Scoped Storage friendly)
          dir = await getExternalStorageDirectory();
        }
      } else {
        try {
          dir = await getDownloadsDirectory();
        } catch (e) {
          dir = null;
        }
      }

      if (dir == null) {
        dir = await getTemporaryDirectory();
      }

      final fileName = 'StarBank_${release.version}.apk';
      final filePath = '${dir.path}/$fileName';
      final file = File(filePath);

      // 发起请求
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final response = await http.Client().send(request);

      if (response.statusCode != 200) {
        throw Exception('服务器返回错误: ${response.statusCode}');
      }

      final contentLength = response.contentLength ?? 0;
      int received = 0;

      status.value = '正在下载...';

      // 下载文件
      final sink = file.openWrite();
      await for (final chunk in response.stream) {
        if (!isDownloading.value) {
          sink.close();
          file.deleteSync();
          return;
        }
        sink.add(chunk);
        received += chunk.length;
        if (contentLength > 0) {
          progress.value = received / contentLength;
        }
      }
      await sink.close();

      // 下载完成
      isDownloading.value = false;
      progress.value = 1.0;
      status.value = '下载完成！点击安装按钮进行安装';
      downloadedFilePath = filePath;
    } catch (e) {
      isDownloading.value = false;
      status.value = '下载失败: $e';
      debugPrint('下载更新失败: $e');
    }
  }

  /// 安装 APK
  Future<void> _installApk(String filePath) async {
    try {
      final result = await OpenFilex.open(filePath);
      if (result.type != ResultType.done) {
        Get.snackbar(
          '安装失败',
          result.message,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } catch (e) {
      Get.snackbar(
        '安装失败',
        '无法打开安装程序: $e',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }
}
