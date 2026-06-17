// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'baby_cloud_source.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class BabyCloudSourceAdapter extends TypeAdapter<BabyCloudSource> {
  @override
  final int typeId = 48;

  @override
  BabyCloudSource read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return BabyCloudSource(
      id: fields[0] as String,
      name: fields[1] as String,
      type: fields[2] as String,
      status: fields[3] as String,
      rootPath: fields[4] as String,
      webDavUrl: fields[5] as String?,
      webDavUsername: fields[6] as String?,
      webDavPassword: fields[7] as String?,
      aliyunDriveRefreshToken: fields[8] as String?,
      webDavLanUrl: fields[11] as String?,
      activeWebDavUrl: fields[12] as String?,
      activeWebDavEndpoint: fields[13] as String,
      lastCheckedAt: fields[14] as DateTime?,
      lastCheckMessage: fields[15] as String?,
      libraryId: fields[16] as String?,
      libraryName: fields[17] as String?,
      aliyunDriveClientId: fields[18] as String?,
      aliyunDriveClientSecret: fields[19] as String?,
      aliyunDriveRedirectUri: fields[20] as String?,
      aliyunDriveScope: fields[21] as String?,
      aliyunDriveAuthUrl: fields[22] as String?,
      aliyunDriveTokenUrl: fields[23] as String?,
      aliyunDriveAccessToken: fields[24] as String?,
      aliyunDriveTokenExpiresAt: fields[25] as DateTime?,
      aliyunDriveDriveId: fields[26] as String?,
      aliyunDriveUserId: fields[27] as String?,
      aliyunDriveNickName: fields[28] as String?,
      webDavEndpointMode: (fields[29] as String?) ?? 'auto',
      createdAt: fields[9] as DateTime?,
      updatedAt: fields[10] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, BabyCloudSource obj) {
    writer
      ..writeByte(30)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.type)
      ..writeByte(3)
      ..write(obj.status)
      ..writeByte(4)
      ..write(obj.rootPath)
      ..writeByte(5)
      ..write(obj.webDavUrl)
      ..writeByte(6)
      ..write(obj.webDavUsername)
      ..writeByte(7)
      ..write(obj.webDavPassword)
      ..writeByte(8)
      ..write(obj.aliyunDriveRefreshToken)
      ..writeByte(9)
      ..write(obj.createdAt)
      ..writeByte(10)
      ..write(obj.updatedAt)
      ..writeByte(11)
      ..write(obj.webDavLanUrl)
      ..writeByte(12)
      ..write(obj.activeWebDavUrl)
      ..writeByte(13)
      ..write(obj.activeWebDavEndpoint)
      ..writeByte(14)
      ..write(obj.lastCheckedAt)
      ..writeByte(15)
      ..write(obj.lastCheckMessage)
      ..writeByte(16)
      ..write(obj.libraryId)
      ..writeByte(17)
      ..write(obj.libraryName)
      ..writeByte(18)
      ..write(obj.aliyunDriveClientId)
      ..writeByte(19)
      ..write(obj.aliyunDriveClientSecret)
      ..writeByte(20)
      ..write(obj.aliyunDriveRedirectUri)
      ..writeByte(21)
      ..write(obj.aliyunDriveScope)
      ..writeByte(22)
      ..write(obj.aliyunDriveAuthUrl)
      ..writeByte(23)
      ..write(obj.aliyunDriveTokenUrl)
      ..writeByte(24)
      ..write(obj.aliyunDriveAccessToken)
      ..writeByte(25)
      ..write(obj.aliyunDriveTokenExpiresAt)
      ..writeByte(26)
      ..write(obj.aliyunDriveDriveId)
      ..writeByte(27)
      ..write(obj.aliyunDriveUserId)
      ..writeByte(28)
      ..write(obj.aliyunDriveNickName)
      ..writeByte(29)
      ..write(obj.webDavEndpointMode);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BabyCloudSourceAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
