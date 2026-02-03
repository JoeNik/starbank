import 'quiz_data_extended.dart';

/// 新年知识问答题库
/// 现已扩展到100道题
class QuizData {
  /// 问答题目列表
  static List<Map<String, dynamic>> getAllQuestions() {
    final questions = QuizDataExtended.getExtendedQuestions();

    // 随机打乱选项顺序
    for (var q in questions) {
      final options = List<String>.from(q['options']);
      final correctOption = options[q['correctIndex']]; // 获取正确答案文本

      options.shuffle(); // 打乱选项

      // 重新找到正确答案的索引
      final newCorrectIndex = options.indexOf(correctOption);

      q['options'] = options;
      q['correctIndex'] = newCorrectIndex;
    }

    return questions;
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
