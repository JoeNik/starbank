import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../models/openai_config.dart';
import '../services/openai_service.dart';
import '../theme/app_theme.dart';
import '../widgets/toast_utils.dart';

/// OpenAI 设置页面
class OpenAISettingsPage extends StatefulWidget {
  const OpenAISettingsPage({super.key});

  @override
  State<OpenAISettingsPage> createState() => _OpenAISettingsPageState();
}

class _OpenAISettingsPageState extends State<OpenAISettingsPage> {
  OpenAIService? _openAIService;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initService();
  }

  Future<void> _initService() async {
    try {
      _openAIService = Get.find<OpenAIService>();
    } catch (e) {
      // 服务未注册,需要初始化
      _openAIService = await Get.putAsync(() => OpenAIService().init());
    }
    setState(() => _isLoading = false);
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
        title: const Text('AI 配置'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加配置',
            onPressed: _addConfig,
          ),
        ],
      ),
      body: Obx(() {
        final configs = _openAIService!.configs;

        if (configs.isEmpty) {
          return _buildEmptyState();
        }

        return ListView.builder(
          padding: EdgeInsets.all(16.w),
          itemCount: configs.length,
          itemBuilder: (context, index) {
            return _buildConfigCard(configs[index]);
          },
        );
      }),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.api, size: 64.sp, color: Colors.grey.shade300),
          SizedBox(height: 16.h),
          Text(
            '暂无 AI 配置',
            style: TextStyle(fontSize: 16.sp, color: Colors.grey),
          ),
          SizedBox(height: 8.h),
          Text(
            '添加 OpenAI 兼容的 API 配置\\n支持 OpenAI、Claude、通义千问等',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.sp, color: Colors.grey),
          ),
          SizedBox(height: 24.h),
          ElevatedButton.icon(
            onPressed: _addConfig,
            icon: const Icon(Icons.add),
            label: const Text('添加配置'),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigCard(OpenAIConfig config) {
    return Card(
      margin: EdgeInsets.only(bottom: 12.h),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 默认标记
                if (config.isDefault)
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                    margin: EdgeInsets.only(right: 8.w),
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(4.r),
                    ),
                    child: Text(
                      '默认',
                      style: TextStyle(
                        fontSize: 10.sp,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                Expanded(
                  child: Text(
                    config.name,
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) => _handleMenuAction(value, config),
                  itemBuilder: (context) => [
                    if (!config.isDefault)
                      const PopupMenuItem(
                          value: 'default', child: Text('设为默认')),
                    const PopupMenuItem(value: 'edit', child: Text('编辑')),
                    const PopupMenuItem(value: 'refresh', child: Text('管理模型')),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('删除', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: 8.h),
            _buildInfoRow('API 地址', config.baseUrl),
            _buildInfoRow('API Key',
                '${config.apiKey.substring(0, config.apiKey.length > 8 ? 8 : config.apiKey.length)}...'),
            _buildInfoRow('当前模型',
                config.selectedModel.isNotEmpty ? config.selectedModel : '未选择'),
            if (config.models.isNotEmpty) ...[
              SizedBox(height: 8.h),
              Row(
                children: [
                  Text(
                    '可用模型 (${config.models.length})',
                    style: TextStyle(fontSize: 12.sp, color: Colors.grey),
                  ),
                  SizedBox(width: 8.w),
                  Tooltip(
                    message: '从在线列表添加/管理模型',
                    child: InkWell(
                      onTap: () => _manageOnlineModels(config),
                      borderRadius: BorderRadius.circular(12.r),
                      child: Padding(
                        padding: EdgeInsets.all(4.w),
                        child: Icon(
                          Icons.add_circle_outline,
                          size: 16.sp,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _showAllModelsDialog(config),
                    style: TextButton.styleFrom(
                      padding:
                          EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      '查看全部',
                      style: TextStyle(fontSize: 11.sp),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 4.h),
              Wrap(
                spacing: 6.w,
                runSpacing: 6.h,
                children: config.models.take(5).map((model) {
                  final isSelected = model == config.selectedModel;
                  return GestureDetector(
                    onTap: () => _selectModel(config, model),
                    child: Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.primary
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(4.r),
                      ),
                      child: Text(
                        model.length > 20
                            ? '${model.substring(0, 20)}...'
                            : model,
                        style: TextStyle(
                          fontSize: 10.sp,
                          color:
                              isSelected ? Colors.white : Colors.grey.shade700,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              if (config.models.length > 5)
                Padding(
                  padding: EdgeInsets.only(top: 4.h),
                  child: Text(
                    '还有 ${config.models.length - 5} 个模型...',
                    style: TextStyle(fontSize: 10.sp, color: Colors.grey),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 4.h),
      child: Row(
        children: [
          SizedBox(
            width: 70.w,
            child: Text(
              label,
              style: TextStyle(fontSize: 12.sp, color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 12.sp),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _handleMenuAction(String action, OpenAIConfig config) {
    switch (action) {
      case 'default':
        _openAIService!.setDefaultConfig(config);
        break;
      case 'edit':
        _editConfig(config);
        break;
      case 'refresh':
        _manageOnlineModels(config);
        break;
      case 'delete':
        _deleteConfig(config);
        break;
    }
  }

  Future<void> _selectModel(OpenAIConfig config, String model) async {
    config.selectedModel = model;
    await _openAIService!.updateConfig(config);
    ToastUtils.showSuccess('已选择模型: $model');
  }

  /// 显示所有模型对话框
  void _showAllModelsDialog(OpenAIConfig config) {
    final searchController = TextEditingController();
    final filteredModels = config.models.obs;

    Get.dialog(
      Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        child: Container(
          constraints: BoxConstraints(maxHeight: 600.h),
          padding: EdgeInsets.all(16.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题
              Row(
                children: [
                  Text(
                    '选择模型',
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Get.back(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              SizedBox(height: 12.h),
              // 搜索框
              TextField(
                controller: searchController,
                decoration: InputDecoration(
                  hintText: '搜索模型...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                ),
                onChanged: (value) {
                  if (value.isEmpty) {
                    filteredModels.value = config.models;
                  } else {
                    filteredModels.value = config.models
                        .where((m) =>
                            m.toLowerCase().contains(value.toLowerCase()))
                        .toList();
                  }
                },
              ),
              SizedBox(height: 12.h),
              // 模型列表
              Expanded(
                child: Obx(() {
                  if (filteredModels.isEmpty) {
                    return const Center(child: Text('没有找到匹配的模型'));
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: filteredModels.length,
                    itemBuilder: (context, index) {
                      final model = filteredModels[index];
                      final isSelected = model == config.selectedModel;
                      return ListTile(
                        title: Text(
                          model,
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        trailing: isSelected
                            ? Icon(Icons.check_circle, color: AppTheme.primary)
                            : null,
                        selected: isSelected,
                        selectedTileColor: AppTheme.primary.withOpacity(0.1),
                        onTap: () async {
                          await _selectModel(config, model);
                          Get.back();
                        },
                      );
                    },
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addConfig() async {
    final result = await _showConfigDialog();
    if (result != null) {
      final config = OpenAIConfig(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: result['name']!,
        baseUrl: result['baseUrl']!,
        apiKey: result['apiKey']!,
        enableWebSearch: result['enableWebSearch'] ?? false,
      );

      // 尝试获取模型列表
      try {
        _showLoadingDialog('正在获取模型列表...');

        final models =
            await _openAIService!.fetchModels(config.baseUrl, config.apiKey);
        config.models = models;
        if (models.isNotEmpty) {
          config.selectedModel = models.first;
        }

        Navigator.of(context).pop(); // 关闭加载对话框
      } catch (e) {
        Navigator.of(context).pop(); // 关闭加载对话框
        ToastUtils.showError('无法获取模型列表: ${_formatError(e)}', title: '提示');
      }

      await _openAIService!.addConfig(config);
      ToastUtils.showSuccess('配置已添加');
    }
  }

  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            SizedBox(width: 16.w),
            Text(message),
          ],
        ),
      ),
    );
  }

  Future<void> _editConfig(OpenAIConfig config) async {
    final result = await _showConfigDialog(existing: config);
    if (result != null) {
      config.name = result['name']!;
      config.baseUrl = result['baseUrl']!;
      config.apiKey = result['apiKey']!;
      config.enableWebSearch = result['enableWebSearch'] ?? false;
      await _openAIService!.updateConfig(config);
      ToastUtils.showSuccess('配置已更新');
    }
  }

  Future<void> _manageOnlineModels(OpenAIConfig config) async {
    try {
      _showLoadingDialog('正在获取在线模型列表...');

      final onlineModels =
          await _openAIService!.fetchModels(config.baseUrl, config.apiKey);

      Navigator.of(context).pop(); // 关闭加载对话框

      if (onlineModels.isEmpty) {
        ToastUtils.showWarning('未获取到任何模型');
        return;
      }

      // 弹出多选对话框
      final selectedModels = await _showModelManageDialog(
        currentModels: config.models,
        userSelectableModels: onlineModels,
      );

      if (selectedModels != null) {
        config.models = selectedModels;
        // 如果当前选中的模型不在新列表中且列表不为空，重置为第一个
        if (config.models.isNotEmpty &&
            !config.models.contains(config.selectedModel)) {
          config.selectedModel = config.models.first;
        }
        // 如果列表为空，清空选中
        if (config.models.isEmpty) {
          config.selectedModel = '';
        }

        await _openAIService!.updateConfig(config);
        ToastUtils.showSuccess('模型列表已更新，共 ${config.models.length} 个模型');
      }
    } catch (e) {
      if (Navigator.canPop(context)) Navigator.of(context).pop();
      ToastUtils.showError('获取模型列表失败: ${_formatError(e)}');
    }
  }

  /// 显示模型管理对话框(多选)
  Future<List<String>?> _showModelManageDialog({
    required List<String> currentModels,
    required List<String> userSelectableModels,
  }) async {
    // 确保当前已保存的模型也在列表中(防止服务商删除了但本地还想保留的情况? 或者取并集?)
    // 这里为了简单，以在线列表为主，并在顶部显示已选。
    // 逻辑：展示 userSelectableModels。默认勾选 currentModels 中的项。

    final RxList<String> selected = RxList<String>.from(currentModels);
    final RxList<String> filteredList =
        RxList<String>.from(userSelectableModels);
    final searchController = TextEditingController();

    return Get.dialog<List<String>>(
      Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        child: Container(
          constraints: BoxConstraints(maxHeight: 700.h),
          padding: EdgeInsets.all(16.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题
              Row(
                children: [
                  Text(
                    '管理模型',
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Obx(() => Text(
                        '已选: ${selected.length}',
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: AppTheme.primary,
                        ),
                      )),
                ],
              ),
              SizedBox(height: 4.h),
              Text(
                '从服务商提供的列表中选择要使用的模型',
                style: TextStyle(fontSize: 12.sp, color: Colors.grey),
              ),
              SizedBox(height: 12.h),

              // 搜索框
              TextField(
                controller: searchController,
                decoration: InputDecoration(
                  hintText: '搜索模型...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      searchController.clear();
                      filteredList.value = userSelectableModels;
                    },
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                ),
                onChanged: (value) {
                  if (value.isEmpty) {
                    filteredList.value = userSelectableModels;
                  } else {
                    filteredList.value = userSelectableModels
                        .where((m) =>
                            m.toLowerCase().contains(value.toLowerCase()))
                        .toList();
                  }
                },
              ),
              SizedBox(height: 12.h),

              // 列表
              Expanded(
                child: Obx(() {
                  if (filteredList.isEmpty) {
                    return const Center(child: Text('没有找到匹配的模型'));
                  }
                  return ListView.builder(
                    itemCount: filteredList.length,
                    itemBuilder: (context, index) {
                      final model = filteredList[index];
                      return Obx(() {
                        final isChecked = selected.contains(model);
                        return CheckboxListTile(
                          title: Text(
                            model,
                            style: TextStyle(fontSize: 13.sp),
                          ),
                          value: isChecked,
                          activeColor: AppTheme.primary,
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (bool? value) {
                            if (value == true) {
                              selected.add(model);
                            } else {
                              selected.remove(model);
                            }
                          },
                        );
                      });
                    },
                  );
                }),
              ),
              SizedBox(height: 16.h),

              // 按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Get.back(),
                    child: const Text('取消'),
                  ),
                  SizedBox(width: 16.w),
                  ElevatedButton(
                    onPressed: () => Get.back(result: selected.toList()),
                    child: const Text('保存'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteConfig(OpenAIConfig config) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除配置 "${config.name}" 吗?'),
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
      await _openAIService!.deleteConfig(config);
      ToastUtils.showSuccess('配置已删除');
    }
  }

  /// 格式化错误信息,提取关键信息
  String _formatError(dynamic error) {
    final errorStr = error.toString();
    // 尝试提取 Exception: 后面的内容
    if (errorStr.contains('Exception:')) {
      return errorStr.split('Exception:').last.trim();
    }
    // 尝试提取 error 字段
    if (errorStr.contains('error')) {
      return errorStr;
    }
    return errorStr;
  }

  Future<Map<String, dynamic>?> _showConfigDialog(
      {OpenAIConfig? existing}) async {
    String name = existing?.name ?? '';
    String baseUrl = existing?.baseUrl ?? 'https://api.openai.com';
    String apiKey = existing?.apiKey ?? '';
    bool enableWebSearch = existing?.enableWebSearch ?? false;

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(existing == null ? '添加配置' : '编辑配置'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      initialValue: name,
                      decoration: const InputDecoration(
                        labelText: '配置名称',
                        hintText: '如: OpenAI、Claude',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => name = v,
                    ),
                    SizedBox(height: 16.h),
                    TextFormField(
                      initialValue: baseUrl,
                      decoration: const InputDecoration(
                        labelText: 'API 地址 (Base URL)',
                        hintText: 'https://api.openai.com',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => baseUrl = v,
                    ),
                    SizedBox(height: 16.h),
                    TextFormField(
                      initialValue: apiKey,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'API Key',
                        hintText: 'sk-...',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => apiKey = v,
                    ),
                    SizedBox(height: 16.h),
                    SwitchListTile(
                      title: const Text('启用联网搜索 (Web Search)'),
                      subtitle: const Text('如果模型支持联网搜索,开启此选项'),
                      value: enableWebSearch,
                      onChanged: (val) {
                        setDialogState(() {
                          enableWebSearch = val;
                        });
                      },
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
                  onPressed: () {
                    if (name.isEmpty || baseUrl.isEmpty || apiKey.isEmpty) {
                      ToastUtils.showError('请填写所有字段');
                      return;
                    }
                    Navigator.of(ctx).pop({
                      'name': name,
                      'baseUrl':
                          baseUrl.trimRight().replaceAll(RegExp(r'/+$'), ''),
                      'apiKey': apiKey,
                      'enableWebSearch': enableWebSearch,
                    });
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
}
