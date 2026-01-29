import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:hive/hive.dart';

/// 全局 TTS 语音服务
/// 使用 GetxService 确保全局单例，所有页面共享同一个 TTS 实例
class TtsService extends GetxService {
  late FlutterTts _flutterTts;
  late Box _settingsBox;

  // 可调参数
  final RxDouble speechRate = 0.5.obs;
  final RxDouble pitch = 1.0.obs;
  final RxDouble volume = 1.0.obs;

  // 引擎
  final RxString currentEngine = ''.obs;
  final RxList<String> engines = <String>[].obs;

  // 状态
  final RxBool isSpeaking = false.obs;
  final RxBool isInitialized = false.obs;

  /// 初始化服务
  Future<TtsService> init() async {
    _flutterTts = FlutterTts();
    _settingsBox = await Hive.openBox('tts_settings');

    // 加载保存的设置
    await _loadSettings();

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
        }
      } catch (e) {
        debugPrint('获取引擎列表失败: $e');
      }
    }

    // 监听播放状态
    _flutterTts.setStartHandler(() => isSpeaking.value = true);
    _flutterTts.setCompletionHandler(() => isSpeaking.value = false);
    _flutterTts.setCancelHandler(() => isSpeaking.value = false);
    _flutterTts.setErrorHandler((msg) {
      isSpeaking.value = false;
      debugPrint('TTS Error: $msg');
      // 尝试重置
      if (msg.toString().contains('not bound')) {
        _resetTts();
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
      {double? rate, double? volume, double? pitch}) async {
    if (isSpeaking.value) {
      await stop();
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

  /// 在开始播放前应用全局设置
  Future<void> _applyGlobalSettings() async {
    await _flutterTts.setSpeechRate(speechRate.value);
    await _flutterTts.setPitch(pitch.value);
    await _flutterTts.setVolume(volume.value);
  }

  /// 停止播放
  Future<void> stop() async {
    await _flutterTts.stop();
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

  @override
  void onClose() {
    _flutterTts.stop();
    super.onClose();
  }
}
