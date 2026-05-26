import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../../controllers/app_mode_controller.dart';
import '../../../data/pinyin_data.dart';
import '../../../services/pinyin_audio_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/toast_utils.dart';

class PinyinLearningPage extends StatefulWidget {
  const PinyinLearningPage({super.key});

  @override
  State<PinyinLearningPage> createState() => _PinyinLearningPageState();
}

class _PinyinLearningPageState extends State<PinyinLearningPage> {
  final PinyinAudioService _audio = Get.find<PinyinAudioService>();
  final AppModeController _modeController = Get.find<AppModeController>();

  PinyinSection _section = PinyinSection.initials;
  PinyinItem _selectedItem = PinyinData.initials.first;
  int _selectedTone = 1;

  @override
  void dispose() {
    _audio.stop();
    super.dispose();
  }

  Future<void> _playItem(PinyinItem item, {int? tone}) async {
    final nextTone = tone ?? _selectedTone;
    setState(() {
      _selectedItem = item;
      _selectedTone = nextTone;
    });
    await _audio.play(item.audioKey(nextTone));
  }

  void _changeSection(PinyinSection section) {
    final firstItem = PinyinData.bySection(section).first;
    setState(() {
      _section = section;
      _selectedItem = firstItem;
      _selectedTone = firstItem.defaultTone;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF7E8),
      appBar: AppBar(
        title: const Text('拼音小耳朵'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        actions: [
          Obx(() {
            if (!_modeController.isParentMode) {
              return const SizedBox.shrink();
            }
            return IconButton(
              onPressed: _showParentSettings,
              icon: const Icon(Icons.settings_rounded),
              tooltip: '拼音设置',
            );
          }),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHero(),
              SizedBox(height: 18.h),
              _buildSectionTabs(),
              SizedBox(height: 16.h),
              _buildListenCard(),
              SizedBox(height: 16.h),
              _buildToneRow(),
              SizedBox(height: 18.h),
              _buildPinyinGrid(),
              SizedBox(height: 18.h),
              _buildAttribution(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHero() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFC857), Color(0xFFFF8A65)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28.r),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF8A65).withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -8.w,
            top: -10.h,
            child: Text(
              'ɑ',
              style: TextStyle(
                fontSize: 88.sp,
                fontWeight: FontWeight.w900,
                color: Colors.white.withValues(alpha: 0.16),
                height: 1,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '每天听一点，拼音就熟一点',
                style: TextStyle(
                  fontSize: 21.sp,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                '点卡片听标准音，听完跟着读一遍。',
                style: TextStyle(
                  fontSize: 13.sp,
                  color: Colors.white.withValues(alpha: 0.92),
                  height: 1.5,
                ),
              ),
              SizedBox(height: 14.h),
              Wrap(
                spacing: 8.w,
                runSpacing: 8.h,
                children: const [
                  _HeroChip(label: '多看'),
                  _HeroChip(label: '多听'),
                  _HeroChip(label: '轻轻跟读'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTabs() {
    return Row(
      children: [
        _buildSectionTab('声母', PinyinSection.initials, const Color(0xFFFF8A65)),
        SizedBox(width: 8.w),
        _buildSectionTab('韵母', PinyinSection.finals, const Color(0xFF4DB6AC)),
        SizedBox(width: 8.w),
        _buildSectionTab(
            '整体认读', PinyinSection.wholeSyllables, const Color(0xFF5C6BC0)),
      ],
    );
  }

  Widget _buildSectionTab(String label, PinyinSection section, Color color) {
    final selected = _section == section;
    return Expanded(
      child: GestureDetector(
        onTap: () => _changeSection(section),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(vertical: 12.h),
          decoration: BoxDecoration(
            color: selected ? color : Colors.white,
            borderRadius: BorderRadius.circular(18.r),
            border: Border.all(
              color: selected ? color : Colors.orange.shade100,
              width: 1.5,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.24),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : [],
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : AppTheme.textMain,
              fontWeight: FontWeight.bold,
              fontSize: 13.sp,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildListenCard() {
    final toneText = PinyinData.markTone(_selectedItem.text, _selectedTone);
    final audioText =
        PinyinData.markTone(_selectedItem.audioBase, _selectedTone);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(18.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28.r),
        border: Border.all(color: const Color(0xFFFFE0B2), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _sectionTitle,
                      style: TextStyle(
                        fontSize: 13.sp,
                        color: AppTheme.textSub,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    Text(
                      toneText,
                      style: TextStyle(
                        fontSize: _selectedItem.text.length > 3 ? 54.sp : 68.sp,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFFFF7043),
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
              Obx(() {
                final loading = _audio.isLoading.value &&
                    _audio.currentAudioKey.value ==
                        _selectedItem.audioKey(_selectedTone);
                return GestureDetector(
                  onTap: loading ? null : () => _playItem(_selectedItem),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 78.w,
                    height: 78.w,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF7043),
                      borderRadius: BorderRadius.circular(26.r),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF7043).withValues(alpha: 0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: loading
                        ? Padding(
                            padding: EdgeInsets.all(24.w),
                            child: const CircularProgressIndicator(
                              strokeWidth: 3,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            Icons.volume_up_rounded,
                            color: Colors.white,
                            size: 38.sp,
                          ),
                  ),
                );
              }),
            ],
          ),
          SizedBox(height: 14.h),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(14.w),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(20.r),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedItem.tip,
                  style: TextStyle(
                    fontSize: 14.sp,
                    color: AppTheme.textMain,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 6.h),
                Text(
                  _selectedItem.isExampleAudio
                      ? '当前播放示例音节：$audioText，用来听清里面的 ${_selectedItem.text}。'
                      : '当前听到：$audioText · ${_selectedItem.example}',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: AppTheme.textSub,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 14.h),
          _buildFollowSteps(),
        ],
      ),
    );
  }

  Widget _buildFollowSteps() {
    return Row(
      children: [
        _buildStepPill('1', '听一听', const Color(0xFFFF8A65)),
        SizedBox(width: 8.w),
        _buildStepPill('2', '我来读', const Color(0xFF4DB6AC)),
        SizedBox(width: 8.w),
        _buildStepPill('3', '再听一次', const Color(0xFF5C6BC0)),
      ],
    );
  }

  Widget _buildStepPill(String number, String label, Color color) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 9.h),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.11),
          borderRadius: BorderRadius.circular(15.r),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 18.w,
              height: 18.w,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Center(
                child: Text(
                  number,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            SizedBox(width: 5.w),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToneRow() {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(22.r),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Row(
        children: List.generate(4, (index) {
          final tone = index + 1;
          final selected = _selectedTone == tone;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 3.w),
              child: GestureDetector(
                onTap: () => _playItem(_selectedItem, tone: tone),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: EdgeInsets.symmetric(vertical: 10.h),
                  decoration: BoxDecoration(
                    color: selected ? AppTheme.primaryDark : Colors.white,
                    borderRadius: BorderRadius.circular(15.r),
                    border: Border.all(
                      color:
                          selected ? AppTheme.primaryDark : Colors.pink.shade50,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        PinyinData.markTone(_selectedItem.text, tone),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17.sp,
                          fontWeight: FontWeight.w900,
                          color: selected ? Colors.white : AppTheme.textMain,
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        PinyinData.toneLabels[index],
                        style: TextStyle(
                          fontSize: 10.sp,
                          color: selected
                              ? Colors.white.withValues(alpha: 0.9)
                              : AppTheme.textSub,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildPinyinGrid() {
    final items = PinyinData.bySection(_section);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '点一个，听一听',
          style: TextStyle(
            fontSize: 17.sp,
            fontWeight: FontWeight.bold,
            color: AppTheme.textMain,
          ),
        ),
        SizedBox(height: 10.h),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 10.h,
            crossAxisSpacing: 10.w,
            childAspectRatio: 1.05,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            final selected = item.text == _selectedItem.text &&
                item.section == _selectedItem.section;
            return _buildPinyinTile(item, selected);
          },
        ),
      ],
    );
  }

  Widget _buildPinyinTile(PinyinItem item, bool selected) {
    return GestureDetector(
      onTap: () => _playItem(item, tone: item.defaultTone),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFF7043) : Colors.white,
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(
            color: selected ? const Color(0xFFFF7043) : Colors.orange.shade100,
            width: selected ? 2.5 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: (selected ? const Color(0xFFFF7043) : Colors.orange)
                  .withValues(alpha: selected ? 0.24 : 0.07),
              blurRadius: selected ? 14 : 8,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              item.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: item.text.length > 3 ? 20.sp : 25.sp,
                fontWeight: FontWeight.w900,
                color: selected ? Colors.white : AppTheme.textMain,
                height: 1,
              ),
            ),
            SizedBox(height: 6.h),
            Icon(
              Icons.hearing_rounded,
              size: 15.sp,
              color: selected ? Colors.white70 : AppTheme.textSub,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttribution() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(18.r),
      ),
      child: Text(
        '音频来自 hugolpz/audio-cmn，首次播放后会缓存到本机，不参与 WebDAV 备份。部分声母/韵母使用教学示例音节辅助发音。',
        style: TextStyle(
          fontSize: 11.sp,
          color: AppTheme.textSub,
          height: 1.45,
        ),
      ),
    );
  }

  String get _sectionTitle {
    switch (_section) {
      case PinyinSection.initials:
        return '声母小队';
      case PinyinSection.finals:
        return '韵母花园';
      case PinyinSection.wholeSyllables:
        return '整体认读';
    }
  }

  void _showParentSettings() {
    final baseUrlController =
        TextEditingController(text: _audio.audioBaseUrl.value);
    final limitController =
        TextEditingController(text: _audio.cacheLimit.value.toString());

    Get.bottomSheet(
      Container(
        padding: EdgeInsets.all(20.w),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E1),
          borderRadius: BorderRadius.vertical(top: Radius.circular(26.r)),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('⚙️', style: TextStyle(fontSize: 24.sp)),
                    SizedBox(width: 8.w),
                    Text(
                      '拼音音频设置',
                      style: TextStyle(
                        fontSize: 20.sp,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textMain,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Get.back(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                SizedBox(height: 16.h),
                _buildSettingCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSettingLabel('音频源 Base URL'),
                      SizedBox(height: 8.h),
                      TextField(
                        controller: baseUrlController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: PinyinAudioService.defaultBaseUrl,
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16.r),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      SizedBox(height: 8.h),
                      Text(
                        '文件会按 cmn-{拼音键}.mp3 拼接请求，默认使用 GitHub raw。',
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: AppTheme.textSub,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 12.h),
                _buildSettingCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSettingLabel('缓存上限'),
                      SizedBox(height: 8.h),
                      TextField(
                        controller: limitController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          suffixText: '个音频',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16.r),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      SizedBox(height: 8.h),
                      Obx(
                        () => Text(
                          '当前已缓存 ${_audio.cachedCount.value} 个音频。超过上限后会自动删除最久没听的音频。',
                          style: TextStyle(
                            fontSize: 11.sp,
                            color: AppTheme.textSub,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 12.h),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFECB3),
                    borderRadius: BorderRadius.circular(16.r),
                  ),
                  child: Text(
                    '拼音音频缓存只保存在本机，用来减少重复下载；WebDAV 备份不会包含这些音频文件。',
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: AppTheme.textMain,
                      height: 1.45,
                    ),
                  ),
                ),
                SizedBox(height: 18.h),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await _audio.clearCache();
                          ToastUtils.showSuccess('拼音音频缓存已清理');
                        },
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('清理缓存'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFE57373),
                          side: const BorderSide(color: Color(0xFFE57373)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18.r),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final limit = int.tryParse(
                            limitController.text.trim(),
                          );
                          if (limit == null) {
                            ToastUtils.showWarning('请输入正确的缓存上限');
                            return;
                          }
                          await _audio.updateSettings(
                            baseUrl: baseUrlController.text,
                            maxCachedAudios: limit,
                          );
                          Get.back();
                          ToastUtils.showSuccess('拼音设置已保存');
                        },
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('保存'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF8A65),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18.r),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  Widget _buildSettingCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: Colors.white),
      ),
      child: child,
    );
  }

  Widget _buildSettingLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 14.sp,
        fontWeight: FontWeight.bold,
        color: AppTheme.textMain,
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  final String label;

  const _HeroChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(999.r),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontSize: 11.sp,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
