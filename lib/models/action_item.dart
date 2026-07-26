import 'package:hive/hive.dart';

part 'action_item.g.dart';

@HiveType(typeId: 1)
class ActionItem extends HiveObject {
  @HiveField(0)
  String name;

  @HiveField(1)
  String type; // 'reward', 'punish', 'deposit', 'withdraw'

  @HiveField(2)
  double value; // +1, -1, +100

  @HiveField(3)
  String iconName; // e.g., 'star', 'broom'

  /// 同步用唯一 ID（旧数据启动时懒回填）
  @HiveField(4)
  String? syncId;

  ActionItem({
    required this.name,
    required this.type,
    required this.value,
    this.iconName = '',
    this.syncId,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type,
    'value': value,
    'iconName': iconName,
    if (syncId != null) 'syncId': syncId,
  };

  factory ActionItem.fromJson(Map<String, dynamic> json) => ActionItem(
    name: json['name'],
    type: json['type'],
    value: (json['value'] ?? 0).toDouble(),
    iconName: json['iconName'] ??= '',
    syncId: json['syncId'] as String?,
  );
}
