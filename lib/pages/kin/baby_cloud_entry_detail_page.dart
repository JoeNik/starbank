import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../models/baby_cloud_entry.dart';
import '../../models/baby_cloud_media.dart';
import '../../theme/app_theme.dart';
import '../../widgets/baby_cloud_media_thumbnail.dart';
import 'baby_cloud_media_detail_page.dart';

class BabyCloudEntryDetailPage extends StatelessWidget {
  const BabyCloudEntryDetailPage({
    super.key,
    this.entry,
    required this.mediaItems,
    this.fallbackActorRole = '家人',
  });

  final BabyCloudEntry? entry;
  final List<BabyCloudMedia> mediaItems;
  final String fallbackActorRole;

  @override
  Widget build(BuildContext context) {
    final media = mediaItems.where((item) => !item.isDiary).toList();
    final first = mediaItems.isNotEmpty ? mediaItems.first : null;
    final description = (entry?.description ?? first?.description ?? '').trim();
    final tags = _tags();
    final role = _actorRole(first);
    final locationName = entry?.locationName ?? first?.locationName;
    final takenAt = entry?.takenAt ?? first?.takenAt ?? DateTime.now();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F0E8),
      appBar: AppBar(
        title: const Text('动态详情'),
        backgroundColor: const Color(0xFFFFFCF4),
        foregroundColor: AppTheme.textMain,
        elevation: 0,
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 28.h),
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 18.h),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFCF4),
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(color: const Color(0xFFE9DFCC)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _articleHeader(
                  role: role,
                  takenAt: takenAt,
                  locationName: locationName,
                ),
                SizedBox(height: 13.h),
                Divider(height: 1, color: const Color(0xFFE8DDC8)),
                SizedBox(height: 15.h),
                _articleBody(description, media),
                if (tags.isNotEmpty) ...[
                  SizedBox(height: 14.h),
                  Wrap(
                    spacing: 6.w,
                    runSpacing: 6.h,
                    children: tags
                        .map(
                          (tag) => Chip(
                            label: Text('#$tag'),
                            side: BorderSide.none,
                            visualDensity: VisualDensity.compact,
                            backgroundColor: const Color(0xFFFFF4D0),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _articleHeader({
    required String role,
    required DateTime takenAt,
    required String? locationName,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 18.r,
          backgroundColor: const Color(0xFFFFF4D0),
          child: Icon(
            Icons.supervisor_account_outlined,
            color: const Color(0xFFE09B00),
            size: 20.sp,
          ),
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      role,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textMain,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF4D0),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _entryTypeLabel,
                      style: TextStyle(
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF8A5C00),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 4.h),
              Wrap(
                spacing: 8.w,
                runSpacing: 4.h,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _metaText(
                    Icons.schedule_outlined,
                    DateFormat('yyyy-MM-dd HH:mm').format(takenAt),
                  ),
                  if (locationName?.trim().isNotEmpty == true)
                    _metaText(
                      Icons.location_on_outlined,
                      locationName!.trim(),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _metaText(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14.sp, color: const Color(0xFF8D8170)),
        SizedBox(width: 3.w),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 220.w),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.sp,
              color: const Color(0xFF756B5C),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _articleBody(String description, List<BabyCloudMedia> media) {
    final paragraphs = _paragraphs(description);
    if (paragraphs.isEmpty && media.isEmpty) {
      return Text(
        '这条动态暂无文字或媒体内容',
        style: TextStyle(
          color: Colors.grey.shade500,
          fontWeight: FontWeight.w700,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (paragraphs.isNotEmpty) _textParagraphs(paragraphs),
        if (paragraphs.isNotEmpty && media.isNotEmpty) SizedBox(height: 14.h),
        if (media.isNotEmpty) _mediaStack(media),
      ],
    );
  }

  Widget _textParagraphs(List<String> paragraphs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < paragraphs.length; index++) ...[
          if (index > 0) SizedBox(height: 10.h),
          _paragraphText(paragraphs[index], isLead: index == 0),
        ],
      ],
    );
  }

  Widget _paragraphText(String text, {bool isLead = false}) {
    return Text(
      text,
      style: TextStyle(
        fontSize: isLead ? 17.sp : 15.5.sp,
        height: 1.55,
        fontWeight: isLead ? FontWeight.w800 : FontWeight.w600,
        color: AppTheme.textMain,
      ),
    );
  }

  Widget _mediaStack(List<BabyCloudMedia> media) {
    return Column(
      children: [
        for (var index = 0; index < media.length; index++) ...[
          if (index > 0) SizedBox(height: 10.h),
          _articleMediaTile(
            media[index],
            media,
            index,
            aspectRatio: _mediaAspectRatio(media[index]),
          ),
        ],
      ],
    );
  }

  double _mediaAspectRatio(BabyCloudMedia item) {
    final width = item.width;
    final height = item.height;
    if (width != null && height != null && width > 0 && height > 0) {
      return (width / height).clamp(0.48, 1.78).toDouble();
    }
    if (item.isVideo) return 16 / 9;
    if (item.isAudio) return 2.8;
    return 4 / 3;
  }

  Widget _articleMediaTile(
    BabyCloudMedia item,
    List<BabyCloudMedia> allMedia,
    int index, {
    required double aspectRatio,
  }) {
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Material(
        color: const Color(0xFFE6E0D4),
        borderRadius: BorderRadius.circular(6.r),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            await Get.to(
              () => BabyCloudMediaDetailPage(
                items: allMedia,
                initialIndex: index,
              ),
            );
          },
          child: BabyCloudMediaThumbnail(
            item: item,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }

  List<String> _paragraphs(String text) {
    if (text.trim().isEmpty) return const [];
    final parts = text
        .split(RegExp(r'\n\s*\n|\r\n\s*\r\n'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length > 1) return parts;
    return _softParagraphs(text);
  }

  List<String> _softParagraphs(String text) {
    final trimmed = text.trim();
    if (trimmed.length <= 80) return [trimmed];

    final sentences = RegExp(r'[^。！？!?；;]+[。！？!?；;]?')
        .allMatches(trimmed)
        .map((match) => match.group(0)?.trim() ?? '')
        .where((part) => part.isNotEmpty)
        .toList();
    if (sentences.length <= 1) return [trimmed];

    final paragraphs = <String>[];
    final buffer = StringBuffer();
    for (final sentence in sentences) {
      if (buffer.isNotEmpty && buffer.length + sentence.length > 72) {
        paragraphs.add(buffer.toString());
        buffer.clear();
      }
      buffer.write(sentence);
    }
    if (buffer.isNotEmpty) paragraphs.add(buffer.toString());
    return paragraphs;
  }

  List<String> _tags() {
    final values = <String>{
      ...?entry?.tags,
      for (final item in mediaItems) ...item.tags,
    }.map((tag) => tag.trim().replaceFirst(RegExp(r'^#+'), '').trim());
    final tags = values.where((tag) => tag.isNotEmpty).toSet().toList()..sort();
    return tags;
  }

  String _actorRole(BabyCloudMedia? first) {
    final role = entry?.actorRole?.trim().isNotEmpty == true
        ? entry!.actorRole!.trim()
        : first?.actorRole?.trim();
    if (role?.isNotEmpty == true) return role!;
    return fallbackActorRole;
  }

  String get _entryTypeLabel {
    return switch (entry?.entryType) {
      'diary' => '文字',
      'audio' => '录音',
      'mixed' => '动态',
      _ => '云相册',
    };
  }
}
