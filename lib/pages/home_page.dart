import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../controllers/user_controller.dart';
import '../models/baby.dart';
import '../models/log.dart';
import '../theme/app_theme.dart';
import '../widgets/image_utils.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final UserController controller = Get.find<UserController>();

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
              _buildBabySelector(controller),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      _buildStarCard(controller),
                      _buildActionGrid(controller),
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

  Widget _buildBabySelector(UserController controller) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 70.h,
              child: Obx(
                () => ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: controller.babies.length + 1,
                  itemBuilder: (context, index) {
                    if (index == controller.babies.length) {
                      return _buildAddBabyButton(controller);
                    }
                    final baby = controller.babies[index];
                    final isSelected =
                        controller.currentBaby.value?.id == baby.id;
                    return _buildBabyAvatar(baby, isSelected, controller);
                  },
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_rounded, color: AppTheme.textSub),
            onPressed: () => _showEditBabyDialog(controller),
          ),
        ],
      ),
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

  Widget _buildBabyAvatar(
    Baby baby,
    bool isSelected,
    UserController controller,
  ) {
    return GestureDetector(
      onTap: () => controller.switchBaby(baby.id),
      child: Container(
        width: 60.w,
        margin: EdgeInsets.only(right: 8.w),
        child: AnimatedScale(
          scale: isSelected ? 1.1 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            padding: EdgeInsets.all(3.w),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? AppTheme.primary : Colors.grey.shade300,
                width: isSelected ? 3.w : 1.w,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: AppTheme.primary.withOpacity(0.4),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ]
                  : [],
            ),
            child: ClipOval(
              child: ImageUtils.displayImage(
                baby.avatarPath,
                width: 48.w,
                height: 48.w,
                fit: BoxFit.cover,
              ),
            ),
          ),
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

  Widget _buildStarCard(UserController controller) {
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
                    onTap: () => _showStarAdjustDialog(controller, true),
                    icon: Icons.add_circle,
                    label: "增加星星",
                    color: AppTheme.primary,
                  ),
                ),
                SizedBox(width: 16.w),
                Expanded(
                  child: _buildStarButton(
                    onTap: () => _showStarAdjustDialog(controller, false),
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

  Widget _buildActionGrid(UserController controller) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "快捷记录",
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.w900,
              color: AppTheme.textMain,
            ),
          ),
          SizedBox(height: 12.h),
          Obx(
            () => GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 12.h,
                crossAxisSpacing: 12.w,
                childAspectRatio: 0.9,
              ),
              itemCount: controller.actions.length,
              itemBuilder: (context, index) {
                final action = controller.actions[index];
                return _buildQuickActionCard(controller, action);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionCard(UserController controller, action) {
    return GestureDetector(
      onTap: () => controller.updateStars(action.value.toInt(), action.name),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              action.iconName.isNotEmpty ? action.iconName : "⭐️",
              style: TextStyle(fontSize: 24.sp),
            ),
            SizedBox(height: 5.h),
            Text(
              action.name,
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.bold,
                color: AppTheme.textMain,
              ),
            ),
            Text(
              "${action.value > 0 ? '+' : ''}${action.value.toInt()}",
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w900,
                color: action.value > 0 ? Colors.green : Colors.red,
              ),
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
            final starLogs = controller.logs
                .where((l) => l.type == 'star')
                .toList();
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
    final icon = isAdd
        ? Icons.stars_rounded
        : Icons.remove_circle_outline_rounded;

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
                          color:
                              (!isCustomReason.value &&
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
                selectedAvatar.value ??
                    'assets/images/1.png', // Fallback to default asset
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
