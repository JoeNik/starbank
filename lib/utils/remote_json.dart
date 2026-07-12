/// Safe helpers for decoding and reading remote JSON payloads.
///
/// Used by network-facing services to avoid crashes when the remote body is
/// empty, non-JSON, or missing expected fields.
library;

import 'dart:convert';

/// Decodes a JSON body. Returns null for empty / invalid / non-decodable input.
dynamic tryDecodeJson(String? body) {
  if (body == null) return null;
  final trimmed = body.trim();
  if (trimmed.isEmpty) return null;
  try {
    return jsonDecode(trimmed);
  } catch (_) {
    return null;
  }
}

/// Decodes a JSON object. Returns null when body is empty, invalid, or not a Map.
Map<String, dynamic>? tryDecodeJsonObject(String? body) {
  return asJsonMap(tryDecodeJson(body));
}

/// Decodes a JSON array. Returns null when body is empty, invalid, or not a List.
List<dynamic>? tryDecodeJsonList(String? body) {
  return asJsonList(tryDecodeJson(body));
}

Map<String, dynamic>? asJsonMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

List<dynamic>? asJsonList(dynamic value) {
  if (value is List) return value;
  return null;
}

String? asNonEmptyString(dynamic value) {
  if (value == null) return null;
  final text = value is String ? value.trim() : value.toString().trim();
  if (text.isEmpty || text == 'null') return null;
  return text;
}

/// Reads a nested path of maps, e.g. `readJsonPath(data, ['error', 'message'])`.
dynamic readJsonPath(dynamic root, List<Object> path) {
  dynamic current = root;
  for (final key in path) {
    if (current is Map && key is String) {
      current = current[key];
      continue;
    }
    if (current is List && key is int) {
      if (key < 0 || key >= current.length) return null;
      current = current[key];
      continue;
    }
    return null;
  }
  return current;
}

/// Extracts OpenAI-compatible `choices[0].message` from a chat completion body.
Map<String, dynamic>? extractChatCompletionMessage(Map<String, dynamic> data) {
  final choices = asJsonList(data['choices']);
  if (choices == null || choices.isEmpty) return null;
  final first = asJsonMap(choices.first);
  if (first == null) return null;
  return asJsonMap(first['message']);
}

/// Extracts assistant text content from a chat completion message map.
///
/// Supports plain string content and multi-part content arrays used by some
/// OpenAI-compatible providers.
String? extractMessageContent(Map<String, dynamic> message) {
  final content = message['content'];
  if (content is String) {
    return content;
  }
  if (content is List) {
    final buffer = StringBuffer();
    for (final part in content) {
      if (part is String) {
        buffer.write(part);
        continue;
      }
      final partMap = asJsonMap(part);
      if (partMap == null) continue;
      final type = partMap['type']?.toString();
      if (type == null || type == 'text' || type == 'output_text') {
        final text = partMap['text'] ?? partMap['content'];
        if (text != null) buffer.write(text.toString());
      }
    }
    final text = buffer.toString();
    return text.isEmpty ? null : text;
  }
  return null;
}

/// Extracts assistant text from a full chat completion response body.
String? extractChatCompletionContent(Map<String, dynamic> data) {
  final message = extractChatCompletionMessage(data);
  if (message == null) return null;
  return extractMessageContent(message);
}

/// Builds a human-readable error message from an OpenAI-style error body.
String openAiErrorMessage(String? body, int statusCode) {
  final map = tryDecodeJsonObject(body);
  if (map != null) {
    final nested = readJsonPath(map, ['error', 'message']);
    final direct = map['message'];
    final msg = asNonEmptyString(nested) ?? asNonEmptyString(direct);
    if (msg != null) return msg;
  }
  if (body != null && body.trim().isNotEmpty) {
    final preview = body.trim();
    final short =
        preview.length > 200 ? '${preview.substring(0, 200)}...' : preview;
    return '请求失败: $statusCode $short';
  }
  return '请求失败: $statusCode';
}

/// Extracts image URLs / data-URIs from an OpenAI images response body.
List<String> extractImagePayloadUrls(Map<String, dynamic> data) {
  final list = asJsonList(data['data']);
  if (list == null) {
    throw const FormatException('图片响应缺少 data 数组');
  }
  if (list.isEmpty) {
    throw const FormatException('API 返回的 data 数组为空');
  }

  final urls = <String>[];
  for (final item in list) {
    final map = asJsonMap(item);
    if (map == null) {
      throw FormatException('图片响应项格式错误: $item');
    }
    final url = asNonEmptyString(map['url']);
    if (url != null) {
      urls.add(url);
      continue;
    }
    final b64 = asNonEmptyString(map['b64_json']);
    if (b64 != null) {
      urls.add('data:image/png;base64,$b64');
      continue;
    }
    throw FormatException('图片响应格式错误: ${jsonEncode(map)}');
  }
  return urls;
}
