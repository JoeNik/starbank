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
          child: Obx(() {
            final items = <Map<String, String>>[
              {
                'value': TtsService.engineGlobal,
                'label': '跟随全局设置（${_ttsService.getTtsRouteDisplayName(_ttsService.getGlobalTtsRoute())}）',
              },
              ..._ttsService.getTtsRouteOptions(),
            ];

            final values = items.map((item) => item['value']).whereType<String>().toSet();
            if (!values.contains(_currentEngine)) {
              _currentEngine = TtsService.engineGlobal;
            }

            return DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _currentEngine,
                items: items
                    .map(
                      (item) => DropdownMenuItem<String>(
                        value: item['value'],
                        child: Text(item['label'] ?? ''),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _currentEngine = val);
                    _ttsService.setFeatureTtsEngine(widget.featureKey, val);
                  }
                },
              ),
            );
          }),
        ),
      ],
    );
  }
}
