import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../services/tts_service.dart';
import '../theme/app_theme.dart';

class TtsEngineSelector extends StatefulWidget {
  final String featureKey;
  final String title;

  const TtsEngineSelector({
    super.key,
    required this.featureKey,
    required this.title,
  });

  @override
  State<TtsEngineSelector> createState() => _TtsEngineSelectorState();
}

class _TtsEngineSelectorState extends State<TtsEngineSelector> {
  final TtsService _ttsService = Get.find<TtsService>();
  late String _currentEngine;

  @override
  void initState() {
    super.initState();
    _currentEngine = _ttsService.getFeatureTtsEngine(widget.featureKey);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.record_voice_over, color: AppTheme.primary, size: 18.sp),
            SizedBox(width: 6.w),
            Text(
              widget.title,
              style: TextStyle(
                fontSize: 15.sp,
                fontWeight: FontWeight.bold,
                color: AppTheme.textMain,
              ),
            ),
          ],
        ),
        SizedBox(height: 12.h),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _currentEngine,
              items: const [
                DropdownMenuItem(
                  value: 'global',
                  child: Text('跟随系统全局设置'),
                ),
                DropdownMenuItem(
                  value: 'system',
                  child: Text('仅使用系统 TTS'),
                ),
                DropdownMenuItem(
                  value: 'cftts',
                  child: Text('仅使用自建 CFTTS'),
                ),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() => _currentEngine = val);
                  _ttsService.setFeatureTtsEngine(widget.featureKey, val);
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}
