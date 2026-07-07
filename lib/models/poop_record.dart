import 'package:hive/hive.dart';

part 'poop_record.g.dart';

/// 便便记录数据模型
@HiveType(typeId: 11)
class PoopRecord extends HiveObject {
  /// 唯一标识
  @HiveField(0)
  String id;

  /// 关联的宝宝ID
  @HiveField(1)
  String babyId;

  /// 记录时间
  @HiveField(2)
  DateTime dateTime;

  /// 备注说明
  @HiveField(3)
  String note;

  /// 便便类型: 0-正常, 1-稀便, 2-干硬, 3-其他
  @HiveField(4)
  int type;

  /// 颜色描述: 0-正常黄色, 1-绿色, 2-黑色, 3-其他
  @HiveField(5)
  int color;

  PoopRecord({
    required this.id,
    required this.babyId,
    required this.dateTime,
    this.note = '',
    this.type = 0,
    this.color = 0,
  });

  /// 获取类型描述
  String get typeDesc {
    switch (type) {
      case 0:
        return '正常';
      case 1:
        return '稀便';
      case 2:
        return '干硬';
      case 3:
        return '其他';
      default:
        return '未知';
    }
  }

  /// 获取颜色描述
  String get colorDesc {
    switch (color) {
      case 0:
        return '正常黄色';
      case 1:
        return '绿色';
      case 2:
        return '黑色';
      case 3:
        return '其他';
      default:
        return '未知';
    }
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() => {
        'id': id,
        'babyId': babyId,
        'dateTime': dateTime.toIso8601String(),
        'note': note,
        'type': type,
        'color': color,
      };

  /// 从 JSON 创建
  factory PoopRecord.fromJson(Map<String, dynamic> json) => PoopRecord(
        id: _requiredString(json['id'], 'id'),
        babyId: _requiredString(json['babyId'], 'babyId'),
        dateTime: _requiredDateTime(json['dateTime'], 'dateTime'),
        note: _optionalString(json['note'], 'note'),
        type: _optionalInt(json['type'], 'type'),
        color: _optionalInt(json['color'], 'color'),
      );

  factory PoopRecord.fromHiveFields(Map<int, dynamic> fields) => PoopRecord(
        id: _requiredString(fields[0], 'id'),
        babyId: _requiredString(fields[1], 'babyId'),
        dateTime: _requiredDateTime(fields[2], 'dateTime'),
        note: _optionalString(fields[3], 'note'),
        type: _optionalInt(fields[4], 'type'),
        color: _optionalInt(fields[5], 'color'),
      );

  static String _requiredString(dynamic value, String fieldName) {
    if (value is String && value.trim().isNotEmpty) {
      return value;
    }
    if (value is num) {
      return value.toString();
    }
    throw FormatException('便便记录字段 $fieldName 缺失或类型错误');
  }

  static DateTime _requiredDateTime(dynamic value, String fieldName) {
    if (value is DateTime) {
      return value;
    }
    if (value is String && value.trim().isNotEmpty) {
      try {
        return DateTime.parse(value);
      } catch (_) {
        throw FormatException('便便记录字段 $fieldName 不是有效时间');
      }
    }
    throw FormatException('便便记录字段 $fieldName 缺失或类型错误');
  }

  static String _optionalString(dynamic value, String fieldName) {
    if (value == null) {
      return '';
    }
    if (value is String) {
      return value;
    }
    throw FormatException('便便记录字段 $fieldName 类型错误');
  }

  static int _optionalInt(dynamic value, String fieldName) {
    if (value == null) {
      return 0;
    }
    if (value is int) {
      return value;
    }
    if (value is num && value.isFinite && value == value.roundToDouble()) {
      return value.toInt();
    }
    if (value is String && value.trim().isNotEmpty) {
      final parsed = int.tryParse(value);
      if (parsed != null) {
        return parsed;
      }
    }
    throw FormatException('便便记录字段 $fieldName 类型错误');
  }
}
