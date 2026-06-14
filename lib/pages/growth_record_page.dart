import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../controllers/app_mode_controller.dart';
import '../controllers/user_controller.dart';
import '../models/baby.dart';
import '../models/growth_record.dart';
import '../models/openai_config.dart';
import '../services/growth_standard_service.dart';
import '../services/openai_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../utils/baby_profile_utils.dart';
import '../widgets/image_utils.dart';
import '../widgets/toast_utils.dart';
import 'openai_settings_page.dart';

class GrowthRecordPage extends StatefulWidget {
  const GrowthRecordPage({super.key});

  @override
  State<GrowthRecordPage> createState() => _GrowthRecordPageState();
}

class _GrowthRecordPageState extends State<GrowthRecordPage>
    with SingleTickerProviderStateMixin {
  final _storage = Get.find<StorageService>();
  final _user = Get.find<UserController>();
  final _mode = Get.find<AppModeController>();
  final _openAI = Get.find<OpenAIService>();

  late TabController _tabController;
  late Box _settingsBox;
  OpenAIConfig? _selectedConfig;
  String _selectedModel = '';
  List<GrowthRecord> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _init();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _settingsBox = await Hive.openBox('growth_record_settings');
    final configId = _settingsBox.get('selected_config_id', defaultValue: '');
    _selectedModel = _settingsBox.get('selected_model', defaultValue: '');
    _selectedConfig =
        _openAI.configs.firstWhereOrNull((c) => c.id == configId) ??
            _openAI.currentConfig.value;
    if (_selectedConfig != null &&
        _selectedModel.isNotEmpty &&
        !_selectedConfig!.models.contains(_selectedModel)) {
      _selectedModel = _selectedConfig!.selectedModel;
      await _settingsBox.put('selected_model', _selectedModel);
    }
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
    _records = _storage.growthRecordBox.values
        .where((r) => r.babyId == babyId && !r.isDeleted)
        .toList()
      ..sort((a, b) => b.recordDate.compareTo(a.recordDate));
  }

  @override
  Widget build(BuildContext context) {
    final baby = _user.currentBaby.value;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          '生长记录',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.textMain,
        elevation: 0,
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
              if (value == 'manual') _showRecordEditor();
              if (value == 'ocr') _importFromScreenshot();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'manual', child: Text('手动添加')),
              PopupMenuItem(value: 'ocr', child: Text('从截图识别导入')),
            ],
            icon: const Icon(Icons.add),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelPadding: EdgeInsets.symmetric(horizontal: 2.w),
          labelColor: AppTheme.textMain,
          unselectedLabelColor: AppTheme.textMain,
          labelStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w900),
          unselectedLabelStyle:
              TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w800),
          indicatorColor: const Color(0xFFFFC83D),
          indicatorWeight: 4,
          indicatorSize: TabBarIndicatorSize.label,
          tabs: [
            _growthTab('记录列表'),
            _growthTab('身高曲线'),
            _growthTab('体重曲线'),
            _growthTab('头围曲线'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : baby == null
              ? const Center(child: Text('请先选择宝宝'))
              : TabBarView(
                  controller: _tabController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildList(),
                    _buildChart(baby, GrowthMetric.height),
                    _buildChart(baby, GrowthMetric.weight),
                    _buildChart(baby, GrowthMetric.headCircumference),
                  ],
                ),
    );
  }

  Widget _buildList() {
    if (_records.isEmpty) {
      return _emptyState('还没有生长记录');
    }
    final baby = _user.currentBaby.value;
    if (baby == null) return const Center(child: Text('请先选择宝宝'));
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _records.length,
      separatorBuilder: (_, __) => Container(
        height: 10.h,
        color: const Color(0xFFF4F4F4),
      ),
      itemBuilder: (_, index) {
        final record = _records[index];
        return _buildRecordItem(baby, record);
      },
    );
  }

  Tab _growthTab(String text) {
    return Tab(
      height: 46.h,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(text),
      ),
    );
  }

  Widget _buildChart(Baby baby, GrowthMetric metric) {
    final points = _records.where((r) => _valueOf(r, metric) != null).toList()
      ..sort((a, b) => a.recordDate.compareTo(b.recordDate));
    final ageMonths = baby.birthDate == null
        ? -1
        : BabyProfileUtils.ageMonths(baby, DateTime.now());
    final bands = GrowthStandardService.bandsFor(baby: baby, metric: metric);
    final canShowChart = baby.birthDate != null && bands.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 32.h),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 22.w),
          child: Text(
            '${_metricTitle(metric)}(${_metricUnit(metric)})',
            style: TextStyle(
              fontSize: 17.sp,
              fontWeight: FontWeight.w900,
              color: AppTheme.textMain,
            ),
          ),
        ),
        SizedBox(height: 18.h),
        Expanded(
          child: !canShowChart
              ? _chartUnavailable(
                  ageMonths >= 0
                      ? GrowthStandardService.unavailableReason(
                          metric,
                          ageMonths,
                        )
                      : '请先设置生日和性别后查看国家标准曲线',
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    return SizedBox(
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      child: GrowthChart(
                        baby: baby,
                        records: points,
                        metric: metric,
                      ),
                    );
                  },
                ),
        ),
        SizedBox(height: 18.h),
        Center(
          child: Text(
            '曲线根据《${GrowthStandardService.sourceTitle}》绘制',
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w800,
              color: AppTheme.textMain,
            ),
          ),
        ),
        TextButton(
          onPressed: _showGrowthStandardInfo,
          child: Text(
            '更多详情 >',
            style: TextStyle(
              fontSize: 15.sp,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF2F68A8),
            ),
          ),
        ),
        SizedBox(height: 24.h),
      ],
    );
  }

  Widget _buildRecordItem(Baby baby, GrowthRecord record) {
    final metrics = <_RecordMetric>[
      if (record.heightCm != null)
        _RecordMetric('身高', _formatGrowthValue(record.heightCm!), 'cm'),
      if (record.weightKg != null)
        _RecordMetric('体重', _formatGrowthValue(record.weightKg!), 'kg'),
      if (record.headCircumferenceCm != null)
        _RecordMetric(
          '头围',
          _formatGrowthValue(record.headCircumferenceCm!),
          'cm',
        ),
    ];
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(18.w, 15.h, 18.w, 18.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '${DateFormat('yyyy-MM-dd').format(record.recordDate)} ${_ageTextAt(baby, record.recordDate)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15.sp,
                    color: const Color(0xFF8E8E8E),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (!_mode.isChildMode)
                PopupMenuButton<String>(
                  tooltip: '更多',
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.more_horiz,
                    color: Colors.grey.shade500,
                    size: 20.sp,
                  ),
                  onSelected: (value) async {
                    if (value == 'edit') _showRecordEditor(record: record);
                    if (value == 'delete') {
                      record.deletedAt = DateTime.now();
                      record.updatedAt = DateTime.now();
                      await record.save();
                      setState(_loadRecords);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('编辑')),
                    PopupMenuItem(value: 'delete', child: Text('移到回收站')),
                  ],
                ),
            ],
          ),
          SizedBox(height: 12.h),
          Text(
            _growthStatusText(baby, record),
            style: TextStyle(
              fontSize: 13.5.sp,
              color: const Color(0xFF55C878),
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 15.h),
          Divider(height: 1, color: const Color(0xFFE8E8E8)),
          SizedBox(height: 17.h),
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = metrics.length == 1
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 16.w) / 2;
              return Wrap(
                spacing: 16.w,
                runSpacing: 15.h,
                children: [
                  for (final metric in metrics)
                    SizedBox(
                      width: itemWidth,
                      child: _metricValue(metric),
                    ),
                ],
              );
            },
          ),
          if (record.note.isNotEmpty) ...[
            SizedBox(height: 12.h),
            Text(
              record.note,
              style: TextStyle(
                fontSize: 12.sp,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metricValue(_RecordMetric metric) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          metric.label,
          style: TextStyle(
            fontSize: 16.sp,
            color: AppTheme.textMain,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(width: 10.w),
        Flexible(
          child: Text(
            metric.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 22.sp,
              height: 1,
              color: const Color(0xFF55C878),
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        SizedBox(width: 6.w),
        Padding(
          padding: EdgeInsets.only(bottom: 2.h),
          child: Text(
            metric.unit,
            style: TextStyle(
              fontSize: 16.sp,
              color: AppTheme.textMain,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        SizedBox(height: 10.h),
      ],
    );
  }

  Widget _chartUnavailable(String message) {
    return Center(
      child: Text(
        message,
        style: TextStyle(
          color: Colors.grey.shade600,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _growthStatusText(Baby baby, GrowthRecord record) {
    final statuses = <_MetricStatus>[
      if (record.heightCm != null)
        _metricStatus(
          baby,
          record,
          GrowthMetric.height,
          record.heightCm!,
        ),
      if (record.weightKg != null)
        _metricStatus(
          baby,
          record,
          GrowthMetric.weight,
          record.weightKg!,
        ),
      if (record.headCircumferenceCm != null)
        _metricStatus(
          baby,
          record,
          GrowthMetric.headCircumference,
          record.headCircumferenceCm!,
        ),
    ];
    if (statuses.isEmpty) return record.note.isNotEmpty ? record.note : '已记录';

    final abnormal = statuses.where((status) => !status.normal).toList();
    if (abnormal.isNotEmpty) {
      return abnormal
          .map((status) => '${status.label}${status.direction}')
          .join('，');
    }

    final allKnown = statuses.every((status) => status.hasStandard);
    if (!allKnown) return '${statuses.map((s) => s.label).join()}已记录';
    if (statuses.length >= 3) return '宝宝发育正常';
    return '${statuses.map((status) => status.label).join()}标准';
  }

  _MetricStatus _metricStatus(
    Baby baby,
    GrowthRecord record,
    GrowthMetric metric,
    double value,
  ) {
    final band = GrowthStandardService.bandAt(
      baby: baby,
      recordDate: record.recordDate,
      metric: metric,
    );
    if (band == null) {
      return _MetricStatus(_metricTitle(metric), true, '已记录', false);
    }
    if (value < band.low) {
      return _MetricStatus(_metricTitle(metric), false, '偏低', true);
    }
    if (value > band.high) {
      return _MetricStatus(_metricTitle(metric), false, '偏高', true);
    }
    return _MetricStatus(_metricTitle(metric), true, '标准', true);
  }

  String _ageTextAt(Baby baby, DateTime date) {
    if (baby.birthDate == null) return '';
    return BabyProfileUtils.ageText(baby, now: date);
  }

  String _metricTitle(GrowthMetric metric) {
    switch (metric) {
      case GrowthMetric.height:
        return '身高';
      case GrowthMetric.weight:
        return '体重';
      case GrowthMetric.headCircumference:
        return '头围';
    }
  }

  String _metricUnit(GrowthMetric metric) {
    switch (metric) {
      case GrowthMetric.height:
      case GrowthMetric.headCircumference:
        return 'cm';
      case GrowthMetric.weight:
        return 'kg';
    }
  }

  String _formatGrowthValue(double value) {
    final text = value.toStringAsFixed(2);
    if (text.endsWith('00')) return value.toStringAsFixed(1);
    if (text.endsWith('0')) return text.substring(0, text.length - 1);
    return text;
  }

  void _showGrowthStandardInfo() {
    Get.defaultDialog(
      title: GrowthStandardService.sourceTitle,
      middleText:
          '曲线使用${GrowthStandardService.sourceDescription}常用月龄检查点绘制，浅蓝色区域为 3%-97% 参考范围，中间蓝线为 50%。\n\n仅作家庭记录参考，不能替代医生诊断。',
      textConfirm: '知道了',
      onConfirm: Get.back,
    );
  }

  Widget _emptyState(String text) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.monitor_weight_outlined,
              size: 64.sp, color: Colors.grey.shade300),
          SizedBox(height: 12.h),
          Text(text, style: TextStyle(color: Colors.grey.shade600)),
          if (!_mode.isChildMode) ...[
            SizedBox(height: 16.h),
            ElevatedButton.icon(
              onPressed: _showRecordEditor,
              icon: const Icon(Icons.add),
              label: const Text('添加记录'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showRecordEditor({GrowthRecord? record}) async {
    final baby = _user.currentBaby.value;
    if (baby == null) return;
    final date = (record?.recordDate ?? DateTime.now()).obs;
    final height =
        TextEditingController(text: record?.heightCm?.toString() ?? '');
    final weight =
        TextEditingController(text: record?.weightKg?.toString() ?? '');
    final head = TextEditingController(
        text: record?.headCircumferenceCm?.toString() ?? '');
    final note = TextEditingController(text: record?.note ?? '');

    await Get.defaultDialog(
      title: record == null ? '添加生长记录' : '编辑生长记录',
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
            _numberField(height, '身高 cm'),
            SizedBox(height: 10.h),
            _numberField(weight, '体重 kg'),
            SizedBox(height: 10.h),
            _numberField(head, '头围 cm'),
            SizedBox(height: 10.h),
            TextField(
              controller: note,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '备注',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      confirm: ElevatedButton(
        onPressed: () async {
          final now = DateTime.now();
          final item = record ??
              GrowthRecord(
                id: now.microsecondsSinceEpoch.toString(),
                babyId: baby.id,
                recordDate: date.value,
              );
          item
            ..recordDate = date.value
            ..heightCm = double.tryParse(height.text)
            ..weightKg = double.tryParse(weight.text)
            ..headCircumferenceCm = double.tryParse(head.text)
            ..note = note.text.trim()
            ..updatedAt = now;
          await _storage.growthRecordBox.put(item.id, item);
          Get.back();
          setState(_loadRecords);
        },
        child: const Text('保存'),
      ),
      cancel: TextButton(
        onPressed: Get.back,
        child: const Text('取消'),
      ),
    );
  }

  Widget _numberField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
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
    var loadingDialogOpen = true;
    Get.dialog(const Center(child: CircularProgressIndicator()),
        barrierDismissible: false);
    try {
      final response = await _openAI.chatWithImage(
        systemPrompt: '你是一个严谨的 OCR 助手，只返回 JSON，不要解释。',
        userMessage: '''
识别这张生长记录截图中的所有可见记录行，不要只取第一条。
只返回 JSON 对象，格式为：
{"records":[{"date":"yyyy-MM-dd","heightCm":数字或null,"weightKg":数字或null,"headCircumferenceCm":数字或null,"note":"简短备注"}]}
要求：
1. 每一条生长记录都要单独放进 records 数组。
2. 同一行可能只有身高、体重、头围中的一部分，无法确定的字段填 null。
3. 数值字段只填数字，不要带单位。
4. 如果截图里有备注、来源或测量场景，可写入 note；没有则为空字符串。
''',
        imageBase64: image,
        config: _selectedConfig,
        model: _selectedModel.isNotEmpty ? _selectedModel : null,
        maxTokens: 4000,
      );
      Get.back();
      loadingDialogOpen = false;
      final records = _growthRecordsFromResponse(response, baby.id, image);
      if (records.length == 1) {
        await _showRecordEditor(record: records.first);
      } else {
        await _showImportPreview(records);
      }
    } catch (e) {
      if (loadingDialogOpen) Get.back();
      ToastUtils.showError(
        '截图识别失败：$e\n当前模型可能不支持图片识别，请切换支持视觉的模型后重试。',
      );
    }
  }

  List<GrowthRecord> _growthRecordsFromResponse(
    String response,
    String babyId,
    String image,
  ) {
    final decoded = _decodeJsonResponse(response);
    final maps = _asJsonRecords(decoded);
    final now = DateTime.now();
    final records = <GrowthRecord>[];
    for (var index = 0; index < maps.length; index++) {
      final data = maps[index];
      final height = _numberOrNull(_jsonField(data, const [
        'heightCm',
        'height',
        'stature',
        '身高',
        '身高cm',
      ]));
      final weight = _numberOrNull(_jsonField(data, const [
        'weightKg',
        'weight',
        '体重',
        '体重kg',
      ]));
      final head = _numberOrNull(_jsonField(data, const [
        'headCircumferenceCm',
        'headCircumference',
        'head',
        '头围',
        '头围cm',
      ]));
      final note = (_jsonField(data, const [
                'note',
                'remark',
                'remarks',
                'description',
                '备注',
                '说明',
              ]) ??
              '')
          .toString()
          .trim();

      if (height == null && weight == null && head == null && note.isEmpty) {
        continue;
      }

      final date = _dateOrNull(_jsonField(data, const [
            'date',
            'recordDate',
            'recordTime',
            'time',
            '日期',
            '记录日期',
            '记录时间',
          ])) ??
          DateTime.now();

      records.add(
        GrowthRecord(
          id: '${now.microsecondsSinceEpoch}_$index',
          babyId: babyId,
          recordDate: date,
          heightCm: height,
          weightKg: weight,
          headCircumferenceCm: head,
          note: note,
          sourceImagePath: index == 0 ? image : null,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    if (records.isEmpty) {
      throw const FormatException('AI 返回的 JSON 中没有可用生长记录');
    }
    return records;
  }

  dynamic _decodeJsonResponse(String response) {
    var text = response.trim();
    if (text.startsWith('```')) {
      text = text.replaceFirst(RegExp(r'^```json\s*|^```\s*'), '');
      if (text.endsWith('```')) text = text.substring(0, text.length - 3);
    }
    text = text.trim();
    try {
      return jsonDecode(text);
    } catch (_) {
      return jsonDecode(_extractJsonPayload(text));
    }
  }

  String _extractJsonPayload(String text) {
    final objectStart = text.indexOf('{');
    final arrayStart = text.indexOf('[');
    final starts = [objectStart, arrayStart].where((index) => index >= 0);
    if (starts.isEmpty) throw const FormatException('AI 返回内容不是 JSON');
    final start = starts.reduce((a, b) => a < b ? a : b);
    final end =
        text[start] == '{' ? text.lastIndexOf('}') : text.lastIndexOf(']');
    if (end <= start) throw const FormatException('AI 返回内容不是完整 JSON');
    return text.substring(start, end + 1);
  }

  List<Map<String, dynamic>> _asJsonRecords(dynamic value) {
    if (value is List) {
      return value.expand(_asJsonRecords).toList();
    }
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      for (final key in const ['records', 'items', 'data', 'result']) {
        final nested = _jsonField(map, [key]);
        if (nested is List) return _asJsonRecords(nested);
      }
      if (_looksLikeGrowthRecord(map)) return [map];
      final nestedRecords = map.values
          .where((item) => item is List || item is Map)
          .expand(_asJsonRecords)
          .toList();
      if (nestedRecords.isNotEmpty) return nestedRecords;
    }
    throw const FormatException('AI 返回的 JSON 中没有可用记录');
  }

  bool _looksLikeGrowthRecord(Map<String, dynamic> value) {
    const keys = [
      'date',
      'recordDate',
      'heightCm',
      'height',
      'weightKg',
      'weight',
      'headCircumferenceCm',
      'headCircumference',
      '身高',
      '体重',
      '头围',
      '日期',
    ];
    return keys.any((key) => _jsonField(value, [key]) != null);
  }

  dynamic _jsonField(Map<String, dynamic> data, Iterable<String> names) {
    final wanted = names.map(_normalizeJsonKey).toList();
    for (final entry in data.entries) {
      final key = _normalizeJsonKey(entry.key);
      if (wanted.any((name) => _jsonKeyMatches(key, name))) {
        final value = entry.value;
        if (value == null) return null;
        if (value is String && value.trim().isEmpty) return null;
        return value;
      }
    }
    return null;
  }

  bool _jsonKeyMatches(String key, String name) {
    if (key == name) return true;
    final hasNonAscii = name.runes.any((codeUnit) => codeUnit > 127);
    if (hasNonAscii || name.length >= 5) return key.contains(name);
    return key.endsWith(name);
  }

  String _normalizeJsonKey(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[\s_\-()（）]'), '');
  }

  DateTime? _dateOrNull(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    final parsed = DateTime.tryParse(text);
    if (parsed != null) return parsed;

    final ymd = RegExp(r'(\d{4})\D+(\d{1,2})\D+(\d{1,2})').firstMatch(text);
    if (ymd != null) {
      return DateTime(
        int.parse(ymd.group(1)!),
        int.parse(ymd.group(2)!),
        int.parse(ymd.group(3)!),
      );
    }

    final compact = RegExp(r'(\d{4})(\d{2})(\d{2})').firstMatch(text);
    if (compact != null) {
      return DateTime(
        int.parse(compact.group(1)!),
        int.parse(compact.group(2)!),
        int.parse(compact.group(3)!),
      );
    }
    return null;
  }

  double? _numberOrNull(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(value.toString());
    if (match == null) return null;
    return double.tryParse(match.group(0)!);
  }

  Future<void> _showImportPreview(List<GrowthRecord> records) async {
    final selected = List<bool>.filled(records.length, true);
    final imported = await Get.bottomSheet<bool>(
      StatefulBuilder(
        builder: (context, setSheetState) {
          final selectedCount = selected.where((value) => value).length;
          return Container(
            height: 560.h,
            padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 16.h),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Text(
                      '识别到 ${records.length} 条生长记录',
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        final allSelected = selected.every((value) => value);
                        setSheetState(() {
                          for (var i = 0; i < selected.length; i++) {
                            selected[i] = !allSelected;
                          }
                        });
                      },
                      child:
                          Text(selected.every((value) => value) ? '全不选' : '全选'),
                    ),
                  ],
                ),
                SizedBox(height: 8.h),
                Expanded(
                  child: ListView.builder(
                    itemCount: records.length,
                    itemBuilder: (_, index) {
                      final record = records[index];
                      return CheckboxListTile(
                        value: selected[index],
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (value) => setSheetState(
                          () => selected[index] = value ?? false,
                        ),
                        title: Text(
                          DateFormat('yyyy-MM-dd').format(record.recordDate),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Padding(
                          padding: EdgeInsets.only(top: 6.h),
                          child: Wrap(
                            spacing: 12.w,
                            runSpacing: 4.h,
                            children: [
                              if (record.heightCm != null)
                                Text('身高 ${record.heightCm} cm'),
                              if (record.weightKg != null)
                                Text('体重 ${record.weightKg} kg'),
                              if (record.headCircumferenceCm != null)
                                Text('头围 ${record.headCircumferenceCm} cm'),
                              if (record.note.isNotEmpty) Text(record.note),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(height: 12.h),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: selectedCount == 0
                        ? null
                        : () async {
                            for (var i = 0; i < records.length; i++) {
                              if (!selected[i]) continue;
                              await _storage.growthRecordBox
                                  .put(records[i].id, records[i]);
                            }
                            Get.back(result: true);
                          },
                    child: Text('导入 $selectedCount 条'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      isScrollControlled: true,
    );

    if (imported == true) {
      setState(_loadRecords);
      ToastUtils.showSuccess('已导入生长记录');
    }
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
                    const Text('生长记录 AI',
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
    final deleted = _storage.growthRecordBox.values
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
            const Text('生长记录回收站',
                style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: deleted.isEmpty
                  ? const Center(child: Text('回收站为空'))
                  : ListView.builder(
                      itemCount: deleted.length,
                      itemBuilder: (_, index) {
                        final record = deleted[index];
                        return ListTile(
                          title: Text(DateFormat('yyyy-MM-dd')
                              .format(record.recordDate)),
                          subtitle: Text(record.note),
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

  double? _valueOf(GrowthRecord record, GrowthMetric metric) {
    switch (metric) {
      case GrowthMetric.height:
        return record.heightCm;
      case GrowthMetric.weight:
        return record.weightKg;
      case GrowthMetric.headCircumference:
        return record.headCircumferenceCm;
    }
  }
}

class _RecordMetric {
  final String label;
  final String value;
  final String unit;

  const _RecordMetric(this.label, this.value, this.unit);
}

class _MetricStatus {
  final String label;
  final bool normal;
  final String direction;
  final bool hasStandard;

  const _MetricStatus(
    this.label,
    this.normal,
    this.direction,
    this.hasStandard,
  );
}

class GrowthChart extends StatefulWidget {
  const GrowthChart({
    super.key,
    required this.baby,
    required this.records,
    required this.metric,
  });

  final Baby baby;
  final List<GrowthRecord> records;
  final GrowthMetric metric;

  @override
  State<GrowthChart> createState() => _GrowthChartState();
}

class _GrowthChartState extends State<GrowthChart> {
  _ChartRange? _xRange;
  _ChartRange? _yRange;
  _ChartRange? _fullXRange;
  _ChartRange? _fullYRange;
  _ChartRange? _startXRange;
  _ChartRange? _startYRange;
  Offset? _startFocalPoint;

  @override
  void didUpdateWidget(covariant GrowthChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.metric != widget.metric ||
        oldWidget.baby.id != widget.baby.id ||
        oldWidget.baby.gender != widget.baby.gender ||
        oldWidget.baby.birthDate != widget.baby.birthDate) {
      _resetViewport();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bands = GrowthStandardService.bandsFor(
      baby: widget.baby,
      metric: widget.metric,
    );
    if (bands.isEmpty || widget.baby.birthDate == null) {
      return CustomPaint(
        painter: _GrowthChartPainter(
          baby: widget.baby,
          records: widget.records,
          metric: widget.metric,
          xRange: null,
          yRange: null,
        ),
        child: const SizedBox.expand(),
      );
    }

    _ensureViewport(bands);
    final xRange = _xRange;
    final yRange = _yRange;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: _resetViewport,
          onScaleStart: (details) {
            _startXRange = xRange;
            _startYRange = yRange;
            _startFocalPoint = details.localFocalPoint;
          },
          onScaleUpdate: (details) => _handleScaleUpdate(details, size),
          child: CustomPaint(
            painter: _GrowthChartPainter(
              baby: widget.baby,
              records: widget.records,
              metric: widget.metric,
              xRange: xRange,
              yRange: yRange,
            ),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }

  void _ensureViewport(List<GrowthStandardBand> bands) {
    final fullX = _ChartRange(bands.first.ageMonths, bands.last.ageMonths);
    final samples = _sampleGrowthBands(
      baby: widget.baby,
      metric: widget.metric,
      range: fullX,
    );
    final points = _recordPoints(fullX);
    final fullY = _growthValueRange(
      widget.metric,
      samples,
      points.map((point) => point.value).toList(),
    );

    if (_xRange == null ||
        _yRange == null ||
        _fullXRange != fullX ||
        _fullYRange != fullY) {
      final wasFullX =
          _xRange == null || _fullXRange == null || _xRange == _fullXRange;
      final wasFullY =
          _yRange == null || _fullYRange == null || _yRange == _fullYRange;
      _xRange = wasFullX ? fullX : _clampRange(_xRange!, fullX);
      _yRange = wasFullY ? fullY : _clampRange(_yRange!, fullY);
      _fullXRange = fullX;
      _fullYRange = fullY;
    }
  }

  List<_GrowthPoint> _recordPoints(_ChartRange xRange) {
    return widget.records
        .map((record) {
          final value = _growthMetricValue(record, widget.metric);
          final age = _exactAgeMonthsFor(widget.baby, record.recordDate);
          if (value == null || age == null) return null;
          return _GrowthPoint(age, value);
        })
        .whereType<_GrowthPoint>()
        .where(
          (point) =>
              point.ageMonths >= xRange.min && point.ageMonths <= xRange.max,
        )
        .toList();
  }

  void _handleScaleUpdate(ScaleUpdateDetails details, Size size) {
    final fullX = _fullXRange;
    final fullY = _fullYRange;
    final startX = _startXRange;
    final startY = _startYRange;
    final startFocal = _startFocalPoint;
    if (fullX == null ||
        fullY == null ||
        startX == null ||
        startY == null ||
        startFocal == null) {
      return;
    }

    final rect = _growthChartPlotRect(size);
    if (rect.width <= 0 || rect.height <= 0) return;

    final focalXRatio =
        _clampDouble((startFocal.dx - rect.left) / rect.width, 0, 1);
    final focalYRatio =
        _clampDouble((rect.bottom - startFocal.dy) / rect.height, 0, 1);
    final focalMonth = startX.min + focalXRatio * startX.span;
    final focalValue = startY.min + focalYRatio * startY.span;

    final scale = _clampDouble(details.scale, 0.25, 8);
    final nextXSpan = _clampDouble(
      startX.span / scale,
      _minXSpan(fullX),
      fullX.span,
    );
    final nextYSpan = _clampDouble(
      startY.span / scale,
      _minYSpan(widget.metric),
      fullY.span,
    );

    final delta = details.localFocalPoint - startFocal;
    final panX = -delta.dx / rect.width * nextXSpan;
    final panY = delta.dy / rect.height * nextYSpan;

    final nextX = _clampRange(
      _ChartRange(
        focalMonth - focalXRatio * nextXSpan + panX,
        focalMonth + (1 - focalXRatio) * nextXSpan + panX,
      ),
      fullX,
    );
    final nextY = _clampRange(
      _ChartRange(
        focalValue - focalYRatio * nextYSpan + panY,
        focalValue + (1 - focalYRatio) * nextYSpan + panY,
      ),
      fullY,
    );

    setState(() {
      _xRange = nextX;
      _yRange = nextY;
    });
  }

  void _resetViewport() {
    setState(() {
      _xRange = null;
      _yRange = null;
      _fullXRange = null;
      _fullYRange = null;
      _startXRange = null;
      _startYRange = null;
      _startFocalPoint = null;
    });
  }

  double _minXSpan(_ChartRange fullX) {
    return math.min(fullX.span, fullX.max <= 18 ? 1.0 : 2.0);
  }

  double _minYSpan(GrowthMetric metric) {
    return switch (metric) {
      GrowthMetric.height => 4.0,
      GrowthMetric.weight => 0.8,
      GrowthMetric.headCircumference => 1.0,
    };
  }
}

class _GrowthPoint {
  final double ageMonths;
  final double value;

  const _GrowthPoint(this.ageMonths, this.value);
}

class _ChartRange {
  final double min;
  final double max;

  const _ChartRange(this.min, this.max);

  double get span => max - min;

  @override
  bool operator ==(Object other) {
    return other is _ChartRange &&
        (other.min - min).abs() < 0.0001 &&
        (other.max - max).abs() < 0.0001;
  }

  @override
  int get hashCode =>
      Object.hash(min.toStringAsFixed(4), max.toStringAsFixed(4));
}

Rect _growthChartPlotRect(Size size) {
  return Rect.fromLTWH(
    48,
    8,
    math.max(40, size.width - 92),
    math.max(80, size.height - 52),
  );
}

List<GrowthStandardBand> _sampleGrowthBands({
  required Baby baby,
  required GrowthMetric metric,
  required _ChartRange range,
}) {
  final step = range.span <= 6
      ? 0.25
      : range.max <= 18
          ? 0.5
          : 1.0;
  final samples = <GrowthStandardBand>[];
  for (var month = range.min; month <= range.max + 0.001; month += step) {
    final band = GrowthStandardService.bandAtAgeMonths(
      baby: baby,
      metric: metric,
      ageMonths: month,
    );
    if (band != null) samples.add(band);
  }
  final last = GrowthStandardService.bandAtAgeMonths(
    baby: baby,
    metric: metric,
    ageMonths: range.max,
  );
  if (last != null &&
      (samples.isEmpty || (samples.last.ageMonths - range.max).abs() > 0.001)) {
    samples.add(last);
  }
  return samples;
}

_ChartRange _growthValueRange(
  GrowthMetric metric,
  List<GrowthStandardBand> samples,
  List<double> values,
) {
  final allValues = <double>[
    for (final band in samples) ...[band.low, band.median, band.high],
    ...values,
  ];
  final minValue = allValues.reduce(math.min);
  final maxValue = allValues.reduce(math.max);
  switch (metric) {
    case GrowthMetric.height:
      final min = math.max(40, _floorToStep(minValue - 25, 10));
      var max = _ceilToStep(maxValue + 20, 10);
      if (max - min < 40) max = min + 40;
      return _ChartRange(min.toDouble(), max.toDouble());
    case GrowthMetric.weight:
      const min = 0.0;
      var max = _ceilToStep(maxValue + 8, 10).toDouble();
      if (max < 20) max = 20;
      return _ChartRange(min, max);
    case GrowthMetric.headCircumference:
      final min = math.max(25, _floorToStep(minValue - 4, 5));
      var max = _ceilToStep(maxValue + 4, 5);
      if (max - min < 15) max = min + 15;
      return _ChartRange(min.toDouble(), max.toDouble());
  }
}

double? _growthMetricValue(GrowthRecord record, GrowthMetric metric) {
  return switch (metric) {
    GrowthMetric.height => record.heightCm,
    GrowthMetric.weight => record.weightKg,
    GrowthMetric.headCircumference => record.headCircumferenceCm,
  };
}

double? _exactAgeMonthsFor(Baby baby, DateTime date) {
  final birth = baby.birthDate;
  if (birth == null || date.isBefore(birth)) return null;
  return date.difference(birth).inDays / 30.4375;
}

_ChartRange _clampRange(_ChartRange range, _ChartRange bounds) {
  if (range.span >= bounds.span) return bounds;
  final span = range.span;
  final min = _clampDouble(range.min, bounds.min, bounds.max - span);
  return _ChartRange(min, min + span);
}

double _clampDouble(double value, double min, double max) {
  if (max < min) return min;
  return math.min(math.max(value, min), max);
}

num _floorToStep(double value, double step) {
  return (value / step).floor() * step;
}

num _ceilToStep(double value, double step) {
  return (value / step).ceil() * step;
}

double _niceStep(double rawStep) {
  if (rawStep <= 0) return 1;
  final exponent = math.pow(10, (math.log(rawStep) / math.ln10).floor());
  final fraction = rawStep / exponent;
  final niceFraction = fraction <= 1
      ? 1
      : fraction <= 2
          ? 2
          : fraction <= 5
              ? 5
              : 10;
  return niceFraction * exponent.toDouble();
}

class _GrowthChartPainter extends CustomPainter {
  final Baby baby;
  final List<GrowthRecord> records;
  final GrowthMetric metric;
  final _ChartRange? xRange;
  final _ChartRange? yRange;

  _GrowthChartPainter({
    required this.baby,
    required this.records,
    required this.metric,
    required this.xRange,
    required this.yRange,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bands = GrowthStandardService.bandsFor(baby: baby, metric: metric);
    if (bands.isEmpty || baby.birthDate == null) {
      _drawCenteredText(canvas, size, '请先设置生日和性别后查看国家标准曲线');
      return;
    }

    final visibleXRange =
        xRange ?? _ChartRange(bands.first.ageMonths, bands.last.ageMonths);
    final allPoints = records
        .map((record) {
          final value = _growthMetricValue(record, metric);
          final age = _exactAgeMonthsFor(baby, record.recordDate);
          if (value == null || age == null) return null;
          return _GrowthPoint(age, value);
        })
        .whereType<_GrowthPoint>()
        .toList()
      ..sort((a, b) => a.ageMonths.compareTo(b.ageMonths));

    final points = allPoints
        .where(
          (point) =>
              point.ageMonths >= visibleXRange.min &&
              point.ageMonths <= visibleXRange.max,
        )
        .toList();
    final samples = _sampleGrowthBands(
      baby: baby,
      metric: metric,
      range: visibleXRange,
    );
    if (samples.length < 2) {
      _drawCenteredText(canvas, size, '当前年龄暂不在国家标准范围内');
      return;
    }

    final visibleYRange = yRange ??
        _growthValueRange(
          metric,
          samples,
          points.map((point) => point.value).toList(),
        );
    final rect = _growthChartPlotRect(size);

    Offset chartPoint(double month, double value) {
      final x = rect.left +
          (month - visibleXRange.min) / visibleXRange.span * rect.width;
      final y = rect.bottom -
          (value - visibleYRange.min) / visibleYRange.span * rect.height;
      return Offset(x, y);
    }

    _drawGrid(canvas, rect, visibleXRange, visibleYRange);
    canvas.save();
    canvas.clipRect(rect);
    _drawStandardBand(canvas, samples, chartPoint);
    _drawRecordLine(canvas, points, chartPoint);
    canvas.restore();
    _drawPercentileLabels(canvas, rect, samples.last, chartPoint);
  }

  void _drawGrid(
    Canvas canvas,
    Rect rect,
    _ChartRange xRange,
    _ChartRange yRange,
  ) {
    final axisPaint = Paint()
      ..color = const Color(0xFFE3E3E3)
      ..strokeWidth = 1;
    canvas.drawLine(rect.bottomLeft, rect.bottomRight, axisPaint);
    canvas.drawLine(rect.bottomLeft, rect.topLeft, axisPaint);

    final horizontalPaint = Paint()
      ..color = const Color(0xFFEFEFEF)
      ..strokeWidth = 1;
    final labelStyle = TextStyle(
      color: const Color(0xFF666666),
      fontSize: 13,
      fontWeight: FontWeight.w600,
    );
    final yStep = _yStep(yRange, rect.height);
    for (var y = _ceilToStep(yRange.min, yStep).toDouble();
        y <= yRange.max + 0.001;
        y += yStep) {
      final dy = rect.bottom - (y - yRange.min) / yRange.span * rect.height;
      _drawDashedLine(
        canvas,
        Offset(rect.left, dy),
        Offset(rect.right, dy),
        horizontalPaint,
      );
      _drawText(
        canvas,
        _numberLabel(y.toDouble(), yStep),
        Offset(rect.left - 8, dy),
        labelStyle,
        align: _TextAlign.rightCenter,
      );
    }

    final verticalPaint = Paint()
      ..color = const Color(0xFFE7E7E7)
      ..strokeWidth = 1;
    final xLabelStyle = TextStyle(
      color: AppTheme.textMain,
      fontSize: 13,
      fontWeight: FontWeight.w700,
    );
    for (final month in _xTicks(xRange, rect.width)) {
      final dx = rect.left + (month - xRange.min) / xRange.span * rect.width;
      canvas.drawLine(
          Offset(dx, rect.top), Offset(dx, rect.bottom), verticalPaint);
      _drawText(
        canvas,
        _monthLabel(month),
        Offset(dx, rect.bottom + 20),
        xLabelStyle,
        align: _TextAlign.topCenter,
      );
    }
  }

  void _drawStandardBand(
    Canvas canvas,
    List<GrowthStandardBand> samples,
    Offset Function(double month, double value) point,
  ) {
    final fillPath = Path();
    final first = point(samples.first.ageMonths, samples.first.high);
    fillPath.moveTo(first.dx, first.dy);
    for (final band in samples.skip(1)) {
      final p = point(band.ageMonths, band.high);
      fillPath.lineTo(p.dx, p.dy);
    }
    for (final band in samples.reversed) {
      final p = point(band.ageMonths, band.low);
      fillPath.lineTo(p.dx, p.dy);
    }
    fillPath.close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..color = const Color(0xFF8CBDEB).withValues(alpha: 0.10)
        ..style = PaintingStyle.fill,
    );

    final paint = Paint()
      ..color = const Color(0xFF9CC5E8)
      ..strokeWidth = 1.7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    _drawBandLine(canvas, samples, (band) => band.high, point, paint);
    _drawBandLine(canvas, samples, (band) => band.median, point, paint);
    _drawBandLine(canvas, samples, (band) => band.low, point, paint);
  }

  void _drawBandLine(
    Canvas canvas,
    List<GrowthStandardBand> samples,
    double Function(GrowthStandardBand band) valueOf,
    Offset Function(double month, double value) point,
    Paint paint,
  ) {
    final path = Path();
    for (var i = 0; i < samples.length; i++) {
      final band = samples[i];
      final p = point(band.ageMonths, valueOf(band));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(path, paint);
  }

  void _drawRecordLine(
    Canvas canvas,
    List<_GrowthPoint> points,
    Offset Function(double month, double value) point,
  ) {
    if (points.isEmpty) return;
    final paint = Paint()
      ..color = const Color(0xFF70C989)
      ..strokeWidth = 2.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (points.length > 1) {
      final path = Path();
      for (var i = 0; i < points.length; i++) {
        final p = point(points[i].ageMonths, points[i].value);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(path, paint);
    }

    final dotPaint = Paint()
      ..color = const Color(0xFF70C989)
      ..style = PaintingStyle.fill;
    final dotBorder = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (final item in points) {
      final p = point(item.ageMonths, item.value);
      canvas.drawCircle(p, 5.2, dotPaint);
      canvas.drawCircle(p, 5.2, dotBorder);
    }
  }

  void _drawPercentileLabels(
    Canvas canvas,
    Rect rect,
    GrowthStandardBand last,
    Offset Function(double month, double value) point,
  ) {
    final style = TextStyle(
      color: const Color(0xFF666666),
      fontSize: 13,
      fontWeight: FontWeight.w800,
    );
    final labels = [
      ('97%', last.high),
      ('50%', last.median),
      ('3%', last.low),
    ];
    for (final item in labels) {
      final p = point(last.ageMonths, item.$2);
      _drawText(
        canvas,
        item.$1,
        Offset(rect.right + 8, p.dy),
        style,
        align: _TextAlign.leftCenter,
      );
    }
  }

  void _drawCenteredText(Canvas canvas, Size size, String text) {
    _drawText(
      canvas,
      text,
      Offset(size.width / 2, size.height / 2),
      TextStyle(
        color: Colors.grey.shade600,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
      align: _TextAlign.center,
    );
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashWidth = 3.0;
    const dashSpace = 7.0;
    final distance = (end - start).distance;
    if (distance <= 0) return;
    final direction = (end - start) / distance;
    var current = 0.0;
    while (current < distance) {
      final next = math.min(current + dashWidth, distance);
      canvas.drawLine(
        start + direction * current,
        start + direction * next,
        paint,
      );
      current += dashWidth + dashSpace;
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset anchor,
    TextStyle style, {
    required _TextAlign align,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final offset = switch (align) {
      _TextAlign.center =>
        Offset(anchor.dx - painter.width / 2, anchor.dy - painter.height / 2),
      _TextAlign.rightCenter =>
        Offset(anchor.dx - painter.width, anchor.dy - painter.height / 2),
      _TextAlign.leftCenter =>
        Offset(anchor.dx, anchor.dy - painter.height / 2),
      _TextAlign.topCenter => Offset(anchor.dx - painter.width / 2, anchor.dy),
    };
    painter.paint(canvas, offset);
  }

  List<double> _xTicks(_ChartRange range, double width) {
    final targetCount = math.max(3, (width / 74).floor());
    final step = _monthStep(range.span / targetCount);
    final ticks = <double>[];
    for (var month = _ceilToStep(range.min, step).toDouble();
        month <= range.max + 0.001;
        month += step) {
      ticks.add(month.toDouble());
    }
    if (ticks.isEmpty || (ticks.first - range.min).abs() > 0.001) {
      ticks.insert(0, range.min);
    }
    return ticks;
  }

  double _monthStep(double target) {
    const steps = [0.5, 1.0, 2.0, 3.0, 6.0, 12.0, 24.0];
    for (final step in steps) {
      if (step >= target) return step;
    }
    return steps.last;
  }

  String _monthLabel(double month) {
    if (month <= 0.001) return '出生';
    final rounded = month.roundToDouble();
    final wholeMonth = (month - rounded).abs() < 0.001;
    if (!wholeMonth) return '${month.toStringAsFixed(1)}个月';
    final monthInt = rounded.toInt();
    if (monthInt < 12) return '$monthInt个月';
    final years = monthInt ~/ 12;
    final rest = monthInt % 12;
    if (rest == 0) return '$years岁';
    if (rest == 6) return '$years岁半';
    return '$monthInt个月';
  }

  double _yStep(_ChartRange range, double height) {
    final targetCount = math.max(3, (height / 74).floor());
    return _niceStep(range.span / targetCount);
  }

  String _numberLabel(double value, double step) {
    if ((value - value.round()).abs() < 0.001) return value.round().toString();
    if (step < 0.1) return value.toStringAsFixed(2);
    return value.toStringAsFixed(1);
  }

  @override
  bool shouldRepaint(covariant _GrowthChartPainter oldDelegate) {
    return oldDelegate.records != records ||
        oldDelegate.baby != baby ||
        oldDelegate.metric != metric ||
        oldDelegate.xRange != xRange ||
        oldDelegate.yRange != yRange;
  }
}

enum _TextAlign {
  center,
  rightCenter,
  leftCenter,
  topCenter,
}
