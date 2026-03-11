import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import '../../../data/hanzi_data.dart';
import '../../../services/hanzi_learning_service.dart';
import '../../../widgets/toast_utils.dart';

/// 汉字字库筛选页面
/// 按册展示汉字（带拼音），支持多选标记已认识的字
class HanziLibraryPage extends StatefulWidget {
  const HanziLibraryPage({super.key});

  @override
  State<HanziLibraryPage> createState() => _HanziLibraryPageState();
}

class _HanziLibraryPageState extends State<HanziLibraryPage>
    with SingleTickerProviderStateMixin {
  final HanziLearningService _service = Get.find<HanziLearningService>();

  /// 当前解锁范围内的全部汉字条目
  List<HanziEntry> _allEntries = [];

  /// 按册分组的条目
  Map<int, List<HanziEntry>> _groupedEntries = {};

  /// 已选中的汉字集合
  final Set<String> _selectedHanzi = {};

  /// 当前展开查看的册别（用于 Tab 切换）
  late TabController _tabController;

  /// 可用的册别列表
  List<int> _availableLevels = [];

  /// 卡通色彩主题（每册一个颜色）
  static const List<Color> _levelColors = [
    Color(0xFFFF6B6B), // 第1册 - 珊瑚红
    Color(0xFFFFB347), // 第2册 - 橘黄
    Color(0xFF87CEEB), // 第3册 - 天蓝
    Color(0xFF98D8C8), // 第4册 - 薄荷绿
    Color(0xFFC39BD3), // 第5册 - 淡紫
    Color(0xFFFFD700), // 第6册 - 金黄
    Color(0xFF77DD77), // 第7册 - 草绿
  ];

  /// 每册的卡通 Emoji 图标
  static const List<String> _levelEmojis = [
    '🌱', // 启蒙
    '🌿', // 探索
    '🌻', // 成长
    '🌈', // 拓展
    '⭐', // 进阶
    '🎯', // 提升
    '🏆', // 综合
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 加载字库数据
  void _loadData() {
    final maxLevel = _service.config.value?.unlockedMaxLevel ?? 1;
    _allEntries = HanziData.getEntriesUpToLevel(maxLevel);

    // 按册分组
    _groupedEntries.clear();
    for (final entry in _allEntries) {
      _groupedEntries.putIfAbsent(entry.bookLevel, () => []).add(entry);
    }
    _availableLevels = _groupedEntries.keys.toList()..sort();

    // 初始化 TabController
    _tabController = TabController(
      length: _availableLevels.length,
      vsync: this,
    );

    // 载入已保存的已知字
    final knownList = _service.config.value?.knownHanziList ?? [];
    _selectedHanzi.addAll(knownList);

    setState(() {});
  }

  /// 切换单个汉字的选中状态
  void _toggleHanzi(String hanzi) {
    setState(() {
      if (_selectedHanzi.contains(hanzi)) {
        _selectedHanzi.remove(hanzi);
      } else {
        _selectedHanzi.add(hanzi);
      }
    });
  }

  /// 全选/取消全选当前册
  void _toggleSelectAllForLevel(int level) {
    final entries = _groupedEntries[level] ?? [];
    final chars = entries.map((e) => e.character).toSet();
    final allSelected = chars.every((c) => _selectedHanzi.contains(c));

    setState(() {
      if (allSelected) {
        _selectedHanzi.removeAll(chars);
      } else {
        _selectedHanzi.addAll(chars);
      }
    });
  }

  /// 保存选择
  Future<void> _saveSelection() async {
    try {
      await _service.updateKnownHanziList(_selectedHanzi.toList());

      // 如果是首次启动，标记完成
      if (_service.config.value?.isFirstLaunch == true) {
        await _service.markFirstLaunchDone();
      }

      ToastUtils.showSuccess('已保存 ${_selectedHanzi.length} 个已认识的汉字');

      // 确保页面仍挂载后再关闭
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      ToastUtils.showError('保存失败: $e');
    }
  }

  /// 获取册别主色调
  Color _getLevelColor(int level) {
    final idx = (level - 1).clamp(0, _levelColors.length - 1);
    return _levelColors[idx];
  }

  /// 获取册别 Emoji
  String _getLevelEmoji(int level) {
    final idx = (level - 1).clamp(0, _levelEmojis.length - 1);
    return _levelEmojis[idx];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8E1),
      appBar: AppBar(
        title: const Text(
          '📚 我的字库',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          // 保存按钮
          Padding(
            padding: EdgeInsets.only(right: 8.w),
            child: TextButton.icon(
              onPressed: _saveSelection,
              icon: const Icon(Icons.check_circle, color: Color(0xFF4CAF50)),
              label: Text(
                '保存',
                style: TextStyle(
                  color: const Color(0xFF4CAF50),
                  fontWeight: FontWeight.bold,
                  fontSize: 14.sp,
                ),
              ),
            ),
          ),
        ],
        bottom: _availableLevels.length > 1
            ? TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: const Color(0xFF333333),
                unselectedLabelColor: Colors.grey,
                indicatorColor: const Color(0xFFFF6B6B),
                indicatorWeight: 3,
                labelStyle: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13.sp,
                ),
                tabs: _availableLevels.map((level) {
                  return Tab(
                    text: '${_getLevelEmoji(level)} 第${level}册',
                  );
                }).toList(),
              )
            : null,
      ),
      body: Column(
        children: [
          // 顶部统计信息卡片
          _buildStatsCard(),

          // 册别内容
          Expanded(
            child: _availableLevels.length > 1
                ? TabBarView(
                    controller: _tabController,
                    children: _availableLevels.map((level) {
                      return _buildLevelGrid(level);
                    }).toList(),
                  )
                : _availableLevels.isNotEmpty
                    ? _buildLevelGrid(_availableLevels.first)
                    : const Center(child: Text('暂无字库数据')),
          ),

          // 底部保存按钮
          _buildBottomSaveBar(),
        ],
      ),
    );
  }

  /// 统计信息卡片
  Widget _buildStatsCard() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6B6B), Color(0xFFFFB347)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF6B6B).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('🎯', '字库总量', '${_allEntries.length}'),
          Container(width: 1, height: 30.h, color: Colors.white30),
          _buildStatItem('✅', '已认识', '${_selectedHanzi.length}'),
          Container(width: 1, height: 30.h, color: Colors.white30),
          _buildStatItem('📖', '待学习',
              '${_allEntries.length - _selectedHanzi.length}'),
        ],
      ),
    );
  }

  /// 统计项
  Widget _buildStatItem(String emoji, String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: TextStyle(fontSize: 18.sp)),
        SizedBox(height: 2.h),
        Text(
          value,
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10.sp,
            color: Colors.white.withOpacity(0.9),
          ),
        ),
      ],
    );
  }

  /// 构建某一册的汉字网格
  Widget _buildLevelGrid(int level) {
    final entries = _groupedEntries[level] ?? [];
    final color = _getLevelColor(level);
    final chars = entries.map((e) => e.character).toSet();
    final allSelected = chars.every((c) => _selectedHanzi.contains(c));
    final selectedCount =
        chars.where((c) => _selectedHanzi.contains(c)).length;

    return Column(
      children: [
        // 册别信息栏 + 全选按钮
        Container(
          margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 6.h),
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(14.r),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Text(
                _getLevelEmoji(level),
                style: TextStyle(fontSize: 22.sp),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entries.isNotEmpty ? entries.first.stageName : '第$level册',
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.bold,
                        color: color.withOpacity(0.9),
                      ),
                    ),
                    Text(
                      '共${entries.length}字 · 已选$selectedCount个',
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              // 全选按钮
              GestureDetector(
                onTap: () => _toggleSelectAllForLevel(level),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 12.w,
                    vertical: 6.h,
                  ),
                  decoration: BoxDecoration(
                    color: allSelected ? color : Colors.white,
                    borderRadius: BorderRadius.circular(20.r),
                    border: Border.all(color: color),
                  ),
                  child: Text(
                    allSelected ? '取消全选' : '全选本册',
                    style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.bold,
                      color: allSelected ? Colors.white : color,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // 汉字网格
        Expanded(
          child: GridView.builder(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              crossAxisSpacing: 8.w,
              mainAxisSpacing: 8.w,
              childAspectRatio: 0.75, // 留空间给拼音
            ),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              final isSelected = _selectedHanzi.contains(entry.character);
              return _buildHanziCard(entry, isSelected, color);
            },
          ),
        ),
      ],
    );
  }

  /// 构建单个汉字卡片（含拼音 + 汉字 + 选中指示）
  Widget _buildHanziCard(HanziEntry entry, bool isSelected, Color levelColor) {
    return GestureDetector(
      onTap: () => _toggleHanzi(entry.character),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected ? levelColor : Colors.white,
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(
            color: isSelected ? levelColor : Colors.grey.shade200,
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? levelColor.withOpacity(0.3)
                  : Colors.black.withOpacity(0.04),
              blurRadius: isSelected ? 8 : 4,
              offset: Offset(0, isSelected ? 3 : 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            // 拼音 + 汉字
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 拼音（在汉字上方）
                  // 拼音（在汉字上方，用 Opacity 强行占位保证对齐）
                  Opacity(
                    opacity: entry.pinyin.isEmpty ? 0.0 : 1.0,
                    child: Text(
                      entry.pinyin.isEmpty ? 'a' : entry.pinyin,
                      style: TextStyle(
                        fontSize: 10.sp,
                        color: isSelected
                            ? Colors.white.withOpacity(0.9)
                            : Colors.grey[500],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  SizedBox(height: 2.h),
                  // 汉字
                  Text(
                    entry.character,
                    style: TextStyle(
                      fontSize: 24.sp,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : const Color(0xFF333333),
                    ),
                  ),
                ],
              ),
            ),
            // 选中小勾
            if (isSelected)
              Positioned(
                top: 3.w,
                right: 3.w,
                child: Container(
                  width: 16.w,
                  height: 16.w,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check,
                    size: 11.sp,
                    color: levelColor,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 底部保存栏
  Widget _buildBottomSaveBar() {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          height: 48.h,
          child: ElevatedButton(
            onPressed: _saveSelection,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B6B),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.r),
              ),
              elevation: 4,
              shadowColor: const Color(0xFFFF6B6B).withOpacity(0.4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('✅', style: TextStyle(fontSize: 18.sp)),
                SizedBox(width: 8.w),
                Text(
                  '保存选择 (${_selectedHanzi.length}个字)',
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
