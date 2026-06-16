// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'baby_cloud_upload_task.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class BabyCloudUploadTaskAdapter extends TypeAdapter<BabyCloudUploadTask> {
  @override
  final int typeId = 50;

  @override
  BabyCloudUploadTask read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return BabyCloudUploadTask(
      id: fields[0] as String,
      babyId: fields[1] as String,
      dataSourceId: fields[2] as String,
      localPath: fields[3] as String,
      fileName: fields[4] as String,
      mediaType: fields[5] as String,
      mimeType: fields[6] as String,
      sizeBytes: fields[7] as int,
      sha256: fields[8] as String?,
      status: fields[9] as String,
      progress: fields[10] as double,
      remotePath: fields[11] as String?,
      errorMessage: fields[12] as String?,
      takenAt: fields[15] as DateTime?,
      localThumbnailPath: fields[16] as String?,
      entryId: fields[17] as String?,
      description: fields[18] as String?,
      tags: (fields[19] as List?)?.cast<String>(),
      locationName: fields[20] as String?,
      visibility: fields[21] == null ? 'family' : fields[21] as String,
      taskType: fields[22] == null ? 'upload' : fields[22] as String,
      targetId: fields[23] as String?,
      actorRole: fields[24] as String?,
      retryCount: fields[25] == null ? 0 : fields[25] as int,
      createdAt: fields[13] as DateTime?,
      updatedAt: fields[14] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, BabyCloudUploadTask obj) {
    writer
      ..writeByte(26)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.babyId)
      ..writeByte(2)
      ..write(obj.dataSourceId)
      ..writeByte(3)
      ..write(obj.localPath)
      ..writeByte(4)
      ..write(obj.fileName)
      ..writeByte(5)
      ..write(obj.mediaType)
      ..writeByte(6)
      ..write(obj.mimeType)
      ..writeByte(7)
      ..write(obj.sizeBytes)
      ..writeByte(8)
      ..write(obj.sha256)
      ..writeByte(9)
      ..write(obj.status)
      ..writeByte(10)
      ..write(obj.progress)
      ..writeByte(11)
      ..write(obj.remotePath)
      ..writeByte(12)
      ..write(obj.errorMessage)
      ..writeByte(13)
      ..write(obj.createdAt)
      ..writeByte(14)
      ..write(obj.updatedAt)
      ..writeByte(15)
      ..write(obj.takenAt)
      ..writeByte(16)
      ..write(obj.localThumbnailPath)
      ..writeByte(17)
      ..write(obj.entryId)
      ..writeByte(18)
      ..write(obj.description)
      ..writeByte(19)
      ..write(obj.tags)
      ..writeByte(20)
      ..write(obj.locationName)
      ..writeByte(21)
      ..write(obj.visibility)
      ..writeByte(22)
      ..write(obj.taskType)
      ..writeByte(23)
      ..write(obj.targetId)
      ..writeByte(24)
      ..write(obj.actorRole)
      ..writeByte(25)
      ..write(obj.retryCount);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BabyCloudUploadTaskAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
