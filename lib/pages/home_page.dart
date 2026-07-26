import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import '../controllers/user_controller.dart';
import '../controllers/app_mode_controller.dart';
import '../models/log.dart';
import '../models/action_item.dart';
import '../theme/app_theme.dart';
import '../widgets/image_utils.dart';
import '../widgets/module_background_scene.dart';
import '../widgets/star_fx.dart';
import 'action_settings_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

/// 快捷记录卡片的糖果色配色（背景 / 强调色），按索引循环使用。
class _TileTint {
  const _TileTint(this.bg, this.fg);
  final Color bg;
  final Color fg;
}

const List<_TileTint> _actionTints = [
  _TileTint(Color(0xFFFFF1E4), Color(0xFFE8811C)), // 蜜桃
  _TileTint(Color(0xFFE8F7EE), Color(0xFF2E9E6B)), // 薄荷
  _TileTint(Color(0xFFEFEDFF), Color(0xFF7B6CD9)), // 香芋
  _TileTint(Color(0xFFE7F4FE), Color(0xFF3E8FD8)), // 天空
  _TileTint(Color(0xFFFFF6D9), Color(0xFFC79A00)), // 柠檬
  _TileTint(Color(0xFFFFEBF0), Color(0xFFE05B8B)), // 草莓
];

class _HomePageState extends State<HomePage> {
  // 快捷记录是否展开
  bool _isQuickActionsExpanded = false;
  // 星星足迹是否展开
  bool _isStarLogsExpanded = false;
  // 星星足迹显示数量
  int _starLogsPageSize = 5;

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
        child: Stack(
          children: [
            const Positioned.fill(
              child: ModuleBackgroundScene(theme: ModuleBackgroundTheme.home),
            ),
            SafeArea(
              child: Column(
                children: [
                  _buildHeader(controller, modeController),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        children: [
                          _StaggerIn(
                            delayMs: 0,
                            child: _buildStarCard(controller, modeController),
                          ),
                          _StaggerIn(
                            delayMs: 120,
                            child: _buildActionGrid(controller, modeController),
                          ),
                          _StaggerIn(
                            delayMs: 240,
                            child: _buildRecentLogs(controller),
                          ),
                          SizedBox(height: 20.h),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 加星/扣星的全屏动效反馈层（撒花 / 委屈表情）
            Positioned.fill(child: StarFxLayer(key: StarFx.layerKey)),
          ],
        ),
      ),
    );
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 5) return '夜深了 🌙';
    if (hour < 12) return '早上好 🌞';
    if (hour < 18) return '下午好 🌈';
    return '晚上好 🌙';
  }

  Widget _buildHeader(
      UserController controller, AppModeController modeController) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 6.h),
      child: Row(
        children: [
          Expanded(
            child: Obx(() {
              final baby = controller.currentBaby.value;
              if (baby == null) {
                return Row(
                  children: [
                    _buildAddBabyButton(controller),
                    Text(
                      '先添加一位宝宝吧',
                      style: TextStyle(
                        fontSize: 15.sp,
                        color: AppTheme.textSub,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                );
              }
              return GestureDetector(
                onTap: () => _showBabySelectorDialog(controller),
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    // 头像 - 带渐变光环，点击查看大图
                    GestureDetector(
                      onTap: () {
                        if (baby.avatarPath.isNotEmpty) {
                          ImageUtils.showImagePreview(context, baby.avatarPath);
                        }
                      },
                      child: Hero(
                        tag: 'avatar_preview_${baby.avatarPath}',
                        child: Container(
                          width: 54.w,
                          height: 54.w,
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
                                color: const Color(0xFFFF6B9D)
                                    .withValues(alpha: 0.35),
                                blurRadius: 12,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Container(
                            margin: EdgeInsets.all(2.5.w),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                            child: ClipOval(
                              child: ImageUtils.displayImage(
                                baby.avatarPath,
                                width: 49.w,
                                height: 49.w,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    // 问候语 + 名字
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _greeting,
                            style: TextStyle(
                              fontSize: 12.sp,
                              color: AppTheme.textSub,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 2.h),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  baby.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 19.sp,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.textMain,
                                  ),
                                ),
                              ),
                              SizedBox(width: 4.w),
                              Icon(
                                Icons.expand_more_rounded,
                                color: AppTheme.textSub,
                                size: 20.sp,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
          // 编辑按钮（儿童模式隐藏）
          Obx(() => modeController.isChildMode
              ? const SizedBox()
              : _buildRoundIconButton(
                  icon: Icons.edit_rounded,
                  color: AppTheme.textSub,
                  tooltip: '编辑宝宝',
                  onTap: () => _showEditBabyDialog(controller),
                )),
          SizedBox(width: 8.w),
          _buildRoundIconButton(
            icon: Icons.settings_rounded,
            color: AppTheme.primaryDark,
            tooltip: '设置',
            onTap: () => Get.to(() => const SettingsPage()),
          ),
        ],
      ),
    );
  }

  Widget _buildRoundIconButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4E342E).withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: color, size: 20.sp),
        onPressed: onTap,
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildQuickActionCard(UserController controller, ActionItem action,
      AppModeController modeController, _TileTint tint) {
    final isPositive = action.value > 0;
    final valueColor = isPositive ? tint.fg : const Color(0xFF5B8DEF);
    return GestureDetector(
      onTap: () async {
        if (modeController.isChildMode) {
          Get.snackbar('👀 只能看哦', '让爸爸妈妈来记录吧~');
          return;
        }

        // 添加二次确认
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Text(action.iconName.isNotEmpty ? action.iconName : "📝"),
                SizedBox(width: 8.w),
                const Text('确认记录'),
              ],
            ),
            content: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: '确定要记录 '),
                  TextSpan(
                    text: action.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary,
                    ),
                  ),
                  const TextSpan(text: ' 吗？\n\n'),
                  TextSpan(
                    text: '${action.value > 0 ? '+' : ''}${action.value} 星星',
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.bold,
                      color: action.value > 0 ? Colors.orange : Colors.blue,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('确定'),
              ),
            ],
          ),
        );

        if (confirm == true) {
          _handleQuickAction(controller, action);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: tint.bg,
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(
            color: tint.fg.withValues(alpha: 0.18),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44.w,
              height: 44.w,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(action.iconName.isNotEmpty ? action.iconName : "⭐️",
                  style: TextStyle(fontSize: 24.sp)),
            ),
            SizedBox(height: 7.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 6.w),
              child: Text(
                action.name,
                style: TextStyle(
                  fontSize: 13.sp,
                  color: AppTheme.textMain,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(height: 5.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 2.5.h),
              decoration: BoxDecoration(
                color: valueColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${isPositive ? '+' : ''}${action.value} ⭐',
                style: TextStyle(
                  fontSize: 11.sp,
                  color: valueColor,
                  fontWeight: FontWeight.w800,
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
    _updateStarsWithFx(controller, action.value.toInt(), action.name);
  }

  /// 更新星星并触发对应的动效与音效（加星撒花 / 扣星委屈）。
  void _updateStarsWithFx(UserController controller, int delta, String reason) {
    controller.updateStars(delta, reason);
    if (delta > 0) {
      StarFx.celebrate(delta);
    } else if (delta < 0) {
      StarFx.pout(delta.abs());
    }
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
                                            .withValues(alpha: 0.3),
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
                    border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.3)),
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
      barrierColor: Colors.black.withValues(alpha: 0.4),
    );
  }

  void _showEditBabyDialog(UserController controller) {
    final baby = controller.currentBaby.value;
    if (baby == null) return;

    final nameController = TextEditingController(text: baby.name);
    final Rx<String?> selectedAvatar = Rx<String?>(baby.avatarPath);
    final Rx<DateTime?> selectedBirthDate = Rx<DateTime?>(baby.birthDate);
    final RxString selectedGender = baby.gender.obs;

    Get.defaultDialog(
      title: "编辑宝宝资料",
      titlePadding: EdgeInsets.only(top: 24.h),
      contentPadding: EdgeInsets.all(24.w),
      content: Column(
        children: [
          GestureDetector(
            onTap: () async {
              final img =
                  await ImageUtils.pickImageAndToBase64(enableCrop: true);
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
          SizedBox(height: 12.h),
          Obx(
            () => _buildBirthDatePicker(
              selectedBirthDate.value,
              (date) => selectedBirthDate.value = date,
            ),
          ),
          SizedBox(height: 12.h),
          Obx(
            () => _buildGenderDropdown(
              selectedGender.value,
              (gender) => selectedGender.value = gender ?? 'unknown',
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
                birthDate: selectedBirthDate.value,
                gender: selectedGender.value,
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

  /// 今日星星净变化（只统计 star 类型日志）。
  num _todayStarDelta(UserController controller) {
    final now = DateTime.now();
    num sum = 0;
    for (final log in controller.logs) {
      if (log.type != 'star') continue;
      final t = log.timestamp;
      if (t.year == now.year && t.month == now.month && t.day == now.day) {
        sum += log.changeAmount;
      }
    }
    return sum;
  }

  Widget _buildStarCard(
      UserController controller, AppModeController modeController) {
    return Obx(() {
      final baby = controller.currentBaby.value;
      if (baby == null) return const SizedBox();
      final todayDelta = _todayStarDelta(controller);
      return Container(
        margin: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 8.h),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28.r),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF8E53).withValues(alpha: 0.38),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28.r),
          child: Stack(
            children: [
              // 落日糖果渐变底
              Positioned.fill(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFFF9A9E),
                        Color(0xFFFF8E53),
                        Color(0xFFFFC371),
                      ],
                    ),
                  ),
                ),
              ),
              // 装饰气泡
              Positioned(
                top: -34.w,
                right: -22.w,
                child: _bubble(120.w, 0.14),
              ),
              Positioned(
                bottom: -40.w,
                left: -26.w,
                child: _bubble(132.w, 0.10),
              ),
              Positioned(
                top: 18.h,
                left: 22.w,
                child: Text('✨',
                    style: TextStyle(
                        fontSize: 16.sp,
                        color: Colors.white.withValues(alpha: 0.9))),
              ),
              Positioned(
                top: 52.h,
                right: 30.w,
                child: Text('✨', style: TextStyle(fontSize: 13.sp)),
              ),
              Positioned(
                bottom: 68.h,
                left: 34.w,
                child: Text('⭐',
                    style: TextStyle(
                        fontSize: 11.sp,
                        color: Colors.white.withValues(alpha: 0.8))),
              ),
              Padding(
                padding: EdgeInsets.symmetric(vertical: 22.h, horizontal: 20.w),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: EdgeInsets.all(2.w),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(10.r),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8.r),
                            child: ImageUtils.displayImage(
                              baby.avatarPath,
                              width: 34.w,
                              height: 34.w,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        SizedBox(width: 10.w),
                        Text(
                          "${baby.name}的星星",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w800,
                            shadows: [
                              Shadow(
                                color: const Color(0xFFE8734D)
                                    .withValues(alpha: 0.5),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 6.h),
                    // 数字滚动动画
                    TweenAnimationBuilder<int>(
                      tween: IntTween(begin: 0, end: baby.starCount),
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, _) => Text(
                        '$value',
                        style: TextStyle(
                          fontSize: 62.sp,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          fontFamily: 'MiSans',
                          shadows: [
                            Shadow(
                              color: const Color(0xFFD96B3B)
                                  .withValues(alpha: 0.45),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 4.h),
                    // 今日变化徽章
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        todayDelta == 0
                            ? '今天还没有新记录'
                            : '今日 ${todayDelta > 0 ? '+' : ''}${todayDelta.toInt()} ⭐',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    SizedBox(height: 18.h),
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
                            filled: true,
                          ),
                        ),
                        SizedBox(width: 14.w),
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
                            filled: false,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _bubble(double size, double alpha) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: alpha),
      ),
    );
  }

  Widget _buildStarButton({
    required VoidCallback onTap,
    required IconData icon,
    required String label,
    required bool filled,
  }) {
    if (filled) {
      return ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 20.sp),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: AppTheme.primaryDark,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.r),
          ),
          padding: EdgeInsets.symmetric(vertical: 12.h),
          textStyle: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 14.sp,
          ),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 20.sp),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.white.withValues(alpha: 0.14),
        side: BorderSide(
          color: Colors.white.withValues(alpha: 0.65),
          width: 1.4,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
        ),
        padding: EdgeInsets.symmetric(vertical: 12.h),
        textStyle: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 14.sp,
        ),
      ),
    );
  }

  Widget _buildSectionCard({required List<Widget> children}) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(color: const Color(0xFFFFE4E6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4E342E).withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildSectionHeader({
    required String emoji,
    required Color emojiBg,
    required String title,
    required String subtitle,
    required bool expanded,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24.r),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
        child: Row(
          children: [
            Container(
              width: 38.w,
              height: 38.w,
              decoration: BoxDecoration(
                color: emojiBg,
                borderRadius: BorderRadius.circular(12.r),
              ),
              alignment: Alignment.center,
              child: Text(emoji, style: TextStyle(fontSize: 19.sp)),
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.textMain,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: AppTheme.textSub,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing,
            SizedBox(width: 6.w),
            AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 240),
              child: Container(
                width: 26.w,
                height: 26.w,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF1F2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: AppTheme.textSub,
                  size: 20.sp,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionGrid(
      UserController controller, AppModeController modeController) {
    return _buildSectionCard(
      children: [
        _buildSectionHeader(
          emoji: '⚡',
          emojiBg: const Color(0xFFFFF6D9),
          title: "快捷记录",
          subtitle: '点一下，星星马上记好',
          expanded: _isQuickActionsExpanded,
          onTap: () {
            setState(() {
              _isQuickActionsExpanded = !_isQuickActionsExpanded;
            });
          },
          trailing: Obx(() => modeController.isChildMode
              ? const SizedBox()
              : IconButton(
                  icon: Icon(Icons.tune_rounded,
                      color: AppTheme.textSub, size: 18.sp),
                  onPressed: () => Get.to(() => const ActionSettingsPage()),
                  tooltip: '管理快捷记录',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                )),
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
                  childAspectRatio: 0.92,
                ),
                itemCount: controller.actions.length,
                itemBuilder: (context, index) {
                  final action = controller.actions[index];
                  return _buildQuickActionCard(
                    controller,
                    action,
                    modeController,
                    _actionTints[index % _actionTints.length],
                  );
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
    );
  }

  Widget _buildRecentLogs(UserController controller) {
    return _buildSectionCard(
      children: [
        _buildSectionHeader(
          emoji: '🌟',
          emojiBg: const Color(0xFFFFEDE3),
          title: "星星足迹",
          subtitle: '每颗星星都有自己的故事',
          expanded: _isStarLogsExpanded,
          onTap: () {
            setState(() {
              _isStarLogsExpanded = !_isStarLogsExpanded;
            });
          },
        ),
        // 记录列表 - 可折叠
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Padding(
            padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 12.h),
            child: Obx(() {
              final starLogs =
                  controller.logs.where((l) => l.type == 'star').toList();
              if (starLogs.isEmpty) {
                return Padding(
                  padding: EdgeInsets.all(20.h),
                  child: Center(
                    child: Column(
                      children: [
                        Text('🐣', style: TextStyle(fontSize: 34.sp)),
                        SizedBox(height: 8.h),
                        Text(
                          "还没有记录哦，快去赚第一颗星星吧",
                          style: TextStyle(
                            color: AppTheme.textSub,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final displayCount = starLogs.length > _starLogsPageSize
                  ? _starLogsPageSize
                  : starLogs.length;
              return Column(
                children: [
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: displayCount,
                    itemBuilder: (context, index) {
                      final log = starLogs[index];
                      return _buildLogItem(log);
                    },
                  ),
                  // 加载更多按钮
                  if (starLogs.length > _starLogsPageSize)
                    Padding(
                      padding: EdgeInsets.only(top: 8.h),
                      child: TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _starLogsPageSize += 5;
                          });
                        },
                        icon: const Icon(Icons.expand_more),
                        label: Text(
                          '加载更多 (还有 ${starLogs.length - _starLogsPageSize} 条)',
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
          crossFadeState: _isStarLogsExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 300),
        ),
      ],
    );
  }

  Widget _buildLogItem(Log log) {
    final isPositive = log.changeAmount > 0;
    final accent =
        isPositive ? const Color(0xFF2E9E6B) : const Color(0xFFE05B5B);
    final accentBg =
        isPositive ? const Color(0xFFE8F7EE) : const Color(0xFFFFEDED);
    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFAF5),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: const Color(0xFFF6E8DC)),
      ),
      child: Row(
        children: [
          Container(
            width: 34.w,
            height: 34.w,
            decoration: BoxDecoration(
              color: accentBg,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPositive ? Icons.add_rounded : Icons.remove_rounded,
              color: accent,
              size: 18.sp,
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5.sp,
                    color: AppTheme.textMain,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  "${log.timestamp.month}-${log.timestamp.day} ${log.timestamp.hour}:${log.timestamp.minute.toString().padLeft(2, '0')}",
                  style: TextStyle(fontSize: 11.sp, color: AppTheme.textSub),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
            decoration: BoxDecoration(
              color: accentBg,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              "${isPositive ? '+' : ''}${log.changeAmount.toInt()} ⭐",
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w900,
                color: accent,
              ),
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
                        selectedColor: themeColor.withValues(alpha: 0.2),
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
                      selectedColor: themeColor.withValues(alpha: 0.2),
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
                    // Close keyboard if open
                    FocusManager.instance.primaryFocus?.unfocus();

                    final val = int.tryParse(countController.text) ?? 1;
                    final reason = isCustomReason.value
                        ? (customReasonController.text.isEmpty
                            ? "自定义操作"
                            : customReasonController.text)
                        : selectedReason.value;

                    // Close dialog FIRST
                    Get.back();

                    _updateStarsWithFx(controller, isAdd ? val : -val, reason);
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
    final Rx<DateTime?> selectedBirthDate = Rx<DateTime?>(null);
    final RxString selectedGender = 'unknown'.obs;

    Get.defaultDialog(
      title: "添加宝宝",
      titlePadding: EdgeInsets.only(top: 24.h),
      contentPadding: EdgeInsets.all(24.w),
      content: Column(
        children: [
          GestureDetector(
            onTap: () async {
              final img =
                  await ImageUtils.pickImageAndToBase64(enableCrop: true);
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
          SizedBox(height: 12.h),
          Obx(
            () => _buildBirthDatePicker(
              selectedBirthDate.value,
              (date) => selectedBirthDate.value = date,
            ),
          ),
          SizedBox(height: 12.h),
          Obx(
            () => _buildGenderDropdown(
              selectedGender.value,
              (gender) => selectedGender.value = gender ?? 'unknown',
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
                birthDate: selectedBirthDate.value,
                gender: selectedGender.value,
              );
              Get.back();
            }
          },
          child: const Text("添加"),
        ),
      ),
    );
  }

  Widget _buildBirthDatePicker(
    DateTime? value,
    ValueChanged<DateTime?> onChanged,
  ) {
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime(now.year - 3, now.month, now.day),
          firstDate: DateTime(now.year - 18),
          lastDate: now,
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: '生日',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.cake_outlined),
        ),
        child: Text(
          value == null ? '未设置' : DateFormat('yyyy-MM-dd').format(value),
        ),
      ),
    );
  }

  Widget _buildGenderDropdown(
    String value,
    ValueChanged<String?> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: const InputDecoration(
        labelText: '性别',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.child_care),
      ),
      items: const [
        DropdownMenuItem(value: 'unknown', child: Text('未设置')),
        DropdownMenuItem(value: 'male', child: Text('男孩')),
        DropdownMenuItem(value: 'female', child: Text('女孩')),
      ],
      onChanged: onChanged,
    );
  }
}

/// 页面加载时的错落浮现动画：整体一次编排，比零散微动效更有仪式感。
class _StaggerIn extends StatelessWidget {
  const _StaggerIn({required this.delayMs, required this.child});

  final int delayMs;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final totalMs = 480 + delayMs;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: totalMs),
      curve: Interval(
        delayMs / totalMs,
        1,
        curve: Curves.easeOutCubic,
      ),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 22 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
