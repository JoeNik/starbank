// 图片生成辅助方法 - 使用 Chat Completions 接口
// 将此代码添加到 openai_service.dart 中

/// 通过 Chat Completions 接口生成图片
/// 某些 API 提供商(如 grok-imagine)使用此方式
Future<List<String>> generateImagesViaChatCompletions(
  String prompt,
  int n,
  OpenAIConfig cfg,
  String? model,
) async {
  try {
    final uri = Uri.parse('${cfg.baseUrl}/v1/chat/completions');
    final modelName = model ??
        (cfg.selectedModel.isNotEmpty ? cfg.selectedModel : 'dall-e-3');

    debugPrint('🎨 ========== 图片生成请求 (Chat Completions) ==========');
    debugPrint('📍 API 地址: $uri');
    debugPrint('🤖 模型: $modelName');
    debugPrint('📝 原始提示词: $prompt');
    debugPrint('🔢 请求数量: $n');

    // 构建生图专用的 prompt
    final imagePrompt = '生成图片：$prompt';
    debugPrint('📝 生图提示词: $imagePrompt');

    final requestBody = {
      'model': modelName,
      'messages': [
        {
          'role': 'user',
          'content': imagePrompt,
        }
      ],
      'stream': false,
      'temperature': 1,
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
        .timeout(const Duration(seconds: 120));

    debugPrint('📥 响应状态码: ${response.statusCode}');

    if (response.statusCode == 200) {
      final responseText = utf8.decode(response.bodyBytes);
      debugPrint('📥 响应体: $responseText');

      final data = jsonDecode(responseText);

      if (data['choices'] == null || (data['choices'] as List).isEmpty) {
        throw Exception('API 返回的 choices 数组为空');
      }

      final choice = data['choices'][0];
      final content =
          choice['message']?['content'] ?? choice['delta']?['content'] ?? '';

      debugPrint('📝 AI 返回内容: $content');

      // 从内容中提取图片链接
      final imageUrls = _extractImageUrlsFromText(content);

      if (imageUrls.isEmpty) {
        throw Exception('未能从响应中提取到图片链接。响应内容: $content');
      }

      debugPrint('🎉 成功提取 ${imageUrls.length} 个图片链接');

      // 如果需要多张图片,递归调用
      if (imageUrls.length < n) {
        final remaining = n - imageUrls.length;
        final additionalUrls = await generateImagesViaChatCompletions(
            prompt, remaining, cfg, model);
        imageUrls.addAll(additionalUrls);
      }

      return imageUrls.take(n).toList();
    } else {
      final errorBody = utf8.decode(response.bodyBytes);
      debugPrint('❌ 错误响应体: $errorBody');
      throw Exception('生成图片失败: HTTP ${response.statusCode}');
    }
  } catch (e, stackTrace) {
    debugPrint('❌ 图片生成失败: $e');
    debugPrint('堆栈: $stackTrace');
    rethrow;
  }
}

/// 从文本中提取图片链接
List<String> _extractImageUrlsFromText(String content) {
  final List<String> urls = [];

  // 1. Markdown 格式: ![alt](url)
  final markdownRegex = RegExp(r'!\[.*?\]\((.*?)\)');
  for (final match in markdownRegex.allMatches(content)) {
    final url = match.group(1);
    if (url != null && url.isNotEmpty) {
      urls.add(url);
      debugPrint('  ✅ 提取 Markdown 图片: $url');
    }
  }

  // 2. 直接 URL
  if (urls.isEmpty) {
    final urlRegex = RegExp(r'https?://[^\s\)]+\.(jpg|jpeg|png|gif|webp)',
        caseSensitive: false);
    for (final match in urlRegex.allMatches(content)) {
      final url = match.group(0);
      if (url != null && !urls.contains(url)) {
        urls.add(url);
        debugPrint('  ✅ 提取直接 URL: $url');
      }
    }
  }

  // 3. Base64
  if (urls.isEmpty) {
    final base64Regex = RegExp(r'data:image/[^;]+;base64,[A-Za-z0-9+/=]+');
    for (final match in base64Regex.allMatches(content)) {
      final dataUri = match.group(0);
      if (dataUri != null) {
        urls.add(dataUri);
        debugPrint('  ✅ 提取 Base64 图片');
      }
    }
  }

  return urls;
}
