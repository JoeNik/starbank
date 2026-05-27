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
import '../models/openai_tts_config.dart';

/// 全局 TTS 语音服务
/// 使用 GetxService 确保全局单例，所有页面共享同一个 TTS 实例
class TtsService extends GetxService {
  static const String engineGlobal = 'global';
  static const String engineSystem = 'system';
  static const String engineCftts = 'cftts';
  static const String openAITtsPrefix = 'openai_tts:';

  late FlutterTts _flutterTts;
  late Box _settingsBox;

  // CFTTS 相关配置
  late Box<CfttsConfig> _cfttsConfigBox;
  final Rx<CfttsConfig?> cfttsConfig = Rx<CfttsConfig?>(null);

  // OpenAI 格式 TTS Provider 配置
  late Box<OpenAITtsConfig> _openAITtsConfigBox;
  final RxList<OpenAITtsConfig> openAITtsConfigs = <OpenAITtsConfig>[].obs;
  final RxString globalTtsRoute = engineSystem.obs;

  // 兼容旧逻辑：是否使用 CFTTS
  final RxBool useCftts = false.obs;

  // 用于播放远程 TTS 生成音频的服务
  late AudioPlayer _audioPlayer;

  /// 暴露 audioPlayer 给外部监听播放进度（用于卡拉OK同步等场景）
  AudioPlayer get audioPlayer => _audioPlayer;

  // 避免对同一个文本的并发请求
  final Map<String, Future<File?>> _remoteTtsFetchTasks = {};

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
    if (!Hive.isAdapterRegistered(42)) {
      Hive.registerAdapter(OpenAITtsConfigAdapter());
    }
    _cfttsConfigBox = await Hive.openBox<CfttsConfig>('cftts_config_box');
    _openAITtsConfigBox =
        await Hive.openBox<OpenAITtsConfig>('openai_tts_config_box');

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
          engines.assignAll(engineList.map((e) => e.toString()));

          if (_settingsBox.get('tts_engine', defaultValue: '') == '') {
            try {
              final defaultEngine = await _flutterTts.getDefaultEngine;
              if (defaultEngine != null && defaultEngine.isNotEmpty) {
                await _flutterTts.setEngine(defaultEngine);
                currentEngine.value = defaultEngine;
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
      onProgressCallback = null;
    });
    _flutterTts.setCancelHandler(() {
      isSpeaking.value = false;
      onProgressCallback = null;
    });
    _flutterTts.setErrorHandler((msg) {
      isSpeaking.value = false;
      onProgressCallback = null;
      debugPrint('TTS Error: $msg');
      if (msg.toString().contains('not bound')) {
        _resetTts();
      }
    });

    _flutterTts
        .setProgressHandler((String text, int start, int end, String word) {
      onProgressCallback?.call(start, end);
    });

    _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
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

    // 加载旧版 use_cftts 兼容值，再优先读取新版 route
    useCftts.value = _settingsBox.get('use_cftts', defaultValue: false);
    final savedRoute = _settingsBox.get(
      'tts_global_route',
      defaultValue: useCftts.value ? engineCftts : engineSystem,
    );
    globalTtsRoute.value = _normalizeEngineRoute(savedRoute.toString());
    useCftts.value = globalTtsRoute.value == engineCftts;

    if (_cfttsConfigBox.isEmpty) {
      final defaultCftts = CfttsConfig();
      await _cfttsConfigBox.add(defaultCftts);
      cfttsConfig.value = defaultCftts;
    } else {
      cfttsConfig.value = _cfttsConfigBox.values.first;
    }

    openAITtsConfigs.assignAll(_openAITtsConfigBox.values);
    await _normalizePersistedXiaomiMimoConfigs();
    _ensureOpenAITtsDefaultConsistency();

    await _flutterTts.setSpeechRate(speechRate.value);
    await _flutterTts.setPitch(pitch.value);
    await _flutterTts.setVolume(volume.value);

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
    debugPrint('TTS 设置已重新加载: 全局路由=${globalTtsRoute.value}');
  }

  Future<void> speak(
    String text, {
    double? rate,
    double? volume,
    double? pitch,
    String? featureKey,
  }) async {
    if (isSpeaking.value) {
      await stop();
    }

    final route = resolveTtsRoute(featureKey: featureKey);
    if (route == engineCftts && _isCfttsAvailable()) {
      await _speakCftts(text, rate: rate);
      return;
    }

    if (route.startsWith(openAITtsPrefix)) {
      final provider = getOpenAITtsConfigByRoute(route);
      if (provider != null && _isOpenAITtsAvailable(provider)) {
        await _speakOpenAITts(provider, text, rate: rate);
        return;
      }
    }

    await _flutterTts.setLanguage("zh-CN");

    if (rate != null || volume != null || pitch != null) {
      if (rate != null) await _flutterTts.setSpeechRate(rate);
      if (volume != null) await _flutterTts.setVolume(volume);
      if (pitch != null) await _flutterTts.setPitch(pitch);
    } else {
      await _applyGlobalSettings();
    }

    await _flutterTts.speak(text);
  }

  Future<void> prefetchCftts(String text, {String? featureKey}) async {
    final route = resolveTtsRoute(featureKey: featureKey);

    if (route == engineCftts && _isCfttsAvailable()) {
      await _getOrFetchCftts(text);
      return;
    }

    if (route.startsWith(openAITtsPrefix)) {
      final provider = getOpenAITtsConfigByRoute(route);
      if (provider != null && _isOpenAITtsAvailable(provider)) {
        await _getOrFetchOpenAITts(provider, text);
      }
    }
  }

  String resolveTtsRoute({String? featureKey}) {
    if (featureKey == null) {
      return globalTtsRoute.value;
    }

    final override = getFeatureTtsEngine(featureKey);
    if (override == engineGlobal) {
      return globalTtsRoute.value;
    }
    return _normalizeEngineRoute(override);
  }

  bool shouldUseAudioBasedPlayback({String? featureKey}) {
    final route = resolveTtsRoute(featureKey: featureKey);
    if (route == engineCftts) {
      return _isCfttsAvailable();
    }
    if (route.startsWith(openAITtsPrefix)) {
      final provider = getOpenAITtsConfigByRoute(route);
      return provider != null && _isOpenAITtsAvailable(provider);
    }
    return false;
  }

  bool _isCfttsAvailable() {
    return cfttsConfig.value != null &&
        cfttsConfig.value!.baseUrl.trim().isNotEmpty;
  }

  bool _isOpenAITtsAvailable(OpenAITtsConfig config) {
    return config.isEnabled &&
        config.baseUrl.trim().isNotEmpty &&
        config.apiKey.trim().isNotEmpty;
  }

  String _normalizeEngineRoute(String route) {
    if (route.isEmpty) return engineSystem;
    if (route == engineGlobal ||
        route == engineSystem ||
        route == engineCftts) {
      return route;
    }
    if (route.startsWith(openAITtsPrefix)) {
      return route;
    }
    return engineSystem;
  }

  String getGlobalTtsRoute() => globalTtsRoute.value;

  Future<void> setGlobalTtsRoute(String route) async {
    final normalized = _normalizeEngineRoute(route);
    globalTtsRoute.value = normalized;
    useCftts.value = normalized == engineCftts;
    await _settingsBox.put('tts_global_route', normalized);
    await _settingsBox.put('use_cftts', useCftts.value);
  }

  Future<void> setUseCftts(bool value) async {
    await setGlobalTtsRoute(value ? engineCftts : engineSystem);
  }

  String getFeatureTtsEngine(String featureKey) {
    final value =
        _settingsBox.get('tts_engine_$featureKey', defaultValue: engineGlobal);
    return _normalizeEngineRoute(value.toString()) == engineSystem &&
            value.toString() == engineGlobal
        ? engineGlobal
        : _normalizeLegacyOverride(value.toString());
  }

  String _normalizeLegacyOverride(String route) {
    if (route == engineGlobal ||
        route == engineSystem ||
        route == engineCftts) {
      return route;
    }
    if (route.startsWith(openAITtsPrefix)) {
      return route;
    }
    return engineGlobal;
  }

  Future<void> setFeatureTtsEngine(String featureKey, String engine) async {
    final normalized = _normalizeLegacyOverride(engine);
    await _settingsBox.put('tts_engine_$featureKey', normalized);
  }

  Future<File?> _getOrFetchCftts(String text) async {
    final cfg = cfttsConfig.value!;
    final cacheKey = _buildRemoteCacheKey(
      providerId: 'cftts',
      text: text,
      model: cfg.model,
      voice: cfg.voice,
      style: '',
      audioFormat: 'mp3',
      speed: cfg.speed,
    );

    final cacheFile = await _buildCfttsCacheFile(text);
    if (await cacheFile.exists()) {
      return cacheFile;
    }

    if (_remoteTtsFetchTasks.containsKey(cacheKey)) {
      return _remoteTtsFetchTasks[cacheKey];
    }

    final task = () async {
      try {
        final url =
            Uri.parse('${_trimTrailingSlash(cfg.baseUrl)}/v1/audio/speech');
        final headers = <String, String>{'Content-Type': 'application/json'};
        if (cfg.apiKey.isNotEmpty) {
          headers['Authorization'] = 'Bearer ${cfg.apiKey}';
        }

        final body = jsonEncode({
          'model': cfg.model,
          'input': text,
          'voice': cfg.voice,
          'speed': cfg.speed,
        });

        final response = await http.post(url, headers: headers, body: body);

        if (response.statusCode == 200) {
          await cacheFile.writeAsBytes(response.bodyBytes);
          return cacheFile;
        }
        debugPrint('CFTTS 请求失败: ${response.statusCode} - ${response.body}');
      } catch (e) {
        debugPrint('CFTTS 预取失败: $e');
      } finally {
        _remoteTtsFetchTasks.remove(cacheKey);
      }
      return null;
    }();

    _remoteTtsFetchTasks[cacheKey] = task;
    return task;
  }

  Future<File?> _getOrFetchOpenAITts(
      OpenAITtsConfig config, String text) async {
    final cacheKey = _buildRemoteCacheKey(
      providerId: config.id,
      text: text,
      model: _resolveOpenAITtsModel(config),
      voice: _resolveOpenAITtsVoice(config),
      style: config.selectedStylePreset,
      audioFormat: config.audioFormat,
    );

    final cacheFile = await _buildOpenAITtsCacheFile(config, text);
    if (await cacheFile.exists()) {
      return cacheFile;
    }

    if (_remoteTtsFetchTasks.containsKey(cacheKey)) {
      return _remoteTtsFetchTasks[cacheKey];
    }

    final task = () async {
      try {
        final bytes = await _requestOpenAITtsAudio(config, text);
        if (bytes == null || bytes.isEmpty) {
          return null;
        }
        await cacheFile.writeAsBytes(bytes, flush: true);
        return cacheFile;
      } catch (e) {
        debugPrint('OpenAI TTS 获取失败: $e');
      } finally {
        _remoteTtsFetchTasks.remove(cacheKey);
      }
      return null;
    }();

    _remoteTtsFetchTasks[cacheKey] = task;
    return task;
  }

  String _buildRemoteCacheKey({
    required String providerId,
    required String text,
    required String model,
    required String voice,
    required String style,
    required String audioFormat,
    double? speed,
  }) {
    final raw = [
      providerId,
      model,
      voice,
      style,
      audioFormat,
      speed ?? '',
      text
    ].join('|');
    final digest = md5.convert(utf8.encode(raw)).toString();
    return 'tts_cache_$digest';
  }

  Future<List<int>?> _requestOpenAITtsAudio(
      OpenAITtsConfig config, String text) async {
    final body = _buildOpenAITtsBody(config, text);
    final url = _buildOpenAITtsUrl(config);
    final headers = _buildOpenAITtsHeaders(config);

    final response = await http
        .post(url, headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      debugPrint('OpenAI TTS 请求失败: ${response.statusCode} - ${response.body}');
      return null;
    }

    final contentType = response.headers['content-type'] ?? '';
    if (contentType.contains('audio/')) {
      return response.bodyBytes;
    }

    final data = _parseResponseBody(response.body);
    return _extractAudioBytes(data);
  }

  Uri _buildOpenAITtsUrl(OpenAITtsConfig config) {
    final baseUrl = _trimTrailingSlash(config.baseUrl);
    if (config.providerType == 'xiaomi_mimo_v25') {
      return Uri.parse('$baseUrl/chat/completions');
    }
    return Uri.parse('$baseUrl/audio/speech');
  }

  Map<String, String> _buildOpenAITtsHeaders(OpenAITtsConfig config) {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (config.authType == 'api-key') {
      headers['api-key'] = config.apiKey;
    } else {
      headers['Authorization'] = 'Bearer ${config.apiKey}';
    }
    return headers;
  }

  Map<String, dynamic> _buildOpenAITtsBody(
      OpenAITtsConfig config, String text) {
    final model = _resolveOpenAITtsModel(config);
    final voice = _resolveOpenAITtsVoice(config);
    final styledText =
        _applyStylePresetToText(text, config.selectedStylePreset);

    if (config.providerType == 'xiaomi_mimo_v25') {
      return {
        'model': model,
        'modalities': ['text', 'audio'],
        'audio': {
          'voice': voice,
          'format': config.audioFormat,
        },
        'messages': [
          {
            'role': 'user',
            'content': _buildStyleInstruction(config.selectedStylePreset),
          },
          {
            'role': 'assistant',
            'content': text,
          }
        ],
        'stream': false,
      };
    }

    return {
      'model': model,
      'input': styledText,
      'voice': voice,
      'format': config.audioFormat,
    };
  }

  String _applyStylePresetToText(String text, String stylePreset) {
    switch (stylePreset) {
      case '自然':
        return '请用自然、清晰的语气朗读以下内容：$text';
      case '温柔':
        return '请用温柔、亲切、适合孩子的语气朗读以下内容：$text';
      case '开心':
        return '请用开心、活泼的语气朗读以下内容：$text';
      case '讲故事':
        return '请用富有故事感、适合儿童聆听的语气朗读以下内容：$text';
      case '默认':
      default:
        return text;
    }
  }

  String _buildStyleInstruction(String stylePreset) {
    switch (stylePreset) {
      case '自然':
        return '请用自然、清晰的语气朗读。';
      case '温柔':
        return '请用温柔、亲切、适合孩子的语气朗读。';
      case '开心':
        return '请用开心、活泼的语气朗读。';
      case '讲故事':
        return '请用富有故事感、适合儿童聆听的语气朗读。';
      case '默认':
      default:
        return '请直接将后续 assistant 消息内容转换为语音输出。';
    }
  }

  Map<String, dynamic> _parseResponseBody(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return <String, dynamic>{};

    try {
      return jsonDecode(trimmed) as Map<String, dynamic>;
    } catch (_) {}

    final lines = trimmed
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.startsWith('data:'));
    for (final line in lines.toList().reversed) {
      final chunk = line.substring(5).trim();
      if (chunk.isEmpty || chunk == '[DONE]') continue;
      try {
        return jsonDecode(chunk) as Map<String, dynamic>;
      } catch (_) {}
    }

    return <String, dynamic>{};
  }

  List<int>? _extractAudioBytes(Map<String, dynamic> data) {
    String? base64Audio;

    final choices = data['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map<String, dynamic>) {
        final message = first['message'];
        if (message is Map<String, dynamic>) {
          final audio = message['audio'];
          if (audio is Map<String, dynamic>) {
            base64Audio = audio['data']?.toString();
          }
        }
      }
    }

    base64Audio ??= data['audio']?['data']?.toString();
    base64Audio ??= data['data']?.toString();

    if (base64Audio == null || base64Audio.isEmpty) {
      return null;
    }

    try {
      return base64Decode(base64Audio);
    } catch (e) {
      debugPrint('base64 音频解析失败: $e');
      return null;
    }
  }

  String _audioExtension(String format) {
    switch (format.toLowerCase()) {
      case 'wav':
        return 'wav';
      case 'aac':
        return 'aac';
      case 'opus':
        return 'opus';
      case 'flac':
        return 'flac';
      case 'pcm':
        return 'pcm';
      case 'mp3':
      default:
        return 'mp3';
    }
  }

  String _trimTrailingSlash(String value) {
    var result = value.trim();
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  Future<void> clearCfttsCache() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final files = tempDir.listSync();
      for (var file in files) {
        if (file is File && file.path.contains('tts_cache_')) {
          await file.delete();
        }
      }
      debugPrint('TTS 缓存已清理');
    } catch (e) {
      debugPrint('清理 TTS 缓存失败: $e');
    }
  }

  Future<void> clearRemoteTtsCacheForText(
    String text, {
    String? featureKey,
  }) async {
    final route = resolveTtsRoute(featureKey: featureKey);

    if (route == engineCftts && _isCfttsAvailable()) {
      await _deleteCacheFile(await _buildCfttsCacheFile(text));
      return;
    }

    if (route.startsWith(openAITtsPrefix)) {
      final provider = getOpenAITtsConfigByRoute(route);
      if (provider != null && _isOpenAITtsAvailable(provider)) {
        await _deleteCacheFile(await _buildOpenAITtsCacheFile(provider, text));
      }
    }
  }

  Future<File> _buildCfttsCacheFile(String text) async {
    final cfg = cfttsConfig.value!;
    final cacheKey = _buildRemoteCacheKey(
      providerId: 'cftts',
      text: text,
      model: cfg.model,
      voice: cfg.voice,
      style: '',
      audioFormat: 'mp3',
      speed: cfg.speed,
    );
    final tempDir = await getTemporaryDirectory();
    return File('${tempDir.path}/$cacheKey.mp3');
  }

  Future<File> _buildOpenAITtsCacheFile(
      OpenAITtsConfig config, String text) async {
    final cacheKey = _buildRemoteCacheKey(
      providerId: config.id,
      text: text,
      model: _resolveOpenAITtsModel(config),
      voice: _resolveOpenAITtsVoice(config),
      style: config.selectedStylePreset,
      audioFormat: config.audioFormat,
    );
    final tempDir = await getTemporaryDirectory();
    final extension = _audioExtension(config.audioFormat);
    return File('${tempDir.path}/$cacheKey.$extension');
  }

  Future<void> _deleteCacheFile(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('删除 TTS 缓存失败: $e');
    }
  }

  String _resolveOpenAITtsModel(OpenAITtsConfig config) {
    return config.selectedModel.isNotEmpty
        ? config.selectedModel
        : (config.models.isNotEmpty ? config.models.first : '');
  }

  String _resolveOpenAITtsVoice(OpenAITtsConfig config) {
    if (config.providerType == 'xiaomi_mimo_v25') {
      final voice = config.selectedVoice.isNotEmpty
          ? config.selectedVoice
          : (config.voices.isNotEmpty ? config.voices.first : 'mimo_default');
      return OpenAITtsConfig.normalizeXiaomiMimoV25Voice(voice);
    }
    if (config.selectedVoice.isNotEmpty) {
      return config.selectedVoice;
    }
    if (config.voices.isNotEmpty) {
      return config.voices.first;
    }
    return 'alloy';
  }

  Future<void> _speakCftts(String text, {double? rate}) async {
    try {
      isSpeaking.value = true;
      final playFile = await _getOrFetchCftts(text);

      if (playFile == null) {
        isSpeaking.value = false;
        debugPrint('CFTTS 请求失败，无法播放');
        return;
      }

      await _audioPlayer.stop();
      await _audioPlayer.setFilePath(playFile.path);
      await _audioPlayer.seek(Duration.zero);
      await _audioPlayer.setSpeed(rate ?? 1.0);
      onStartCallback?.call();
      await _audioPlayer.play();
    } catch (e) {
      isSpeaking.value = false;
      debugPrint('CFTTS播放失败: $e');
    }
  }

  Future<void> _speakOpenAITts(
    OpenAITtsConfig config,
    String text, {
    double? rate,
  }) async {
    try {
      isSpeaking.value = true;
      final playFile = await _getOrFetchOpenAITts(config, text);
      if (playFile == null) {
        isSpeaking.value = false;
        debugPrint('OpenAI TTS 请求失败，无法播放');
        return;
      }

      await _audioPlayer.stop();
      await _audioPlayer.setFilePath(playFile.path);
      await _audioPlayer.seek(Duration.zero);
      await _audioPlayer.setSpeed(rate ?? 1.0);
      onStartCallback?.call();
      await _audioPlayer.play();
    } catch (e) {
      isSpeaking.value = false;
      debugPrint('OpenAI TTS 播放失败: $e');
    }
  }

  Future<void> _applyGlobalSettings() async {
    await _flutterTts.setSpeechRate(speechRate.value);
    await _flutterTts.setPitch(pitch.value);
    await _flutterTts.setVolume(volume.value);
  }

  Future<void> stop() async {
    try {
      await _audioPlayer.stop();
      await _flutterTts.stop();
    } catch (e) {
      debugPrint('TTS 停止失败: $e');
    }
    isSpeaking.value = false;
  }

  Future<void> setSpeechRate(double rate) async {
    speechRate.value = rate;
    await _flutterTts.setSpeechRate(rate);
    await _settingsBox.put('speech_rate', rate);
  }

  Future<void> setPitch(double value) async {
    pitch.value = value;
    await _flutterTts.setPitch(value);
    await _settingsBox.put('pitch', value);
  }

  Future<void> setVolume(double value) async {
    volume.value = value;
    await _flutterTts.setVolume(value);
    await _settingsBox.put('volume', value);
  }

  Future<void> setEngine(String engine) async {
    await _flutterTts.setEngine(engine);
    currentEngine.value = engine;
    await _settingsBox.put('tts_engine', engine);
    await _flutterTts.setSpeechRate(speechRate.value);
    await _flutterTts.setPitch(pitch.value);
    await _flutterTts.setVolume(volume.value);
  }

  Future<List<String>> fetchCfttsVoices() async {
    final cfg = cfttsConfig.value;
    if (cfg == null || cfg.baseUrl.isEmpty) return [];

    try {
      final url = Uri.parse('${_trimTrailingSlash(cfg.baseUrl)}/voices');
      final headers = <String, String>{};
      if (cfg.apiKey.isNotEmpty) {
        headers['Authorization'] = 'Bearer ${cfg.apiKey}';
      }

      final response = await http
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final dynamic data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data is List) {
          final List<String> voices = [];
          for (var item in data) {
            if (item is Map && item.containsKey('ShortName')) {
              voices.add(item['ShortName'].toString());
            } else if (item is String) {
              voices.add(item);
            }
          }
          if (voices.isNotEmpty) {
            return voices;
          }
        }
      }
      debugPrint(
          '获取 CFTTS 语音列表失败: HTTP ${response.statusCode} - ${response.body}');
    } catch (e) {
      debugPrint('获取 CFTTS 语音列表异常: $e');
    }
    return [];
  }

  Future<List<String>> fetchOpenAITtsModels(OpenAITtsConfig config) async {
    final baseUrl = _trimTrailingSlash(config.baseUrl);
    if (baseUrl.isEmpty || config.apiKey.trim().isEmpty) return [];

    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/models'),
            headers: _buildOpenAITtsHeaders(config),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint(
            '获取 OpenAI TTS 模型失败: ${response.statusCode} - ${response.body}');
        return [];
      }

      final body = _parseResponseBody(response.body);
      final data = body['data'];
      if (data is! List) return [];

      final models = data
          .map((item) {
            if (item is Map<String, dynamic>) {
              return item['id']?.toString() ?? '';
            }
            if (item is Map) {
              return item['id']?.toString() ?? '';
            }
            return '';
          })
          .where((item) => item.isNotEmpty)
          .toList();

      return models.cast<String>();
    } catch (e) {
      debugPrint('获取 OpenAI TTS 模型异常: $e');
      return [];
    }
  }

  Future<List<String>> fetchOpenAITtsVoices(OpenAITtsConfig config) async {
    final baseUrl = _trimTrailingSlash(config.baseUrl);
    if (baseUrl.isEmpty || config.apiKey.trim().isEmpty) return [];

    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/voices'),
            headers: _buildOpenAITtsHeaders(config),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint(
            '获取 OpenAI TTS 音色失败: ${response.statusCode} - ${response.body}');
        return [];
      }

      final body = _parseResponseBody(response.body);
      final data = body['data'] ?? body['voices'] ?? body['items'] ?? body;

      if (data is List) {
        final voices = data
            .map((item) {
              if (item is String) return item;
              if (item is Map<String, dynamic>) {
                return item['id']?.toString() ??
                    item['name']?.toString() ??
                    item['voice']?.toString() ??
                    '';
              }
              if (item is Map) {
                return item['id']?.toString() ??
                    item['name']?.toString() ??
                    item['voice']?.toString() ??
                    '';
              }
              return '';
            })
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList();
        return voices.cast<String>();
      }
    } catch (e) {
      debugPrint('获取 OpenAI TTS 音色异常: $e');
    }
    return [];
  }

  Future<void> updateCfttsConfig(CfttsConfig newConfig) async {
    if (_cfttsConfigBox.isEmpty) {
      await _cfttsConfigBox.add(newConfig);
    } else {
      final existingKey = _cfttsConfigBox.keys.first;
      await _cfttsConfigBox.put(existingKey, newConfig);
    }
    cfttsConfig.value = newConfig;
  }

  Future<void> addOpenAITtsConfig(OpenAITtsConfig config) async {
    if (config.isDefault) {
      await _setOpenAITtsDefaultFlag(config.id);
    }
    await _openAITtsConfigBox.put(config.id, config);
    openAITtsConfigs.assignAll(_openAITtsConfigBox.values);
  }

  Future<void> updateOpenAITtsConfig(OpenAITtsConfig config) async {
    if (config.isDefault) {
      await _setOpenAITtsDefaultFlag(config.id);
    }
    await _openAITtsConfigBox.put(config.id, config);
    openAITtsConfigs.assignAll(_openAITtsConfigBox.values);
  }

  Future<void> deleteOpenAITtsConfig(String id) async {
    await _openAITtsConfigBox.delete(id);
    openAITtsConfigs.assignAll(_openAITtsConfigBox.values);

    final route = globalTtsRoute.value;
    if (route == '$openAITtsPrefix$id') {
      await setGlobalTtsRoute(engineSystem);
    }

    final featureKeys = _settingsBox.keys
        .where((key) => key.toString().startsWith('tts_engine_'))
        .map((key) => key.toString())
        .toList();
    for (final key in featureKeys) {
      final value = _settingsBox.get(key);
      if (value == '$openAITtsPrefix$id') {
        await _settingsBox.put(key, engineGlobal);
      }
    }
  }

  Future<void> setDefaultOpenAITtsConfig(String id) async {
    await _setOpenAITtsDefaultFlag(id);
    openAITtsConfigs.assignAll(_openAITtsConfigBox.values);
  }

  Future<void> _setOpenAITtsDefaultFlag(String id) async {
    for (final config in _openAITtsConfigBox.values) {
      final shouldDefault = config.id == id;
      if (config.isDefault != shouldDefault) {
        config.isDefault = shouldDefault;
        await config.save();
      }
    }
  }

  Future<void> _normalizePersistedXiaomiMimoConfigs() async {
    var changed = false;
    for (final config in _openAITtsConfigBox.values) {
      if (config.providerType != 'xiaomi_mimo_v25') continue;

      final normalizedVoice =
          OpenAITtsConfig.normalizeXiaomiMimoV25Voice(config.selectedVoice);
      final expectedVoices = OpenAITtsConfig.xiaomiMimoV25PresetVoices;

      if (config.selectedVoice != normalizedVoice ||
          config.voices.length != expectedVoices.length ||
          !config.voices.every(expectedVoices.contains)) {
        config.selectedVoice = normalizedVoice;
        config.voices = expectedVoices;
        await config.save();
        changed = true;
      }
    }
    if (changed) {
      openAITtsConfigs.assignAll(_openAITtsConfigBox.values);
    }
  }

  void _ensureOpenAITtsDefaultConsistency() {
    final defaults =
        openAITtsConfigs.where((config) => config.isDefault).toList();
    if (defaults.length <= 1) return;

    for (var i = 1; i < defaults.length; i++) {
      defaults[i].isDefault = false;
      defaults[i].save();
    }
    openAITtsConfigs.refresh();
  }

  OpenAITtsConfig? getOpenAITtsConfigById(String id) {
    for (final config in openAITtsConfigs) {
      if (config.id == id) return config;
    }
    return null;
  }

  OpenAITtsConfig? getOpenAITtsConfigByRoute(String route) {
    if (!route.startsWith(openAITtsPrefix)) return null;
    final id = route.substring(openAITtsPrefix.length);
    return getOpenAITtsConfigById(id);
  }

  List<Map<String, String>> getTtsRouteOptions() {
    final options = <Map<String, String>>[
      {'value': engineSystem, 'label': '系统 TTS'},
      {'value': engineCftts, 'label': '自建 CFTTS'},
    ];

    for (final config in openAITtsConfigs.where((item) => item.isEnabled)) {
      options.add({
        'value': '$openAITtsPrefix${config.id}',
        'label': config.name,
      });
    }

    return options;
  }

  String getTtsRouteDisplayName(String route, {bool withGlobalPrefix = false}) {
    String label;
    if (route == engineGlobal) {
      label = '跟随全局设置';
    } else if (route == engineSystem) {
      label = '系统 TTS';
    } else if (route == engineCftts) {
      label = '自建 CFTTS';
    } else if (route.startsWith(openAITtsPrefix)) {
      label = getOpenAITtsConfigByRoute(route)?.name ?? '自定义 OpenAI TTS';
    } else {
      label = '系统 TTS';
    }
    return withGlobalPrefix ? '使用$label' : label;
  }

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

  @override
  void onClose() {
    _flutterTts.stop();
    _audioPlayer.dispose();
    super.onClose();
  }
}
