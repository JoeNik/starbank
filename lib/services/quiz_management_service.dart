import 'dart:convert';
import 'package:hive/hive.dart';
import '../models/quiz_question.dart';
import '../data/quiz_data.dart';

/// 题目管理服务
class QuizManagementService {
  static const String _boxName = 'quiz_questions';
  static QuizManagementService? _instance;
  Box<QuizQuestion>? _box;

  QuizManagementService._();

  /// 获取单例实例
  static QuizManagementService get instance {
    _instance ??= QuizManagementService._();
    return _instance!;
  }

  /// 初始化服务
  Future<void> init() async {
    if (_box == null || !_box!.isOpen) {
      _box = await Hive.openBox<QuizQuestion>(_boxName);

      // 如果是首次初始化,导入内置题目
      if (_box!.isEmpty) {
        await _importBuiltInQuestions();
      }
    }
  }

  /// 导入内置题目
  Future<void> _importBuiltInQuestions() async {
    final builtInQuestions = QuizData.getAllQuestions();

    for (var questionMap in builtInQuestions) {
      final question = QuizQuestion.fromLegacyMap(questionMap);
      await _box!.put(question.id, question);
    }

    print('已导入 ${builtInQuestions.length} 道内置题目');
  }

  /// 获取所有题目
  List<QuizQuestion> getAllQuestions() {
    return _box?.values.toList() ?? [];
  }

  /// 获取所有题目(旧格式,用于兼容现有代码)
  List<Map<String, dynamic>> getAllQuestionsLegacy() {
    return getAllQuestions().map((q) => q.toJson()).toList();
  }

  /// 根据 ID 获取题目
  QuizQuestion? getQuestionById(String id) {
    return _box?.get(id);
  }

  /// 根据分类获取题目
  List<QuizQuestion> getQuestionsByCategory(String category) {
    return getAllQuestions().where((q) => q.category == category).toList();
  }

  /// 随机获取指定数量的题目
  List<QuizQuestion> getRandomQuestions(int count) {
    final all = getAllQuestions();
    all.shuffle();
    return all.take(count).toList();
  }

  /// 添加题目
  Future<void> addQuestion(QuizQuestion question) async {
    await _box?.put(question.id, question);
  }

  /// 更新题目
  Future<void> updateQuestion(QuizQuestion question) async {
    question.updatedAt = DateTime.now();
    await _box?.put(question.id, question);
  }

  /// 删除题目
  Future<void> deleteQuestion(String id) async {
    await _box?.delete(id);
  }

  /// 批量删除题目
  Future<void> deleteQuestions(List<String> ids) async {
    await _box?.deleteAll(ids);
  }

  /// 检查题目是否重复(基于问题文本)
  bool isDuplicate(String question, {String? excludeId}) {
    final questions = getAllQuestions();

    for (var q in questions) {
      if (q.id == excludeId) continue;

      // 完全匹配或高度相似
      if (q.question == question ||
          _calculateSimilarity(q.question, question) > 0.85) {
        return true;
      }
    }

    return false;
  }

  /// 计算两个字符串的相似度(简单实现)
  double _calculateSimilarity(String s1, String s2) {
    if (s1 == s2) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;

    // 移除标点符号和空格后比较
    String clean1 = s1.replaceAll(RegExp(r'[^\u4e00-\u9fa5a-zA-Z0-9]'), '');
    String clean2 = s2.replaceAll(RegExp(r'[^\u4e00-\u9fa5a-zA-Z0-9]'), '');

    if (clean1 == clean2) return 1.0;

    // 简单的字符匹配相似度
    int matches = 0;
    int minLength =
        clean1.length < clean2.length ? clean1.length : clean2.length;

    for (int i = 0; i < minLength; i++) {
      if (clean1[i] == clean2[i]) matches++;
    }

    return matches /
        (clean1.length > clean2.length ? clean1.length : clean2.length);
  }

  /// 从 JSON 导入题目
  Future<int> importFromJson(String jsonString) async {
    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      int imported = 0;

      for (var jsonItem in jsonList) {
        final question =
            QuizQuestion.fromJson(jsonItem as Map<String, dynamic>);

        // 检查是否重复
        if (!isDuplicate(question.question, excludeId: question.id)) {
          await addQuestion(question);
          imported++;
        }
      }

      return imported;
    } catch (e) {
      print('导入题目失败: $e');
      return 0;
    }
  }

  /// 导出所有题目为 JSON
  String exportToJson() {
    final questions = getAllQuestions();
    final jsonList = questions.map((q) => q.toJson()).toList();
    return jsonEncode(jsonList);
  }

  /// 重置为内置题目
  Future<void> resetToBuiltIn() async {
    await _box?.clear();
    await _importBuiltInQuestions();
  }

  /// 获取题目数量
  int get questionCount => _box?.length ?? 0;

  /// 获取所有分类
  List<String> getAllCategories() {
    final questions = getAllQuestions();
    final categories = questions.map((q) => q.category).toSet().toList();
    categories.sort();
    return categories;
  }
}
