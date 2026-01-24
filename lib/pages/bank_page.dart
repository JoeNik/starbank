import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../controllers/user_controller.dart';
import '../theme/app_theme.dart';
import 'wallet_details_page.dart';

class BankPage extends StatelessWidget {
  const BankPage({super.key});

  @override
  Widget build(BuildContext context) {
    final UserController controller = Get.find<UserController>();

    return Scaffold(
      backgroundColor: AppTheme.bgBlue,
      appBar: AppBar(title: const Text("我的银行")),
      body: SafeArea(
        child: Obx(() {
          final baby = controller.currentBaby.value;
          if (baby == null) return const Center(child: Text("请先选择或添加宝宝"));

          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                _buildWalletCard(
                  controller: controller,
                  title: "存钱罐",
                  balance: baby.piggyBankBalance,
                  icon: '🏦', // 使用 emoji 图标
                  color: Colors.orange.shade300,
                  isPiggy: true,
                  subtitle: "年化利率: 5%",
                ),
                _buildWalletCard(
                  controller: controller,
                  title: "零花钱",
                  balance: baby.pocketMoneyBalance,
                  icon: '💰', // 使用 emoji 图标
                  color: Colors.lightBlue.shade300,
                  isPiggy: false,
                  subtitle: "收益计入此钱包",
                ),
                _buildInterestCalculator(controller),
                _buildLogSection(controller),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildWalletCard({
    required UserController controller,
    required String title,
    required double balance,
    required String icon,
    required Color color,
    required bool isPiggy,
    required String subtitle,
  }) {
    return GestureDetector(
      onTap: () => Get.to(() => WalletDetailsPage(isPiggy: isPiggy)),
      child: Container(
        margin: EdgeInsets.all(16.w),
        padding: EdgeInsets.all(20.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32.r),
          border: Border.all(color: color.withOpacity(0.2), width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Image.asset(
                  icon,
                  width: 48.w,
                  height: 48.w,
                  errorBuilder: (_, __, ___) => Text(
                    icon,
                    style: TextStyle(fontSize: 32.sp),
                  ),
                ),
                SizedBox(width: 15.w),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textMain,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: AppTheme.textSub,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      "¥${balance.toStringAsFixed(2)}",
                      style: TextStyle(
                        fontSize: 24.sp,
                        fontWeight: FontWeight.w900,
                        color: color,
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          "查看明细",
                          style: TextStyle(fontSize: 10.sp, color: Colors.grey),
                        ),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 10.sp,
                          color: Colors.grey,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: 20.h),
            Row(
              children: [
                Expanded(
                  child: _buildMiniButton(
                    onTap: () =>
                        _showWalletDialog(controller, title, true, isPiggy),
                    label: "存入",
                    color: color,
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: _buildMiniButton(
                    onTap: () =>
                        _showWalletDialog(controller, title, false, isPiggy),
                    label: "取出",
                    color: Colors.grey.shade400,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniButton({
    required VoidCallback onTap,
    required String label,
    required Color color,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 10.h),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16.r),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  Widget _buildInterestCalculator(UserController controller) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16.w),
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.6),
        borderRadius: BorderRadius.circular(24.r),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.calculate_rounded, color: AppTheme.textSub),
              SizedBox(width: 8.w),
              Obx(
                () => Text(
                  "利息收益 (年化 ${(controller.currentInterestRate.value * 100).toStringAsFixed(1)}%)",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textMain,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Obx(
                () => _buildCalcItem(
                  "昨日收益",
                  "¥${controller.getYesterdayInterest().toStringAsFixed(2)}",
                ),
              ),
              Obx(
                () => _buildCalcItem(
                  "累计收益",
                  "¥${controller.getTotalInterest().toStringAsFixed(2)}",
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCalcItem(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11.sp, color: AppTheme.textSub),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.w900,
            color: AppTheme.primaryDark,
          ),
        ),
      ],
    );
  }

  Widget _buildLogSection(UserController controller) {
    return Padding(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "收支记录",
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.w900,
              color: AppTheme.textMain,
            ),
          ),
          SizedBox(height: 12.h),
          Obx(() {
            final moneyLogs = controller.logs
                .where((l) => l.type == 'piggy' || l.type == 'pocket')
                .toList();
            if (moneyLogs.isEmpty) return const Center(child: Text("还没有记录哦"));
            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: moneyLogs.length > 10 ? 10 : moneyLogs.length,
              itemBuilder: (context, index) {
                final log = moneyLogs[index];
                return _buildMoneyLogItem(log);
              },
            );
          }),
        ],
      ),
    );
  }

  Widget _buildMoneyLogItem(log) {
    final isPositive = log.changeAmount > 0;
    final isPiggy = log.type == 'piggy';
    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(6.w),
            decoration: BoxDecoration(
              color: isPiggy
                  ? Colors.orange.withOpacity(0.1)
                  : Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Icon(
              isPiggy ? Icons.savings : Icons.account_balance_wallet,
              size: 14.sp,
              color: isPiggy ? Colors.orange : Colors.blue,
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.description,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.sp,
                  ),
                ),
                Text(
                  "${log.timestamp.year}-${log.timestamp.month}-${log.timestamp.day}",
                  style: TextStyle(fontSize: 10.sp, color: Colors.grey),
                ),
              ],
            ),
          ),
          Text(
            "${isPositive ? '+' : ''}${log.changeAmount.toStringAsFixed(2)}",
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w900,
              color: isPositive ? Colors.green : Colors.red,
            ),
          ),
        ],
      ),
    );
  }

  void _showWalletDialog(
    UserController controller,
    String title,
    bool isDeposit,
    bool isPiggy,
  ) {
    final amountController = TextEditingController();
    final reasonController = TextEditingController();

    Get.defaultDialog(
      title: "$title - ${isDeposit ? '存入' : '取出'}",
      content: Column(
        children: [
          TextField(
            controller: amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: "金额 (¥)"),
          ),
          TextField(
            controller: reasonController,
            decoration: const InputDecoration(labelText: "备注原因"),
          ),
        ],
      ),
      onConfirm: () {
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
      textConfirm: "确定",
      textCancel: "取消",
    );
  }
}
