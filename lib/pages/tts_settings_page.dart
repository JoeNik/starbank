import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/tts_service.dart';
import '../widgets/toast_utils.dart';

/// TTS 语音设置页面
/// 提供应用内个性化语音参数调整，不影响系统全局设置
class TtsSettingsPage extends StatefulWidget {
  const TtsSettingsPage({super.key});

  @override
  State<TtsSettingsPage> createState() => _TtsSettingsPageState();
}

class _TtsSettingsPageState extends State<TtsSettingsPage> {
  // 使用全局 TTS 服务
  final TtsService _tts = Get.find<TtsService>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('语音设置'),
        actions: [
          TextButton(
            onPressed: _resetToDefault,
            child: const Text('重置'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 试听区域
            _buildTestSection(),
            SizedBox(height: 24.h),

            // 语速调节
            _buildSliderSection(
              title: '语速',
              value: _tts.speechRate,
              min: 0.5,
              max: 2.0,
              icon: Icons.speed,
              description: '1.0 为正常语速',
              onChanged: (v) => _tts.setSpeechRate(v),
            ),

            // 音调调节
            _buildSliderSection(
              title: '音调',
              value: _tts.pitch,
              min: 0.5,
              max: 2.0,
              icon: Icons.music_note,
              description: '1.0 为正常音调',
              onChanged: (v) => _tts.setPitch(v),
            ),

            // 音量调节
            _buildSliderSection(
              title: '音量',
              value: _tts.volume,
              min: 0.0,
              max: 1.0,
              icon: Icons.volume_up,
              description: '1.0 为最大音量',
              onChanged: (v) => _tts.setVolume(v),
            ),

            SizedBox(height: 16.h),

            // 引擎选择
            Obx(() => _tts.engines.isNotEmpty
                ? _buildEngineSection()
                : const SizedBox()),

            SizedBox(height: 16.h),

            // 声音设置提示
            _buildVoiceHintSection(),

            SizedBox(height: 32.h),
          ],
        ),
      ),
    );
  }

  Widget _buildTestSection() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.hearing, color: Colors.blue, size: 24.sp),
                SizedBox(width: 8.w),
                Text(
                  '试听效果',
                  style:
                      TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            Row(
              children: [
                Expanded(
                  child: Obx(() => ElevatedButton.icon(
                        onPressed: () => _speak('你好，这是语音测试。调整参数后可以再次试听。'),
                        icon: Icon(_tts.isSpeaking.value
                            ? Icons.stop
                            : Icons.play_arrow),
                        label: Text(_tts.isSpeaking.value ? '停止' : '试听'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              _tts.isSpeaking.value ? Colors.red : Colors.blue,
                        ),
                      )),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _speak('小朋友，你知道什么动物最爱问为什么吗？答案是猪，因为猪会哼哼'),
                    icon: const Icon(Icons.child_care),
                    label: const Text('谜语测试'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _speak(String text) async {
    if (_tts.isSpeaking.value) {
      await _tts.stop();
    } else {
      await _tts.speak(text);
    }
  }

  Future<void> _resetToDefault() async {
    await _tts.setSpeechRate(1.0);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    ToastUtils.showSuccess('语音参数已恢复默认', title: '已重置');
  }

  Widget _buildSliderSection({
    required String title,
    required RxDouble value,
    required double min,
    required double max,
    required IconData icon,
    required String description,
    required Function(double) onChanged,
  }) {
    return Card(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
        child: Obx(() => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 20.sp, color: Colors.grey),
                    SizedBox(width: 8.w),
                    Text(title, style: TextStyle(fontSize: 14.sp)),
                    const Spacer(),
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Text(
                        value.value.toStringAsFixed(1),
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(trackHeight: 4),
                  child: Slider(
                    value: value.value,
                    min: min,
                    max: max,
                    divisions: ((max - min) * 10).toInt(),
                    activeColor: Colors.amber,
                    onChanged: (v) => onChanged(v),
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(fontSize: 10.sp, color: Colors.grey),
                ),
              ],
            )),
      ),
    );
  }

  Widget _buildEngineSection() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.settings_voice, size: 20.sp, color: Colors.grey),
                SizedBox(width: 8.w),
                Text('语音引擎', style: TextStyle(fontSize: 14.sp)),
                const Spacer(),
                Obx(() => Text(
                      _tts.getEngineDisplayName(_tts.currentEngine.value),
                      style: TextStyle(fontSize: 12.sp, color: Colors.blue),
                    )),
              ],
            ),
            SizedBox(height: 12.h),
            Obx(() => Wrap(
                  spacing: 8.w,
                  runSpacing: 8.h,
                  children: _tts.engines.map((engine) {
                    final isSelected = _tts.currentEngine.value == engine;
                    return ChoiceChip(
                      label: Text(_tts.getEngineDisplayName(engine)),
                      selected: isSelected,
                      onSelected: (selected) async {
                        if (selected) {
                          await _tts.setEngine(engine);
                          // 切换引擎后试听
                          _speak('已切换到 ${_tts.getEngineDisplayName(engine)}');
                        }
                      },
                    );
                  }).toList(),
                )),
          ],
        ),
      ),
    );
  }

  /// 声音设置提示区域
  Widget _buildVoiceHintSection() {
    return Card(
      color: Colors.orange.shade50,
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, size: 20.sp, color: Colors.orange),
                SizedBox(width: 8.w),
                Text(
                  '声音选择',
                  style:
                      TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SizedBox(height: 8.h),
            Text(
              '如需更换声音（如选择女声/男声、不同音色），请在对应的 TTS 引擎应用中设置。',
              style: TextStyle(fontSize: 12.sp, color: Colors.grey.shade700),
            ),
            SizedBox(height: 12.h),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openSystemTtsSettings,
                icon: const Icon(Icons.open_in_new),
                label: const Text('打开系统 TTS 设置'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 打开系统 TTS 设置
  Future<void> _openSystemTtsSettings() async {
    try {
      const url = 'intent:#Intent;action=com.android.settings.TTS_SETTINGS;end';
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        ToastUtils.showInfo('请手动打开：设置 → 辅助功能 → 文字转语音');
      }
    } catch (e) {
      ToastUtils.showInfo('请手动打开：设置 → 辅助功能 → 文字转语音\n或在第三方 TTS 应用中设置声音');
    }
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }
}
