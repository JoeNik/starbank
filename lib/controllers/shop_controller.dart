import 'package:get/get.dart';
import '../models/product.dart';
import '../services/storage_service.dart';
import 'user_controller.dart';

class ShopController extends GetxController {
  StorageService get _storage => Get.find<StorageService>();
  UserController get _userController => Get.find<UserController>();

  final RxList<Product> products = <Product>[].obs;

  @override
  void onInit() {
    super.onInit();
    _loadProducts();
    ever(_userController.currentBaby, (_) => _loadProducts());
  }

  void _loadProducts() {
    final baby = _userController.currentBaby.value;
    if (baby == null) {
      products.clear();
      return;
    }
    // Filter products for the current baby
    products.assignAll(
      _storage.productBox.values.where((p) => p.babyId == baby.id).toList(),
    );
  }

  void addProduct(Product product) {
    if (_userController.currentBaby.value != null && product.babyId == null) {
      product.babyId = _userController.currentBaby.value!.id;
    }
    _storage.productBox.add(product);
    _loadProducts();
  }

  void deleteProduct(int index) {
    _storage.productBox.deleteAt(index);
    products.removeAt(index);
  }

  bool canAfford(Product product) {
    if (_userController.currentBaby.value == null) return false;
    final baby = _userController.currentBaby.value!;

    if (product.priceType == 'star') {
      return baby.starCount >= product.price;
    } else {
      // Usually spend from Pocket Money
      return baby.pocketMoneyBalance >= product.price;
    }
  }

  double getProgress(Product product) {
    if (_userController.currentBaby.value == null) return 0.0;
    final baby = _userController.currentBaby.value!;

    double current = 0;
    if (product.priceType == 'star') {
      current = baby.starCount.toDouble();
    } else {
      current = baby.pocketMoneyBalance;
    }

    if (current >= product.price) return 1.0;
    return current / product.price;
  }

  void redeemProduct(int index) {
    final product = products[index];

    if (!canAfford(product)) {
      Get.snackbar('余额不足', '你的星星或零花钱不够哦！');
      return;
    }

    if (product.priceType == 'star') {
      _userController.updateStars(
        -product.price.toInt(),
        '兑换: ${product.name}',
        silent: true, // 避免重复弹框,使用商店自己的成功提示
      );
    } else {
      _userController.updateWallet(
        -product.price,
        '兑换: ${product.name}',
        false,
      );
    }

    product.isRedeemed = true;
    product.save();
    products.refresh(); // Update UI
    Get.snackbar('兑换成功', '恭喜你获得了 ${product.name}！');
  }

  void resetProduct(int index) {
    final product = products[index];
    product.isRedeemed = false;
    product.save();
    products.refresh();
  }
}
