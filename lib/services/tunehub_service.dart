import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import '../models/music/music_track.dart';
import '../models/music/tunehub_method.dart';
import 'storage_service.dart';

class TuneHubService extends GetxService {
  final StorageService _storage = Get.find<StorageService>();

  // Default to a placeholder if user hasn't set one, or use a public one if known.
  // For now, I'll use a placeholder and allow user to set it.
  final RxString baseUrl = ''.obs;
  final RxString apiKey = ''.obs;

  @override
  void onInit() {
    super.onInit();
    // Load from storage if available
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

  Future<TuneHubMethod> _getMethod(String platform, String function) async {
    if (baseUrl.value.isEmpty) throw Exception('请先配置 TuneHub 服务器地址');

    final uri = Uri.parse('${baseUrl.value}/v1/methods/$platform/$function');
    final response = await http.get(uri, headers: {
      'X-API-Key': apiKey.value,
    });

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      if (json['code'] == 0 && json['data'] != null) {
        return TuneHubMethod.fromJson(json['data']);
      } else {
        throw Exception(json['msg'] ?? '获取配置失败');
      }
    } else {
      throw Exception('网络错误: ${response.statusCode}');
    }
  }

  // Generic executor
  Future<dynamic> _executeMethod(
      TuneHubMethod config, Map<String, String> vars) async {
    var finalUrl = config.url;
    var finalParams = Map<String, String>.from(config.params);

    // Replace variables in params
    finalParams.forEach((key, value) {
      var processedValue = value;
      vars.forEach((k, v) {
        // 1. Exact match: {{keyword}}
        if (processedValue.contains('{{$k}}')) {
          processedValue = processedValue.replaceAll('{{$k}}', v);
        }
        // 2. Logic match: {{(page || 1) - 1}} or {{page - 1}}
        // Handle common 0-indexing conversion for music APIs
        if (k == 'page' &&
            (processedValue.contains('page') &&
                processedValue.contains('- 1'))) {
          try {
            final pageInt = int.parse(v);
            final newVal = (pageInt - 1).toString();
            // Replace the whole template block
            processedValue = processedValue.replaceAll(
                RegExp(r'\{\{.*?page.*?\}\}'), newVal);
          } catch (_) {}
        }
        // 3. Fallback/Default match: {{limit || 20}}
        if (processedValue.contains('{{$k') && processedValue.contains('||')) {
          processedValue =
              processedValue.replaceAll(RegExp(r'\{\{.*?' + k + r'.*?\}\}'), v);
        }
      });
      finalParams[key] = processedValue;
    });

    // Replace variables in URL
    vars.forEach((k, v) {
      if (finalUrl.contains('{{$k}}')) {
        finalUrl = finalUrl.replaceAll('{{$k}}', v);
      }
    });

    final uri = Uri.parse(finalUrl).replace(queryParameters: finalParams);

    final headers = config.headers ?? {};
    // Add standard headers if needed

    http.Response response;
    if (config.method == 'POST') {
      response = await http.post(uri, headers: headers, body: config.body);
    } else {
      response = await http.get(uri, headers: headers);
    }

    if (response.statusCode == 200) {
      // Here lies the problem: The API expects us to run 'transform' (JS).
      // Since we are in Dart, we must manually parse known responses if we can't run JS.
      // Or return raw body and let the caller handle specialized parsing.
      return _manualParse(response.body, vars);
    } else {
      throw Exception(
          'Accessing Music Provider Failed: ${response.statusCode}');
    }
  }

  // Temporary manual parser until we have a JS engine or better solution
  dynamic _manualParse(String body, Map<String, String> vars) {
    // Try JSON
    try {
      return jsonDecode(body);
    } catch (e) {
      return body; // Return detailed string if not JSON
    }
  }

  // --- High Level APIs ---

  Future<List<MusicTrack>> searchMusic(String keyword,
      {String platform = 'kuwo', int page = 1}) async {
    if (GetPlatform.isWeb) {
      Get.snackbar('平台限制', '由于浏览器 CORS 限制，Web 端搜索可能会失败，请使用 Windows 或安卓端',
          backgroundColor: Colors.orange, colorText: Colors.white);
    }
    try {
      final method = await _getMethod(platform, 'search');
      final rawResult = await _executeMethod(method, {
        'keyword': keyword,
        'page': page.toString(),
        'pageSize': '20',
        'limit': '20', // Common alias
      });

      List<MusicTrack> tracks = [];

      // V3 Result is usually in data.list or similar based on method transform
      // Since we can't run JS 'transform' easily, we handle common ones.
      if (rawResult is Map) {
        final list = rawResult['list'] ??
            rawResult['data']?['list'] ??
            rawResult['abslist'];
        if (list is List) {
          for (var item in list) {
            tracks.add(MusicTrack(
              id: (item['id'] ?? item['MUSICRID'] ?? item['songId']).toString(),
              title: item['name'] ?? item['SONGNAME'] ?? item['title'] ?? '',
              artist: item['artist'] ?? item['ARTIST'] ?? item['singer'] ?? '',
              coverUrl: item['pic'] ??
                  item['web_albumpic_short'] ??
                  item['img'] ??
                  item['album']?['picUrl'],
              album: item['album']?['name'] ?? item['ALBUM'] ?? '',
              platform: platform,
            ));
          }
        }
      }
      return tracks;
    } catch (e) {
      print('TuneHub Search Error: $e');
      return [];
    }
  }

  /// 获取播放地址和歌词
  Future<Map<String, dynamic>> parseTrack(String platform, String id) async {
    if (baseUrl.value.isEmpty) throw Exception('未配置服务器');

    final uri = Uri.parse('${baseUrl.value}/v1/parse');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'X-API-Key': apiKey.value,
      },
      body: jsonEncode({
        'platform': platform,
        'ids': id,
        'quality': '128k', // Default quality
      }),
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      if (json['code'] == 0 && json['data'] != null) {
        final results = json['data'] as Map;
        // Search for ID either as string or int
        var trackData = results[id] ?? results[int.tryParse(id)];

        if (trackData == null) {
          final key = results.keys.firstWhere(
            (k) => k.toString().contains(id) || id.contains(k.toString()),
            orElse: () => null,
          );
          if (key != null) trackData = results[key];
        }

        return trackData != null ? Map<String, dynamic>.from(trackData) : {};
      }
    }
    return {};
  }
}
