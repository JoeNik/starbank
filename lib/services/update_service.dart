import 'dart:convert';
import 'dart:io';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:hive/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../widgets/toast_utils.dart';

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

/// UpdateService
class UpdateService extends GetxService {
  // GitHub 仓库信息
  static const String owner = 'JoeNik';
  static const String repo = 'starbank';

  final RxBool isChecking = false.obs;
  final Rx<ReleaseInfo?> latestRelease = Rx<ReleaseInfo?>(null);

  // Settings box
  Box? _settingsBox;

  @override
  void onInit() {
    super.onInit();
    _initBox();
  }

  Future<void> _initBox() async {
    _settingsBox = await Hive.openBox('update_settings');
  }

  /// 检查更新
  Future<bool> checkForUpdate({bool showNoUpdateMessage = false}) async {
    isChecking.value = true;

    try {
      if (_settingsBox == null) await _initBox(); // Ensure box is open

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
          // Check if ignored
          final ignoredVersion = _settingsBox?.get('ignored_version');

          // 如果是自动检查（!showNoUpdateMessage）且该版本已被忽略，则不提示
          if (!showNoUpdateMessage && ignoredVersion == release.version) {
            debugPrint('Version ${release.version} is ignored.');
            return false;
          }

          _showUpdateDialog(release, currentVersion);
          return true;
        } else if (showNoUpdateMessage) {
          ToastUtils.showSuccess('当前版本 v$currentVersion 已是最新');
        }
      } else if (showNoUpdateMessage) {
        ToastUtils.showError('无法获取版本信息');
      }
    } catch (e) {
      if (showNoUpdateMessage) {
        ToastUtils.showError('网络错误: $e');
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
                child: MarkdownBody(
                  data: release.body.isNotEmpty ? release.body : '暂无更新说明',
                  styleSheet: MarkdownStyleSheet(
                    p: TextStyle(
                      fontSize: 13.sp,
                      color: Colors.grey.shade700,
                    ),
                    listBullet: TextStyle(
                      fontSize: 13.sp,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Get.back();
              if (_settingsBox == null) await _initBox();
              await _settingsBox?.put('ignored_version', release.version);
              ToastUtils.showInfo('此版本将不再自动提醒');
            },
            child: Text('不再提醒', style: TextStyle(color: Colors.grey.shade600)),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () => Get.back(),
                child: const Text('稍后再说'),
              ),
              SizedBox(width: 8.w),
              ElevatedButton(
                onPressed: () {
                  Get.back();
                  _downloadUpdate(release);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  elevation: 0,
                ),
                child: const Text(
                  '立即更新',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ],
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actionsPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      ),
      barrierDismissible: false,
    );
  }

  /// 下载更新
  Future<void> _downloadUpdate(ReleaseInfo release) async {
    if (release.downloadUrl.isEmpty) {
      ToastUtils.showError('未找到下载链接');
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
                  ToastUtils.showError('无法打开浏览器: $e');
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
                ToastUtils.showSuccess('下载链接已复制到剪贴板');
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
                  SizedBox(height: 8.h),
                  if (status.value.contains('下载'))
                    Text(
                      '请保持应用在前台，否则下载可能中断',
                      style: TextStyle(color: Colors.orange, fontSize: 12.sp),
                    ),
                ],
              )),
          actions: [
            Obx(() => isDownloading.value
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          isDownloading.value = false;
                          Get.back();
                        },
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () {
                          isDownloading.value = false;
                          Get.back();
                          launchUrl(
                              Uri.parse(useMirror
                                  ? 'https://ghproxy.com/${release.downloadUrl}'
                                  : release.downloadUrl),
                              mode: LaunchMode.externalApplication);
                        },
                        child: const Text('浏览器下载'),
                      ),
                    ],
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
        // Android: 优先使用公共下载目录
        try {
          // 尝试使用标准下载目录
          final downloadDir = Directory('/storage/emulated/0/Download');
          if (await downloadDir.exists()) {
            dir = downloadDir;
          } else {
            // 如果不存在,尝试创建
            try {
              dir = await downloadDir.create(recursive: true);
            } catch (e) {
              debugPrint('无法创建Download目录: $e');
              dir = null;
            }
          }
        } catch (e) {
          debugPrint('访问Download目录失败: $e');
          dir = null;
        }

        // 降级方案: 使用getDownloadsDirectory()
        if (dir == null) {
          try {
            dir = await getDownloadsDirectory();
          } catch (e) {
            debugPrint('getDownloadsDirectory失败: $e');
            dir = null;
          }
        }

        // 最后降级: 使用应用专属外部存储
        if (dir == null) {
          dir = await getExternalStorageDirectory();
        }
      } else {
        // iOS/其他平台: 使用getDownloadsDirectory()
        try {
          dir = await getDownloadsDirectory();
        } catch (e) {
          debugPrint('getDownloadsDirectory失败: $e');
          dir = null;
        }
      }

      // 最终降级: 使用临时目录
      if (dir == null) {
        dir = await getTemporaryDirectory();
      }

      debugPrint('下载目录: ${dir.path}');

      final fileName = 'StarBank_${release.version}.apk';
      final filePath = '${dir.path}/$fileName';
      final file = File(filePath);

      // 检查文件是否已存在
      if (await file.exists()) {
        final fileSize = await file.length();
        if (fileSize > 1024 * 1024) {
          // 文件大于1MB,认为是有效的安装包
          status.value = '已找到已下载的安装包';
          progress.value = 1.0;
          isDownloading.value = false;
          downloadedFilePath = filePath;
          debugPrint(
              '使用已存在的安装包: $filePath (${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB)');
          return;
        } else {
          // 文件太小,可能是损坏的,删除后重新下载
          await file.delete();
          debugPrint('删除损坏的安装包: $filePath');
        }
      }

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
        ToastUtils.showError(result.message);
      }
    } catch (e) {
      ToastUtils.showError('无法打开安装程序: $e');
    }
  }
}
