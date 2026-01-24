import 'package:hive/hive.dart';

part 'product.g.dart';

@HiveType(typeId: 3)
class Product extends HiveObject {
  @HiveField(0)
  String name;

  @HiveField(1)
  double price; // Target price

  @HiveField(2)
  String priceType; // 'money' or 'star'

  @HiveField(3)
  String imagePath;

  @HiveField(4)
  bool isRedeemed;

  @HiveField(5)
  String? babyId; // Which baby this belongs to

  Product({
    required this.name,
    required this.price,
    required this.priceType,
    required this.imagePath,
    this.isRedeemed = false,
    this.babyId,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'price': price,
    'priceType': priceType,
    'imagePath': imagePath,
    'isRedeemed': isRedeemed,
    'babyId': babyId,
  };

  factory Product.fromJson(Map<String, dynamic> json) => Product(
    name: json['name'],
    price: (json['price'] ?? 0).toDouble(),
    priceType: json['priceType'],
    imagePath: json['imagePath'],
    isRedeemed: json['isRedeemed'] ?? false,
    babyId: json['babyId'],
  );
}
