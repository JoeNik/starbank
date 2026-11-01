import 'package:flutter/services.dart';

/// 把文件保存到系统公共下载目录 `Download/<subDir>`(如 Download/starBank/music)。
/// API 29+ 走 MediaStore,无需任何权限;更早版本由调用方先申请存储权限。
class PublicStorageService {
  static const MethodChannel _channel =
      MethodChannel('star_bank/public_storage');

  /// 设备 Android API 等级;通道不可用时返回 0(调用方按新版处理,跳过权限申请)
  Future<int> sdkInt() async {
    try {
      final v = await _channel.invokeMethod<int>('sdkInt');
      return v ?? 0;
    } on PlatformException {
      return 0;
    } on MissingPluginException {
      return 0;
    }
  }

  /// 保存字节到 `Download/<subDir>`,返回实际落盘文件名(系统可能自动追加去重后缀)
  Future<String> saveToDownload({
    required Uint8List bytes,
    required String fileName,
    String subDir = 'starBank/music',
    String mimeType = 'audio/mpeg',
  }) async {
    final name = await _channel.invokeMethod<String>('saveToDownload', {
      'bytes': bytes,
      'fileName': fileName,
      'subDir': subDir,
      'mime': mimeType,
    });
    return name ?? fileName;
  }

  /// 按扩展名映射常见音频 MIME 类型
  static String audioMime(String fileName) {
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    switch (ext) {
      case 'flac':
        return 'audio/flac';
      case 'm4a':
        return 'audio/mp4';
      case 'wav':
        return 'audio/x-wav';
      case 'ogg':
        return 'audio/ogg';
      case 'aac':
        return 'audio/aac';
      case 'mp3':
      default:
        return 'audio/mpeg';
    }
  }
}
