import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';

import '../controllers/app_mode_controller.dart';
import '../controllers/user_controller.dart';
import '../models/baby_cloud_entry.dart';
import '../models/baby_cloud_media.dart';
import '../models/milestone_record.dart';
import '../models/openai_config.dart';
import '../services/baby_cloud_service.dart';
import '../services/openai_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../utils/baby_profile_utils.dart';
import '../widgets/baby_cloud_media_thumbnail.dart';
import '../widgets/image_utils.dart';
import '../widgets/toast_utils.dart';
import 'kin/baby_cloud_entry_detail_page.dart';
import 'openai_settings_page.dart';

class MilestonePage extends StatefulWidget {
  const MilestonePage({super.key});

  @override
  State<MilestonePage> createState() => _MilestonePageState();
}

class _CloudMilestoneEntry {
  const _CloudMilestoneEntry({
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

class _MilestoneTimelineItem {
  const _MilestoneTimelineItem.record(this.record) : cloudEntry = null;
  const _MilestoneTimelineItem.cloud(this.cloudEntry) : record = null;

  final MilestoneRecord? record;
  final _CloudMilestoneEntry? cloudEntry;

  DateTime get date => record?.recordDate ?? cloudEntry!.takenAt;
}

class _MilestonePageState extends State<MilestonePage> {
  static const _defaultCategories = [
    '第一次',
    '徒步',
    '露营',
    '旅行',
    '运动会',
    '演出',
    '节日',
    '成长MV',
  ];

  final _storage = Get.find<StorageService>();
  final _user = Get.find<UserController>();
  final _mode = Get.find<AppModeController>();
  final _openAI = Get.find<OpenAIService>();
  final _cloud = Get.isRegistered<BabyCloudService>()
      ? Get.find<BabyCloudService>()
      : Get.put(BabyCloudService());

  late Box _settingsBox;
  OpenAIConfig? _selectedConfig;
  String _selectedModel = '';
  String _selectedCategory = '';
  String _selectedTag = '';
  List<MilestoneRecord> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _cloud.init();
    _settingsBox = await Hive.openBox('milestone_record_settings');
    final configId = _settingsBox.get('selected_config_id', defaultValue: '');
    _selectedModel = _settingsBox.get('selected_model', defaultValue: '');
    _selectedConfig =
        _openAI.configs.firstWhereOrNull((c) => c.id == configId) ??
            _openAI.currentConfig.value;
    if (_selectedModel.isEmpty) {
      _selectedModel = _selectedConfig?.selectedModel ?? '';
    }
    _loadRecords();
    setState(() => _loading = false);
  }

  void _loadRecords() {
    final babyId = _user.currentBaby.value?.id;
    if (babyId == null) {
      _records = [];
      return;
    }
    _records = _storage.milestoneRecordBox.values
        .where((r) => r.babyId == babyId && !r.isDeleted)
        .toList()
      ..sort((a, b) => b.recordDate.compareTo(a.recordDate));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('宝宝大事记'),
        actions: [
          IconButton(
            tooltip: 'AI 模型',
            icon: const Icon(Icons.smart_toy_outlined),
            onPressed: _showAISelector,
          ),
          IconButton(
            tooltip: '回收站',
            icon: const Icon(Icons.delete_outline),
            onPressed: _showRecycleBin,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'manual') _showEditor();
              if (value == 'ocr') _importFromScreenshot();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'manual', child: Text('手动添加')),
              PopupMenuItem(value: 'ocr', child: Text('从截图识别导入')),
            ],
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildCategoryBar(),
                Expanded(child: _buildTimeline()),
              ],
            ),
    );
  }

  Widget _buildCategoryBar() {
    return Obx(() {
      final babyId = _user.currentBaby.value?.id;
      final cloudTags = babyId == null ? const <String>[] : _cloudTags(babyId);
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
        child: Row(
          children: [
            ChoiceChip(
              label: const Text('全部'),
              selected: _selectedCategory.isEmpty && _selectedTag.isEmpty,
              onSelected: (_) => setState(() {
                _selectedCategory = '';
                _selectedTag = '';
                _loadRecords();
              }),
            ),
            SizedBox(width: 8.w),
            ..._defaultCategories.map(
              (c) => Padding(
                padding: EdgeInsets.only(right: 8.w),
                child: ChoiceChip(
                  label: Text(c),
                  selected: _selectedCategory == c,
                  onSelected: (_) => setState(() {
                    _selectedCategory = c;
                    _selectedTag = '';
                    _loadRecords();
                  }),
                ),
              ),
            ),
            if (cloudTags.isNotEmpty) ...[
              SizedBox(width: 6.w),
              VerticalDivider(
                width: 12.w,
                thickness: 1,
                color: Colors.grey.shade300,
              ),
              ...cloudTags.map(
                (tag) => Padding(
                  padding: EdgeInsets.only(right: 8.w),
                  child: ChoiceChip(
                    label: Text('#$tag'),
                    selected: _selectedTag == tag,
                    onSelected: (_) => setState(() {
                      _selectedCategory = '';
                      _selectedTag = tag;
                      _loadRecords();
                    }),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    });
  }

  Widget _buildTimeline() {
    return Obx(() {
      final babyId = _user.currentBaby.value?.id;
      final items = <_MilestoneTimelineItem>[
        for (final record in _records)
          if (_matchesRecordFilters(record))
            _MilestoneTimelineItem.record(record),
        if (babyId != null)
          for (final entry in _cloudTimelineEntriesFor(babyId))
            if (_matchesCloudEntryFilters(entry))
              _MilestoneTimelineItem.cloud(entry),
      ]..sort((a, b) => b.date.compareTo(a.date));

      if (items.isEmpty) {
        final filtered =
            _selectedCategory.isNotEmpty || _selectedTag.isNotEmpty;
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.flag_outlined,
                  size: 64.sp, color: Colors.grey.shade300),
              SizedBox(height: 12.h),
              Text(filtered ? '没有匹配的大事记' : '还没有大事记'),
              if (!_mode.isChildMode) ...[
                SizedBox(height: 16.h),
                ElevatedButton.icon(
                  onPressed: _showEditor,
                  icon: const Icon(Icons.add),
                  label: const Text('添加大事记'),
                ),
              ],
            ],
          ),
        );
      }

      return ListView.builder(
        padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
        itemCount: items.length,
        itemBuilder: (_, index) {
          final item = items[index];
          final cloudEntry = item.cloudEntry;
          if (cloudEntry != null) {
            return _buildCloudTimelineRow(cloudEntry);
          }
          return _buildRecordTimelineRow(item.record!);
        },
      );
    });
  }

  Widget _buildRecordTimelineRow(MilestoneRecord record) {
    final tags = _effectiveTags(record);
    return _buildTimelineRow(
      lineHeight: 130.h,
      child: Card(
        margin: EdgeInsets.only(bottom: 14.h),
        child: InkWell(
          onTap: () => _showEditor(record: record),
          child: Padding(
            padding: EdgeInsets.all(14.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      DateFormat('yyyy-MM-dd').format(record.recordDate),
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12.sp,
                      ),
                    ),
                    const Spacer(),
                    Chip(
                      label: Text(record.category),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                SizedBox(height: 8.h),
                Text(
                  record.title,
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (record.description.isNotEmpty) ...[
                  SizedBox(height: 8.h),
                  Text(record.description, maxLines: 3),
                ],
                if (tags.isNotEmpty) ...[
                  SizedBox(height: 8.h),
                  Wrap(
                    spacing: 6.w,
                    runSpacing: 4.h,
                    children: tags
                        .map(
                          (tag) => Chip(
                            label: Text('#$tag'),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        )
                        .toList(),
                  ),
                ],
                if (record.mediaRefs.isNotEmpty) ...[
                  SizedBox(height: 10.h),
                  Text(
                    '关联媒体 ${record.mediaRefs.length} 个',
                    style: TextStyle(
                      color: AppTheme.primaryDark,
                      fontSize: 12.sp,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCloudTimelineRow(_CloudMilestoneEntry entry) {
    final tags = _effectiveCloudTags(entry);
    final mediaItems = entry.mediaItems.where((item) => !item.isDiary).toList();
    final firstMedia = mediaItems.isEmpty ? null : mediaItems.first;
    final description = _cloudEntryDescription(entry);
    final title = _cloudEntryTitle(entry, tags, description);
    final baby = _user.currentBaby.value;
    final ageText =
        baby == null ? '' : BabyProfileUtils.ageText(baby, now: entry.takenAt);

    return _buildTimelineRow(
      lineHeight: firstMedia == null ? 132.h : 150.h,
      child: Card(
        margin: EdgeInsets.only(bottom: 14.h),
        child: InkWell(
          onTap: () => Get.to(
            () => BabyCloudEntryDetailPage(
              entry: entry.entry,
              mediaItems: entry.mediaItems,
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(12.w),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              ageText.isEmpty
                                  ? DateFormat('yyyy-MM-dd')
                                      .format(entry.takenAt)
                                  : ageText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12.sp,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Chip(
                            label: const Text('云相册'),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ],
                      ),
                      SizedBox(height: 8.h),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (description.isNotEmpty && description != title) ...[
                        SizedBox(height: 7.h),
                        Text(
                          description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (tags.isNotEmpty) ...[
                        SizedBox(height: 8.h),
                        Wrap(
                          spacing: 6.w,
                          runSpacing: 4.h,
                          children: tags
                              .map(
                                (tag) => Chip(
                                  label: Text('#$tag'),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  backgroundColor: const Color(0xFFFFF4D0),
                                  side: BorderSide.none,
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                if (firstMedia != null) ...[
                  SizedBox(width: 12.w),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8.r),
                    child: SizedBox(
                      width: 94.w,
                      height: 94.w,
                      child: BabyCloudMediaThumbnail(
                        item: firstMedia,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimelineRow({
    required Widget child,
    required double lineHeight,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 12.w,
              height: 12.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.amber, width: 3),
              ),
            ),
            Container(
                width: 2, height: lineHeight, color: Colors.grey.shade200),
          ],
        ),
        SizedBox(width: 12.w),
        Expanded(child: child),
      ],
    );
  }

  Future<void> _showEditor({MilestoneRecord? record}) async {
    final baby = _user.currentBaby.value;
    if (baby == null) return;
    final date = (record?.recordDate ?? DateTime.now()).obs;
    final title = TextEditingController(text: record?.title ?? '');
    final category = (record?.category ?? _defaultCategories.first).obs;
    final customCategory = TextEditingController();
    final description = TextEditingController(text: record?.description ?? '');
    final tagInput = TextEditingController();
    final refs = (record?.mediaRefs.toList() ?? <String>[]).obs;
    final tags = (<String>{
      ...?record?.tags,
      ..._tagsFromMediaRefs(record?.mediaRefs ?? const <String>[]),
      if (record != null) ..._autoCloudTagsForRecord(record),
    }.toList()
          ..sort())
        .obs;
    final tagSuggestions = _cloudTags(baby.id);

    void addTag(String value) {
      final clean = _cleanTag(value);
      if (clean.isEmpty || tags.contains(clean)) return;
      tags.add(clean);
      tags.sort();
      tagInput.clear();
    }

    await Get.defaultDialog(
      title: record == null ? '添加大事记' : '编辑大事记',
      contentPadding: EdgeInsets.all(20.w),
      content: SingleChildScrollView(
        child: Column(
          children: [
            Obx(
              () => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today),
                title: Text(DateFormat('yyyy-MM-dd').format(date.value)),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: date.value,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (picked != null) date.value = picked;
                },
              ),
            ),
            TextField(
              controller: title,
              decoration: const InputDecoration(
                labelText: '标题',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 10.h),
            Obx(
              () => DropdownButtonFormField<String>(
                value: _defaultCategories.contains(category.value)
                    ? category.value
                    : '自定义',
                decoration: const InputDecoration(
                  labelText: '分类',
                  border: OutlineInputBorder(),
                ),
                items: [
                  ..._defaultCategories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c))),
                  const DropdownMenuItem(value: '自定义', child: Text('自定义')),
                ],
                onChanged: (value) {
                  if (value == '自定义') {
                    category.value = customCategory.text.trim().isEmpty
                        ? '自定义'
                        : customCategory.text.trim();
                  } else {
                    category.value = value ?? _defaultCategories.first;
                  }
                },
              ),
            ),
            SizedBox(height: 10.h),
            TextField(
              controller: customCategory,
              decoration: const InputDecoration(
                labelText: '自定义分类（可选）',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                if (value.trim().isNotEmpty) category.value = value.trim();
              },
            ),
            SizedBox(height: 10.h),
            TextField(
              controller: description,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '描述',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 10.h),
            Obx(
              () => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '标签',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(height: 6.h),
                  if (tags.isEmpty && tagSuggestions.isEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '关联云相册动态后会自动同步标签',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12.sp,
                        ),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8.w,
                      runSpacing: 6.h,
                      children: [
                        for (final tag in tags)
                          Chip(
                            label: Text('#$tag'),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () => tags.remove(tag),
                            visualDensity: VisualDensity.compact,
                          ),
                        for (final tag in tagSuggestions)
                          if (!tags.contains(tag))
                            ActionChip(
                              label: Text('#$tag'),
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                tags.add(tag);
                                tags.sort();
                              },
                            ),
                      ],
                    ),
                  SizedBox(height: 8.h),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: tagInput,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            hintText: '手动输入标签',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: addTag,
                        ),
                      ),
                      SizedBox(width: 8.w),
                      IconButton.filledTonal(
                        tooltip: '添加标签',
                        onPressed: () => addTag(tagInput.text),
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  SizedBox(height: 6.h),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '保存时会自动匹配同名云相册标签，并关联对应媒体。',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12.sp,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 10.h),
            Obx(
              () => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.photo_library_outlined),
                title: Text('关联亲宝宝媒体 ${refs.length} 个'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final selected = await _selectCloudMedia(refs.toList());
                  if (selected != null) {
                    refs.assignAll(selected);
                    final merged = <String>{
                      ...tags,
                      ..._tagsFromMediaRefs(selected),
                    }.toList()
                      ..sort();
                    tags.assignAll(merged);
                  }
                },
              ),
            ),
          ],
        ),
      ),
      confirm: ElevatedButton(
        onPressed: () async {
          final now = DateTime.now();
          final cleanTitle = title.text.trim();
          if (cleanTitle.isEmpty) {
            ToastUtils.showInfo('先写一个大事记标题');
            return;
          }
          final cat = customCategory.text.trim().isNotEmpty
              ? customCategory.text.trim()
              : category.value;
          final finalTags = _normalizedTags({
            ...tags,
            ..._autoCloudTagsForDraft(
              babyId: baby.id,
              title: title.text,
              category: cat,
              description: description.text,
            ),
          });
          final finalRefs = _normalizedRefs({
            ...refs,
            ..._refsForTags(baby.id, finalTags),
          });
          final item = record ??
              MilestoneRecord(
                id: now.microsecondsSinceEpoch.toString(),
                babyId: baby.id,
                recordDate: date.value,
                title: cleanTitle,
              );
          item
            ..recordDate = date.value
            ..title = cleanTitle
            ..category = cat == '自定义' ? '第一次' : cat
            ..description = description.text.trim()
            ..mediaRefs = finalRefs
            ..coverMediaRef = finalRefs.isEmpty ? null : finalRefs.first
            ..tags = finalTags
            ..updatedAt = now;
          await _storage.milestoneRecordBox.put(item.id, item);
          Get.back();
          setState(_loadRecords);
        },
        child: const Text('保存'),
      ),
      cancel: record == null
          ? TextButton(onPressed: Get.back, child: const Text('取消'))
          : TextButton(
              onPressed: () async {
                record.deletedAt = DateTime.now();
                record.updatedAt = DateTime.now();
                await record.save();
                Get.back();
                setState(_loadRecords);
              },
              child: const Text('移到回收站'),
            ),
    );
  }

  Future<List<String>?> _selectCloudMedia(List<String> initial) async {
    final babyId = _user.currentBaby.value?.id;
    if (babyId == null) return null;
    final selected = initial.toSet().obs;
    final items = _cloud.mediaForBaby(babyId);
    return Get.bottomSheet<List<String>>(
      Container(
        height: 560.h,
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
        ),
        child: Column(
          children: [
            const Text('选择亲宝宝媒体',
                style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('当前数据源暂无可关联媒体'))
                  : GridView.builder(
                      padding: EdgeInsets.only(top: 12.h),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 6.h,
                        crossAxisSpacing: 6.w,
                      ),
                      itemCount: items.length,
                      itemBuilder: (_, index) {
                        final item = items[index];
                        return Obx(
                          () {
                            final active = selected.contains(item.ref);
                            return GestureDetector(
                              onTap: () {
                                if (active) {
                                  selected.remove(item.ref);
                                } else {
                                  selected.add(item.ref);
                                }
                              },
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Container(
                                    color: Colors.grey.shade200,
                                    child: item.localPath != null
                                        ? ImageUtils.displayImage(
                                            item.localPath,
                                            fit: BoxFit.cover,
                                          )
                                        : Icon(item.isVideo
                                            ? Icons.videocam
                                            : Icons.image),
                                  ),
                                  if (active)
                                    Container(
                                      color: AppTheme.primary.withOpacity(0.35),
                                      child: const Icon(Icons.check_circle,
                                          color: Colors.white),
                                    ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Get.back(result: selected.toList()),
                child: const Text('确定'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<String> _cloudTags(String babyId) {
    return _normalizedTags([
      for (final entry in _cloud.entriesForBaby(babyId)) ...entry.tags,
      for (final item in _cloud.mediaForBaby(babyId)) ...item.tags,
    ]);
  }

  List<String> _tagsFromMediaRefs(List<String> refs) {
    if (refs.isEmpty) return const [];
    final refSet = refs.toSet();
    final entriesById = {
      for (final entry in _cloud.entries) entry.id: entry,
    };
    return _normalizedTags(
      _cloud.media.where((item) => refSet.contains(item.ref)).expand(
            (item) => [
              ...item.tags,
              ...?entriesById[item.entryId]?.tags,
            ],
          ),
    );
  }

  List<String> _effectiveTags(MilestoneRecord record) {
    return _normalizedTags({
      ...record.tags.map((tag) => tag.trim()).where((tag) => tag.isNotEmpty),
      ..._tagsFromMediaRefs(record.mediaRefs),
      ..._autoCloudTagsForRecord(record),
    });
  }

  List<String> _autoCloudTagsForRecord(MilestoneRecord record) {
    return _autoCloudTagsForDraft(
      babyId: record.babyId,
      title: record.title,
      category: record.category,
      description: record.description,
    );
  }

  List<String> _autoCloudTagsForDraft({
    required String babyId,
    required String title,
    required String category,
    required String description,
  }) {
    final haystack = '$title $category $description'.toLowerCase();
    if (haystack.trim().isEmpty) return const [];
    return _cloudTags(babyId)
        .where((tag) => haystack.contains(tag.toLowerCase()))
        .toList();
  }

  List<String> _refsForTags(String babyId, List<String> tags) {
    final tagSet = tags
        .map((tag) => _cleanTag(tag).toLowerCase())
        .where((tag) => tag.isNotEmpty)
        .toSet();
    if (tagSet.isEmpty) return const [];
    final entriesById = {
      for (final entry in _cloud.entriesForBaby(babyId)) entry.id: entry,
    };
    final refs = _cloud.mediaForBaby(babyId).where(
      (item) {
        final itemTags = _normalizedTags([
          ...item.tags,
          ...?entriesById[item.entryId]?.tags,
        ]);
        return itemTags.any((tag) => tagSet.contains(tag.toLowerCase()));
      },
    ).map((item) => item.ref);
    return _normalizedRefs(refs);
  }

  List<_CloudMilestoneEntry> _cloudTimelineEntriesFor(String babyId) {
    final mediaItems = _cloud.mediaForBaby(babyId);
    final result = <_CloudMilestoneEntry>[];
    final usedMediaIds = <String>{};

    for (final entry in _cloud.entriesForBaby(babyId)) {
      final mediaIds = entry.mediaIds.toSet();
      final entryMedia = mediaItems
          .where(
            (item) => item.entryId == entry.id || mediaIds.contains(item.id),
          )
          .toList()
        ..sort((a, b) => a.takenAt.compareTo(b.takenAt));
      usedMediaIds.addAll(entryMedia.map((item) => item.id));
      final timelineEntry = _CloudMilestoneEntry(
        entry: entry,
        mediaItems: entryMedia,
      );
      if (_effectiveCloudTags(timelineEntry).isNotEmpty) {
        result.add(timelineEntry);
      }
    }

    final fallbackGroups = <String, List<BabyCloudMedia>>{};
    for (final item in mediaItems) {
      if (usedMediaIds.contains(item.id)) continue;
      fallbackGroups.putIfAbsent(item.entryId, () => []).add(item);
    }
    for (final items in fallbackGroups.values) {
      items.sort((a, b) => a.takenAt.compareTo(b.takenAt));
      final timelineEntry = _CloudMilestoneEntry(
        entry: null,
        mediaItems: items,
      );
      if (_effectiveCloudTags(timelineEntry).isNotEmpty) {
        result.add(timelineEntry);
      }
    }

    return result..sort((a, b) => b.takenAt.compareTo(a.takenAt));
  }

  bool _matchesRecordFilters(MilestoneRecord record) {
    final tags = _effectiveTags(record);
    if (_selectedTag.isNotEmpty) return tags.contains(_selectedTag);
    if (_selectedCategory.isNotEmpty) {
      return record.category == _selectedCategory ||
          tags.contains(_selectedCategory);
    }
    return true;
  }

  bool _matchesCloudEntryFilters(_CloudMilestoneEntry entry) {
    final tags = _effectiveCloudTags(entry);
    if (tags.isEmpty) return false;
    if (_selectedTag.isNotEmpty) return tags.contains(_selectedTag);
    if (_selectedCategory.isNotEmpty) return tags.contains(_selectedCategory);
    return true;
  }

  List<String> _effectiveCloudTags(_CloudMilestoneEntry entry) {
    return _normalizedTags([
      ...?entry.entry?.tags,
      for (final item in entry.mediaItems) ...item.tags,
    ]);
  }

  String _cloudEntryDescription(_CloudMilestoneEntry entry) {
    final entryText = entry.entry?.description?.trim() ?? '';
    if (entryText.isNotEmpty) return entryText;
    for (final item in entry.mediaItems) {
      final text = item.description?.trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  String _cloudEntryTitle(
    _CloudMilestoneEntry entry,
    List<String> tags,
    String description,
  ) {
    if (tags.isNotEmpty) return tags.join(' · ');
    if (description.isNotEmpty) return description;
    return switch (entry.entry?.entryType) {
      'diary' => '文字动态',
      'audio' => '录音动态',
      _ => '云相册动态',
    };
  }

  List<String> _normalizedTags(Iterable<String> values) {
    final tags = values
        .map(_cleanTag)
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return tags;
  }

  List<String> _normalizedRefs(Iterable<String> values) {
    final refs = values
        .map((ref) => ref.trim())
        .where((ref) => ref.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return refs;
  }

  String _cleanTag(String value) {
    return value.trim().replaceFirst(RegExp(r'^#+'), '').trim();
  }

  Future<void> _importFromScreenshot() async {
    if (_selectedConfig == null) {
      _showMissingAI();
      return;
    }
    final baby = _user.currentBaby.value;
    if (baby == null) return;
    final image = await ImageUtils.pickImageAndToBase64();
    if (image == null) return;
    Get.dialog(const Center(child: CircularProgressIndicator()),
        barrierDismissible: false);
    try {
      final response = await _openAI.chatWithImage(
        systemPrompt: '你是一个严谨的 OCR 助手，只返回 JSON，不要解释。',
        userMessage:
            '识别这张宝宝大事记截图，返回 JSON：{"date":"yyyy-MM-dd","title":"标题","category":"分类","description":"描述"}。分类优先从第一次、徒步、露营、旅行、运动会、演出、节日、成长MV中选择，无法确定用第一次。',
        imageBase64: image,
        config: _selectedConfig,
        model: _selectedModel.isNotEmpty ? _selectedModel : null,
      );
      Get.back();
      final data = _extractJson(response);
      final record = MilestoneRecord(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        babyId: baby.id,
        recordDate:
            DateTime.tryParse(data['date']?.toString() ?? '') ?? DateTime.now(),
        title: data['title']?.toString() ?? '',
        category: data['category']?.toString() ?? '第一次',
        description: data['description']?.toString() ?? '',
        sourceImagePath: image,
      );
      await _showEditor(record: record);
    } catch (e) {
      Get.back();
      ToastUtils.showError(
        '截图识别失败：$e\n当前模型可能不支持图片识别，请切换支持视觉的模型后重试。',
      );
    }
  }

  Map<String, dynamic> _extractJson(String response) {
    var text = response.trim();
    if (text.startsWith('```')) {
      text = text.replaceFirst(RegExp(r'^```json\s*|^```\s*'), '');
      if (text.endsWith('```')) text = text.substring(0, text.length - 3);
    }
    return _asJsonObject(jsonDecode(text.trim()));
  }

  Map<String, dynamic> _asJsonObject(dynamic value) {
    if (value is Map) {
      for (final key in const [
        'data',
        'result',
        'record',
        'records',
        'items'
      ]) {
        final nested = value[key];
        if (nested is Map || nested is List) return _asJsonObject(nested);
      }
      return Map<String, dynamic>.from(value);
    }
    if (value is List) {
      for (final item in value) {
        if (item is Map || item is List) return _asJsonObject(item);
      }
    }
    throw const FormatException('AI 返回的 JSON 中没有可用记录');
  }

  Future<void> _showAISelector() async {
    OpenAIConfig? selected = _selectedConfig;
    String model = _selectedModel;
    await Get.bottomSheet(
      StatefulBuilder(
        builder: (context, setSheetState) {
          final models = selected?.models ?? const <String>[];
          return Container(
            padding: EdgeInsets.all(20.w),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text('大事记 AI',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Get.to(() => const OpenAISettingsPage()),
                      child: const Text('管理'),
                    ),
                  ],
                ),
                DropdownButtonFormField<OpenAIConfig>(
                  value: selected,
                  decoration: const InputDecoration(labelText: '接口'),
                  items: _openAI.configs
                      .map((c) =>
                          DropdownMenuItem(value: c, child: Text(c.name)))
                      .toList(),
                  onChanged: (value) {
                    setSheetState(() {
                      selected = value;
                      model = value?.selectedModel ?? '';
                    });
                  },
                ),
                SizedBox(height: 12.h),
                DropdownButtonFormField<String>(
                  value: models.contains(model) ? model : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '模型'),
                  items: models
                      .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (value) =>
                      setSheetState(() => model = value ?? ''),
                ),
                SizedBox(height: 16.h),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      _selectedConfig = selected;
                      _selectedModel = model;
                      if (selected != null) {
                        await _settingsBox.put(
                            'selected_config_id', selected!.id);
                      }
                      await _settingsBox.put('selected_model', model);
                      if (mounted) setState(() {});
                      Get.back();
                    },
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showMissingAI() {
    Get.defaultDialog(
      title: '未配置 AI',
      middleText: '请先添加 OpenAI 兼容接口，或在本页面选择可识别图片的模型。',
      textConfirm: '去设置',
      textCancel: '取消',
      onConfirm: () {
        Get.back();
        Get.to(() => const OpenAISettingsPage());
      },
    );
  }

  Future<void> _showRecycleBin() async {
    final babyId = _user.currentBaby.value?.id;
    if (babyId == null) return;
    final deleted = _storage.milestoneRecordBox.values
        .where((r) => r.babyId == babyId && r.isDeleted)
        .toList()
      ..sort((a, b) =>
          (b.deletedAt ?? b.updatedAt).compareTo(a.deletedAt ?? a.updatedAt));
    await Get.bottomSheet(
      Container(
        height: 520.h,
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
        ),
        child: Column(
          children: [
            const Text('大事记回收站', style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: deleted.isEmpty
                  ? const Center(child: Text('回收站为空'))
                  : ListView.builder(
                      itemCount: deleted.length,
                      itemBuilder: (_, index) {
                        final record = deleted[index];
                        return ListTile(
                          title: Text(record.title),
                          subtitle: Text(DateFormat('yyyy-MM-dd')
                              .format(record.recordDate)),
                          trailing: Wrap(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.restore),
                                onPressed: () async {
                                  record.deletedAt = null;
                                  record.updatedAt = DateTime.now();
                                  await record.save();
                                  Get.back();
                                  setState(_loadRecords);
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_forever),
                                onPressed: () async {
                                  await record.delete();
                                  Get.back();
                                  setState(_loadRecords);
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
