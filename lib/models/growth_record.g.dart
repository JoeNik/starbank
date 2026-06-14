// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'growth_record.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class GrowthRecordAdapter extends TypeAdapter<GrowthRecord> {
  @override
  final int typeId = 46;

  @override
  GrowthRecord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return GrowthRecord(
      id: fields[0] as String,
      babyId: fields[1] as String,
      recordDate: fields[2] as DateTime,
      heightCm: fields[3] as double?,
      weightKg: fields[4] as double?,
      headCircumferenceCm: fields[5] as double?,
      note: fields[6] as String,
      sourceImagePath: fields[7] as String?,
      createdAt: fields[8] as DateTime?,
      updatedAt: fields[9] as DateTime?,
      deletedAt: fields[10] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, GrowthRecord obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.babyId)
      ..writeByte(2)
      ..write(obj.recordDate)
      ..writeByte(3)
      ..write(obj.heightCm)
      ..writeByte(4)
      ..write(obj.weightKg)
      ..writeByte(5)
      ..write(obj.headCircumferenceCm)
      ..writeByte(6)
      ..write(obj.note)
      ..writeByte(7)
      ..write(obj.sourceImagePath)
      ..writeByte(8)
      ..write(obj.createdAt)
      ..writeByte(9)
      ..write(obj.updatedAt)
      ..writeByte(10)
      ..write(obj.deletedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GrowthRecordAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
