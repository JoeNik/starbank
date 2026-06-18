import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import '../models/music/music_track.dart';
import '../models/music/tunehub_method.dart';
import 'android_background_network_service.dart';
import 'storage_service.dart';

class TuneHubService extends GetxService {
  final StorageService _storage = Get.find<StorageService>();

  final RxString baseUrl = ''.obs;
  final RxString apiKey = ''.obs;

  // 用于存储最后一次搜索的调试信息
  String _lastSearchDebugInfo = '';
  String get lastSearchDebugInfo => _lastSearchDebugInfo;

  @override
  void onInit() {
    super.onInit();
    baseUrl.value = _storage.getValue('tunehub_base_url') ??
        'https://tunehub.sayqz.com/api';
    apiKey.value = _storage.getValue('tunehub_api_key') ?? '';
  }

  void updateConfig(String url, String key) {
    baseUrl.value = url;
    apiKey.value = key;
    _storage.saveValue('tunehub_base_url', url);
    _storage.saveValue('tunehub_api_key', key);
  }

  String get _randomApiKey {
    if (apiKey.value.isEmpty) return '';
    final keys =
        apiKey.value.split(';').where((k) => k.trim().isNotEmpty).toList();
    if (keys.isEmpty) return '';
    keys.shuffle();
    return keys.first.trim();
  }

  String _safeGetBody(http.Response res) {
    try {
      return utf8.decode(res.bodyBytes);
    } catch (e) {
      return res.body;
    }
  }

  Future<TuneHubMethod> _getMethod(String platform, String function) async {
    if (baseUrl.value.isEmpty) throw Exception('请先配置 TuneHub 服务器地址');
    final uri = Uri.parse('${baseUrl.value}/v1/methods/$platform/$function');
    final response = await AndroidBackgroundNetworkService.protect(
      'tunehub_method_${platform}_$function',
      () => http.get(uri, headers: {'X-API-Key': _randomApiKey}),
      title: 'StarBank 音乐',
      text: '正在获取音乐解析配置',
    );
    if (response.statusCode == 200) {
      final json = jsonDecode(_safeGetBody(response));
      if (json['code'] == 0 && json['data'] != null) {
        return TuneHubMethod.fromJson(json['data']);
      }
      throw Exception(json['msg'] ?? '获取配置失败');
    }
    throw Exception('网络错误: ${response.statusCode}');
  }

  String _replaceString(String source, Map<String, String> vars) {
    if (!source.contains('{{')) return source;
    if (source.contains('page') && source.contains('*')) {
      try {
        final page = int.parse(vars['page'] ?? '1');
        final limit = int.parse(vars['limit'] ?? '20');
        final val = ((page - 1) * limit).toString();
        return source.replaceAll(RegExp(r'\{\{.*?\}\}'), val);
      } catch (_) {}
    }
    if (source.contains('page') && source.contains('-')) {
      try {
        final page = int.parse(vars['page'] ?? '1');
        final val = (page - 1).toString();
        return source.replaceAll(RegExp(r'\{\{.*?\}\}'), val);
      } catch (_) {}
    }
    var result = source;
    final regExp = RegExp(r'\{\{(.*?)\}\}');
    result = result.replaceAllMapped(regExp, (match) {
      String content = match.group(1)!.trim();
      if (content.contains('||')) {
        final parts = content.split('||');
        final key = parts[0].trim();
        if (vars.containsKey(key)) return vars[key]!;
        final def = parts[1].trim().replaceAll('"', '').replaceAll("'", "");
        return def;
      }
      return vars[content] ?? '';
    });
    return result;
  }

  dynamic _deepReplace(dynamic source, Map<String, String> vars) {
    if (source is String) {
      final res = _replaceString(source, vars);
      if (source.contains('{{')) {
        final asNum = int.tryParse(res);
        if (asNum != null && !res.startsWith('0')) return asNum;
      }
      return res;
    } else if (source is Map) {
      return source
          .map((key, value) => MapEntry(key, _deepReplace(value, vars)));
    } else if (source is List) {
      return source.map((item) => _deepReplace(item, vars)).toList();
    }
    return source;
  }

  Future<dynamic> _executeMethod(
      TuneHubMethod config, Map<String, String> vars) async {
    final Map<String, String> context = Map.from(vars);
    final limit = vars['limit'] ?? vars['pageSize'] ?? '20';
    context['limit'] = limit;
    context['pageSize'] = limit;
    context['pagesize'] = limit;
    context['rn'] = limit;
    context['num'] = limit;

    try {
      final processedParams = config.params
          .map((k, v) => MapEntry(k, _deepReplace(v, context).toString()));
      var finalUrl = _deepReplace(config.url, context).toString();

      // Fix: 对 URL 进行编码，防止中文路径导致 Uri.parse 失败
      finalUrl = Uri.encodeFull(finalUrl);

      final baseUri = Uri.parse(finalUrl);

      // Fix: 合并参数！而不是直接覆盖。
      // Uri.replace(queryParameters: ...) 会丢弃原有的 query parameters。
      // 我们需要把 config.url 里自带的参数保留下来。
      final Map<String, dynamic> mergedParams =
          Map.from(baseUri.queryParameters);
      mergedParams.addAll(processedParams);

      final uri = baseUri.replace(queryParameters: mergedParams);

      final Map<String, String> headers = {};
      if (config.headers != null) {
        config.headers!.forEach((k, v) {
          var val = _deepReplace(v, context).toString().trim();
          if (val.endsWith(';')) val = val.substring(0, val.length - 1).trim();
          headers[k] = val;
        });
      }

      // 如果这个请求是指向 TuneHub 自身的，务必注入 Key
      if (uri.toString().startsWith(baseUrl.value)) {
        headers['X-API-Key'] = _randomApiKey;
      }

      dynamic finalBody;
      if (config.body != null) {
        finalBody = _deepReplace(config.body, context);
        final ct = (headers['Content-Type'] ?? headers['content-type'] ?? '')
            .toLowerCase();
        if (ct.contains('application/json')) {
          finalBody = jsonEncode(finalBody);
        }
      }

      // 详细日志
      debugPrint('TH Method: ${config.method}');
      debugPrint('TH Request: $uri');

      http.Response response;
      if (config.method == 'POST') {
        debugPrint('TH Body: $finalBody');
        response = await AndroidBackgroundNetworkService.protect(
          'tunehub_exec_${DateTime.now().microsecondsSinceEpoch}',
          () => http.post(uri, headers: headers, body: finalBody),
          title: 'StarBank 音乐',
          text: '正在请求音乐服务',
        );
      } else {
        response = await AndroidBackgroundNetworkService.protect(
          'tunehub_exec_${DateTime.now().microsecondsSinceEpoch}',
          () => http.get(uri, headers: headers),
          title: 'StarBank 音乐',
          text: '正在请求音乐服务',
        );
      }

      final bodyStr = _safeGetBody(response);

      // 调试日志
      if (uri.path.contains('/parse')) {
        debugPrint('TH Parse Resp Code: ${response.statusCode}');
        debugPrint('TH Parse Resp Body: $bodyStr');
      }

      if (response.statusCode == 200) {
        return jsonDecode(bodyStr);
      }
      return null;
    } catch (e) {
      debugPrint('TH Error: $e');
      return null;
    }
  }

  // --- High Level APIs ---

  Future<List<MusicTrack>> searchMusic(String keyword,
      {String platform = 'kuwo', int page = 1}) async {
    final vars = {
      'keyword': keyword,
      'query': keyword,
      's': keyword,
      'searchKey': keyword,
      'page': page.toString(),
      'curpage': page.toString(),
    };

    try {
      final method = await _getMethod(platform, 'search');
      debugPrint('🔍 [TuneHub] 获取到 $platform 的 search method');
      debugPrint('   URL: ${method.url}');
      debugPrint('   Params: ${method.params}');

      final raw = await _executeMethod(method, vars);
      if (raw == null) {
        debugPrint('❌ [TuneHub] $platform search 返回 null');
        return [];
      }

      debugPrint('✅ [TuneHub] $platform search 返回数据类型: ${raw.runtimeType}');
      if (raw is Map) {
        debugPrint('   返回的 Map keys: ${raw.keys.toList()}');
        // 将关键信息保存到全局变量，供 UI 显示
        _lastSearchDebugInfo =
            '平台: $platform\n返回类型: Map\nKeys: ${raw.keys.toList()}';
      } else {
        _lastSearchDebugInfo = '平台: $platform\n返回类型: ${raw.runtimeType}';
      }

      List<MusicTrack> tracks = [];
      dynamic list;

      if (raw is Map) {
        if (raw['abslist'] != null)
          list = raw['abslist'];
        else if (raw['result'] is Map && raw['result']['songs'] != null)
          list = raw['result']['songs'];
        // QQ 音乐特殊处理
        if (platform == 'qq') {
          // QQ 音乐可能的数据结构:
          // { data: { song: { list: [...] } } }
          // { req_1: { data: { song: { list: [...] } } } }
          if (raw['data'] is Map) {
            final data = raw['data'] as Map;
            if (data['song'] is Map && data['song']['list'] is List) {
              list = data['song']['list'];
              debugPrint('🎵 [QQ音乐] 从 data.song.list 找到歌曲列表');
            } else if (data['list'] is List) {
              list = data['list'];
              debugPrint('🎵 [QQ音乐] 从 data.list 找到歌曲列表');
            }
          }
          // 检查 req_1 格式
          if (list == null && raw['req_1'] is Map) {
            final req1 = raw['req_1'] as Map;
            if (req1['data'] is Map) {
              final data = req1['data'] as Map;
              if (data['song'] is Map && data['song']['list'] is List) {
                list = data['song']['list'];
                debugPrint('🎵 [QQ音乐] 从 req_1.data.song.list 找到歌曲列表');
              }
            }
          }
          // 检查其他可能的 QQ 音乐格式
          if (list == null) {
            // 尝试 data.list 直接格式
            if (raw['data'] is Map && raw['data']['list'] is List) {
              list = raw['data']['list'];
              debugPrint('🎵 [QQ音乐] 从 data.list 直接找到歌曲列表');
            }
            // 尝试顶层 list
            else if (raw['list'] is List) {
              list = raw['list'];
              debugPrint('🎵 [QQ音乐] 从顶层 list 找到歌曲列表');
            }
          }
        }

        // 如果还没找到，执行通用扫描
        if (list == null) {
          void scan(dynamic obj) {
            if (list != null) return;
            if (obj is Map) {
              if (obj.containsKey('list') &&
                  obj['list'] is List &&
                  (obj['list'] as List).isNotEmpty) {
                list = obj['list'];
                return;
              }
              if (obj.containsKey('songs') && obj['songs'] is List) {
                list = obj['songs'];
                return;
              }
              obj.values.forEach(scan);
            }
          }

          scan(raw);
        }
      }

      if (list == null) {
        debugPrint('❌ [TuneHub] $platform 未能从响应中提取歌曲列表');
        final jsonStr = jsonEncode(raw);
        final preview =
            jsonStr.length > 500 ? jsonStr.substring(0, 500) + '...' : jsonStr;
        debugPrint('   响应预览: $preview');

        // 保存详细错误信息
        _lastSearchDebugInfo = '平台: $platform\n错误: 未找到歌曲列表\n响应预览: $preview';
        return [];
      }

      if (list is List) {
        debugPrint('✅ [TuneHub] $platform 找到 ${list.length} 首歌曲');

        for (var item in list) {
          // QQ 音乐的 ID 字段可能是 songmid 或 mid
          final id = (item['songmid'] ??
                  item['mid'] ??
                  item['id'] ??
                  item['rid'] ??
                  item['mid'] ??
                  item['songId'] ??
                  item['DC_TARGETID'] ??
                  item['MUSICRID'] ??
                  '')
              .toString();
          if (id.isEmpty) continue;

          // QQ 音乐封面图片处理
          String? cover;
          if (platform == 'qq') {
            // QQ 音乐封面可能在 albummid 中，需要拼接 URL
            final albummid = item['albummid'] ?? item['album_mid'];
            if (albummid != null && albummid.toString().isNotEmpty) {
              cover =
                  'https://y.gtimg.cn/music/photo_new/T002R300x300M000$albummid.jpg';
            }
          }

          // 通用封面处理
          cover ??= item['hts_MVPIC'] ??
              item['pic'] ??
              item['img'] ??
              item['picUrl'] ??
              item['albumPic'] ??
              item['web_albumpic_short'] ??
              (item['album'] is Map ? item['album']['picUrl'] : null);
          if (cover != null && cover.startsWith('//')) cover = 'https:$cover';

          // 歌名处理
          final title = (item['songname'] ??
                  item['name'] ??
                  item['title'] ??
                  item['SONGNAME'] ??
                  '未知歌曲')
              .toString();

          // 专辑处理
          String? album;
          if (platform == 'qq') {
            album = item['albumname'] ?? item['albumName'];
          }
          album ??= (item['album'] is Map
              ? item['album']['name']
              : (item['album'] ?? item['ALBUM'] ?? ''));

          tracks.add(MusicTrack(
            id: id,
            title: title,
            artist: _parseArtist(item),
            coverUrl: cover,
            album: album,
            platform: platform,
          ));
        }
      }
      return tracks;
    } catch (e) {
      debugPrint('TuneHub Search Error: $e');
      if (e.toString().contains('ClientException') ||
          e.toString().contains('XMLHttpRequest')) {
        debugPrint(
            '⚠️ [TuneHub] 检测到 Web 端跨域错误 (CORS)。直接访问第三方 HTTP 接口 (如 kuwo) 在浏览器中通常被禁止。请使用 Android/iOS 模拟器或真机调试，或配置 TuneHub 代理。');
      }
      return [];
    }
  }

  String _parseArtist(dynamic item) {
    // QQ 音乐的歌手信息可能在 singer 数组中
    var singer = item['singer'] ??
        item['artist'] ??
        item['ARTIST'] ??
        item['SINGER'] ??
        item['ar'] ??
        item['artists'];

    if (singer is List && singer.isNotEmpty) {
      return singer
          .map((e) => e is Map ? (e['name'] ?? e['title'] ?? '') : e.toString())
          .where((s) => s.isNotEmpty)
          .join('/');
    }
    if (singer is Map) return (singer['name'] ?? '').toString();
    return (singer ?? '未知歌手').toString();
  }

  Future<Map<String, dynamic>> parseTrack(String platform, String id) async {
    // 强制使用 TuneHub 自身的 Parse 接口，绕过不稳定的 Method 配置代理
    // 这样能确保所有的请求都走统一的 Key 轮询，且 Params 格式绝对正确
    if (baseUrl.value.isNotEmpty) {
      final uri = Uri.parse('${baseUrl.value}/v1/parse');
      try {
        final body = jsonEncode({
          'platform': platform,
          'ids': id,
          'quality': '128k',
        });

        debugPrint('Thinking Parse: $uri');
        debugPrint('Body: $body');

        final response = await AndroidBackgroundNetworkService.protect(
          'music_parse_${platform}_$id',
          () => http.post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'X-API-Key': _randomApiKey, // 使用轮询 Key
            },
            body: body,
          ),
          title: 'StarBank 音乐',
          text: '正在解析播放链接',
        );

        final resStr = _safeGetBody(response);
        debugPrint('TH Parse Res: $resStr');

        if (response.statusCode == 200) {
          final json = jsonDecode(resStr);
          if (json['code'] == 0 && json['data'] != null) {
            final data = json['data'];
            // 适配各种返回格式
            if (data is Map && data['data'] is List) {
              // data: { data: [{id: xxx, url: xxx}] }
              for (var item in (data['data'] as List)) {
                if (item is Map && item['id'].toString() == id)
                  return Map<String, dynamic>.from(item);
              }
            }
            if (data is Map && data[id] != null) {
              return Map<String, dynamic>.from(data[id]);
            }
          }
        }
      } catch (e) {
        debugPrint('TH Parse Error: $e');
      }
    }

    // Fallback: 如果上面的硬编码失败，尝试用旧方法 (通常不应走到这里)
    return {};
  }
}
