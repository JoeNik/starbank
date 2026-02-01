// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'quiz_config.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class QuizConfigAdapter extends TypeAdapter<QuizConfig> {
  @override
  final int typeId = 20;

  @override
  QuizConfig read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return QuizConfig(
      imageGenConfigId: fields[0] as String?,
      chatConfigId: fields[1] as String?,
      imageGenPrompt: fields[2] == null
          ? '请为以下新年知识点生成一张可爱的儿童插画:\n{knowledge}\n\n要求:\n1. 儿童插画风格,色彩明亮温暖,画面可爱有趣\n2. 符合中国传统新年文化,展现节日喜庆氛围\n3. 适合3-8岁儿童观看,内容健康积极\n4. 画面简洁清晰,主题突出,避免复杂细节\n5. 使用卡通风格,圆润可爱的造型\n6. 严格禁止任何暴力、恐怖、成人或不适合儿童的内容'
          : fields[2] as String,
      chatPrompt: fields[3] == null
          ? '你是一个儿童教育专家,请为以下新年知识点生成一个适合儿童的问答题:\n{knowledge}\n\n要求:\n1. 问题简单易懂,适合3-8岁儿童\n2. 提供4个选项,其中1个正确\n3. 包含详细的知识点解释\n4. 语言生动有趣'
          : fields[3] as String,
      enableImageGen: fields[4] == null ? false : fields[4] as bool,
      enableQuestionGen: fields[5] == null ? false : fields[5] as bool,
      dailyPlayLimit: fields[6] == null ? 0 : fields[6] as int,
    );
  }

  @override
  void write(BinaryWriter writer, QuizConfig obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.imageGenConfigId)
      ..writeByte(1)
      ..write(obj.chatConfigId)
      ..writeByte(2)
      ..write(obj.imageGenPrompt)
      ..writeByte(3)
      ..write(obj.chatPrompt)
      ..writeByte(4)
      ..write(obj.enableImageGen)
      ..writeByte(5)
      ..write(obj.enableQuestionGen)
      ..writeByte(6)
      ..write(obj.dailyPlayLimit);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuizConfigAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
