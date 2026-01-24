import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../controllers/user_controller.dart';
import '../theme/app_theme.dart';
import 'package:intl/intl.dart';

class WalletDetailsPage extends StatelessWidget {
  final bool isPiggy;

  const WalletDetailsPage({super.key, required this.isPiggy});

  @override
  Widget build(BuildContext context) {
    final UserController controller = Get.find<UserController>();
    final title = isPiggy ? "存钱罐" : "零花钱";
    final themeColor = isPiggy ? Colors.orange : Colors.blue;

    return Scaffold(
      backgroundColor: isPiggy ? Colors.orange.shade50 : Colors.blue.shade50,
      appBar: AppBar(
        title: Text("$title明细"),
        backgroundColor: themeColor,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(controller, title, themeColor),
            Expanded(child: _buildTransactionList(controller, themeColor)),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomActions(controller, title, themeColor),
    );
  }

  Widget _buildHeader(UserController controller, String title, Color color) {
    return Container(
      padding: EdgeInsets.all(24.w),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32.r),
          bottomRight: Radius.circular(32.r),
        ),
      ),
      child: Column(
        children: [
          Text(
            "当前余额",
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 14.sp,
            ),
          ),
          SizedBox(height: 10.h),
          Obx(() {
            final baby = controller.currentBaby.value;
            final balance = baby == null
                ? 0.0
                : (isPiggy ? baby.piggyBankBalance : baby.pocketMoneyBalance);
            return Text(
              "¥${balance.toStringAsFixed(2)}",
              style: TextStyle(
                color: Colors.white,
                fontSize: 36.sp,
                fontWeight: FontWeight.w900,
              ),
            );
          }),
          if (isPiggy) ...[
            SizedBox(height: 10.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Obx(
                () => Text(
                  "年化利率: ${(controller.currentInterestRate.value * 100).toStringAsFixed(1)}%",
                  style: TextStyle(color: Colors.white, fontSize: 12.sp),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTransactionList(UserController controller, Color themeColor) {
    return Obx(() {
      final babyId = controller.currentBaby.value?.id;
      if (babyId == null) return const SizedBox();

      final type = isPiggy ? 'piggy' : 'pocket';
      final logs = controller.logs
          .where((l) => l.babyId == babyId && l.type == type)
          .toList();

      if (logs.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.history, size: 60.sp, color: Colors.grey.shade300),
              SizedBox(height: 10.h),
              Text("暂无交易记录", style: TextStyle(color: Colors.grey.shade400)),
            ],
          ),
        );
      }

      return ListView.builder(
        padding: EdgeInsets.all(16.w),
        physics: const BouncingScrollPhysics(),
        itemCount: logs.length,
        itemBuilder: (context, index) {
          final log = logs[index];
          final isPositive = log.changeAmount > 0;
          return Container(
            margin: EdgeInsets.only(bottom: 12.h),
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16.r),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(10.w),
                  decoration: BoxDecoration(
                    color: isPositive
                        ? Colors.green.withOpacity(0.1)
                        : Colors.red.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPositive ? Icons.add : Icons.remove,
                    color: isPositive ? Colors.green : Colors.red,
                    size: 20.sp,
                  ),
                ),
                SizedBox(width: 16.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        log.description,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15.sp,
                          color: AppTheme.textMain,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        DateFormat('yyyy-MM-dd HH:mm').format(log.timestamp),
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: AppTheme.textSub,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  "${isPositive ? '+' : ''}${log.changeAmount.toStringAsFixed(2)}",
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.bold,
                    color: isPositive ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
          );
        },
      );
    });
  }

  Widget _buildBottomActions(
    UserController controller,
    String title,
    Color color,
  ) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () => _showWalletDialog(controller, title, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                ),
                child: const Text("存入"),
              ),
            ),
            SizedBox(width: 16.w),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _showWalletDialog(controller, title, false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color),
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                ),
                child: const Text("取出"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showWalletDialog(
    UserController controller,
    String title,
    bool isDeposit,
  ) {
    final amountController = TextEditingController();
    final reasonController = TextEditingController();

    Get.bottomSheet(
      Container(
        padding: EdgeInsets.all(24.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32.r)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "$title - ${isDeposit ? '存入' : '取出'}",
              style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20.h),
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              autofocus: true,
              style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                prefixText: "¥ ",
                labelText: "金额",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
              ),
            ),
            SizedBox(height: 16.h),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                labelText: "备注原因 (选填)",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
              ),
            ),
            SizedBox(height: 24.h),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final amount = double.tryParse(amountController.text) ?? 0;
                  if (amount > 0) {
                    final reason = reasonController.text.isEmpty
                        ? (isDeposit ? "手动存入" : "手动取出")
                        : reasonController.text;
                    controller.updateWallet(
                      isDeposit ? amount : -amount,
                      reason,
                      isPiggy,
                    );
                    Get.back();
                  }
                },
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 16.h),
                  backgroundColor: isDeposit ? Colors.green : Colors.redAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                ),
                child: Text(
                  "确认${isDeposit ? '存入' : '取出'}",
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            SizedBox(height: 10.h),
          ],
        ),
      ),
    );
  }
}
