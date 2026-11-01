import 'dart:async' show TimeoutException;
import 'dart:convert';
import 'dart:io'
    show
        ConnectionTask,
        HttpClient,
        InternetAddress,
        SecureSocket,
        Socket,
        SocketException;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' show IOClient;
import '../models/music/music_track.dart';
import '../utils/remote_json.dart';
import 'android_background_network_service.dart';
import 'music_source.dart';
import 'storage_service.dart';

/// ChKSz 音乐 API(https://api.chksz.com)。
/// 提供网易云音乐的搜索 / 播放解析 / 歌词 / 歌单能力,apikey 鉴权。
/// 文档:https://api.chksz.com/#apis
class ChkSzMusicService extends GetxService implements MusicSource {
  final StorageService _storage = Get.find<StorageService>();

  static const String kBaseUrl = 'https://api.chksz.com';
  static const String _defaultApiKey = 'chksz_kiOtNpRd0IcmWX_aHMykHeCiN47jWPYUVTVd-mxP140';
  static const String _apiKeyStorageKey = 'chksz_api_key';
  static const String _qualityStorageKey = 'chksz_quality';

  /// 源站直连 IP:部分网络的路由器 DNS 会把域名解析到 Cloudflare 国际
  /// 边缘节点,该路径在国内网络容易被间歇性 RST(连接重置)。此时改连
  /// 源站 IP,TLS 握手仍以 api.chksz.com 作为 SNI 与证书校验主机。
  static const String _originDirectIp = '198.20.0.210';

  /// 网易公开接口(music.163.com)所需的请求头。
  /// 不带 UA:dart:io 对 UA 头是追加语义,带了会把默认 UA 拼在前面;
  /// 浏览器 UA 由 main.dart 的 AppHttpOverrides 全局提供。
  static const Map<String, String> kNeteaseApiHeaders = {
    'Referer': 'https://music.163.com/',
  };

  http.Client? _directClient;

  /// 网易云音质档位(由低到高),解析失败时向下自动降级重试
  static const List<String> kQualityLevels = [
    'standard',
    'exhigh',
    'lossless',
    'hires',
    'jyeffect',
    'sky',
    'jymaster',
  ];

  static const Map<String, String> kQualityLabels = {
    'standard': '标准',
    'exhigh': '320K',
    'lossless': '无损',
    'hires': 'Hi-Res',
    'jyeffect': '高清环绕',
    'sky': '沉浸环绕',
    'jymaster': '超清母带',
  };

  static String qualityLabel(String? level) {
    if (level == null || level.isEmpty) return '';
    return kQualityLabels[level] ?? level;
  }

  final RxString apiKey = ''.obs;
  final RxString quality = 'exhigh'.obs;

  String _lastDebugInfo = '';

  @override
  String get id => 'chksz';

  @override
  String get displayName => 'ChKSz·网易';

  @override
  bool get isConfigured => apiKey.value.isNotEmpty;

  @override
  String get lastDebugInfo => _lastDebugInfo;

  @override
  void onInit() {
    super.onInit();
    reloadFromStorage();
  }

  void reloadFromStorage() {
    apiKey.value = _storage.getValue(_apiKeyStorageKey) ?? _defaultApiKey;
    final savedQuality = _storage.getValue(_qualityStorageKey);
    if (savedQuality != null && kQualityLevels.contains(savedQuality)) {
      quality.value = savedQuality;
    }
  }

  void updateConfig(String key, String newQuality) {
    apiKey.value = key.trim();
    if (kQualityLevels.contains(newQuality)) quality.value = newQuality;
    _storage.saveValue(_apiKeyStorageKey, apiKey.value);
    _storage.saveValue(_qualityStorageKey, quality.value);
  }

  String get _effectiveApiKey {
    final key = apiKey.value.trim();
    return key.isNotEmpty ? key : _defaultApiKey;
  }

  /// 源站直连客户端:自定义 connectionFactory 绕过系统 DNS,
  /// 直接 TCP 连源站 IP,再对裸 socket 做以域名为 SNI 的 TLS 握手
  http.Client get _directHttpClient {
    return _directClient ??= IOClient(
      HttpClient()
        ..connectionTimeout = const Duration(seconds: 4)
        ..connectionFactory = (uri, proxyHost, proxyPort) async {
          final task =
              await Socket.startConnect(InternetAddress(_originDirectIp), uri.port);
          final socket = task.socket.then((raw) async {
            try {
              return await SecureSocket.secure(raw, host: uri.host);
            } catch (_) {
              raw.destroy();
              rethrow;
            }
          });
          return ConnectionTask.fromSocket(socket, task.cancel);
        },
    );
  }

  bool _isTransportReset(Object e) {
    if (e is SocketException) return true;
    if (e is TimeoutException) return true;
    if (e is http.ClientException) {
      final msg = e.message;
      return msg.contains('Connection reset') ||
          msg.contains('Connection closed') ||
          msg.contains('Software caused connection abort') ||
          msg.contains('timed out');
    }
    return false;
  }

  @override
  void onClose() {
    _directClient?.close();
    _directClient = null;
    super.onClose();
  }

  Future<String> _safeGetBody(http.Response res) async {
    try {
      return utf8.decode(res.bodyBytes);
    } catch (_) {
      return res.body;
    }
  }

  /// 传输层熔断:ChKSz 整体不可达(如被网络环境屏蔽)时,
  /// 音质降级链每档都会烧满超时;记录最近一次传输失败,
  /// 60 秒内直接放弃 ChKSz 请求,让上层尽快走 TuneHub 兜底。
  static const Duration _circuitOpenDuration = Duration(seconds: 60);
  DateTime? _lastTransportFailureAt;

  bool get _circuitOpen {
    final t = _lastTransportFailureAt;
    return t != null && DateTime.now().difference(t) < _circuitOpenDuration;
  }

  void _markTransportFailure() {
    _lastTransportFailureAt = DateTime.now();
  }

  /// 源站直连重试:同一 URL 走直连客户端再请求一次
  Future<http.Response> _directRetry(
    Uri uri,
    String operationId,
    String loadingText,
  ) {
    return AndroidBackgroundNetworkService.protect(
      '$operationId-direct',
      () => _directHttpClient.get(uri).timeout(const Duration(seconds: 20)),
      title: 'StarBank 音乐',
      text: loadingText,
    );
  }

  Future<dynamic> _getJson(
    String path,
    Map<String, String> query, {
    required String operationId,
    required String loadingText,
  }) async {
    final uri = Uri.https('api.chksz.com', path, query);
    debugPrint('🌐 [ChKSz] GET $uri');

    // 三段式传输层策略:
    // 1) 普通请求重试 2 次(被间歇性 RST 的网络波动窗口内常能通过);
    // 2) 源站 IP 直连(应对 DNS 指向被干扰节点、且源站可达的网络);
    // 3) 都失败才抛出,由上层回退 TuneHub。
    http.Response? response;
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        response = await AndroidBackgroundNetworkService.protect(
          operationId,
          () => http.get(uri).timeout(const Duration(seconds: 20)),
          title: 'StarBank 音乐',
          text: loadingText,
        );
        break;
      } catch (e) {
        if (!_isTransportReset(e)) rethrow;
        lastError = e;
        if (attempt < 3) {
          await Future.delayed(const Duration(milliseconds: 400));
        } else {
          debugPrint('⚠️ [ChKSz] 普通连接 ${lastError}');
        }
      }
    }
    if (response == null) {
      // 普通路径全部失败,试源站直连;直连也失败则标记熔断
      try {
        response = await _directRetry(uri, operationId, loadingText);
      } catch (e) {
        if (_isTransportReset(e)) _markTransportFailure();
        rethrow;
      }
    }

    if (response.statusCode != 200) {
      _lastDebugInfo = 'HTTP ${response.statusCode}';
      throw Exception('ChKSz 接口 HTTP ${response.statusCode}');
    }
    final body = await _safeGetBody(response);
    final json = tryDecodeJsonObject(body);
    if (json == null) {
      _lastDebugInfo = '响应不是合法 JSON';
      throw Exception('ChKSz 接口返回异常数据');
    }
    if (json['code'] != 200) {
      _lastDebugInfo = 'code=${json['code']}, msg=${json['msg']}';
      throw Exception('ChKSz 接口错误: ${json['msg'] ?? json['code']}');
    }
    return json['data'];
  }

  /// 封面 URL 统一升级为 HTTPS(部分接口返回 http,Android 9+ 明文被禁)
  static String? normalizeCover(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http://')) return url.replaceFirst('http://', 'https://');
    return url;
  }

  @override
  Future<List<MusicTrack>> searchMusic(
    String keyword, {
    String platform = 'netease',
    int page = 1,
  }) async {
    const limit = 30;
    try {
      final data = await _getJson(
        '/api/163_search',
        {
          'keyword': keyword,
          'limit': '$limit',
          'offset': '${(page - 1) * limit}',
          'apikey': _effectiveApiKey,
        },
        operationId: 'chksz_search_${page}_$keyword',
        loadingText: '正在搜索歌曲',
      );

      // 兼容两种返回形状:data 为 {songs:[...]} 或直接为数组
      dynamic list;
      if (data is Map) {
        list = data['songs'];
      } else if (data is List) {
        list = data;
      }
      if (list is! List) {
        _lastDebugInfo = '搜索响应中未找到歌曲列表';
        return [];
      }

      final tracks = <MusicTrack>[];
      for (final item in list) {
        final map = asJsonMap(item);
        if (map == null) continue;
        final id = asNonEmptyString(map['id']);
        if (id == null || id.isEmpty) continue;
        tracks.add(MusicTrack(
          id: id,
          title: asNonEmptyString(map['name']) ?? '未知歌曲',
          artist: asNonEmptyString(map['artists']) ?? '未知歌手',
          album: asNonEmptyString(map['album']),
          coverUrl: normalizeCover(asNonEmptyString(map['picUrl'])),
          durationMs: (map['duration'] is num) ? (map['duration'] as num).toInt() : null,
          platform: 'netease',
        ));
      }
      debugPrint('✅ [ChKSz] 搜索 "${keyword}" 第${page}页,共 ${tracks.length} 首');
      return tracks;
    } catch (e) {
      debugPrint('❌ [ChKSz] 搜索失败: $e');
      if (_lastDebugInfo.isEmpty) _lastDebugInfo = '$e';
      return [];
    }
  }

  @override
  Future<Map<String, dynamic>> parseTrack(
    String platform,
    String id, {
    String? level,
  }) async {
    // 音质自动降级:目标档位无资源时逐级向下重试
    final requested = (level != null && kQualityLevels.contains(level))
        ? level
        : quality.value;
    final requestedIndex = kQualityLevels.indexOf(requested);
    final chain = <String>[];
    for (var i = requestedIndex; i >= 0; i--) {
      chain.add(kQualityLevels[i]);
    }

    // 熔断中:ChKSz 整体连不上,别再逐档烧超时
    if (_circuitOpen && platform == 'netease') {
      debugPrint('⚡ [ChKSz] 60 秒内传输持续失败,本次解析直接跳过(熔断中)');
      throw Exception('ChKSz 熔断中,跳过本次请求');
    }

    for (final tryLevel in chain) {
      try {
        final data = await _getJson(
          '/api/163_music',
          {
            'id': id,
            'level': tryLevel,
            'type': 'json',
            'apikey': _effectiveApiKey,
          },
          operationId: 'chksz_parse_${id}_$tryLevel',
          loadingText: '正在解析播放链接',
        );
        final map = asJsonMap(data);
        final url = map == null ? null : asNonEmptyString(map['url']);
        if (map == null || url == null || url.isEmpty) {
          debugPrint('⚠️ [ChKSz] 音质 $tryLevel 无可用资源,降级重试');
          continue;
        }
        debugPrint('✅ [ChKSz] 解析成功: ${map['level']} ${map['br']}bps');
        return {
          'url': url,
          'cover': normalizeCover(asNonEmptyString(map['picUrl'])),
          'lyrics': null,
          'level': asNonEmptyString(map['level']) ?? tryLevel,
          'br': map['br'],
          'size': map['size'],
        };
      } catch (e) {
        // 传输层失败(重置/超时)说明服务不可达:标记熔断并放弃剩余档位;
        // 业务失败(HTTP 4xx/无资源)则照常降级重试
        if (_isTransportReset(e)) {
          _markTransportFailure();
          debugPrint('❌ [ChKSz] 音质 $tryLevel 传输失败($e),熔断并结束降级链');
          rethrow;
        }
        debugPrint('⚠️ [ChKSz] 音质 $tryLevel 解析异常: $e');
      }
    }
    return {};
  }

  /// 获取歌词,返回 {lrc, tlyric, romalrc}(可能为空字符串)
  Future<Map<String, String>> fetchLyric(String id) async {
    try {
      final data = await _getJson(
        '/api/163_lyric',
        {'id': id, 'apikey': _effectiveApiKey},
        operationId: 'chksz_lyric_$id',
        loadingText: '正在获取歌词',
      );
      final map = asJsonMap(data);
      if (map == null) return {};
      String pick(dynamic v) => (v is String) ? v : '';
      return {
        'lrc': pick(map['lrc']),
        'tlyric': pick(map['tlyric']),
        'romalrc': pick(map['romalrc']),
      };
    } catch (e) {
      debugPrint('⚠️ [ChKSz] 获取歌词失败: $e');
      return {};
    }
  }

  /// 导入网易云歌单(支持粘贴完整链接或纯 ID),返回 {name, cover, tracks}。
  /// 三级策略:ChKSz 接口 → 网易公开 API 兜底(ChKSz 被网络屏蔽时仍可用)
  /// → Hive 持久缓存(彻底断网时保底)。
  Future<Map<String, dynamic>> fetchPlaylist(String idOrUrl) async {
    // 5 位起步:网易歌单 ID 最短 7 位(热歌榜 3778678),但 URL 里的域名 163 只有 3 位需要滤掉
    final match = RegExp(r'\d{5,}').firstMatch(idOrUrl.trim());
    final id = match?.group(0);
    if (id == null) {
      _lastDebugInfo = '无法从输入中提取歌单 ID';
      return {};
    }

    Map<String, dynamic>? result;
    // 熔断中(ChKSz 60 秒内传输持续失败)直接跳过,别烧超时
    if (!_circuitOpen) {
      try {
        final data = await _getJson(
          '/api/163_playlist',
          {'id': id, 'apikey': _effectiveApiKey},
          operationId: 'chksz_playlist_$id',
          loadingText: '正在导入歌单',
        );
        final map = asJsonMap(data);
        if (map != null) {
          result = _parseChkszPlaylist(map);
        } else {
          _lastDebugInfo = '歌单响应为空';
        }
      } catch (e) {
        debugPrint('❌ [ChKSz] 导入歌单失败: $e');
        if (_lastDebugInfo.isEmpty) _lastDebugInfo = '$e';
      }
    }

    result ??= await _fetchNeteasePlaylistDirect(id);
    result ??= _readPersistedPlaylist(id);
    return result ?? {};
  }

  Map<String, dynamic> _parseChkszPlaylist(Map<String, dynamic> map) {
    final rawTracks = map['tracks'];
    final tracks = <MusicTrack>[];
    if (rawTracks is List) {
      for (final item in rawTracks) {
        final t = asJsonMap(item);
        if (t == null) continue;
        final trackId = asNonEmptyString(t['id']);
        if (trackId == null || trackId.isEmpty) continue;
        // 歌手:ar 数组 [{name}] → "A/B"
        String artist = '未知歌手';
        if (t['ar'] is List) {
          final names = (t['ar'] as List)
              .map((e) => asJsonMap(e)?['name'])
              .whereType<String>()
              .where((s) => s.isNotEmpty)
              .toList();
          if (names.isNotEmpty) artist = names.join('/');
        }
        // 专辑:al 对象 {name, picUrl}
        String? album;
        String? cover;
        if (t['al'] is Map) {
          final al = asJsonMap(t['al'])!;
          album = asNonEmptyString(al['name']);
          cover = normalizeCover(asNonEmptyString(al['picUrl']));
        }
        tracks.add(MusicTrack(
          id: trackId,
          title: asNonEmptyString(t['name']) ?? '未知歌曲',
          artist: artist,
          album: album,
          coverUrl: cover,
          platform: 'netease',
        ));
      }
    }
    return {
      'name': asNonEmptyString(map['name']) ?? '网易云歌单',
      'cover': normalizeCover(asNonEmptyString(map['coverImgUrl'])),
      'tracks': tracks,
    };
  }

  /// 网易公开歌单接口直连兜底(music.163.com,与 TuneHub 搜索同源,
  /// 国内网络可达性远好于 ChKSz 的 Cloudflare 边缘)。
  Future<Map<String, dynamic>?> _fetchNeteasePlaylistDirect(String id) async {
    try {
      final uri = Uri.https('music.163.com', '/api/playlist/detail', {'id': id});
      debugPrint('🌐 [ChKSz] 歌单兜底走网易公开 API: $uri');
      final response = await AndroidBackgroundNetworkService.protect(
        'netease_playlist_$id',
        () => http
            .get(uri, headers: kNeteaseApiHeaders)
            .timeout(const Duration(seconds: 15)),
        title: 'StarBank 音乐',
        text: '正在导入歌单',
      );
      if (response.statusCode != 200) {
        debugPrint('❌ [ChKSz] 网易公开歌单 HTTP ${response.statusCode}');
        return null;
      }
      final body = await _safeGetBody(response);
      final json = tryDecodeJsonObject(body);
      final result = asJsonMap(json?['result']);
      if (json == null || result == null) {
        debugPrint('❌ [ChKSz] 网易公开歌单响应异常');
        return null;
      }
      final tracks = <MusicTrack>[];
      final rawTracks = result['tracks'];
      if (rawTracks is List) {
        for (final item in rawTracks) {
          final t = asJsonMap(item);
          if (t == null) continue;
          final trackId = asNonEmptyString(t['id']);
          if (trackId == null || trackId.isEmpty) continue;
          String artist = '未知歌手';
          if (t['artists'] is List) {
            final names = (t['artists'] as List)
                .map((e) => asJsonMap(e)?['name'])
                .whereType<String>()
                .where((s) => s.isNotEmpty)
                .toList();
            if (names.isNotEmpty) artist = names.join('/');
          }
          String? album;
          String? cover;
          if (t['album'] is Map) {
            final al = asJsonMap(t['album'])!;
            album = asNonEmptyString(al['name']);
            cover = normalizeCover(asNonEmptyString(al['picUrl']));
          }
          final durationMs = (t['duration'] is num)
              ? (t['duration'] as num).toInt()
              : null;
          tracks.add(MusicTrack(
            id: trackId,
            title: asNonEmptyString(t['name']) ?? '未知歌曲',
            artist: artist,
            album: album,
            coverUrl: cover,
            durationMs: durationMs,
            platform: 'netease',
          ));
        }
      }
      if (tracks.isEmpty) {
        debugPrint('❌ [ChKSz] 网易公开歌单无曲目');
        return null;
      }
      final playlist = {
        'name': asNonEmptyString(result['name']) ?? '网易云歌单',
        'cover': normalizeCover(asNonEmptyString(result['coverImgUrl'])),
        'trackCount':
            (result['trackCount'] is num) ? result['trackCount'] as num : null,
        'tracks': tracks,
      };
      _persistPlaylist(id, playlist);
      debugPrint('✅ [ChKSz] 网易公开歌单兜底成功: ${playlist['name']} '
          '(${tracks.length} 首)');
      return playlist;
    } catch (e) {
      debugPrint('❌ [ChKSz] 网易公开歌单兜底失败: $e');
      return null;
    }
  }

  static String _playlistCacheKey(String id) => 'netease_playlist_$id';

  /// 歌单结果持久化:一次拉取成功后,断网/音源故障时仍能打开
  void _persistPlaylist(String id, Map<String, dynamic> playlist) {
    try {
      _storage.saveValue(
        _playlistCacheKey(id),
        jsonEncode({
          'ts': DateTime.now().millisecondsSinceEpoch,
          'data': {
            'name': playlist['name'],
            'cover': playlist['cover'],
            'trackCount': playlist['trackCount'],
            'tracks':
                (playlist['tracks'] as List<MusicTrack>).map((t) => t.toJson()).toList(),
          },
        }),
      );
    } catch (e) {
      debugPrint('⚠️ [ChKSz] 歌单缓存写入失败: $e');
    }
  }

  Map<String, dynamic>? _readPersistedPlaylist(String id) {
    try {
      final raw = _storage.getValue(_playlistCacheKey(id));
      if (raw is! String || raw.isEmpty) return null;
      final wrapper = asJsonMap(tryDecodeJsonObject(raw));
      final data = wrapper == null ? null : asJsonMap(wrapper['data']);
      if (data == null) return null;
      final rawTracks = data['tracks'];
      final tracks = <MusicTrack>[];
      if (rawTracks is List) {
        for (final item in rawTracks) {
          final t = asJsonMap(item);
          if (t == null) continue;
          tracks.add(MusicTrack.fromJson(t));
        }
      }
      if (tracks.isEmpty) return null;
      debugPrint('✅ [ChKSz] 使用本地缓存的歌单: ${data['name']}');
      return {
        'name': asNonEmptyString(data['name']) ?? '网易云歌单',
        'cover': normalizeCover(asNonEmptyString(data['cover'])),
        'trackCount': data['trackCount'],
        'tracks': tracks,
      };
    } catch (e) {
      debugPrint('⚠️ [ChKSz] 歌单缓存读取失败: $e');
      return null;
    }
  }
}
