import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../models/openai_config.dart';
import '../services/openai_service.dart';
import '../theme/app_theme.dart';

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
      // 服务未注册，需要初始化
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
            '添加 OpenAI 兼容的 API 配置\n支持 OpenAI、Claude、通义千问等',
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
                    const PopupMenuItem(value: 'refresh', child: Text('刷新模型')),
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
            _buildInfoRow('API Key', '${config.apiKey.substring(0, 8)}...'),
            _buildInfoRow('当前模型',
                config.selectedModel.isNotEmpty ? config.selectedModel : '未选择'),
            if (config.models.isNotEmpty) ...[
              SizedBox(height: 8.h),
              Text(
                '可用模型 (${config.models.length})',
                style: TextStyle(fontSize: 12.sp, color: Colors.grey),
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
        _refreshModels(config);
        break;
      case 'delete':
        _deleteConfig(config);
        break;
    }
  }

  Future<void> _selectModel(OpenAIConfig config, String model) async {
    config.selectedModel = model;
    await _openAIService!.updateConfig(config);
    Get.snackbar('成功', '已选择模型: $model', snackPosition: SnackPosition.BOTTOM);
  }

  Future<void> _addConfig() async {
    final result = await _showConfigDialog();
    if (result != null) {
      final config = OpenAIConfig(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: result['name'] as String,
        baseUrl: result['baseUrl'] as String,
        apiKey: result['apiKey'] as String,
      );

      // 尝试获取模型列表
      try {
        Get.dialog(
          const Center(child: CircularProgressIndicator()),
          barrierDismissible: false,
        );

        final models =
            await _openAIService!.fetchModels(config.baseUrl, config.apiKey);
        config.models = models;
        if (models.isNotEmpty) {
          config.selectedModel = models.first;
        }

        Get.back();
      } catch (e) {
        Get.back();
        Get.snackbar('提示', '无法获取模型列表: $e', snackPosition: SnackPosition.BOTTOM);
      }

      await _openAIService!.addConfig(config);
      Get.snackbar('成功', '配置已添加', snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _editConfig(OpenAIConfig config) async {
    final result = await _showConfigDialog(existing: config);
    if (result != null) {
      config.name = result['name'] as String;
      config.baseUrl = result['baseUrl'] as String;
      config.apiKey = result['apiKey'] as String;
      await _openAIService!.updateConfig(config);
      Get.snackbar('成功', '配置已更新', snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _refreshModels(OpenAIConfig config) async {
    try {
      Get.dialog(
        const Center(child: CircularProgressIndicator()),
        barrierDismissible: false,
      );

      final models =
          await _openAIService!.fetchModels(config.baseUrl, config.apiKey);
      config.models = models;
      await _openAIService!.updateConfig(config);

      Get.back();
      Get.snackbar('成功', '已刷新 ${models.length} 个模型',
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.back();
      Get.snackbar('失败', '获取模型列表失败: $e', snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _deleteConfig(OpenAIConfig config) async {
    final confirm = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除配置 "${config.name}" 吗？'),
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
      await _openAIService!.deleteConfig(config);
      Get.snackbar('成功', '配置已删除', snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<Map<String, String>?> _showConfigDialog(
      {OpenAIConfig? existing}) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final urlController = TextEditingController(
        text: existing?.baseUrl ?? 'https://api.openai.com');
    final keyController = TextEditingController(text: existing?.apiKey ?? '');

    return Get.dialog<Map<String, String>>(
      AlertDialog(
        title: Text(existing == null ? '添加配置' : '编辑配置'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '配置名称',
                  hintText: '如: OpenAI、Claude',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 16.h),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: 'API 地址 (Base URL)',
                  hintText: 'https://api.openai.com',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 16.h),
              TextField(
                controller: keyController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'API Key',
                  hintText: 'sk-...',
                  border: OutlineInputBorder(),
                ),
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
            onPressed: () {
              if (nameController.text.isEmpty ||
                  urlController.text.isEmpty ||
                  keyController.text.isEmpty) {
                Get.snackbar('错误', '请填写所有字段',
                    snackPosition: SnackPosition.BOTTOM);
                return;
              }
              Get.back(result: {
                'name': nameController.text,
                'baseUrl': urlController.text
                    .trimRight()
                    .replaceAll(RegExp(r'/+$'), ''),
                'apiKey': keyController.text,
              });
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
