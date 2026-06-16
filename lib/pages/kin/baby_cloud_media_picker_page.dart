import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import '../../controllers/user_controller.dart';
import '../../services/baby_cloud_service.dart';
import '../../widgets/toast_utils.dart';
import 'baby_cloud_entry_edit_page.dart';
import 'baby_cloud_source_page.dart';

class BabyCloudMediaPickerPage extends StatefulWidget {
  const BabyCloudMediaPickerPage({super.key});

  @override
  State<BabyCloudMediaPickerPage> createState() =>
      _BabyCloudMediaPickerPageState();
}

class _BabyCloudMediaPickerPageState extends State<BabyCloudMediaPickerPage> {
  static const _pageSize = 60;
  static const _thumbnailSize = ThumbnailSize.square(180);

  final _cloud = Get.find<BabyCloudService>();
  final _user = Get.find<UserController>();
  final _assets = <AssetEntity>[];
  final _selected = <String>{};
  final _uploadedAssetIds = <String>{};
  final _hashCache = <String, String>{};
  final _remoteHashes = <String>{};
  final _warmingAssetIds = <String>{};
  final _checkingAssetIds = <String>{};

  AssetPathEntity? _path;
  int _page = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _queueing = false;
  bool _closing = false;
  String? _blockedMessage;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _closing = true;
    super.dispose();
  }

  Future<void> _init() async {
    if (!Platform.isAndroid) {
      _safeSetState(() {
        _blockedMessage = '自定义媒体浏览器第一版仅支持 Android';
        _loading = false;
      });
      return;
    }
    if (!_cloud.hasUsableCurrentSource) {
      _safeSetState(() {
        _blockedMessage = _cloud.currentSourceSetupMessage;
        _loading = false;
      });
      return;
    }

    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth) {
      _safeSetState(() {
        _blockedMessage = '请允许访问照片和视频后再选择';
        _loading = false;
      });
      return;
    }

    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      onlyAll: true,
      filterOption: FilterOptionGroup(
        orders: const [
          OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
      ),
    );
    if (paths.isEmpty) {
      _safeSetState(() => _loading = false);
      return;
    }

    final babyId = _user.currentBaby.value?.id;
    if (babyId != null) {
      _remoteHashes.addAll(
        _cloud.mediaForBaby(babyId, includeDeleted: false).map((m) => m.sha256),
      );
    }
    _path = paths.first;
    await _loadMore();
    _safeSetState(() => _loading = false);
  }

  Future<void> _loadMore() async {
    if (_path == null || _loadingMore || !_hasMore) return;
    _loadingMore = true;
    final next = await _path!.getAssetListPaged(page: _page, size: _pageSize);
    _page++;
    _assets.addAll(next);
    _assets.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));
    _hasMore = next.length == _pageSize;
    _loadingMore = false;
    _safeSetState(() {});

    // 优化：加载第一页时预检测更多图片，后续页面只检测可见部分
    final warmupCount = _page == 1 ? 40 : 18;
    final visibleWarmups = next.take(warmupCount).toList();
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 200))
          .then((_) => _warmUploadedMarks(visibleWarmups)),
    );
  }

  Future<void> _warmUploadedMarks(List<AssetEntity> assets) async {
    if (_remoteHashes.isEmpty) return;
    for (final asset in assets) {
      if (!mounted || _closing) return;
      if (_hashCache.containsKey(asset.id) ||
          _warmingAssetIds.contains(asset.id)) {
        continue;
      }
      _warmingAssetIds.add(asset.id);
      try {
        final hash = await _hashAsset(asset);
        if (hash == null) continue;
        if (_remoteHashes.contains(hash)) {
          _uploadedAssetIds.add(asset.id);
          _safeSetState(() {});
        }
      } catch (_) {
        // Ignore files the system gallery cannot expose.
      } finally {
        _warmingAssetIds.remove(asset.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_blockedMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('选择照片/视频')),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(28.w),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_outlined,
                    size: 58.sp, color: Colors.grey.shade400),
                SizedBox(height: 14.h),
                Text(
                  _blockedMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15.sp),
                ),
                if (Platform.isAndroid) ...[
                  SizedBox(height: 18.h),
                  ElevatedButton.icon(
                    onPressed: () => Get.off(() => const BabyCloudSourcePage()),
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('配置亲宝宝数据源'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('选择照片/视频'),
        actions: [
          TextButton(
            onPressed: () {
              if (_queueing) {
                ToastUtils.showInfo('正在加入上传队列，请稍等');
                return;
              }
              if (_selected.isEmpty) {
                ToastUtils.showInfo('请先选择要上传的照片或视频');
                return;
              }
              _queueSelected();
            },
            child: Text('上传 ${_selected.length}'),
          ),
        ],
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.extentAfter < 900) {
            unawaited(_loadMore());
          }
          return false;
        },
        child: GridView.builder(
          padding: EdgeInsets.all(4.w),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 4.w,
            crossAxisSpacing: 4.w,
          ),
          itemCount: _assets.length + (_hasMore || _loadingMore ? 1 : 0),
          itemBuilder: (_, index) {
            if (index >= _assets.length) {
              return const Center(child: CircularProgressIndicator());
            }
            final asset = _assets[index];
            final uploaded = _uploadedAssetIds.contains(asset.id);
            final checking = _checkingAssetIds.contains(asset.id);
            final selected = _selected.contains(asset.id);
            return _AssetTile(
              asset: asset,
              thumbnailSize: _thumbnailSize,
              uploaded: uploaded,
              checking: checking,
              selected: selected,
              onTap: () => _toggleAssetSelection(asset),
              onPreview: () => _openPreview(index),
            );
          },
        ),
      ),
    );
  }

  void _openPreview(int index) {
    Get.to(
      () => _AssetPreviewPage(
        assets: _assets,
        initialIndex: index,
        selectedIds: _selected,
        uploadedIds: _uploadedAssetIds,
        checkingIds: _checkingAssetIds,
        onToggleSelection: _toggleAssetSelection,
      ),
    );
  }

  Future<void> _queueSelected() async {
    if (_queueing) {
      ToastUtils.showInfo('正在加入上传队列，请稍等');
      return;
    }
    final baby = _user.currentBaby.value;
    if (baby == null) {
      ToastUtils.showWarning('请先在主页选择宝宝');
      return;
    }
    if (!_cloud.hasUsableCurrentSource) {
      ToastUtils.showWarning(_cloud.currentSourceSetupMessage);
      return;
    }

    final selectedAssets =
        _assets.where((asset) => _selected.contains(asset.id)).toList();
    if (selectedAssets.isEmpty) {
      ToastUtils.showInfo('请先选择要上传的照片或视频');
      return;
    }

    _queueing = true;
    _safeSetState(() {});
    final readyAssets = <AssetEntity>[];
    var duplicateCount = 0;
    for (final asset in selectedAssets) {
      final hash = await _hashAsset(asset, markChecking: true);
      if (hash != null && _remoteHashes.contains(hash)) {
        duplicateCount++;
        _uploadedAssetIds.add(asset.id);
        _selected.remove(asset.id);
      } else {
        readyAssets.add(asset);
      }
    }
    if (duplicateCount > 0) {
      ToastUtils.showInfo('已过滤 $duplicateCount 个已上传文件');
    }
    if (readyAssets.isEmpty) {
      _queueing = false;
      _safeSetState(() {});
      return;
    }
    _closing = true;
    Get.off(() => BabyCloudEntryEditPage(assets: readyAssets));
  }

  Future<void> _toggleAssetSelection(AssetEntity asset) async {
    if (_uploadedAssetIds.contains(asset.id)) {
      ToastUtils.showInfo('已在当前宝宝的当前数据源中存在');
      return;
    }
    if (_checkingAssetIds.contains(asset.id)) {
      ToastUtils.showInfo('正在校验是否已上传');
      return;
    }
    if (_selected.contains(asset.id)) {
      _safeSetState(() => _selected.remove(asset.id));
      return;
    }

    final hash = await _hashAsset(asset, markChecking: true);
    if (hash != null && _remoteHashes.contains(hash)) {
      _uploadedAssetIds.add(asset.id);
      _safeSetState(() {});
      ToastUtils.showInfo('已在当前宝宝的当前数据源中存在');
      return;
    }
    _safeSetState(() => _selected.add(asset.id));
  }

  Future<String> _hashFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  Future<String?> _hashAsset(
    AssetEntity asset, {
    bool markChecking = false,
  }) async {
    final cached = _hashCache[asset.id];
    if (cached != null) return cached;
    if (markChecking) {
      _checkingAssetIds.add(asset.id);
      _safeSetState(() {});
    }
    try {
      final file = await asset.file;
      if (file == null || !await file.exists()) return null;
      final hash = await _hashFile(file);
      _hashCache[asset.id] = hash;
      return hash;
    } catch (_) {
      return null;
    } finally {
      if (markChecking) {
        _checkingAssetIds.remove(asset.id);
        _safeSetState(() {});
      }
    }
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted || _closing) return;
    setState(fn);
  }
}

class _AssetTile extends StatefulWidget {
  const _AssetTile({
    required this.asset,
    required this.thumbnailSize,
    required this.uploaded,
    required this.checking,
    required this.selected,
    required this.onTap,
    required this.onPreview,
  });

  final AssetEntity asset;
  final ThumbnailSize thumbnailSize;
  final bool uploaded;
  final bool checking;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onPreview;

  @override
  State<_AssetTile> createState() => _AssetTileState();
}

class _AssetTileState extends State<_AssetTile> {
  late Future<Uint8List?> _thumbnailFuture;

  @override
  void initState() {
    super.initState();
    _thumbnailFuture = _loadThumbnail();
  }

  @override
  void didUpdateWidget(covariant _AssetTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset.id != widget.asset.id) {
      _thumbnailFuture = _loadThumbnail();
    }
  }

  Future<Uint8List?> _loadThumbnail() {
    return widget.asset.thumbnailDataWithSize(
      widget.thumbnailSize,
      quality: 72,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4.r),
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<Uint8List?>(
              future: _thumbnailFuture,
              builder: (_, snapshot) {
                final bytes = snapshot.data;
                if (bytes == null) {
                  return Container(color: Colors.grey.shade200);
                }
                return Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.low,
                );
              },
            ),
            if (widget.asset.type == AssetType.video)
              Positioned(
                right: 4.w,
                bottom: 4.w,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
            if (widget.uploaded)
              Container(
                color: Colors.black45,
                child: const Center(
                  child: Text(
                    '已上传',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            if (widget.checking)
              Container(
                color: Colors.black26,
                child: const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            if (widget.selected)
              Container(
                color: Colors.pink.withValues(alpha: 0.28),
                child: const Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.check_circle, color: Colors.white),
                  ),
                ),
              ),
            Positioned(
              left: 4.w,
              bottom: 4.w,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onPreview,
                child: SizedBox.square(
                  dimension: 28.w,
                  child: Icon(
                    Icons.visibility,
                    size: 20.sp,
                    color: Colors.white,
                    shadows: const [
                      Shadow(
                        color: Colors.black54,
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssetPreviewPage extends StatefulWidget {
  const _AssetPreviewPage({
    required this.assets,
    required this.initialIndex,
    required this.selectedIds,
    required this.uploadedIds,
    required this.checkingIds,
    required this.onToggleSelection,
  });

  final List<AssetEntity> assets;
  final int initialIndex;
  final Set<String> selectedIds;
  final Set<String> uploadedIds;
  final Set<String> checkingIds;
  final Future<void> Function(AssetEntity asset) onToggleSelection;

  @override
  State<_AssetPreviewPage> createState() => _AssetPreviewPageState();
}

class _AssetPreviewPageState extends State<_AssetPreviewPage> {
  late final PageController _controller;
  late int _index;
  bool _toggling = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.assets[_index];
    final uploaded = widget.uploadedIds.contains(asset.id);
    final checking = widget.checkingIds.contains(asset.id);
    final selected = widget.selectedIds.contains(asset.id);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        foregroundColor: Colors.white,
        backgroundColor: Colors.black,
        title: Text('${_index + 1}/${widget.assets.length}'),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.assets.length,
              onPageChanged: (index) => setState(() => _index = index),
              itemBuilder: (_, index) {
                final current = widget.assets[index];
                if (current.type == AssetType.video) {
                  return _AssetVideoPreview(asset: current);
                }
                return _AssetImagePreview(asset: current);
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 12.h),
              color: Colors.black87,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _assetMeta(asset),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  FilledButton.icon(
                    onPressed: uploaded || checking || _toggling
                        ? null
                        : () async {
                            setState(() => _toggling = true);
                            await widget.onToggleSelection(asset);
                            if (mounted) {
                              setState(() => _toggling = false);
                            }
                          },
                    icon: _toggling || checking
                        ? SizedBox.square(
                            dimension: 16.w,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : Icon(selected
                            ? Icons.check_circle
                            : Icons.add_circle_outline),
                    label: Text(
                      uploaded
                          ? '已上传'
                          : selected
                              ? '取消选择'
                              : '选择',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _assetMeta(AssetEntity asset) {
    final type = asset.type == AssetType.video ? '视频' : '照片';
    final date = asset.createDateTime;
    final dateText =
        '${date.year}-${_twoDigits(date.month)}-${_twoDigits(date.day)} '
        '${_twoDigits(date.hour)}:${_twoDigits(date.minute)}';
    if (asset.type == AssetType.video && asset.duration > 0) {
      return '$type · ${_durationText(asset.duration)} · $dateText';
    }
    return '$type · $dateText';
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');

  String _durationText(int seconds) {
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return '$minutes:${_twoDigits(rest)}';
  }
}

class _AssetImagePreview extends StatefulWidget {
  const _AssetImagePreview({required this.asset});

  final AssetEntity asset;

  @override
  State<_AssetImagePreview> createState() => _AssetImagePreviewState();
}

class _AssetImagePreviewState extends State<_AssetImagePreview> {
  late Future<File?> _fileFuture;

  @override
  void initState() {
    super.initState();
    _fileFuture = widget.asset.file;
  }

  @override
  void didUpdateWidget(covariant _AssetImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset.id != widget.asset.id) {
      _fileFuture = widget.asset.file;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: _fileFuture,
      builder: (_, snapshot) {
        final file = snapshot.data;
        if (file == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return Center(
          child: InteractiveViewer(
            child: Image.file(
              file,
              fit: BoxFit.contain,
              gaplessPlayback: true,
            ),
          ),
        );
      },
    );
  }
}

class _AssetVideoPreview extends StatefulWidget {
  const _AssetVideoPreview({required this.asset});

  final AssetEntity asset;

  @override
  State<_AssetVideoPreview> createState() => _AssetVideoPreviewState();
}

class _AssetVideoPreviewState extends State<_AssetVideoPreview> {
  VideoPlayerController? _controller;
  Future<void>? _initFuture;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initFuture = _init();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final file = await widget.asset.file;
    if (file == null) {
      _error = '视频文件暂不可读取';
      return;
    }
    final controller = VideoPlayerController.file(file);
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setLooping(true);
      if (mounted) setState(() {});
    } catch (e) {
      _error = '视频预览失败：$e';
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (_, snapshot) {
        if (_error != null) {
          return Center(
            child: Padding(
              padding: EdgeInsets.all(28.w),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          );
        }
        final controller = _controller;
        if (controller == null || !controller.value.isInitialized) {
          return const Center(child: CircularProgressIndicator());
        }
        return Center(
          child: GestureDetector(
            onTap: () {
              controller.value.isPlaying
                  ? controller.pause()
                  : controller.play();
              setState(() {});
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: VideoPlayer(controller),
                ),
                if (!controller.value.isPlaying)
                  Container(
                    width: 64.w,
                    height: 64.w,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.46),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 44.sp,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
