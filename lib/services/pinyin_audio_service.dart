import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../widgets/toast_utils.dart';

class PinyinAudioService extends GetxService {
  static const String defaultBaseUrl =
      'https://raw.githubusercontent.com/hugolpz/audio-cmn/master/18k-abr/syllabs';
  /// HSK 单字音频（同仓库）。部分 syllabs 录音送气/音色偏差大时回退到这里。
  static const String defaultHskBaseUrl =
      'https://raw.githubusercontent.com/hugolpz/audio-cmn/master/18k-abr/hsk';
  static const String _baseUrlKey = 'audio_base_url';
  static const String _cacheLimitKey = 'cache_limit';
  static const String _cacheIndexFileName = 'cache_index.json';
  static const int defaultCacheLimit = 1000;

  /// 内置纠正音频（打包进 APK）。远程 syllabs 的 chi1 送气不足，听感像「知」。
  /// 资源来自 audio-cmn 64k HSK 单字（吃/池/尺）与 64k syllabs chi4。
  static const Map<String, String> _bundledAssetOverrides = {
    'chi1': 'assets/audio/pinyin/chi1.mp3',
    'chi2': 'assets/audio/pinyin/chi2.mp3',
    'chi3': 'assets/audio/pinyin/chi3.mp3',
    'chi4': 'assets/audio/pinyin/chi4.mp3',
  };

  /// 远程 HSK 单字备选（内置资源缺失/损坏时用；永不回退到错误的 syllabs chi1）。
  static const Map<String, List<String>> _hskCharCandidates = {
    'chi1': ['吃'],
    'chi2': ['池', '迟'],
    'chi3': ['尺'],
  };

  /// 这些 key 的远程 syllabs 录音已知不可用，禁止作为兜底。
  static const Set<String> _blockRemoteSyllabs = {
    'chi1',
  };

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
  int _playRunId = 0;

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
    await _purgeBadLegacyChiCache();
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
    final key = audioKey.trim();
    final chars = _hskCharCandidates[key];
    if (chars != null && chars.isNotEmpty) {
      return _hskCharUri(chars.first);
    }
    return Uri.parse(
        '${_trimTrailingSlash(audioBaseUrl.value)}/cmn-$key.mp3');
  }

  Future<void> play(String audioKey) async {
    if (audioKey.trim().isEmpty) return;

    final runId = ++_playRunId;
    try {
      isLoading.value = true;
      currentAudioKey.value = audioKey;

      final audioFile = await _getOrFetchAudio(audioKey);
      if (audioFile == null) {
        return;
      }

      await _audioPlayer.stop();
      if (runId != _playRunId) return;
      await _audioPlayer.setFilePath(audioFile.path);
      await _audioPlayer.seek(Duration.zero);
      if (runId != _playRunId) return;
      await _audioPlayer.play();
    } catch (e) {
      debugPrint('拼音音频播放失败: $e');
      if (runId == _playRunId) {
        ToastUtils.showError('拼音音频加载失败，请检查网络后再试');
      }
    } finally {
      if (runId == _playRunId) {
        isLoading.value = false;
      }
    }
  }

  Future<void> playSequence(
    List<String> audioKeys, {
    Duration gap = const Duration(milliseconds: 180),
  }) async {
    if (audioKeys.isEmpty) return;

    final runId = ++_playRunId;
    try {
      isLoading.value = true;
      await _audioPlayer.stop();

      for (final audioKey in audioKeys) {
        if (runId != _playRunId) return;
        if (audioKey.trim().isEmpty) continue;
        currentAudioKey.value = audioKey;
        final audioFile = await _getOrFetchAudio(audioKey);
        if (audioFile == null) {
          continue;
        }
        if (runId != _playRunId) return;
        await _playFileToEnd(audioFile, runId: runId);
        if (runId != _playRunId) return;
        if (gap.inMilliseconds > 0) {
          await Future.delayed(gap);
        }
      }
    } catch (e) {
      debugPrint('拼音串读播放失败: $e');
      if (runId == _playRunId) {
        ToastUtils.showError('拼音串读失败，请稍后再试');
      }
    } finally {
      if (runId == _playRunId) {
        isLoading.value = false;
      }
    }
  }

  Future<PinyinCacheWarmupResult> cacheAudioKeys(
    Iterable<String> audioKeys, {
    bool forceRefresh = false,
    void Function(int done, int total)? onProgress,
  }) async {
    final uniqueKeys = audioKeys
        .map((key) => key.trim())
        .where((key) => key.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    var done = 0;
    final failedKeys = <String>[];
    onProgress?.call(done, uniqueKeys.length);

    for (final audioKey in uniqueKeys) {
      try {
        final audioFile = await _getOrFetchAudio(
          audioKey,
          forceRefresh: forceRefresh,
          showToastOnMissing: false,
        );
        if (audioFile == null) {
          failedKeys.add(audioKey);
        }
      } catch (e) {
        debugPrint('预缓存拼音音频失败 $audioKey: $e');
        failedKeys.add(audioKey);
      } finally {
        done++;
        onProgress?.call(done, uniqueKeys.length);
      }
    }

    return PinyinCacheWarmupResult(
      total: uniqueKeys.length,
      failedKeys: failedKeys,
    );
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
    _playRunId++;
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

  Future<void> _playFileToEnd(File audioFile, {required int runId}) async {
    await _audioPlayer.setFilePath(audioFile.path);
    await _audioPlayer.seek(Duration.zero);
    if (runId != _playRunId) return;
    final completed = _audioPlayer.processingStateStream.firstWhere(
      (state) =>
          state == ProcessingState.completed || state == ProcessingState.idle,
    );
    await _audioPlayer.play();
    await completed.timeout(
      const Duration(seconds: 8),
      onTimeout: () => ProcessingState.completed,
    );
  }

  Future<File?> _getOrFetchAudio(
    String audioKey, {
    bool forceRefresh = false,
    bool showToastOnMissing = true,
  }) async {
    final key = audioKey.trim();
    final cacheKey = _cacheKeyFor(key);
    final cacheFile = _cacheFileFor(cacheKey);

    if (forceRefresh) {
      await _deleteCacheEntry(cacheKey);
      // 旧版无后缀 / hsk_v1 缓存一并清掉
      await _deleteCacheEntry(key);
      await _deleteCacheEntry('${key}_hsk_v1');
    }

    if (await cacheFile.exists()) {
      await _touchCache(cacheKey);
      return cacheFile;
    }

    // 1) 内置纠正音频（离线可用，不依赖 GitHub）
    final bundled = await _materializeBundledAsset(key);
    if (bundled != null) {
      return bundled;
    }

    // 2) 远程 HSK 单字 /（非屏蔽的）syllabs
    http.Response? response;
    Object? lastError;
    for (final uri in _candidateRemoteUris(key)) {
      try {
        final res = await http.get(uri).timeout(const Duration(seconds: 20));
        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
          response = res;
          debugPrint('拼音音频命中: $key <- $uri');
          break;
        }
        debugPrint('拼音音频未命中 ${res.statusCode}: $uri');
      } catch (e) {
        lastError = e;
        debugPrint('拼音音频请求异常 $uri: $e');
      }
    }

    if (response == null) {
      debugPrint('拼音音频全部失败 key=$key lastError=$lastError');
      if (showToastOnMissing) {
        ToastUtils.showError('没有找到这个拼音音频，请稍后再试');
      }
      return null;
    }

    await cacheFile.writeAsBytes(response.bodyBytes, flush: true);
    await _touchCache(cacheKey);
    await _trimCacheIfNeeded();
    return cacheFile;
  }

  /// 把 APK 内纠正音频拷到缓存目录，供 just_audio 以文件路径播放。
  Future<File?> _materializeBundledAsset(String audioKey) async {
    final assetPath = _bundledAssetOverrides[audioKey];
    if (assetPath == null) return null;

    final cacheKey = _cacheKeyFor(audioKey);
    final cacheFile = _cacheFileFor(cacheKey);
    try {
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();
      if (bytes.isEmpty) return null;
      await cacheFile.writeAsBytes(bytes, flush: true);
      await _touchCache(cacheKey);
      debugPrint('拼音音频使用内置资源: $audioKey <- $assetPath');
      return cacheFile;
    } catch (e) {
      debugPrint('加载内置拼音音频失败 $assetPath: $e');
      return null;
    }
  }

  List<Uri> _candidateRemoteUris(String audioKey) {
    final key = audioKey.trim();
    final uris = <Uri>[];

    // 优先 64k HSK（送气更清晰），再 18k HSK
    final chars = _hskCharCandidates[key] ?? const <String>[];
    for (final quality in const ['64k', '18k-abr']) {
      for (final hanzi in chars) {
        uris.add(_hskCharUriForQuality(hanzi, quality));
      }
    }

    // jsDelivr 镜像（国内 GitHub raw 常慢/失败）
    for (final hanzi in chars) {
      final enc = Uri.encodeComponent(hanzi);
      uris.add(Uri.parse(
          'https://cdn.jsdelivr.net/gh/hugolpz/audio-cmn@master/64k/hsk/cmn-$enc.mp3'));
      uris.add(Uri.parse(
          'https://cdn.jsdelivr.net/gh/hugolpz/audio-cmn@master/18k-abr/hsk/cmn-$enc.mp3'));
    }

    // 普通音节：syllabs 兜底（chi1 等屏蔽项除外）
    if (!_blockRemoteSyllabs.contains(key)) {
      uris.add(Uri.parse(
          '${_trimTrailingSlash(audioBaseUrl.value)}/cmn-$key.mp3'));
      // 同品质 64k syllabs
      final syllabs64 = _syllabsUrlForQuality('64k');
      uris.add(Uri.parse('$syllabs64/cmn-$key.mp3'));
    }

    return uris;
  }

  Uri _hskCharUri(String hanzi) {
    final base = _hskBaseUrlFromSyllabs(audioBaseUrl.value);
    return Uri.parse('$base/cmn-${Uri.encodeComponent(hanzi)}.mp3');
  }

  Uri _hskCharUriForQuality(String hanzi, String quality) {
    return Uri.parse(
      'https://raw.githubusercontent.com/hugolpz/audio-cmn/master/'
      '$quality/hsk/cmn-${Uri.encodeComponent(hanzi)}.mp3',
    );
  }

  String _syllabsUrlForQuality(String quality) {
    return 'https://raw.githubusercontent.com/hugolpz/audio-cmn/master/'
        '$quality/syllabs';
  }

  /// 用户若把 baseUrl 改成 64k/24k 的 syllabs，HSK 覆盖也跟同品质目录。
  String _hskBaseUrlFromSyllabs(String syllabsUrl) {
    final normalized = _trimTrailingSlash(syllabsUrl);
    if (normalized.contains('/syllabs')) {
      return normalized.replaceFirst(RegExp(r'/syllabs$'), '/hsk');
    }
    return defaultHskBaseUrl;
  }

  /// 内置/纠正音频使用独立缓存名，避免沿用错误的旧 syllabs 文件。
  String _cacheKeyFor(String audioKey) {
    if (_bundledAssetOverrides.containsKey(audioKey) ||
        _hskCharCandidates.containsKey(audioKey)) {
      return '${audioKey}_fix_v2';
    }
    return audioKey;
  }

  Future<void> _purgeBadLegacyChiCache() async {
    // 启动时清掉已知错误的 chi 旧缓存，强制下次走内置纠正音。
    const stale = [
      'chi1',
      'chi2',
      'chi3',
      'chi4',
      'chi1_hsk_v1',
      'chi2_hsk_v1',
      'chi3_hsk_v1',
      'chi4_hsk_v1',
    ];
    var changed = false;
    for (final key in stale) {
      final file = _cacheFileFor(key);
      if (await file.exists()) {
        try {
          await file.delete();
          changed = true;
        } catch (_) {}
      }
      if (_cacheIndex.remove(key) != null) changed = true;
    }
    if (changed) {
      await _saveCacheIndex();
      cachedCount.value = await _countCacheFiles();
      debugPrint('已清理旧版 chi 拼音缓存，将使用内置纠正音频');
    }
  }

  Future<void> _deleteCacheEntry(String cacheKey) async {
    final file = _cacheFileFor(cacheKey);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
    _cacheIndex.remove(cacheKey);
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

class PinyinCacheWarmupResult {
  final int total;
  final List<String> failedKeys;

  const PinyinCacheWarmupResult({
    required this.total,
    required this.failedKeys,
  });

  int get successCount => total - failedKeys.length;
  bool get hasFailures => failedKeys.isNotEmpty;
}
