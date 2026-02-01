# 知识库管理和AI生成功能实现计划

## 目标
为"新年故事听听"和"新年知多少"添加以下功能:
1. 知识库管理:删除/批量删除、编辑内容
2. AI生成:通过LLM接口生成新的题目/故事,避免重复

## 技术方案

### 一、数据模型扩展

#### 1. 故事模型 (NewYearStory)
创建 `lib/models/new_year_story.dart`:
- 使用 Hive 存储
- 字段:id, title, emoji, duration, pages, createdAt, updatedAt
- 支持 JSON 序列化

#### 2. 题目模型 (QuizQuestion)
已存在,需要确保支持完整的 CRUD 操作

### 二、服务层

#### 1. 故事管理服务 (StoryManagementService)
创建 `lib/services/story_management_service.dart`:
- 初始化:从内置数据导入到 Hive
- CRUD 操作:增删改查
- 批量操作:批量删除
- 去重检测:基于 title 或 id

#### 2. 题目管理服务 (QuizManagementService)
创建 `lib/services/quiz_management_service.dart`:
- 类似故事管理服务
- 去重检测:基于 question 文本相似度

#### 3. AI生成服务扩展
扩展现有的 OpenAI 服务:
- 生成故事:根据主题生成新故事
- 生成题目:根据类别生成新题目
- 返回格式化 JSON 数据

### 三、UI 页面

#### 1. 故事管理页面 (StoryManagementPage)
创建 `lib/pages/entertainment/new_year_story/story_management_page.dart`:
- 列表展示所有故事
- 编辑故事(弹窗)
- 删除/批量删除
- AI 生成新故事

#### 2. 题目管理页面 (QuizManagementPage)
已存在 `lib/pages/entertainment/quiz/quiz_management_page.dart`,需要扩展:
- 添加编辑功能
- 添加 AI 生成功能
- 优化批量删除

#### 3. AI生成配置页面
- 设置生成数量(1-3)
- 设置生成主题/类别
- 自定义 prompt

### 四、实现步骤

1. **创建数据模型** (NewYearStory)
2. **创建管理服务** (StoryManagementService, QuizManagementService)
3. **扩展 AI 服务** (添加生成故事和题目的方法)
4. **创建/扩展管理页面** (UI 界面)
5. **集成到主页面** (添加管理入口)
6. **测试和优化**

## 关键技术点

### 1. 去重逻辑
```dart
// 基于标题/问题的相似度检测
bool isDuplicate(String newContent, List<String> existingContents) {
  for (var existing in existingContents) {
    if (similarity(newContent, existing) > 0.8) {
      return true;
    }
  }
  return false;
}
```

### 2. AI Prompt 设计

#### 生成故事 Prompt:
```
请生成一个适合儿童的中国新年相关故事,要求:
1. 故事主题:[用户输入的主题]
2. 包含5-7个页面
3. 每页包含:文本、emoji、TTS文本
4. 至少包含1个互动问题
5. 返回JSON格式,结构如下:
{
  "title": "故事标题",
  "emoji": "🎊",
  "duration": "2分钟",
  "pages": [...]
}
```

#### 生成题目 Prompt:
```
请生成[数量]道关于中国新年的问答题,要求:
1. 类别:[用户选择的类别]
2. 每题包含:问题、emoji、4个选项、正确答案索引、知识点解释
3. 难度适合儿童
4. 返回JSON数组格式
```

### 3. 批量操作优化
- 使用 Checkbox 多选
- 全选/反选功能
- 确认对话框防止误删

## 文件清单

### 新建文件:
1. `lib/models/new_year_story.dart` - 故事模型
2. `lib/models/new_year_story.g.dart` - Hive 生成文件
3. `lib/services/story_management_service.dart` - 故事管理服务
4. `lib/services/quiz_management_service.dart` - 题目管理服务
5. `lib/pages/entertainment/new_year_story/story_management_page.dart` - 故事管理页面
6. `lib/pages/entertainment/new_year_story/story_edit_dialog.dart` - 故事编辑对话框

### 修改文件:
1. `lib/pages/entertainment/quiz/quiz_management_page.dart` - 添加编辑和AI生成
2. `lib/pages/entertainment/new_year_story/new_year_story_page.dart` - 添加管理入口
3. `lib/pages/entertainment/quiz/quiz_page.dart` - 添加管理入口
4. `lib/services/openai_service.dart` - 添加生成方法

## 下一步
开始实现第一步:创建故事数据模型
