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
        id: json['id'] as String,
        babyId: json['babyId'] as String,
        dateTime: DateTime.parse(json['dateTime'] as String),
        note: json['note'] as String? ?? '',
        type: json['type'] as int? ?? 0,
        color: json['color'] as int? ?? 0,
      );
}
