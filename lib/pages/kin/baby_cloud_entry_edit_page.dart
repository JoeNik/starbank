import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../controllers/app_mode_controller.dart';
import '../../controllers/user_controller.dart';
import '../../models/baby.dart';
import '../../models/baby_cloud_media.dart';
import '../../services/baby_cloud_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/toast_utils.dart';
import 'baby_cloud_media_picker_page.dart';

class BabyCloudEntryEditPage extends StatefulWidget {
  const BabyCloudEntryEditPage({
    super.key,
    this.assets = const [],
    this.audioPath,
    this.audioFileName,
    this.localMediaPath,
    this.localMediaType,
    this.localMediaFileName,
    this.initialDiary = false,
    this.editingItems = const [],
  });

  final List<AssetEntity> assets;
  final String? audioPath;
  final String? audioFileName;
  final String? localMediaPath;
  final String? localMediaType;
  final String? localMediaFileName;
  final bool initialDiary;
  final List<BabyCloudMedia> editingItems;

  @override
  State<BabyCloudEntryEditPage> createState() => _BabyCloudEntryEditPageState();
}

class _BabyCloudEntryEditPageState extends State<BabyCloudEntryEditPage> {
  static const _actorRoles = [
    '妈妈',
    '爸爸',
    '爷爷',
    '奶奶',
    '外公',
    '外婆',
    '家人',
  ];

  final _cloud = Get.find<BabyCloudService>();
  final _mode = Get.find<AppModeController>();
  final _user = Get.find<UserController>();
  final _storage = Get.find<StorageService>();
  final _text = TextEditingController();
  final _tagInput = TextEditingController();
  final _location = TextEditingController();
  final _draftAssets = <AssetEntity>[];
  final _tags = <String>[];

  DateTime _recordTime = DateTime.now();
  String _visibility = 'family';
  late String _actorRole;
  bool _saving = false;
  bool _recordTimeManuallyEdited = false;

  bool get _isEditing => widget.editingItems.isNotEmpty;

  bool get _isDiary =>
      (_isEditing && widget.editingItems.every((item) => item.isDiary)) ||
      (widget.initialDiary &&
          _draftAssets.isEmpty &&
          widget.audioPath == null &&
          widget.localMediaPath == null);

  @override
  void initState() {
    super.initState();
    _draftAssets.addAll(widget.assets);
    _actorRole = _defaultActorRole;
    if (_isEditing) {
      final first = widget.editingItems.first;
      _text.text = first.description ?? '';
      _location.text = first.locationName ?? '';
      _tags.addAll(first.tags);
      _recordTime = first.takenAt;
      _visibility = first.visibility;
      _actorRole = first.actorRole?.trim().isNotEmpty == true
          ? first.actorRole!.trim()
          : _defaultActorRole;
    } else {
      _syncDefaultRecordTimeFromMedia(force: true);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _tagInput.dispose();
    _location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_mode.isParentMode) {
      return Scaffold(
        appBar: AppBar(title: const Text('编辑动态')),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24.w),
            child: Text(
              '请先切换到家长模式后再编辑亲宝宝动态',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15.sp, color: Colors.grey.shade700),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leadingWidth: 82.w,
        leading: TextButton(
          onPressed: _saving ? null : () => Get.back(result: false),
          child: const Text('取消'),
        ),
        centerTitle: true,
        title: Text(_isEditing ? '编辑动态' : (_isDiary ? '记日记' : '编辑动态')),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: 14.w),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFFC22D),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 18.w),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22.r),
                ),
              ),
              child: _saving
                  ? SizedBox.square(
                      dimension: 16.w,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('保存'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(28.w, 16.h, 28.w, 28.h),
        children: [
          TextField(
            controller: _text,
            maxLines: 5,
            minLines: 3,
            style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: '宝宝在笑、在跑… 还是发呆中？',
              hintStyle: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 19.sp,
                fontWeight: FontWeight.w800,
              ),
              border: InputBorder.none,
            ),
          ),
          if (!_isDiary) ...[
            SizedBox(height: 20.h),
            _buildPreview(),
          ],
          SizedBox(height: 28.h),
          Wrap(
            spacing: 10.w,
            runSpacing: 10.h,
            children: [
              _quickTag('第一次'),
              _tagButton(),
              for (final tag in _tags)
                InputChip(
                  label: Text(tag),
                  onDeleted: () => setState(() => _tags.remove(tag)),
                  backgroundColor: const Color(0xFFF6F6F6),
                  side: BorderSide.none,
                ),
            ],
          ),
          SizedBox(height: 28.h),
          _settingRow(
            icon: Icons.supervisor_account_outlined,
            title: '发布角色',
            value: _actorRole,
            onTap: _pickActorRole,
          ),
          _settingRow(
            icon: Icons.location_on_outlined,
            title: '所在位置',
            value:
                _location.text.trim().isEmpty ? '未填写' : _location.text.trim(),
            onTap: _editLocation,
          ),
          _settingRow(
            icon: Icons.schedule,
            title: '记录时间',
            value: DateFormat('yyyy-MM-dd HH:mm').format(_recordTime),
            onTap: _pickRecordTime,
          ),
        ],
      ),
    );
  }

  String get _defaultActorRole {
    final babyId = _user.currentBaby.value?.id;
    final key = babyId == null
        ? 'baby_cloud_actor_role'
        : 'baby_cloud_actor_role_$babyId';
    final value = _storage.settingsBox.get(key, defaultValue: '妈妈') as String;
    return _actorRoles.contains(value) ? value : '妈妈';
  }

  Widget _buildPreview() {
    if (_isEditing) {
      final mediaItems =
          widget.editingItems.where((item) => !item.isDiary).toList();
      if (mediaItems.isEmpty) return const SizedBox.shrink();
      return SizedBox(
        height: 92.h,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: mediaItems.length,
          separatorBuilder: (_, __) => SizedBox(width: 10.w),
          itemBuilder: (_, index) {
            final item = mediaItems[index];
            return ClipRRect(
              borderRadius: BorderRadius.circular(8.r),
              child: SizedBox(
                width: 92.h,
                height: 92.h,
                child: Image.file(
                  File(item.localThumbnailPath ?? item.localPath ?? ''),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: const Color(0xFFF3F3F3),
                    child: Icon(
                      item.isVideo
                          ? Icons.play_circle_fill
                          : item.isAudio
                              ? Icons.mic
                              : Icons.image_outlined,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    if (widget.audioPath != null) {
      return Container(
        height: 92.h,
        padding: EdgeInsets.symmetric(horizontal: 18.w),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7DD),
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24.r,
              backgroundColor: const Color(0xFFFFC22D),
              child: const Icon(Icons.mic, color: Colors.white),
            ),
            SizedBox(width: 14.w),
            Expanded(
              child: Text(
                widget.audioFileName ?? '录音文件',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      );
    }

    if (widget.localMediaPath != null) {
      final isVideo = widget.localMediaType == 'video';
      return ClipRRect(
        borderRadius: BorderRadius.circular(10.r),
        child: Container(
          width: 104.h,
          height: 104.h,
          color: const Color(0xFFF3F3F3),
          child: isVideo
              ? const Center(
                  child: Icon(Icons.play_circle_fill,
                      color: Colors.black54, size: 42),
                )
              : Image.file(
                  File(widget.localMediaPath!),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.broken_image_outlined),
                ),
        ),
      );
    }

    return SizedBox(
      height: 92.h,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _draftAssets.length + 1,
        separatorBuilder: (_, __) => SizedBox(width: 10.w),
        itemBuilder: (_, index) {
          if (index == _draftAssets.length) {
            return _buildAddAssetTile();
          }
          return _AssetPreview(asset: _draftAssets[index]);
        },
      ),
    );
  }

  Widget _buildAddAssetTile() {
    return Material(
      color: const Color(0xFFF3F3F3),
      borderRadius: BorderRadius.circular(8.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(8.r),
        onTap: _saving ? null : _pickMoreAssets,
        child: SizedBox(
          width: 92.h,
          height: 92.h,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_a_photo_outlined, color: Colors.grey.shade500),
              SizedBox(height: 6.h),
              Text(
                '继续添加',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickTag(String tag) {
    return ActionChip(
      label: Text('+ $tag'),
      side: BorderSide.none,
      backgroundColor: const Color(0xFFF5F5F5),
      onPressed: () {
        if (_tags.contains(tag)) return;
        setState(() => _tags.add(tag));
      },
    );
  }

  Widget _tagButton() {
    return ActionChip(
      label: const Text('+ 标签'),
      side: BorderSide.none,
      backgroundColor: const Color(0xFFF5F5F5),
      onPressed: _addTagDialog,
    );
  }

  Widget _settingRow({
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 18.h),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 26.sp, color: AppTheme.textMain),
            SizedBox(width: 18.w),
            Text(
              title,
              style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w900),
            ),
            const Spacer(),
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 16.sp,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  Future<void> _addTagDialog() async {
    _tagInput.clear();
    final tag = await Get.dialog<String>(
      AlertDialog(
        title: const Text('添加标签'),
        content: TextField(
          controller: _tagInput,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例如：露营、生日、第一次'),
          onSubmitted: (value) => Get.back(result: value),
        ),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('取消')),
          FilledButton(
            onPressed: () => Get.back(result: _tagInput.text),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    final clean = tag?.trim();
    if (clean == null || clean.isEmpty || _tags.contains(clean)) return;
    setState(() => _tags.add(clean));
  }

  Future<void> _editLocation() async {
    var draft = _location.text;
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('所在位置'),
          content: TextFormField(
            initialValue: draft,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              hintText: '例如：动物园、家里、公园',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => draft = value,
            onFieldSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(draft),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    if (!mounted || value == null) return;
    setState(() => _location.text = value.trim());
  }

  Future<void> _pickActorRole() async {
    final role = await Get.bottomSheet<String>(
      SafeArea(
        child: Container(
          padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 18.h),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              SizedBox(height: 12.h),
              for (final item in _actorRoles)
                ListTile(
                  leading: Icon(
                    item == _actorRole
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                    color: item == _actorRole
                        ? AppTheme.primaryDark
                        : Colors.grey.shade400,
                  ),
                  title: Text(item),
                  onTap: () => Get.back(result: item),
                ),
            ],
          ),
        ),
      ),
    );
    if (role == null || role == _actorRole) return;
    await _saveDefaultActorRole(role);
    if (!mounted) return;
    setState(() => _actorRole = role);
  }

  Future<void> _saveDefaultActorRole(String role) async {
    final babyId = _user.currentBaby.value?.id;
    final key = babyId == null
        ? 'baby_cloud_actor_role'
        : 'baby_cloud_actor_role_$babyId';
    await _storage.settingsBox.put(key, role);
  }

  Future<void> _pickRecordTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _recordTime,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_recordTime),
    );
    if (time == null) return;
    setState(() {
      _recordTimeManuallyEdited = true;
      _recordTime =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _pickMoreAssets() async {
    final result = await Get.to<List<AssetEntity>>(
      () => BabyCloudMediaPickerPage(
        initialAssets: _draftAssets,
        returnSelectionOnly: true,
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _draftAssets
        ..clear()
        ..addAll(result);
      _syncDefaultRecordTimeFromMedia();
    });
  }

  Future<void> _save() async {
    final baby = _user.currentBaby.value;
    if (baby == null) {
      ToastUtils.showWarning('请先在主页选择宝宝');
      return;
    }
    final text = _text.text.trim();
    if (_isDiary && text.isEmpty) {
      ToastUtils.showInfo('先写一点日记内容');
      return;
    }
    if (!_isDiary && !_hasAnyMedia) {
      ToastUtils.showInfo('请先选择照片或视频');
      return;
    }
    setState(() => _saving = true);
    final entryId = DateTime.now().microsecondsSinceEpoch.toString();
    final tags = List<String>.from(_tags);
    final location =
        _location.text.trim().isEmpty ? null : _location.text.trim();
    final actorRole = _actorRole.trim().isEmpty ? null : _actorRole.trim();

    if (_isEditing) {
      final entryId = widget.editingItems.first.entryId;
      try {
        final ok = await _cloud.queueEntryMetadataUpdate(
          entryId: entryId,
          baby: baby,
          description: text,
          takenAt: _recordTime,
          tags: tags,
          locationName: location,
          actorRole: actorRole,
          visibility: _visibility,
        );
        if (!ok) {
          ToastUtils.showError('保存失败：动态不存在或数据源不可用');
          if (mounted) setState(() => _saving = false);
          return;
        }
        ToastUtils.showSuccess('已保存，后台同步中');
        if (mounted) Get.until((route) => route.isFirst);
      } catch (e) {
        ToastUtils.showError('保存失败: $e');
        if (mounted) setState(() => _saving = false);
      }
      return;
    }

    unawaited(
      Future<void>(() async {
        if (_isDiary) {
          await _cloud.createDiaryEntry(
            baby: baby,
            description: text,
            takenAt: _recordTime,
            tags: tags,
            locationName: location,
            actorRole: actorRole,
            visibility: _visibility,
          );
        } else if (widget.audioPath != null) {
          await _queueAudio(
            baby: baby,
            entryId: entryId,
            description: text,
            tags: tags,
            locationName: location,
            actorRole: actorRole,
          );
        } else if (widget.localMediaPath != null) {
          await _queueLocalMedia(
            baby: baby,
            entryId: entryId,
            description: text,
            tags: tags,
            locationName: location,
            actorRole: actorRole,
          );
        } else {
          await _queueAssets(
            baby: baby,
            entryId: entryId,
            description: text,
            tags: tags,
            locationName: location,
            actorRole: actorRole,
          );
        }
      }).catchError((e) {
        ToastUtils.showError('保存到上传队列失败: $e');
      }),
    );
    ToastUtils.showSuccess('已保存，后台开始上传');
    if (mounted) {
      Get.until((route) => route.isFirst);
    }
  }

  Future<void> _queueAudio({
    required Baby baby,
    required String entryId,
    required String description,
    required List<String> tags,
    required String? locationName,
    required String? actorRole,
  }) async {
    final path = widget.audioPath;
    if (path == null) return;
    final file = File(path);
    if (!await file.exists()) return;
    final hash = await _hashFile(file);
    final cachedPath = await _copyLocalFile(
        file, hash, widget.audioFileName ?? file.uri.pathSegments.last);
    await _cloud.queueUpload(
      baby: baby,
      localPath: cachedPath ?? file.path,
      fileName: widget.audioFileName ?? file.uri.pathSegments.last,
      mediaType: 'audio',
      mimeType: 'audio/mp4',
      takenAt: _recordTime,
      sha256Hash: hash,
      entryId: entryId,
      description: description,
      tags: tags,
      locationName: locationName,
      actorRole: actorRole,
      visibility: _visibility,
    );
  }

  Future<void> _queueLocalMedia({
    required Baby baby,
    required String entryId,
    required String description,
    required List<String> tags,
    required String? locationName,
    required String? actorRole,
  }) async {
    final path = widget.localMediaPath;
    if (path == null) return;
    final file = File(path);
    if (!await file.exists()) return;
    final fileName = widget.localMediaFileName ?? file.uri.pathSegments.last;
    final hash = await _hashFile(file);
    final cachedPath = await _copyLocalFile(file, hash, fileName);
    await _cloud.queueUpload(
      baby: baby,
      localPath: cachedPath ?? file.path,
      fileName: fileName,
      mediaType: widget.localMediaType ?? 'photo',
      takenAt: _recordTime,
      sha256Hash: hash,
      entryId: entryId,
      description: description,
      tags: tags,
      locationName: locationName,
      actorRole: actorRole,
      visibility: _visibility,
    );
  }

  Future<void> _queueAssets({
    required Baby baby,
    required String entryId,
    required String description,
    required List<String> tags,
    required String? locationName,
    required String? actorRole,
  }) async {
    for (final asset in _draftAssets) {
      final file = await asset.file;
      if (file == null || !await file.exists()) continue;
      final name = asset.title ?? file.uri.pathSegments.last;
      final hash = await _hashFile(file);
      final cachedPath = await _copyLocalFile(file, hash, name);
      final thumbnailPath = await _saveLocalThumbnail(asset, hash);
      await _cloud.queueUpload(
        baby: baby,
        localPath: cachedPath ?? file.path,
        fileName: name,
        mediaType: asset.type == AssetType.video ? 'video' : 'photo',
        takenAt: _recordTime,
        sha256Hash: hash,
        localThumbnailPath: thumbnailPath,
        entryId: entryId,
        description: description,
        tags: tags,
        locationName: locationName,
        actorRole: actorRole,
        visibility: _visibility,
      );
    }
  }

  Future<String> _hashFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  Future<String?> _copyLocalFile(
      File source, String hash, String fileName) async {
    try {
      final base = await getApplicationDocumentsDirectory();
      final dir =
          Directory('${base.path}${Platform.pathSeparator}baby_cloud_media');
      await dir.create(recursive: true);
      final ext = _extension(fileName).isNotEmpty
          ? _extension(fileName)
          : _extension(source.path);
      final target = File(
          '${dir.path}${Platform.pathSeparator}${_safeFileName(hash)}$ext');
      if (await target.exists() && await target.length() > 0)
        return target.path;
      await source.copy(target.path);
      return target.path;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _saveLocalThumbnail(AssetEntity asset, String hash) async {
    try {
      final bytes = await asset.thumbnailDataWithSize(
        const ThumbnailSize.square(360),
        quality: 62,
      );
      if (bytes == null || bytes.isEmpty) return null;
      final base = await getApplicationDocumentsDirectory();
      final dir = Directory(
          '${base.path}${Platform.pathSeparator}baby_cloud_thumbnails');
      await dir.create(recursive: true);
      final file = File(
          '${dir.path}${Platform.pathSeparator}${_safeFileName(hash)}_360_q62.jpg');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  String _safeFileName(String value) {
    final clean = value.trim().isEmpty ? 'item' : value.trim();
    return clean.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
  }

  String _extension(String value) {
    final dot = value.lastIndexOf('.');
    if (dot <= 0 || dot == value.length - 1) return '';
    return value.substring(dot).toLowerCase();
  }

  bool get _hasAnyMedia {
    if (_isEditing) {
      return widget.editingItems.any((item) => !item.isDiary);
    }
    return widget.audioPath != null ||
        widget.localMediaPath != null ||
        _draftAssets.isNotEmpty;
  }

  void _syncDefaultRecordTimeFromMedia({bool force = false}) {
    if (_isEditing || (!force && _recordTimeManuallyEdited)) return;
    final mediaTime = _defaultRecordTimeFromMedia();
    if (mediaTime == null) return;
    _recordTime = mediaTime;
  }

  DateTime? _defaultRecordTimeFromMedia() {
    if (_draftAssets.isNotEmpty) {
      final createdAt = _draftAssets.last.createDateTime;
      if (createdAt.millisecondsSinceEpoch > 0) {
        return createdAt.toLocal();
      }
    }

    final localPath = widget.localMediaPath ?? widget.audioPath;
    if (localPath == null || localPath.trim().isEmpty) return null;
    try {
      return File(localPath).lastModifiedSync().toLocal();
    } catch (_) {
      return null;
    }
  }
}

class _AssetPreview extends StatefulWidget {
  const _AssetPreview({required this.asset});

  final AssetEntity asset;

  @override
  State<_AssetPreview> createState() => _AssetPreviewState();
}

class _AssetPreviewState extends State<_AssetPreview> {
  late Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.asset.thumbnailDataWithSize(
      const ThumbnailSize.square(240),
      quality: 78,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8.r),
      child: SizedBox(
        width: 92.h,
        height: 92.h,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<Uint8List?>(
              future: _future,
              builder: (_, snapshot) {
                final bytes = snapshot.data;
                if (bytes == null)
                  return Container(color: const Color(0xFFF3F3F3));
                return Image.memory(bytes, fit: BoxFit.cover);
              },
            ),
            if (widget.asset.type == AssetType.video)
              const Center(
                child:
                    Icon(Icons.play_circle_fill, color: Colors.white, size: 34),
              ),
          ],
        ),
      ),
    );
  }
}
