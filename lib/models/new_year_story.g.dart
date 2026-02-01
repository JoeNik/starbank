// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'new_year_story.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class NewYearStoryAdapter extends TypeAdapter<NewYearStory> {
  @override
  final int typeId = 22;

  @override
  NewYearStory read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return NewYearStory(
      id: fields[0] as String,
      title: fields[1] as String,
      emoji: fields[2] as String,
      duration: fields[3] as String,
      pagesJson: fields[4] as String,
      createdAt: fields[5] as DateTime?,
      updatedAt: fields[6] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, NewYearStory obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.emoji)
      ..writeByte(3)
      ..write(obj.duration)
      ..writeByte(4)
      ..write(obj.pagesJson)
      ..writeByte(5)
      ..write(obj.createdAt)
      ..writeByte(6)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NewYearStoryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
