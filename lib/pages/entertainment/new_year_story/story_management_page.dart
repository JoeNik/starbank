import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../models/new_year_story.dart';
import '../../../services/story_management_service.dart';
import '../../../services/ai_generation_service.dart';
import '../../../widgets/toast_utils.dart';
import 'story_edit_dialog.dart';

/// 故事管理页面
class StoryManagementPage extends StatefulWidget {
  const StoryManagementPage({super.key});

  @override
  State<StoryManagementPage> createState() => _StoryManagementPageState();
}

class _StoryManagementPageState extends State<StoryManagementPage> {
  final StoryManagementService _storyService = StoryManagementService.instance;
  final AIGenerationService _aiService = AIGenerationService();

  // 选中的故事 ID 列表
  final Set<String> _selectedIds = {};

  // 是否处于选择模式
  bool _isSelectionMode = false;

  // 是否正在加载
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initService();
  }

  /// 初始化服务
  Future<void> _initService() async {
    setState(() => _isLoading = true);
    try {
      await _storyService.init();
    } catch (e) {
      ToastUtils.showError('初始化失败: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// 切换选择模式
  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedIds.clear();
      }
    });
  }

  /// 切换故事选中状态
  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  /// 全选/取消全选
  void _toggleSelectAll() {
    setState(() {
      if (_selectedIds.length == _storyService.storyCount) {
        _selectedIds.clear();
      } else {
        _selectedIds.clear();
        _selectedIds.addAll(_storyService.getAllStories().map((s) => s.id));
      }
    });
  }

  /// 删除选中的故事
  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) {
      ToastUtils.showWarning('请先选择要删除的故事');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除选中的 ${_selectedIds.length} 个故事吗?此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _storyService.deleteStories(_selectedIds.toList());
        ToastUtils.showSuccess('已删除 ${_selectedIds.length} 个故事');
        setState(() {
          _selectedIds.clear();
          _isSelectionMode = false;
        });
      } catch (e) {
        ToastUtils.showError('删除失败: $e');
      }
    }
  }

  /// 删除单个故事
  Future<void> _deleteStory(NewYearStory story) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除故事"${story.title}"吗?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _storyService.deleteStory(story.id);
        ToastUtils.showSuccess('已删除故事');
        setState(() {});
      } catch (e) {
        ToastUtils.showError('删除失败: $e');
      }
    }
  }

  /// 编辑故事
  Future<void> _editStory(NewYearStory story) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StoryEditDialog(story: story),
    );

    if (result == true) {
      setState(() {});
    }
  }

  /// 显示 AI 生成对话框
  Future<void> _showAIGenerateDialog() async {
    int count = 1;
    String theme = '';
    bool isGenerating = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('AI 生成故事'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('生成数量'),
                Slider(
                  value: count.toDouble(),
                  min: 1,
                  max: 3,
                  divisions: 2,
                  label: count.toString(),
                  onChanged: isGenerating
                      ? null
                      : (value) {
                          setDialogState(() => count = value.toInt());
                        },
                ),
                Text('$count 个故事'),
                SizedBox(height: 16.h),
                TextField(
                  decoration: const InputDecoration(
                    labelText: '故事主题(可选)',
                    hintText: '例如:元宵节、舞龙舞狮',
                    border: OutlineInputBorder(),
                  ),
                  enabled: !isGenerating,
                  onChanged: (value) => theme = value,
                ),
                SizedBox(height: 16.h),
                const Text(
                  '提示:AI 将生成适合儿童的新年相关故事,重复的故事会自动跳过。',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          actions: [
            if (!isGenerating)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ElevatedButton(
              onPressed: isGenerating
                  ? null
                  : () async {
                      setDialogState(() => isGenerating = true);
                      try {
                        final (success, skip, fail, errors) =
                            await _aiService.generateAndImportStories(
                          count: count,
                          theme: theme.isEmpty ? null : theme,
                        );

                        Navigator.pop(context);

                        // 显示结果
                        _showGenerationResult(
                          success: success,
                          skip: skip,
                          fail: fail,
                          errors: errors,
                          type: '故事',
                        );

                        setState(() {});
                      } catch (e) {
                        setDialogState(() => isGenerating = false);
                        ToastUtils.showError('生成失败: $e');
                      }
                    },
              child: isGenerating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('开始生成'),
            ),
          ],
        ),
      ),
    );
  }

  /// 显示生成结果
  void _showGenerationResult({
    required int success,
    required int skip,
    required int fail,
    required List<String> errors,
    required String type,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('生成$type结果'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('✅ 成功: $success'),
              Text('⏭️ 跳过(重复): $skip'),
              Text('❌ 失败: $fail'),
              if (errors.isNotEmpty) ...[
                SizedBox(height: 16.h),
                const Text('错误详情:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                ...errors.map(
                    (e) => Text('• $e', style: const TextStyle(fontSize: 12))),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stories = _storyService.getAllStories();

    return Scaffold(
      appBar: AppBar(
        title: const Text('故事管理'),
        actions: [
          if (_isSelectionMode) ...[
            TextButton.icon(
              onPressed: _toggleSelectAll,
              icon: Icon(
                _selectedIds.length == stories.length
                    ? Icons.deselect
                    : Icons.select_all,
              ),
              label:
                  Text(_selectedIds.length == stories.length ? '取消全选' : '全选'),
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _deleteSelected,
              tooltip: '删除选中',
            ),
          ],
          IconButton(
            icon: Icon(_isSelectionMode ? Icons.close : Icons.checklist),
            onPressed: _toggleSelectionMode,
            tooltip: _isSelectionMode ? '退出选择' : '批量选择',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : stories.isEmpty
              ? _buildEmptyState()
              : _buildStoryList(stories),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAIGenerateDialog,
        icon: const Icon(Icons.auto_awesome),
        label: const Text('AI 生成'),
      ),
    );
  }

  /// 空状态
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.book_outlined, size: 80.sp, color: Colors.grey),
          SizedBox(height: 16.h),
          const Text('还没有故事',
              style: TextStyle(fontSize: 18, color: Colors.grey)),
          SizedBox(height: 8.h),
          const Text('点击下方按钮使用 AI 生成故事', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  /// 故事列表
  Widget _buildStoryList(List<NewYearStory> stories) {
    return ListView.builder(
      padding: EdgeInsets.all(16.w),
      itemCount: stories.length,
      itemBuilder: (context, index) {
        final story = stories[index];
        final isSelected = _selectedIds.contains(story.id);

        return Card(
          margin: EdgeInsets.only(bottom: 12.h),
          child: ListTile(
            leading: _isSelectionMode
                ? Checkbox(
                    value: isSelected,
                    onChanged: (_) => _toggleSelection(story.id),
                  )
                : Text(
                    story.emoji,
                    style: TextStyle(fontSize: 32.sp),
                  ),
            title: Text(story.title),
            subtitle: Text(
              '${story.duration} • ${story.pageCount} 页',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: _isSelectionMode
                ? null
                : PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') {
                        _editStory(story);
                      } else if (value == 'delete') {
                        _deleteStory(story);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 20),
                            SizedBox(width: 8),
                            Text('编辑'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 20, color: Colors.red),
                            SizedBox(width: 8),
                            Text('删除', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
            onTap: _isSelectionMode ? () => _toggleSelection(story.id) : null,
          ),
        );
      },
    );
  }
}
