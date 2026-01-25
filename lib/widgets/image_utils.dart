import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';

class ImageUtils {
  static final ImagePicker _picker = ImagePicker();

  static Future<String?> pickImageAndToBase64() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 75,
      );

      if (image == null) return null;

      final bytes = await image.readAsBytes();
      return base64Encode(bytes);
    } catch (e) {
      debugPrint("Error picking image: $e");
      return null;
    }
  }

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

    // 如果长度超过 100，可能是 base64
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

    // 其他情况（如 emoji 或无效字符串），返回 placeholder
    // 不要尝试加载它们作为资源
    return placeholder ?? const Icon(Icons.image);
  }
}
