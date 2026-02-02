// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'music_track.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MusicTrackAdapter extends TypeAdapter<MusicTrack> {
  @override
  final int typeId = 30;

  @override
  MusicTrack read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MusicTrack(
      id: fields[0] as String,
      title: fields[1] as String,
      artist: fields[2] as String,
      album: fields[3] as String?,
      coverUrl: fields[4] as String?,
      url: fields[5] as String?,
      durationMs: fields[6] as int?,
      platform: fields[7] as String,
      lyricUrl: fields[8] as String?,
      lyricContent: fields[9] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, MusicTrack obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.artist)
      ..writeByte(3)
      ..write(obj.album)
      ..writeByte(4)
      ..write(obj.coverUrl)
      ..writeByte(5)
      ..write(obj.url)
      ..writeByte(6)
      ..write(obj.durationMs)
      ..writeByte(7)
      ..write(obj.platform)
      ..writeByte(8)
      ..write(obj.lyricUrl)
      ..writeByte(9)
      ..write(obj.lyricContent);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MusicTrackAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
