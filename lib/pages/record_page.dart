import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:file_picker/file_picker.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../controllers/app_mode_controller.dart';
import '../controllers/user_controller.dart';
import '../models/baby_cloud_entry.dart';
import '../models/baby_cloud_media.dart';
import '../models/baby_cloud_source.dart';
import '../services/baby_cloud_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../utils/baby_profile_utils.dart';
import '../widgets/baby_cloud_media_thumbnail.dart';
import '../widgets/image_utils.dart';
import '../widgets/toast_utils.dart';
import 'growth_record_page.dart';
import 'kin/baby_cloud_audio_record_page.dart';
import 'kin/baby_cloud_entry_detail_page.dart';
import 'kin/baby_cloud_entry_edit_page.dart';
import 'kin/baby_cloud_media_detail_page.dart';
import 'kin/baby_cloud_media_picker_page.dart';
import 'kin/baby_cloud_recycle_bin_page.dart';
import 'kin/baby_cloud_source_page.dart';
import 'kin/baby_cloud_upload_tasks_page.dart';
import 'milestone_page.dart';
import 'poop/poop_record_page.dart';

class _TimelineEntryData {
  const _TimelineEntryData({
    required this.entry,
    required this.mediaItems,
  });

  final BabyCloudEntry? entry;
  final List<BabyCloudMedia> mediaItems;

  DateTime get takenAt {
    final entryTime = entry?.takenAt;
    if (entryTime != null) return entryTime;
    if (mediaItems.isNotEmpty) return mediaItems.first.takenAt;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}

ImageProvider? _recordHeroImageProvider(String? source) {
  final value = source?.trim();
  if (value == null || value.isEmpty) return null;
  if (value.startsWith('assets/')) return AssetImage(value);
  if (value.startsWith('http')) return NetworkImage(value);
  if (_looksLikeRecordHeroFilePath(value)) {
    try {
      final file = File(value);
      return file.existsSync() ? FileImage(file) : null;
    } catch (_) {
      return null;
    }
  }
  if (value.length > 100) {
    try {
      return MemoryImage(base64Decode(value.replaceAll(RegExp(r'\s+'), '')));
    } catch (_) {
      return null;
    }
  }
  return null;
}

bool _looksLikeRecordHeroFilePath(String source) {
  if (source.startsWith('/') || source.startsWith('\\')) return true;
  return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(source);
}

class _HeroBackgroundImage extends StatefulWidget {
  const _HeroBackgroundImage({required this.path});

  final String path;

  @override
  State<_HeroBackgroundImage> createState() => _HeroBackgroundImageState();
}

class _HeroBackgroundImageState extends State<_HeroBackgroundImage> {
  ImageProvider? _provider;

  @override
  void initState() {
    super.initState();
    _resolveProvider();
  }

  @override
  void didUpdateWidget(covariant _HeroBackgroundImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _resolveProvider();
  }

  void _resolveProvider() {
    _provider = _recordHeroImageProvider(widget.path);
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    if (provider == null) return const SizedBox.shrink();
    return Image(
      image: provider,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }
}

class _HeroBabyAvatar extends StatelessWidget {
  const _HeroBabyAvatar({
    required this.path,
    required this.radius,
    required this.imageSize,
    required this.iconSize,
    required this.hasAvatar,
  });

  final String path;
  final double radius;
  final double imageSize;
  final double iconSize;
  final bool hasAvatar;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.white.withValues(alpha: 0.88),
      child: ClipOval(
        child: ImageUtils.displayImage(
          hasAvatar ? path : '',
          width: imageSize,
          height: imageSize,
          fit: BoxFit.cover,
          placeholder: Center(
            child: Text('👶', style: TextStyle(fontSize: iconSize)),
          ),
        ),
      ),
    );
  }
}

/// 亲宝宝模块入口。
/// 云相册是主页面，便便记录、生长记录和宝宝大事记收拢在后续 tab 中。
class RecordPage extends StatefulWidget {
  const RecordPage({super.key, this.isActive = false});

  final bool isActive;

  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  static const _cloudActorRoles = [
    '妈妈',
    '爸爸',
    '爷爷',
    '奶奶',
    '外公',
    '外婆',
    '家人',
  ];

  final _user = Get.find<UserController>();
  final _cloud = Get.find<BabyCloudService>();
  final _mode = Get.find<AppModeController>();
  final _storage = Get.find<StorageService>();
  final _albumScrollController = ScrollController();
  final _searchController = TextEditingController();
  final _imagePicker = ImagePicker();
  final _filterRevision = ValueNotifier<int>(0);

  Worker? _babySyncWorker;
  Worker? _sourceSyncWorker;
  bool _heroCollapsed = false;
  bool _searchOpen = false;
  String _searchQuery = '';
  String _mediaFilter = 'all';
  DateTime? _dateFilter;
  bool _visibleSyncRunning = false;

  @override
  void initState() {
    super.initState();
    _albumScrollController.addListener(_handleAlbumScroll);
    _babySyncWorker = ever(_user.currentBaby, (_) {
      if (widget.isActive) _scheduleCurrentBabySync();
    });
    _sourceSyncWorker = ever(_cloud.currentSource, (_) {
      if (widget.isActive) _scheduleCurrentBabySync();
    });
    if (widget.isActive) {
      _scheduleCurrentBabySync();
    }
  }

  @override
  void didUpdateWidget(covariant RecordPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive) {
      _scheduleCurrentBabySync();
    }
  }

  @override
  void dispose() {
    _babySyncWorker?.dispose();
    _sourceSyncWorker?.dispose();
    _albumScrollController
      ..removeListener(_handleAlbumScroll)
      ..dispose();
    _searchController.dispose();
    _filterRevision.dispose();
    super.dispose();
  }

  void _notifyFiltersChanged() {
    _filterRevision.value++;
  }

  void _openSearchPanel() {
    if (!_searchOpen) {
      _searchOpen = true;
      _notifyFiltersChanged();
    }
  }

  void _handleAlbumScroll() {
    if (!_albumScrollController.hasClients) return;
    final offset = _albumScrollController.offset;
    if (!_heroCollapsed && offset > 76.h) {
      setState(() => _heroCollapsed = true);
    } else if (_heroCollapsed && offset < 34.h) {
      setState(() => _heroCollapsed = false);
    }
  }

  void _scheduleCurrentBabySync({
    bool showErrors = false,
    bool forceRemote = false,
  }) {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _syncCurrentBaby(
        showErrors: showErrors,
        forceRemote: forceRemote,
      ),
    );
  }

  Future<void> _syncCurrentBaby({
    bool showErrors = false,
    bool forceRemote = false,
  }) async {
    if (_visibleSyncRunning) return;
    final baby = _user.currentBaby.value;
    if (baby == null || _cloud.currentSource.value == null) return;
    _visibleSyncRunning = true;
    try {
      await _cloud.syncBaby(
        baby,
        showErrors: showErrors,
        forceRemote: forceRemote,
      );
      unawaited(_cloud.processQueue());
    } finally {
      _visibleSyncRunning = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final baby = _user.currentBaby.value;
      if (baby == null) {
        return Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(28.w),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.child_care,
                      size: 64.sp, color: Colors.grey.shade300),
                  SizedBox(height: 12.h),
                  Text(
                    '请先在主页选择或添加宝宝',
                    style:
                        TextStyle(fontSize: 16.sp, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      return DefaultTabController(
        length: 4,
        child: Scaffold(
          backgroundColor: const Color(0xFFF6F6F6),
          body: Column(
            children: [
              _buildHero(baby),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildAlbumTab(baby),
                    _buildFeatureTab(
                      icon: Icons.flag,
                      color: Colors.pink,
                      title: '宝宝大事记',
                      subtitle: '记录第一次、旅行、露营等重要时刻。',
                      buttonText: '进入大事记',
                      onTap: () => Get.to(() => const MilestonePage()),
                    ),
                    _buildFeatureTab(
                      icon: Icons.height,
                      color: Colors.green,
                      title: '生长记录',
                      subtitle: '记录身高、体重、头围，查看 WHO 参考曲线。',
                      buttonText: '进入生长记录',
                      onTap: () => Get.to(() => const GrowthRecordPage()),
                    ),
                    _buildFeatureTab(
                      icon: Icons.calendar_month,
                      color: Colors.brown,
                      title: '便便记录',
                      subtitle: '记录宝宝排便情况，查看 AI 分析和历史趋势。',
                      buttonText: '进入便便记录',
                      onTap: () => Get.to(() => const PoopRecordPage()),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildHero(baby) {
    final hasAvatar = baby.avatarPath.trim().isNotEmpty;
    final coverPath = _heroCoverPath(baby.id);
    final collapsed = _heroCollapsed;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      height: collapsed ? 138.h : 304.h,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFB9C6BA), Color(0xFFE8BC72)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          if (coverPath != null || hasAvatar)
            RepaintBoundary(
              child: _HeroBackgroundImage(
                path: coverPath ?? baby.avatarPath,
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withOpacity(0.24),
                  Colors.black.withOpacity(0.06),
                  Colors.black.withOpacity(0.42),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Stack(
              children: [
                Positioned(
                  left: 16.w,
                  right: 14.w,
                  top: 8.h,
                  child: Row(
                    children: [
                      Expanded(
                        child: AnimatedOpacity(
                          opacity: collapsed ? 1 : 0,
                          duration: const Duration(milliseconds: 140),
                          curve: Curves.easeOut,
                          child: Row(
                            children: [
                              _buildBabyAvatar(
                                baby,
                                radius: 17.r,
                                imageSize: 30.w,
                                iconSize: 20.sp,
                                hasAvatar: hasAvatar,
                              ),
                              SizedBox(width: 8.w),
                              Expanded(
                                child: Text(
                                  baby.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18.sp,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '搜索',
                        onPressed: _openSearchPanel,
                        icon: Icon(
                          Icons.search,
                          color: Colors.white,
                          size: 25.sp,
                        ),
                      ),
                      InkWell(
                        onTap: _showUploadMenu,
                        borderRadius: BorderRadius.circular(99),
                        child: Container(
                          width: 40.w,
                          height: 40.w,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFFC22D),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.add_a_photo,
                            color: Colors.white,
                            size: 21.sp,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 16.w,
                  right: 16.w,
                  bottom: 58.h,
                  child: IgnorePointer(
                    ignoring: collapsed,
                    child: AnimatedOpacity(
                      opacity: collapsed ? 0 : 1,
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOut,
                      child: AnimatedSlide(
                        offset:
                            collapsed ? const Offset(0, -0.08) : Offset.zero,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            _buildBabyAvatar(
                              baby,
                              radius: 40.r,
                              imageSize: 72.w,
                              iconSize: 42.sp,
                              hasAvatar: hasAvatar,
                            ),
                            SizedBox(width: 16.w),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    baby.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 24.sp,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  SizedBox(height: 4.h),
                                  Text(
                                    BabyProfileUtils.ageText(baby),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18.sp,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(width: 8.w),
                            IconButton.filledTonal(
                              tooltip: '更换背景',
                              style: IconButton.styleFrom(
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.22),
                                foregroundColor: Colors.white,
                                fixedSize: Size(40.w, 40.w),
                              ),
                              onPressed: () => _changeHeroCover(baby),
                              icon: Icon(Icons.wallpaper_outlined, size: 21.sp),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SizedBox(
                    height: 48.h,
                    child: TabBar(
                      isScrollable: false,
                      indicatorColor: const Color(0xFFFFC22D),
                      indicatorWeight: 4,
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white.withOpacity(0.86),
                      labelStyle: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w900,
                      ),
                      unselectedLabelStyle: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w700,
                      ),
                      tabs: const [
                        Tab(text: '云相册'),
                        Tab(text: '大事记'),
                        Tab(text: '生长'),
                        Tab(text: '便便'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _heroCoverPath(String babyId) {
    final path = _storage.settingsBox.get(
      'baby_cloud_cover_$babyId',
      defaultValue: '',
    ) as String;
    if (path.trim().isEmpty) return null;
    try {
      return File(path).existsSync() ? path : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _changeHeroCover(baby) async {
    final file = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
    );
    if (file == null) return;
    try {
      final dir = Directory(
        '${(await getApplicationDocumentsDirectory()).path}'
        '${Platform.pathSeparator}baby_cloud_covers',
      );
      await dir.create(recursive: true);
      final ext =
          _extension(file.name).isEmpty ? '.jpg' : _extension(file.name);
      final target = File(
        '${dir.path}${Platform.pathSeparator}${baby.id}_cover$ext',
      );
      await File(file.path).copy(target.path);
      await _storage.settingsBox
          .put('baby_cloud_cover_${baby.id}', target.path);
      if (mounted) setState(() {});
      ToastUtils.showSuccess('背景图已更新');
    } catch (e) {
      ToastUtils.showError('更新背景图失败: $e');
    }
  }

  Widget _buildBabyAvatar(
    baby, {
    required double radius,
    required double imageSize,
    required double iconSize,
    required bool hasAvatar,
  }) {
    return _HeroBabyAvatar(
      path: baby.avatarPath,
      radius: radius,
      imageSize: imageSize,
      iconSize: iconSize,
      hasAvatar: hasAvatar,
    );
  }

  Widget _buildAlbumTab(baby) {
    return ValueListenableBuilder<int>(
      valueListenable: _filterRevision,
      builder: (context, _, __) {
        return RefreshIndicator(
          onRefresh: () => _syncCurrentBaby(
            showErrors: true,
            forceRemote: true,
          ),
          child: CustomScrollView(
            controller: _albumScrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _buildSourceTools()),
              if (_searchOpen ||
                  _searchQuery.isNotEmpty ||
                  _mediaFilter != 'all' ||
                  _dateFilter != null)
                SliverToBoxAdapter(child: _buildSearchPanel()),
              _buildTimelineSliver(baby.id),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSourceTools() {
    return Obx(() {
      final source = _cloud.currentSource.value;
      return Container(
        color: Colors.white,
        padding: EdgeInsets.fromLTRB(12.w, 7.h, 12.w, 8.h),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => Get.to(() => const BabyCloudSourcePage()),
                borderRadius: BorderRadius.circular(8.r),
                child: Container(
                  height: 46.h,
                  padding: EdgeInsets.symmetric(horizontal: 10.w),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F8F8),
                    borderRadius: BorderRadius.circular(8.r),
                    border: Border.all(color: const Color(0xFFEAEAEA)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.dns_outlined,
                          size: 18.sp, color: AppTheme.primaryDark),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    source == null ? '未配置数据源' : source.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13.sp,
                                      fontWeight: FontWeight.w900,
                                      color: AppTheme.textMain,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 6.w),
                                _sourceStatusBadge(source),
                              ],
                            ),
                            SizedBox(height: 2.h),
                            Text(
                              _sourceSubtitle(source),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.sp,
                                color: Colors.grey.shade500,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          size: 18.sp, color: Colors.grey.shade500),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(width: 8.w),
            _roleToolButton(),
            _compactToolButton(
              tooltip: '按时间选择',
              icon: Icons.timeline,
              backgroundColor: const Color(0xFFFFF4D0),
              foregroundColor: const Color(0xFFE09B00),
              onPressed: _pickTimelineDate,
            ),
            _compactToolButton(
              tooltip: '后台任务',
              icon: Icons.task_alt_outlined,
              onPressed: () => Get.to(() => const BabyCloudUploadTasksPage()),
            ),
            _compactToolButton(
              tooltip: '回收站',
              icon: Icons.inventory_2_outlined,
              onPressed: () => Get.to(() => const BabyCloudRecycleBinPage()),
            ),
          ],
        ),
      );
    });
  }

  Widget _roleToolButton() {
    final role = _cloudActorRole;
    return Padding(
      padding: EdgeInsets.only(left: 5.w),
      child: SizedBox.square(
        dimension: 38.w,
        child: PopupMenuButton<String>(
          tooltip: '发布角色：$role',
          padding: EdgeInsets.zero,
          onSelected: _setCloudActorRole,
          itemBuilder: (_) => _cloudActorRoles
              .map(
                (item) => PopupMenuItem(
                  value: item,
                  child: Row(
                    children: [
                      Icon(
                        item == role
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                        size: 18,
                        color: item == role
                            ? AppTheme.primaryDark
                            : Colors.grey.shade400,
                      ),
                      const SizedBox(width: 8),
                      Text(item),
                    ],
                  ),
                ),
              )
              .toList(),
          child: Container(
            width: 38.w,
            height: 38.w,
            decoration: BoxDecoration(
              color: const Color(0xFFF4F4F4),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Icon(
              Icons.supervisor_account_outlined,
              size: 20.sp,
              color: AppTheme.textMain,
            ),
          ),
        ),
      ),
    );
  }

  Widget _compactToolButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
    Color? backgroundColor,
    Color? foregroundColor,
  }) {
    return Padding(
      padding: EdgeInsets.only(left: 5.w),
      child: SizedBox.square(
        dimension: 38.w,
        child: IconButton.filledTonal(
          tooltip: tooltip,
          style: IconButton.styleFrom(
            padding: EdgeInsets.zero,
            backgroundColor: backgroundColor ?? const Color(0xFFF4F4F4),
            foregroundColor: foregroundColor ?? AppTheme.textMain,
          ),
          onPressed: onPressed,
          icon: Icon(icon, size: 20.sp),
        ),
      ),
    );
  }

  String get _cloudActorRole {
    final babyId = _user.currentBaby.value?.id;
    final key = babyId == null
        ? 'baby_cloud_actor_role'
        : 'baby_cloud_actor_role_$babyId';
    final value = _storage.settingsBox.get(key, defaultValue: '妈妈') as String;
    return _cloudActorRoles.contains(value) ? value : '妈妈';
  }

  Future<void> _setCloudActorRole(String role) async {
    final babyId = _user.currentBaby.value?.id;
    final key = babyId == null
        ? 'baby_cloud_actor_role'
        : 'baby_cloud_actor_role_$babyId';
    await _storage.settingsBox.put(key, role);
    if (mounted) setState(() {});
  }

  Widget _sourceStatusBadge(BabyCloudSource? source) {
    final syncing = _cloud.isSyncing.value;
    final color = syncing
        ? const Color(0xFF2F80ED)
        : source == null
            ? Colors.grey
            : source.status == 'normal'
                ? const Color(0xFF18A058)
                : source.status == 'invalid'
                    ? const Color(0xFFE5484D)
                    : const Color(0xFFE09B00);
    final label = syncing
        ? '检测中'
        : source == null
            ? '未配置'
            : source.status == 'normal'
                ? '可用'
                : source.status == 'invalid'
                    ? '不可用'
                    : '未检测';
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (syncing) ...[
            SizedBox(
              width: 8.w,
              height: 8.w,
              child: CircularProgressIndicator(
                strokeWidth: 1.4,
                color: color,
              ),
            ),
            SizedBox(width: 4.w),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 9.sp,
              height: 1.1,
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  String _sourceSubtitle(BabyCloudSource? source) {
    if (source == null) return '点击配置独立 WebDAV';
    if (_cloud.isSyncing.value) return '正在检查 WebDAV 可用性';
    final endpoint = source.activeWebDavEndpoint == 'lan'
        ? '内网'
        : source.activeWebDavEndpoint == 'external'
            ? '外网'
            : '未选择线路';
    final checked = source.lastCheckedAt == null
        ? '尚未检测'
        : DateFormat('HH:mm').format(source.lastCheckedAt!);
    return '$endpoint · $checked';
  }

  Widget _buildSearchPanel() {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(14.w, 0, 14.w, 12.h),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: (value) {
              _searchQuery = value.trim();
              _notifyFiltersChanged();
            },
            decoration: InputDecoration(
              hintText: '搜索文字、标签、日期',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                onPressed: _clearFilters,
                icon: const Icon(Icons.close),
              ),
              filled: true,
              fillColor: const Color(0xFFF7F7F7),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10.r),
                borderSide: BorderSide.none,
              ),
              isDense: true,
            ),
          ),
          SizedBox(height: 8.h),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('全部', 'all'),
                SizedBox(width: 8.w),
                _filterChip('照片', 'photo'),
                SizedBox(width: 8.w),
                _filterChip('视频', 'video'),
                SizedBox(width: 8.w),
                _filterChip('录音', 'audio'),
                SizedBox(width: 8.w),
                _filterChip('文字', 'diary'),
                if (_dateFilter != null) ...[
                  SizedBox(width: 8.w),
                  ActionChip(
                    label: Text(DateFormat('MM-dd').format(_dateFilter!)),
                    avatar: const Icon(Icons.event, size: 16),
                    onPressed: _pickTimelineDate,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _mediaFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        _mediaFilter = value;
        _notifyFiltersChanged();
      },
      selectedColor: const Color(0xFFFFE8A6),
      side: BorderSide.none,
      backgroundColor: const Color(0xFFF5F5F5),
    );
  }

  Widget _buildTimelineSliver(String babyId) {
    return Obx(() {
      final source = _cloud.currentSource.value;
      final mediaItems = _cloud.mediaForBaby(babyId);
      final timelineEntries = _timelineEntriesFor(babyId, mediaItems);
      if (source == null) {
        return SliverFillRemaining(
          hasScrollBody: false,
          child: _emptyTimeline('先配置亲宝宝 WebDAV，再开始备份照片和视频'),
        );
      }
      if (timelineEntries.isEmpty) {
        final sourceId = source.id;
        final tasks = _cloud.uploadTasks
            .where((task) =>
                task.babyId == babyId && task.dataSourceId == sourceId)
            .toList();
        final activeTasks = tasks.where((task) => task.isActive).length;
        final failedTasks =
            tasks.where((task) => task.status == 'failed').toList();
        if (activeTasks > 0) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: _taskTimeline(
              icon: Icons.task_alt_outlined,
              title: '正在后台处理',
              message: '$activeTasks 个任务正在处理，完成后会同步到时间轴',
            ),
          );
        }
        if (failedTasks.isNotEmpty) {
          final reason = failedTasks.first.errorMessage ?? '未知错误';
          return SliverFillRemaining(
            hasScrollBody: false,
            child: _taskTimeline(
              icon: Icons.error_outline,
              title: '后台任务失败',
              message: reason,
            ),
          );
        }
        return SliverFillRemaining(
          hasScrollBody: false,
          child: _emptyTimeline('还没有上传照片或视频'),
        );
      }

      final visibleEntries =
          timelineEntries.where(_matchesTimelineEntry).toList();
      if (visibleEntries.isEmpty) {
        return SliverFillRemaining(
          hasScrollBody: false,
          child: _emptyTimeline('没有匹配的亲宝宝记录'),
        );
      }
      if (_mediaFilter == 'photo' || _mediaFilter == 'video') {
        final visibleMedia = visibleEntries
            .expand((entry) => entry.mediaItems)
            .where((item) => item.mediaType == _mediaFilter)
            .toList();
        if (visibleMedia.isEmpty) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: _emptyTimeline('没有匹配的亲宝宝记录'),
          );
        }
        return _buildFilteredMediaGrid(visibleMedia);
      }

      final groups = <String, List<_TimelineEntryData>>{};
      for (final entry in visibleEntries) {
        final key = DateFormat('yyyy-MM-dd').format(entry.takenAt);
        groups.putIfAbsent(key, () => []).add(entry);
      }
      final entries = groups.entries.toList();
      return SliverPadding(
        padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 24.h),
        sliver: SliverList.builder(
          itemCount: entries.length,
          itemBuilder: (_, index) {
            final entry = entries[index];
            final date = DateTime.parse(entry.key);
            return _buildDayGroup(date, entry.value);
          },
        ),
      );
    });
  }

  Widget _buildFilteredMediaGrid(List<BabyCloudMedia> items) {
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 24.h),
      sliver: SliverGrid.builder(
        itemCount: items.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 5.w,
          mainAxisSpacing: 5.w,
        ),
        itemBuilder: (_, index) => Material(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(6.r),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Get.to(
              () => BabyCloudMediaDetailPage(
                items: items,
                initialIndex: index,
              ),
            ),
            child: BabyCloudMediaThumbnail(
              item: items[index],
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );
  }

  List<_TimelineEntryData> _timelineEntriesFor(
    String babyId,
    List<BabyCloudMedia> mediaItems,
  ) {
    final result = <_TimelineEntryData>[];
    final usedMediaIds = <String>{};
    final entries = _cloud.entriesForBaby(babyId);

    for (final entry in entries) {
      final mediaIds = entry.mediaIds.toSet();
      final entryMedia = mediaItems
          .where(
            (item) => item.entryId == entry.id || mediaIds.contains(item.id),
          )
          .toList()
        ..sort((a, b) => a.takenAt.compareTo(b.takenAt));
      usedMediaIds.addAll(entryMedia.map((item) => item.id));
      result.add(_TimelineEntryData(entry: entry, mediaItems: entryMedia));
    }

    final fallbackGroups = <String, List<BabyCloudMedia>>{};
    for (final item in mediaItems) {
      if (usedMediaIds.contains(item.id)) continue;
      fallbackGroups.putIfAbsent(item.entryId, () => []).add(item);
    }
    for (final items in fallbackGroups.values) {
      items.sort((a, b) => a.takenAt.compareTo(b.takenAt));
      result.add(_TimelineEntryData(entry: null, mediaItems: items));
    }

    return result..sort((a, b) => b.takenAt.compareTo(a.takenAt));
  }

  Widget _buildDayGroup(DateTime date, List<_TimelineEntryData> items) {
    final today = DateUtils.isSameDay(date, DateTime.now());
    final baby = _user.currentBaby.value;
    final ageText =
        baby == null ? '' : BabyProfileUtils.ageText(baby, now: date);
    return Padding(
      padding: EdgeInsets.only(bottom: 20.h),
      child: Stack(
        children: [
          Positioned(
            left: 5.w,
            top: 12.w,
            bottom: 0,
            child: GestureDetector(
              onTap: _pickTimelineDate,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 10.w,
                color: Colors.transparent,
                child: Center(
                  child: Container(width: 2.w, color: const Color(0xFFE6E6E6)),
                ),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 18.w,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: GestureDetector(
                    onTap: _pickTimelineDate,
                    child: Container(
                      width: 12.w,
                      height: 12.w,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFFFC22D),
                          width: 3,
                        ),
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: 2.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            today ? '今天' : DateFormat('M月d日').format(date),
                            style: TextStyle(
                              fontSize: 22.sp,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.textMain,
                            ),
                          ),
                          SizedBox(width: 8.w),
                          Expanded(
                            child: Text(
                              ageText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w800,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 10.h),
                      for (final entry in items) _buildEntryCard(entry),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEntryCard(_TimelineEntryData timelineEntry) {
    final entry = timelineEntry.entry;
    final entryItems = timelineEntry.mediaItems;
    final first = entryItems.isNotEmpty ? entryItems.first : null;
    final mediaItems = entryItems.where((item) => !item.isDiary).toList();
    final description = (entry?.description ?? first?.description ?? '').trim();
    final tags = entry?.tags ?? first?.tags ?? const <String>[];
    final locationName = entry?.locationName ?? first?.locationName;
    final actorRole = entry?.actorRole?.trim().isNotEmpty == true
        ? entry!.actorRole!.trim()
        : first?.actorRole?.trim().isNotEmpty == true
            ? first!.actorRole!.trim()
            : '家人';
    final takenAt = timelineEntry.takenAt;
    return Container(
      margin: EdgeInsets.only(bottom: 14.h),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8.r),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openEntryDetail(timelineEntry),
          child: Padding(
            padding: EdgeInsets.all(10.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (mediaItems.isNotEmpty)
                  _buildMediaWrap(
                    mediaItems,
                    onOverflowTap: () => _openEntryDetail(timelineEntry),
                  ),
                if (description.isNotEmpty) ...[
                  SizedBox(height: 10.h),
                  InkWell(
                    onTap: () => _openEntryDetail(timelineEntry),
                    borderRadius: BorderRadius.circular(6.r),
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 2.h),
                      child: Text(
                        description,
                        style: TextStyle(
                          fontSize: 16.sp,
                          height: 1.35,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textMain,
                        ),
                      ),
                    ),
                  ),
                ],
                if (tags.isNotEmpty) ...[
                  SizedBox(height: 8.h),
                  InkWell(
                    onTap: () => _openEntryDetail(timelineEntry),
                    borderRadius: BorderRadius.circular(6.r),
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 2.h),
                      child: Wrap(
                        spacing: 6.w,
                        runSpacing: 6.h,
                        children: tags
                            .map((tag) => Chip(
                                  label: Text('#$tag'),
                                  side: BorderSide.none,
                                  visualDensity: VisualDensity.compact,
                                  backgroundColor: const Color(0xFFFFF4D0),
                                ))
                            .toList(),
                      ),
                    ),
                  ),
                ],
                SizedBox(height: 8.h),
                InkWell(
                  onTap: () => _openEntryDetail(timelineEntry),
                  borderRadius: BorderRadius.circular(6.r),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 2.h),
                    child: Row(
                      children: [
                        Text(
                          actorRole,
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (locationName?.trim().isNotEmpty == true) ...[
                          SizedBox(width: 6.w),
                          Flexible(
                            child: Text(
                              locationName!.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                        SizedBox(width: 6.w),
                        Text(
                          DateFormat('HH:mm').format(takenAt),
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        PopupMenuButton<String>(
                          tooltip: '更多',
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            Icons.more_horiz,
                            color: Colors.blueGrey.shade400,
                            size: 22.sp,
                          ),
                          onSelected: (value) {
                            if (value == 'edit') _editEntry(timelineEntry);
                            if (value == 'delete') {
                              _confirmDeleteEntry(timelineEntry);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit_outlined),
                                  SizedBox(width: 8),
                                  Text('编辑动态'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline),
                                  SizedBox(width: 8),
                                  Text('删除动态'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (description.isEmpty && tags.isEmpty && mediaItems.isEmpty)
                  SizedBox(height: 24.h, width: double.infinity),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openEntryDetail(_TimelineEntryData entry) {
    Get.to(
      () => BabyCloudEntryDetailPage(
        entry: entry.entry,
        mediaItems: entry.mediaItems,
        fallbackActorRole: '家人',
      ),
    );
  }

  Future<void> _editEntry(_TimelineEntryData entry) async {
    if (!_ensureParentMode('请先切换到家长模式后再编辑亲宝宝动态')) {
      return;
    }
    if (entry.mediaItems.isEmpty) {
      ToastUtils.showWarning('这条动态暂无可编辑的媒体记录');
      return;
    }
    await Get.to(
      () => BabyCloudEntryEditPage(editingItems: entry.mediaItems),
    );
    _cloud.reloadLocalMedia();
  }

  Future<void> _confirmDeleteEntry(_TimelineEntryData entry) async {
    if (!_ensureParentMode('请先切换到家长模式后再删除亲宝宝动态')) {
      return;
    }
    if (entry.mediaItems.isEmpty) {
      ToastUtils.showWarning('这条动态暂无可删除的媒体记录');
      return;
    }
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('删除动态'),
        content: const Text('这条动态会移入亲宝宝回收站，可在回收站恢复。'),
        actions: [
          TextButton(
              onPressed: () => Get.back(result: false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _cloud.softDeleteEntry(entry.mediaItems);
    ToastUtils.showSuccess('已移入回收站');
  }

  Widget _buildMediaWrap(
    List<BabyCloudMedia> items, {
    VoidCallback? onTileTap,
    VoidCallback? onOverflowTap,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = 4.w;
        final tileSize = (constraints.maxWidth - gap * 2) / 3;
        final visibleCount = items.length > 9 ? 9 : items.length;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var index = 0; index < visibleCount; index++)
              SizedBox(
                width: tileSize,
                height: tileSize,
                child: _buildMediaTile(
                  items,
                  index,
                  onTap: onTileTap,
                  onOverflowTap: onOverflowTap,
                  overflowCount:
                      index == 8 && items.length > 9 ? items.length - 8 : 0,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildMediaTile(
    List<BabyCloudMedia> items,
    int index, {
    VoidCallback? onTap,
    VoidCallback? onOverflowTap,
    int overflowCount = 0,
  }) {
    final item = items[index];
    return Material(
      color: Colors.grey.shade200,
      borderRadius: BorderRadius.circular(4.r),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap ??
            () => Get.to(
                  () => BabyCloudMediaDetailPage(
                    items: items,
                    initialIndex: index,
                  ),
                ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            BabyCloudMediaThumbnail(
              item: item,
              fit: BoxFit.cover,
            ),
            if (overflowCount > 0)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onOverflowTap,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.28),
                  child: Center(
                    child: Text(
                      '+$overflowCount',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24.sp,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _emptyTimeline(String text) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(28.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_library_outlined,
                size: 68.sp, color: Colors.grey.shade300),
            SizedBox(height: 12.h),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
            SizedBox(height: 16.h),
            ElevatedButton.icon(
              onPressed: () {
                if (!_ensureParentMode('请先切换到家长模式后再上传照片和视频')) {
                  return;
                }
                _showUploadMenu();
              },
              icon: const Icon(Icons.add_a_photo),
              label: const Text('上传照片/视频'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _taskTimeline({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(28.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 68.sp, color: Colors.grey.shade400),
            SizedBox(height: 12.h),
            Text(
              title,
              style: TextStyle(
                fontSize: 17.sp,
                fontWeight: FontWeight.w900,
                color: AppTheme.textMain,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              message,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
            SizedBox(height: 16.h),
            OutlinedButton.icon(
              onPressed: () => Get.to(() => const BabyCloudUploadTasksPage()),
              icon: const Icon(Icons.task_alt_outlined),
              label: const Text('查看后台任务'),
            ),
          ],
        ),
      ),
    );
  }

  bool _matchesTimelineEntry(_TimelineEntryData entryData) {
    final entry = entryData.entry;
    final mediaItems = entryData.mediaItems;
    if (_mediaFilter != 'all') {
      final entryMatchesType = entry?.entryType == _mediaFilter;
      final mediaMatchesType =
          mediaItems.any((item) => item.mediaType == _mediaFilter);
      if (!entryMatchesType && !mediaMatchesType) return false;
    }
    if (_dateFilter != null &&
        !DateUtils.isSameDay(entryData.takenAt, _dateFilter)) {
      return false;
    }

    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return true;

    final dateText =
        DateFormat('yyyy-MM-dd MM-dd M月d日').format(entryData.takenAt);
    final typeLabels = <String>[
      entry?.entryType ?? '',
      for (final item in mediaItems) item.mediaType,
    ].map((type) {
      return switch (type) {
        'photo' => '照片 图片',
        'video' => '视频',
        'audio' => '录音 音频',
        'diary' => '文字 日记',
        'mixed' => '混合 动态',
        'media' => '媒体 动态',
        _ => type,
      };
    }).join(' ');
    final haystack = [
      entry?.description ?? '',
      entry?.locationName ?? '',
      entry?.tags.join(' ') ?? '',
      dateText,
      typeLabels,
      for (final item in mediaItems) ...[
        item.description ?? '',
        item.fileName,
        item.locationName ?? '',
        item.tags.join(' '),
      ],
    ].join(' ').toLowerCase();
    return haystack.contains(query);
  }

  void _clearFilters() {
    _searchOpen = false;
    _searchQuery = '';
    _mediaFilter = 'all';
    _dateFilter = null;
    _searchController.clear();
    _notifyFiltersChanged();
  }

  Future<void> _pickTimelineDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateFilter ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    _searchOpen = true;
    _dateFilter = picked;
    _notifyFiltersChanged();
    if (_albumScrollController.hasClients) {
      await _albumScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  String _extension(String value) {
    final dot = value.lastIndexOf('.');
    if (dot <= 0 || dot == value.length - 1) return '';
    return value.substring(dot).toLowerCase();
  }

  Widget _buildFeatureTab({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String buttonText,
    required VoidCallback onTap,
  }) {
    return ListView(
      padding: EdgeInsets.fromLTRB(16.w, 18.h, 16.w, 24.h),
      children: [
        Container(
          padding: EdgeInsets.all(18.w),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 58.w,
                height: 58.w,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Icon(icon, color: color, size: 30.sp),
              ),
              SizedBox(width: 14.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 5.h),
                    Text(
                      subtitle,
                      style: TextStyle(
                        height: 1.3,
                        fontSize: 13.sp,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 14.h),
        ElevatedButton.icon(
          onPressed: onTap,
          icon: Icon(icon),
          label: Text(buttonText),
          style: ElevatedButton.styleFrom(
            minimumSize: Size.fromHeight(48.h),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.r),
            ),
          ),
        ),
      ],
    );
  }

  void _showUploadMenu() {
    if (!_ensureParentMode('请先切换到家长模式后再上传照片和视频')) {
      return;
    }
    if (_user.currentBaby.value == null) {
      ToastUtils.showWarning('请先在主页选择宝宝');
      return;
    }
    if (!_cloud.hasUsableCurrentSource) {
      _showSourceRequiredSheet();
      return;
    }
    Get.bottomSheet(
      SafeArea(
        child: SingleChildScrollView(
          child: Container(
            padding: EdgeInsets.fromLTRB(22.w, 18.h, 22.w, 20.h),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.98),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildUploadSheetHeader(),
                SizedBox(height: 18.h),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final itemWidth = constraints.maxWidth / 4;
                    return Wrap(
                      runSpacing: 14.h,
                      children: [
                        SizedBox(
                          width: itemWidth,
                          child: _actionItem(
                            label: '照片视频',
                            icon: Icons.photo_library,
                            color: const Color(0xFF39D16D),
                            onTap: _openMediaPicker,
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _actionItem(
                            label: '拍摄',
                            icon: Icons.camera_alt,
                            color: const Color(0xFFFF7A3D),
                            onTap: _openCameraPicker,
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _actionItem(
                            label: '录音',
                            icon: Icons.mic,
                            color: const Color(0xFF08CFA0),
                            onTap: _openAudioRecorder,
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _actionItem(
                            label: '日记',
                            icon: Icons.notes,
                            color: const Color(0xFFFF5F6D),
                            onTap: _openDiaryEditor,
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _actionItem(
                            label: '录音文件',
                            icon: Icons.audio_file,
                            color: const Color(0xFF6895FF),
                            onTap: _pickAudioFile,
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _actionItem(
                            label: '后台任务',
                            icon: Icons.task_alt,
                            color: const Color(0xFFFFB72B),
                            onTap: () {
                              Get.back();
                              Get.to(() => const BabyCloudUploadTasksPage());
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUploadSheetHeader() {
    final baby = _user.currentBaby.value;
    final now = DateTime.now();
    return Row(
      children: [
        Text(
          DateFormat('d').format(now),
          style: TextStyle(
            fontSize: 52.sp,
            fontWeight: FontWeight.w900,
            color: Colors.grey.shade700,
          ),
        ),
        SizedBox(width: 12.w),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _weekdayText(now),
              style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w800),
            ),
            Text(
              DateFormat('MM/yyyy').format(now),
              style: TextStyle(fontSize: 15.sp, color: Colors.grey.shade600),
            ),
            if (baby != null)
              Text(
                BabyProfileUtils.ageText(baby),
                style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w900),
              ),
          ],
        ),
        const Spacer(),
        Icon(Icons.toys_outlined, color: Colors.blue.shade200, size: 42.sp),
      ],
    );
  }

  Widget _actionItem({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18.r),
      child: SizedBox(
        height: 86.h,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 54.w,
              height: 54.w,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.22),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 27.sp),
            ),
            SizedBox(height: 7.h),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMediaPicker() async {
    if (!_ensureParentMode('请先切换到家长模式后再上传照片和视频')) {
      return;
    }
    Get.back();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final result = await Get.to(() => const BabyCloudMediaPickerPage());
    if (result == true) {
      _cloud.reloadLocalMedia();
      unawaited(_cloud.processQueue());
    }
  }

  Future<void> _openCameraPicker() async {
    if (!_ensureParentMode('请先切换到家长模式后再上传照片和视频')) {
      return;
    }
    final choice = await Get.bottomSheet<String>(
      SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(18.r)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('拍照'),
                onTap: () => Get.back(result: 'photo'),
              ),
              ListTile(
                leading: const Icon(Icons.videocam),
                title: const Text('录像'),
                onTap: () => Get.back(result: 'video'),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null) return;
    Get.back();
    final XFile? file = choice == 'video'
        ? await _imagePicker.pickVideo(source: ImageSource.camera)
        : await _imagePicker.pickImage(
            source: ImageSource.camera, imageQuality: 92);
    if (file == null) return;
    await Get.to(
      () => BabyCloudEntryEditPage(
        localMediaPath: file.path,
        localMediaType: choice,
        localMediaFileName: file.name,
      ),
    );
  }

  void _openAudioRecorder() {
    if (!_ensureParentMode('请先切换到家长模式后再上传录音')) {
      return;
    }
    Get.back();
    Get.to(() => const BabyCloudAudioRecordPage());
  }

  void _openDiaryEditor() {
    if (!_ensureParentMode('请先切换到家长模式后再新增日记')) {
      return;
    }
    Get.back();
    Get.to(() => const BabyCloudEntryEditPage(initialDiary: true));
  }

  Future<void> _pickAudioFile() async {
    if (!_ensureParentMode('请先切换到家长模式后再上传录音文件')) {
      return;
    }
    Get.back();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['m4a', 'mp3', 'aac', 'wav', 'ogg'],
    );
    final file = result?.files.single;
    final path = file?.path;
    if (file == null || path == null) return;
    await Get.to(
      () => BabyCloudEntryEditPage(
        audioPath: path,
        audioFileName: file.name,
      ),
    );
  }

  String _weekdayText(DateTime date) {
    const labels = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return labels[date.weekday - 1];
  }

  void _showSourceRequiredSheet() {
    Get.bottomSheet(
      Container(
        padding: EdgeInsets.fromLTRB(20.w, 18.h, 20.w, 24.h),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 44.sp, color: Colors.grey.shade500),
            SizedBox(height: 10.h),
            Text(
              _cloud.currentSourceSetupMessage,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 16.h),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: Get.back,
                    child: const Text('取消'),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (!_ensureParentMode('请先切换到家长模式后再配置亲宝宝数据源')) {
                        return;
                      }
                      Get.back();
                      Get.to(() => const BabyCloudSourcePage());
                    },
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('去配置'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _ensureParentMode(String message) {
    if (_mode.isParentMode) return true;
    ToastUtils.showWarning(message);
    return false;
  }
}
