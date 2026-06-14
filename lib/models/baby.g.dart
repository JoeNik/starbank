// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'baby.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class BabyAdapter extends TypeAdapter<Baby> {
  @override
  final int typeId = 4;

  @override
  Baby read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Baby(
      id: fields[0] as String,
      name: fields[1] as String,
      avatarPath: fields[2] as String,
      starCount: fields[3] as int,
      piggyBankBalance: fields[4] as double,
      pocketMoneyBalance: fields[5] as double,
      lastInterestDate: fields[6] as DateTime?,
      birthDate: fields[7] as DateTime?,
      gender: fields[8] == null ? 'unknown' : fields[8] as String,
    );
  }

  @override
  void write(BinaryWriter writer, Baby obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.avatarPath)
      ..writeByte(3)
      ..write(obj.starCount)
      ..writeByte(4)
      ..write(obj.piggyBankBalance)
      ..writeByte(5)
      ..write(obj.pocketMoneyBalance)
      ..writeByte(6)
      ..write(obj.lastInterestDate)
      ..writeByte(7)
      ..write(obj.birthDate)
      ..writeByte(8)
      ..write(obj.gender);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BabyAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
