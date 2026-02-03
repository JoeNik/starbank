// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'story_game_config.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class StoryGameConfigAdapter extends TypeAdapter<StoryGameConfig> {
  @override
  final int typeId = 14;

  @override
  StoryGameConfig read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return StoryGameConfig(
      id: fields[0] as String,
      imageGenerationConfigId: fields[1] == null ? '' : fields[1] as String,
      imageGenerationModel:
          fields[2] == null ? 'dall-e-3' : fields[2] as String,
      imageGenerationPrompt: fields[3] as String,
      visionConfigId: fields[4] == null ? '' : fields[4] as String,
      visionModel: fields[5] == null ? 'gpt-4o' : fields[5] as String,
      visionAnalysisPrompt: fields[6] as String,
      chatConfigId: fields[7] == null ? '' : fields[7] as String,
      chatModel: fields[8] == null ? '' : fields[8] as String,
      chatSystemPrompt: fields[9] as String,
      evaluationPrompt: fields[10] as String,
      maxRounds: fields[11] == null ? 5 : fields[11] as int,
      dailyLimit: fields[12] == null ? 2 : fields[12] as int,
      baseStars: fields[13] == null ? 3 : fields[13] as int,
      enableStarReward: fields[14] == null ? true : fields[14] as bool,
      fallbackImageUrls:
          fields[15] == null ? [] : (fields[15] as List).cast<String>(),
      remoteImageApiUrl: fields[16] == null ? '' : fields[16] as String,
      ttsRate: fields[17] == null ? 0.5 : fields[17] as double,
      ttsVolume: fields[18] == null ? 1.0 : fields[18] as double,
      ttsPitch: fields[19] == null ? 1.0 : fields[19] as double,
      enableImageGeneration: fields[20] == null ? false : fields[20] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, StoryGameConfig obj) {
    writer
      ..writeByte(21)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.imageGenerationConfigId)
      ..writeByte(2)
      ..write(obj.imageGenerationModel)
      ..writeByte(3)
      ..write(obj.imageGenerationPrompt)
      ..writeByte(4)
      ..write(obj.visionConfigId)
      ..writeByte(5)
      ..write(obj.visionModel)
      ..writeByte(6)
      ..write(obj.visionAnalysisPrompt)
      ..writeByte(7)
      ..write(obj.chatConfigId)
      ..writeByte(8)
      ..write(obj.chatModel)
      ..writeByte(9)
      ..write(obj.chatSystemPrompt)
      ..writeByte(10)
      ..write(obj.evaluationPrompt)
      ..writeByte(11)
      ..write(obj.maxRounds)
      ..writeByte(12)
      ..write(obj.dailyLimit)
      ..writeByte(13)
      ..write(obj.baseStars)
      ..writeByte(14)
      ..write(obj.enableStarReward)
      ..writeByte(15)
      ..write(obj.fallbackImageUrls)
      ..writeByte(16)
      ..write(obj.remoteImageApiUrl)
      ..writeByte(17)
      ..write(obj.ttsRate)
      ..writeByte(18)
      ..write(obj.ttsVolume)
      ..writeByte(19)
      ..write(obj.ttsPitch)
      ..writeByte(20)
      ..write(obj.enableImageGeneration);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StoryGameConfigAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
