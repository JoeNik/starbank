# 宝宝健康记录模块实现计划

## 功能概述
1. 调整导航栏：移除设置入口，新增"记录"模块
2. 设置入口移到主页右上角
3. 新增 OpenAI 设置页面
4. 新增便便记录功能（含 AI 分析）

## 任务分解

### Phase 1: 导航栏和设置入口调整 ✅
- [x] 1.1 修改 main.dart，导航栏从5个变为4个（实际仍是5个，替换了设置为记录）
- [x] 1.2 移除"设置"导航项，新增"记录"导航项
- [x] 1.3 主页面右上角添加设置图标入口
- [x] 1.4 创建记录模块入口页面 RecordPage

### Phase 2: OpenAI 设置功能 ✅
- [x] 2.1 创建 OpenAI 配置数据模型 (openai_config.dart)
- [x] 2.2 创建 OpenAI 设置页面 (openai_settings_page.dart)
- [x] 2.3 创建 OpenAI 服务 (openai_service.dart)
- [x] 2.4 设置页面添加 OpenAI 设置入口
- [ ] 2.5 OpenAI 配置支持备份/恢复 (待完善)

### Phase 3: 便便记录功能 ✅
- [x] 3.1 创建便便记录数据模型 (poop_record.dart)
- [x] 3.2 创建智能体配置（集成在 AI 分析页面）
- [x] 3.3 创建便便记录页面 (poop_record_page.dart)
  - 日历视图展示
  - 快速添加记录
  - 记录类型和颜色选择
- [x] 3.4 创建 AI 分析功能 (poop_ai_page.dart)
  - 选择时间范围
  - 自定义 prompt
  - AI 分析结果展示
- [x] 3.5 历史对话记录
- [ ] 3.6 便便数据支持备份/恢复 (待完善)

### Phase 4: 数据备份恢复增强 (后续版本)
- [ ] 4.1 扩展 WebDAV 备份，包含新增数据
- [ ] 4.2 确保所有新数据模型支持序列化

### Phase 5: 测试和发布 ✅
- [x] 5.1 代码编译通过
- [x] 5.2 更新版本号为 2.0.0+22
- [x] 5.3 提交代码

## 已创建的文件

### 数据模型
- `lib/models/poop_record.dart` - 便便记录
- `lib/models/poop_record.g.dart` - Hive 适配器
- `lib/models/ai_chat.dart` - AI 对话记录
- `lib/models/ai_chat.g.dart` - Hive 适配器
- `lib/models/openai_config.dart` - OpenAI 配置
- `lib/models/openai_config.g.dart` - Hive 适配器

### 服务
- `lib/services/openai_service.dart` - OpenAI API 服务

### 页面
- `lib/pages/record_page.dart` - 记录模块入口
- `lib/pages/poop/poop_record_page.dart` - 便便记录主页
- `lib/pages/poop/poop_ai_page.dart` - AI 分析页面
- `lib/pages/openai_settings_page.dart` - OpenAI 设置

### 修改的文件
- `lib/main.dart` - 导航栏调整，初始化 OpenAI 服务
- `lib/pages/home_page.dart` - 添加设置入口
- `lib/pages/settings_page.dart` - 添加 AI 设置入口，更新版本号
- `lib/theme/app_theme.dart` - 添加 primaryLight 颜色
- `pubspec.yaml` - 更新版本号

## 版本信息
- 版本号: 2.0.0+22
- 提交信息: feat: 2.0.0 大版本更新 - 新增宝宝记录模块和 AI 分析功能
