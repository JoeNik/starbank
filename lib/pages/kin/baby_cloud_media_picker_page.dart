import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import '../../controllers/app_mode_controller.dart';
import '../../controllers/user_controller.dart';
import '../../services/baby_cloud_service.dart';
import '../../services/storage_service.dart';
import '../../utils/async_semaphore.dart';
import '../../widgets/toast_utils.dart';
import 'baby_cloud_entry_edit_page.dart';
import 'baby_cloud_source_page.dart';

class BabyCloudMediaPickerPage extends StatefulWidget {
  const BabyCloudMediaPickerPage({
    super.key,
    this.initialAssets = const [],
    this.returnSelectionOnly = false,
  });

  final List<AssetEntity> initialAssets;
  final bool returnSelectionOnly;

  @override
  State<BabyCloudMediaPickerPage> createState() =>
      _BabyCloudMediaPickerPageState();
}

class _BabyCloudMediaPickerPageState extends State<BabyCloudMediaPickerPage> {
  static const _pageSize = 80;
  static const _thumbnailSize = ThumbnailSize.square(140);
  static const _crossAxisCount = 4;
  static const _gridSpacing = 4.0;
  static const _lastAssetIdKey = 'baby_cloud_picker_last_asset_id';
  static const int _thumbCacheLimit = 256;
  // 后台"已上传"标记预热时跳过超大文件，避免长时间读盘。
  static const int _warmupHashMaxBytes = 128 * 1024 * 1024;
  // 哈希计算在后台 isolate 执行，但仍限制并发避免 IO 争抢。
  static final AsyncSemaphore _hashSemaphore = AsyncSemaphore(2);

  final _cloud = Get.find<BabyCloudService>();
  final _user = Get.find<UserController>();
  final _mode = Get.find<AppModeController>();
  final _storage = Get.find<StorageService>();
  final _assets = <AssetEntity>[];
  final _selected = <String>{};
  final _selectedAssetsById = <String, AssetEntity>{};
  final _selectedAssetIdsInOrder = <String>[];
  final _uploadedAssetIds = <String>{};
  final _hashCache = <String, String>{};
  final _remoteHashes = <String>{};
  final _warmingAssetIds = <String>{};
  final _checkingAssetIds = <String>{};
  final _scrollController = ScrollController();
  static final Map<String, Uint8List> _thumbnailBytesCache =
      <String, Uint8List>{};
  Timer? _scrollIdleWarmupTimer;
  bool _isScrolling = false;

  AssetPathEntity? _path;
  int _page = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _queueing = false;
  bool _closing = false;
  String? _blockedMessage;
  String? _pendingRestoreAssetId;
  bool _restoringScroll = false;

  @override
  void initState() {
    super.initState();
    for (final asset in widget.initialAssets) {
      _selected.add(asset.id);
      _selectedAssetsById[asset.id] = asset;
      _selectedAssetIdsInOrder.add(asset.id);
    }
    _init();
  }

  @override
  void dispose() {
    _closing = true;
    _scrollIdleWarmupTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    if (!_mode.isParentMode) {
      _safeSetState(() {
        _blockedMessage = '请先切换到家长模式后再上传照片和视频';
        _loading = false;
      });
      return;
    }
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

    _pendingRestoreAssetId =
        _storage.settingsBox.get(_lastAssetIdKey) as String?;
    final babyId = _user.currentBaby.value?.id;
    if (babyId != null) {
      _remoteHashes.addAll(
        _cloud.mediaForBaby(babyId, includeDeleted: false).map((m) => m.sha256),
      );
    }
    _path = paths.first;
    await _loadMore();
    await _restoreLastPositionIfNeeded();
    _safeSetState(() => _loading = false);
  }

  Future<void> _loadMore() async {
    if (_path == null || _loadingMore || !_hasMore) return;
    _loadingMore = true;
    final next = await _path!.getAssetListPaged(page: _page, size: _pageSize);
    _page++;
    // PhotoManager already returns createDate desc via FilterOptionGroup orders.
    _assets.addAll(next);
    for (final asset in next) {
      if (_selected.contains(asset.id)) {
        _selectedAssetsById[asset.id] = asset;
      }
    }
    _hasMore = next.length == _pageSize;
    _loadingMore = false;
    _safeSetState(() {});

    // Defer hash warmup until scrolling settles to keep fling smooth.
    if (!_isScrolling) {
      final warmupCount = _page == 1 ? 24 : 12;
      final visibleWarmups = next.take(warmupCount).toList();
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 350))
            .then((_) => _warmUploadedMarks(visibleWarmups)),
      );
    }
  }

  Future<void> _restoreLastPositionIfNeeded() async {
    final targetId = _pendingRestoreAssetId;
    if (targetId == null || targetId.isEmpty || _restoringScroll) return;
    _restoringScroll = true;
    try {
      var index = _assets.indexWhere((asset) => asset.id == targetId);
      while (index < 0 && _hasMore) {
        await _loadMore();
        index = _assets.indexWhere((asset) => asset.id == targetId);
      }
      if (index >= 0 && mounted && !_closing) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _jumpToAssetIndex(index);
        });
      }
      if (index >= 0 || !_hasMore) {
        _pendingRestoreAssetId = null;
      }
    } finally {
      _restoringScroll = false;
    }
  }

  void _jumpToAssetIndex(int index) {
    if (!_scrollController.hasClients) return;
    final width = MediaQuery.sizeOf(context).width;
    final tileWidth =
        (width - (_gridSpacing * 2) - (_gridSpacing * (_crossAxisCount - 1))) /
            _crossAxisCount;
    final row = index ~/ _crossAxisCount;
    final offset = row * (tileWidth + _gridSpacing);
    final maxOffset = _scrollController.position.maxScrollExtent;
    _scrollController.jumpTo(offset.clamp(0.0, maxOffset));
  }

  void _warmVisibleUploadedMarks() {
    if (!_scrollController.hasClients || _remoteHashes.isEmpty) return;
    final position = _scrollController.position;
    if (!position.hasPixels || !position.hasContentDimensions) return;
    final width = MediaQuery.sizeOf(context).width;
    final tile =
        (width - (_gridSpacing * 2) - (_gridSpacing * (_crossAxisCount - 1))) /
            _crossAxisCount;
    final rowHeight = tile + _gridSpacing;
    if (rowHeight <= 0) return;
    final firstRow = (position.pixels / rowHeight).floor().clamp(0, 1 << 20);
    final visibleRows =
        ((position.viewportDimension / rowHeight).ceil() + 2).clamp(1, 40);
    final start = (firstRow * _crossAxisCount).clamp(0, _assets.length);
    final end =
        ((firstRow + visibleRows) * _crossAxisCount).clamp(0, _assets.length);
    if (start >= end) return;
    unawaited(_warmUploadedMarks(_assets.sublist(start, end)));
  }

  Future<void> _rememberAssetPosition(AssetEntity asset) {
    return _storage.settingsBox.put(_lastAssetIdKey, asset.id);
  }

  Future<void> _warmUploadedMarks(List<AssetEntity> assets) async {
    if (_remoteHashes.isEmpty || _isScrolling) return;
    var changed = false;
    for (final asset in assets) {
      if (!mounted || _closing || _isScrolling) return;
      if (_uploadedAssetIds.contains(asset.id)) continue;
      if (_hashCache.containsKey(asset.id) ||
          _warmingAssetIds.contains(asset.id)) {
        continue;
      }
      _warmingAssetIds.add(asset.id);
      try {
        final hash = await _hashAsset(asset, maxBytes: _warmupHashMaxBytes);
        if (hash == null) continue;
        if (_remoteHashes.contains(hash)) {
          if (_uploadedAssetIds.add(asset.id)) {
            changed = true;
          }
        }
      } catch (_) {
        // Ignore files the system gallery cannot expose.
      } finally {
        _warmingAssetIds.remove(asset.id);
      }
    }
    if (changed) _safeSetState(() {});
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
            child: Text(
                '${widget.returnSelectionOnly ? '完成' : '上传'} ${_selected.length}'),
          ),
        ],
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollStartNotification ||
              notification is ScrollUpdateNotification) {
            _isScrolling = true;
            _scrollIdleWarmupTimer?.cancel();
          } else if (notification is ScrollEndNotification) {
            _isScrolling = false;
            _scrollIdleWarmupTimer?.cancel();
            _scrollIdleWarmupTimer =
                Timer(const Duration(milliseconds: 280), () {
              if (!mounted || _closing) return;
              _warmVisibleUploadedMarks();
            });
          }
          if (notification.metrics.extentAfter < 1200) {
            unawaited(_loadMore());
          }
          return false;
        },
        child: _FastScrollbar(
          controller: _scrollController,
          labelForFraction: _fastScrollLabel,
          child: GridView.builder(
            controller: _scrollController,
            padding: EdgeInsets.all(4.w),
            cacheExtent: 900,
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: true,
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
                key: ValueKey(asset.id),
                asset: asset,
                thumbnailSize: _thumbnailSize,
                thumbnailCache: _thumbnailBytesCache,
                thumbnailCacheLimit: _thumbCacheLimit,
                uploaded: uploaded,
                checking: checking,
                selected: selected,
                onTap: () => _toggleAssetSelection(asset),
                onPreview: () => _openPreview(index),
              );
            },
          ),
        ),
      ),
    );
  }

  String? _fastScrollLabel(double fraction) {
    if (_assets.isEmpty) return null;
    final index =
        ((_assets.length - 1) * fraction).round().clamp(0, _assets.length - 1);
    final date = _assets[index].createDateTime;
    return '${date.year}年${date.month}月${date.day}日';
  }

  void _openPreview(int index) {
    final asset = _assets[index];
    unawaited(_rememberAssetPosition(asset));
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

    final selectedAssets = _orderedSelectedAssets();
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
        _selectedAssetsById.remove(asset.id);
        _selectedAssetIdsInOrder.remove(asset.id);
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
    if (widget.returnSelectionOnly) {
      Get.back(result: readyAssets);
      return;
    }
    Get.off(() => BabyCloudEntryEditPage(assets: readyAssets));
  }

  Future<void> _toggleAssetSelection(AssetEntity asset) async {
    unawaited(_rememberAssetPosition(asset));
    if (_uploadedAssetIds.contains(asset.id)) {
      ToastUtils.showInfo('已在当前宝宝的当前数据源中存在');
      return;
    }
    if (_selected.contains(asset.id)) {
      _safeSetState(() {
        _selected.remove(asset.id);
        _selectedAssetsById.remove(asset.id);
        _selectedAssetIdsInOrder.remove(asset.id);
      });
      return;
    }

    // 立即选中，杜绝点选时等待整文件哈希导致的卡顿；
    // 是否重复上传由后台校验，发现重复时自动取消并提示。
    _safeSetState(() {
      _selected.add(asset.id);
      _selectedAssetsById[asset.id] = asset;
      _selectedAssetIdsInOrder.add(asset.id);
    });
    unawaited(_verifySelectionNotUploaded(asset));
  }

  Future<void> _verifySelectionNotUploaded(AssetEntity asset) async {
    if (_remoteHashes.isEmpty) return;
    String? hash;
    try {
      hash = await _hashAsset(asset);
    } catch (_) {
      return;
    }
    if (!mounted || _closing) return;
    if (hash == null || !_remoteHashes.contains(hash)) return;
    _uploadedAssetIds.add(asset.id);
    final wasSelected = _selected.remove(asset.id);
    _selectedAssetsById.remove(asset.id);
    _selectedAssetIdsInOrder.remove(asset.id);
    if (wasSelected) {
      ToastUtils.showInfo('该文件已上传过，已自动取消选择');
    }
    _safeSetState(() {});
  }

  List<AssetEntity> _orderedSelectedAssets() {
    final result = <AssetEntity>[];
    final seen = <String>{};
    for (final id in _selectedAssetIdsInOrder) {
      final asset = _selectedAssetsById[id];
      if (asset != null && _selected.contains(id) && seen.add(id)) {
        result.add(asset);
      }
    }
    for (final entry in _selectedAssetsById.entries) {
      if (_selected.contains(entry.key) && seen.add(entry.key)) {
        result.add(entry.value);
      }
    }
    return result;
  }

  static Future<String> _hashFile(File file) {
    final path = file.path;
    // SHA-256 在后台 isolate 计算，主线程只等待结果。
    return Isolate.run(() async {
      final digest = await sha256.bind(File(path).openRead()).first;
      return digest.toString();
    });
  }

  Future<String?> _hashAsset(
    AssetEntity asset, {
    bool markChecking = false,
    int? maxBytes,
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
      if (maxBytes != null && await file.length() > maxBytes) return null;
      final hash = await _hashSemaphore.run(() => _hashFile(file));
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

/// 右侧可拖动的快速滚动条：拖动滑块可快速跳转，并显示当前位置的日期气泡。
class _FastScrollbar extends StatefulWidget {
  const _FastScrollbar({
    required this.controller,
    required this.labelForFraction,
    required this.child,
  });

  final ScrollController controller;
  final String? Function(double fraction) labelForFraction;
  final Widget child;

  @override
  State<_FastScrollbar> createState() => _FastScrollbarState();
}

class _FastScrollbarState extends State<_FastScrollbar> {
  static const double _thumbHeight = 52;
  static const double _thumbWidth = 24;

  final GlobalKey _trackKey = GlobalKey();
  bool _dragging = false;
  bool _visible = false;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!widget.controller.hasClients) return;
    final position = widget.controller.position;
    if (!position.hasContentDimensions || position.maxScrollExtent <= 0) {
      return;
    }
    if (!_visible && mounted) {
      setState(() => _visible = true);
    }
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 1600), () {
      if (!mounted || _dragging) return;
      setState(() => _visible = false);
    });
  }

  void _dragTo(Offset globalPosition) {
    final trackBox = _trackKey.currentContext?.findRenderObject() as RenderBox?;
    if (trackBox == null || !widget.controller.hasClients) return;
    final position = widget.controller.position;
    if (!position.hasContentDimensions || position.maxScrollExtent <= 0) {
      return;
    }
    final localY = trackBox.globalToLocal(globalPosition).dy;
    final travel = trackBox.size.height - _thumbHeight;
    if (travel <= 0) return;
    final fraction = ((localY - _thumbHeight / 2) / travel).clamp(0.0, 1.0);
    widget.controller.jumpTo(fraction * position.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 8,
          bottom: 8,
          right: 0,
          width: 120,
          child: LayoutBuilder(
            key: _trackKey,
            builder: (context, box) {
              final trackHeight = box.maxHeight;
              final travel = trackHeight - _thumbHeight;
              return AnimatedBuilder(
                animation: widget.controller,
                builder: (context, _) {
                  double fraction = 0;
                  var hasContent = false;
                  if (widget.controller.hasClients) {
                    final position = widget.controller.position;
                    if (position.hasContentDimensions &&
                        position.maxScrollExtent > 0) {
                      hasContent = true;
                      fraction = (position.pixels / position.maxScrollExtent)
                          .clamp(0.0, 1.0);
                    }
                  }
                  if (!hasContent || travel <= 0) {
                    return const SizedBox.shrink();
                  }
                  final top = fraction * travel;
                  final label =
                      _dragging ? widget.labelForFraction(fraction) : null;
                  final active = _visible || _dragging;
                  return IgnorePointer(
                    // 隐藏时不拦截右侧边缘的滑动手势
                    ignoring: !active,
                    child: AnimatedOpacity(
                      opacity: active ? 1 : 0,
                      duration: const Duration(milliseconds: 220),
                      child: Stack(
                        children: [
                          if (label != null && label.isNotEmpty)
                            Positioned(
                              right: _thumbWidth + 12,
                              top: (top + _thumbHeight / 2 - 20)
                                  .clamp(0.0, trackHeight - 40),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 9,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.78),
                                  borderRadius: BorderRadius.circular(22),
                                ),
                                child: Text(
                                  label,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            top: top,
                            right: 2,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onVerticalDragStart: (details) {
                                setState(() => _dragging = true);
                                _dragTo(details.globalPosition);
                              },
                              onVerticalDragUpdate: (details) =>
                                  _dragTo(details.globalPosition),
                              onVerticalDragEnd: (_) {
                                setState(() => _dragging = false);
                                _scheduleHide();
                              },
                              onVerticalDragCancel: () {
                                setState(() => _dragging = false);
                                _scheduleHide();
                              },
                              child: SizedBox(
                                width: _thumbWidth + 8,
                                height: _thumbHeight,
                                child: Center(
                                  child: Container(
                                    width: _thumbWidth,
                                    height: _thumbHeight,
                                    decoration: BoxDecoration(
                                      color: _dragging
                                          ? const Color(0xFFE91E63)
                                          : Colors.black.withValues(alpha: 0.5),
                                      borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(26),
                                        bottomLeft: Radius.circular(26),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.25),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.unfold_more_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AssetTile extends StatefulWidget {
  const _AssetTile({
    super.key,
    required this.asset,
    required this.thumbnailSize,
    required this.thumbnailCache,
    required this.thumbnailCacheLimit,
    required this.uploaded,
    required this.checking,
    required this.selected,
    required this.onTap,
    required this.onPreview,
  });

  final AssetEntity asset;
  final ThumbnailSize thumbnailSize;
  final Map<String, Uint8List> thumbnailCache;
  final int thumbnailCacheLimit;
  final bool uploaded;
  final bool checking;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onPreview;

  @override
  State<_AssetTile> createState() => _AssetTileState();
}

class _AssetTileState extends State<_AssetTile> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _prepareThumbnail();
  }

  @override
  void didUpdateWidget(covariant _AssetTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset.id != widget.asset.id) {
      _prepareThumbnail();
    }
  }

  void _prepareThumbnail() {
    final cached = widget.thumbnailCache[widget.asset.id];
    if (cached != null) {
      _bytes = cached;
      return;
    }
    _bytes = null;
    _loadThumbnail().then((bytes) {
      if (!mounted || bytes == null) return;
      if (widget.thumbnailCache[widget.asset.id] == null) {
        final cache = widget.thumbnailCache;
        if (cache.length >= widget.thumbnailCacheLimit) {
          final removeCount = (cache.length / 4).ceil();
          final keys = cache.keys.take(removeCount).toList(growable: false);
          for (final key in keys) {
            cache.remove(key);
          }
        }
        cache[widget.asset.id] = bytes;
      }
      if (!identical(_bytes, bytes)) {
        setState(() => _bytes = bytes);
      }
    });
  }

  Future<Uint8List?> _loadThumbnail() {
    return widget.asset.thumbnailDataWithSize(
      widget.thumbnailSize,
      quality: 60,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final decodeWidth =
        (widget.thumbnailSize.width * dpr).round().clamp(80, 220);
    final imageBytes = _bytes;
    return RepaintBoundary(
      child: GestureDetector(
        onTap: widget.onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4.r),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imageBytes != null)
                Image.memory(
                  imageBytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.low,
                  cacheWidth: decodeWidth,
                )
              else
                ColoredBox(color: Colors.grey.shade200),
              if (widget.asset.type == AssetType.video)
                Positioned(
                  right: 4.w,
                  bottom: 4.w,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.play_arrow,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              if (widget.uploaded)
                const ColoredBox(
                  color: Color(0x73000000),
                  child: Center(
                    child: Text(
                      '已上传',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              if (widget.checking)
                const ColoredBox(
                  color: Color(0x42000000),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              if (widget.selected)
                const ColoredBox(
                  color: Color(0x47E91E63),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.check_circle,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ),
              Positioned(
                left: 2.w,
                bottom: 2.w,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onPreview,
                  child: SizedBox.square(
                    dimension: 28.w,
                    child: Icon(
                      Icons.visibility,
                      size: 18.sp,
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
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // 预览无需按原始分辨率解码；限制解码宽度可显著降低内存与掉帧。
    final decodeWidth = (size.width * dpr * 1.5).round().clamp(720, 2048);
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
              cacheWidth: decodeWidth,
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
