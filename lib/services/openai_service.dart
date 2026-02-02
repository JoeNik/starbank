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
    loadConfigs();

    return this;
  }

  void loadConfigs() {
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
    loadConfigs();
  }

  /// 更新配置
  Future<void> updateConfig(OpenAIConfig config) async {
    await config.save();
    loadConfigs();
  }

  /// 删除配置
  Future<void> deleteConfig(OpenAIConfig config) async {
    await config.delete();
    loadConfigs();
  }

  /// 设置默认配置
  Future<void> setDefaultConfig(OpenAIConfig config) async {
    for (var c in configs) {
      c.isDefault = c.id == config.id;
      await c.save();
    }
    loadConfigs();
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
        final models =
            (data['data'] as List).map((m) => m['id'] as String).toList();
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
    String? model,
  }) async {
    final cfg = config ?? currentConfig.value;
    if (cfg == null) {
      throw Exception('未配置 OpenAI');
    }

    // 完整的消息历史
    List<Map<String, dynamic>> messages = [
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': userMessage},
    ];

    try {
      final uri = Uri.parse('${cfg.baseUrl}/v1/chat/completions');
      final headers = {
        'Authorization': 'Bearer ${cfg.apiKey}',
        'Content-Type': 'application/json',
      };

      // 构建请求体
      Map<String, dynamic> requestBody = {
        'model': model ??
            (cfg.selectedModel.isNotEmpty
                ? cfg.selectedModel
                : 'gpt-3.5-turbo'),
        'messages': messages,
        'temperature': 0.7,
        'max_tokens': 2000,
      };

      // 如果启用联网搜索，添加工具定义
      if (cfg.enableWebSearch) {
        requestBody['tools'] = [
          {
            'type': 'function',
            'function': {
              'name': 'web_search',
              'description': 'Search the internet for real-time information',
              'parameters': {
                'type': 'object',
                'properties': {
                  'query': {
                    'type': 'string',
                    'description': 'The search query',
                  },
                },
                'required': ['query'],
              },
            },
          }
        ];
      }

      var response = await http
          .post(uri, headers: headers, body: jsonEncode(requestBody))
          .timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body);
        throw Exception(
            error['error']?['message'] ?? '请求失败: ${response.statusCode}');
      }

      var data = jsonDecode(utf8.decode(response.bodyBytes));
      var message = data['choices'][0]['message'];

      // 检查是否有工具调用
      if (message['tool_calls'] != null) {
        final toolCalls = message['tool_calls'] as List;
        messages.add(message); // 添加助手的回复（包含工具调用）

        for (var toolCall in toolCalls) {
          if (toolCall['function']['name'] == 'web_search') {
            final args = jsonDecode(toolCall['function']['arguments']);
            final query = args['query'];

            // 模拟搜索结果
            final searchResult = "Simulated search result for: '$query'. \n"
                "Note: Actual web search is not available without a backend proxy or Search API Key. "
                "Please answer based on this context.";

            messages.add({
              'role': 'tool',
              'tool_call_id': toolCall['id'],
              'name': 'web_search',
              'content': searchResult,
            });
          }
        }

        // 再次调用模型
        requestBody['messages'] = messages;
        requestBody.remove('tools'); // 必须移除 tools 这里的简单实现防止多轮

        response = await http
            .post(uri, headers: headers, body: jsonEncode(requestBody))
            .timeout(const Duration(seconds: 60));

        if (response.statusCode != 200) {
          throw Exception('Tool response failed');
        }

        data = jsonDecode(utf8.decode(response.bodyBytes));
        message = data['choices'][0]['message'];
      }

      return message['content'] as String;
    } catch (e) {
      debugPrint('OpenAI 请求失败: $e');
      rethrow;
    }
  }

  /// 导出配置(用于备份)
  List<Map<String, dynamic>> exportConfigs() {
    return configs.map((c) => c.toJson()).toList();
  }

  /// 导入配置(用于恢复)
  Future<void> importConfigs(List<dynamic> data) async {
    for (var item in data) {
      final config = OpenAIConfig.fromJson(item as Map<String, dynamic>);
      await _configBox.put(config.id, config);
    }
    loadConfigs();
  }

  /// 生成新年故事
  /// [count] 生成数量(1-3)
  /// [theme] 故事主题
  /// [customPrompt] 自定义提示词(可选)
  Future<List<Map<String, dynamic>>> generateStories({
    required int count,
    String? theme,
    String? customPrompt,
    OpenAIConfig? config,
    String? model,
  }) async {
    if (count < 1 || count > 3) {
      throw Exception('生成数量必须在 1-3 之间');
    }

    final systemPrompt = '''你是一个专业的儿童故事创作者,擅长创作适合儿童的中国新年相关故事。
请严格按照 JSON 格式返回,不要添加任何其他文字说明。''';

    final userPrompt = customPrompt ??
        '''请生成 $count 个适合儿童的中国新年相关故事。

要求:
1. ${theme != null ? '故事主题: $theme' : '主题可以是春节习俗、传统文化、民间传说等'}
2. 每个故事包含 5-7 个页面
3. 每页包含: text(文本内容)、emoji(表情符号)、tts(语音播报文本)
4. 至少包含 1 个互动问题,问题包含: text(问题)、options(3个选项数组)、correctIndex(正确答案索引0-2)
5. 故事要有教育意义,语言简单易懂
6. 时长控制在 1-2 分钟

返回格式(JSON数组):
[
  {
    "id": "唯一标识(使用拼音_时间戳)",
    "title": "故事标题",
    "emoji": "🎊",
    "duration": "2分钟",
    "pages": [
      {
        "text": "故事文本",
        "emoji": "😊",
        "tts": "语音播报文本",
        "question": {
          "text": "问题文本",
          "options": ["选项1", "选项2", "选项3"],
          "correctIndex": 0
        }
      }
    ]
  }
]

请直接返回 JSON 数组,不要添加任何解释文字。''';

    try {
      final response = await chat(
        systemPrompt: systemPrompt,
        userMessage: userPrompt,
        config: config,
        model: model,
      );

      // 提取 JSON 内容(处理可能的 markdown 代码块)
      String jsonStr = response.trim();
      if (jsonStr.startsWith('```json')) {
        jsonStr = jsonStr.substring(7);
      } else if (jsonStr.startsWith('```')) {
        jsonStr = jsonStr.substring(3);
      }
      if (jsonStr.endsWith('```')) {
        jsonStr = jsonStr.substring(0, jsonStr.length - 3);
      }
      jsonStr = jsonStr.trim();

      final List<dynamic> stories = jsonDecode(jsonStr);
      return stories.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('生成故事失败: $e');
      rethrow;
    }
  }

  /// 生成新年问答题目
  /// [count] 生成数量(1-3)
  /// [category] 题目分类
  /// [customPrompt] 自定义提示词(可选)
  Future<List<Map<String, dynamic>>> generateQuizQuestions({
    required int count,
    String? category,
    String? customPrompt,
    OpenAIConfig? config,
    String? model,
  }) async {
    if (count < 1 || count > 3) {
      throw Exception('生成数量必须在 1-3 之间');
    }

    final systemPrompt = '''你是一个专业的儿童教育专家,擅长设计适合儿童的中国新年知识问答题。
请严格按照 JSON 格式返回,不要添加任何其他文字说明。''';

    final userPrompt = customPrompt ??
        '''请生成 $count 道关于中国新年的问答题。

要求:
1. ${category != null ? '题目分类: $category' : '分类可以是习俗、美食、传说、文化等'}
2. 每题包含: 问题、emoji、4个选项、正确答案索引(0-3)、知识点解释
3. 难度适合 3-8 岁儿童
4. 知识点解释要简单易懂,有教育意义
5. 选项要有一定迷惑性,但不要太难

返回格式(JSON数组):
[
  {
    "id": "唯一标识(使用拼音_时间戳)",
    "question": "问题文本",
    "emoji": "🎊",
    "options": ["选项1", "选项2", "选项3", "选项4"],
    "correctIndex": 0,
    "explanation": "知识点解释",
    "category": "${category ?? 'general'}"
  }
]

请直接返回 JSON 数组,不要添加任何解释文字。''';

    try {
      final response = await chat(
        systemPrompt: systemPrompt,
        userMessage: userPrompt,
        config: config,
        model: model,
      );

      // 提取 JSON 内容(处理可能的 markdown 代码块)
      String jsonStr = response.trim();
      if (jsonStr.startsWith('```json')) {
        jsonStr = jsonStr.substring(7);
      } else if (jsonStr.startsWith('```')) {
        jsonStr = jsonStr.substring(3);
      }
      if (jsonStr.endsWith('```')) {
        jsonStr = jsonStr.substring(0, jsonStr.length - 3);
      }
      jsonStr = jsonStr.trim();

      final List<dynamic> questions = jsonDecode(jsonStr);
      return questions.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('生成题目失败: $e');
      rethrow;
    }
  }

  /// 验证生成的故事格式是否正确
  bool validateStoryFormat(Map<String, dynamic> story) {
    try {
      if (!story.containsKey('id') ||
          !story.containsKey('title') ||
          !story.containsKey('emoji') ||
          !story.containsKey('duration') ||
          !story.containsKey('pages')) {
        return false;
      }

      final pages = story['pages'] as List;
      if (pages.isEmpty) return false;

      for (var page in pages) {
        if (!page.containsKey('text') ||
            !page.containsKey('emoji') ||
            !page.containsKey('tts')) {
          return false;
        }
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// 验证生成的题目格式是否正确
  bool validateQuestionFormat(Map<String, dynamic> question) {
    try {
      if (!question.containsKey('id') ||
          !question.containsKey('question') ||
          !question.containsKey('emoji') ||
          !question.containsKey('options') ||
          !question.containsKey('correctIndex') ||
          !question.containsKey('explanation') ||
          !question.containsKey('category')) {
        return false;
      }

      final options = question['options'] as List;
      if (options.length != 4) return false;

      final correctIndex = question['correctIndex'] as int;
      if (correctIndex < 0 || correctIndex >= 4) return false;

      return true;
    } catch (e) {
      return false;
    }
  }

  /// 生成图片(多张)
  Future<List<String>> generateImages({
    required String prompt,
    int n = 1,
    OpenAIConfig? config,
    String? model,
  }) async {
    final cfg = config ?? currentConfig.value;
    if (cfg == null) {
      throw Exception('未配置 OpenAI');
    }

    // 根据配置的供应商类型选择不同的图片生成逻辑
    // 假设 OpenAIConfig 中有一个 providerType 字段，或者根据 baseUrl 判断
    // 为了兼容性，这里暂时只处理 OpenAI 的逻辑，但结构上为未来扩展留出接口
    // 实际重构时，可能需要引入一个抽象的 ImageGenerator 接口和不同的实现类
    // 例如:
    // if (cfg.providerType == ProviderType.openAI) {
    //   return _generateImagesWithOpenAI(prompt, n, cfg, model);
    // } else if (cfg.providerType == ProviderType.stabilityAI) {
    //   return _generateImagesWithStabilityAI(prompt, n, cfg, model);
    // } else {
    //   throw Exception('不支持的图片生成供应商');
    // }

    // 目前仍沿用 OpenAI 的实现，但将其封装成私有方法，便于未来替换或扩展
    return _generateImagesWithOpenAI(prompt, n, cfg, model);
  }

  /// 内部方法: 使用 OpenAI API 生成图片
  Future<List<String>> _generateImagesWithOpenAI(
    String prompt,
    int n,
    OpenAIConfig cfg,
    String? model,
  ) async {
    try {
      final uri = Uri.parse('${cfg.baseUrl}/v1/images/generations');
      final modelName = model ??
          (cfg.selectedModel.isNotEmpty ? cfg.selectedModel : 'dall-e-3');

      // DALL-E 3 不支持 n > 1,需要循环调用
      // DALL-E 2 支持 n 参数
      final isDallE3 = modelName.toLowerCase().contains('dall-e-3');

      if (isDallE3 && n > 1) {
        // DALL-E 3: 循环生成多张图片
        debugPrint('🎨 DALL-E 3 检测到,将循环生成 $n 张图片');
        final List<String> allUrls = [];

        for (int i = 0; i < n; i++) {
          debugPrint('🎨 正在生成第 ${i + 1}/$n 张图片...');

          final response = await http
              .post(
                uri,
                headers: {
                  'Authorization': 'Bearer ${cfg.apiKey}',
                  'Content-Type': 'application/json',
                },
                body: jsonEncode({
                  'model': modelName,
                  'prompt': prompt,
                  'n': 1,
                  'size': '1024x1024',
                }),
              )
              .timeout(const Duration(seconds: 120));

          if (response.statusCode == 200) {
            final data = jsonDecode(utf8.decode(response.bodyBytes));
            final List<dynamic> list = data['data'];

            // 解析图片,支持 URL 和 base64
            final imageData = list.first;
            if (imageData['url'] != null) {
              allUrls.add(imageData['url'] as String);
            } else if (imageData['b64_json'] != null) {
              allUrls.add('data:image/png;base64,${imageData['b64_json']}');
            } else {
              throw Exception('图片响应格式错误');
            }

            // 避免频繁调用 API,添加延迟
            if (i < n - 1) {
              await Future.delayed(const Duration(milliseconds: 500));
            }
          } else {
            Map<String, dynamic> error;
            try {
              error = jsonDecode(utf8.decode(response.bodyBytes));
            } catch (_) {
              error = {
                'error': {'message': 'Response: ${response.body}'}
              };
            }
            throw Exception(
                error['error']?['message'] ?? '生成图片失败: ${response.statusCode}');
          }
        }

        debugPrint('🎨 DALL-E 3 成功生成 ${allUrls.length} 张图片');
        return allUrls;
      } else {
        // DALL-E 2 或单张图片: 直接调用
        final response = await http
            .post(
              uri,
              headers: {
                'Authorization': 'Bearer ${cfg.apiKey}',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'model': modelName,
                'prompt': prompt,
                'n': n,
                'size': '1024x1024',
              }),
            )
            .timeout(const Duration(seconds: 120));

        if (response.statusCode == 200) {
          final data = jsonDecode(utf8.decode(response.bodyBytes));
          final List<dynamic> list = data['data'];

          // 解析图片数据,支持两种格式:
          // 1. URL 格式: {"url": "https://..."}
          // 2. Base64 格式: {"b64_json": "iVBORw0KGgo..."}
          return list.map((e) {
            // 优先使用 URL
            if (e['url'] != null) {
              return e['url'] as String;
            }
            // 如果是 base64,返回 data URI
            else if (e['b64_json'] != null) {
              return 'data:image/png;base64,${e['b64_json']}';
            }
            // 兜底错误
            else {
              throw Exception('图片响应格式错误: 既没有 url 也没有 b64_json');
            }
          }).toList();
        } else {
          Map<String, dynamic> error;
          try {
            error = jsonDecode(utf8.decode(response.bodyBytes));
          } catch (_) {
            error = {
              'error': {'message': 'Response: ${response.body}'}
            };
          }
          throw Exception(
              error['error']?['message'] ?? '生成图片失败: ${response.statusCode}');
        }
      }
    } catch (e) {
      debugPrint('生图 API 调用失败: $e');
      rethrow;
    }
  }

  /// 生成单张图片 (兼容旧代码)
  Future<String> generateImage({
    required String prompt,
    OpenAIConfig? config,
    String? model,
  }) async {
    final images = await generateImages(
      prompt: prompt,
      n: 1,
      config: config,
      model: model,
    );
    return images.first;
  }
}
