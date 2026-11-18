import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../controllers/user_controller.dart';
import '../controllers/app_mode_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/image_utils.dart';
import '../widgets/memphis_widgets.dart';
import '../widgets/module_background_scene.dart';
import 'wallet_details_page.dart';

/// 孟菲斯（Memphis Milano）风格银行模块主页面
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
      backgroundColor: AppTheme.cream,
      appBar: AppBar(
        title: Obx(() {
          final baby = controller.currentBaby.value;
          if (baby == null) return const Text("我的银行");
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34.w,
                height: 34.w,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.yellow,
                  border: AppTheme.border(),
                  boxShadow: AppTheme.paperShadow(h: 8.0),
                ),
                child: ClipOval(
                  child: ImageUtils.displayImage(
                    baby.avatarPath,
                    width: 30.w,
                    height: 30.w,
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
                      icon: '🏦',
                      color: AppTheme.yellow,
                      isPiggy: true,
                      subtitle: "年化利率: 5%",
                    ),
                    _buildWalletCard(
                      controller: controller,
                      modeController: modeController,
                      title: "零花钱",
                      balance: baby.pocketMoneyBalance,
                      icon: '💰',
                      color: AppTheme.teal,
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

  /// 构建孟菲斯风格账户卡片（白底 + 粗黑描边 + 硬投影 + 撞色图标与金额牌）
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
        margin: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 8.h),
        padding: EdgeInsets.all(18.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22.r),
          border: AppTheme.border(),
          boxShadow: AppTheme.paperShadow(h: 8.0),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 50.w,
                  height: 50.w,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(14.r),
                    border: AppTheme.border(),
                    boxShadow: AppTheme.paperShadow(h: 8.0),
                  ),
                  child: Center(
                    child: Text(
                      icon,
                      style: TextStyle(fontSize: 26.sp),
                    ),
                  ),
                ),
                SizedBox(width: 14.w),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.ink,
                      ),
                    ),
                    SizedBox(height: 3.h),
                    MemphisTag(
                      text: subtitle,
                      color: isPiggy ? AppTheme.yellowSoft : AppTheme.tealSoft,
                      tiltDeg: isPiggy ? -2.5 : 2.5,
                      fontSize: 10.5.sp,
                      padding:
                          EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                      shadowOffset: 1.5,
                    ),
                  ],
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(10.r),
                        border: AppTheme.border(),
                      ),
                      child: Text(
                        "¥${balance.toStringAsFixed(2)}",
                        style: TextStyle(
                          fontSize: 20.sp,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.ink,
                        ),
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Row(
                      children: [
                        Text(
                          "查看明细",
                          style: TextStyle(
                            fontSize: 11.sp,
                            color: AppTheme.textSub,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 11.sp,
                          color: AppTheme.ink,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: 16.h),
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
                    label: "存入 +",
                    color: color,
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: _buildMiniButton(
                    onTap: () {
                      if (modeController.isChildMode) {
                        Get.snackbar('👀 只能看哦', '让爸爸妈妈来取钱吧~');
                        return;
                      }
                      _showWalletDialog(controller, title, false, isPiggy);
                    },
                    label: "取出 -",
                    color: AppTheme.pinkSoft,
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
    return MemphisButton(
      text: label,
      color: color,
      textColor: AppTheme.ink,
      borderRadius: 14.r,
      shadowOffset: 3.5,
      fontSize: 14.sp,
      padding: EdgeInsets.symmetric(vertical: 10.h),
      onTap: onTap,
    );
  }

  /// 构建孟菲斯风格利息收益与计算器卡片
  Widget _buildInterestCalculator(UserController controller) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      padding: EdgeInsets.all(18.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22.r),
        border: AppTheme.border(),
        boxShadow: AppTheme.paperShadow(h: 8.0),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8.w),
                decoration: BoxDecoration(
                  color: AppTheme.pink,
                  borderRadius: BorderRadius.circular(12.r),
                  border: AppTheme.border(),
                  boxShadow: AppTheme.paperShadow(h: 8.0),
                ),
                child: Text('📈', style: TextStyle(fontSize: 18.sp)),
              ),
              SizedBox(width: 12.w),
              Text(
                "利息收益",
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.ink,
                ),
              ),
              const Spacer(),
              Obx(() => MemphisTag(
                    text:
                        "年化 ${(controller.currentInterestRate.value * 100).toStringAsFixed(1)}%",
                    color: AppTheme.yellow,
                    tiltDeg: -4.0,
                    fontSize: 11.5.sp,
                  )),
            ],
          ),
          SizedBox(height: 16.h),
          // 收益数据
          Container(
            padding: EdgeInsets.all(14.w),
            decoration: BoxDecoration(
              color: AppTheme.cream,
              borderRadius: BorderRadius.circular(16.r),
              border: AppTheme.border(),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Obx(() => _buildCalcItem(
                      "昨日收益",
                      "¥${controller.getYesterdayInterest().toStringAsFixed(2)}",
                      AppTheme.tomato,
                    )),
                Container(
                  width: 2,
                  height: 36.h,
                  color: AppTheme.ink,
                ),
                Obx(() => _buildCalcItem(
                      "累计收益",
                      "¥${controller.getTotalInterest().toStringAsFixed(2)}",
                      AppTheme.teal,
                    )),
              ],
            ),
          ),
          SizedBox(height: 12.h),
          // 收益计算器按钮
          MemphisButton(
            text: '🧮 打开收益计算器',
            color: AppTheme.lilacSoft,
            borderRadius: 12.r,
            shadowOffset: 3.0,
            fontSize: 13.sp,
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
            onTap: () => _showInterestCalculatorDialog(controller),
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
          style: TextStyle(
            fontSize: 11.5.sp,
            color: AppTheme.textSub,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: 2.h),
        Text(
          value,
          style: TextStyle(
            fontSize: 17.sp,
            fontWeight: FontWeight.w900,
            color: AppTheme.ink,
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
        backgroundColor: AppTheme.cream,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24.r),
          side: const BorderSide(color: AppTheme.ink, width: 3.0),
        ),
        child: Container(
          padding: EdgeInsets.all(22.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text('💰', style: TextStyle(fontSize: 24.sp)),
                  SizedBox(width: 10.w),
                  Text(
                    '收益计算器',
                    style: TextStyle(
                      fontSize: 20.sp,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.ink,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppTheme.ink),
                    onPressed: () => Get.back(),
                  ),
                ],
              ),
              Text(
                '预估您的储蓄收益',
                style: TextStyle(
                  color: AppTheme.textSub,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 18.h),
              Container(
                padding: EdgeInsets.all(14.w),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16.r),
                  border: AppTheme.border(),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '存入金额',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5.sp,
                        color: AppTheme.ink,
                      ),
                    ),
                    SizedBox(height: 6.h),
                    TextField(
                      controller: amountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(
                        fontSize: 24.sp,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.ink,
                      ),
                      decoration: InputDecoration(
                        prefixText: '¥ ',
                        prefixStyle: TextStyle(
                          fontSize: 24.sp,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.ink,
                        ),
                        hintText: '0',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                      onChanged: (_) => calculate(),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12.h),
              Container(
                padding: EdgeInsets.all(14.w),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16.r),
                  border: AppTheme.border(),
                ),
                child: Row(
                  children: [
                    Text(
                      '年化利率',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5.sp,
                        color: AppTheme.ink,
                      ),
                    ),
                    const Spacer(),
                    Obx(() => Text(
                          (rate.value * 100).toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.ink,
                          ),
                        )),
                    SizedBox(width: 4.w),
                    Text(
                      '%',
                      style: TextStyle(
                        fontSize: 16.sp,
                        color: AppTheme.cobalt,
                        fontWeight: FontWeight.w900,
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
                          child: Icon(Icons.arrow_drop_up, size: 22.sp),
                        ),
                        GestureDetector(
                          onTap: () {
                            if (rate.value > 0.005) {
                              rate.value -= 0.005;
                              calculate();
                            }
                          },
                          child: Icon(Icons.arrow_drop_down, size: 22.sp),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: 14.h),
              Container(
                padding: EdgeInsets.all(14.w),
                decoration: BoxDecoration(
                  color: AppTheme.yellowSoft,
                  borderRadius: BorderRadius.circular(16.r),
                  border: AppTheme.border(),
                ),
                child: Column(
                  children: [
                    Obx(() => _buildProfitRow('日收益', dailyProfit.value)),
                    Divider(height: 14.h, color: AppTheme.ink),
                    Obx(() => _buildProfitRow('月收益', monthlyProfit.value)),
                    Divider(height: 14.h, color: AppTheme.ink),
                    Obx(() => _buildProfitRow('年收益', yearlyProfit.value)),
                  ],
                ),
              ),
              SizedBox(height: 12.h),
              Row(
                children: [
                  Icon(Icons.lightbulb_rounded,
                      size: 15.sp, color: AppTheme.tomato),
                  SizedBox(width: 6.w),
                  Expanded(
                    child: Text(
                      '实际收益以每日结算为准，将自动计入零花钱余额',
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: AppTheme.textSub,
                        fontWeight: FontWeight.w700,
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
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          '¥${value.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.w900,
            color: AppTheme.cobalt,
          ),
        ),
      ],
    );
  }

  Widget _buildLogSection(UserController controller) {
    return Container(
      margin: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22.r),
        border: AppTheme.border(),
        boxShadow: AppTheme.paperShadow(h: 8.0),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _isMoneyLogsExpanded = !_isMoneyLogsExpanded;
              });
            },
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(22.r),
              bottom:
                  _isMoneyLogsExpanded ? Radius.zero : Radius.circular(22.r),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(6.w),
                    decoration: BoxDecoration(
                      color: AppTheme.yellow,
                      borderRadius: BorderRadius.circular(10.r),
                      border: AppTheme.border(),
                    ),
                    child: Icon(
                      Icons.receipt_long_rounded,
                      color: AppTheme.ink,
                      size: 18.sp,
                    ),
                  ),
                  SizedBox(width: 10.w),
                  Text(
                    "收支记录",
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.ink,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 28.w,
                    height: 28.w,
                    decoration: BoxDecoration(
                      color: AppTheme.tealSoft,
                      shape: BoxShape.circle,
                      border: AppTheme.border(),
                    ),
                    child: Icon(
                      _isMoneyLogsExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: AppTheme.ink,
                      size: 20.sp,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 12.h),
              child: Obx(() {
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
                            foregroundColor: AppTheme.ink,
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

  Widget _buildMoneyLogItem(dynamic log) {
    final isPositive = log.changeAmount > 0;
    final isPiggy = log.type == 'piggy';
    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: AppTheme.cream,
        borderRadius: BorderRadius.circular(14.r),
        border: AppTheme.border(),
        boxShadow: AppTheme.paperShadow(h: 8.0),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(6.w),
            decoration: BoxDecoration(
              color: isPiggy ? AppTheme.yellow : AppTheme.teal,
              borderRadius: BorderRadius.circular(8.r),
              border: AppTheme.border(),
            ),
            child: Icon(
              isPiggy
                  ? Icons.savings_rounded
                  : Icons.account_balance_wallet_rounded,
              size: 15.sp,
              color: AppTheme.ink,
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
                    fontWeight: FontWeight.w900,
                    fontSize: 13.sp,
                    color: AppTheme.ink,
                  ),
                ),
                Text(
                  "${log.timestamp.year}-${log.timestamp.month}-${log.timestamp.day}",
                  style: TextStyle(
                    fontSize: 10.5.sp,
                    color: AppTheme.textSub,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
            decoration: BoxDecoration(
              color: isPositive ? AppTheme.tealSoft : AppTheme.tomatoSoft,
              borderRadius: BorderRadius.circular(999),
              border: AppTheme.border(),
            ),
            child: Text(
              "${isPositive ? '+' : ''}${log.changeAmount.toStringAsFixed(2)}",
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w900,
                color: AppTheme.ink,
              ),
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
          SizedBox(height: 10.h),
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
