import 'package:hive/hive.dart';

part 'baby.g.dart';

@HiveType(typeId: 4)
class Baby extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String avatarPath;

  @HiveField(3)
  int starCount;

  @HiveField(4)
  double piggyBankBalance; // 存钱罐 (Generate Interest)

  @HiveField(5)
  double pocketMoneyBalance; // 零花钱 (Interest flows here)

  @HiveField(6)
  DateTime? lastInterestDate;

  Baby({
    required this.id,
    required this.name,
    required this.avatarPath,
    this.starCount = 0,
    this.piggyBankBalance = 0.0,
    this.pocketMoneyBalance = 0.0,
    this.lastInterestDate,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'avatarPath': avatarPath,
    'starCount': starCount,
    'piggyBankBalance': piggyBankBalance,
    'pocketMoneyBalance': pocketMoneyBalance,
    'lastInterestDate': lastInterestDate?.toIso8601String(),
  };

  factory Baby.fromJson(Map<String, dynamic> json) => Baby(
    id: json['id'],
    name: json['name'],
    avatarPath: json['avatarPath'],
    starCount: json['starCount'] ?? 0,
    piggyBankBalance: (json['piggyBankBalance'] ?? 0).toDouble(),
    pocketMoneyBalance: (json['pocketMoneyBalance'] ?? 0).toDouble(),
    lastInterestDate: json['lastInterestDate'] != null
        ? DateTime.parse(json['lastInterestDate'])
        : null,
  );
}
