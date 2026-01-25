// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'openai_config.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class OpenAIConfigAdapter extends TypeAdapter<OpenAIConfig> {
  @override
  final int typeId = 10;

  @override
  OpenAIConfig read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return OpenAIConfig(
      id: fields[0] as String,
      name: fields[1] as String,
      baseUrl: fields[2] as String,
      apiKey: fields[3] as String,
      models: (fields[4] as List).cast<String>(),
      selectedModel: fields[5] as String,
      isDefault: fields[6] as bool,
      enableWebSearch: fields[7] == null ? false : fields[7] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, OpenAIConfig obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.baseUrl)
      ..writeByte(3)
      ..write(obj.apiKey)
      ..writeByte(4)
      ..write(obj.models)
      ..writeByte(5)
      ..write(obj.selectedModel)
      ..writeByte(6)
      ..write(obj.isDefault)
      ..writeByte(7)
      ..write(obj.enableWebSearch);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OpenAIConfigAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
