// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'milestone_record.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MilestoneRecordAdapter extends TypeAdapter<MilestoneRecord> {
  @override
  final int typeId = 47;

  @override
  MilestoneRecord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MilestoneRecord(
      id: fields[0] as String,
      babyId: fields[1] as String,
      recordDate: fields[2] as DateTime,
      title: fields[3] as String,
      category: fields[4] as String,
      description: fields[5] as String,
      mediaRefs: fields[6] == null ? [] : (fields[6] as List?)?.cast<String>(),
      coverMediaRef: fields[7] as String?,
      sourceImagePath: fields[8] as String?,
      tags: fields[12] == null ? [] : (fields[12] as List?)?.cast<String>(),
      createdAt: fields[9] as DateTime?,
      updatedAt: fields[10] as DateTime?,
      deletedAt: fields[11] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, MilestoneRecord obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.babyId)
      ..writeByte(2)
      ..write(obj.recordDate)
      ..writeByte(3)
      ..write(obj.title)
      ..writeByte(4)
      ..write(obj.category)
      ..writeByte(5)
      ..write(obj.description)
      ..writeByte(6)
      ..write(obj.mediaRefs)
      ..writeByte(7)
      ..write(obj.coverMediaRef)
      ..writeByte(8)
      ..write(obj.sourceImagePath)
      ..writeByte(9)
      ..write(obj.createdAt)
      ..writeByte(10)
      ..write(obj.updatedAt)
      ..writeByte(11)
      ..write(obj.deletedAt)
      ..writeByte(12)
      ..write(obj.tags);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MilestoneRecordAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
