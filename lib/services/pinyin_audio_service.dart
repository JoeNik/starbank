import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../widgets/toast_utils.dart';

class PinyinAudioService extends GetxService {
  static const String defaultBaseUrl =
      'https://raw.githubusercontent.com/hugolpz/audio-cmn/master/18k-abr/syllabs';
  static const String _baseUrlKey = 'audio_base_url';
  static const String _cacheLimitKey = 'cache_limit';
  static const String _cacheIndexFileName = 'cache_index.json';
  static const int defaultCacheLimit = 1000;

  late final AudioPlayer _audioPlayer;
  late final Box _settingsBox;
  late final Directory _cacheDir;

  final RxBool isPlaying = false.obs;
  final RxBool isLoading = false.obs;
  final RxString currentAudioKey = ''.obs;
  final RxString audioBaseUrl = defaultBaseUrl.obs;
  final RxInt cacheLimit = defaultCacheLimit.obs;
  final RxInt cachedCount = 0.obs;

  final Map<String, int> _cacheIndex = {};

  Future<PinyinAudioService> init() async {
    _audioPlayer = AudioPlayer();
    _settingsBox = await Hive.openBox('pinyin_audio_settings');
    audioBaseUrl.value =
        _settingsBox.get(_baseUrlKey, defaultValue: defaultBaseUrl).toString();
    cacheLimit.value = _settingsBox.get(_cacheLimitKey,
        defaultValue: defaultCacheLimit) as int;

    final supportDir = await getApplicationSupportDirectory();
    _cacheDir = Directory('${supportDir.path}/pinyin_audio_cache');
    if (!await _cacheDir.exists()) {
      await _cacheDir.create(recursive: true);
    }
    await _loadCacheIndex();
    await _trimCacheIfNeeded();

    _audioPlayer.playerStateStream.listen((state) {
      isPlaying.value = state.playing;
      if (state.processingState == ProcessingState.completed) {
        isPlaying.value = false;
      }
    });
    return this;
  }

  Uri buildAudioUri(String audioKey) {
    return Uri.parse(
        '${_trimTrailingSlash(audioBaseUrl.value)}/cmn-$audioKey.mp3');
  }

  Future<void> play(String audioKey) async {
    if (audioKey.trim().isEmpty) return;

    try {
      isLoading.value = true;
      currentAudioKey.value = audioKey;

      final audioFile = await _getOrFetchAudio(audioKey);
      if (audioFile == null) {
        return;
      }

      await _audioPlayer.stop();
      await _audioPlayer.setFilePath(audioFile.path);
      await _audioPlayer.seek(Duration.zero);
      await _audioPlayer.play();
    } catch (e) {
      debugPrint('拼音音频播放失败: $e');
      ToastUtils.showError('拼音音频加载失败，请检查网络后再试');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> updateSettings({
    required String baseUrl,
    required int maxCachedAudios,
  }) async {
    final normalizedLimit = maxCachedAudios.clamp(20, 5000);
    audioBaseUrl.value =
        baseUrl.trim().isEmpty ? defaultBaseUrl : _trimTrailingSlash(baseUrl);
    cacheLimit.value = normalizedLimit;
    await _settingsBox.put(_baseUrlKey, audioBaseUrl.value);
    await _settingsBox.put(_cacheLimitKey, cacheLimit.value);
    await _trimCacheIfNeeded();
  }

  Future<void> clearCache() async {
    try {
      if (await _cacheDir.exists()) {
        await for (final entity in _cacheDir.list()) {
          if (entity is File && entity.path.endsWith('.mp3')) {
            await entity.delete();
          }
        }
      }
      _cacheIndex.clear();
      await _saveCacheIndex();
      cachedCount.value = 0;
    } catch (e) {
      debugPrint('清理拼音音频缓存失败: $e');
      ToastUtils.showError('清理缓存失败: $e');
    }
  }

  Future<void> replay() async {
    if (currentAudioKey.value.isEmpty) return;
    await play(currentAudioKey.value);
  }

  Future<void> stop() async {
    try {
      await _audioPlayer.stop();
    } catch (e) {
      debugPrint('拼音音频停止失败: $e');
    }
    isPlaying.value = false;
  }

  @override
  void onClose() {
    _audioPlayer.dispose();
    super.onClose();
  }

  Future<File?> _getOrFetchAudio(String audioKey) async {
    final cacheFile = _cacheFileFor(audioKey);
    if (await cacheFile.exists()) {
      await _touchCache(audioKey);
      return cacheFile;
    }

    final response = await http
        .get(buildAudioUri(audioKey))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
      debugPrint('拼音音频请求失败: ${response.statusCode} ${response.body}');
      ToastUtils.showError('没有找到这个拼音音频，请稍后再试');
      return null;
    }

    await cacheFile.writeAsBytes(response.bodyBytes, flush: true);
    await _touchCache(audioKey);
    await _trimCacheIfNeeded();
    return cacheFile;
  }

  File _cacheFileFor(String audioKey) {
    final safeName = audioKey.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return File('${_cacheDir.path}/cmn-$safeName.mp3');
  }

  Future<File> get _cacheIndexFile async =>
      File('${_cacheDir.path}/$_cacheIndexFileName');

  Future<void> _loadCacheIndex() async {
    try {
      final file = await _cacheIndexFile;
      if (!await file.exists()) {
        cachedCount.value = await _countCacheFiles();
        return;
      }
      final data = jsonDecode(await file.readAsString());
      if (data is Map) {
        _cacheIndex
          ..clear()
          ..addAll(data.map(
            (key, value) => MapEntry(key.toString(), value as int),
          ));
      }
      cachedCount.value = await _countCacheFiles();
    } catch (e) {
      debugPrint('读取拼音缓存索引失败: $e');
      _cacheIndex.clear();
      cachedCount.value = await _countCacheFiles();
    }
  }

  Future<void> _saveCacheIndex() async {
    final file = await _cacheIndexFile;
    await file.writeAsString(jsonEncode(_cacheIndex), flush: true);
  }

  Future<void> _touchCache(String audioKey) async {
    _cacheIndex[audioKey] = DateTime.now().millisecondsSinceEpoch;
    await _saveCacheIndex();
    cachedCount.value = await _countCacheFiles();
  }

  Future<void> _trimCacheIfNeeded() async {
    final limit = cacheLimit.value;
    if (limit <= 0 || _cacheIndex.length <= limit) {
      cachedCount.value = await _countCacheFiles();
      return;
    }

    final entries = _cacheIndex.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final removeCount = entries.length - limit;
    for (final entry in entries.take(removeCount)) {
      final file = _cacheFileFor(entry.key);
      if (await file.exists()) {
        await file.delete();
      }
      _cacheIndex.remove(entry.key);
    }
    await _saveCacheIndex();
    cachedCount.value = await _countCacheFiles();
  }

  Future<int> _countCacheFiles() async {
    if (!await _cacheDir.exists()) return 0;
    var count = 0;
    await for (final entity in _cacheDir.list()) {
      if (entity is File && entity.path.endsWith('.mp3')) {
        count++;
      }
    }
    return count;
  }

  String _trimTrailingSlash(String value) {
    var result = value.trim();
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}
