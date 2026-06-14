// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'baby_cloud_media.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class BabyCloudMediaAdapter extends TypeAdapter<BabyCloudMedia> {
  @override
  final int typeId = 49;

  @override
  BabyCloudMedia read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return BabyCloudMedia(
      id: fields[0] as String,
      babyId: fields[1] as String,
      dataSourceId: fields[2] as String,
      sha256: fields[3] as String,
      fileName: fields[4] as String,
      mediaType: fields[5] as String,
      mimeType: fields[6] as String,
      remotePath: fields[7] as String,
      thumbnailRemotePath: fields[8] as String?,
      localPath: fields[9] as String?,
      localThumbnailPath: fields[10] as String?,
      sizeBytes: fields[11] as int,
      width: fields[12] as int?,
      height: fields[13] as int?,
      durationSeconds: fields[14] as int?,
      takenAt: fields[15] as DateTime?,
      uploadedAt: fields[16] as DateTime?,
      updatedAt: fields[17] as DateTime?,
      deletedAt: fields[18] as DateTime?,
      entryId: fields[19] as String?,
      description: fields[20] as String?,
      tags: (fields[21] as List?)?.cast<String>(),
      locationName: fields[22] as String?,
      visibility: fields[23] as String,
      libraryId: fields[24] == null ? '' : fields[24] as String,
      cloudBabyId: fields[25] == null ? '' : fields[25] as String,
      deleteReason: fields[26] as String?,
      replacedByMediaId: fields[27] as String?,
      purgedAt: fields[28] as DateTime?,
      actorRole: fields[29] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, BabyCloudMedia obj) {
    writer
      ..writeByte(30)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.babyId)
      ..writeByte(2)
      ..write(obj.dataSourceId)
      ..writeByte(3)
      ..write(obj.sha256)
      ..writeByte(4)
      ..write(obj.fileName)
      ..writeByte(5)
      ..write(obj.mediaType)
      ..writeByte(6)
      ..write(obj.mimeType)
      ..writeByte(7)
      ..write(obj.remotePath)
      ..writeByte(8)
      ..write(obj.thumbnailRemotePath)
      ..writeByte(9)
      ..write(obj.localPath)
      ..writeByte(10)
      ..write(obj.localThumbnailPath)
      ..writeByte(11)
      ..write(obj.sizeBytes)
      ..writeByte(12)
      ..write(obj.width)
      ..writeByte(13)
      ..write(obj.height)
      ..writeByte(14)
      ..write(obj.durationSeconds)
      ..writeByte(15)
      ..write(obj.takenAt)
      ..writeByte(16)
      ..write(obj.uploadedAt)
      ..writeByte(17)
      ..write(obj.updatedAt)
      ..writeByte(18)
      ..write(obj.deletedAt)
      ..writeByte(19)
      ..write(obj.entryId)
      ..writeByte(20)
      ..write(obj.description)
      ..writeByte(21)
      ..write(obj.tags)
      ..writeByte(22)
      ..write(obj.locationName)
      ..writeByte(23)
      ..write(obj.visibility)
      ..writeByte(24)
      ..write(obj.libraryId)
      ..writeByte(25)
      ..write(obj.cloudBabyId)
      ..writeByte(26)
      ..write(obj.deleteReason)
      ..writeByte(27)
      ..write(obj.replacedByMediaId)
      ..writeByte(28)
      ..write(obj.purgedAt)
      ..writeByte(29)
      ..write(obj.actorRole);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BabyCloudMediaAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
