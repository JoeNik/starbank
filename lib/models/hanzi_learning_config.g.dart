// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hanzi_learning_config.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class HanziLearningConfigAdapter extends TypeAdapter<HanziLearningConfig> {
  @override
  final int typeId = 40;

  @override
  HanziLearningConfig read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return HanziLearningConfig(
      id: fields[0] as String,
      childAge: fields[1] == null ? 5 : fields[1] as int,
      knownHanziList:
          fields[2] == null ? [] : (fields[2] as List).cast<String>(),
      chatConfigId: fields[3] == null ? '' : fields[3] as String,
      chatModel: fields[4] == null ? '' : fields[4] as String,
      aiPrompt: fields[5] as String?,
      knownHanziCount: fields[6] == null ? 10 : fields[6] as int,
      newHanziCount: fields[7] == null ? 2 : fields[7] as int,
      targetCoverageRate: fields[8] == null ? 0.85 : fields[8] as double,
      isFirstLaunch: fields[9] == null ? true : fields[9] as bool,
      unlockedMaxLevel: fields[10] == null ? 1 : fields[10] as int,
    );
  }

  @override
  void write(BinaryWriter writer, HanziLearningConfig obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.childAge)
      ..writeByte(2)
      ..write(obj.knownHanziList)
      ..writeByte(3)
      ..write(obj.chatConfigId)
      ..writeByte(4)
      ..write(obj.chatModel)
      ..writeByte(5)
      ..write(obj.aiPrompt)
      ..writeByte(6)
      ..write(obj.knownHanziCount)
      ..writeByte(7)
      ..write(obj.newHanziCount)
      ..writeByte(8)
      ..write(obj.targetCoverageRate)
      ..writeByte(9)
      ..write(obj.isFirstLaunch)
      ..writeByte(10)
      ..write(obj.unlockedMaxLevel);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HanziLearningConfigAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
