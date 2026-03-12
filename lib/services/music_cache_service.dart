import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import '../models/music/music_track.dart';

/// 缓存元数据模型
class CacheMetadata {
  final String trackId;
  final String title;
  final String artist;
  final String? album;
  final String? coverUrl;
  final String platform;
  final String originalUrl;
  final int fileSize;
  final DateTime cachedAt;
  final String checksum;
  final String? lyricContent;

  CacheMetadata({
    required this.trackId,
    required this.title,
    required this.artist,
    this.album,
    this.coverUrl,
    required this.platform,
    required this.originalUrl,
    required this.fileSize,
    required this.cachedAt,
    required this.checksum,
    this.lyricContent,
  });

  factory CacheMetadata.fromJson(Map<String, dynamic> json) {
    return CacheMetadata(
      trackId: json['trackId'],
      title: json['title'],
      artist: json['artist'],
      album: json['album'],
      coverUrl: json['coverUrl'],
      platform: json['platform'],
      originalUrl: json['originalUrl'],
      fileSize: json['fileSize'],
      cachedAt: DateTime.parse(json['cachedAt']),
      checksum: json['checksum'],
      lyricContent: json['lyricContent'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'trackId': trackId,
      'title': title,
      'artist': artist,
      'album': album,
      'coverUrl': coverUrl,
      'platform': platform,
      'originalUrl': originalUrl,
      'fileSize': fileSize,
      'cachedAt': cachedAt.toIso8601String(),
      'checksum': checksum,
      'lyricContent': lyricContent,
    };
  }
}

/// 缓存统计信息
class CacheStats {
  final int totalFiles;
  final int totalSize;
  final Map<String, int> platformCounts;

  CacheStats({
    required this.totalFiles,
    required this.totalSize,
    required this.platformCounts,
  });

  String get formattedSize {
    if (totalSize < 1024) return '$totalSize B';
    if (totalSize < 1024 * 1024) {
      return '${(totalSize / 1024).toStringAsFixed(2)} KB';
    }
    if (totalSize < 1024 * 1024 * 1024) {
      return '${(totalSize / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(totalSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// 音乐缓存服务
class MusicCacheService extends GetxService {
  // 加密密钥（用于简单的异或加密,防止直接播放缓存文件）
  static const String _encryptionKey = 'StarBankMusicCacheKey2026';

  Directory? _cacheDir;
  final Map<String, CacheMetadata> _cacheIndex = {};
  bool _isInitialized = false;
  final RxBool cacheEnabled = true.obs; // 缓存开关,默认开启以便测试
  String? _customCacheDir; // 自定义缓存目录

  bool get isInitialized => _isInitialized;
  int get cachedCount => _cacheIndex.length;
  String? get customCacheDir => _customCacheDir;
  String? get currentCacheDir => _cacheDir?.path;

  /// 初始化缓存服务
  Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('ℹ️ [MusicCacheService] 缓存服务已初始化,跳过');
      return;
    }

    if (kIsWeb) {
      debugPrint('⚠️ [MusicCacheService] Web 环境不支持文件系统缓存，已自动禁用');
      cacheEnabled.value = false;
      _isInitialized = true;
      return;
    }

    try {
      debugPrint('💾 [MusicCacheService] 开始初始化缓存服务...');

      // 加载缓存设置
      await _loadSettings();

      // 获取缓存目录
      if (_customCacheDir != null && _customCacheDir!.isNotEmpty) {
        // 使用自定义目录
        _cacheDir = Directory(_customCacheDir!);
        debugPrint('📂 [MusicCacheService] 使用自定义目录: $_customCacheDir');
      } else {
        // 使用应用支撑目录，防止某些 Android 上的 documents directory 权限问题
        final appDir = await getApplicationSupportDirectory();
        _cacheDir = Directory('${appDir.path}/music_cache');
        debugPrint('📂 [MusicCacheService] 应用支撑目录: ${appDir.path}');
      }

      debugPrint('📂 [MusicCacheService] 缓存目录路径: ${_cacheDir!.path}');
      debugPrint(
          '🔧 [MusicCacheService] 缓存开关状态: ${cacheEnabled.value ? "已启用" : "已禁用"}');

      // 创建缓存目录
      if (!await _cacheDir!.exists()) {
        debugPrint('📁 [MusicCacheService] 缓存目录不存在,创建中...');
        await _cacheDir!.create(recursive: true);
        debugPrint('✅ [MusicCacheService] 缓存目录已创建: ${_cacheDir!.path}');
      } else {
        debugPrint('✅ [MusicCacheService] 缓存目录已存在: ${_cacheDir!.path}');
      }

      // 验证目录是否可写
      try {
        final testFile = File('${_cacheDir!.path}/.test');
        await testFile.writeAsString('test');
        await testFile.delete();
        debugPrint('✅ [MusicCacheService] 缓存目录可写');
      } catch (e) {
        debugPrint('❌ [MusicCacheService] 缓存目录不可写: $e');
        throw Exception('缓存目录不可写');
      }

      // 加载缓存索引
      await _loadCacheIndex();

      _isInitialized = true;

      debugPrint('✅ [MusicCacheService] 缓存服务初始化完成！');
      debugPrint('📊 [MusicCacheService] 已缓存歌曲数: ${_cacheIndex.length}');
      debugPrint('📁 [MusicCacheService] 缓存位置: ${_cacheDir!.path}');
    } catch (e, stackTrace) {
      debugPrint('❌ [MusicCacheService] 初始化失败: $e');
      debugPrint('❌ [MusicCacheService] 错误堆栈: $stackTrace');
      _isInitialized = false;
    }
  }

  /// 生成缓存键（基于歌曲ID和平台）
  /// 统一转为小写并去除空格，防止因格式差异导致匹配失败
  String _generateCacheKey(String trackId, String platform) {
    final cleanPlatform = platform.trim().toLowerCase();
    final cleanId = trackId.trim();
    return '${cleanPlatform}_$cleanId';
  }

  /// 获取缓存文件路径
  String _getCacheFilePath(String cacheKey) {
    return '${_cacheDir!.path}/$cacheKey.starmusic';
  }

  /// 加密数据（简单的异或加密,防止直接播放）
  Uint8List _encryptData(Uint8List data) {
    final keyBytes = utf8.encode(_encryptionKey);
    final encrypted = Uint8List(data.length);

    for (int i = 0; i < data.length; i++) {
      encrypted[i] = data[i] ^ keyBytes[i % keyBytes.length];
    }

    return encrypted;
  }

  /// 计算文件校验和
  String _calculateChecksum(Uint8List data) {
    return md5.convert(data).toString();
  }

  /// 检查缓存是否存在
  bool isCached(MusicTrack track) {
    if (!_isInitialized || !cacheEnabled.value) return false;

    final cacheKey = _generateCacheKey(track.id, track.platform);
    return _cacheIndex.containsKey(cacheKey);
  }

  /// 获取缓存的元数据
  CacheMetadata? getCachedMetadata(MusicTrack track) {
    if (!_isInitialized || !cacheEnabled.value) return null;

    final cacheKey = _generateCacheKey(track.id, track.platform);
    return _cacheIndex[cacheKey];
  }

  /// 获取缓存文件路径（用于播放）
  /// 采用流式解密 (Streaming) 以降低内存占用，防止后台 OOM
  Future<String?> getCachedFilePath(MusicTrack track) async {
    if (!_isInitialized) {
      debugPrint('⚠️ [MusicCacheService] 缓存服务未初始化');
      return null;
    }

    final cacheKey = _generateCacheKey(track.id, track.platform);

    if (!_cacheIndex.containsKey(cacheKey)) {
      debugPrint('ℹ️ [MusicCacheService] 索引未命中: $cacheKey');
      return null;
    }

    final cacheFilePath = _getCacheFilePath(cacheKey);
    final cacheFile = File(cacheFilePath);

    if (!await cacheFile.exists()) {
      debugPrint('⚠️ [MusicCacheService] 缓存文件不存在: $cacheFilePath');
      _cacheIndex.remove(cacheKey);
      await _saveCacheIndex();
      return null;
    }

    try {
      // 1. 准备解密目标路径
      // 使用 ApplicationSupportDirectory 而不是 TemporaryDirectory，防止后台被系统清理
      final supportDir = await getApplicationSupportDirectory();
      final playbackDir = Directory('${supportDir.path}/playback_cache');
      if (!await playbackDir.exists()) {
        await playbackDir.create(recursive: true);
      }

      // 使用带扩展名的文件名，方便播放器识别
      final tempFilePath = '${playbackDir.path}/$cacheKey.mp3';
      final tempFile = File(tempFilePath);

      // 如果临时文件已存在且大小合理，直接复用（可选优化）
      if (await tempFile.exists()) {
        // 这里可以加一个简单的校验，比如文件修改时间，暂且直接复用
        debugPrint('♻️ [MusicCacheService] 复用已解密文件: $tempFilePath');
        return tempFilePath;
      }

      // 2. 开始流式解密
      // 打开源文件流

      final raf = await cacheFile.open(mode: FileMode.read);

      // 读取元数据长度 (4 bytes)
      final headerBytes = await raf.read(4);
      if (headerBytes.length < 4) {
        await raf.close();
        throw Exception('文件头不完整');
      }

      final metadataLength = (headerBytes[0] << 24) |
          (headerBytes[1] << 16) |
          (headerBytes[2] << 8) |
          headerBytes[3];

      // 计算音频数据开始位置
      final audioStartOffset = 4 + metadataLength;
      final fileSize = await cacheFile.length();

      if (fileSize < audioStartOffset) {
        await raf.close();
        throw Exception('文件被截断');
      }

      // 移动指针到音频数据开始处
      await raf.setPosition(audioStartOffset);

      // 3. 写入目标文件 (Chunked Processing)
      final sink = tempFile.openWrite();
      final keyBytes = utf8.encode(_encryptionKey);
      final bufferSize = 64 * 1024; // 64KB chunk
      int keyIndex = 0;

      // 我们需要自己从 RAF 读取块，然后写入 sink
      // 或者更简单的: 如果数据量不是巨大(几百MB)，分块读取循环是安全的

      // 循环读取直到结束
      int bytesRead = 0;
      while (true) {
        final chunk = await raf.read(bufferSize);
        if (chunk.isEmpty) break;

        // 解密这个块 (XOR)
        for (int i = 0; i < chunk.length; i++) {
          chunk[i] ^= keyBytes[keyIndex % keyBytes.length];
          keyIndex++;
        }

        sink.add(chunk);
        bytesRead += chunk.length;
      }

      await sink.flush();
      await sink.close();
      await raf.close();

      debugPrint(
          '✅ [MusicCacheService] 流式解密完成: $tempFilePath ($bytesRead bytes)');
      return tempFilePath;
    } catch (e) {
      debugPrint('❌ [MusicCacheService] 流式解密失败: $e');
      // 出错时最好清理残缺文件
      // _cacheIndex.remove(cacheKey);
      // await _saveCacheIndex();
      return null;
    }
  }

  /// 缓存歌曲
  Future<bool> cacheSong(MusicTrack track, String audioUrl) async {
    if (!_isInitialized) {
      debugPrint('⚠️ [MusicCacheService] 缓存服务未初始化');
      return false;
    }

    if (!cacheEnabled.value) {
      debugPrint('ℹ️ [MusicCacheService] 缓存功能已禁用,跳过缓存');
      return false;
    }

    try {
      final cacheKey = _generateCacheKey(track.id, track.platform);

      // 检查是否已缓存
      if (_cacheIndex.containsKey(cacheKey)) {
        debugPrint('ℹ️ [MusicCacheService] 歌曲已缓存: ${track.title}');
        return true;
      }

      debugPrint(
          '💾 [MusicCacheService] 开始缓存: ${track.title} (${track.platform})');

      // 下载音频数据
      final response = await http.get(Uri.parse(audioUrl));
      if (response.statusCode != 200) {
        debugPrint('❌ [MusicCacheService] 下载失败: ${response.statusCode}');
        return false;
      }

      final audioData = response.bodyBytes;
      debugPrint('📥 [MusicCacheService] 下载完成: ${audioData.length} bytes');

      // 计算校验和
      final checksum = _calculateChecksum(audioData);

      // 加密音频数据
      final encryptedAudioData = _encryptData(audioData);

      // 创建元数据
      final metadata = CacheMetadata(
        trackId: track.id,
        title: track.title,
        artist: track.artist,
        album: track.album,
        coverUrl: track.coverUrl,
        platform: track.platform,
        originalUrl: audioUrl,
        fileSize: audioData.length,
        cachedAt: DateTime.now(),
        checksum: checksum,
        lyricContent: track.lyricContent,
      );

      // 将元数据转换为字节
      final metadataJson = jsonEncode(metadata.toJson());
      final metadataBytes = utf8.encode(metadataJson);
      final metadataLength = metadataBytes.length;

      // 构建 .starmusic 文件
      // 格式: [4字节元数据长度] [元数据JSON] [加密的音频数据]
      final starmusicFile = BytesBuilder();

      // 写入元数据长度（4字节,大端序）
      starmusicFile.addByte((metadataLength >> 24) & 0xFF);
      starmusicFile.addByte((metadataLength >> 16) & 0xFF);
      starmusicFile.addByte((metadataLength >> 8) & 0xFF);
      starmusicFile.addByte(metadataLength & 0xFF);

      // 写入元数据
      starmusicFile.add(metadataBytes);

      // 写入加密的音频数据
      starmusicFile.add(encryptedAudioData);

      // 保存 .starmusic 文件
      final cacheFilePath = _getCacheFilePath(cacheKey);
      final cacheFile = File(cacheFilePath);
      await cacheFile.writeAsBytes(starmusicFile.toBytes());

      debugPrint('🔒 [MusicCacheService] 保存缓存文件: $cacheFilePath');
      debugPrint(
          '📊 [MusicCacheService] 文件大小: ${starmusicFile.length} bytes (元数据: $metadataLength bytes)');

      // 更新缓存索引
      _cacheIndex[cacheKey] = metadata;
      await _saveCacheIndex();

      debugPrint('✅ [MusicCacheService] 缓存完成: ${track.title}');

      return true;
    } catch (e) {
      debugPrint('❌ [MusicCacheService] 缓存失败: $e');
      return false;
    }
  }

  /// 加载缓存索引
  Future<void> _loadCacheIndex() async {
    try {
      final indexFile = File('${_cacheDir!.path}/cache_index.json');
      if (await indexFile.exists()) {
        final indexJson = await indexFile.readAsString();
        final indexData = jsonDecode(indexJson) as Map<String, dynamic>;

        _cacheIndex.clear();
        indexData.forEach((key, value) {
          _cacheIndex[key] = CacheMetadata.fromJson(value);
        });

        debugPrint('✅ [MusicCacheService] 缓存索引加载完成: ${_cacheIndex.length} 首歌曲');
      } else {
        debugPrint('ℹ️ [MusicCacheService] 缓存索引文件不存在,创建新索引');
      }
    } catch (e) {
      debugPrint('❌ [MusicCacheService] 加载缓存索引失败: $e');
      _cacheIndex.clear();
    }
  }

  /// 保存缓存索引
  Future<void> _saveCacheIndex() async {
    try {
      final indexFile = File('${_cacheDir!.path}/cache_index.json');
      final indexData = <String, dynamic>{};

      _cacheIndex.forEach((key, value) {
        indexData[key] = value.toJson();
      });

      await indexFile.writeAsString(jsonEncode(indexData));
      debugPrint('✅ [MusicCacheService] 缓存索引已保存');
    } catch (e) {
      debugPrint('❌ [MusicCacheService] 保存缓存索引失败: $e');
    }
  }

  /// 加载缓存设置
  Future<void> _loadSettings() async {
    // TODO: 从 StorageService 或 SharedPreferences 加载设置
    // 暂时使用 True 以便调试
    cacheEnabled.value = true;
    _customCacheDir = null;
  }

  /// 保存缓存设置
  Future<void> saveSettings({
    bool? enabled,
    String? customDir,
  }) async {
    if (enabled != null) {
      cacheEnabled.value = enabled;
    }
    if (customDir != null) {
      _customCacheDir = customDir;
    }

    // TODO: 保存到 StorageService 或 SharedPreferences
    debugPrint('✅ [MusicCacheService] 缓存设置已保存');
  }

  /// 获取缓存统计信息
  Future<CacheStats> getCacheStats() async {
    if (!_isInitialized) {
      return CacheStats(
        totalFiles: 0,
        totalSize: 0,
        platformCounts: {},
      );
    }

    int totalSize = 0;
    final platformCounts = <String, int>{};

    for (final metadata in _cacheIndex.values) {
      totalSize += metadata.fileSize;
      platformCounts[metadata.platform] =
          (platformCounts[metadata.platform] ?? 0) + 1;
    }

    return CacheStats(
      totalFiles: _cacheIndex.length,
      totalSize: totalSize,
      platformCounts: platformCounts,
    );
  }

  /// 清除所有缓存
  Future<void> clearAllCache() async {
    if (!_isInitialized) {
      debugPrint('⚠️ [MusicCacheService] 缓存服务未初始化');
      return;
    }

    try {
      debugPrint('🗑️ [MusicCacheService] 开始清除所有缓存...');

      // 删除所有缓存文件
      for (final cacheKey in _cacheIndex.keys.toList()) {
        final cacheFilePath = _getCacheFilePath(cacheKey);
        final cacheFile = File(cacheFilePath);
        if (await cacheFile.exists()) {
          await cacheFile.delete();
        }
      }

      // 清空索引
      _cacheIndex.clear();
      await _saveCacheIndex();

      debugPrint('✅ [MusicCacheService] 所有缓存已清除');
    } catch (e) {
      debugPrint('❌ [MusicCacheService] 清除缓存失败: $e');
    }
  }

  /// 删除单个缓存
  Future<void> deleteCache(MusicTrack track) async {
    if (!_isInitialized) {
      debugPrint('⚠️ [MusicCacheService] 缓存服务未初始化');
      return;
    }

    try {
      final cacheKey = _generateCacheKey(track.id, track.platform);

      if (!_cacheIndex.containsKey(cacheKey)) {
        debugPrint('ℹ️ [MusicCacheService] 缓存不存在: ${track.title}');
        return;
      }

      // 删除缓存文件
      final cacheFilePath = _getCacheFilePath(cacheKey);
      final cacheFile = File(cacheFilePath);
      if (await cacheFile.exists()) {
        await cacheFile.delete();
      }

      // 从索引中移除
      _cacheIndex.remove(cacheKey);
      await _saveCacheIndex();

      debugPrint('✅ [MusicCacheService] 缓存已删除: ${track.title}');
    } catch (e) {
      debugPrint('❌ [MusicCacheService] 删除缓存失败: $e');
    }
  }

  /// 获取所有缓存的歌曲列表
  List<CacheMetadata> getAllCachedTracks() {
    return _cacheIndex.values.toList();
  }
}
