import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import '../models/openai_config.dart';

/// OpenAI 服务
/// 封装对 OpenAI 兼容 API 的调用
class OpenAIService extends GetxService {
  late Box<OpenAIConfig> _configBox;

  // 当前配置
  final Rx<OpenAIConfig?> currentConfig = Rx<OpenAIConfig?>(null);

  // 所有配置列表
  final RxList<OpenAIConfig> configs = <OpenAIConfig>[].obs;

  Future<OpenAIService> init() async {
    // 注册适配器
    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(OpenAIConfigAdapter());
    }
    _configBox = await Hive.openBox<OpenAIConfig>('openai_configs');

    // 加载配置
    _loadConfigs();

    return this;
  }

  void _loadConfigs() {
    configs.assignAll(_configBox.values.toList());

    // 找到默认配置
    final defaultConfig = configs.firstWhereOrNull((c) => c.isDefault);
    if (defaultConfig != null) {
      currentConfig.value = defaultConfig;
    } else if (configs.isNotEmpty) {
      currentConfig.value = configs.first;
    }
  }

  /// 添加配置
  Future<void> addConfig(OpenAIConfig config) async {
    // 如果是第一个配置，设为默认
    if (configs.isEmpty) {
      config.isDefault = true;
    }

    await _configBox.put(config.id, config);
    _loadConfigs();
  }

  /// 更新配置
  Future<void> updateConfig(OpenAIConfig config) async {
    await config.save();
    _loadConfigs();
  }

  /// 删除配置
  Future<void> deleteConfig(OpenAIConfig config) async {
    await config.delete();
    _loadConfigs();
  }

  /// 设置默认配置
  Future<void> setDefaultConfig(OpenAIConfig config) async {
    for (var c in configs) {
      c.isDefault = c.id == config.id;
      await c.save();
    }
    _loadConfigs();
  }

  /// 测试连接并获取模型列表
  Future<List<String>> fetchModels(String baseUrl, String apiKey) async {
    try {
      final uri = Uri.parse('$baseUrl/v1/models');
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final models = (data['data'] as List)
            .map((m) => m['id'] as String)
            .where((id) =>
                id.contains('gpt') ||
                id.contains('claude') ||
                id.contains('qwen'))
            .toList();
        models.sort();
        return models;
      } else {
        throw Exception('获取模型失败: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('获取模型列表失败: $e');
      rethrow;
    }
  }

  /// 发送聊天请求
  Future<String> chat({
    required String systemPrompt,
    required String userMessage,
    OpenAIConfig? config,
  }) async {
    final cfg = config ?? currentConfig.value;
    if (cfg == null) {
      throw Exception('未配置 OpenAI');
    }

    try {
      final uri = Uri.parse('${cfg.baseUrl}/v1/chat/completions');
      final response = await http
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer ${cfg.apiKey}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': cfg.selectedModel.isNotEmpty
                  ? cfg.selectedModel
                  : 'gpt-3.5-turbo',
              'messages': [
                {'role': 'system', 'content': systemPrompt},
                {'role': 'user', 'content': userMessage},
              ],
              'temperature': 0.7,
              'max_tokens': 2000,
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final content = data['choices'][0]['message']['content'] as String;
        return content;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(
            error['error']?['message'] ?? '请求失败: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('OpenAI 请求失败: $e');
      rethrow;
    }
  }

  /// 导出配置（用于备份）
  List<Map<String, dynamic>> exportConfigs() {
    return configs.map((c) => c.toJson()).toList();
  }

  /// 导入配置（用于恢复）
  Future<void> importConfigs(List<dynamic> data) async {
    for (var item in data) {
      final config = OpenAIConfig.fromJson(item as Map<String, dynamic>);
      await _configBox.put(config.id, config);
    }
    _loadConfigs();
  }
}
