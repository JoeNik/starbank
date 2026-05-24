// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'openai_tts_config.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class OpenAITtsConfigAdapter extends TypeAdapter<OpenAITtsConfig> {
  @override
  final int typeId = 42;

  @override
  OpenAITtsConfig read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return OpenAITtsConfig(
      id: fields[0] as String,
      name: fields[1] as String,
      baseUrl: fields[2] as String,
      apiKey: fields[3] as String,
      providerType: fields[4] == null ? 'openai_standard' : fields[4] as String,
      authType: fields[5] == null ? 'bearer' : fields[5] as String,
      models: (fields[6] as List).cast<String>(),
      selectedModel: fields[7] as String,
      voices: (fields[8] as List).cast<String>(),
      selectedVoice: fields[9] as String,
      stylePresets: (fields[10] as List).cast<String>(),
      selectedStylePreset: fields[11] as String,
      audioFormat: fields[12] == null ? 'mp3' : fields[12] as String,
      isDefault: fields[13] == null ? false : fields[13] as bool,
      supportsModelFetch: fields[14] == null ? true : fields[14] as bool,
      supportsVoiceFetch: fields[15] == null ? false : fields[15] as bool,
      isEnabled: fields[16] == null ? true : fields[16] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, OpenAITtsConfig obj) {
    writer
      ..writeByte(17)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.baseUrl)
      ..writeByte(3)
      ..write(obj.apiKey)
      ..writeByte(4)
      ..write(obj.providerType)
      ..writeByte(5)
      ..write(obj.authType)
      ..writeByte(6)
      ..write(obj.models)
      ..writeByte(7)
      ..write(obj.selectedModel)
      ..writeByte(8)
      ..write(obj.voices)
      ..writeByte(9)
      ..write(obj.selectedVoice)
      ..writeByte(10)
      ..write(obj.stylePresets)
      ..writeByte(11)
      ..write(obj.selectedStylePreset)
      ..writeByte(12)
      ..write(obj.audioFormat)
      ..writeByte(13)
      ..write(obj.isDefault)
      ..writeByte(14)
      ..write(obj.supportsModelFetch)
      ..writeByte(15)
      ..write(obj.supportsVoiceFetch)
      ..writeByte(16)
      ..write(obj.isEnabled);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OpenAITtsConfigAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
