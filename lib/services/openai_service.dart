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
          .timeout(const Duration(seconds: 180));

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
            .timeout(const Duration(seconds: 180));

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
        '''请生成 $count 个关于中国传统春节习俗及其由来的科普故事，适合儿童阅读。

重点：不要生成虚构的童话故事，而是要以生动有趣的方式讲解真实的民俗知识（如：为什么过年要吃饺子？春联的由来？压岁钱的寓意？）。

要求:
1. ${theme != null ? '故事主题: $theme' : '主题必须围绕春节传统习俗的由来、传说或具体礼仪（例如：年兽的传说、贴福字的由来、拜年的礼仪、元宵节的习俗等）'}
2. 每个故事包含 5-7 个页面
3. 每页包含: text(展示文本，简练有趣)、emoji(相关表情)、tts(口语化播报，语气亲切，适合讲给孩子听)
4. 至少包含 1 个互动问题，考察孩子对刚才科普知识的理解，问题包含: text(问题)、options(3个选项数组)、correctIndex(正确答案索引0-2)
5. 内容必须准确、有教育意义，弘扬传统文化
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

    final modelName = model ??
        (cfg.selectedModel.isNotEmpty ? cfg.selectedModel : 'dall-e-3');

    // 检测是否需要使用流式API
    // grok-imagine 等模型使用流式API
    final useStreamApi = modelName.toLowerCase().contains('grok-imagine') ||
        modelName.toLowerCase().contains('flux') ||
        modelName.toLowerCase().contains('stable-diffusion');

    if (useStreamApi) {
      debugPrint('🔄 检测到流式图片生成模型，使用流式API');
      return generateImagesStream(
        prompt: prompt,
        n: n,
        config: config,
        model: model,
      );
    }

    // 使用传统的OpenAI图片生成API
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
      // 使用 chat/completions 接口而非 images/generations
      // 某些 API 提供商(如 grok-imagine)通过此接口生成图片
      final uri = Uri.parse('${cfg.baseUrl}/v1/chat/completions');
      final modelName = model ??
          (cfg.selectedModel.isNotEmpty ? cfg.selectedModel : 'dall-e-3');

      debugPrint('🎨 ========== 图片生成请求 ==========');
      debugPrint('📍 API 地址: $uri');
      debugPrint('🤖 模型: $modelName');
      debugPrint('📝 提示词: $prompt');
      debugPrint('🔢 数量: $n');

      // DALL-E 3 不支持 n > 1,需要循环调用
      final isDallE3 = modelName.toLowerCase().contains('dall-e-3');

      if (isDallE3 && n > 1) {
        debugPrint('⚠️ DALL-E 3 不支持 n>1,将循环生成 $n 张图片');
        final List<String> allUrls = [];

        for (int i = 0; i < n; i++) {
          debugPrint('🎨 [${i + 1}/$n] 开始生成...');

          final requestBody = {
            'messages': [
              {
                'role': 'user',
                'content': '生成图片：$prompt',
              }
            ],
            'model': modelName,
            'stream': false,
          };

          debugPrint('📤 请求体: ${jsonEncode(requestBody)}');

          final response = await http
              .post(
                uri,
                headers: {
                  'Authorization': 'Bearer ${cfg.apiKey}',
                  'Content-Type': 'application/json',
                },
                body: jsonEncode(requestBody),
              )
              .timeout(const Duration(seconds: 300));

          debugPrint('📥 响应状态码: ${response.statusCode}');
          debugPrint('📥 响应头: ${response.headers}');

          if (response.statusCode == 200) {
            final responseText = utf8.decode(response.bodyBytes);
            debugPrint('📥 响应体: $responseText');

            final data = jsonDecode(responseText);
            final List<dynamic> list = data['data'];

            if (list.isEmpty) {
              throw Exception('API 返回的 data 数组为空');
            }

            final imageData = list.first;
            if (imageData['url'] != null) {
              final url = imageData['url'] as String;
              debugPrint('✅ [${i + 1}/$n] 成功获取图片 URL: $url');
              allUrls.add(url);
            } else if (imageData['b64_json'] != null) {
              debugPrint('✅ [${i + 1}/$n] 成功获取 Base64 图片');
              allUrls.add('data:image/png;base64,${imageData['b64_json']}');
            } else {
              throw Exception('图片响应格式错误: ${jsonEncode(imageData)}');
            }

            if (i < n - 1) {
              await Future.delayed(const Duration(milliseconds: 500));
            }
          } else {
            final errorBody = utf8.decode(response.bodyBytes);
            debugPrint('❌ 错误响应体: $errorBody');

            Map<String, dynamic> error;
            try {
              error = jsonDecode(errorBody);
            } catch (_) {
              error = {
                'error': {
                  'message': 'HTTP ${response.statusCode}: $errorBody',
                  'type': 'http_error',
                }
              };
            }

            final errorMsg = error['error']?['message'] ??
                error['message'] ??
                'HTTP ${response.statusCode}: $errorBody';
            throw Exception('生成第 ${i + 1} 张图片失败: $errorMsg');
          }
        }

        debugPrint('🎉 成功生成 ${allUrls.length} 张图片');
        return allUrls;
      } else {
        // DALL-E 2 或单张图片: 直接调用
        final requestBody = {
          'messages': [
            {
              'role': 'user',
              'content': '生成图片：$prompt',
            }
          ],
          'model': modelName,
          'stream': false,
        };

        debugPrint('📤 请求体: ${jsonEncode(requestBody)}');

        final response = await http
            .post(
              uri,
              headers: {
                'Authorization': 'Bearer ${cfg.apiKey}',
                'Content-Type': 'application/json',
              },
              body: jsonEncode(requestBody),
            )
            .timeout(const Duration(seconds: 300));

        debugPrint('📥 响应状态码: ${response.statusCode}');
        debugPrint('📥 响应头: ${response.headers}');

        if (response.statusCode == 200) {
          final responseText = utf8.decode(response.bodyBytes);
          debugPrint('📥 响应体: $responseText');

          final data = jsonDecode(responseText);
          final List<dynamic> list = data['data'];

          if (list.isEmpty) {
            throw Exception('API 返回的 data 数组为空');
          }

          final urls = list.map((e) {
            if (e['url'] != null) {
              return e['url'] as String;
            } else if (e['b64_json'] != null) {
              return 'data:image/png;base64,${e['b64_json']}';
            } else {
              throw Exception('图片响应格式错误: ${jsonEncode(e)}');
            }
          }).toList();

          debugPrint('🎉 成功生成 ${urls.length} 张图片');
          return urls;
        } else {
          final errorBody = utf8.decode(response.bodyBytes);
          debugPrint('❌ 错误响应体: $errorBody');

          Map<String, dynamic> error;
          try {
            error = jsonDecode(errorBody);
          } catch (_) {
            error = {
              'error': {
                'message': 'HTTP ${response.statusCode}: $errorBody',
                'type': 'http_error',
              }
            };
          }

          final errorMsg = error['error']?['message'] ??
              error['message'] ??
              'HTTP ${response.statusCode}: $errorBody';
          throw Exception('生成图片失败: $errorMsg');
        }
      }
    } catch (e, stackTrace) {
      debugPrint('❌ ========== 图片生成失败 ==========');
      debugPrint('错误: $e');
      debugPrint('堆栈: $stackTrace');
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

  /// 使用流式API生成图片 (支持grok-imagine等流式返回的API)
  /// 返回图片URL列表或base64数据URI列表
  Future<List<String>> generateImagesStream({
    required String prompt,
    int n = 1,
    OpenAIConfig? config,
    String? model,
  }) async {
    final cfg = config ?? currentConfig.value;
    if (cfg == null) {
      throw Exception('未配置 OpenAI');
    }

    try {
      final uri = Uri.parse('${cfg.baseUrl}/v1/chat/completions');
      final modelName = model ??
          (cfg.selectedModel.isNotEmpty
              ? cfg.selectedModel
              : 'grok-imagine-0.9');

      debugPrint('🎨 ========== 流式图片生成请求 ==========');
      debugPrint('📍 API 地址: $uri');
      debugPrint('🤖 模型: $modelName');
      debugPrint('📝 提示词: $prompt');
      debugPrint('🔢 数量: $n');

      // 构建请求体 - 使用流式API格式
      final requestBody = {
        'messages': [
          {
            'role': 'user',
            'content': '生成图片：$prompt',
          }
        ],
        'model': modelName,
        'stream': true,
        'stream_options': {
          'include_usage': true,
        },
        'temperature': 1,
      };

      debugPrint('📤 请求体: ${jsonEncode(requestBody)}');

      final request = http.Request('POST', uri);
      request.headers.addAll({
        'Authorization': 'Bearer ${cfg.apiKey}',
        'Content-Type': 'application/json',
      });
      request.body = jsonEncode(requestBody);

      final streamedResponse = await request.send().timeout(
            const Duration(seconds: 300),
          );

      debugPrint('📥 响应状态码: ${streamedResponse.statusCode}');

      if (streamedResponse.statusCode != 200) {
        final errorBody = await streamedResponse.stream.bytesToString();
        debugPrint('❌ 错误响应体: $errorBody');
        throw Exception('流式图片生成失败: HTTP ${streamedResponse.statusCode}');
      }

      // 解析流式响应
      final List<String> imageUrls = [];
      String accumulatedContent = '';

      await for (var chunk in streamedResponse.stream.transform(utf8.decoder)) {
        debugPrint('📦 收到数据块: $chunk');

        // 处理多行数据
        final lines = chunk.split('\n');
        for (var line in lines) {
          line = line.trim();
          if (line.isEmpty || !line.startsWith('data: ')) continue;

          final dataStr = line.substring(6); // 移除 "data: " 前缀
          if (dataStr == '[DONE]') continue;

          try {
            final data = jsonDecode(dataStr);
            final choices = data['choices'] as List?;
            if (choices == null || choices.isEmpty) continue;

            final delta = choices[0]['delta'];
            final content = delta['content'] as String?;
            if (content != null) {
              accumulatedContent += content;
            }

            final finishReason = choices[0]['finish_reason'];
            if (finishReason == 'stop') {
              debugPrint('✅ 流式响应完成，累积内容: $accumulatedContent');
            }
          } catch (e) {
            debugPrint('⚠️ 解析数据块失败: $e, 数据: $dataStr');
          }
        }
      }

      // 从累积的内容中提取图片URL
      imageUrls.addAll(_extractImageUrls(accumulatedContent));

      if (imageUrls.isEmpty) {
        throw Exception('未能从响应中提取到图片URL');
      }

      debugPrint('🎉 成功提取 ${imageUrls.length} 张图片');
      for (var url in imageUrls) {
        debugPrint('  - $url');
      }

      return imageUrls;
    } catch (e, stackTrace) {
      debugPrint('❌ ========== 流式图片生成失败 ==========');
      debugPrint('错误: $e');
      debugPrint('堆栈: $stackTrace');
      rethrow;
    }
  }

  /// 从文本中提取图片URL
  /// 支持markdown格式: ![alt](url)
  /// 支持base64格式: data:image/...;base64,...
  List<String> _extractImageUrls(String text) {
    final List<String> urls = [];

    // 提取markdown格式的图片链接: ![...](url)
    final markdownRegex = RegExp(r'!\[.*?\]\((.*?)\)');
    final markdownMatches = markdownRegex.allMatches(text);
    for (var match in markdownMatches) {
      final url = match.group(1);
      if (url != null && url.isNotEmpty) {
        urls.add(url);
      }
    }

    // 提取base64格式的图片数据
    final base64Regex = RegExp(r'data:image/[^;]+;base64,[A-Za-z0-9+/=]+');
    final base64Matches = base64Regex.allMatches(text);
    for (var match in base64Matches) {
      final dataUri = match.group(0);
      if (dataUri != null && dataUri.isNotEmpty) {
        urls.add(dataUri);
      }
    }

    return urls;
  }
}
