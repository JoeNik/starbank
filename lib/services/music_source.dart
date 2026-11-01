import 'package:get/get.dart';
import '../models/music/music_track.dart';
import 'storage_service.dart';

/// 音乐源抽象接口:所有第三方音乐 API(搜索 + 解析)统一实现此接口,
/// 播放控制器依赖抽象而非具体服务,便于多源路由与降级。
abstract class MusicSource {
  /// 源标识(用于持久化与路由,如 'chksz' / 'tunehub')
  String get id;

  /// 显示名
  String get displayName;

  /// 是否已配置可用(有密钥/服务地址)
  bool get isConfigured;

  /// 关键词搜索歌曲,失败时返回空列表
  Future<List<MusicTrack>> searchMusic(
    String keyword, {
    String platform,
    int page,
  });

  /// 解析歌曲播放地址。
  /// 返回约定 Map:{url, cover?, lyrics?, level?, br?};失败返回空 Map。
  Future<Map<String, dynamic>> parseTrack(
    String platform,
    String id, {
    String? level,
  });

  /// 最近一次请求的调试信息(供 UI 排错展示)
  String get lastDebugInfo;
}

/// 音源注册中心:管理可用音源与当前激活音源(持久化于 settings box)。
class MusicSourceRegistry extends GetxService {
  final StorageService _storage = Get.find<StorageService>();

  static const String _storageKey = 'music_source';

  final List<MusicSource> _sources = [];
  final RxString activeSourceId = ''.obs;

  /// 注册音源(顺序即设置页展示顺序)
  void register(MusicSource source) {
    _sources.add(source);
  }

  List<MusicSource> get sources => List.unmodifiable(_sources);

  MusicSource? byId(String? id) {
    for (final s in _sources) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// 当前激活音源;未匹配到已保存 ID 时回退第一个已注册源
  MusicSource? get active {
    final bySaved = byId(activeSourceId.value);
    if (bySaved != null) return bySaved;
    return _sources.isEmpty ? null : _sources.first;
  }

  /// 启动时恢复持久化的音源选择;无记录或记录失效时默认 ChKSz
  void restore() {
    if (_sources.isEmpty) return;
    final saved = _storage.getValue(_storageKey);
    if (saved != null && byId(saved) != null) {
      activeSourceId.value = saved;
      return;
    }
    activeSourceId.value =
        byId('chksz') != null ? 'chksz' : _sources.first.id;
  }

  void setActive(String id) {
    if (byId(id) == null) return;
    activeSourceId.value = id;
    _storage.saveValue(_storageKey, id);
  }
}
