import 'dart:convert';
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
        'https://api.tunehub.example.com'; // User needs to change this
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
      if (apiKey.value.isNotEmpty)
        'Authorization':
            'Bearer ${apiKey.value}', // Assuming Bearer auth or similar
      'x-api-key': apiKey.value,
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
      // Simple string replacement for {{val}}
      vars.forEach((k, v) {
        if (value is String && value.contains('{{$k}}')) {
          finalParams[key] = (value as String).replaceAll('{{$k}}', v);
        }
      });
    });
    // Replace variables in URL if any (though usually in params)
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
    try {
      final method = await _getMethod(platform, 'search');
      final rawResult = await _executeMethod(method,
          {'keyword': keyword, 'page': page.toString(), 'pageSize': '20'});

      // PARSING LOGIC: This assumes specific structure based on platform unfortunately.
      // For the "First Version", if the user does NOT provide a working JS engine,
      // I have to hack this for Kuwo/Netease if I want it to actually SHOW music.
      // Or I can return dummy data if the API isn't real yet.

      // Let's assume standard Kuwo JSON for demo if possible, or just look for a list.
      List<MusicTrack> tracks = [];

      if (platform == 'kuwo') {
        // Basic Kuwo parsing logic (example)
        // If rawResult is a Map, look for 'abslist' or similar
        if (rawResult is Map) {
          final list = rawResult['abslist'] ?? rawResult['data']?['list'];
          if (list is List) {
            for (var item in list) {
              tracks.add(MusicTrack(
                  id: item['MUSICRID'] ?? item['id'].toString(),
                  title: item['SONGNAME'] ?? item['name'],
                  artist: item['ARTIST'] ?? item['artist'],
                  coverUrl: item['web_albumpic_short'] ?? item['pic'],
                  platform: platform));
            }
          }
        }
      } else if (platform == 'netease') {
        // Basic Netease parsing
        if (rawResult is Map &&
            rawResult['result'] != null &&
            rawResult['result']['songs'] != null) {
          for (var item in rawResult['result']['songs']) {
            tracks.add(MusicTrack(
                id: item['id'].toString(),
                title: item['name'],
                artist:
                    (item['artists'] as List).map((e) => e['name']).join(','),
                album: item['album']?['name'],
                // Netease often needs separate call for cover, or it's in album
                coverUrl: item['album']?['picUrl'] ?? item['picUrl'],
                platform: platform));
          }
        }
      }

      return tracks;
    } catch (e) {
      print('Search Error: $e');
      return [];
    }
  }
}
