import 'package:get/get.dart';
import '../models/new_year_story.dart';
import '../models/quiz_question.dart';
import 'openai_service.dart';
import 'story_management_service.dart';
import 'quiz_management_service.dart';

/// AI 生成助手服务
/// 协调 AI 生成和知识库导入
class AIGenerationService {
  final OpenAIService _openAIService = Get.find<OpenAIService>();
  final StoryManagementService _storyService = StoryManagementService.instance;
  final QuizManagementService _quizService = QuizManagementService.instance;

  /// 生成并导入故事
  /// 返回: (成功数量, 跳过数量, 失败数量, 错误信息列表)
  Future<(int, int, int, List<String>)> generateAndImportStories({
    required int count,
    String? theme,
    String? customPrompt,
  }) async {
    int successCount = 0;
    int skipCount = 0;
    int failCount = 0;
    List<String> errors = [];

    try {
      // 调用 AI 生成故事
      final generatedStories = await _openAIService.generateStories(
        count: count,
        theme: theme,
        customPrompt: customPrompt,
      );

      // 逐个验证和导入
      for (var storyMap in generatedStories) {
        try {
          // 验证格式
          if (!_openAIService.validateStoryFormat(storyMap)) {
            errors.add('故事 "${storyMap['title'] ?? '未知'}" 格式不正确');
            failCount++;
            continue;
          }

          // 检查重复
          final title = storyMap['title'] as String;
          if (_storyService.isDuplicate(title)) {
            errors.add('故事 "$title" 已存在,跳过导入');
            skipCount++;
            continue;
          }

          // 转换并保存
          final story = NewYearStory.fromLegacyMap(storyMap);
          await _storyService.addStory(story);
          successCount++;
        } catch (e) {
          errors.add('导入故事失败: $e');
          failCount++;
        }
      }
    } catch (e) {
      errors.add('AI 生成失败: $e');
      failCount = count;
    }

    return (successCount, skipCount, failCount, errors);
  }

  /// 生成并导入题目
  /// 返回: (成功数量, 跳过数量, 失败数量, 错误信息列表)
  Future<(int, int, int, List<String>)> generateAndImportQuestions({
    required int count,
    String? category,
    String? customPrompt,
  }) async {
    int successCount = 0;
    int skipCount = 0;
    int failCount = 0;
    List<String> errors = [];

    try {
      // 调用 AI 生成题目
      final generatedQuestions = await _openAIService.generateQuizQuestions(
        count: count,
        category: category,
        customPrompt: customPrompt,
      );

      // 逐个验证和导入
      for (var questionMap in generatedQuestions) {
        try {
          // 验证格式
          if (!_openAIService.validateQuestionFormat(questionMap)) {
            errors.add('题目 "${questionMap['question'] ?? '未知'}" 格式不正确');
            failCount++;
            continue;
          }

          // 检查重复
          final question = questionMap['question'] as String;
          if (_quizService.isDuplicate(question)) {
            errors.add('题目 "$question" 已存在,跳过导入');
            skipCount++;
            continue;
          }

          // 转换并保存
          final quizQuestion = QuizQuestion.fromJson(questionMap);
          await _quizService.addQuestion(quizQuestion);
          successCount++;
        } catch (e) {
          errors.add('导入题目失败: $e');
          failCount++;
        }
      }
    } catch (e) {
      errors.add('AI 生成失败: $e');
      failCount = count;
    }

    return (successCount, skipCount, failCount, errors);
  }

  /// 批量生成故事(支持多轮生成)
  /// [totalCount] 总共要生成的数量
  /// [batchSize] 每批生成数量(1-3)
  Future<(int, int, int, List<String>)> batchGenerateStories({
    required int totalCount,
    int batchSize = 3,
    String? theme,
    String? customPrompt,
    Function(int current, int total)? onProgress,
  }) async {
    int totalSuccess = 0;
    int totalSkip = 0;
    int totalFail = 0;
    List<String> allErrors = [];

    int remaining = totalCount;
    int current = 0;

    while (remaining > 0) {
      final count = remaining > batchSize ? batchSize : remaining;

      onProgress?.call(current, totalCount);

      final (success, skip, fail, errors) = await generateAndImportStories(
        count: count,
        theme: theme,
        customPrompt: customPrompt,
      );

      totalSuccess += success;
      totalSkip += skip;
      totalFail += fail;
      allErrors.addAll(errors);

      current += count;
      remaining -= count;

      // 避免请求过快
      if (remaining > 0) {
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    onProgress?.call(totalCount, totalCount);

    return (totalSuccess, totalSkip, totalFail, allErrors);
  }

  /// 批量生成题目(支持多轮生成)
  Future<(int, int, int, List<String>)> batchGenerateQuestions({
    required int totalCount,
    int batchSize = 3,
    String? category,
    String? customPrompt,
    Function(int current, int total)? onProgress,
  }) async {
    int totalSuccess = 0;
    int totalSkip = 0;
    int totalFail = 0;
    List<String> allErrors = [];

    int remaining = totalCount;
    int current = 0;

    while (remaining > 0) {
      final count = remaining > batchSize ? batchSize : remaining;

      onProgress?.call(current, totalCount);

      final (success, skip, fail, errors) = await generateAndImportQuestions(
        count: count,
        category: category,
        customPrompt: customPrompt,
      );

      totalSuccess += success;
      totalSkip += skip;
      totalFail += fail;
      allErrors.addAll(errors);

      current += count;
      remaining -= count;

      // 避免请求过快
      if (remaining > 0) {
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    onProgress?.call(totalCount, totalCount);

    return (totalSuccess, totalSkip, totalFail, allErrors);
  }
}
