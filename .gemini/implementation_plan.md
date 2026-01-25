# 宝宝健康记录模块实现计划

## 功能概述
1. 调整导航栏：移除设置入口，新增"记录"模块
2. 设置入口移到主页右上角
3. 新增 OpenAI 设置页面
4. 新增便便记录功能（含 AI 分析）

## 任务分解

### Phase 1: 导航栏和设置入口调整
- [ ] 1.1 修改 main.dart，导航栏从5个变为4个
- [ ] 1.2 移除"设置"导航项，新增"记录"导航项
- [ ] 1.3 主页面右上角添加设置图标入口
- [ ] 1.4 创建记录模块入口页面 RecordPage

### Phase 2: OpenAI 设置功能
- [ ] 2.1 创建 OpenAI 配置数据模型 (openai_config.dart)
  - 支持多个 API 地址
  - 存储 API Key、Base URL、模型列表
- [ ] 2.2 创建 OpenAI 设置页面 (openai_settings_page.dart)
  - 添加/编辑/删除配置
  - 测试连接并获取模型列表
  - 选择默认配置
- [ ] 2.3 创建 OpenAI 服务 (openai_service.dart)
  - 封装 API 调用
  - 支持流式响应
- [ ] 2.4 设置页面添加 OpenAI 设置入口
- [ ] 2.5 OpenAI 配置支持备份/恢复

### Phase 3: 便便记录功能
- [ ] 3.1 创建便便记录数据模型 (poop_record.dart)
  - 日期、时间、备注、宝宝ID
- [ ] 3.2 创建智能体配置模型 (agent_config.dart)
  - prompt 模板
  - 分析时间范围设置
- [ ] 3.3 创建便便记录页面 (poop_record_page.dart)
  - 快速添加记录按钮
  - 日历视图展示
  - 记录列表
- [ ] 3.4 创建 AI 分析功能
  - 选择时间范围
  - 发送记录给 AI
  - 展示 AI 建议
- [ ] 3.5 创建历史对话页面
  - 保存历史对话
  - 查看历史建议
- [ ] 3.6 便便数据支持备份/恢复

### Phase 4: 数据备份恢复增强
- [ ] 4.1 扩展 WebDAV 备份，包含新增数据
- [ ] 4.2 确保所有新数据模型支持序列化

### Phase 5: 测试和发布
- [ ] 5.1 功能测试
- [ ] 5.2 更新版本号为 2.0.0
- [ ] 5.3 提交编译

## 技术设计

### 数据模型

```dart
// OpenAI 配置
@HiveType(typeId: 10)
class OpenAIConfig {
  @HiveField(0) String id;
  @HiveField(1) String name;        // 配置名称
  @HiveField(2) String baseUrl;     // API 地址
  @HiveField(3) String apiKey;      // API Key
  @HiveField(4) List<String> models; // 可用模型列表
  @HiveField(5) String selectedModel; // 选中的模型
  @HiveField(6) bool isDefault;     // 是否默认
}

// 便便记录
@HiveType(typeId: 11)
class PoopRecord {
  @HiveField(0) String id;
  @HiveField(1) String babyId;      // 关联宝宝
  @HiveField(2) DateTime dateTime;  // 记录时间
  @HiveField(3) String note;        // 备注
  @HiveField(4) int type;           // 类型（正常/异常等）
}

// AI 对话记录
@HiveType(typeId: 12)
class AIChat {
  @HiveField(0) String id;
  @HiveField(1) String babyId;
  @HiveField(2) DateTime createdAt;
  @HiveField(3) String prompt;      // 发送的内容
  @HiveField(4) String response;    // AI 回复
  @HiveField(5) String type;        // 对话类型（便便分析等）
}

// 智能体配置
@HiveType(typeId: 13)
class AgentConfig {
  @HiveField(0) String id;
  @HiveField(1) String name;
  @HiveField(2) String prompt;      // 系统提示词
  @HiveField(3) String type;        // 类型
}
```

### 页面结构

```
lib/pages/
├── record_page.dart           # 记录模块入口
├── poop/
│   ├── poop_record_page.dart  # 便便记录主页
│   ├── poop_add_dialog.dart   # 添加记录弹窗
│   ├── poop_calendar.dart     # 日历视图
│   └── poop_ai_page.dart      # AI 分析页面
├── openai_settings_page.dart  # OpenAI 设置
└── agent_settings_page.dart   # 智能体设置
```

## 开始实施

请确认此计划，我将开始实施。
