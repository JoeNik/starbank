import 'package:flutter/material.dart';

/// 网易云图片 CDN(p*.music.126.net)按 UA 指纹拦截:请求 UA 以 "Dart/" 开头即 403
/// (curl 实测:任何边缘、明文/加密、全小写头都放行,唯 UA 含 Dart 字样必 403)。
const String kNeteaseBrowserUa =
    'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36';

/// 关键陷阱:dart:io 的 `headers.add('User-Agent', ...)` 是**追加**而非替换,
/// 实际发出 `user-agent: Dart/x (dart:io), Mozilla/5.0 ...`(Dart 在前)→ 照样 403。
/// 因此 Dart 侧(HTTP 层)绝不能在请求头里再带 UA,统一依赖 main.dart 里
/// AppHttpOverrides 设置的客户端默认 UA(替换语义)。
const Map<String, String> kNeteaseImageHeaders = {
  'Referer': 'https://music.163.com/',
};

/// 原生侧(audio_service 通知栏封面走 HttpURLConnection.setRequestHeader,
/// 替换语义)可以安全自带 UA。
const Map<String, String> kNeteaseNativeHeaders = {
  'User-Agent': kNeteaseBrowserUa,
  'Referer': 'https://music.163.com/',
};

/// Dart 侧图片加载头;非网易 CDN 不需要额外头
Map<String, String>? coverHeadersFor(String? url) =>
    (url != null && url.contains('music.126.net'))
        ? kNeteaseImageHeaders
        : null;

/// 原生侧加载头
Map<String, String>? nativeCoverHeadersFor(String? url) =>
    (url != null && url.contains('music.126.net'))
        ? kNeteaseNativeHeaders
        : null;

/// 音乐封面统一组件:自带网易 CDN 兼容头,加载失败时显示音符占位。
class MusicCoverImage extends StatelessWidget {
  const MusicCoverImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.fallbackIcon = Icons.music_note,
    this.fallbackColor = Colors.white24,
    this.fallbackIconSize = 24,
  });

  final String? url;
  final BoxFit fit;
  final IconData fallbackIcon;
  final Color fallbackColor;
  final double fallbackIconSize;

  @override
  Widget build(BuildContext context) {
    final hasCover = url != null && url!.isNotEmpty;
    if (!hasCover) {
      return Icon(fallbackIcon,
          color: fallbackColor, size: fallbackIconSize);
    }
    return Image.network(
      url!,
      fit: fit,
      headers: coverHeadersFor(url),
      errorBuilder: (ctx, err, st) => Icon(fallbackIcon,
          color: fallbackColor, size: fallbackIconSize),
    );
  }
}
