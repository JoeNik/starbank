// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'quiz_question.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class QuizQuestionAdapter extends TypeAdapter<QuizQuestion> {
  @override
  final int typeId = 21;

  @override
  QuizQuestion read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return QuizQuestion(
      id: fields[0] as String,
      question: fields[1] as String,
      emoji: fields[2] as String,
      options: (fields[3] as List).cast<String>(),
      correctIndex: fields[4] as int,
      explanation: fields[5] as String,
      category: fields[6] as String,
      imagePath: fields[7] as String?,
      imageStatus: fields[8] as String?,
      imageError: fields[9] as String?,
      createdAt: fields[10] as DateTime?,
      updatedAt: fields[11] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, QuizQuestion obj) {
    writer
      ..writeByte(12)
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
      ..write(obj.explanation)
      ..writeByte(6)
      ..write(obj.category)
      ..writeByte(7)
      ..write(obj.imagePath)
      ..writeByte(8)
      ..write(obj.imageStatus)
      ..writeByte(9)
      ..write(obj.imageError)
      ..writeByte(10)
      ..write(obj.createdAt)
      ..writeByte(11)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuizQuestionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
