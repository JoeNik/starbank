import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../../services/tts_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/toast_utils.dart';
import '../../../widgets/tts_engine_selector.dart';
import 'math_tts_config.dart';

class MathTtsSettingsPage extends StatefulWidget {
  const MathTtsSettingsPage({super.key});

  @override
  State<MathTtsSettingsPage> createState() => _MathTtsSettingsPageState();
}

class _MathTtsSettingsPageState extends State<MathTtsSettingsPage> {
  final TtsService _tts = Get.find<TtsService>();
  bool _isWarmingUp = false;

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _speakPreview() async {
    await _tts.speak(
      '一加二等于三，数学乐园准备好啦。',
      featureKey: mathCalculatorTtsFeatureKey,
    );
  }

  Future<void> _warmUpAudio() async {
    setState(() => _isWarmingUp = true);
    var successCount = 0;
    try {
      for (final text in mathWarmupSpeechTexts.toSet()) {
        await _tts.prefetchCftts(
          text,
          featureKey: mathCalculatorTtsFeatureKey,
        );
        successCount++;
      }
      if (mounted) {
        ToastUtils.showSuccess('已缓存 $successCount 个数学语音');
      }
    } catch (e) {
      if (mounted) {
        ToastUtils.showWarning('部分语音缓存失败: $e');
      }
    } finally {
      if (mounted) setState(() => _isWarmingUp = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F7FF),
      appBar: AppBar(
        title: const Text('数学语音设置'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: _speakPreview,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('试听'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.all(16.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionCard(
                title: '数学乐园 TTS',
                icon: Icons.record_voice_over_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const TtsEngineSelector(
                      featureKey: mathCalculatorTtsFeatureKey,
                      title: '当前功能 TTS 引擎',
                    ),
                    SizedBox(height: 12.h),
                    Text(
                      '数字、运算符、题目朗读和解释都会使用这里的语音设置。',
                      style: TextStyle(
                        color: AppTheme.textSub,
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 14.h),
              _sectionCard(
                title: '常用符号预缓存',
                icon: Icons.cached_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8.w,
                      runSpacing: 8.h,
                      children: mathKeySpeechMap.entries
                          .where((entry) => entry.key.length <= 1)
                          .map(
                            (entry) => Chip(
                              label: Text('${entry.key}  ${entry.value}'),
                              backgroundColor: const Color(0xFFFFD166)
                                  .withValues(alpha: 0.2),
                              side: BorderSide.none,
                            ),
                          )
                          .toList(),
                    ),
                    SizedBox(height: 12.h),
                    ElevatedButton.icon(
                      onPressed: _isWarmingUp ? null : _warmUpAudio,
                      icon: _isWarmingUp
                          ? SizedBox(
                              width: 16.w,
                              height: 16.w,
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.cloud_download_rounded),
                      label: Text(_isWarmingUp ? '缓存中...' : '缓存数字和符号语音'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2388E8),
                        foregroundColor: Colors.white,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    Text(
                      '使用系统 TTS 时无需生成文件；使用在线或自建 TTS 时会提前下载常用短语，按钮点击更顺。',
                      style: TextStyle(
                        color: AppTheme.textSub,
                        fontSize: 12.sp,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 14.h),
              _sectionCard(
                title: '声音细节',
                icon: Icons.tune_rounded,
                child: Column(
                  children: [
                    _sliderControl(
                      icon: Icons.speed_rounded,
                      title: '语速',
                      value: _tts.speechRate,
                      min: 0.0,
                      max: 1.0,
                      onChanged: (value) => _tts.setSpeechRate(value),
                    ),
                    SizedBox(height: 12.h),
                    _sliderControl(
                      icon: Icons.graphic_eq_rounded,
                      title: '音调',
                      value: _tts.pitch,
                      min: 0.5,
                      max: 2.0,
                      onChanged: (value) => _tts.setPitch(value),
                    ),
                    SizedBox(height: 12.h),
                    _sliderControl(
                      icon: Icons.volume_up_rounded,
                      title: '音量',
                      value: _tts.volume,
                      min: 0.0,
                      max: 1.0,
                      onChanged: (value) => _tts.setVolume(value),
                    ),
                    SizedBox(height: 8.h),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              unawaited(_tts.setSpeechRate(0.5));
                              unawaited(_tts.setPitch(1.0));
                              unawaited(_tts.setVolume(1.0));
                            },
                            icon: const Icon(Icons.restart_alt_rounded),
                            label: const Text('恢复默认'),
                          ),
                        ),
                        SizedBox(width: 10.w),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _speakPreview,
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('试听'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFEF476F),
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: 20.h),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(
          color: const Color(0xFFC8EEFF),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2388E8).withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20.sp, color: const Color(0xFF2388E8)),
              SizedBox(width: 8.w),
              Text(
                title,
                style: TextStyle(
                  color: AppTheme.textMain,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          SizedBox(height: 14.h),
          child,
        ],
      ),
    );
  }

  Widget _sliderControl({
    required IconData icon,
    required String title,
    required RxDouble value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Obx(
      () => Container(
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
          color: const Color(0xFFF7FBFF),
          borderRadius: BorderRadius.circular(16.r),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(icon, color: const Color(0xFF2388E8), size: 19.sp),
                SizedBox(width: 8.w),
                Text(
                  title,
                  style: TextStyle(
                    color: AppTheme.textMain,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  value.value.toStringAsFixed(1),
                  style: TextStyle(
                    color: const Color(0xFF2388E8),
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            Slider(
              value: value.value,
              min: min,
              max: max,
              divisions: 10,
              activeColor: const Color(0xFF2388E8),
              inactiveColor: const Color(0xFFC8EEFF),
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
