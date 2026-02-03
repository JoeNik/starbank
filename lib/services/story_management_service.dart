import 'dart:convert';
import 'dart:io';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import '../models/new_year_story.dart';
import '../data/new_year_story_data.dart';

/// 故事管理服务
class StoryManagementService {
  static const String _boxName = 'new_year_stories';
  static StoryManagementService? _instance;
  Box<NewYearStory>? _box;

  StoryManagementService._();

  /// 获取单例实例
  static StoryManagementService get instance {
    _instance ??= StoryManagementService._();
    return _instance!;
  }

  /// 初始化服务
  Future<void> init() async {
    if (_box == null || !_box!.isOpen) {
      _box = await Hive.openBox<NewYearStory>(_boxName);

      // 如果是首次初始化,导入内置故事
      if (_box!.isEmpty) {
        await _importBuiltInStories();
      }
    }
  }

  /// 导入内置故事
  Future<void> _importBuiltInStories() async {
    final builtInStories = NewYearStoryData.getAllStories();

    for (var storyMap in builtInStories) {
      final story = NewYearStory.fromLegacyMap(storyMap);
      await _box!.put(story.id, story);
    }

    print('已导入 ${builtInStories.length} 个内置故事');
  }

  /// 获取所有故事
  List<NewYearStory> getAllStories() {
    return _box?.values.toList() ?? [];
  }

  /// 获取所有故事(旧格式,用于兼容现有代码)
  List<Map<String, dynamic>> getAllStoriesLegacy() {
    return getAllStories().map((story) => story.toLegacyMap()).toList();
  }

  /// 根据 ID 获取故事
  NewYearStory? getStoryById(String id) {
    return _box?.get(id);
  }

  /// 添加故事
  Future<void> addStory(NewYearStory story) async {
    await _box?.put(story.id, story);
  }

  /// 更新故事
  Future<void> updateStory(NewYearStory story) async {
    story.updatedAt = DateTime.now();
    await _box?.put(story.id, story);
  }

  /// 删除故事
  Future<void> deleteStory(String id) async {
    await _box?.delete(id);
  }

  /// 批量删除故事
  Future<void> deleteStories(List<String> ids) async {
    await _box?.deleteAll(ids);
  }

  /// 检查故事是否重复(基于标题)
  bool isDuplicate(String title, {String? excludeId}) {
    final stories = getAllStories();

    for (var story in stories) {
      if (story.id == excludeId) continue;

      // 完全匹配或高度相似
      if (story.title == title ||
          _calculateSimilarity(story.title, title) > 0.8) {
        return true;
      }
    }

    return false;
  }

  /// 计算两个字符串的相似度(简单实现)
  double _calculateSimilarity(String s1, String s2) {
    if (s1 == s2) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;

    // 简单的字符匹配相似度
    int matches = 0;
    int minLength = s1.length < s2.length ? s1.length : s2.length;

    for (int i = 0; i < minLength; i++) {
      if (s1[i] == s2[i]) matches++;
    }

    return matches / (s1.length > s2.length ? s1.length : s2.length);
  }

  /// 从 JSON 导入故事
  Future<int> importFromJson(String jsonString) async {
    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      int imported = 0;

      for (var jsonItem in jsonList) {
        final story = NewYearStory.fromJson(jsonItem as Map<String, dynamic>);

        // 检查是否重复
        if (!isDuplicate(story.title, excludeId: story.id)) {
          await addStory(story);
          imported++;
        }
      }

      return imported;
    } catch (e) {
      print('导入故事失败: $e');
      return 0;
    }
  }

  /// 导出所有故事为 JSON
  String exportToJson() {
    final stories = getAllStories();
    final jsonList = stories.map((story) => story.toJson()).toList();
    return jsonEncode(jsonList);
  }

  /// 重置为内置故事
  Future<void> resetToBuiltIn() async {
    await _box?.clear();
    await _importBuiltInStories();
  }

  /// 备份所有故事(包含图片转Base64)
  Future<List<Map<String, dynamic>>> backupStories() async {
    final stories = getAllStories();
    final List<Map<String, dynamic>> list = [];

    for (var story in stories) {
      final json = story.toJson();

      // 处理 pages 中的图片
      try {
        final List<dynamic> pagesRaw = jsonDecode(story.pagesJson);
        final List<Map<String, dynamic>> pages =
            pagesRaw.map((e) => e as Map<String, dynamic>).toList();
        bool hasChanges = false;

        for (var page in pages) {
          final imagePath = page['image'] as String?;
          if (imagePath != null && imagePath.isNotEmpty) {
            // 如果已是 data:image 直接保留
            if (imagePath.startsWith('data:image')) {
              continue;
            }

            // 尝试读取文件转 Base64
            try {
              final file = File(imagePath);
              if (await file.exists()) {
                final bytes = await file.readAsBytes();
                final base64 = base64Encode(bytes);
                page['image'] = 'data:image/png;base64,$base64';
                hasChanges = true;
              } else {
                // 文件不存在，可能是 web 或者 broken path
                // 如果是 http 链接，在 web 端也许可以直接用，但备份最好转 base64
                // 这里简单处理：文件不存在就不动
              }
            } catch (e) {
              print('备份故事图片失败: $e');
            }
          }
        }

        if (hasChanges) {
          json['pages'] = jsonEncode(pages);
        }
      } catch (e) {
        print('处理故事图片备份失败: $e');
      }

      list.add(json);
    }
    return list;
  }

  /// 恢复故事数据(包含 Base64 转图片文件)
  Future<void> restoreStories(List<dynamic> data) async {
    final appDir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory('${appDir.path}/story_images');
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    int imported = 0;
    for (var item in data) {
      if (item is Map<String, dynamic>) {
        try {
          // 还原 pages 中的图片
          if (item['pages'] is String) {
            final List<dynamic> pagesDecoded = jsonDecode(item['pages']);
            final List<Map<String, dynamic>> pages =
                pagesDecoded.map((e) => e as Map<String, dynamic>).toList();
            bool hasChanges = false;

            for (int i = 0; i < pages.length; i++) {
              final page = pages[i];
              final imagePath = page['image'] as String?;

              if (imagePath != null && imagePath.startsWith('data:image')) {
                try {
                  final base64Data = imagePath.split(',')[1];
                  final bytes = base64Decode(base64Data);
                  // 重新生成文件名
                  final fileName = '${item['title']}_${item['id']}_$i.png'
                      .replaceAll(
                          RegExp(r'[<>:"/\\|?*]'), '_'); // Sanitize filename
                  final file = File('${imagesDir.path}/$fileName');
                  await file.writeAsBytes(bytes);
                  page['image'] = file.path;
                  hasChanges = true;
                } catch (e) {
                  print('恢复故事图片失败: $e');
                }
              }
            }

            if (hasChanges) {
              item['pages'] = jsonEncode(pages);
            }
          }

          final story = NewYearStory.fromJson(item);
          await addStory(story);
          imported++;
        } catch (e) {
          print('恢复单个故事失败: $e');
        }
      }
    }
    print('已恢复 $imported 个故事');
  }

  /// 获取故事数量
  int get storyCount => _box?.length ?? 0;
}
