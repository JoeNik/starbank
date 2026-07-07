// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'poop_record.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PoopRecordAdapter extends TypeAdapter<PoopRecord> {
  @override
  final int typeId = 11;

  @override
  PoopRecord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PoopRecord.fromHiveFields(fields);
  }

  @override
  void write(BinaryWriter writer, PoopRecord obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.babyId)
      ..writeByte(2)
      ..write(obj.dateTime)
      ..writeByte(3)
      ..write(obj.note)
      ..writeByte(4)
      ..write(obj.type)
      ..writeByte(5)
      ..write(obj.color);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PoopRecordAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
