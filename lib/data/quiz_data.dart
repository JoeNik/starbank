import 'quiz_data_extended.dart';

/// 新年知识问答题库
/// 现已扩展到100道题
class QuizData {
  /// 问答题目列表
  static List<Map<String, dynamic>> getAllQuestions() {
    return QuizDataExtended.getExtendedQuestions();
  }

  /// 随机获取指定数量的题目
  static List<Map<String, dynamic>> getRandomQuestions(int count) {
    final all = getAllQuestions();
    all.shuffle();
    return all.take(count).toList();
  }

  /// 按分类获取题目
  static List<Map<String, dynamic>> getQuestionsByCategory(String category) {
    return getAllQuestions().where((q) => q['category'] == category).toList();
  }
}
