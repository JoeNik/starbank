# AI 生成体验优化实现方案

## 改进点

### 1. 题目生成 (quiz_management_page.dart)
- ✅ 默认 Prompt 预填充到输入框
- ✅ 支持复制默认 Prompt
- 🆕 使用进度对话框展示生成过程
- 🆕 展示 AI 返回的原始 JSON
- 🆕 展示解析后的题目内容

### 2. 故事生成 (story_management_page.dart)
- ✅ 默认 Prompt 可折叠展示
- 🆕 默认 Prompt 预填充到输入框
- 🆕 使用进度对话框展示生成过程
- 🆕 展示每个故事的生成进度
- 🆕 展示图片生成进度

## 实现步骤

### Step 1: 修改题目生成对话框
1. 默认 Prompt 已经预填充 ✅ (代码中已实现)
2. 添加复制按钮到 Prompt 输入框
3. 生成时使用 AIGenerationProgressDialog

### Step 2: 修改故事生成对话框  
1. 将默认 Prompt 预填充到输入框
2. 添加复制按钮
3. 生成时使用 AIGenerationProgressDialog

### Step 3: 修改生成逻辑
在 AIGenerationService 中添加进度回调

## 代码修改位置

1. `quiz_management_page.dart` - _showAIGenerateDialog 方法
   - 添加复制按钮到 TextField
   - 生成时创建进度步骤并显示对话框

2. `story_management_page.dart` - _showAIGenerateDialog 方法
   - 将 ExpansionTile 改为预填充到 TextField
   - 添加复制按钮
   - 生成时创建进度步骤并显示对话框

3. `ai_generation_service.dart`
   - 添加进度回调参数
   - 在关键步骤更新进度
