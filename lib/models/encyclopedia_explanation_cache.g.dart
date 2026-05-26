// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'encyclopedia_explanation_cache.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class EncyclopediaExplanationCacheAdapter
    extends TypeAdapter<EncyclopediaExplanationCache> {
  @override
  final int typeId = 45;

  @override
  EncyclopediaExplanationCache read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return EncyclopediaExplanationCache(
      cacheKey: fields[0] as String,
      questionId: fields[1] as String,
      model: fields[2] as String,
      promptVersion: fields[3] as String,
      shortAnswer: fields[4] as String,
      why: fields[5] as String,
      example: fields[6] as String,
      createdAt: fields[7] as DateTime?,
      updatedAt: fields[8] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, EncyclopediaExplanationCache obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.cacheKey)
      ..writeByte(1)
      ..write(obj.questionId)
      ..writeByte(2)
      ..write(obj.model)
      ..writeByte(3)
      ..write(obj.promptVersion)
      ..writeByte(4)
      ..write(obj.shortAnswer)
      ..writeByte(5)
      ..write(obj.why)
      ..writeByte(6)
      ..write(obj.example)
      ..writeByte(7)
      ..write(obj.createdAt)
      ..writeByte(8)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EncyclopediaExplanationCacheAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
