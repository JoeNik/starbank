import 'package:flutter/material.dart';
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
    logs.refresh(); // 强制刷新日志列表

    _checkInterest();
  }

  void switchBaby(String id) {
    currentBaby.value = babies.firstWhere((b) => b.id == id);
    currentBaby.refresh(); // 强制刷新
    babies.refresh(); // 刷新列表
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
    final logsToDelete =
        _storage.logBox.values.where((l) => l.babyId == babyId).toList();
    for (var log in logsToDelete) {
      log.delete();
    }

    // 删除相关商品
    final productsToDelete =
        _storage.productBox.values.where((p) => p.babyId == babyId).toList();
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
  void updateStars(int change, String reason, {bool silent = false}) {
    if (currentBaby.value == null) return;

    currentBaby.value!.starCount += change;
    currentBaby.value!.save();
    currentBaby.refresh();

    _addLog(change.toDouble(), reason, 'star');

    // 只在非静默模式下显示 Snackbar
    if (!silent) {
      Get.snackbar(
        change > 0 ? '⭐ 获得星星' : '⭐ 扣除星星',
        '$reason ${change > 0 ? '+' : ''}$change 颗星星',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 4),
        mainButton: TextButton(
          onPressed: () {
            revertLastStarAction();
            Get.back(); // 关闭 Snackbar
          },
          child: const Text(
            '撤销',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }
  }

  /// 撤销上一次星星变动操作
  Future<void> revertLastStarAction() async {
    if (currentBaby.value == null || logs.isEmpty) return;

    // 找到最近的一条属于当前宝宝的星星记录
    int index = -1;
    for (int i = 0; i < logs.length; i++) {
      if (logs[i].type == 'star' && logs[i].babyId == currentBaby.value!.id) {
        index = i;
        break;
      }
    }

    if (index != -1) {
      final logToRevert = logs[index];

      // 回滚星星
      currentBaby.value!.starCount -= logToRevert.changeAmount.toInt();
      currentBaby.value!.save();
      currentBaby.refresh();

      // 删除日志
      try {
        if (logToRevert.isInBox) {
          await logToRevert.delete();
        }
      } catch (e) {
        debugPrint("Error deleting log: $e");
      }

      logs.removeAt(index);
    }
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
        currentBaby.value!.pocketMoneyBalance < amount) return;

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

  /// 检查并计算利息
  /// 使用 'interest' 类型标记利息记录，按日期判断是否已产生收益
  /// 支持补算多天未打开 APP 期间的利息
  void _checkInterest() {
    if (currentBaby.value == null) return;
    final baby = currentBaby.value!;

    // 没有存款则不产生利息
    if (baby.piggyBankBalance <= 0) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 查找该宝宝最近一次利息记录的日期
    DateTime? lastInterestDate;
    final interestLogs = _storage.logBox.values
        .where((log) => log.babyId == baby.id && log.type == 'interest')
        .toList();

    if (interestLogs.isNotEmpty) {
      // 按时间排序，取最新的一条
      interestLogs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final latest = interestLogs.first;
      lastInterestDate = DateTime(
        latest.timestamp.year,
        latest.timestamp.month,
        latest.timestamp.day,
      );
    }

    // 如果今天已经有利息记录，不重复计算
    if (lastInterestDate != null &&
        lastInterestDate.year == today.year &&
        lastInterestDate.month == today.month &&
        lastInterestDate.day == today.day) {
      return;
    }

    // 计算需要补算的天数
    // 起始日期：上次利息记录的下一天；如果没有历史记录，则只算今天（1天）
    final startDate = lastInterestDate != null
        ? lastInterestDate.add(const Duration(days: 1))
        : today;

    // 从 startDate 到 today（包含 today），计算每一天的利息
    final rate = currentInterestRate.value;
    final dailyRate = rate / 365.0; // 日利率 = 年化利率 / 365
    double totalInterest = 0;

    // 用当前余额统一计算（简化处理，避免复杂的逐日余额追溯）
    DateTime currentDate = startDate;
    while (!currentDate.isAfter(today)) {
      final interest = baby.piggyBankBalance * dailyRate;

      if (interest > 0.001) {
        totalInterest += interest;

        // 为每一天创建独立的利息记录，时间戳使用对应日期
        final log = Log(
          timestamp: currentDate,
          description: '存钱罐利息收益',
          changeAmount: interest,
          type: 'interest', // 专门的利息类型
          babyId: baby.id,
        );
        _storage.logBox.add(log);
        logs.insert(0, log);
      }

      currentDate = currentDate.add(const Duration(days: 1));
    }

    // 一次性将累计利息计入零花钱
    if (totalInterest > 0.001) {
      baby.pocketMoneyBalance += totalInterest;
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
              l.type == 'interest' &&
              l.timestamp.year == yesterday.year &&
              l.timestamp.month == yesterday.month &&
              l.timestamp.day == yesterday.day,
        )
        .fold(0.0, (sum, item) => sum + item.changeAmount);
  }

  double getTotalInterest() {
    if (currentBaby.value == null) return 0.0;
    return logs
        .where((l) => l.type == 'interest')
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

  /// 更新快捷记录
  void updateAction(int index, String name, double value, String iconName) {
    if (index < 0 || index >= actions.length) return;

    final action = actions[index];
    action.name = name;
    action.value = value;
    action.iconName = iconName;
    action.type = value > 0 ? 'reward' : 'punish';
    action.save();
    actions.refresh();
  }

  /// 重新排序快捷记录
  void reorderAction(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final item = actions.removeAt(oldIndex);
    actions.insert(newIndex, item);

    // 重新保存到 Hive（需要清空后重新添加来保持顺序）
    _storage.actionBox.clear();
    for (var action in actions) {
      _storage.actionBox.add(action);
    }
    actions.refresh();
  }
}
