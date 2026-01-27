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

      debugPrint('TH Request: $uri');

      http.Response response;
      if (config.method == 'POST') {
        debugPrint('TH Body: $finalBody');
        response = await http.post(uri, headers: headers, body: finalBody);
      } else {
        response = await http.get(uri, headers: headers);
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
      final raw = await _executeMethod(method, vars);
      if (raw == null) return [];

      List<MusicTrack> tracks = [];
      dynamic list;

      if (raw is Map) {
        if (raw['abslist'] != null)
          list = raw['abslist'];
        else if (raw['result'] is Map && raw['result']['songs'] != null)
          list = raw['result']['songs'];
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
              item['web_albumpic_short'] ??
              (item['album'] is Map ? item['album']['picUrl'] : null);
          if (cover != null && cover.startsWith('//')) cover = 'https:$cover';

          tracks.add(MusicTrack(
            id: id,
            title: (item['name'] ??
                    item['title'] ??
                    item['SONGNAME'] ??
                    item['songname'] ??
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
    var singer = item['artist'] ??
        item['singer'] ??
        item['ARTIST'] ??
        item['SINGER'] ??
        item['ar'] ??
        item['artists'];
    if (singer is List && singer.isNotEmpty) {
      return singer
          .map((e) => e is Map ? (e['name'] ?? '') : e.toString())
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

        final response = await http.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'X-API-Key': _randomApiKey, // 使用轮询 Key
          },
          body: body,
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
