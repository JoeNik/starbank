import 'package:hive/hive.dart';

part 'log.g.dart';

@HiveType(typeId: 2)
class Log extends HiveObject {
  @HiveField(0)
  DateTime timestamp;

  @HiveField(1)
  String description;

  @HiveField(2)
  double changeAmount;

  @HiveField(3)
  String type; // 'star', 'piggy', 'pocket'

  @HiveField(4)
  String babyId;

  Log({
    required this.timestamp,
    required this.description,
    required this.changeAmount,
    required this.type,
    required this.babyId,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'description': description,
    'changeAmount': changeAmount,
    'type': type,
    'babyId': babyId,
  };

  factory Log.fromJson(Map<String, dynamic> json) => Log(
    timestamp: DateTime.parse(json['timestamp']),
    description: json['description'],
    changeAmount: (json['changeAmount'] ?? 0).toDouble(),
    type: json['type'],
    babyId: json['babyId'] ?? '1',
  );
}
