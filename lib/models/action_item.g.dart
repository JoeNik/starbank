// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'action_item.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ActionItemAdapter extends TypeAdapter<ActionItem> {
  @override
  final int typeId = 1;

  @override
  ActionItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ActionItem(
      name: fields[0] as String,
      type: fields[1] as String,
      value: fields[2] as double,
      iconName: fields[3] as String,
      syncId: fields[4] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, ActionItem obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.type)
      ..writeByte(2)
      ..write(obj.value)
      ..writeByte(3)
      ..write(obj.iconName)
      ..writeByte(4)
      ..write(obj.syncId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActionItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
