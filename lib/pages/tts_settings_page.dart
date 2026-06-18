import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import '../services/android_background_network_service.dart';
import '../services/tts_service.dart';
import '../models/cftts_config.dart';
import '../models/openai_tts_config.dart';
import '../widgets/toast_utils.dart';

class TtsSettingsPage extends StatefulWidget {
  const TtsSettingsPage({super.key});

  @override
  State<TtsSettingsPage> createState() => _TtsSettingsPageState();
}

class _TtsSettingsPageState extends State<TtsSettingsPage> {
  final TtsService _tts = Get.find<TtsService>();

  late TextEditingController _baseUrlController;
  late TextEditingController _apiKeyController;

  final RxList<String> _cfttsVoices = <String>[].obs;
  final RxBool _isLoadingVoices = false.obs;
  final RxString _selectedVoice = 'zh-CN-XiaoxiaoNeural'.obs;
  final RxString _selectedEmotion = 'cheerful'.obs;
  final RxDouble _cfttsSpeed = 1.0.obs;

  final List<String> _emotions = ['neutral', 'cheerful', 'sad', 'angry'];
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
    _baseUrlController =
        TextEditingController(text: cfg?.baseUrl ?? 'http://localhost:8080');
    _apiKeyController = TextEditingController(text: cfg?.apiKey ?? '');
    _selectedVoice.value = cfg?.voice ?? 'zh-CN-XiaoxiaoNeural';
    _selectedEmotion.value =
        _emotions.contains(cfg?.model) ? cfg!.model : 'cheerful';
    _cfttsSpeed.value = cfg?.speed ?? 1.0;
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
          IconButton(
            onPressed: _addOpenAITtsProvider,
            icon: const Icon(Icons.add),
            tooltip: '添加 OpenAI TTS 接口',
          ),
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
            _buildTestSection(),
            SizedBox(height: 16.h),
            _buildGlobalRouteSelector(),
            SizedBox(height: 16.h),
            _buildSystemTtsSettings(),
            SizedBox(height: 16.h),
            _buildCfttsSettings(),
            SizedBox(height: 16.h),
            _buildOpenAITtsSection(),
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
                  child: Obx(
                    () => ElevatedButton.icon(
                      onPressed: () => _speak('你好，这是语音测试。调整参数后可以再次试听。'),
                      icon: Icon(_tts.isSpeaking.value
                          ? Icons.stop
                          : Icons.play_arrow),
                      label: Text(_tts.isSpeaking.value ? '停止' : '试听'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _tts.isSpeaking.value ? Colors.red : Colors.blue,
                      ),
                    ),
                  ),
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

  Widget _buildGlobalRouteSelector() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('默认语音引擎',
                style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
            SizedBox(height: 12.h),
            Obx(() {
              final options = _tts.getTtsRouteOptions();
              final value = _tts.getGlobalTtsRoute();
              return DropdownButtonFormField<String>(
                value: options.any((item) => item['value'] == value)
                    ? value
                    : TtsService.engineSystem,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
                items: options
                    .map(
                      (item) => DropdownMenuItem<String>(
                        value: item['value'],
                        child: Text(item['label'] ?? ''),
                      ),
                    )
                    .toList(),
                onChanged: (val) async {
                  if (val == null) return;
                  await _tts.setGlobalTtsRoute(val);
                },
              );
            }),
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
          min: 0.5,
          max: 2.0,
          icon: Icons.speed,
          description: '1.0 为正常语速',
          onChanged: (v) => _tts.setSpeechRate(v),
        ),
        _buildSliderSection(
          title: '音调',
          value: _tts.pitch,
          min: 0.5,
          max: 2.0,
          icon: Icons.music_note,
          description: '1.0 为正常音调',
          onChanged: (v) => _tts.setPitch(v),
        ),
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
        Obx(() =>
            _tts.engines.isNotEmpty ? _buildEngineSection() : const SizedBox()),
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
                    Text('自建 CFTTS',
                        style: TextStyle(
                            fontSize: 16.sp, fontWeight: FontWeight.bold)),
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
            _buildTextField('服务器地址 (带端口)', _baseUrlController,
                hint: 'http://localhost:8080', onBlur: _fetchVoices),
            SizedBox(height: 12.h),
            _buildTextField('API Key (可选)', _apiKeyController,
                hint: 'Bearer Token', onBlur: _fetchVoices),
            SizedBox(height: 12.h),
            _buildVoiceSelector(),
            SizedBox(height: 12.h),
            Obx(
              () => _buildDropdown(
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
              ),
            ),
            SizedBox(height: 16.h),
            Obx(() {
              final speed = _cfttsSpeed.value;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.speed, size: 20.sp, color: Colors.grey),
                      SizedBox(width: 8.w),
                      Text('语速 (${speed.toStringAsFixed(1)})',
                          style: TextStyle(fontSize: 14.sp)),
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

  Widget _buildOpenAITtsSection() {
    return Obx(() {
      final configs = _tts.openAITtsConfigs;
      return Card(
        child: Padding(
          padding: EdgeInsets.all(16.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.record_voice_over,
                      color: Colors.purple, size: 24.sp),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Text('OpenAI 格式 TTS 接口',
                        style: TextStyle(
                            fontSize: 16.sp, fontWeight: FontWeight.bold)),
                  ),
                  ElevatedButton.icon(
                    onPressed: _addOpenAITtsProvider,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('添加'),
                  ),
                ],
              ),
              SizedBox(height: 8.h),
              Text(
                '支持自定义名称、API Key、接口地址、模型、音色和风格预置。已内置 Xiaomi MIMO V2.5 模板。',
                style: TextStyle(fontSize: 12.sp, color: Colors.grey.shade700),
              ),
              SizedBox(height: 16.h),
              if (configs.isEmpty)
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(16.w),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    '还没有自定义 OpenAI TTS 接口。点击右上角“添加”开始配置。',
                    style:
                        TextStyle(fontSize: 13.sp, color: Colors.grey.shade700),
                  ),
                )
              else
                ...configs.map(_buildOpenAITtsCard),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildOpenAITtsCard(OpenAITtsConfig config) {
    final route = '${TtsService.openAITtsPrefix}${config.id}';
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (config.isDefault)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                  margin: EdgeInsets.only(right: 8.w),
                  decoration: BoxDecoration(
                    color: Colors.purple,
                    borderRadius: BorderRadius.circular(6.r),
                  ),
                  child: Text('默认',
                      style: TextStyle(
                          fontSize: 10.sp,
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                ),
              Expanded(
                child: Text(config.name,
                    style: TextStyle(
                        fontSize: 15.sp, fontWeight: FontWeight.bold)),
              ),
              PopupMenuButton<String>(
                onSelected: (value) => _handleProviderAction(value, config),
                itemBuilder: (context) => [
                  if (!config.isDefault)
                    const PopupMenuItem(value: 'default', child: Text('设为默认')),
                  PopupMenuItem(
                      value: 'use_global',
                      child: Text(_tts.getGlobalTtsRoute() == route
                          ? '当前已是全局默认'
                          : '设为全局引擎')),
                  const PopupMenuItem(value: 'edit', child: Text('编辑')),
                  const PopupMenuItem(value: 'models', child: Text('刷新模型')),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('删除', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: 8.h),
          _buildInfoLine(
              '类型',
              config.providerType == 'xiaomi_mimo_v25'
                  ? 'Xiaomi MIMO V2.5'
                  : 'OpenAI 标准'),
          _buildInfoLine('地址', config.baseUrl),
          _buildInfoLine('模型',
              config.selectedModel.isNotEmpty ? config.selectedModel : '未选择'),
          _buildInfoLine('音色',
              config.selectedVoice.isNotEmpty ? config.selectedVoice : '未选择'),
          _buildInfoLine(
              '风格',
              config.selectedStylePreset.isNotEmpty
                  ? config.selectedStylePreset
                  : '默认'),
          if (config.models.isNotEmpty) ...[
            SizedBox(height: 8.h),
            Wrap(
              spacing: 6.w,
              runSpacing: 6.h,
              children: config.models.take(6).map((model) {
                final isSelected = model == config.selectedModel;
                return Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.purple.withOpacity(0.12)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6.r),
                  ),
                  child: Text(
                    model,
                    style: TextStyle(
                      fontSize: 10.sp,
                      color: isSelected ? Colors.purple : Colors.grey.shade700,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoLine(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 4.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56.w,
            child: Text(label,
                style: TextStyle(fontSize: 12.sp, color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(fontSize: 12.sp, color: Colors.grey.shade800)),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller,
      {String? hint, VoidCallback? onBlur}) {
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
            Text('语音风格 (Voice)',
                style: TextStyle(fontSize: 12.sp, color: Colors.grey.shade700)),
            Obx(() {
              if (_isLoadingVoices.value) {
                return Padding(
                  padding: EdgeInsets.only(left: 8.w),
                  child: SizedBox(
                    width: 12.w,
                    height: 12.h,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  ),
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
            } else if (_baseUrlController.text.isNotEmpty) {
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
                  child: Obx(
                    () => Text(
                      _selectedVoice.value,
                      style: TextStyle(fontSize: 14.sp),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
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
    final searchController = TextEditingController();
    final filteredVoices = RxList<String>.from(_cfttsVoices);

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
                  Text('选择语音风格 (${_cfttsVoices.length}个)',
                      style: TextStyle(
                          fontSize: 18.sp, fontWeight: FontWeight.bold)),
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
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.r)),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
                onChanged: (text) {
                  if (text.isEmpty) {
                    filteredVoices.assignAll(_cfttsVoices);
                  } else {
                    filteredVoices.assignAll(_cfttsVoices.where(
                        (v) => v.toLowerCase().contains(text.toLowerCase())));
                  }
                },
              ),
            ),
            SizedBox(height: 8.h),
            Expanded(
              child: Obx(
                () => ListView.builder(
                  itemCount: filteredVoices.length,
                  itemBuilder: (context, index) {
                    final voice = filteredVoices[index];
                    final isSelected = voice == _selectedVoice.value;
                    return ListTile(
                      title: Text(voice, style: TextStyle(fontSize: 14.sp)),
                      trailing: isSelected
                          ? const Icon(Icons.check, color: Colors.blue)
                          : null,
                      tileColor:
                          isSelected ? Colors.blue.withOpacity(0.05) : null,
                      onTap: () {
                        _selectedVoice.value = voice;
                        _saveCfttsConfig();
                        Get.back();
                      },
                    );
                  },
                ),
              ),
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
            Text(label,
                style: TextStyle(fontSize: 12.sp, color: Colors.grey.shade700)),
            if (isLoading) ...[
              SizedBox(width: 8.w),
              SizedBox(
                width: 12.w,
                height: 12.h,
                child: const CircularProgressIndicator(strokeWidth: 2),
              ),
            ]
          ],
        ),
        SizedBox(height: 4.h),
        DropdownButtonFormField<String>(
          isExpanded: true,
          value: items.contains(value)
              ? value
              : (items.isNotEmpty ? items.first : value),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            contentPadding:
                EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
          ),
          items: items
              .map((e) => DropdownMenuItem(
                  value: e,
                  child: Text(labels?[e] ?? e,
                      style: const TextStyle(fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1)))
              .toList(),
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
      final response = await AndroidBackgroundNetworkService.protect(
        'tts_health_${DateTime.now().microsecondsSinceEpoch}',
        () => http.get(url).timeout(const Duration(seconds: 5)),
        title: 'StarBank 语音',
        text: '正在检测语音服务',
      );
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

  Future<void> _addOpenAITtsProvider() async {
    final result = await _showProviderDialog();
    if (result == null) return;
    await _tts.addOpenAITtsConfig(result);
    ToastUtils.showSuccess('接口已添加');
  }

  Future<void> _editOpenAITtsProvider(OpenAITtsConfig config) async {
    final result = await _showProviderDialog(existing: config);
    if (result == null) return;
    await _tts.updateOpenAITtsConfig(result);
    ToastUtils.showSuccess('接口已更新');
  }

  Future<void> _handleProviderAction(
      String action, OpenAITtsConfig config) async {
    switch (action) {
      case 'default':
        await _tts.setDefaultOpenAITtsConfig(config.id);
        ToastUtils.showSuccess('已设为默认接口');
        break;
      case 'use_global':
        await _tts
            .setGlobalTtsRoute('${TtsService.openAITtsPrefix}${config.id}');
        ToastUtils.showSuccess('已设为全局默认语音引擎');
        break;
      case 'edit':
        await _editOpenAITtsProvider(config);
        break;
      case 'models':
        await _refreshProviderModels(config);
        break;
      case 'delete':
        await _deleteProvider(config);
        break;
    }
  }

  Future<void> _refreshProviderModels(OpenAITtsConfig config) async {
    final models = await _tts.fetchOpenAITtsModels(config);
    if (models.isEmpty) {
      ToastUtils.showWarning('未获取到模型列表，保留原有设置');
      return;
    }
    config.models = models;
    if (!models.contains(config.selectedModel)) {
      config.selectedModel = models.first;
    }
    await _tts.updateOpenAITtsConfig(config);
    ToastUtils.showSuccess('模型列表已刷新');
  }

  Future<void> _deleteProvider(OpenAITtsConfig config) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('删除接口'),
            content: Text('确定删除 ${config.name} 吗？'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消')),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('删除')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    await _tts.deleteOpenAITtsConfig(config.id);
    ToastUtils.showSuccess('接口已删除');
  }

  Future<OpenAITtsConfig?> _showProviderDialog(
      {OpenAITtsConfig? existing}) async {
    final template = existing == null
        ? OpenAITtsConfig.createXiaomiMimoTemplate()
        : OpenAITtsConfig.fromJson(existing.toJson());

    final nameController = TextEditingController(text: template.name);
    final baseUrlController = TextEditingController(text: template.baseUrl);
    final apiKeyController = TextEditingController(text: template.apiKey);
    final manualModelsController =
        TextEditingController(text: template.models.join('\n'));
    final manualVoicesController =
        TextEditingController(text: template.voices.join('\n'));
    final manualVoiceValueController =
        TextEditingController(text: template.selectedVoice);
    final manualStylesController = TextEditingController(
      text: template.stylePresets.join('\n'),
    );
    final manualStyleValueController =
        TextEditingController(text: template.selectedStylePreset);

    final selectedProviderType = template.providerType.obs;
    final selectedAuthType = template.authType.obs;
    final selectedAudioFormat = template.audioFormat.obs;
    final isDefault = template.isDefault.obs;

    final availableModels = RxList<String>.from(template.models);
    final availableVoices = RxList<String>.from(template.voices);
    final availableStyles = RxList<String>.from(template.stylePresets);

    final selectedModel = template.selectedModel.obs;
    final selectedVoice = template.selectedVoice.obs;
    final selectedStyle = template.selectedStylePreset.obs;

    final isLoadingModels = false.obs;
    final isLoadingVoices = false.obs;

    List<String> parseLines(String text) {
      return text
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    List<String> presetModelsFor(String providerType) {
      if (providerType == 'xiaomi_mimo_v25') {
        return const [
          'mimo-v2.5-tts',
          'mimo-v2.5-tts-voicedesign',
          'mimo-v2.5-tts-voiceclone',
        ];
      }
      return const [];
    }

    List<String> presetVoicesFor(String providerType) {
      if (providerType == 'xiaomi_mimo_v25') {
        return OpenAITtsConfig.xiaomiMimoV25PresetVoices;
      }
      return const [];
    }

    List<String> presetStylesFor(String providerType) {
      if (providerType == 'xiaomi_mimo_v25') {
        return const ['默认', '自然', '温柔', '开心', '讲故事'];
      }
      return const [];
    }

    String normalizeVoiceForProvider(String providerType, String voice) {
      if (providerType == 'xiaomi_mimo_v25') {
        return OpenAITtsConfig.normalizeXiaomiMimoV25Voice(voice);
      }
      return voice;
    }

    void ensureSelectedValue(RxList<String> items, RxString selected,
        {String fallback = ''}) {
      if (items.contains(selected.value)) return;
      if (items.isNotEmpty) {
        selected.value = items.first;
      } else {
        selected.value = fallback;
      }
    }

    void applyProviderDefaults(String providerType) {
      if (providerType == 'xiaomi_mimo_v25') {
        selectedAuthType.value = 'api-key';
        selectedAudioFormat.value = 'wav';
        if (baseUrlController.text.trim().isEmpty ||
            baseUrlController.text.trim() == 'https://api.openai.com/v1') {
          baseUrlController.text = 'https://api.xiaomimimo.com/v1';
        }
      } else {
        if (baseUrlController.text.trim().isEmpty ||
            baseUrlController.text.trim() == 'https://api.xiaomimimo.com/v1') {
          baseUrlController.text = 'https://api.openai.com/v1';
        }
        if (selectedAuthType.value != 'bearer') {
          selectedAuthType.value = 'bearer';
        }
        if (selectedAudioFormat.value == 'wav') {
          selectedAudioFormat.value = 'mp3';
        }
      }

      final presetModels = presetModelsFor(providerType);
      final presetVoices = presetVoicesFor(providerType);
      final presetStyles = presetStylesFor(providerType);

      if (providerType == 'xiaomi_mimo_v25') {
        selectedVoice.value =
            normalizeVoiceForProvider(providerType, selectedVoice.value);
      }

      availableModels.assignAll(
        presetModels.isNotEmpty
            ? presetModels
            : parseLines(manualModelsController.text),
      );
      availableVoices.assignAll(
        presetVoices.isNotEmpty
            ? presetVoices
            : parseLines(manualVoicesController.text),
      );
      availableStyles.assignAll(
        presetStyles.isNotEmpty
            ? presetStyles
            : parseLines(manualStylesController.text),
      );

      if (presetVoices.isNotEmpty && selectedVoice.value.isEmpty) {
        selectedVoice.value = presetVoices.first;
      }
      if (presetStyles.isNotEmpty && selectedStyle.value.isEmpty) {
        selectedStyle.value = presetStyles.first;
      }
      manualVoiceValueController.text = selectedVoice.value;
      manualStyleValueController.text = selectedStyle.value;

      ensureSelectedValue(availableModels, selectedModel);
      ensureSelectedValue(availableVoices, selectedVoice);
      ensureSelectedValue(availableStyles, selectedStyle, fallback: '默认');
    }

    Future<void> refreshModels() async {
      final draft = OpenAITtsConfig(
        id: template.id,
        name: nameController.text.trim().isEmpty
            ? template.name
            : nameController.text.trim(),
        baseUrl: baseUrlController.text.trim(),
        apiKey: apiKeyController.text.trim(),
        providerType: selectedProviderType.value,
        authType: selectedAuthType.value,
        models: availableModels.toList(),
        selectedModel: selectedModel.value,
        voices: availableVoices.toList(),
        selectedVoice: selectedVoice.value,
        stylePresets: availableStyles.toList(),
        selectedStylePreset: selectedStyle.value,
        audioFormat: selectedAudioFormat.value,
        isDefault: isDefault.value,
        supportsModelFetch: true,
        supportsVoiceFetch: false,
        isEnabled: true,
      );

      isLoadingModels.value = true;
      try {
        final models = await _tts.fetchOpenAITtsModels(draft);
        if (models.isEmpty) {
          ToastUtils.showWarning('未获取到模型列表');
          return;
        }
        availableModels.assignAll(models);
        manualModelsController.text = models.join('\n');
        ensureSelectedValue(availableModels, selectedModel);
        ToastUtils.showSuccess('模型列表已刷新');
      } finally {
        isLoadingModels.value = false;
      }
    }

    Future<void> refreshVoices() async {
      final draft = OpenAITtsConfig(
        id: template.id,
        name: nameController.text.trim().isEmpty
            ? template.name
            : nameController.text.trim(),
        baseUrl: baseUrlController.text.trim(),
        apiKey: apiKeyController.text.trim(),
        providerType: selectedProviderType.value,
        authType: selectedAuthType.value,
        models: availableModels.toList(),
        selectedModel: selectedModel.value,
        voices: availableVoices.toList(),
        selectedVoice: selectedVoice.value,
        stylePresets: availableStyles.toList(),
        selectedStylePreset: selectedStyle.value,
        audioFormat: selectedAudioFormat.value,
        isDefault: isDefault.value,
        supportsModelFetch: true,
        supportsVoiceFetch: false,
        isEnabled: true,
      );

      isLoadingVoices.value = true;
      try {
        final voices = await _tts.fetchOpenAITtsVoices(draft);
        if (voices.isEmpty) {
          ToastUtils.showWarning('未获取到音色列表');
          return;
        }
        availableVoices.assignAll(voices);
        manualVoicesController.text = voices.join('\n');
        ensureSelectedValue(availableVoices, selectedVoice);
        manualVoiceValueController.text = selectedVoice.value;
        ToastUtils.showSuccess('音色列表已刷新');
      } finally {
        isLoadingVoices.value = false;
      }
    }

    applyProviderDefaults(selectedProviderType.value);

    return showDialog<OpenAITtsConfig>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                  existing == null ? '添加 OpenAI TTS 接口' : '编辑 OpenAI TTS 接口'),
              content: SizedBox(
                width: 520.w,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: '名称',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      SizedBox(height: 12.h),
                      Obx(
                        () => DropdownButtonFormField<String>(
                          value: selectedProviderType.value,
                          decoration: const InputDecoration(
                            labelText: 'Provider 类型',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'xiaomi_mimo_v25',
                              child: Text('Xiaomi MIMO V2.5'),
                            ),
                            DropdownMenuItem(
                              value: 'openai_standard',
                              child: Text('OpenAI 标准'),
                            ),
                          ],
                          onChanged: (val) {
                            if (val == null) return;
                            selectedProviderType.value = val;
                            applyProviderDefaults(val);
                            setDialogState(() {});
                          },
                        ),
                      ),
                      SizedBox(height: 12.h),
                      TextField(
                        controller: baseUrlController,
                        decoration: const InputDecoration(
                          labelText: '接口地址',
                          hintText: 'https://api.xiaomimimo.com/v1',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      SizedBox(height: 12.h),
                      TextField(
                        controller: apiKeyController,
                        decoration: const InputDecoration(
                          labelText: 'API Key',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      SizedBox(height: 12.h),
                      Obx(
                        () => DropdownButtonFormField<String>(
                          value: selectedAuthType.value,
                          decoration: const InputDecoration(
                            labelText: '认证方式',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 'api-key', child: Text('api-key')),
                            DropdownMenuItem(
                                value: 'bearer', child: Text('Bearer')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              selectedAuthType.value = val;
                            }
                          },
                        ),
                      ),
                      SizedBox(height: 16.h),
                      Obx(() {
                        final hasChoices = availableModels.isNotEmpty;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '模型',
                                    style: TextStyle(
                                      fontSize: 12.sp,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: isLoadingModels.value
                                      ? null
                                      : refreshModels,
                                  icon: isLoadingModels.value
                                      ? SizedBox(
                                          width: 14.w,
                                          height: 14.h,
                                          child:
                                              const CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.refresh, size: 16),
                                  label: const Text('拉取列表'),
                                ),
                              ],
                            ),
                            SizedBox(height: 4.h),
                            if (hasChoices)
                              DropdownButtonFormField<String>(
                                value: availableModels.contains(selectedModel.value)
                                    ? selectedModel.value
                                    : availableModels.first,
                                decoration: const InputDecoration(
                                  labelText: '当前模型',
                                  border: OutlineInputBorder(),
                                ),
                                items: availableModels
                                    .map(
                                      (item) => DropdownMenuItem<String>(
                                        value: item,
                                        child: Text(item,
                                            overflow: TextOverflow.ellipsis),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    selectedModel.value = val;
                                  }
                                },
                              )
                            else
                              Container(
                                width: double.infinity,
                                padding: EdgeInsets.all(12.w),
                                decoration: BoxDecoration(
                                  border:
                                      Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(4.r),
                                ),
                                child: Text(
                                  '点击“拉取列表”获取模型后选择',
                                  style: TextStyle(
                                      fontSize: 13.sp,
                                      color: Colors.grey.shade700),
                                ),
                              ),
                          ],
                        );
                      }),
                      SizedBox(height: 12.h),
                      Obx(() {
                        final hasPresetVoices =
                            presetVoicesFor(selectedProviderType.value)
                                .isNotEmpty;
                        final supportsFetch =
                            selectedProviderType.value != 'xiaomi_mimo_v25';
                        final hasChoices = availableVoices.isNotEmpty;
                        final useManualFallback =
                            !supportsFetch && !hasPresetVoices;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '音色',
                                    style: TextStyle(
                                      fontSize: 12.sp,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                                if (supportsFetch)
                                  OutlinedButton.icon(
                                    onPressed: isLoadingVoices.value
                                        ? null
                                        : refreshVoices,
                                    icon: isLoadingVoices.value
                                        ? SizedBox(
                                            width: 14.w,
                                            height: 14.h,
                                            child:
                                                const CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.refresh, size: 16),
                                    label: const Text('拉取列表'),
                                  ),
                              ],
                            ),
                            SizedBox(height: 4.h),
                            if (hasChoices)
                              DropdownButtonFormField<String>(
                                value: availableVoices.contains(selectedVoice.value)
                                    ? selectedVoice.value
                                    : availableVoices.first,
                                decoration: const InputDecoration(
                                  labelText: '当前音色',
                                  border: OutlineInputBorder(),
                                ),
                                items: availableVoices
                                    .map(
                                      (item) => DropdownMenuItem<String>(
                                        value: item,
                                        child: Text(item,
                                            overflow: TextOverflow.ellipsis),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    selectedVoice.value = val;
                                  }
                                },
                              )
                            else if (useManualFallback) ...[
                              TextField(
                                controller: manualVoicesController,
                                minLines: 2,
                                maxLines: 5,
                                decoration: const InputDecoration(
                                  labelText: '语音列表（每行一个）',
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (value) {
                                  final voices = parseLines(value);
                                  availableVoices.assignAll(voices);
                                  ensureSelectedValue(
                                      availableVoices, selectedVoice);
                                  manualVoiceValueController.text =
                                      selectedVoice.value;
                                  setDialogState(() {});
                                },
                              ),
                              SizedBox(height: 12.h),
                              TextField(
                                controller: manualVoiceValueController,
                                decoration: const InputDecoration(
                                  labelText: '当前音色',
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (value) =>
                                    selectedVoice.value = value.trim(),
                              ),
                            ] else
                              Container(
                                width: double.infinity,
                                padding: EdgeInsets.all(12.w),
                                decoration: BoxDecoration(
                                  border:
                                      Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(4.r),
                                ),
                                child: Text(
                                  supportsFetch
                                      ? '点击“拉取列表”获取音色后选择'
                                      : '当前 provider 暂无可选音色列表',
                                  style: TextStyle(
                                      fontSize: 13.sp,
                                      color: Colors.grey.shade700),
                                ),
                              ),
                          ],
                        );
                      }),
                      SizedBox(height: 12.h),
                      Obx(() {
                        final hasPresetStyles =
                            presetStylesFor(selectedProviderType.value)
                                .isNotEmpty;
                        final useManualFallback =
                            !hasPresetStyles && availableStyles.isEmpty;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (availableStyles.isNotEmpty)
                              DropdownButtonFormField<String>(
                                value: availableStyles.contains(selectedStyle.value)
                                    ? selectedStyle.value
                                    : availableStyles.first,
                                decoration: const InputDecoration(
                                  labelText: '风格',
                                  border: OutlineInputBorder(),
                                ),
                                items: availableStyles
                                    .map(
                                      (item) => DropdownMenuItem<String>(
                                        value: item,
                                        child: Text(item,
                                            overflow: TextOverflow.ellipsis),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    selectedStyle.value = val;
                                  }
                                },
                              )
                            else if (useManualFallback) ...[
                              TextField(
                                controller: manualStylesController,
                                minLines: 2,
                                maxLines: 5,
                                decoration: const InputDecoration(
                                  labelText: '风格预置（每行一个）',
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (value) {
                                  final styles = parseLines(value);
                                  availableStyles.assignAll(styles);
                                  ensureSelectedValue(
                                    availableStyles,
                                    selectedStyle,
                                    fallback: '默认',
                                  );
                                  manualStyleValueController.text =
                                      selectedStyle.value;
                                  setDialogState(() {});
                                },
                              ),
                              SizedBox(height: 12.h),
                              TextField(
                                controller: manualStyleValueController,
                                decoration: const InputDecoration(
                                  labelText: '当前风格',
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (value) =>
                                    selectedStyle.value = value.trim(),
                              ),
                            ] else
                              Container(
                                width: double.infinity,
                                padding: EdgeInsets.all(12.w),
                                decoration: BoxDecoration(
                                  border:
                                      Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(4.r),
                                ),
                                child: Text(
                                  '当前 provider 未配置风格预置，默认按普通朗读处理',
                                  style: TextStyle(
                                      fontSize: 13.sp,
                                      color: Colors.grey.shade700),
                                ),
                              ),
                          ],
                        );
                      }),
                      SizedBox(height: 12.h),
                      Obx(
                        () => DropdownButtonFormField<String>(
                          value: selectedAudioFormat.value,
                          decoration: const InputDecoration(
                            labelText: '音频格式',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'wav', child: Text('wav')),
                            DropdownMenuItem(value: 'mp3', child: Text('mp3')),
                            DropdownMenuItem(value: 'aac', child: Text('aac')),
                            DropdownMenuItem(
                                value: 'opus', child: Text('opus')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              selectedAudioFormat.value = val;
                            }
                          },
                        ),
                      ),
                      SizedBox(height: 12.h),
                      Obx(
                        () => CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('标记为默认接口'),
                          value: isDefault.value,
                          onChanged: (val) {
                            isDefault.value = val ?? false;
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    final baseUrl = baseUrlController.text.trim();
                    final apiKey = apiKeyController.text.trim();
                    if (name.isEmpty || baseUrl.isEmpty || apiKey.isEmpty) {
                      ToastUtils.showWarning('名称、接口地址、API Key 不能为空');
                      return;
                    }

                    final hasPresetVoices =
                        presetVoicesFor(selectedProviderType.value).isNotEmpty;
                    final supportsVoiceFetch =
                        selectedProviderType.value != 'xiaomi_mimo_v25';
                    final useManualVoiceFallback =
                        !supportsVoiceFetch && !hasPresetVoices;
                    final hasPresetStyles =
                        presetStylesFor(selectedProviderType.value).isNotEmpty;
                    final useManualStyleFallback =
                        !hasPresetStyles && availableStyles.isEmpty;

                    final models = availableModels.toList();
                    final voices = useManualVoiceFallback
                        ? parseLines(manualVoicesController.text)
                        : availableVoices.toList();
                    final selectedVoiceValue = normalizeVoiceForProvider(
                      selectedProviderType.value,
                      selectedVoice.value.trim().isNotEmpty
                          ? selectedVoice.value.trim()
                          : (voices.isNotEmpty ? voices.first : ''),
                    );
                    final styles = useManualStyleFallback
                        ? parseLines(manualStylesController.text)
                        : availableStyles.toList();

                    final result = OpenAITtsConfig(
                      id: template.id,
                      name: name,
                      baseUrl: baseUrl,
                      apiKey: apiKey,
                      providerType: selectedProviderType.value,
                      authType: selectedAuthType.value,
                      models: models,
                      selectedModel: selectedModel.value.trim().isNotEmpty
                          ? selectedModel.value.trim()
                          : (models.isNotEmpty ? models.first : ''),
                      voices: voices,
                      selectedVoice: selectedVoiceValue,
                      stylePresets: styles.isEmpty ? ['默认'] : styles,
                      selectedStylePreset: selectedStyle.value.trim().isNotEmpty
                          ? selectedStyle.value.trim()
                          : (styles.isNotEmpty ? styles.first : '默认'),
                      audioFormat: selectedAudioFormat.value,
                      isDefault: isDefault.value,
                      supportsModelFetch: true,
                      supportsVoiceFetch: supportsVoiceFetch,
                      isEnabled: true,
                    );

                    Navigator.pop(ctx, result);
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
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
        child: Obx(
          () => Column(
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
          ),
        ),
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
                Text('系统语音引擎', style: TextStyle(fontSize: 14.sp)),
                const Spacer(),
                Obx(
                  () => Text(
                    _tts.getEngineDisplayName(_tts.currentEngine.value),
                    style: TextStyle(fontSize: 12.sp, color: Colors.blue),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            Obx(
              () => Wrap(
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
                        _speak('已切换到 ${_tts.getEngineDisplayName(engine)}');
                      }
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
                  '系统声音选择',
                  style:
                      TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SizedBox(height: 8.h),
            Text(
              '如需更换系统 TTS 的男声/女声或其他音色，请在对应的 TTS 引擎应用中设置。',
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
      ToastUtils.showInfo('请手动打开：设置 → 辅助功能 → 文字转语音');
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
