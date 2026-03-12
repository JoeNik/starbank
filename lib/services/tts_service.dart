import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:hive/hive.dart';
import 'package:just_audio/just_audio.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../models/cftts_config.dart';

/// 全局 TTS 语音服务
/// 使用 GetxService 确保全局单例，所有页面共享同一个 TTS 实例
class TtsService extends GetxService {
  late FlutterTts _flutterTts;
  late Box _settingsBox;

  // CFTTS 相关配置
  late Box<CfttsConfig> _cfttsConfigBox;
  final Rx<CfttsConfig?> cfttsConfig = Rx<CfttsConfig?>(null);
  
  // 选择使用系统 TTS 还是 CFTTS的开关
  final RxBool useCftts = false.obs;
  
  // 用于播放 CFTTS 生成音频的服务
  late AudioPlayer _audioPlayer;

  // 避免对同一个文本的并发请求
  final Map<String, Future<File?>> _cfttsFetchTasks = {};

  // 可调参数
  final RxDouble speechRate = 0.5.obs;
  final RxDouble pitch = 1.0.obs;
  final RxDouble volume = 1.0.obs;

  // 引擎
  final RxString currentEngine = ''.obs;
  final RxList<String> engines = <String>[].obs;

  // 状态
  final RxBool isSpeaking = false.obs;

  /// 朗读进度回调（参数为当前朗读到的文本起始位置 offset）
  /// 外部（如卡拉OK高亮）可设置此回调来跟踪实际朗读位置
  void Function(int start, int end)? onProgressCallback;
  void Function()? onStartCallback;
  final RxBool isInitialized = false.obs;

  /// 初始化服务
  Future<TtsService> init() async {
    _flutterTts = FlutterTts();
    _audioPlayer = AudioPlayer();
    _settingsBox = await Hive.openBox('tts_settings');

    if (!Hive.isAdapterRegistered(41)) {
      Hive.registerAdapter(CfttsConfigAdapter());
    }
    _cfttsConfigBox = await Hive.openBox<CfttsConfig>('cftts_config_box');

    // 加载保存的设置
    await _loadSettings();

    // Android 专用配置: 等待播放完成回调，这对于某些引擎的状态同步很重要
    if (GetPlatform.isAndroid) {
      await _flutterTts.awaitSpeakCompletion(true);
    }

    // 显式设置中文
    try {
      await _flutterTts.setLanguage("zh-CN");
    } catch (e) {
      debugPrint('设置语言失败: $e');
    }

    // 获取引擎列表
    if (GetPlatform.isAndroid) {
      try {
        final engineList = await _flutterTts.getEngines;
        if (engineList != null && engineList is List) {
          engines.addAll(engineList.map((e) => e.toString()));

          // 如果没有保存的引擎，尝试获取并设置默认引擎
          // 这有助于在某些系统(如MIUI)上"唤醒"默认引擎
          if (_settingsBox.get('tts_engine', defaultValue: '') == '') {
            try {
              final defaultEngine = await _flutterTts.getDefaultEngine;
              if (defaultEngine != null && defaultEngine.isNotEmpty) {
                await _flutterTts.setEngine(defaultEngine);
                currentEngine.value = defaultEngine;
                // 再次应用设置，确保生效
                await Future.delayed(const Duration(milliseconds: 200));
                await _applyGlobalSettings();
              }
            } catch (_) {}
          }
        }
      } catch (e) {
        debugPrint('获取引擎列表失败: $e');
      }
    }

    // 监听播放状态
    _flutterTts.setStartHandler(() {
      isSpeaking.value = true;
      onStartCallback?.call();
    });
    _flutterTts.setCompletionHandler(() {
      isSpeaking.value = false;
      onProgressCallback = null; // 播放结束后清除回调
    });
    _flutterTts.setCancelHandler(() {
      isSpeaking.value = false;
      onProgressCallback = null;
    });
    _flutterTts.setErrorHandler((msg) {
      isSpeaking.value = false;
      onProgressCallback = null;
      debugPrint('TTS Error: $msg');
      // 尝试重置
      if (msg.toString().contains('not bound')) {
        _resetTts();
      }
    });

    // 朗读进度回调 - 追踪当前朗读到文本的哪个位置 (仅 FlutterTts)
    _flutterTts.setProgressHandler(
        (String text, int start, int end, String word) {
      onProgressCallback?.call(start, end);
    });

    // 监听 just_audio 的播放状态
    _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        // 无论何种音色，如果底层刚刚播放完成，统统标记结束
        isSpeaking.value = false;
        onProgressCallback = null;
      }
    });

    isInitialized.value = true;
    return this;
  }

  Future<void> _resetTts() async {
    try {
      await _flutterTts.stop();
      await _flutterTts.setLanguage("zh-CN");
    } catch (e) {
      debugPrint('Rest TTS Error $e');
    }
  }

  /// 加载保存的设置
  Future<void> _loadSettings() async {
    speechRate.value = _settingsBox.get('speech_rate', defaultValue: 0.5);
    pitch.value = _settingsBox.get('pitch', defaultValue: 1.0);
    volume.value = _settingsBox.get('volume', defaultValue: 1.0);
    final savedEngine = _settingsBox.get('tts_engine', defaultValue: '');
    useCftts.value = _settingsBox.get('use_cftts', defaultValue: false);

    // 加载或创建 CFTTS 配置
    if (_cfttsConfigBox.isEmpty) {
      final defaultCftts = CfttsConfig();
      await _cfttsConfigBox.add(defaultCftts);
      cfttsConfig.value = defaultCftts;
    } else {
      cfttsConfig.value = _cfttsConfigBox.values.first;
    }

    // 应用设置
    await _flutterTts.setSpeechRate(speechRate.value);
    await _flutterTts.setPitch(pitch.value);
    await _flutterTts.setVolume(volume.value);

    // 恢复引擎
    if (savedEngine.isNotEmpty) {
      try {
        final engineList = await _flutterTts.getEngines;
        if (engineList != null && engineList.contains(savedEngine)) {
          await _flutterTts.setEngine(savedEngine);
          currentEngine.value = savedEngine;
        }
      } catch (e) {
        debugPrint('恢复引擎失败: $e');
      }
    }
  }

  /// 重新加载设置（从设置页面返回后调用）
  Future<void> reloadSettings() async {
    await _loadSettings();
    debugPrint('TTS 设置已重新加载: 语速=${speechRate.value}');
  }

  /// 播放文本
  Future<void> speak(String text,
      {double? rate, double? volume, double? pitch, String? featureKey}) async {
    if (isSpeaking.value) {
      await stop();
    }

    bool shouldCftts = useCftts.value;
    if (featureKey != null) {
      final override = getFeatureTtsEngine(featureKey);
      if (override == 'cftts') shouldCftts = true;
      if (override == 'system') shouldCftts = false;
    }

    if (shouldCftts && cfttsConfig.value != null && cfttsConfig.value!.baseUrl.isNotEmpty) {
      await _speakCftts(text);
      return;
    }

    // 确保语言被设置 (Xiaomi fix)
    await _flutterTts.setLanguage("zh-CN");

    if (rate != null || volume != null || pitch != null) {
      // 如果指定了参数，则临时设置
      if (rate != null) await _flutterTts.setSpeechRate(rate);
      if (volume != null) await _flutterTts.setVolume(volume);
      if (pitch != null) await _flutterTts.setPitch(pitch);
    } else {
      // 否则应用全局设置
      await _applyGlobalSettings();
    }

    await _flutterTts.speak(text);
  }

  Future<void> prefetchCftts(String text, {String? featureKey}) async {
    bool shouldCftts = useCftts.value;
    if (featureKey != null) {
      final override = getFeatureTtsEngine(featureKey);
      if (override == 'cftts') shouldCftts = true;
      if (override == 'system') shouldCftts = false;
    }

    if (!shouldCftts || cfttsConfig.value == null || cfttsConfig.value!.baseUrl.isEmpty) {
      return;
    }

    // 调用通用获取缓冲文件的逻辑，提前触发下载任务
    await _getOrFetchCftts(text);
  }

  /// 内部获取或下载 CFTTS 的逻辑
  Future<File?> _getOrFetchCftts(String text) async {
    final tempDir = await getTemporaryDirectory();
    final textMd5 = md5.convert(utf8.encode(text)).toString();
    final cacheFile = File('${tempDir.path}/cftts_cache_$textMd5.mp3');

    if (await cacheFile.exists()) {
      return cacheFile; // 已有缓存
    }

    // 检查是否正在请求，若是，直接等待先前的未来
    if (_cfttsFetchTasks.containsKey(textMd5)) {
      return await _cfttsFetchTasks[textMd5];
    }

    // 开启新的请求任务
    final task = () async {
      try {
        final cfg = cfttsConfig.value!;
        final url = Uri.parse('${cfg.baseUrl}/v1/audio/speech');
        final headers = {'Content-Type': 'application/json'};
        if (cfg.apiKey.isNotEmpty) headers['Authorization'] = 'Bearer ${cfg.apiKey}';
        
        final body = jsonEncode({
          "model": cfg.model,
          "input": text,
          "voice": cfg.voice,
          "speed": cfg.speed,
        });

        final response = await http.post(url, headers: headers, body: body);

        if (response.statusCode == 200) {
          await cacheFile.writeAsBytes(response.bodyBytes);
          debugPrint('CFTTS 下载成功并保存缓存: ${cacheFile.path}');
          return cacheFile;
        } else {
          debugPrint('CFTTS 请求失败: ${response.statusCode} - ${response.body}');
        }
      } catch (e) {
        debugPrint('CFTTS 预取失败: $e');
      } finally {
        _cfttsFetchTasks.remove(textMd5);
      }
      return null;
    }();

    _cfttsFetchTasks[textMd5] = task;
    return await task;
  }

  /// 清除所有的 CFTTS 缓存
  Future<void> clearCfttsCache() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final files = tempDir.listSync();
      for (var file in files) {
        if (file is File && file.path.contains('cftts_cache_')) {
          await file.delete();
        }
      }
      debugPrint('CFTTS 缓存已清理');
    } catch (e) {
      debugPrint('清理 CFTTS 缓存失败: $e');
    }
  }

  Future<void> _speakCftts(String text) async {
    try {
      isSpeaking.value = true;
      final playFile = await _getOrFetchCftts(text);

      if (playFile == null) {
         isSpeaking.value = false;
         debugPrint('CFTTS 请求失败，无法播放');
         return;
      }

      // 强制停止底层的 just_audio，避免重新加载一样路径的缓存时状态被卡在 Completed 导致随后 play() 秒退返回
      await _audioPlayer.stop();
      await _audioPlayer.setFilePath(playFile.path);
      await _audioPlayer.seek(Duration.zero);
      onStartCallback?.call();
      await _audioPlayer.play();
    } catch (e) {
      isSpeaking.value = false;
      debugPrint('CFTTS播放失败: $e');
    }
  }

  /// 在开始播放前应用全局设置
  Future<void> _applyGlobalSettings() async {
    await _flutterTts.setSpeechRate(speechRate.value);
    await _flutterTts.setPitch(pitch.value);
    await _flutterTts.setVolume(volume.value);
  }

  /// 停止播放
  Future<void> stop() async {
    try {
      await _audioPlayer.stop();
      await _flutterTts.stop();
    } catch (e) {
      debugPrint('TTS 停止失败: $e');
    }
    isSpeaking.value = false;
  }

  /// 设置语速
  Future<void> setSpeechRate(double rate) async {
    speechRate.value = rate;
    await _flutterTts.setSpeechRate(rate);
    await _settingsBox.put('speech_rate', rate);
  }

  /// 设置音调
  Future<void> setPitch(double value) async {
    pitch.value = value;
    await _flutterTts.setPitch(value);
    await _settingsBox.put('pitch', value);
  }

  /// 设置音量
  Future<void> setVolume(double value) async {
    volume.value = value;
    await _flutterTts.setVolume(value);
    await _settingsBox.put('volume', value);
  }

  /// 设置引擎
  Future<void> setEngine(String engine) async {
    await _flutterTts.setEngine(engine);
    currentEngine.value = engine;
    await _settingsBox.put('tts_engine', engine);

    // 重新应用语速等设置（切换引擎后可能需要）
    await _flutterTts.setSpeechRate(speechRate.value);
    await _flutterTts.setPitch(pitch.value);
    await _flutterTts.setVolume(volume.value);
  }

  /// 获取 CFTTS 支持的语音风格列表
  Future<List<String>> fetchCfttsVoices() async {
    final cfg = cfttsConfig.value;
    if (cfg == null || cfg.baseUrl.isEmpty) return [];

    try {
      final url = Uri.parse('${cfg.baseUrl}/voices');
      final headers = <String, String>{};
      if (cfg.apiKey.isNotEmpty) {
        headers['Authorization'] = 'Bearer ${cfg.apiKey}';
      }

      final response = await http.get(url, headers: headers).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        // 由于返回体是 JSON 对象数组
        // 形如: [{"ShortName": "am-ET-AmehaNeural", ...}, ...]
        final dynamic data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data is List) {
           final List<String> voices = [];
           for (var item in data) {
             if (item is Map && item.containsKey('ShortName')) {
               voices.add(item['ShortName'].toString());
             } else if (item is String) {
               // 兜底某些接口可能直接返回字符串数组
               voices.add(item);
             }
           }
           if (voices.isNotEmpty) {
             return voices;
           }
        }
      }
      debugPrint('获取 CFTTS 语音列表失败: HTTP ${response.statusCode} - ${response.body}');
    } catch (e) {
      debugPrint('获取 CFTTS 语音列表异常: $e');
    }
    return [];
  }

  /// 获取引擎显示名称
  String getEngineDisplayName(String engine) {
    if (engine.isEmpty) return '系统默认';
    if (engine.contains('google')) return 'Google TTS';
    if (engine.contains('samsung')) return '三星 TTS';
    if (engine.contains('huawei')) return '华为 TTS';
    if (engine.contains('xiaomi')) return '小米 TTS';
    if (engine.contains('multi')) return 'MultiTTS';
    if (engine.contains('iflytek')) return '讯飞 TTS';
    return engine.split('.').last;
  }

  /// 切换全局引擎模式（System或CFTTS）
  Future<void> setUseCftts(bool value) async {
    useCftts.value = value;
    await _settingsBox.put('use_cftts', value);
  }

  /// 更新 CFTTS 配置
  Future<void> updateCfttsConfig(CfttsConfig newConfig) async {
    if (_cfttsConfigBox.isEmpty) {
      await _cfttsConfigBox.add(newConfig);
    } else {
      final existingKey = _cfttsConfigBox.keys.first;
      await _cfttsConfigBox.put(existingKey, newConfig);
    }
    cfttsConfig.value = newConfig;
  }

  /// 获取某个功能特有的 TTS 覆盖设置
  /// 返回 'global' (跟随系统), 'system' (强制使用系统TTS), 'cftts' (强制使用自建CFTTS)
  String getFeatureTtsEngine(String featureKey) {
    return _settingsBox.get('tts_engine_$featureKey', defaultValue: 'global');
  }

  /// 设定某个功能的专项 TTS 覆盖设置
  Future<void> setFeatureTtsEngine(String featureKey, String engine) async {
    await _settingsBox.put('tts_engine_$featureKey', engine);
  }

  @override
  void onClose() {
    _flutterTts.stop();
    _audioPlayer.dispose();
    super.onClose();
  }
}
