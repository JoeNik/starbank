# 新年问答功能补充实施说明

## ✅ 已完成的功能

### 1. 数据模型
- ✅ `QuizConfig` - 问答配置模型 (typeId: 20)
- ✅ `QuizQuestion` - 问答题目模型 (typeId: 21)

### 2. 服务层
- ✅ `QuizService` - 问答服务,管理题库和AI生成
  - 题库导入导出
  - AI 图片生成(单个/批量)
  - 图片缓存管理
  - 数据备份恢复接口

### 3. 页面
- ✅ `QuizAISettingsPage` - AI 设置页面
- ✅ `QuizManagementPage` - 题库管理页面

## 📝 待完成的集成工作

### 1. 在 main.dart 中注册服务

在 `main.dart` 的服务初始化部分添加:

```dart
// 初始化问答服务
await Get.putAsync(() => QuizService().init());
```

### 2. 更新 WebDAV 备份服务

在 `webdav_service.dart` 的 `backupData()` 方法中添加(约第 238 行之后):

```dart
// 备份新年问答数据
try {
  if (Get.isRegistered<QuizService>()) {
    final quizService = Get.find<QuizService>();
    backupData['quizData'] = quizService.exportData();
  }
} catch (e) {
  print('备份问答数据失败: $e');
}
```

在 `restoreData()` 方法中添加(约第 617 行之前):

```dart
// 恢复新年问答数据
if (backupData['quizData'] != null) {
  try {
    if (Get.isRegistered<QuizService>()) {
      final quizService = Get.find<QuizService>();
      await quizService.importData(backupData['quizData'] as Map<String, dynamic>);
    }
  } catch (e) {
    print('恢复问答数据失败: $e');
    ToastUtils.showWarning('问答数据恢复失败: $e');
  }
}
```

在 `_checkAdapters()` 方法中添加:

```dart
// QuizConfig (20)
if (!Hive.isAdapterRegistered(20)) {
  Hive.registerAdapter(QuizConfigAdapter());
}
// QuizQuestion (21)
if (!Hive.isAdapterRegistered(21)) {
  Hive.registerAdapter(QuizQuestionAdapter());
}
```

### 3. 更新问答页面使用新服务

修改 `quiz_page.dart`:

1. 添加导入:
```dart
import '../../services/quiz_service.dart';
import '../../models/quiz_question.dart';
```

2. 在页面顶部添加:
```dart
final QuizService _quizService = Get.find<QuizService>();
```

3. 在 initState 中使用服务加载题目:
```dart
_questions = _quizService.questions.take(10).toList();
```

4. 添加题库管理入口:
在 AppBar 的 actions 中添加:
```dart
IconButton(
  onPressed: () => Get.to(() => const QuizManagementPage()),
  icon: const Icon(Icons.settings),
  tooltip: '题库管理',
),
```

5. 显示题目图片:
在 `_buildQuestionCard` 方法中,如果题目有图片,显示图片而不是 emoji:
```dart
// 图片或 Emoji 图标
if (question.hasImage && question.imagePath != null)
  ClipRRect(
    borderRadius: BorderRadius.circular(16.r),
    child: Image.file(
      File(question.imagePath!),
      width: 200.w,
      height: 200.w,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Text(
          question.emoji,
          style: TextStyle(fontSize: 64.sp),
        );
      },
    ),
  )
else
  Text(
    question.emoji,
    style: TextStyle(fontSize: 64.sp),
  ),
```

### 4. 添加路由

在路由配置中添加:
```dart
GetPage(name: '/quiz_management', page: () => const QuizManagementPage()),
GetPage(name: '/quiz_ai_settings', page: () => const QuizAISettingsPage()),
```

## 🎯 功能特点总结

### AI 配置
- 支持配置独立的生图 AI 和问答 AI
- 自定义提示词模板
- 功能开关控制

### 题库管理
- 导入外部 JSON 题库(支持 URL)
- 导出题库为 JSON
- 恢复默认题库
- 清空题库

### 图片生成
- 单个题目生成图片
- 批量生成(带进度显示)
- API 调用频率控制(3秒间隔)
- 图片本地缓存
- 缓存大小统计
- 清空缓存功能

### 数据备份
- 集成到 WebDAV 备份系统
- 题库和配置一起备份
- 支持恢复

## 📋 使用流程

1. **配置 AI**
   - 进入娱乐乐园 → 新年知多少 → 设置 → 题库管理 → AI 设置
   - 选择生图 AI 和问答 AI
   - 可自定义提示词

2. **导入题库**
   - 题库管理 → 导入题库
   - 粘贴 JSON 或输入 URL

3. **生成图片**
   - 单个生成:点击题目旁的菜单 → 生成图片
   - 批量生成:题库管理 → 批量生成

4. **备份恢复**
   - 使用 WebDAV 备份功能自动包含问答数据

## 🔧 注意事项

1. **API 限制**: 批量生成时每次间隔 3 秒,避免超限
2. **图片缓存**: 图片保存在应用文档目录,可以清空释放空间
3. **题库格式**: 支持新旧两种格式,兼容性好
4. **生成状态**: 题目有生成中、成功、失败三种状态

## 📊 数据格式

### 题库 JSON 格式
```json
[
  {
    "id": "unique_id",
    "question": "问题文本",
    "emoji": "🧧",
    "options": ["选项1", "选项2", "选项3", "选项4"],
    "correctIndex": 0,
    "explanation": "知识点解释",
    "category": "分类",
    "imagePath": "/path/to/image.png",
    "imageStatus": "success",
    "createdAt": "2026-02-01T22:00:00.000Z",
    "updatedAt": "2026-02-01T22:00:00.000Z"
  }
]
```

### 简化格式(兼容)
```json
[
  {
    "question": "问题",
    "emoji": "🧧",
    "options": ["A", "B", "C", "D"],
    "correctIndex": 0,
    "explanation": "解释",
    "category": "分类"
  }
]
```

---

**实施完成后,新年问答功能将具备完整的 AI 辅助、题库管理和数据备份能力!** 🎉
