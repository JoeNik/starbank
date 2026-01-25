import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import '../../models/poop_record.dart';
import '../../controllers/user_controller.dart';
import '../../theme/app_theme.dart';
import 'poop_ai_page.dart';

/// 便便记录主页面
class PoopRecordPage extends StatefulWidget {
  const PoopRecordPage({super.key});

  @override
  State<PoopRecordPage> createState() => _PoopRecordPageState();
}

class _PoopRecordPageState extends State<PoopRecordPage> {
  final UserController _userController = Get.find<UserController>();

  // 记录列表
  final RxList<PoopRecord> _records = <PoopRecord>[].obs;

  // 当前选中的日期（用于日历）
  final Rx<DateTime> _selectedDate = DateTime.now().obs;

  // 当前显示的月份
  final Rx<DateTime> _displayMonth = DateTime.now().obs;

  late Box<PoopRecord> _recordBox;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    // 注册适配器（如果还未注册）
    if (!Hive.isAdapterRegistered(11)) {
      Hive.registerAdapter(PoopRecordAdapter());
    }
    _recordBox = await Hive.openBox<PoopRecord>('poop_records');
    _loadRecords();
    setState(() => _isLoading = false);
  }

  void _loadRecords() {
    final babyId = _userController.currentBaby.value?.id;
    if (babyId == null) {
      _records.clear();
      return;
    }

    // 加载当前宝宝的所有记录
    final allRecords = _recordBox.values
        .where((r) => r.babyId == babyId)
        .toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
    _records.assignAll(allRecords);
  }

  /// 获取指定日期的记录数
  int _getRecordCountForDate(DateTime date) {
    return _records
        .where((r) =>
            r.dateTime.year == date.year &&
            r.dateTime.month == date.month &&
            r.dateTime.day == date.day)
        .length;
  }

  /// 获取指定日期的记录
  List<PoopRecord> _getRecordsForDate(DateTime date) {
    return _records
        .where((r) =>
            r.dateTime.year == date.year &&
            r.dateTime.month == date.month &&
            r.dateTime.day == date.day)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('便便记录'),
        actions: [
          // AI 分析按钮
          IconButton(
            icon: const Icon(Icons.psychology),
            tooltip: 'AI 分析',
            onPressed: () => Get.to(() => const PoopAIPage()),
          ),
          // 设置按钮（智能体）
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: _showSettingsDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // 日历视图
          _buildCalendarView(),

          // 选中日期的记录
          Expanded(
            child: _buildRecordList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addRecord,
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.add),
        label: const Text('记录'),
      ),
    );
  }

  /// 日历视图
  Widget _buildCalendarView() {
    return Container(
      margin: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // 月份导航
          Obx(() => Padding(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () {
                        _displayMonth.value = DateTime(
                          _displayMonth.value.year,
                          _displayMonth.value.month - 1,
                        );
                      },
                    ),
                    Text(
                      DateFormat('yyyy年MM月').format(_displayMonth.value),
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () {
                        _displayMonth.value = DateTime(
                          _displayMonth.value.year,
                          _displayMonth.value.month + 1,
                        );
                      },
                    ),
                  ],
                ),
              )),

          // 星期标题
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.w),
            child: Row(
              children: ['日', '一', '二', '三', '四', '五', '六']
                  .map((d) => Expanded(
                        child: Center(
                          child: Text(
                            d,
                            style: TextStyle(
                              fontSize: 12.sp,
                              color: Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),

          SizedBox(height: 8.h),

          // 日期网格
          Obx(() => _buildCalendarGrid()),

          SizedBox(height: 8.h),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid() {
    final year = _displayMonth.value.year;
    final month = _displayMonth.value.month;
    final firstDay = DateTime(year, month, 1);
    final lastDay = DateTime(year, month + 1, 0);
    final startWeekday = firstDay.weekday % 7; // 0=周日

    List<Widget> rows = [];
    List<Widget> currentRow = [];

    // 填充前面的空白
    for (int i = 0; i < startWeekday; i++) {
      currentRow.add(const Expanded(child: SizedBox()));
    }

    // 填充日期
    for (int day = 1; day <= lastDay.day; day++) {
      final date = DateTime(year, month, day);
      final count = _getRecordCountForDate(date);
      final isSelected = _selectedDate.value.year == date.year &&
          _selectedDate.value.month == date.month &&
          _selectedDate.value.day == date.day;
      final isToday = DateTime.now().year == date.year &&
          DateTime.now().month == date.month &&
          DateTime.now().day == date.day;

      currentRow.add(
        Expanded(
          child: GestureDetector(
            onTap: () => _selectedDate.value = date,
            child: Container(
              margin: EdgeInsets.all(2.w),
              padding: EdgeInsets.symmetric(vertical: 6.h),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.primary
                    : isToday
                        ? AppTheme.primaryLight.withOpacity(0.3)
                        : null,
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$day',
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight:
                          isSelected || isToday ? FontWeight.bold : null,
                      color: isSelected ? Colors.white : null,
                    ),
                  ),
                  if (count > 0)
                    Container(
                      margin: EdgeInsets.only(top: 2.h),
                      width: 18.w,
                      height: 14.h,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.white.withOpacity(0.9)
                            : Colors.brown.shade300,
                        borderRadius: BorderRadius.circular(7.r),
                      ),
                      child: Center(
                        child: Text(
                          '$count',
                          style: TextStyle(
                            fontSize: 10.sp,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? AppTheme.primary : Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );

      if (currentRow.length == 7) {
        rows.add(Row(children: currentRow));
        currentRow = [];
      }
    }

    // 填充最后一行的空白
    while (currentRow.length < 7 && currentRow.isNotEmpty) {
      currentRow.add(const Expanded(child: SizedBox()));
    }
    if (currentRow.isNotEmpty) {
      rows.add(Row(children: currentRow));
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.w),
      child: Column(children: rows),
    );
  }

  /// 记录列表
  Widget _buildRecordList() {
    return Obx(() {
      final dayRecords = _getRecordsForDate(_selectedDate.value);

      if (dayRecords.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.event_note, size: 64.sp, color: Colors.grey.shade300),
              SizedBox(height: 16.h),
              Text(
                '${DateFormat('M月d日').format(_selectedDate.value)} 暂无记录',
                style: TextStyle(
                  fontSize: 14.sp,
                  color: Colors.grey,
                ),
              ),
              SizedBox(height: 8.h),
              TextButton.icon(
                onPressed: _addRecord,
                icon: const Icon(Icons.add),
                label: const Text('添加记录'),
              ),
            ],
          ),
        );
      }

      return ListView.builder(
        padding: EdgeInsets.symmetric(horizontal: 12.w),
        itemCount: dayRecords.length,
        itemBuilder: (context, index) {
          final record = dayRecords[index];
          return _buildRecordCard(record);
        },
      );
    });
  }

  Widget _buildRecordCard(PoopRecord record) {
    return Card(
      margin: EdgeInsets.only(bottom: 8.h),
      child: ListTile(
        leading: Container(
          width: 48.w,
          height: 48.w,
          decoration: BoxDecoration(
            color: Colors.brown.shade100,
            borderRadius: BorderRadius.circular(12.r),
          ),
          child: Icon(
            Icons.event_available,
            color: Colors.brown,
            size: 24.sp,
          ),
        ),
        title: Text(
          DateFormat('HH:mm').format(record.dateTime),
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildTag(record.typeDesc, Colors.blue),
                SizedBox(width: 8.w),
                _buildTag(record.colorDesc, Colors.orange),
              ],
            ),
            if (record.note.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: 4.h),
                child: Text(
                  record.note,
                  style: TextStyle(fontSize: 12.sp, color: Colors.grey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'edit') {
              _editRecord(record);
            } else if (value == 'delete') {
              _deleteRecord(record);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'edit', child: Text('编辑')),
            const PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
      ),
    );
  }

  Widget _buildTag(String text, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4.r),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.sp,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// 添加记录
  Future<void> _addRecord() async {
    final baby = _userController.currentBaby.value;
    if (baby == null) {
      Get.snackbar('提示', '请先选择宝宝', snackPosition: SnackPosition.BOTTOM);
      return;
    }

    final result = await _showRecordDialog();
    if (result != null) {
      final record = PoopRecord(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        babyId: baby.id,
        dateTime: result['dateTime'] as DateTime,
        note: result['note'] as String,
        type: result['type'] as int,
        color: result['color'] as int,
      );

      await _recordBox.put(record.id, record);
      _loadRecords();
      Get.snackbar('成功', '记录已添加', snackPosition: SnackPosition.BOTTOM);
    }
  }

  /// 编辑记录
  Future<void> _editRecord(PoopRecord record) async {
    final result = await _showRecordDialog(existing: record);
    if (result != null) {
      record.dateTime = result['dateTime'] as DateTime;
      record.note = result['note'] as String;
      record.type = result['type'] as int;
      record.color = result['color'] as int;

      await record.save();
      _loadRecords();
      Get.snackbar('成功', '记录已更新', snackPosition: SnackPosition.BOTTOM);
    }
  }

  /// 删除记录
  Future<void> _deleteRecord(PoopRecord record) async {
    final confirm = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除这条记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await record.delete();
      _loadRecords();
      Get.snackbar('成功', '记录已删除', snackPosition: SnackPosition.BOTTOM);
    }
  }

  /// 显示记录编辑对话框
  Future<Map<String, dynamic>?> _showRecordDialog(
      {PoopRecord? existing}) async {
    final dateTime = (existing?.dateTime ?? _selectedDate.value).obs;
    final note = TextEditingController(text: existing?.note ?? '');
    final type = (existing?.type ?? 0).obs;
    final color = (existing?.color ?? 0).obs;

    return Get.dialog<Map<String, dynamic>>(
      AlertDialog(
        title: Text(existing == null ? '添加记录' : '编辑记录'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 时间选择
              Obx(() => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.access_time),
                    title: Text(
                        DateFormat('yyyy-MM-dd HH:mm').format(dateTime.value)),
                    trailing: const Icon(Icons.edit),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: dateTime.value,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(dateTime.value),
                        );
                        if (time != null) {
                          dateTime.value = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            time.hour,
                            time.minute,
                          );
                        }
                      }
                    },
                  )),

              SizedBox(height: 16.h),

              // 类型选择
              Text('便便类型',
                  style: TextStyle(fontSize: 12.sp, color: Colors.grey)),
              SizedBox(height: 8.h),
              Obx(() => Wrap(
                    spacing: 8.w,
                    children: [
                      _buildChoiceChip('正常', 0, type),
                      _buildChoiceChip('稀便', 1, type),
                      _buildChoiceChip('干硬', 2, type),
                      _buildChoiceChip('其他', 3, type),
                    ],
                  )),

              SizedBox(height: 16.h),

              // 颜色选择
              Text('颜色', style: TextStyle(fontSize: 12.sp, color: Colors.grey)),
              SizedBox(height: 8.h),
              Obx(() => Wrap(
                    spacing: 8.w,
                    children: [
                      _buildChoiceChip('正常黄色', 0, color),
                      _buildChoiceChip('绿色', 1, color),
                      _buildChoiceChip('黑色', 2, color),
                      _buildChoiceChip('其他', 3, color),
                    ],
                  )),

              SizedBox(height: 16.h),

              // 备注
              TextField(
                controller: note,
                decoration: const InputDecoration(
                  labelText: '备注（可选）',
                  hintText: '如：量多、有奶瓣等',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Get.back(result: {
              'dateTime': dateTime.value,
              'note': note.text,
              'type': type.value,
              'color': color.value,
            }),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Widget _buildChoiceChip(String label, int value, RxInt selected) {
    return ChoiceChip(
      label: Text(label),
      selected: selected.value == value,
      onSelected: (s) => selected.value = value,
    );
  }

  /// 设置对话框
  void _showSettingsDialog() {
    Get.snackbar('提示', '智能体设置功能开发中', snackPosition: SnackPosition.BOTTOM);
  }
}
