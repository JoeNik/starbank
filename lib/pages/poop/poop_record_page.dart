import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import '../../models/poop_record.dart';
import '../../controllers/user_controller.dart';
import '../../controllers/app_mode_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/toast_utils.dart';
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
          // AI 分析按钮 - 使用更大更美观的样式
          Padding(
            padding: EdgeInsets.only(right: 8.w),
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                ),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12.r),
                  onTap: () => Get.to(() => const PoopAIPage()),
                  child: Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.psychology,
                            color: Colors.white, size: 20.sp),
                        SizedBox(width: 4.w),
                        Text(
                          'AI 分析',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
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
      floatingActionButton: Obx(() {
        final modeController = Get.find<AppModeController>();
        if (modeController.isChildMode) {
          return const SizedBox(); // 儿童模式隐藏添加按钮
        }
        return FloatingActionButton.extended(
          onPressed: _addRecord,
          backgroundColor: AppTheme.primary,
          icon: const Icon(Icons.add),
          label: const Text('记录'),
        );
      }),
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
                mainAxisAlignment: MainAxisAlignment.center,
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
                      padding:
                          EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                      constraints: BoxConstraints(minWidth: 20.w),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.white.withOpacity(0.9)
                            : Colors.brown.shade300,
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      child: Text(
                        '$count',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10.sp,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? AppTheme.primary : Colors.white,
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
        trailing: Get.find<AppModeController>().isChildMode
            ? null // 儿童模式下不显示菜单
            : PopupMenuButton<String>(
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
      ToastUtils.showInfo('请先选择宝宝');
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
      ToastUtils.showSuccess('记录已添加');
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
      ToastUtils.showSuccess('记录已更新');
    }
  }

  /// 删除记录
  Future<void> _deleteRecord(PoopRecord record) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除这条记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await record.delete();
      _loadRecords();
      ToastUtils.showSuccess('记录已删除');
    }
  }

  /// 显示记录编辑对话框
  Future<Map<String, dynamic>?> _showRecordDialog(
      {PoopRecord? existing}) async {
    DateTime selectedDateTime = existing?.dateTime ??
        DateTime(
          _selectedDate.value.year,
          _selectedDate.value.month,
          _selectedDate.value.day,
          DateTime.now().hour,
          DateTime.now().minute,
        );
    String noteText = existing?.note ?? '';
    int typeValue = existing?.type ?? 0;
    int colorValue = existing?.color ?? 0;

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(existing == null ? '添加记录' : '编辑记录'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 时间选择
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.access_time),
                      title: Text(DateFormat('yyyy-MM-dd HH:mm')
                          .format(selectedDateTime)),
                      trailing: const Icon(Icons.edit),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: selectedDateTime,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (date != null) {
                          final time = await showTimePicker(
                            context: context,
                            initialTime:
                                TimeOfDay.fromDateTime(selectedDateTime),
                          );
                          if (time != null) {
                            setDialogState(() {
                              selectedDateTime = DateTime(
                                date.year,
                                date.month,
                                date.day,
                                time.hour,
                                time.minute,
                              );
                            });
                          }
                        }
                      },
                    ),

                    SizedBox(height: 16.h),

                    // 类型选择
                    Text('便便类型',
                        style: TextStyle(fontSize: 12.sp, color: Colors.grey)),
                    SizedBox(height: 8.h),
                    Wrap(
                      spacing: 8.w,
                      children: [
                        _buildDialogChip('正常', 0, typeValue,
                            (v) => setDialogState(() => typeValue = v)),
                        _buildDialogChip('稀便', 1, typeValue,
                            (v) => setDialogState(() => typeValue = v)),
                        _buildDialogChip('干硬', 2, typeValue,
                            (v) => setDialogState(() => typeValue = v)),
                        _buildDialogChip('其他', 3, typeValue,
                            (v) => setDialogState(() => typeValue = v)),
                      ],
                    ),

                    SizedBox(height: 16.h),

                    // 颜色选择
                    Text('颜色',
                        style: TextStyle(fontSize: 12.sp, color: Colors.grey)),
                    SizedBox(height: 8.h),
                    Wrap(
                      spacing: 8.w,
                      children: [
                        _buildDialogChip('正常黄色', 0, colorValue,
                            (v) => setDialogState(() => colorValue = v)),
                        _buildDialogChip('绿色', 1, colorValue,
                            (v) => setDialogState(() => colorValue = v)),
                        _buildDialogChip('黑色', 2, colorValue,
                            (v) => setDialogState(() => colorValue = v)),
                        _buildDialogChip('其他', 3, colorValue,
                            (v) => setDialogState(() => colorValue = v)),
                      ],
                    ),

                    SizedBox(height: 16.h),

                    // 备注
                    TextFormField(
                      initialValue: noteText,
                      decoration: const InputDecoration(
                        labelText: '备注（可选）',
                        hintText: '如：量多、有奶瓣等',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                      onChanged: (v) => noteText = v,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop({
                    'dateTime': selectedDateTime,
                    'note': noteText,
                    'type': typeValue,
                    'color': colorValue,
                  }),
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDialogChip(
      String label, int value, int selected, Function(int) onSelect) {
    return ChoiceChip(
      label: Text(label),
      selected: selected == value,
      onSelected: (s) {
        if (s) onSelect(value);
      },
    );
  }
}
