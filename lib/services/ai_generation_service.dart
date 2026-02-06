import 'dart:convert';

import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import '../models/new_year_story.dart';
import '../models/quiz_question.dart';
import '../models/openai_config.dart';
import '../widgets/ai_generation_progress_dialog.dart';
import 'openai_service.dart';
import 'story_management_service.dart';
import 'quiz_service.dart';

/// AI 生成助手服务
/// 协调 AI 生成和知识库导入
class AIGenerationService extends GetxService {
  final OpenAIService _openAIService = Get.find<OpenAIService>();
  final StoryManagementService _storyService = StoryManagementService.instance;
  final QuizService _quizService = Get.find<QuizService>();

  /// 全局任务状态
  final RxBool isTaskRunning = false.obs;
  final RxList<GenerationStep> taskSteps = <GenerationStep>[].obs;

  /// 开始故事生成任务 (包含文本和可选插图)
  Future<void> startStoryGenerationTask({
    required int count,
    String? theme,
    String? customPrompt,
    OpenAIConfig? textConfig,
    String? textModel,
    OpenAIConfig? imageConfig,
    String? imageModel,
    required bool enableImageGen,
  }) async {
    if (isTaskRunning.value) return;

    isTaskRunning.value = true;
    taskSteps.clear();
    taskSteps.addAll([
      GenerationStep(
        title: '生成故事文本',
        description: '正在连接 AI 生成故事内容...',
        status: StepStatus.running,
      ),
      if (enableImageGen)
        GenerationStep(
          title: '生成插图',
          description: '等待文本生成完成...',
          status: StepStatus.pending,
        ),
      GenerationStep(
        title: '验证与保存',
        description: '等待生成完成...',
        status: StepStatus.pending,
      ),
    ]);

    try {
      final result = await generateAndImportStories(
        count: count,
        theme: theme,
        customPrompt: customPrompt,
        textConfig: textConfig,
        textModel: textModel,
        imageConfig: imageConfig,
        imageModel: imageModel,
        onProgress: (step, message, {Map<String, dynamic>? details}) {
          if (taskSteps.isEmpty) return;
          _updateStoryTaskProgress(step, message, enableImageGen, details);
        },
      );

      // 添加结果汇总
      final (success, skip, fail, errors) = result;
      final summary = '生成完成\n成功: $success\n跳过: $skip\n失败: $fail';

      if (fail > 0 || errors.isNotEmpty) {
        taskSteps.add(GenerationStep(
          title: '生成结果',
          status: StepStatus.error,
          description: summary,
          details: errors.join('\n'),
        ));
      } else {
        taskSteps.add(GenerationStep(
          title: '生成结果',
          status: StepStatus.success,
          description: summary,
        ));
      }
    } catch (e) {
      taskSteps.add(GenerationStep(
        title: '发生异常',
        status: StepStatus.error,
        error: e.toString(),
      ));
    } finally {
      isTaskRunning.value = false;
    }
  }

  /// 启动批量插图生成任务 (为现有故事)
  Future<void> startBatchImageGenerationTask({
    required List<NewYearStory> stories,
    required OpenAIConfig config,
    String? model,
  }) async {
    if (isTaskRunning.value) return;

    isTaskRunning.value = true;
    taskSteps.clear();
    taskSteps.add(GenerationStep(
      title: '生成插图',
      description: '准备为 ${stories.length} 个故事生成插图...',
      status: StepStatus.running,
    ));

    int successCount = 0;
    int failCount = 0;
    List<String> errors = [];

    try {
      int currentStoryIndex = 0;
      for (final story in stories) {
        currentStoryIndex++;

        // 解析页面数据
        List<Map<String, dynamic>> pages = [];
        try {
          final dynamic decoded = jsonDecode(story.pagesJson);
          if (decoded is List) {
            pages = decoded.map((e) => e as Map<String, dynamic>).toList();
          }
        } catch (e) {
          errors.add('故事 "${story.title}" 数据解析失败: $e');
          failCount++;
          continue;
        }

        int totalImages = pages.length;
        if (totalImages == 0) {
          errors.add('故事 "${story.title}" 没有页面');
          failCount++;
          continue;
        }

        for (int i = 0; i < pages.length; i++) {
          final page = pages[i];
          final text = page['text'] as String? ?? '';

          taskSteps[0].update(
            status: StepStatus.running,
            description:
                '[$currentStoryIndex/${stories.length}] 正在生成 "${story.title}"\n'
                '进度: ${i + 1}/$totalImages 页',
            details: '场景: $text',
          );

          try {
            // 生成提示词
            final imagePrompt =
                'Children book illustration, Chinese New Year theme. '
                'Scene: $text. '
                'Style: Cute, colorful, warm, flat vector art, simple background, suited for kids.';

            // 调用 API
            final imageUrl = await _openAIService.generateImage(
              prompt: imagePrompt,
              config: config,
              model: model,
            );

            // Sanitize title for filename
            final safeTitle = story.title
                .replaceAll(
                    RegExp(r'[<>:"/\\|?*]'), '_') // Windows invalid chars
                .replaceAll(RegExp(r'\s+'), '_');

            // 保存图片
            final imagePath = await _downloadAndSaveImage(imageUrl,
                '${safeTitle}_${DateTime.now().millisecondsSinceEpoch}_$i');

            // 更新页面数据
            page['image'] = imagePath;
          } catch (e) {
            errors.add('故事 "${story.title}" 第 ${i + 1} 页生成失败: $e');
          }

          // 频率控制
          if (i < pages.length - 1) {
            await Future.delayed(const Duration(seconds: 1));
          }
        }

        // 保存故事更新
        story.pagesJson = jsonEncode(pages);
        story.updatedAt = DateTime.now();
        await story.save(); // 确保持久化

        successCount++;

        // 故事间延迟
        if (currentStoryIndex < stories.length) {
          await Future.delayed(const Duration(seconds: 1));
        }
      }

      taskSteps[0].setSuccess(description: '生成任务完成');
      taskSteps.add(GenerationStep(
        title: '生成结果',
        status: failCount > 0 ? StepStatus.error : StepStatus.success,
        description: '成功: $successCount, 失败: $failCount',
        details: errors.join('\n'),
      ));
    } catch (e) {
      taskSteps[0].setError('任务异常中止: $e');
    } finally {
      isTaskRunning.value = false;
    }
  }

  /// 开始题目生成任务
  Future<void> startQuizGenerationTask({
    required int count,
    String? category,
    String? customPrompt,
    OpenAIConfig? config,
    String? model,
  }) async {
    if (isTaskRunning.value) return;

    isTaskRunning.value = true;
    taskSteps.clear();
    taskSteps.addAll([
      GenerationStep(
        title: '生成题目',
        description: '正在连接 AI 生成题目...',
        status: StepStatus.running,
      ),
      GenerationStep(
        title: '验证与导入',
        description: '等待生成完成...',
        status: StepStatus.pending,
      ),
      GenerationStep(
        title: '生成图片',
        description: '等待题目导入完成...',
        status: StepStatus.pending,
      ),
    ]);

    try {
      final result = await generateAndImportQuestions(
        count: count,
        category: category,
        customPrompt: customPrompt,
        config: config,
        model: model,
        onProgress: (step, message, {Map<String, dynamic>? details}) {
          if (taskSteps.isEmpty) return;
          _updateQuizTaskProgress(step, message, details);
        },
      );

      final (success, skip, fail, errors) = result;
      final summary = '生成完成\n成功: $success\n跳过: $skip\n失败: $fail';

      if (fail > 0 || errors.isNotEmpty) {
        taskSteps.add(GenerationStep(
          title: '生成结果',
          status: StepStatus.error,
          description: summary,
          details: errors.join('\n'),
        ));
      } else {
        taskSteps.add(GenerationStep(
          title: '生成结果',
          status: StepStatus.success,
          description: summary,
        ));
      }
    } catch (e) {
      taskSteps.add(GenerationStep(
        title: '发生异常',
        status: StepStatus.error,
        error: e.toString(),
      ));
    } finally {
      isTaskRunning.value = false;
    }
  }

  /// 启动批量题目插图生成任务
  Future<void> startBatchQuizImageGenerationTask({
    required List<QuizQuestion> questions,
    required OpenAIConfig imageGenConfig,
    String? imageGenModel,
    required String promptTemplate,
  }) async {
    if (isTaskRunning.value) return;

    isTaskRunning.value = true;
    taskSteps.clear();
    taskSteps.add(GenerationStep(
      title: '生成插图',
      description: '准备为 ${questions.length} 个题目生成插图...',
      status: StepStatus.running,
    ));

    int successCount = 0;
    int failCount = 0;
    List<String> errors = [];

    try {
      // 预先设置状态
      for (var q in questions) {
        q.imageStatus = 'generating';
        await q.save();
      }
      _quizService.questions.refresh();

      for (int i = 0; i < questions.length; i++) {
        final question = questions[i];

        taskSteps[0].update(
          status: StepStatus.running,
          description: '[${i + 1}/${questions.length}] 正在为题目生成图片...',
          details: '题目: ${question.question}',
        );

        try {
          // 1. 生成提示词 (Replicating logic from QuizManagementPage)
          final knowledge =
              '${question.question}\n答案: ${question.options[question.correctIndex]}\n解释: ${question.explanation}';
          final userPrompt =
              promptTemplate.replaceAll('{knowledge}', knowledge);

          // 调用 Chat API 生成 SD/DALL-E 提示词
          final imagePrompt = await _openAIService.chat(
            systemPrompt:
                '你是一个专业的儿童插画提示词生成专家。请根据用户提供的内容生成适合 DALL-E 或 Stable Diffusion 的英文提示词。\n\n'
                '严格要求:\n'
                '1. 必须使用可爱、卡通、儿童插画风格\n'
                '2. 色彩明亮温暖,画面简洁清晰\n'
                '3. 严格禁止任何暴力、恐怖、成人或不适合儿童的内容\n'
                '4. 使用圆润可爱的造型,避免尖锐或恐怖元素\n'
                '5. 符合中国传统新年文化,展现节日喜庆氛围\n'
                '6. 适合3-8岁儿童观看\n\n'
                '只返回英文提示词本身,不要有其他说明。提示词中应包含: cute, cartoon, children illustration, colorful, warm, simple, Chinese New Year 等关键词。',
            userMessage: userPrompt,
            config: imageGenConfig,
          );

          // 2. 生成图片
          final imageUrls = await _openAIService.generateImages(
            prompt: imagePrompt,
            n: 1,
            config: imageGenConfig,
            model: imageGenModel,
          );

          if (imageUrls.isNotEmpty) {
            // 3. 保存并下载 (如果返回的是 URL)
            final imagePath = await _downloadAndSaveImage(
                imageUrls.first, 'quiz_${question.id}');

            question.imagePath = imagePath;
            question.imageStatus = 'success';
            question.imageError = null;
            question.updatedAt = DateTime.now();
            await question.save();
            successCount++;
          } else {
            throw Exception('未能生成图片');
          }
        } catch (e) {
          failCount++;
          errors.add('题目 "${question.question}" 生成失败: $e');

          question.imageStatus = 'failed';
          question.imageError = e.toString();
          question.updatedAt = DateTime.now();
          await question.save();
        }

        // 刷新 Quiz Service 列表
        _quizService.questions.refresh();

        // API 频率控制
        if (i < questions.length - 1) {
          await Future.delayed(const Duration(seconds: 2));
        }
      }

      taskSteps[0].setSuccess(description: '批量生成完成');
      taskSteps.add(GenerationStep(
        title: '生成结果',
        status: failCount > 0 ? StepStatus.error : StepStatus.success,
        description: '成功: $successCount, 失败: $failCount',
        details: errors.join('\n'),
      ));
    } catch (e) {
      taskSteps[0].setError('任务异常中止: $e');
    } finally {
      isTaskRunning.value = false;
    }
  }

  void _updateQuizTaskProgress(
      String step, String message, Map<String, dynamic>? details) {
    switch (step) {
      case 'text':
        taskSteps[0].setRunning(description: message);
        break;
      case 'text_done':
        taskSteps[0].setSuccess(
            description: message, details: details?['raw']?.toString());
        if (taskSteps.length > 1) {
          taskSteps[1].setRunning(description: '准备导入...');
        }
        break;
      case 'import':
        if (taskSteps.length > 1) {
          taskSteps[1].setRunning(description: message);
        }
        break;
      case 'import_done':
        if (taskSteps.length > 1) {
          taskSteps[1].setSuccess(description: message);
        }
        if (taskSteps.length > 2) {
          taskSteps[2].setRunning(description: '准备生成图片...');
        }
        break;
      case 'image_start':
        if (taskSteps.length > 2) {
          taskSteps[2].setRunning(
              description: '开始生成图片 (共 ${details?['total']} 个题目)...');
        }
        break;
      case 'image_progress':
        if (taskSteps.length > 2) {
          final current = details?['current'] ?? 0;
          final total = details?['total'] ?? 0;
          final question = details?['question'] ?? '';
          taskSteps[2].update(
              status: StepStatus.running,
              description: '[$current/$total] 正在为题目生成图片...',
              details: '题目: $question');
        }
        break;
      case 'image_item_success':
        // Do nothing to status, just progress
        break;
      case 'image_item_fail':
        if (taskSteps.length > 2) {
          final currentDetails = taskSteps[2].details.value;
          final error = details?['error'] ?? '';
          taskSteps[2].update(details: '$currentDetails\n失败: $error');
        }
        break;
      case 'image_done':
        if (taskSteps.length > 2) {
          final imageSuccess = details?['success'] ?? 0;
          final imageFail = details?['fail'] ?? 0;
          taskSteps[2].setSuccess(
              description: '图片生成完成 (成功: $imageSuccess, 失败: $imageFail)');
        }
        break;
      case 'image_skip':
        if (taskSteps.length > 2) {
          taskSteps[2].setSuccess(description: message);
        }
        break;
      case 'done':
        // All done
        break;
      case 'error':
        final current = taskSteps.firstWhere(
            (s) => s.status.value == StepStatus.running,
            orElse: () => taskSteps.last);
        current.setError(message);
        break;
    }
  }

  void _updateStoryTaskProgress(String step, String message,
      bool enableImageGen, Map<String, dynamic>? details) {
    switch (step) {
      case 'text':
        taskSteps[0].setRunning(description: message);
        break;
      case 'text_done':
        // 尝试解析生成的内容并展示
        String contentPreview = details?['raw']?.toString() ?? '';
        try {
          final raw = details?['raw'];
          if (raw != null) {
            final List<dynamic> list = jsonDecode(raw.toString());
            final buffer = StringBuffer();
            for (var i = 0; i < list.length; i++) {
              final story = list[i];
              buffer.writeln('${i + 1}. ${story['title']}');
              buffer.writeln(
                  '   时长: ${story['duration']} | 页数: ${(story['pages'] as List).length}');
              // Extract first page text as preview
              final pages = story['pages'] as List;
              if (pages.isNotEmpty) {
                buffer.writeln('   简介: ${pages[0]['text']}...');
              }
              buffer.writeln('');
            }
            contentPreview = buffer.toString();
          }
        } catch (e) {
          // Keep raw if parse error
        }

        taskSteps[0].setSuccess(
            description: '故事文本生成完成 (${details?['count']}个)',
            details: contentPreview);

        // 如果有图片生成，开启第二步
        if (enableImageGen && taskSteps.length > 2) {
          taskSteps[1].setRunning(description: '准备生成插图...');
        } else {
          // 否则直接跳到最后一步
          taskSteps.last.setRunning(description: '正在保存数据...');
        }
        break;
      case 'image':
        if (enableImageGen && taskSteps.length > 2) {
          taskSteps[1].setRunning(description: message);
        }
        break;
      case 'image_download':
        if (enableImageGen && taskSteps.length > 2) {
          taskSteps[1].setRunning(description: message);
        }
        break;
      case 'import':
        // 如果有图片步，先完成它
        if (enableImageGen && taskSteps.length > 2) {
          taskSteps[1].setSuccess(description: '插图生成完成');
        }
        taskSteps.last.setRunning(description: message);
        break;
      case 'done':
        taskSteps.last.setSuccess(description: '流程结束');
        break;
      case 'error':
        // 找到当前正在运行的步骤报错
        final currentStep = taskSteps.firstWhere(
          (s) => s.status.value == StepStatus.running,
          orElse: () => taskSteps.last,
        );
        currentStep.setError(message);
        break;
    }
  }

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
