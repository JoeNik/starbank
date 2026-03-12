// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cftts_config.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CfttsConfigAdapter extends TypeAdapter<CfttsConfig> {
  @override
  final int typeId = 41;

  @override
  CfttsConfig read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CfttsConfig(
      baseUrl:
          fields[0] == null ? 'http://localhost:8080' : fields[0] as String,
      apiKey: fields[1] == null ? '' : fields[1] as String,
      voice: fields[2] == null ? 'zh-CN-XiaoxiaoNeural' : fields[2] as String,
      model: fields[3] == null ? 'cheerful' : fields[3] as String,
      speed: fields[4] == null ? 1.0 : fields[4] as double,
    );
  }

  @override
  void write(BinaryWriter writer, CfttsConfig obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.baseUrl)
      ..writeByte(1)
      ..write(obj.apiKey)
      ..writeByte(2)
      ..write(obj.voice)
      ..writeByte(3)
      ..write(obj.model)
      ..writeByte(4)
      ..write(obj.speed);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CfttsConfigAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
