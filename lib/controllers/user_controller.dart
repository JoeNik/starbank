import 'package:get/get.dart';
import '../models/baby.dart';
import '../models/action_item.dart';
import '../models/log.dart';
import '../services/storage_service.dart';

class UserController extends GetxController {
  final StorageService _storage = Get.find<StorageService>();

  final RxList<Baby> babies = <Baby>[].obs;
  final Rx<Baby?> currentBaby = Rx<Baby?>(null);

  final RxList<ActionItem> actions = <ActionItem>[].obs;
  final RxList<Log> logs = <Log>[].obs;
  final RxString parentName = "星球家长".obs;
  final RxDouble currentInterestRate = 0.05.obs;

  @override
  void onInit() {
    super.onInit();
    _loadData();
  }

  void _loadData() {
    if (_storage.userBox.isNotEmpty) {
      final profile = _storage.userBox.getAt(0)!;
      parentName.value = profile.name;
      currentInterestRate.value = profile.interestRate;
    }

    babies.assignAll(_storage.babyBox.values);
    if (babies.isNotEmpty) {
      if (currentBaby.value == null) {
        currentBaby.value = babies[0];
      }
      _loadBabySpecificData();
    }

    actions.assignAll(_storage.actionBox.values);
  }

  void _loadBabySpecificData() {
    if (currentBaby.value == null) return;

    final babyId = currentBaby.value!.id;
    logs.assignAll(
      _storage.logBox.values.where((l) => l.babyId == babyId).toList().reversed,
    );

    _checkInterest();
  }

  void switchBaby(String id) {
    currentBaby.value = babies.firstWhere((b) => b.id == id);
    _loadBabySpecificData();
  }

  void addBaby(String name, String avatar) {
    final newBaby = Baby(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      avatarPath: avatar,
    );
    _storage.babyBox.add(newBaby);
    babies.add(newBaby);
    if (currentBaby.value == null) {
      switchBaby(newBaby.id);
    }
  }

  void editBaby(String name, String avatar) {
    if (currentBaby.value == null) return;
    currentBaby.value!.name = name;
    currentBaby.value!.avatarPath = avatar;
    currentBaby.value!.save();
    currentBaby.refresh();
    babies.refresh();
  }

  /// 删除宝宝及其相关数据
  void deleteBaby(String babyId) {
    if (babies.length <= 1) {
      Get.snackbar('提示', '至少保留一个宝宝');
      return;
    }

    // 查找并删除宝宝
    final babyIndex = babies.indexWhere((b) => b.id == babyId);
    if (babyIndex == -1) return;

    final baby = babies[babyIndex];

    // 删除相关日志
    final logsToDelete = _storage.logBox.values
        .where((l) => l.babyId == babyId)
        .toList();
    for (var log in logsToDelete) {
      log.delete();
    }

    // 删除相关商品
    final productsToDelete = _storage.productBox.values
        .where((p) => p.babyId == babyId)
        .toList();
    for (var product in productsToDelete) {
      product.delete();
    }

    // 删除宝宝
    baby.delete();
    babies.removeAt(babyIndex);

    // 切换到第一个宝宝
    if (currentBaby.value?.id == babyId && babies.isNotEmpty) {
      currentBaby.value = babies.first;
      _loadBabySpecificData();
    }

    Get.snackbar('成功', '宝宝已删除');
  }

  // Star Logic
  void updateStars(int change, String reason) {
    if (currentBaby.value == null) return;

    currentBaby.value!.starCount += change;
    currentBaby.value!.save();
    currentBaby.refresh();

    _addLog(change.toDouble(), reason, 'star');
  }

  // Wallet Logic: piggyBank and pocketMoney
  void updateWallet(double change, String reason, bool isPiggy) {
    if (currentBaby.value == null) return;

    if (isPiggy) {
      currentBaby.value!.piggyBankBalance += change;
    } else {
      currentBaby.value!.pocketMoneyBalance += change;
    }

    currentBaby.value!.save();
    currentBaby.refresh();

    _addLog(change, reason, isPiggy ? 'piggy' : 'pocket');
  }

  void transferToPiggy(double amount) {
    if (currentBaby.value == null ||
        currentBaby.value!.pocketMoneyBalance < amount)
      return;

    currentBaby.value!.pocketMoneyBalance -= amount;
    currentBaby.value!.piggyBankBalance += amount;

    currentBaby.value!.save();
    currentBaby.refresh();

    _addLog(-amount, "转入存钱罐", 'pocket');
    _addLog(amount, "从零花钱转入", 'piggy');
  }

  void _addLog(double change, String description, String type) {
    if (currentBaby.value == null) return;

    final log = Log(
      timestamp: DateTime.now(),
      description: description,
      changeAmount: change,
      type: type,
      babyId: currentBaby.value!.id,
    );
    _storage.logBox.add(log);
    logs.insert(0, log);
  }

  void _checkInterest() {
    if (currentBaby.value == null) return;
    final baby = currentBaby.value!;

    final lastDate = baby.lastInterestDate;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // First time init or reset if in future
    if (lastDate == null || lastDate.isAfter(today)) {
      baby.lastInterestDate = today;
      baby.save();
      return;
    }

    final last = DateTime(lastDate.year, lastDate.month, lastDate.day);
    final diff = today.difference(last).inDays;

    // DEBUG LOG
    // debugPrint("Checking interest: last=${last.toString()}, today=${today.toString()}, diff=$diff");

    if (diff > 0) {
      final rate = currentInterestRate.value;
      // Daily Interest = Principal * Rate / 365 * days
      final interest = baby.piggyBankBalance * rate * (diff / 365.0);

      if (interest > 0.001) {
        // Interest goes to Pocket Money
        baby.pocketMoneyBalance += interest;
        _addLog(
          interest,
          '存钱罐利息 ($diff 天)',
          'pocket',
        ); // Log as pocket money change
        // We also want to tag it specially so we can calculate total interest later
        // The current logic uses '利息' in description to filter.
      }

      baby.lastInterestDate = today;
      baby.save();
      if (currentBaby.value?.id == baby.id) {
        currentBaby.refresh();
      }
    }
  }

  double getYesterdayInterest() {
    if (currentBaby.value == null) return 0.0;
    final now = DateTime.now();
    final yesterday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 1));

    return logs
        .where(
          (l) =>
              l.description.contains('利息') &&
              l.timestamp.year == yesterday.year &&
              l.timestamp.month == yesterday.month &&
              l.timestamp.day == yesterday.day,
        )
        .fold(0.0, (sum, item) => sum + item.changeAmount);
  }

  double getTotalInterest() {
    if (currentBaby.value == null) return 0.0;
    return logs
        .where((l) => l.description.contains('利息'))
        .fold(0.0, (sum, item) => sum + item.changeAmount);
  }

  void updateParentName(String name) {
    parentName.value = name;
    if (_storage.userBox.isNotEmpty) {
      final profile = _storage.userBox.getAt(0)!;
      profile.name = name;
      profile.save();
    }
    parentName.refresh();
  }

  void updateInterestRate(double rate) {
    currentInterestRate.value = rate;
    if (_storage.userBox.isNotEmpty) {
      final profile = _storage.userBox.getAt(0)!;
      profile.interestRate = rate;
      profile.save();
    }
    currentInterestRate.refresh();
  }

  // Action Management
  void addAction(ActionItem item) {
    _storage.actionBox.add(item);
    actions.add(item);
  }

  void deleteAction(int index) {
    _storage.actionBox.deleteAt(index);
    actions.removeAt(index);
  }
}
