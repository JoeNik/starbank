// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_chat.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AIChatAdapter extends TypeAdapter<AIChat> {
  @override
  final int typeId = 12;

  @override
  AIChat read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AIChat(
      id: fields[0] as String,
      babyId: fields[1] as String,
      createdAt: fields[2] as DateTime,
      prompt: fields[3] as String,
      response: fields[4] as String,
      chatType: fields[5] as String,
    );
  }

  @override
  void write(BinaryWriter writer, AIChat obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.babyId)
      ..writeByte(2)
      ..write(obj.createdAt)
      ..writeByte(3)
      ..write(obj.prompt)
      ..writeByte(4)
      ..write(obj.response)
      ..writeByte(5)
      ..write(obj.chatType);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AIChatAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
