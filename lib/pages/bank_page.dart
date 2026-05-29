import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../controllers/user_controller.dart';
import '../controllers/app_mode_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/image_utils.dart';
import '../widgets/module_background_scene.dart';
import 'wallet_details_page.dart';

class BankPage extends StatefulWidget {
  const BankPage({super.key});

  @override
  State<BankPage> createState() => _BankPageState();
}

class _BankPageState extends State<BankPage> {
  // 收支记录是否展开
  bool _isMoneyLogsExpanded = false;
  // 收支记录显示数量
  int _moneyLogsPageSize = 10;

  @override
  Widget build(BuildContext context) {
    final UserController controller = Get.find<UserController>();
    final AppModeController modeController = Get.find<AppModeController>();

    return Scaffold(
      backgroundColor: AppTheme.bgBlue,
      appBar: AppBar(
        title: Obx(() {
          final baby = controller.currentBaby.value;
          if (baby == null) return const Text("我的银行");
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32.w,
                height: 32.w,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: ClipOval(
                  child: ImageUtils.displayImage(
                    baby.avatarPath,
                    width: 32.w,
                    height: 32.w,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              SizedBox(width: 10.w),
              Text("${baby.name}的银行"),
            ],
          );
        }),
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: ModuleBackgroundScene(theme: ModuleBackgroundTheme.bank),
          ),
          SafeArea(
            child: Obx(() {
              final baby = controller.currentBaby.value;
              if (baby == null) {
                return const Center(child: Text("请先在主页选择宝宝"));
              }

              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    _buildWalletCard(
                      controller: controller,
                      modeController: modeController,
                      title: "存钱罐",
                      balance: baby.piggyBankBalance,
                      icon: '🏦', // 使用 emoji 图标
                      color: Colors.orange.shade300,
                      isPiggy: true,
                      subtitle: "年化利率: 5%",
                    ),
                    _buildWalletCard(
                      controller: controller,
                      modeController: modeController,
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
        ],
      ),
    );
  }

  Widget _buildWalletCard({
    required UserController controller,
    required AppModeController modeController,
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
                // 直接使用 Text 显示 emoji
                Container(
                  width: 48.w,
                  height: 48.w,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16.r),
                  ),
                  child: Center(
                    child: Text(
                      icon,
                      style: TextStyle(fontSize: 28.sp),
                    ),
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
                    onTap: () {
                      if (modeController.isChildMode) {
                        Get.snackbar('👀 只能看哦', '让爸爸妈妈来存钱吧~');
                        return;
                      }
                      _showWalletDialog(controller, title, true, isPiggy);
                    },
                    label: "存入",
                    color: color,
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: _buildMiniButton(
                    onTap: () {
                      if (modeController.isChildMode) {
                        Get.snackbar('👀 只能看哦', '让爸爸妈妈来取钱吧~');
                        return;
                      }
                      _showWalletDialog(controller, title, false, isPiggy);
                    },
                    label: "取出",
                    color: Colors.orange.shade400,
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(24.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8.w),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Text('💰', style: TextStyle(fontSize: 20.sp)),
              ),
              SizedBox(width: 12.w),
              Text(
                "利息收益",
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textMain,
                ),
              ),
              const Spacer(),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Obx(() => Text(
                      "年化 ${(controller.currentInterestRate.value * 100).toStringAsFixed(1)}%",
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: Colors.blue,
                        fontWeight: FontWeight.w600,
                      ),
                    )),
              ),
            ],
          ),
          SizedBox(height: 16.h),
          // 收益数据
          Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.amber.shade50,
                  Colors.orange.shade50,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16.r),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Obx(() => _buildCalcItem(
                      "昨日收益",
                      "¥${controller.getYesterdayInterest().toStringAsFixed(2)}",
                      Colors.orange,
                    )),
                Container(
                  width: 1,
                  height: 40.h,
                  color: Colors.orange.withOpacity(0.2),
                ),
                Obx(() => _buildCalcItem(
                      "累计收益",
                      "¥${controller.getTotalInterest().toStringAsFixed(2)}",
                      Colors.green,
                    )),
              ],
            ),
          ),
          SizedBox(height: 12.h),
          // 收益计算器按钮
          TextButton.icon(
            onPressed: () => _showInterestCalculatorDialog(controller),
            icon: const Icon(Icons.calculate_rounded, size: 18),
            label: const Text('收益计算器'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.blue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalcItem(String label, String value, Color color) {
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
            color: color,
          ),
        ),
      ],
    );
  }

  /// 收益计算器对话框
  void _showInterestCalculatorDialog(UserController controller) {
    final amountController = TextEditingController();
    final RxDouble rate = controller.currentInterestRate.value.obs;
    final RxDouble dailyProfit = 0.0.obs;
    final RxDouble monthlyProfit = 0.0.obs;
    final RxDouble yearlyProfit = 0.0.obs;

    void calculate() {
      final amount = double.tryParse(amountController.text) ?? 0;
      final r = rate.value;
      yearlyProfit.value = amount * r;
      monthlyProfit.value = yearlyProfit.value / 12;
      dailyProfit.value = yearlyProfit.value / 365;
    }

    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24.r),
        ),
        child: Container(
          padding: EdgeInsets.all(24.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题
              Row(
                children: [
                  Text('💰', style: TextStyle(fontSize: 24.sp)),
                  SizedBox(width: 10.w),
                  Text(
                    '收益计算器',
                    style: TextStyle(
                      fontSize: 20.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Get.back(),
                  ),
                ],
              ),
              Text(
                '预估您的储蓄收益',
                style: TextStyle(color: Colors.grey, fontSize: 13.sp),
              ),
              SizedBox(height: 20.h),

              // 存入金额
              Container(
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(16.r),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '存入金额',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14.sp,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    TextField(
                      controller: amountController,
                      keyboardType:
                          TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(
                          fontSize: 24.sp, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        prefixText: '¥ ',
                        prefixStyle: TextStyle(
                          fontSize: 24.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                        hintText: '0',
                        border: InputBorder.none,
                      ),
                      onChanged: (_) => calculate(),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12.h),

              // 年化利率
              Container(
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(16.r),
                ),
                child: Row(
                  children: [
                    Text(
                      '年化利率',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14.sp,
                      ),
                    ),
                    const Spacer(),
                    Obx(() => Text(
                          '${(rate.value * 100).toStringAsFixed(1)}',
                          style: TextStyle(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.bold,
                          ),
                        )),
                    SizedBox(width: 4.w),
                    Text(
                      '%',
                      style: TextStyle(
                        fontSize: 16.sp,
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Column(
                      children: [
                        GestureDetector(
                          onTap: () {
                            if (rate.value < 0.20) {
                              rate.value += 0.005;
                              calculate();
                            }
                          },
                          child: Icon(Icons.arrow_drop_up, size: 20.sp),
                        ),
                        GestureDetector(
                          onTap: () {
                            if (rate.value > 0.005) {
                              rate.value -= 0.005;
                              calculate();
                            }
                          },
                          child: Icon(Icons.arrow_drop_down, size: 20.sp),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16.h),

              // 收益预估
              Container(
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade50, Colors.purple.shade50],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16.r),
                ),
                child: Column(
                  children: [
                    Obx(() => _buildProfitRow('日收益', dailyProfit.value)),
                    Divider(height: 16.h),
                    Obx(() => _buildProfitRow('月收益', monthlyProfit.value)),
                    Divider(height: 16.h),
                    Obx(() => _buildProfitRow('年收益', yearlyProfit.value)),
                  ],
                ),
              ),
              SizedBox(height: 12.h),

              // 提示
              Row(
                children: [
                  Icon(Icons.lightbulb_outline,
                      size: 14.sp, color: Colors.amber),
                  SizedBox(width: 6.w),
                  Expanded(
                    child: Text(
                      '实际收益以每日结算为准\n收益将自动加入零花钱余额',
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: Colors.grey,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfitRow(String label, double value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: AppTheme.textSub)),
        Text(
          '¥${value.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
      ],
    );
  }

  Widget _buildLogSection(UserController controller) {
    return Card(
      margin: EdgeInsets.all(16.w),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Column(
        children: [
          // 标题栏 - 可点击折叠/展开
          InkWell(
            onTap: () {
              setState(() {
                _isMoneyLogsExpanded = !_isMoneyLogsExpanded;
              });
            },
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(16.r),
              bottom:
                  _isMoneyLogsExpanded ? Radius.zero : Radius.circular(16.r),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
              child: Row(
                children: [
                  Icon(
                    Icons.receipt_long,
                    color: AppTheme.primary,
                    size: 20.sp,
                  ),
                  SizedBox(width: 8.w),
                  Text(
                    "收支记录",
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textMain,
                    ),
                  ),
                  const Spacer(),
                  // 展开/收起图标
                  Icon(
                    _isMoneyLogsExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppTheme.textSub,
                  ),
                ],
              ),
            ),
          ),
          // 记录列表 - 可折叠
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 12.h),
              child: Obx(() {
                // 包含存钱罐、零花钱和利息记录
                final moneyLogs = controller.logs
                    .where((l) =>
                        l.type == 'piggy' ||
                        l.type == 'pocket' ||
                        l.type == 'interest')
                    .toList();
                if (moneyLogs.isEmpty) {
                  return Padding(
                    padding: EdgeInsets.all(20.h),
                    child: const Center(child: Text("还没有记录哦")),
                  );
                }
                final displayCount = moneyLogs.length > _moneyLogsPageSize
                    ? _moneyLogsPageSize
                    : moneyLogs.length;
                return Column(
                  children: [
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: displayCount,
                      itemBuilder: (context, index) {
                        final log = moneyLogs[index];
                        return _buildMoneyLogItem(log);
                      },
                    ),
                    // 加载更多按钮
                    if (moneyLogs.length > _moneyLogsPageSize)
                      Padding(
                        padding: EdgeInsets.only(top: 8.h),
                        child: TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _moneyLogsPageSize += 10;
                            });
                          },
                          icon: const Icon(Icons.expand_more),
                          label: Text(
                            '加载更多 (还有 ${moneyLogs.length - _moneyLogsPageSize} 条)',
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.primary,
                          ),
                        ),
                      ),
                  ],
                );
              }),
            ),
            crossFadeState: _isMoneyLogsExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 300),
          ),
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
