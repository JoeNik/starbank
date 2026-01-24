import 'package:hive/hive.dart';

part 'user_profile.g.dart';

@HiveType(typeId: 0)
class UserProfile extends HiveObject {
  @HiveField(0)
  String name;

  @HiveField(1)
  String avatarPath;

  @HiveField(2)
  int starCount;

  @HiveField(3)
  double balance;

  @HiveField(4)
  DateTime? lastInterestDate;

  @HiveField(5)
  double interestRate;

  UserProfile({
    required this.name,
    required this.avatarPath,
    this.starCount = 0,
    this.balance = 0.0,
    this.lastInterestDate,
    this.interestRate = 0.05,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'avatarPath': avatarPath,
    'starCount': starCount,
    'balance': balance,
    'lastInterestDate': lastInterestDate?.toIso8601String(),
    'interestRate': interestRate,
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    name: json['name'],
    avatarPath: json['avatarPath'],
    starCount: json['starCount'] ?? 0,
    balance: (json['balance'] ?? 0).toDouble(),
    lastInterestDate: json['lastInterestDate'] != null
        ? DateTime.parse(json['lastInterestDate'])
        : null,
    interestRate: (json['interestRate'] ?? 0.05).toDouble(),
  );
}
