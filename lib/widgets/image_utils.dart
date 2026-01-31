import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:flutter/material.dart';

class ImageUtils {
  static final ImagePicker _picker = ImagePicker();

  /// 选择图片并裁剪,返回Base64编码
  static Future<String?> pickImageAndToBase64({
    bool enableCrop = false,
    CropAspectRatio? aspectRatio,
  }) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: enableCrop ? null : 512,
        maxHeight: enableCrop ? null : 512,
        imageQuality: enableCrop ? 100 : 75,
      );

      if (image == null) return null;

      // 如果启用裁剪
      if (enableCrop) {
        final croppedFile = await ImageCropper().cropImage(
          sourcePath: image.path,
          aspectRatio:
              aspectRatio ?? const CropAspectRatio(ratioX: 1, ratioY: 1),
          compressQuality: 75,
          maxWidth: 512,
          maxHeight: 512,
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: '裁剪头像',
              toolbarColor: const Color(0xFFFF6B9D),
              toolbarWidgetColor: Colors.white,
              initAspectRatio: CropAspectRatioPreset.square,
              lockAspectRatio: true,
              aspectRatioPresets: [
                CropAspectRatioPreset.square,
              ],
            ),
            IOSUiSettings(
              title: '裁剪头像',
              aspectRatioPresets: [
                CropAspectRatioPreset.square,
              ],
            ),
          ],
        );

        if (croppedFile == null) return null;

        final bytes = await croppedFile.readAsBytes();
        return base64Encode(bytes);
      } else {
        // 不裁剪,直接返回
        final bytes = await image.readAsBytes();
        return base64Encode(bytes);
      }
    } catch (e) {
      debugPrint("Error picking/cropping image: $e");
      return null;
    }
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
