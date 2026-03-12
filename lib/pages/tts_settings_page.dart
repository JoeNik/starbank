import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import '../services/tts_service.dart';
import '../models/cftts_config.dart';
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

  late TextEditingController _baseUrlController;
  late TextEditingController _apiKeyController;

  final RxList<String> _cfttsVoices = <String>[].obs;
  final RxBool _isLoadingVoices = false.obs;
  final RxString _selectedVoice = 'zh-CN-XiaoxiaoNeural'.obs;
  final RxString _selectedEmotion = 'cheerful'.obs;
  final RxDouble _cfttsSpeed = 1.0.obs;
  
  final List<String> _emotions = [
    'neutral',
    'cheerful',
    'sad',
    'angry',
  ];

  final Map<String, String> _emotionLabels = {
    'neutral': '自然 (Neutral)',
    'cheerful': '开心 (Cheerful)',
    'sad': '悲伤 (Sad)',
    'angry': '生气 (Angry)',
  };

  @override
  void initState() {
    super.initState();
    final cfg = _tts.cfttsConfig.value;
    _baseUrlController = TextEditingController(text: cfg?.baseUrl ?? 'http://localhost:8080');
    _apiKeyController = TextEditingController(text: cfg?.apiKey ?? '');
    _selectedVoice.value = cfg?.voice ?? 'zh-CN-XiaoxiaoNeural';
    
    if (_emotions.contains(cfg?.model ?? 'cheerful')) {
      _selectedEmotion.value = cfg?.model ?? 'cheerful';
    } else {
      _selectedEmotion.value = 'cheerful';
    }
    
    _cfttsSpeed.value = cfg?.speed ?? 1.0;

    // 初始化时获取一次语音列表
    if (cfg?.baseUrl.isNotEmpty == true) {
      _fetchVoices();
    }
  }

  Future<void> _fetchVoices() async {
    _isLoadingVoices.value = true;
    try {
      final voices = await _tts.fetchCfttsVoices();
      if (voices.isNotEmpty) {
        _cfttsVoices.assignAll(voices);
        // 如果当前选中的语音不在列表中，则重置为列表第一项
        if (!_cfttsVoices.contains(_selectedVoice.value)) {
          _selectedVoice.value = _cfttsVoices.first;
          _saveCfttsConfig();
        }
      }
    } finally {
      _isLoadingVoices.value = false;
    }
  }

  void _saveCfttsConfig() {
    final cfg = _tts.cfttsConfig.value ?? CfttsConfig();
    cfg.baseUrl = _baseUrlController.text.trim();
    cfg.apiKey = _apiKeyController.text.trim();
    cfg.voice = _selectedVoice.value;
    cfg.model = _selectedEmotion.value;
    cfg.speed = _cfttsSpeed.value;
    _tts.updateCfttsConfig(cfg);
  }

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
            SizedBox(height: 16.h),

            // 引擎类型选择
            _buildEngineTypeSelector(),
            SizedBox(height: 16.h),

            // 根据选中的引擎显示不同内容
            Obx(() {
              if (_tts.useCftts.value) {
                return _buildCfttsSettings();
              } else {
                return _buildSystemTtsSettings();
              }
            }),

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

  Widget _buildEngineTypeSelector() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('默认语音引擎', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
            Obx(() => ToggleButtons(
              isSelected: [!_tts.useCftts.value, _tts.useCftts.value],
              onPressed: (index) {
                _tts.setUseCftts(index == 1);
              },
              borderRadius: BorderRadius.circular(8.r),
              constraints: BoxConstraints(minHeight: 36.h, minWidth: 80.w),
              children: const [
                Text('系统 TTS'),
                Text('自建 CFTTS'),
              ],
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemTtsSettings() {
    return Column(
      children: [
        _buildSliderSection(
          title: '语速',
          value: _tts.speechRate,
          min: 0.5, max: 2.0, icon: Icons.speed,
          description: '1.0 为正常语速', onChanged: (v) => _tts.setSpeechRate(v),
        ),
        _buildSliderSection(
          title: '音调',
          value: _tts.pitch,
          min: 0.5, max: 2.0, icon: Icons.music_note,
          description: '1.0 为正常音调', onChanged: (v) => _tts.setPitch(v),
        ),
        _buildSliderSection(
          title: '音量',
          value: _tts.volume,
          min: 0.0, max: 1.0, icon: Icons.volume_up,
          description: '1.0 为最大音量', onChanged: (v) => _tts.setVolume(v),
        ),
        SizedBox(height: 16.h),
        Obx(() => _tts.engines.isNotEmpty ? _buildEngineSection() : const SizedBox()),
        SizedBox(height: 16.h),
        _buildVoiceHintSection(),
      ],
    );
  }

  Widget _buildCfttsSettings() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.cloud, color: Colors.blue, size: 24.sp),
                    SizedBox(width: 8.w),
                    Text('CFTTS 配置', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: _checkCfttsHealth,
                  icon: const Icon(Icons.health_and_safety, size: 18),
                  label: const Text('健康检查'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    minimumSize: Size(0, 32.h),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16.h),
            _buildTextField('服务器地址 (带端口)', _baseUrlController, hint: 'http://localhost:8080', onBlur: _fetchVoices),
            SizedBox(height: 12.h),
            _buildTextField('API Key (可选)', _apiKeyController, hint: 'Bearer Token', onBlur: _fetchVoices),
            SizedBox(height: 12.h),
            
            // 语音风格选择
            _buildVoiceSelector(),
                
            SizedBox(height: 12.h),
            
            // 情感风格选择
            Obx(() => _buildDropdown(
                  label: '情感风格 (Emotion)',
                  value: _selectedEmotion.value,
                  items: _emotions,
                  labels: _emotionLabels,
                  isLoading: false,
                  onChanged: (val) {
                    if (val != null) {
                      _selectedEmotion.value = val;
                      _saveCfttsConfig();
                    }
                  },
                )),
                
            SizedBox(height: 16.h),
            
            // CFTTS 专属语速滑块
            Obx(() {
              final speed = _cfttsSpeed.value;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.speed, size: 20.sp, color: Colors.grey),
                      SizedBox(width: 8.w),
                      Text('语速 (${speed.toStringAsFixed(1)})', style: TextStyle(fontSize: 14.sp)),
                    ],
                  ),
                  Slider(
                    value: speed,
                    min: 0.5,
                    max: 2.0,
                    divisions: 15,
                    activeColor: Colors.blue,
                    onChanged: (v) {
                      _cfttsSpeed.value = v;
                      _saveCfttsConfig();
                    },
                  ),
                ],
              );
            }),
            
            SizedBox(height: 12.h),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  _saveCfttsConfig();
                  ToastUtils.showSuccess('配置已保存');
                },
                child: const Text('保存配置'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {String? hint, VoidCallback? onBlur}) {
    return Focus(
      onFocusChange: (hasFocus) {
        if (!hasFocus && onBlur != null) {
          onBlur();
        }
      },
      child: TextField(
        controller: controller,
        onChanged: (_) => _saveCfttsConfig(),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        ),
      ),
    );
  }

  Widget _buildVoiceSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('语音风格 (Voice)', style: TextStyle(fontSize: 12.sp, color: Colors.grey.shade700)),
            Obx(() {
              if (_isLoadingVoices.value) {
                return Padding(
                  padding: EdgeInsets.only(left: 8.w),
                  child: SizedBox(width: 12.w, height: 12.h, child: const CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              return const SizedBox();
            }),
          ],
        ),
        SizedBox(height: 4.h),
        InkWell(
          onTap: () {
            if (_cfttsVoices.isNotEmpty) {
              _showVoicesDialog();
            } else {
              if (_baseUrlController.text.isNotEmpty) {
                _fetchVoices().then((_) {
                  if (_cfttsVoices.isNotEmpty) {
                    _showVoicesDialog();
                  } else {
                    ToastUtils.showWarning('获取不到语音列表，请检查网络和服务器配置');
                  }
                });
              } else {
                ToastUtils.showWarning('请先输入服务器地址');
              }
            }
          },
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(4.r),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Obx(() => Text(
                        _selectedVoice.value,
                        style: TextStyle(fontSize: 14.sp),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      )),
                ),
                Icon(Icons.arrow_drop_down, color: Colors.grey.shade700),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showVoicesDialog() {
    TextEditingController searchController = TextEditingController();
    RxList<String> filteredVoices = RxList<String>.from(_cfttsVoices);

    Get.bottomSheet(
      Container(
        height: Get.height * 0.7,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
        ),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.all(16.w),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('选择语音风格 (${_cfttsVoices.length}个)', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Get.back(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: TextField(
                controller: searchController,
                decoration: InputDecoration(
                  hintText: '搜索语音风格...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
                onChanged: (text) {
                  if (text.isEmpty) {
                    filteredVoices.assignAll(_cfttsVoices);
                  } else {
                    filteredVoices.assignAll(_cfttsVoices.where((v) => v.toLowerCase().contains(text.toLowerCase())));
                  }
                },
              ),
            ),
            SizedBox(height: 8.h),
            Expanded(
              child: Obx(() => ListView.builder(
                    itemCount: filteredVoices.length,
                    itemBuilder: (context, index) {
                      final voice = filteredVoices[index];
                      final isSelected = voice == _selectedVoice.value;
                      return ListTile(
                        title: Text(voice, style: TextStyle(fontSize: 14.sp)),
                        trailing: isSelected ? const Icon(Icons.check, color: Colors.blue) : null,
                        tileColor: isSelected ? Colors.blue.withOpacity(0.05) : null,
                        onTap: () {
                          _selectedVoice.value = voice;
                          _saveCfttsConfig();
                          Get.back();
                        },
                      );
                    },
                  )),
            ),
          ],
        ),
      ),
      isScrollControlled: true,
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    Map<String, String>? labels,
    required Function(String?) onChanged,
    bool isLoading = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: TextStyle(fontSize: 12.sp, color: Colors.grey.shade700)),
            if (isLoading) ...[
               SizedBox(width: 8.w),
               SizedBox(width: 12.w, height: 12.h, child: const CircularProgressIndicator(strokeWidth: 2)),
            ]
          ],
        ),
        SizedBox(height: 4.h),
        DropdownButtonFormField<String>(
          isExpanded: true,
          value: items.contains(value) ? value : (items.isNotEmpty ? items.first : value),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
          ),
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(labels?[e] ?? e, style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis, maxLines: 1))).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Future<void> _checkCfttsHealth() async {
    _saveCfttsConfig();
    final baseUrl = _baseUrlController.text.trim();
    if (baseUrl.isEmpty) {
      ToastUtils.showWarning('请输入服务器地址');
      return;
    }
    try {
      final url = Uri.parse('$baseUrl/api/v1/health');
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        ToastUtils.showSuccess('连接成功！');
        _fetchVoices();
      } else {
        ToastUtils.showError('服务异常: HTTP ${response.statusCode}');
      }
    } catch (e) {
      ToastUtils.showError('连接失败: $e');
    }
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
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _tts.stop();
    super.dispose();
  }
}
