// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'baby_cloud_entry.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class BabyCloudEntryAdapter extends TypeAdapter<BabyCloudEntry> {
  @override
  final int typeId = 51;

  @override
  BabyCloudEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return BabyCloudEntry(
      id: fields[0] as String,
      babyId: fields[1] as String,
      dataSourceId: fields[2] as String,
      libraryId: fields[3] == null ? '' : fields[3] as String,
      cloudBabyId: fields[4] == null ? '' : fields[4] as String,
      entryType: fields[5] == null ? 'media' : fields[5] as String,
      description: fields[6] as String?,
      tags: (fields[7] as List?)?.cast<String>(),
      locationName: fields[8] as String?,
      visibility: fields[9] == null ? 'family' : fields[9] as String,
      takenAt: fields[10] as DateTime?,
      createdAt: fields[11] as DateTime?,
      updatedAt: fields[12] as DateTime?,
      deletedAt: fields[13] as DateTime?,
      deleteReason: fields[14] as String?,
      mediaIds: (fields[15] as List?)?.cast<String>(),
      purgedAt: fields[16] as DateTime?,
      actorRole: fields[17] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, BabyCloudEntry obj) {
    writer
      ..writeByte(18)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.babyId)
      ..writeByte(2)
      ..write(obj.dataSourceId)
      ..writeByte(3)
      ..write(obj.libraryId)
      ..writeByte(4)
      ..write(obj.cloudBabyId)
      ..writeByte(5)
      ..write(obj.entryType)
      ..writeByte(6)
      ..write(obj.description)
      ..writeByte(7)
      ..write(obj.tags)
      ..writeByte(8)
      ..write(obj.locationName)
      ..writeByte(9)
      ..write(obj.visibility)
      ..writeByte(10)
      ..write(obj.takenAt)
      ..writeByte(11)
      ..write(obj.createdAt)
      ..writeByte(12)
      ..write(obj.updatedAt)
      ..writeByte(13)
      ..write(obj.deletedAt)
      ..writeByte(14)
      ..write(obj.deleteReason)
      ..writeByte(15)
      ..write(obj.mediaIds)
      ..writeByte(16)
      ..write(obj.purgedAt)
      ..writeByte(17)
      ..write(obj.actorRole);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BabyCloudEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
