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

  ActionItem({
    required this.name,
    required this.type,
    required this.value,
    this.iconName = '',
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type,
    'value': value,
    'iconName': iconName,
  };

  factory ActionItem.fromJson(Map<String, dynamic> json) => ActionItem(
    name: json['name'],
    type: json['type'],
    value: (json['value'] ?? 0).toDouble(),
    iconName: json['iconName'] ??= '',
  );
}
