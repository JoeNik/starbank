// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'story_session.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class StorySessionAdapter extends TypeAdapter<StorySession> {
  @override
  final int typeId = 13;

  @override
  StorySession read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return StorySession(
      id: fields[0] as String,
      babyId: fields[1] as String,
      createdAt: fields[2] as DateTime,
      imageUrl: fields[3] as String,
      messages: (fields[4] as List)
          .map((dynamic e) => (e as Map).cast<String, dynamic>())
          .toList(),
      score: fields[5] == null ? 0 : fields[5] as int,
      isCompleted: fields[6] == null ? false : fields[6] as bool,
      isReviewed: fields[7] == null ? false : fields[7] as bool,
      bonusStars: fields[8] == null ? 0 : fields[8] as int,
      storySummary: fields[9] == null ? '' : fields[9] as String,
    );
  }

  @override
  void write(BinaryWriter writer, StorySession obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.babyId)
      ..writeByte(2)
      ..write(obj.createdAt)
      ..writeByte(3)
      ..write(obj.imageUrl)
      ..writeByte(4)
      ..write(obj.messages)
      ..writeByte(5)
      ..write(obj.score)
      ..writeByte(6)
      ..write(obj.isCompleted)
      ..writeByte(7)
      ..write(obj.isReviewed)
      ..writeByte(8)
      ..write(obj.bonusStars)
      ..writeByte(9)
      ..write(obj.storySummary);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StorySessionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
