// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'encyclopedia_config.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class EncyclopediaConfigAdapter extends TypeAdapter<EncyclopediaConfig> {
  @override
  final int typeId = 44;

  @override
  EncyclopediaConfig read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return EncyclopediaConfig(
      chatConfigId: fields[0] as String?,
      chatModel: fields[1] as String?,
      promptTemplate: fields[2] == null
          ? '你是一位严谨的儿童科学老师。请基于题目内容，输出 JSON，且仅输出 JSON，不要输出多余文本。\n\n硬性要求：\n1. 不能修改题目标准答案，不能自创与标准答案冲突的结论。\n2. 表达面向 6-12 岁儿童，简单、准确、易懂。\n3. 每段 1-2 句，总字数约 120-180 字。\n4. example 必须紧扣本题具体知识点，给出孩子能安全观察或理解的生活场景；禁止使用“多观察类似现象”“慢慢理解”这类空泛句。\n5. 输出必须包含以下 3 个字段：\n   - short_answer: 一句话答案\n   - why: 为什么是这个答案\n   - example: 生活中的小例子\n\n题目信息：\n问题：{question}\n选项：{options}\n标准答案：{answer}\n内置解释：{fallback}\n\n请返回：\n{\n  "short_answer": "...",\n  "why": "...",\n  "example": "..."\n}\n'
          : fields[2] as String,
      cacheExpiryDays: fields[3] == null ? 30 : fields[3] as int,
      enableAutoRefresh: fields[4] == null ? true : fields[4] as bool,
      importUrl: fields[5] as String?,
      dailyPlayLimit: fields[6] == null ? 0 : fields[6] as int,
      questionGenPromptTemplate: fields[7] == null
          ? '你是一位严谨的儿童百科题库编辑。请根据用户给定的类目，生成适合 6-12 岁儿童的一问一答选择题。\n\n硬性要求：\n1. 必须输出 JSON 数组，且仅输出 JSON，不要解释。\n2. 每题只有 2 个选项，其中 1 个正确。\n3. 正确答案位置要随机分布，不要总是第一个。\n4. 内容必须科学、准确、无争议，适合儿童。\n5. 题目语言简短清楚，解释简单易懂。\n6. explanation 必须写具体原因，不能使用“多观察类似现象”这类空泛句。\n7. id 使用英文小写、数字和下划线，必须尽量唯一。\n\n生成数量：{count}\n类目：{category}\n\n返回格式：\n[\n  {\n    "id": "life_science_001",\n    "question": "问题文本",\n    "emoji": "🌍",\n    "options": ["选项1", "选项2"],\n    "correctIndex": 0,\n    "answer": "正确答案文本",\n    "explanation": "内置解释",\n    "category": "{category}"\n  }\n]\n'
          : fields[7] as String,
      correctFeedbackText: fields[8] == null ? '恭喜答对了' : fields[8] as String,
      wrongFeedbackText: fields[9] == null ? '答错了，继续加油哦' : fields[9] as String,
    );
  }

  @override
  void write(BinaryWriter writer, EncyclopediaConfig obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.chatConfigId)
      ..writeByte(1)
      ..write(obj.chatModel)
      ..writeByte(2)
      ..write(obj.promptTemplate)
      ..writeByte(3)
      ..write(obj.cacheExpiryDays)
      ..writeByte(4)
      ..write(obj.enableAutoRefresh)
      ..writeByte(5)
      ..write(obj.importUrl)
      ..writeByte(6)
      ..write(obj.dailyPlayLimit)
      ..writeByte(7)
      ..write(obj.questionGenPromptTemplate)
      ..writeByte(8)
      ..write(obj.correctFeedbackText)
      ..writeByte(9)
      ..write(obj.wrongFeedbackText);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EncyclopediaConfigAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
