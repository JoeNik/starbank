import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:crop_your_image/crop_your_image.dart';

class ImageUtils {
  static final ImagePicker _picker = ImagePicker();

  /// 选择图片并裁剪,返回Base64编码
  static Future<String?> pickImageAndToBase64({
    bool enableCrop = false,
    dynamic aspectRatio,
  }) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80, // 进一步压缩
      );

      if (image == null) return null;

      final bytes = await image.readAsBytes();

      // 如果启用裁剪
      if (enableCrop) {
        final croppedBytes = await _showCropDialog(bytes);
        if (croppedBytes == null) return null;
        return base64Encode(croppedBytes);
      } else {
        // 不裁剪,直接返回
        return base64Encode(bytes);
      }
    } catch (e) {
      debugPrint("Error picking image: $e");
      return null;
    }
  }

  /// 显示裁剪对话框
  static Future<Uint8List?> _showCropDialog(Uint8List imageBytes) async {
    final cropController = CropController();
    final completer = Completer<Uint8List?>();
    var isCropping = false;

    Get.dialog(
      WillPopScope(
        onWillPop: () async {
          if (!completer.isCompleted) {
            completer.complete(null);
          }
          return true;
        },
        child: StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              backgroundColor: Colors.black,
              insetPadding: EdgeInsets.zero,
              child: SafeArea(
                child: Column(
                  children: [
                    // 顶部工具栏
                    Container(
                      color: Colors.black87,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () {
                              if (!completer.isCompleted) {
                                completer.complete(null);
                              }
                              Get.back();
                            },
                          ),
                          const Spacer(),
                          const Text(
                            '裁剪头像',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          if (isCropping)
                            const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          else
                            IconButton(
                              icon:
                                  const Icon(Icons.check, color: Colors.white),
                              onPressed: () {
                                setState(() {
                                  isCropping = true;
                                });

                                // 超时保护 (10秒)
                                Future.delayed(const Duration(seconds: 10), () {
                                  // 简单的超时机制，如果10秒后还在loading状态，强制取消
                                  // 注意: 这里无法准确判断是否已经被关闭，但setState如果是安全的则无妨
                                  // 由于是在StatefulBuilder中，如果Dialog关闭了，setState可能会报错，
                                  // 但在Dialog关闭时通常整个UI树都卸载了。
                                  try {
                                    if (isCropping) {
                                      setState(() {
                                        isCropping = false;
                                      });
                                      debugPrint("Crop operation timed out");
                                    }
                                  } catch (_) {}
                                });

                                try {
                                  debugPrint("Starting crop...");
                                  cropController.crop();
                                } catch (e) {
                                  debugPrint("Crop error: $e");
                                  setState(() {
                                    isCropping = false;
                                  });
                                  Get.snackbar("错误", "裁剪启动失败: $e");
                                }
                              },
                            ),
                        ],
                      ),
                    ),
                    // 裁剪区域
                    Expanded(
                      child: Stack(
                        children: [
                          Crop(
                            image: imageBytes,
                            controller: cropController,
                            onCropped: (result) {
                              debugPrint(
                                  'onCropped called, type: ${result.runtimeType}');
                              if (!completer.isCompleted) {
                                try {
                                  // 尝试作为 Uint8List 处理 (旧版本)
                                  if (result is Uint8List) {
                                    completer.complete(result as Uint8List);
                                  } else {
                                    // 新版本 CropResult
                                    // 使用 dynamic 避免编译时类型检查错误 (如果我们没 import 具体类)
                                    final dynamic r = result;
                                    // 检查是否有关键字
                                    final str = result.toString();
                                    if (str.contains('Failure')) {
                                      Get.snackbar('错误', '裁剪失败');
                                      completer.complete(null);
                                    } else {
                                      // 尝试获取数据
                                      try {
                                        completer.complete(
                                            r.croppedImage as Uint8List?);
                                      } catch (_) {
                                        // 备选字段 data
                                        try {
                                          completer
                                              .complete(r.data as Uint8List?);
                                        } catch (e) {
                                          debugPrint(
                                              "Failed to extract data: $e");
                                          completer.complete(null);
                                        }
                                      }
                                    }
                                  }
                                } catch (e) {
                                  debugPrint("onCropped error: $e");
                                  completer.complete(null);
                                }
                              }
                              Navigator.of(context).pop();
                            },
                            aspectRatio: 1.0,
                            // initialSize: 0.8, // 2.0.0 版本不支持
                            maskColor: Colors.black.withOpacity(0.7),
                            cornerDotBuilder: (size, edgeAlignment) =>
                                const DotControl(color: Colors.white),
                            interactive: true,
                            fixCropRect: false,
                            withCircleUi: false,
                            onStatusChanged: (status) {
                              debugPrint('CropStatus: $status');
                            },
                            // format: ImageFormat.jpeg,
                          ),
                          if (isCropping)
                            Container(
                              color: Colors.black54,
                              child: const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(
                                      color: Colors.white,
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      "处理中...",
                                      style: TextStyle(color: Colors.white),
                                    )
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    // 底部提示
                    Container(
                      color: Colors.black87,
                      padding: const EdgeInsets.all(16),
                      child: const Text(
                        '拖动调整裁剪区域,点击✓完成',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      barrierDismissible: false,
    );

    return completer.future;
  }

  /// 显示图片
  static Widget displayImage(
    String? pathOrBase64, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    Widget? placeholder,
  }) {
    // 空字符串或 null
    if (pathOrBase64 == null || pathOrBase64.isEmpty) {
      return placeholder ??
          const Center(child: Text('👶', style: TextStyle(fontSize: 32)));
    }

    // 如果是 assets 路径
    if (pathOrBase64.startsWith('assets/')) {
      return Image.asset(pathOrBase64, width: width, height: height, fit: fit);
    }

    // 如果是网络 URL
    if (pathOrBase64.startsWith('http')) {
      return Image.network(
        pathOrBase64,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) {
          return placeholder ?? const Icon(Icons.broken_image);
        },
      );
    }

    // 如果长度超过 100,可能是 base64
    if (pathOrBase64.length > 100) {
      try {
        final cleanBase64 = pathOrBase64.replaceAll(RegExp(r'\s+'), '');
        return Image.memory(
          base64Decode(cleanBase64),
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (context, error, stackTrace) {
            debugPrint("Base64 Image Error: $error");
            return placeholder ?? const Icon(Icons.broken_image);
          },
        );
      } catch (e) {
        debugPrint("Image Decode Error: $e");
        return placeholder ?? const Icon(Icons.error);
      }
    }

    // 其他情况(如 emoji 或无效字符串),返回 placeholder
    return placeholder ?? const Icon(Icons.image);
  }

  /// 显示大图预览对话框
  static void showImagePreview(BuildContext context, String? pathOrBase64) {
    if (pathOrBase64 == null || pathOrBase64.isEmpty) {
      return;
    }

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            // 点击背景关闭
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                color: Colors.transparent,
              ),
            ),
            // 图片
            Center(
              child: Hero(
                tag: 'avatar_preview_$pathOrBase64',
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.9,
                    maxHeight: MediaQuery.of(context).size.height * 0.8,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: displayImage(
                      pathOrBase64,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
            // 关闭按钮
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
