// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'encyclopedia_question.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class EncyclopediaQuestionAdapter extends TypeAdapter<EncyclopediaQuestion> {
  @override
  final int typeId = 43;

  @override
  EncyclopediaQuestion read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return EncyclopediaQuestion(
      id: fields[0] as String,
      question: fields[1] as String,
      emoji: fields[2] as String,
      options: (fields[3] as List).cast<String>(),
      correctIndex: fields[4] as int,
      answer: fields[5] as String,
      explanation: fields[6] as String,
      category: fields[7] as String,
      source: fields[8] as String,
      createdAt: fields[9] as DateTime?,
      updatedAt: fields[10] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, EncyclopediaQuestion obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.question)
      ..writeByte(2)
      ..write(obj.emoji)
      ..writeByte(3)
      ..write(obj.options)
      ..writeByte(4)
      ..write(obj.correctIndex)
      ..writeByte(5)
      ..write(obj.answer)
      ..writeByte(6)
      ..write(obj.explanation)
      ..writeByte(7)
      ..write(obj.category)
      ..writeByte(8)
      ..write(obj.source)
      ..writeByte(9)
      ..write(obj.createdAt)
      ..writeByte(10)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EncyclopediaQuestionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
