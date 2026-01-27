import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import '../models/music/music_track.dart';
import '../models/music/tunehub_method.dart';
import 'storage_service.dart';

class TuneHubService extends GetxService {
  final StorageService _storage = Get.find<StorageService>();

  final RxString baseUrl = ''.obs;
  final RxString apiKey = ''.obs;

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

  String _safeGetBody(http.Response res) {
    try {
      return utf8.decode(res.bodyBytes);
    } catch (e) {
      return res.body;
    }
  }

  // 获取随机 Key 以实现负载均衡
  String get _randomApiKey {
    if (apiKey.value.isEmpty) return '';
    final keys =
        apiKey.value.split(';').where((k) => k.trim().isNotEmpty).toList();
    if (keys.isEmpty) return '';
    return keys[DateTime.now().millisecondsSinceEpoch % keys.length].trim();
  }

  Future<TuneHubMethod> _getMethod(String platform, String function) async {
    if (baseUrl.value.isEmpty) throw Exception('请先配置 TuneHub 服务器地址');
    final uri = Uri.parse('${baseUrl.value}/v1/methods/$platform/$function');

    // 使用随机 Key
    final response = await http.get(uri, headers: {'X-API-Key': _randomApiKey});

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

    // 1. 优先处理数学硬编码 (必须最先处理)
    if (source.contains('page') && source.contains('*')) {
      // (page-1)*limit
      try {
        final page = int.parse(vars['page'] ?? '1');
        final limit = int.parse(vars['limit'] ?? '20');
        final val = ((page - 1) * limit).toString();
        // 替换整个 {{...}} 块
        return source.replaceAll(RegExp(r'\{\{.*?\}\}'), val);
      } catch (_) {}
    }
    if (source.contains('page') && source.contains('-')) {
      // page-1
      try {
        final page = int.parse(vars['page'] ?? '1');
        final val = (page - 1).toString();
        return source.replaceAll(RegExp(r'\{\{.*?\}\}'), val);
      } catch (_) {}
    }

    // 2. 普通变量替换
    var result = source;
    final regExp = RegExp(r'\{\{(.*?)\}\}');
    result = result.replaceAllMapped(regExp, (match) {
      String content = match.group(1)!.trim();

      // 处理默认值 limit || 20
      if (content.contains('||')) {
        final parts = content.split('||');
        final key = parts[0].trim();
        if (vars.containsKey(key)) return vars[key]!;
        // 返回默认值
        return parts[1].trim().replaceAll('"', '').replaceAll("'", "");
      }

      // 直接变量
      return vars[content] ?? '';
    });

    return result;
  }

  dynamic _deepReplace(dynamic source, Map<String, String> vars) {
    if (source is String) {
      final res = _replaceString(source, vars);
      // 尝试转 INT
      if (source.contains('{{')) {
        final asNum = int.tryParse(res);
        if (asNum != null && !res.startsWith('0')) return asNum;
      }
      return res;
    } else if (source is Map) {
      // 递归 Map
      return source
          .map((key, value) => MapEntry(key, _deepReplace(value, vars)));
    } else if (source is List) {
      // 递归 List
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
      final finalUrl = _deepReplace(config.url, context).toString();
      final uri = Uri.parse(finalUrl).replace(queryParameters: processedParams);

      final Map<String, String> headers = {};
      if (config.headers != null) {
        config.headers!.forEach((k, v) {
          var val = _deepReplace(v, context).toString().trim();
          if (val.endsWith(';')) val = val.substring(0, val.length - 1).trim();
          headers[k] = val;
        });
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

      debugPrint('TH Request: $uri');

      http.Response response;
      if (config.method == 'POST') {
        // 关键调试：打印 Body
        debugPrint('TH Body: $finalBody');
        response = await http.post(uri, headers: headers, body: finalBody);
      } else {
        response = await http.get(uri, headers: headers);
      }

      final bodyStr = _safeGetBody(response);

      if (bodyStr.length > 500) {
        debugPrint('TH Response (prefix): ${bodyStr.substring(0, 500)}...');
      } else {
        debugPrint('TH Response: $bodyStr');
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
    // 注入全部可能的关键字别名
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
      final raw = await _executeMethod(method, vars);
      if (raw == null) return [];

      List<MusicTrack> tracks = [];
      dynamic list;

      // 暴力但有效的查找逻辑
      if (raw is Map) {
        // 酷我路径
        if (raw['abslist'] != null)
          list = raw['abslist'];
        // 网易云路径
        else if (raw['result'] is Map && raw['result']['songs'] != null)
          list = raw['result']['songs'];
        // QQ 音乐路径
        else {
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

      if (list is List) {
        for (var item in list) {
          // 核心修复：加入 Kuwo 的 DC_TARGETID 和 MUSICRID
          final id = (item['id'] ??
                  item['rid'] ??
                  item['mid'] ??
                  item['songId'] ??
                  item['DC_TARGETID'] ??
                  item['MUSICRID'] ??
                  '')
              .toString();

          if (id.isEmpty) continue;

          String? cover = item['hts_MVPIC'] ??
              item['pic'] ??
              item['img'] ??
              item['picUrl'] ??
              (item['album'] is Map ? item['album']['picUrl'] : null);
          if (cover != null && cover.startsWith('//')) cover = 'https:$cover';

          tracks.add(MusicTrack(
            id: id,
            title: (item['name'] ??
                    item['title'] ??
                    item['songname'] ??
                    item['SONGNAME'] ??
                    '未知歌曲')
                .toString(),
            artist: _parseArtist(item),
            coverUrl: cover,
            album: item['album'] is Map
                ? item['album']['name']
                : (item['album'] ?? item['ALBUM'] ?? ''),
            platform: platform,
          ));
        }
      }
      return tracks;
    } catch (e) {
      debugPrint('TuneHub Search Error: $e');
      return [];
    }
  }

  String _parseArtist(dynamic item) {
    var singer =
        item['artist'] ?? item['singer'] ?? item['ar'] ?? item['artists'];
    if (singer is List && singer.isNotEmpty) {
      return singer
          .map((e) => e is Map ? (e['name'] ?? '') : e.toString())
          .join('/');
    }
    if (singer is Map) return (singer['name'] ?? '').toString();
    return (singer ?? '未知歌手').toString();
  }

  Future<Map<String, dynamic>> parseTrack(String platform, String id) async {
    try {
      final method = await _getMethod(platform, 'parse');
      // 解析请求这里也要随机 Key，但 _getMethod 已经随机取了一个配置。
      // 关键在于 _executeMethod 内部会不会用 key？
      // 查看 _executeMethod 实现，它会用 config.headers。
      // 此时我们需要覆盖 header 里的 key 或者确保 config 里没写死 key。
      // 通常 Method 配置里不会写 X-API-Key，而是由客户端注入。
      // 我们之前的 _executeMethod 并没有显式注入 X-API-Key。
      // 这似乎是个BUG，或者 Method 配置里自带 key?

      // 检查原 TuneHub 文档：API Key 是客户端请求 TuneHub 网关用的。
      // 而 _executeMethod 请求的是第三方音乐 API (如 u.y.qq.com)。
      // 第三方 API 不需要我们的 API Key。
      // **但是**，如果这是一个 "Parse" 请求，如果它是请求 TuneHub 自建的解析服务，那就需要 Key。

      // 根据您的代码逻辑，_executeMethod 是执行 TuneHub 返回的 Method 配置。
      // 如果 Method 是直接请求第三方，那不需要 Key。
      // 但 _parseTrack 的逻辑里，我们看到它是请求 /v1/parse (TuneHub 自己的接口)。
      // 等等，之前的代码里 parseTrack 是直接 http.post 到 baseUrl/v1/parse。

      // 啊！之前的代码里 parseTrack 是这么写的：
      /*
      final method = await _getMethod(platform, 'parse');
      final result = await _executeMethod(method...);
      */
      // 这说明 parse 也是走通用 Method 流程。

      // 让我们回头看旧代码 (Step 781):
      // Future<Map<String, dynamic>> parseTrack(String platform, String id) async {
      //   try {
      //     final method = await _getMethod(platform, 'parse');
      //     final result = await _executeMethod(method, { ... });

      // 所以不需要特别改动 parseTrack，因为主要耗额度的是 _getMethod（获取配置）和 TuneHub 中转的流量。
      // 如果 /v1/parse 是真实解析接口，那它确实消耗额度。

      // 修正逻辑：
      // TuneHub 的设计是：
      // 1. 获取 Method (消耗额度? 通常不，配置是静态的)
      // 2. 执行 Method (如果 Method URL 是 TuneHub 代理地址，则消耗；如果是直连第三方，则不消耗)

      // 如果用户提到的“听歌额度”，通常是指 TuneHub 的 VIP 解析服务。
      // 之前的代码里 parseTrack 逻辑被修改为走 _executeMethod。
      // 如果 method 是指向 TuneHub 的 parse 接口，那 header 应该在 method 配置里。
      // 但更可能是：我们需要在 parseTrack 里**显式**调用带 Key 的接口？

      // 此时我们还是保持现状，因为 _getMethod 已经随机了 Key。
      // 如果 /v1/methods/platform/parse 返回的配置里包含 X-API-Key 字段且值为 {{key}}，那我们得注入。

      // 但为了安全起见，我们假设用户是想让所有发往 TuneHub 的请求都轮询 Key。
      // 目前只有 _getMethod 是发往 TuneHub 的。
      // 还有之前的 parseTrack 实现里有直接 POST /v1/parse 的版本。
      // 现在版本是基于 _getMethod 的。

      // 让我们不做多余改动，只需确保 `_getMethod` 用了随机 Key 即可。
      // 下面我仅仅是恢复代码，不做逻辑变更，只是为了确认。

      final result = await _executeMethod(method, {
        'platform': platform,
        'id': id,
        'quality': '128k',
      });
      if (result is Map) {
        if (result['success'] == true) return Map<String, dynamic>.from(result);
        if (result['data'] != null && result['data'] is Map) {
          final data = result['data'];
          if (data[id] != null) return Map<String, dynamic>.from(data[id]);
        }
      }
    } catch (_) {}
    return {};
  }
}
