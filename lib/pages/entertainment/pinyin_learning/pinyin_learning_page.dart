import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../../controllers/app_mode_controller.dart';
import '../../../data/pinyin_data.dart';
import '../../../services/pinyin_audio_service.dart';
import '../../../services/tts_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/tts_engine_selector.dart';
import '../../../widgets/toast_utils.dart';

class PinyinLearningPage extends StatefulWidget {
  const PinyinLearningPage({super.key});

  @override
  State<PinyinLearningPage> createState() => _PinyinLearningPageState();
}

class _PinyinLearningPageState extends State<PinyinLearningPage> {
  final PinyinAudioService _audio = Get.find<PinyinAudioService>();
  final TtsService _tts = Get.find<TtsService>();
  final AppModeController _modeController = Get.find<AppModeController>();

  PinyinSection _section = PinyinSection.initials;
  PinyinItem _selectedItem = PinyinData.initials.first;
  int _selectedTone = 1;
  String _playingWordText = '';
  final Set<String> _spokenTipKeys = {};

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

  Future<void> _playSelectedWithTip() async {
    final tipKey = _tipKeyFor(_selectedItem);
    if (!_spokenTipKeys.contains(tipKey)) {
      await _playTip(_selectedItem);
      _spokenTipKeys.add(tipKey);
    }
    await _audio.play(_selectedItem.audioKey(_selectedTone));
  }

  Future<void> _playTip(PinyinItem item) async {
    await _audio.stop();
    await _tts.speak(_buildTipSpeech(item), featureKey: 'pinyin_tip');
    await _waitForTipSpeechDone();
  }

  Future<void> _playWord(PinyinWord word) async {
    await _tts.stop();
    setState(() => _playingWordText = word.text);
    try {
      await _audio.playSequence(word.audioKeys);
    } finally {
      if (mounted && _playingWordText == word.text) {
        setState(() => _playingWordText = '');
      }
    }
  }

  void _changeSection(PinyinSection section) {
    final firstItem = PinyinData.bySection(section).first;
    setState(() {
      _section = section;
      _selectedItem = firstItem;
      _selectedTone = firstItem.defaultTone;
    });
  }

  Future<void> _waitForTipSpeechDone() async {
    for (var i = 0; i < 80; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!_tts.isSpeaking.value) return;
    }
  }

  String _buildTipSpeech(PinyinItem item) {
    if (item.isExampleAudio) {
      return '${item.text}，${item.tip}。';
    }
    return '${item.text}，${item.tip}。${item.example}。';
  }

  String _tipKeyFor(PinyinItem item) => '${item.section.name}:${item.text}';

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
        child: Stack(
          children: [
            const Positioned.fill(
              child: IgnorePointer(
                child: _PinyinBackgroundScene(),
              ),
            ),
            SingleChildScrollView(
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
                  _buildWordPractice(),
                  SizedBox(height: 18.h),
                  _buildAttribution(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Iterable<String> _presetWordAudioKeys() {
    return PinyinData.words.expand((word) => word.audioKeys);
  }

  Future<void> _cachePresetWordAudios({
    required void Function(int done, int total) onProgress,
    required void Function(bool value) onCachingChanged,
    required String baseUrl,
    required int maxCachedAudios,
  }) async {
    onCachingChanged(true);
    onProgress(0, 0);

    try {
      await _audio.updateSettings(
        baseUrl: baseUrl,
        maxCachedAudios: maxCachedAudios,
      );
      final result = await _audio.cacheAudioKeys(
        _presetWordAudioKeys(),
        forceRefresh: true,
        onProgress: onProgress,
      );

      if (result.hasFailures) {
        final preview = result.failedKeys.take(6).join(', ');
        final suffix = result.failedKeys.length > 6 ? ' 等' : '';
        ToastUtils.showWarning(
          '已缓存 ${result.successCount}/${result.total} 个音频，失败：$preview$suffix',
        );
      } else {
        ToastUtils.showSuccess('预置词语音频已重新缓存');
      }
    } catch (e) {
      ToastUtils.showError('预置词语音频缓存失败: $e');
    } finally {
      if (mounted) {
        onCachingChanged(false);
      }
    }
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
                  onTap: loading ? null : _playSelectedWithTip,
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selectedItem.tip,
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: AppTheme.textMain,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    GestureDetector(
                      onTap: () => _playTip(_selectedItem),
                      child: Container(
                        width: 34.w,
                        height: 34.w,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF8A65),
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 22.sp,
                        ),
                      ),
                    ),
                  ],
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

  Widget _buildWordPractice() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '词语串读',
              style: TextStyle(
                fontSize: 17.sp,
                fontWeight: FontWeight.bold,
                color: AppTheme.textMain,
              ),
            ),
            SizedBox(width: 8.w),
            Text(
              '按音节连起来听',
              style: TextStyle(
                fontSize: 11.sp,
                color: AppTheme.textSub,
              ),
            ),
          ],
        ),
        SizedBox(height: 10.h),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: PinyinData.words.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10.h,
            crossAxisSpacing: 10.w,
            childAspectRatio: 2.25,
          ),
          itemBuilder: (context, index) {
            final word = PinyinData.words[index];
            return _buildWordTile(word, _playingWordText == word.text);
          },
        ),
      ],
    );
  }

  Widget _buildWordTile(PinyinWord word, bool isPlaying) {
    return GestureDetector(
      onTap: () => _playWord(word),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 180),
        scale: isPlaying ? 1.03 : 1.0,
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
          decoration: BoxDecoration(
            color: isPlaying ? const Color(0xFFFFF3E0) : Colors.white,
            borderRadius: BorderRadius.circular(20.r),
            border: Border.all(
              color:
                  isPlaying ? const Color(0xFFFF8A65) : const Color(0xFFFFCCBC),
              width: isPlaying ? 2.5 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF8A65)
                    .withValues(alpha: isPlaying ? 0.26 : 0.08),
                blurRadius: isPlaying ? 16 : 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      word.text,
                      style: TextStyle(
                        fontSize: 18.sp,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textMain,
                        height: 1,
                      ),
                    ),
                    SizedBox(height: 5.h),
                    Text(
                      word.pinyin,
                      style: TextStyle(
                        fontSize: 13.sp,
                        color: const Color(0xFFFF7043),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: isPlaying
                    ? SizedBox(
                        key: const ValueKey('word_loading'),
                        width: 26.w,
                        height: 26.w,
                        child: const CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Color(0xFFFF8A65),
                        ),
                      )
                    : Icon(
                        Icons.play_circle_fill_rounded,
                        key: const ValueKey('word_play'),
                        color: const Color(0xFFFF8A65),
                        size: 28.sp,
                      ),
              ),
            ],
          ),
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
    var isCachingWords = false;
    var cacheDone = 0;
    var cacheTotal = 0;
    var sheetAlive = true;

    Get.bottomSheet(
      StatefulBuilder(
        builder: (context, setSheetState) {
          void updateProgress(int done, int total) {
            if (!sheetAlive) return;
            setSheetState(() {
              cacheDone = done;
              cacheTotal = total;
            });
          }

          void updateCaching(bool value) {
            if (!sheetAlive) return;
            setSheetState(() => isCachingWords = value);
          }

          return Container(
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
                        Text('设置', style: TextStyle(fontSize: 20.sp)),
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
                          onPressed: isCachingWords ? null : () => Get.back(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    SizedBox(height: 16.h),
                    _buildSettingCard(
                      child: const TtsEngineSelector(
                        featureKey: 'pinyin_tip',
                        title: '发音提示朗读引擎',
                      ),
                    ),
                    SizedBox(height: 12.h),
                    _buildSettingCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSettingLabel('音频源 Base URL'),
                          SizedBox(height: 8.h),
                          TextField(
                            controller: baseUrlController,
                            enabled: !isCachingWords,
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
                            enabled: !isCachingWords,
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
                    _buildSettingCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: _buildSettingLabel('词语串读预缓存')),
                              if (isCachingWords)
                                SizedBox(
                                  width: 18.w,
                                  height: 18.w,
                                  child: const CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: Color(0xFFFF8A65),
                                  ),
                                ),
                            ],
                          ),
                          SizedBox(height: 8.h),
                          Text(
                            cacheTotal > 0
                                ? '正在缓存 $cacheDone/$cacheTotal 个预置词音频。'
                                : '把预置词语用到的音频提前下载，孩子点击串读时会更顺畅。',
                            style: TextStyle(
                              fontSize: 11.sp,
                              color: AppTheme.textSub,
                              height: 1.4,
                            ),
                          ),
                          SizedBox(height: 10.h),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: isCachingWords
                                  ? null
                                  : () async {
                                      final limit = int.tryParse(
                                        limitController.text.trim(),
                                      );
                                      if (limit == null) {
                                        ToastUtils.showWarning('请输入正确的缓存上限');
                                        return;
                                      }
                                      await _cachePresetWordAudios(
                                        onProgress: updateProgress,
                                        onCachingChanged: updateCaching,
                                        baseUrl: baseUrlController.text,
                                        maxCachedAudios: limit,
                                      );
                                    },
                              icon: const Icon(Icons.cloud_download_rounded),
                              label: Text(
                                isCachingWords ? '正在重新缓存...' : '重新缓存词语音频',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFFB74D),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18.r),
                                ),
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
                            onPressed: isCachingWords
                                ? null
                                : () async {
                                    await _audio.clearCache();
                                    ToastUtils.showSuccess('拼音音频缓存已清理');
                                  },
                            icon: const Icon(Icons.delete_outline_rounded),
                            label: const Text('清理缓存'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFE57373),
                              side:
                                  const BorderSide(color: Color(0xFFE57373)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18.r),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: isCachingWords
                                ? null
                                : () async {
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
          );
        },
      ),
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
    ).whenComplete(() => sheetAlive = false);
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

class _PinyinBackgroundScene extends StatefulWidget {
  const _PinyinBackgroundScene();

  @override
  State<_PinyinBackgroundScene> createState() => _PinyinBackgroundSceneState();
}

class _PinyinBackgroundSceneState extends State<_PinyinBackgroundScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 36),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _PinyinBackgroundPainter(_controller.value),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

class _PinyinBackgroundPainter extends CustomPainter {
  final double progress;

  const _PinyinBackgroundPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    _drawLetterBubbles(canvas, size);
    _drawFish(canvas, size);
    _drawHorse(canvas, size);
  }

  void _drawLetterBubbles(Canvas canvas, Size size) {
    final letters = ['a', 'o', 'e', 'i', 'u', 'v', 'b', 'p', 'm', 'f'];
    final bubblePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = Colors.orangeAccent.withValues(alpha: 0.11)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final textPainter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );

    for (var i = 0; i < letters.length; i++) {
      final seed = i * 43.0;
      final x = ((seed * 3.7) + progress * size.width * 0.18) % size.width;
      final y =
          ((seed * 7.9) + progress * size.height * (0.28 + i % 4 * 0.08)) %
              size.height;
      final radius = 13.w + (i % 3) * 4.w;
      final center = Offset(x, y);
      canvas.drawCircle(center, radius, bubblePaint);
      canvas.drawCircle(center, radius, borderPaint);

      textPainter.text = TextSpan(
        text: letters[i] == 'v' ? 'ü' : letters[i],
        style: TextStyle(
          fontSize: 13.sp + (i % 3) * 2.sp,
          fontWeight: FontWeight.w900,
          color: const Color(0xFFFF8A65).withValues(alpha: 0.16),
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        center - Offset(textPainter.width / 2, textPainter.height / 2),
      );
    }
  }

  void _drawFish(Canvas canvas, Size size) {
    final bodyPaint = Paint()
      ..color = const Color(0xFF4DB6AC).withValues(alpha: 0.10)
      ..style = PaintingStyle.fill;
    final finPaint = Paint()
      ..color = const Color(0xFF26A69A).withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    final eyePaint = Paint()
      ..color = Colors.blueGrey.withValues(alpha: 0.14)
      ..style = PaintingStyle.fill;

    for (var i = 0; i < 4; i++) {
      final laneY = size.height * (0.2 + i * 0.16);
      final direction = i.isEven ? 1.0 : -1.0;
      final travel = (progress + i * 0.23) % 1.0;
      final x = direction > 0
          ? -36.w + travel * (size.width + 72.w)
          : size.width + 36.w - travel * (size.width + 72.w);
      final wave = sin((progress * pi * 2) + i) * 8.h;
      canvas.save();
      canvas.translate(x, laneY + wave);
      canvas.scale(direction, 1);

      final bodyRect = Rect.fromCenter(
        center: Offset.zero,
        width: 34.w,
        height: 18.h,
      );
      canvas.drawOval(bodyRect, bodyPaint);

      final tail = Path()
        ..moveTo(-17.w, 0)
        ..lineTo(-29.w, -9.h)
        ..lineTo(-29.w, 9.h)
        ..close();
      canvas.drawPath(tail, finPaint);

      final topFin = Path()
        ..moveTo(-2.w, -8.h)
        ..lineTo(8.w, -18.h)
        ..lineTo(12.w, -5.h)
        ..close();
      canvas.drawPath(topFin, finPaint);

      canvas.drawCircle(Offset(10.w, -3.h), 1.5.w, eyePaint);
      canvas.restore();
    }
  }

  void _drawHorse(Canvas canvas, Size size) {
    final groundY = size.height * 0.84;
    final x = ((progress * 0.45 + 0.1) % 1.0) * (size.width + 100.w) - 50.w;
    final bob = sin(progress * pi * 2) * 2.h;
    final paint = Paint()
      ..color = const Color(0xFF8D6E63).withValues(alpha: 0.08)
      ..strokeWidth = 3.w
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final fill = Paint()
      ..color = const Color(0xFF8D6E63).withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.translate(x, groundY + bob);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 42.w, height: 20.h),
      fill,
    );
    canvas.drawCircle(Offset(25.w, -11.h), 9.w, fill);
    canvas.drawLine(Offset(15.w, -8.h), Offset(24.w, -13.h), paint);

    final step = sin(progress * pi * 4);
    canvas.drawLine(
      Offset(-14.w, 8.h),
      Offset(-20.w + step * 4.w, 26.h),
      paint,
    );
    canvas.drawLine(
      Offset(-3.w, 9.h),
      Offset(-6.w - step * 4.w, 27.h),
      paint,
    );
    canvas.drawLine(
      Offset(10.w, 8.h),
      Offset(16.w - step * 4.w, 26.h),
      paint,
    );
    canvas.drawLine(
      Offset(18.w, 6.h),
      Offset(23.w + step * 4.w, 24.h),
      paint,
    );
    canvas.drawLine(Offset(-22.w, -2.h), Offset(-34.w, -10.h), paint);

    final ear = Path()
      ..moveTo(25.w, -20.h)
      ..lineTo(29.w, -30.h)
      ..lineTo(32.w, -18.h)
      ..close();
    canvas.drawPath(ear, fill);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PinyinBackgroundPainter oldDelegate) {
    return oldDelegate.progress != progress;
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
