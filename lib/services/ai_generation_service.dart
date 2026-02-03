import 'dart:convert';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import '../models/new_year_story.dart';
import '../models/quiz_question.dart';
import '../models/openai_config.dart';
import 'openai_service.dart';
import 'story_management_service.dart';
import 'quiz_service.dart';

/// AI 生成助手服务
/// 协调 AI 生成和知识库导入
class AIGenerationService {
  final OpenAIService _openAIService = Get.find<OpenAIService>();
  final StoryManagementService _storyService = StoryManagementService.instance;
  final QuizService _quizService = Get.find<QuizService>();

  /// 生成并导入故事
  /// 返回: (成功数量, 跳过数量, 失败数量, 错误信息列表)
  Future<(int, int, int, List<String>)> generateAndImportStories({
    required int count,
    String? theme,
    String? customPrompt,
    OpenAIConfig? textConfig,
    String? textModel,
    OpenAIConfig? imageConfig,
    String? imageModel,
    Function(String step, String message, {Map<String, dynamic>? details})?
        onProgress,
  }) async {
    int successCount = 0;
    int skipCount = 0;
    int failCount = 0;
    List<String> errors = [];

    try {
      // 1. 调用 AI 生成故事文本
      onProgress?.call('text', '正在请求 AI 生成故事文本...');

      final generatedStories = await _openAIService.generateStories(
        count: count,
        theme: theme,
        customPrompt: customPrompt,
        config: textConfig,
        model: textModel,
      );

      onProgress?.call('text_done', '故事文本生成完成', details: {
        'count': generatedStories.length,
        'raw': jsonEncode(generatedStories) // 简单模拟 Raw JSON
      });

      // 2. 如果配置了生图模型,则为每个页面生成图片
      if (imageConfig != null) {
        int totalImages = generatedStories.fold<int>(
            0, (sum, story) => sum + (story['pages'] as List).length);
        int currentImage = 0;

        for (var story in generatedStories) {
          final pages = story['pages'] as List;
          final storyTitle = story['title'] as String? ?? '未命名';

          for (int i = 0; i < pages.length; i++) {
            currentImage++;
            onProgress?.call(
              'image',
              '正在生成图片 ($currentImage/$totalImages)\n$storyTitle - 第 ${i + 1} 页',
            );

            try {
              final page = pages[i] as Map<String, dynamic>;
              final text = page['text'] as String;

              // 构建生图提示词
              final imagePrompt =
                  'Children book illustration, Chinese New Year theme. '
                  'Scene: $text. '
                  'Style: Cute, colorful, warm, flat vector art, simple background, suited for kids.';

              final imageUrl = await _openAIService.generateImage(
                prompt: imagePrompt,
                config: imageConfig,
                model: imageModel,
              );

              // 下载并保存图片
              onProgress?.call(
                'image_download',
                '正在保存图片 ($currentImage/$totalImages)...',
              );

              final imagePath =
                  await _downloadAndSaveImage(imageUrl, '${story['title']}_$i');
              page['image'] = imagePath; // Set image path
            } catch (e) {
              errors.add('为故事 "${story['title']}" 第 ${i + 1} 页生成图片失败: $e');
              // Continue without image
            }
          }
        }
      }

      // 3. 逐个验证和导入
      onProgress?.call('import', '正在验证并导入数据...');

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

      onProgress?.call('done', '生成流程结束');
    } catch (e) {
      errors.add('AI 生成失败: $e');
      failCount = count;
      onProgress?.call('error', '生成失败: $e');
    }

    return (successCount, skipCount, failCount, errors);
  }

  /// 生成并导入题目
  /// 返回: (成功数量, 跳过数量, 失败数量, 错误信息列表)
  Future<(int, int, int, List<String>)> generateAndImportQuestions({
    required int count,
    String? category,
    String? customPrompt,
    OpenAIConfig? config,
    String? model,
    Function(String step, String message, {Map<String, dynamic>? details})?
        onProgress,
  }) async {
    int successCount = 0;
    int skipCount = 0;
    int failCount = 0;
    List<String> errors = [];
    List<QuizQuestion> importedQuestions = [];

    try {
      // 1. 调用 AI 生成题目
      onProgress?.call('text', '正在请求 AI 生成题目文本...');

      final generatedQuestions = await _openAIService.generateQuizQuestions(
        count: count,
        category: category,
        customPrompt: customPrompt,
        config: config,
        model: model,
      );

      onProgress?.call('text_done', '题目文本生成完成', details: {
        'count': generatedQuestions.length,
        'raw': jsonEncode(generatedQuestions)
      });

      // 2. 逐个验证和导入
      onProgress?.call('import', '正在验证并导入数据...');

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
          importedQuestions.add(quizQuestion);
          successCount++;
        } catch (e) {
          errors.add('导入题目失败: $e');
          failCount++;
        }
      }

      onProgress?.call('import_done', '题目导入完成');

      // 3. 为导入的题目生成图片
      if (importedQuestions.isNotEmpty) {
        onProgress?.call('image_start', '开始生成图片...', details: {
          'total': importedQuestions.length,
        });

        final quizConfig = _quizService.config.value;
        if (quizConfig != null && quizConfig.enableImageGen) {
          final imageGenConfig = _openAIService.configs
              .firstWhereOrNull((c) => c.id == quizConfig.imageGenConfigId);

          if (imageGenConfig != null) {
            int imageSuccess = 0;
            int imageFail = 0;

            for (int i = 0; i < importedQuestions.length; i++) {
              final question = importedQuestions[i];

              onProgress?.call('image_progress',
                  '正在为题目 ${i + 1}/${importedQuestions.length} 生成图片...',
                  details: {
                    'current': i + 1,
                    'total': importedQuestions.length,
                    'question': question.question,
                  });

              try {
                // 尝试生成图片
                await _quizService.generateImageForQuestion(question,
                    imageCount: 1);
                imageSuccess++;

                onProgress?.call(
                    'image_item_success', '题目 "${question.question}" 图片生成成功',
                    details: {
                      'questionId': question.id,
                    });
              } catch (e) {
                imageFail++;
                // 图片生成失败，使用 emoji 替代（已在 QuizQuestion 中有默认 emoji）
                errors.add('题目 "${question.question}" 图片生成失败: $e，将使用 emoji 替代');

                onProgress?.call('image_item_fail',
                    '题目 "${question.question}" 图片生成失败，使用 emoji',
                    details: {
                      'questionId': question.id,
                      'error': e.toString(),
                    });
              }

              // API 调用频率控制
              if (i < importedQuestions.length - 1) {
                await Future.delayed(const Duration(seconds: 2));
              }
            }

            onProgress?.call('image_done', '图片生成完成', details: {
              'success': imageSuccess,
              'fail': imageFail,
            });
          } else {
            onProgress?.call('image_skip', '未配置生图AI，跳过图片生成');
          }
        } else {
          onProgress?.call('image_skip', '未启用图片生成功能');
        }
      }

      onProgress?.call('done', '生成流程结束');
    } catch (e) {
      errors.add('AI 生成失败: $e');
      failCount = count;
      onProgress?.call('error', '生成失败: $e');
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

  /// 下载并转换为Base64 (保存到数据库)
  Future<String> _downloadAndSaveImage(
      String urlOrDataUri, String fileNamePrefix) async {
    try {
      // Base64 格式直接返回
      if (urlOrDataUri.startsWith('data:image')) {
        return urlOrDataUri;
      }

      // URL 格式: 下载并转 Base64
      print('📥 从URL下载图片并转Base64: $urlOrDataUri');
      final response = await http.get(Uri.parse(urlOrDataUri));
      if (response.statusCode != 200) {
        throw Exception('下载图片失败: ${response.statusCode}');
      }

      final base64String = base64Encode(response.bodyBytes);
      return 'data:image/png;base64,$base64String';
    } catch (e) {
      print('下载转变图片失败: $e');
      rethrow;
    }
  }
}
