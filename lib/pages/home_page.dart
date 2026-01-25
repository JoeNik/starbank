import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../controllers/user_controller.dart';
import '../controllers/app_mode_controller.dart';
import '../models/log.dart';
import '../models/action_item.dart';
import '../theme/app_theme.dart';
import '../widgets/image_utils.dart';
import 'action_settings_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // 快捷记录是否展开
  bool _isQuickActionsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final UserController controller = Get.find<UserController>();
    final AppModeController modeController = Get.find<AppModeController>();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFF1F2), Colors.white],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildBabySelector(controller, modeController),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      _buildStarCard(controller, modeController),
                      _buildActionGrid(controller, modeController),
                      _buildRecentLogs(controller),
                      SizedBox(height: 20.h),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBabySelector(
      UserController controller, AppModeController modeController) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
      child: Row(
        children: [
          // 当前宝宝头像和信息（点击弹出选择器）
          Obx(() {
            final baby = controller.currentBaby.value;
            if (baby == null) {
              return _buildAddBabyButton(controller);
            }
            return GestureDetector(
              onTap: () => _showBabySelectorDialog(controller),
              child: Row(
                children: [
                  // 头像 - 带渐变边框
                  Container(
                    width: 56.w,
                    height: 56.w,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFFF6B9D),
                          Color(0xFFFF8E53),
                          Color(0xFFFFC371),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF6B9D).withOpacity(0.4),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Container(
                      margin: EdgeInsets.all(3.w),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                      child: ClipOval(
                        child: ImageUtils.displayImage(
                          baby.avatarPath,
                          width: 50.w,
                          height: 50.w,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  // 名字和星星数
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        baby.name,
                        style: TextStyle(
                          fontSize: 18.sp,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textMain,
                        ),
                      ),
                      Row(
                        children: [
                          Icon(Icons.star, color: Colors.amber, size: 16.sp),
                          SizedBox(width: 4.w),
                          Text(
                            '${baby.starCount} 颗星星',
                            style: TextStyle(
                              fontSize: 13.sp,
                              color: AppTheme.textSub,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(width: 8.w),
                  Icon(Icons.keyboard_arrow_down, color: AppTheme.textSub),
                ],
              ),
            );
          }),
          const Spacer(),
          // 编辑按钮（儿童模式隐藏）
          Obx(() => modeController.isChildMode
              ? const SizedBox()
              : IconButton(
                  icon: const Icon(Icons.edit_rounded, color: AppTheme.textSub),
                  onPressed: () => _showEditBabyDialog(controller),
                )),
          // 设置按钮 - 始终显示，使用更醒目的样式
          Container(
            margin: EdgeInsets.only(left: 4.w),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8.r),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              icon: Icon(Icons.settings_rounded,
                  color: AppTheme.primary, size: 22.sp),
              onPressed: () => Get.to(() => const SettingsPage()),
              tooltip: '设置',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionCard(UserController controller, ActionItem action,
      AppModeController modeController) {
    final isPositive = action.value > 0;
    return GestureDetector(
      onTap: () {
        if (modeController.isChildMode) {
          Get.snackbar('👀 只能看哦', '让爸爸妈妈来记录吧~');
          return;
        }
        _handleQuickAction(controller, action);
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20.r),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 使用 iconName 作为 emoji
            Text(action.iconName.isNotEmpty ? action.iconName : "⭐️",
                style: TextStyle(fontSize: 32.sp)),
            SizedBox(height: 8.h),
            Text(
              action.name,
              style: TextStyle(
                fontSize: 14.sp,
                color: AppTheme.textMain,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: 4.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
              decoration: BoxDecoration(
                color:
                    (isPositive ? Colors.orange : Colors.blue).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Text(
                '${isPositive ? '+' : ''}${action.value}',
                style: TextStyle(
                  fontSize: 12.sp,
                  color: isPositive ? Colors.orange : Colors.blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleQuickAction(UserController controller, ActionItem action) {
    // 快捷记录对应的是星星增减
    controller.updateStars(action.value.toInt(), action.name);

    Get.snackbar(
      action.value > 0 ? '🎉 加油！' : '💪 继续努力',
      '已记录: ${action.name} (${action.value > 0 ? '+' : ''}${action.value})',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
    );
  }

  /// 宝宝选择对话框（居中弹出）
  void _showBabySelectorDialog(UserController controller) {
    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28.r),
        ),
        backgroundColor: const Color(0xFFFFF1F2),
        child: Container(
          padding: EdgeInsets.all(24.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题
              Row(
                children: [
                  Text('👶', style: TextStyle(fontSize: 24.sp)),
                  SizedBox(width: 10.w),
                  Text(
                    '选择宝宝',
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
              SizedBox(height: 20.h),

              // 宝宝列表
              Obx(() {
                final babies = controller.babies;
                final currentId = controller.currentBaby.value?.id;

                if (babies.isEmpty) {
                  return Padding(
                    padding: EdgeInsets.symmetric(vertical: 20.h),
                    child: const Text('还没有添加宝宝'),
                  );
                }

                return Wrap(
                  spacing: 20.w,
                  runSpacing: 16.h,
                  alignment: WrapAlignment.center,
                  children: babies.map((baby) {
                    final isSelected = baby.id == currentId;
                    return GestureDetector(
                      onTap: () {
                        controller.switchBaby(baby.id);
                        Get.back();
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 头像
                          Container(
                            width: 80.w,
                            height: 80.w,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: isSelected
                                  ? const LinearGradient(
                                      colors: [
                                        Color(0xFFFF6B9D),
                                        Color(0xFFFF8E53),
                                        Color(0xFFFFC371),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : null,
                              color: isSelected ? null : Colors.white,
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: const Color(0xFFFF6B9D)
                                            .withOpacity(0.3),
                                        blurRadius: 12,
                                        spreadRadius: 2,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Container(
                              margin: EdgeInsets.all(isSelected ? 3.w : 0),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                              ),
                              child: ClipOval(
                                child: baby.avatarPath.isEmpty
                                    ? Center(
                                        child: Text('👶',
                                            style: TextStyle(fontSize: 32.sp)),
                                      )
                                    : ImageUtils.displayImage(
                                        baby.avatarPath,
                                        width: 74.w,
                                        height: 74.w,
                                        fit: BoxFit.cover,
                                      ),
                              ),
                            ),
                          ),
                          SizedBox(height: 8.h),
                          // 名字或星星数
                          if (isSelected)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle,
                                    color: Colors.green, size: 16.sp),
                                SizedBox(width: 4.w),
                                Text(
                                  '${baby.starCount}',
                                  style: TextStyle(
                                    fontSize: 14.sp,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                              ],
                            )
                          else
                            Text(
                              baby.name,
                              style: TextStyle(
                                fontSize: 13.sp,
                                color: AppTheme.textMain,
                              ),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              }),
              SizedBox(height: 16.h),

              // 添加宝宝按钮
              GestureDetector(
                onTap: () {
                  Get.back(); // 先关闭选择对话框
                  _showAddBabyDialog(controller);
                },
                child: Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20.r),
                    border:
                        Border.all(color: AppTheme.primary.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_circle_outline,
                          color: AppTheme.primary, size: 20.sp),
                      SizedBox(width: 8.w),
                      Text(
                        '添加宝宝',
                        style: TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 12.h),

              // 提示
              Text(
                '点击头像切换宝宝',
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 12.sp,
                ),
              ),
            ],
          ),
        ),
      ),
      barrierColor: Colors.black.withOpacity(0.4),
    );
  }

  void _showEditBabyDialog(UserController controller) {
    final baby = controller.currentBaby.value;
    if (baby == null) return;

    final nameController = TextEditingController(text: baby.name);
    final Rx<String?> selectedAvatar = Rx<String?>(baby.avatarPath);

    Get.defaultDialog(
      title: "编辑宝宝资料",
      titlePadding: EdgeInsets.only(top: 24.h),
      contentPadding: EdgeInsets.all(24.w),
      content: Column(
        children: [
          GestureDetector(
            onTap: () async {
              final img = await ImageUtils.pickImageAndToBase64();
              if (img != null) selectedAvatar.value = img;
            },
            child: Obx(
              () => Container(
                width: 80.w,
                height: 80.w,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: ClipOval(
                  child: ImageUtils.displayImage(
                    selectedAvatar.value,
                    width: 80.w,
                    height: 80.w,
                    placeholder: const Icon(
                      Icons.add_a_photo,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: 16.h),
          TextField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: "宝宝称呼",
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      confirm: SizedBox(
        width: 100.w,
        child: ElevatedButton(
          onPressed: () {
            if (nameController.text.isNotEmpty) {
              controller.editBaby(
                nameController.text,
                selectedAvatar.value ?? baby.avatarPath,
              );
              Get.back();
            }
          },
          child: const Text("保存"),
        ),
      ),
      cancel: OutlinedButton.icon(
        onPressed: () {
          Get.back(); // 关闭编辑对话框
          // 确认删除对话框
          Get.defaultDialog(
            title: "确认删除",
            middleText: "确定要删除 ${baby.name} 吗？\n该宝宝的所有数据都将被删除！",
            textConfirm: "确认删除",
            textCancel: "取消",
            confirmTextColor: Colors.white,
            buttonColor: Colors.red,
            onConfirm: () {
              Get.back(); // 先关闭确认对话框
              controller.deleteBaby(baby.id);
            },
            onCancel: () {}, // 点击取消时自动关闭
          );
        },
        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
        label: const Text("删除", style: TextStyle(color: Colors.red)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.red),
        ),
      ),
    );
  }

  Widget _buildAddBabyButton(UserController controller) {
    return GestureDetector(
      onTap: () => _showAddBabyDialog(controller),
      child: Container(
        width: 48.w,
        height: 48.w,
        margin: EdgeInsets.only(right: 12.w),
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.grey.shade300, width: 1),
        ),
        child: const Icon(Icons.add, color: Colors.grey),
      ),
    );
  }

  Widget _buildStarCard(
      UserController controller, AppModeController modeController) {
    return Obx(() {
      final baby = controller.currentBaby.value;
      if (baby == null) return const SizedBox();
      return Container(
        margin: EdgeInsets.all(16.w),
        padding: EdgeInsets.symmetric(vertical: 24.h, horizontal: 20.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32.r),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8.r),
                  child: ImageUtils.displayImage(
                    baby.avatarPath,
                    width: 40.w,
                    height: 40.w,
                    fit: BoxFit.cover,
                  ),
                ),
                SizedBox(width: 10.w),
                Text(
                  "${baby.name}的星星",
                  style: TextStyle(
                    color: AppTheme.textSub,
                    fontSize: 16.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            SizedBox(height: 10.h),
            Text(
              "${baby.starCount}",
              style: TextStyle(
                fontSize: 64.sp,
                fontWeight: FontWeight.w900,
                color: AppTheme.primary,
                fontFamily: 'MiSans',
              ),
            ),
            SizedBox(height: 20.h),
            Row(
              children: [
                Expanded(
                  child: _buildStarButton(
                    onTap: () {
                      if (modeController.isChildMode) {
                        Get.snackbar('👀 只能看哦', '让爸爸妈妈来加星星吧~');
                        return;
                      }
                      _showStarAdjustDialog(controller, true);
                    },
                    icon: Icons.add_circle,
                    label: "增加星星",
                    color: AppTheme.primary,
                  ),
                ),
                SizedBox(width: 16.w),
                Expanded(
                  child: _buildStarButton(
                    onTap: () {
                      if (modeController.isChildMode) {
                        Get.snackbar('👀 只能看哦', '让爸爸妈妈来操作吧~');
                        return;
                      }
                      _showStarAdjustDialog(controller, false);
                    },
                    icon: Icons.remove_circle,
                    label: "扣除星星",
                    color: Colors.grey.shade400,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }

  Widget _buildStarButton({
    required VoidCallback onTap,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 20.sp),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
        ),
        padding: EdgeInsets.symmetric(vertical: 12.h),
      ),
    );
  }

  Widget _buildActionGrid(
      UserController controller, AppModeController modeController) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Card(
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
                  _isQuickActionsExpanded = !_isQuickActionsExpanded;
                });
              },
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(16.r),
                bottom: _isQuickActionsExpanded
                    ? Radius.zero
                    : Radius.circular(16.r),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                child: Row(
                  children: [
                    Icon(
                      Icons.flash_on,
                      color: AppTheme.primary,
                      size: 20.sp,
                    ),
                    SizedBox(width: 8.w),
                    Text(
                      "快捷记录",
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textMain,
                      ),
                    ),
                    const Spacer(),
                    // 管理按钮 (儿童模式隐藏)
                    Obx(() => modeController.isChildMode
                        ? const SizedBox()
                        : IconButton(
                            icon: Icon(Icons.settings_outlined,
                                color: AppTheme.textSub, size: 18.sp),
                            onPressed: () =>
                                Get.to(() => const ActionSettingsPage()),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          )),
                    SizedBox(width: 8.w),
                    // 展开/收起图标
                    Icon(
                      _isQuickActionsExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: AppTheme.textSub,
                    ),
                  ],
                ),
              ),
            ),
            // 快捷记录网格 - 可折叠
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 12.h),
                child: Obx(
                  () => GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 8.h,
                      crossAxisSpacing: 8.w,
                      childAspectRatio: 1.0,
                    ),
                    itemCount: controller.actions.length,
                    itemBuilder: (context, index) {
                      final action = controller.actions[index];
                      return _buildQuickActionCard(
                          controller, action, modeController);
                    },
                  ),
                ),
              ),
              crossFadeState: _isQuickActionsExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 300),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentLogs(UserController controller) {
    return Padding(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "星星足迹",
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textMain,
                ),
              ),
              TextButton(
                onPressed: () {},
                child: const Text(
                  "更多",
                  style: TextStyle(color: AppTheme.textSub),
                ),
              ),
            ],
          ),
          Obx(() {
            final starLogs =
                controller.logs.where((l) => l.type == 'star').toList();
            if (starLogs.isEmpty) return const Center(child: Text("还没有记录哦"));
            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: starLogs.length > 5 ? 5 : starLogs.length,
              itemBuilder: (context, index) {
                final log = starLogs[index];
                return _buildLogItem(log);
              },
            );
          }),
        ],
      ),
    );
  }

  Widget _buildLogItem(Log log) {
    final isPositive = log.changeAmount > 0;
    return Container(
      margin: EdgeInsets.only(bottom: 10.h),
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8.w),
            decoration: BoxDecoration(
              color: isPositive
                  ? Colors.green.withOpacity(0.1)
                  : Colors.red.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPositive ? Icons.add : Icons.remove,
              color: isPositive ? Colors.green : Colors.red,
              size: 16.sp,
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
                    color: AppTheme.textMain,
                  ),
                ),
                Text(
                  "${log.timestamp.month}-${log.timestamp.day} ${log.timestamp.hour}:${log.timestamp.minute.toString().padLeft(2, '0')}",
                  style: TextStyle(fontSize: 11.sp, color: AppTheme.textSub),
                ),
              ],
            ),
          ),
          Text(
            "${isPositive ? '+' : ''}${log.changeAmount.toInt()}",
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.w900,
              color: isPositive ? Colors.green : Colors.red,
            ),
          ),
        ],
      ),
    );
  }

  void _showStarAdjustDialog(UserController controller, bool isAdd) {
    // Determine title and color theme
    final title = isAdd ? "获得星星" : "扣除星星";
    final themeColor = isAdd ? Colors.orange : Colors.blueGrey;
    final icon =
        isAdd ? Icons.stars_rounded : Icons.remove_circle_outline_rounded;

    // Default reason options
    final List<String> defaultReasons = isAdd
        ? ["按时起床", "自己吃饭", "主动学习", "表现很棒"]
        : ["乱丢玩具", "看电视超时", "没吃完饭", "淘气"];

    // UI Controllers
    final countController = TextEditingController(text: "1");
    // We'll use an RxString for the reason to reactively update the UI (especially if we want custom input integration)
    // But for simplicity in a dialog, a simple variable + SetState (StatefulBuilder) or GetX reactive variable is fine.
    // Let's use a local RxString for reactivity within Get.bottomSheet
    final selectedReason = defaultReasons[0].obs;
    final customReasonController = TextEditingController();
    final isCustomReason = false.obs;

    Get.bottomSheet(
      Container(
        padding: EdgeInsets.all(24.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32.r)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: themeColor, size: 28.sp),
                  SizedBox(width: 8.w),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 20.sp,
                      fontWeight: FontWeight.w900,
                      color: themeColor,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 24.h),

              // Count Input with +/- buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: () {
                      int val = int.tryParse(countController.text) ?? 1;
                      if (val > 1) countController.text = (val - 1).toString();
                    },
                    icon: Icon(
                      Icons.remove_circle,
                      color: Colors.grey.shade300,
                      size: 36.sp,
                    ),
                  ),
                  SizedBox(width: 16.w),
                  SizedBox(
                    width: 80.w,
                    child: TextField(
                      controller: countController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 32.sp,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textMain,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  SizedBox(width: 16.w),
                  IconButton(
                    onPressed: () {
                      int val = int.tryParse(countController.text) ?? 1;
                      countController.text = (val + 1).toString();
                    },
                    icon: Icon(
                      Icons.add_circle,
                      color: themeColor,
                      size: 36.sp,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 24.h),

              // Reason Selection
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "选择原因",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
              SizedBox(height: 12.h),
              Obx(
                () => Wrap(
                  spacing: 10.w,
                  runSpacing: 10.h,
                  children: [
                    ...defaultReasons.map(
                      (r) => ChoiceChip(
                        label: Text(r),
                        selected:
                            !isCustomReason.value && selectedReason.value == r,
                        selectedColor: themeColor.withOpacity(0.2),
                        labelStyle: TextStyle(
                          color: (!isCustomReason.value &&
                                  selectedReason.value == r)
                              ? themeColor
                              : Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                        onSelected: (s) {
                          if (s) {
                            selectedReason.value = r;
                            isCustomReason.value = false;
                          }
                        },
                      ),
                    ),
                    ChoiceChip(
                      label: const Text("自定义"),
                      selected: isCustomReason.value,
                      selectedColor: themeColor.withOpacity(0.2),
                      labelStyle: TextStyle(
                        color: isCustomReason.value ? themeColor : Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                      onSelected: (s) {
                        if (s) isCustomReason.value = true;
                      },
                    ),
                  ],
                ),
              ),

              // Custom Reason Input (Visible only when 'Custom' is selected)
              Obx(
                () => isCustomReason.value
                    ? Padding(
                        padding: EdgeInsets.only(top: 16.h),
                        child: TextField(
                          controller: customReasonController,
                          decoration: InputDecoration(
                            hintText: "请输入原因...",
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16.w,
                              vertical: 12.h,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.r),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      )
                    : const SizedBox(),
              ),

              SizedBox(height: 32.h),

              // Confirm Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final val = int.tryParse(countController.text) ?? 1;
                    final reason = isCustomReason.value
                        ? (customReasonController.text.isEmpty
                            ? "自定义操作"
                            : customReasonController.text)
                        : selectedReason.value;

                    controller.updateStars(isAdd ? val : -val, reason);
                    Get.back();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeColor,
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                  ),
                  child: const Text("确认提交"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddBabyDialog(UserController controller) {
    final nameController = TextEditingController();
    final Rx<String?> selectedAvatar = Rx<String?>(null);

    Get.defaultDialog(
      title: "添加宝宝",
      titlePadding: EdgeInsets.only(top: 24.h),
      contentPadding: EdgeInsets.all(24.w),
      content: Column(
        children: [
          GestureDetector(
            onTap: () async {
              final img = await ImageUtils.pickImageAndToBase64();
              if (img != null) selectedAvatar.value = img;
            },
            child: Obx(
              () => Container(
                width: 80.w,
                height: 80.w,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: selectedAvatar.value != null
                    ? ClipOval(
                        child: ImageUtils.displayImage(selectedAvatar.value),
                      )
                    : const Icon(Icons.add_a_photo, color: Colors.grey),
              ),
            ),
          ),
          SizedBox(height: 16.h),
          TextField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: "宝宝称呼",
              hintText: "例如：宝贝、小明",
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      confirm: SizedBox(
        width: 100.w,
        child: ElevatedButton(
          onPressed: () {
            if (nameController.text.isNotEmpty) {
              controller.addBaby(
                nameController.text,
                selectedAvatar.value ?? '', // 使用默认 emoji 头像
              );
              Get.back();
            }
          },
          child: const Text("添加"),
        ),
      ),
    );
  }
}
