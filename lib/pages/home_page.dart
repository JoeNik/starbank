import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import '../controllers/user_controller.dart';
import '../controllers/app_mode_controller.dart';
import '../controllers/shop_controller.dart';
import '../controllers/music_player_controller.dart';
import '../models/log.dart';
import '../models/action_item.dart';
import '../models/product.dart';
import '../theme/app_theme.dart';
import '../widgets/image_utils.dart';
import '../widgets/memphis_widgets.dart';
import '../widgets/module_background_scene.dart';
import '../widgets/star_fx.dart';
import 'action_settings_page.dart';
import 'settings_page.dart';
import 'riddle_page.dart';
import 'entertainment/weiqi/weiqi_home_page.dart';
import 'entertainment/weiqi/weiqi_service.dart';
import 'entertainment/music/music_home_page.dart';
import 'entertainment/hanzi_learning/hanzi_learning_page.dart';
import 'entertainment/encyclopedia/encyclopedia_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

/// 快捷记录卡片的 017 · 中世纪现代暖调配色（背景 / 强调块色），相邻不同色循环使用。
class _TileTint {
  const _TileTint(this.bg, this.fg);
  final Color bg;
  final Color fg;
}

const List<_TileTint> _actionTints = [
  _TileTint(AppTheme.yellowSoft, AppTheme.yellow), // 向日葵黄
  _TileTint(AppTheme.tealSoft, AppTheme.teal), // 绿松石
  _TileTint(AppTheme.pinkSoft, AppTheme.pink), // Girard 粉
  _TileTint(AppTheme.lilacSoft, AppTheme.lilac), // 丁香紫
  _TileTint(AppTheme.cobaltSoft, AppTheme.cobalt), // 钴蓝
  _TileTint(AppTheme.tomatoSoft, AppTheme.tomato), // 番茄红
];

class _HomePageState extends State<HomePage> {
  /// 近 7 日趋势图当前选中的天数索引（0~6，6 代表今天）
  int _selectedChartDayIndex = 6;

  /// 动态信息流每条日志的喝彩点赞数（key: 时间戳+描述）
  final Map<String, int> _feedClapCounts = <String, int>{};

  @override
  Widget build(BuildContext context) {
    final UserController controller = Get.find<UserController>();
    final AppModeController modeController = Get.find<AppModeController>();
    final ShopController shopController = Get.find<ShopController>();

    return Scaffold(
      backgroundColor: AppTheme.cream,
      body: Stack(
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
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 1. 顶部星星金库主卡片 + 四大高频金刚区（快捷打卡弹框 / 星星足迹弹框 / 加星 / 扣星）
                        _StaggerIn(
                          delayMs: 0,
                          child: _buildStarCard(controller, modeController),
                        ),
                        // 2. 趣味交互舱：今日好习惯挑战 + 幸运星盘亲子盲盒
                        _StaggerIn(
                          delayMs: 80,
                          child: _buildInteractiveChallengeHub(
                              controller, modeController),
                        ),
                        // 3. Bento 商业双拼看板：下一站心愿目标 × 财富小金库
                        _StaggerIn(
                          delayMs: 150,
                          child: _buildBentoGoalAndWealthRow(
                              controller, shopController),
                        ),
                        // 4. 跨模块直达横滑舱：星球乐园 · 今日推荐
                        _StaggerIn(
                          delayMs: 220,
                          child: _buildPlanetPlaygroundCarousel(),
                        ),
                        // 5. 数据洞察：近 7 日星星能量趋势图（可点击切换日期明细）
                        _StaggerIn(
                          delayMs: 290,
                          child: _buildWeeklyTrendCard(controller),
                        ),
                        // 6. 商业级实时成长动态流：星球成长喜报（带喝彩点赞交互 + 打开完整足迹弹框）
                        _StaggerIn(
                          delayMs: 360,
                          child: _buildLiveActivityFeed(
                              controller, modeController),
                        ),
                        SizedBox(height: 28.h),
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
                    // 头像 - 孟菲斯泡泡糖粉/柠檬黄粗黑描边硬投影圆环，点击查看大图
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
                            color: AppTheme.yellow,
                            border: AppTheme.border(),
                            boxShadow: AppTheme.paperShadow(h: 8.0),
                          ),
                          child: Container(
                            margin: EdgeInsets.all(2.5.w),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              border: AppTheme.border(),
                            ),
                            child: ClipOval(
                              child: ImageUtils.displayImage(
                                baby.avatarPath,
                                width: 45.w,
                                height: 45.w,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    // 问候语贴纸 + 名字
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MemphisTag(
                            text: _greeting,
                            color: AppTheme.pinkSoft,
                            tiltDeg: -3.0,
                            fontSize: 10.5.sp,
                            padding: EdgeInsets.symmetric(
                                horizontal: 8.w, vertical: 2.h),
                            shadowOffset: 2.0,
                          ),
                          SizedBox(height: 4.h),
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
                                    color: AppTheme.ink,
                                  ),
                                ),
                              ),
                              SizedBox(width: 4.w),
                              Icon(
                                Icons.expand_more_rounded,
                                color: AppTheme.ink,
                                size: 22.sp,
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
    return MemphisIconButton(
      icon: icon,
      iconColor: AppTheme.ink,
      bgColor: color == AppTheme.primaryDark ? AppTheme.yellow : Colors.white,
      size: 40.w,
      iconSize: 20.sp,
      tooltip: tooltip,
      onTap: onTap,
    );
  }

  Widget _buildQuickActionCard(UserController controller, ActionItem action,
      AppModeController modeController, _TileTint tint) {
    final isPositive = action.value > 0;
    final doneToday = _isDoneToday(controller, action.name);
    return BouncyTap(
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
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              color: tint.bg,
              borderRadius: BorderRadius.circular(18.r),
              boxShadow: AppTheme.paperShadow(h: 5.0),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 40.w,
                  height: 40.w,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    action.iconName.isNotEmpty ? action.iconName : "⭐️",
                    style: TextStyle(fontSize: 21.sp),
                  ),
                ),
                SizedBox(height: 6.h),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6.w),
                  child: Text(
                    action.name,
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: AppTheme.ink,
                      fontWeight: FontWeight.w900,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(height: 5.h),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                  decoration: BoxDecoration(
                    color: isPositive ? tint.fg : AppTheme.tomato,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${isPositive ? '+' : ''}${action.value} ⭐',
                    style: TextStyle(
                      fontSize: 10.5.sp,
                      color: (!isPositive || tint.fg == AppTheme.cobalt)
                          ? Colors.white
                          : AppTheme.ink,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (doneToday)
            Positioned(
              top: 6.h,
              right: 6.w,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 1.5.h),
                decoration: BoxDecoration(
                  color: AppTheme.teal,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '✓今日已记',
                  style: TextStyle(
                    fontSize: 8.5.sp,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
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

  /// 计算连续得星打卡天数（从今天或昨天往回推算）
  int _calculateStreakDays(UserController controller) {
    final now = DateTime.now();
    final activeDateKeys = <String>{};
    for (final log in controller.logs) {
      if (log.type == 'star' && log.changeAmount > 0) {
        final t = log.timestamp;
        activeDateKeys.add('${t.year}-${t.month}-${t.day}');
      }
    }
    int streak = 0;
    for (int i = 0; i < 365; i++) {
      final d = now.subtract(Duration(days: i));
      final key = '${d.year}-${d.month}-${d.day}';
      if (activeDateKeys.contains(key)) {
        streak++;
      } else if (i == 0) {
        continue;
      } else {
        break;
      }
    }
    return streak;
  }

  /// 判断某个动作或任务标题今天是否已打卡记录过
  bool _isDoneToday(UserController controller, String title) {
    final now = DateTime.now();
    return controller.logs.any((l) =>
        l.type == 'star' &&
        l.description == title &&
        l.timestamp.year == now.year &&
        l.timestamp.month == now.month &&
        l.timestamp.day == now.day);
  }

  // ===========================================================================
  // 1. 顶部星星金库主卡片 + 四大高频金刚区（快捷打卡弹框 / 星星足迹弹框 / 加星 / 扣星）
  // ===========================================================================
  Widget _buildStarCard(
      UserController controller, AppModeController modeController) {
    return Obx(() {
      final baby = controller.currentBaby.value;
      if (baby == null) return const SizedBox();
      final todayDelta = _todayStarDelta(controller);
      final streakDays = _calculateStreakDays(controller);

      return Container(
        margin: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 8.h),
        decoration: BoxDecoration(
          color: AppTheme.yellow,
          borderRadius: BorderRadius.circular(24.r),
          boxShadow: AppTheme.paperShadow(h: 8.0),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24.r),
          child: Stack(
            children: [
              // 右上角中世纪现代粉圆剪纸装饰
              Positioned(
                top: -18.w,
                right: -14.w,
                child: const MemphisShapeBadge(
                  shape: MemphisShapeType.circle,
                  color: AppTheme.pink,
                  size: 76,
                  tiltDeg: 12,
                  shadowOffset: 3,
                ),
              ),
              // 左下角绿松石三角剪纸装饰
              Positioned(
                bottom: 58.h,
                left: 10.w,
                child: const MemphisShapeBadge(
                  shape: MemphisShapeType.triangle,
                  color: AppTheme.teal,
                  size: 34,
                  tiltDeg: -12,
                  shadowOffset: 2.5,
                ),
              ),
              // 右中侧原子星芒装饰
              Positioned(
                top: 66.h,
                right: 16.w,
                child: const MemphisShapeBadge(
                  shape: MemphisShapeType.ring,
                  color: AppTheme.tomato,
                  size: 32,
                  tiltDeg: 15,
                  shadowOffset: 2.5,
                ),
              ),
              // 左上角波浪线
              Positioned(
                top: 16.h,
                left: 14.w,
                child: Transform.rotate(
                  angle: -0.12,
                  child: const MemphisSquiggle(
                    width: 48,
                    height: 9,
                    color: AppTheme.ink,
                    strokeWidth: 2.4,
                    waves: 3,
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
                child: Column(
                  children: [
                    // 顶部：宝宝小头像 + 金库铭牌 + 连续打卡火焰徽章
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: EdgeInsets.all(2.w),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10.r),
                            boxShadow: AppTheme.paperShadow(h: 4.0),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8.r),
                            child: ImageUtils.displayImage(
                              baby.avatarPath,
                              width: 28.w,
                              height: 28.w,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 12.w, vertical: 4.h),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: AppTheme.paperShadow(h: 4.0),
                          ),
                          child: Text(
                            "${baby.name}的星星金库",
                            style: TextStyle(
                              color: AppTheme.ink,
                              fontSize: 13.5.sp,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (streakDays > 0) ...[
                          SizedBox(width: 6.w),
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 9.w, vertical: 4.h),
                            decoration: BoxDecoration(
                              color: AppTheme.tomato,
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: AppTheme.paperShadow(h: 4.0),
                            ),
                            child: Text(
                              '🔥 连续$streakDays天',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11.sp,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: 10.h),
                    // 中央白底星星数大铭牌 + 今日变化贴纸
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 24.w, vertical: 6.h),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20.r),
                            boxShadow: AppTheme.paperShadow(h: 6.0),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('⭐', style: TextStyle(fontSize: 28.sp)),
                              SizedBox(width: 8.w),
                              TweenAnimationBuilder<int>(
                                tween: IntTween(begin: 0, end: baby.starCount),
                                duration: const Duration(milliseconds: 650),
                                curve: Curves.easeOutCubic,
                                builder: (context, value, _) => Text(
                                  '$value',
                                  style: TextStyle(
                                    fontSize: 44.sp,
                                    height: 1.05,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.ink,
                                    fontFamily: 'MiSans',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8.h),
                    MemphisTag(
                      text: todayDelta == 0
                          ? '今天还没有新记录 · 快去打卡赚星星 ✨'
                          : '今日净得 ${todayDelta > 0 ? '+' : ''}${todayDelta.toInt()} 颗星 🌟',
                      color: todayDelta >= 0 ? AppTheme.teal : AppTheme.tomato,
                      textColor:
                          todayDelta >= 0 ? AppTheme.ink : Colors.white,
                      tiltDeg: -1.8,
                      fontSize: 11.5.sp,
                      padding: EdgeInsets.symmetric(
                          horizontal: 12.w, vertical: 4.h),
                      shadowOffset: 3.0,
                    ),
                    SizedBox(height: 14.h),
                    // 四大高频金刚区（Quick Command Dock）：快捷打卡弹框 / 星星足迹弹框 / 奖励加星 / 提醒扣星
                    Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: 10.w, vertical: 10.h),
                      decoration: BoxDecoration(
                        color: AppTheme.cream.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(18.r),
                        boxShadow: AppTheme.paperShadow(h: 4.0),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildDockCommandBtn(
                              emoji: '⚡',
                              label: '快捷记录',
                              sub: '${controller.actions.length}项习惯',
                              bgColor: AppTheme.teal,
                              textColor: Colors.white,
                              onTap: () => _showQuickActionsSheet(
                                  context, controller, modeController),
                            ),
                          ),
                          SizedBox(width: 8.w),
                          Expanded(
                            child: _buildDockCommandBtn(
                              emoji: '📜',
                              label: '星星足迹',
                              sub: '成长账本',
                              bgColor: AppTheme.cobalt,
                              textColor: Colors.white,
                              onTap: () =>
                                  _showStarFootprintsSheet(context, controller),
                            ),
                          ),
                          SizedBox(width: 8.w),
                          Expanded(
                            child: _buildDockCommandBtn(
                              emoji: '➕',
                              label: '奖励加星',
                              sub: '自由夸奖',
                              bgColor: AppTheme.tomato,
                              textColor: Colors.white,
                              onTap: () {
                                if (modeController.isChildMode) {
                                  Get.snackbar('👀 只能看哦', '让爸爸妈妈来加星星吧~');
                                  return;
                                }
                                _showStarAdjustDialog(controller, true);
                              },
                            ),
                          ),
                          SizedBox(width: 8.w),
                          Expanded(
                            child: _buildDockCommandBtn(
                              emoji: '➖',
                              label: '提醒扣星',
                              sub: '习惯纠正',
                              bgColor: Colors.white,
                              textColor: AppTheme.ink,
                              onTap: () {
                                if (modeController.isChildMode) {
                                  Get.snackbar('👀 只能看哦', '让爸爸妈妈来操作吧~');
                                  return;
                                }
                                _showStarAdjustDialog(controller, false);
                              },
                            ),
                          ),
                        ],
                      ),
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

  /// 主卡底部金刚区单个 Q 弹按钮
  Widget _buildDockCommandBtn({
    required String emoji,
    required String label,
    required String sub,
    required Color bgColor,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return BouncyTap(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 4.w),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14.r),
          boxShadow: AppTheme.paperShadow(h: 4.0),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 30.w,
              height: 30.w,
              decoration: BoxDecoration(
                color: Colors.white.withValues(
                    alpha: bgColor == Colors.white ? 0.0 : 0.22),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(emoji, style: TextStyle(fontSize: 16.sp)),
            ),
            SizedBox(height: 4.h),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5.sp,
                fontWeight: FontWeight.w900,
                color: textColor,
              ),
            ),
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5.sp,
                fontWeight: FontWeight.w700,
                color: textColor.withValues(alpha: 0.82),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 弹框 1：快捷记录底部弹框（支持分类筛选、已打卡角标、管理入口与一键打卡）
  // ===========================================================================
  void _showQuickActionsSheet(
    BuildContext context,
    UserController controller,
    AppModeController modeController,
  ) {
    final RxInt filterMode = 0.obs; // 0: 全部, 1: 奖励好习惯(>0), 2: 提醒待改进(<0)

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.50,
          maxChildSize: 0.92,
          expand: false,
          builder: (_, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: AppTheme.cream,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
                boxShadow: AppTheme.paperShadow(h: 14.0),
              ),
              child: Column(
                children: [
                  SizedBox(height: 10.h),
                  // 顶部拖拽把手
                  Container(
                    width: 44.w,
                    height: 5.h,
                    decoration: BoxDecoration(
                      color: AppTheme.ink.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  // 弹框标题栏
                  Padding(
                    padding: EdgeInsets.fromLTRB(18.w, 12.h, 14.w, 8.h),
                    child: Row(
                      children: [
                        Container(
                          width: 40.w,
                          height: 40.w,
                          decoration: BoxDecoration(
                            color: AppTheme.teal,
                            borderRadius: BorderRadius.circular(12.r),
                            boxShadow: AppTheme.paperShadow(h: 4.0),
                          ),
                          alignment: Alignment.center,
                          child: Text('⚡', style: TextStyle(fontSize: 20.sp)),
                        ),
                        SizedBox(width: 10.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '快捷记录打卡台',
                                style: TextStyle(
                                  fontSize: 17.sp,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.ink,
                                ),
                              ),
                              Text(
                                '点一下习惯卡片，立即奖励或提醒星星',
                                style: TextStyle(
                                  fontSize: 11.5.sp,
                                  color: AppTheme.textSub,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Obx(() => modeController.isChildMode
                            ? const SizedBox()
                            : BouncyTap(
                                onTap: () {
                                  Navigator.of(ctx).pop();
                                  Get.to(() => const ActionSettingsPage());
                                },
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 10.w, vertical: 6.h),
                                  decoration: BoxDecoration(
                                    color: AppTheme.yellow,
                                    borderRadius: BorderRadius.circular(999),
                                    boxShadow: AppTheme.paperShadow(h: 4.0),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.tune_rounded,
                                          size: 15.sp, color: AppTheme.ink),
                                      SizedBox(width: 4.w),
                                      Text(
                                        '管理',
                                        style: TextStyle(
                                          fontSize: 11.5.sp,
                                          fontWeight: FontWeight.w900,
                                          color: AppTheme.ink,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )),
                        SizedBox(width: 6.w),
                        IconButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: Icon(Icons.close_rounded,
                              color: AppTheme.ink, size: 22.sp),
                        ),
                      ],
                    ),
                  ),
                  // 分类筛选胶囊栏
                  Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 18.w, vertical: 6.h),
                    child: Obx(() {
                      final totalCount = controller.actions.length;
                      final posCount =
                          controller.actions.where((a) => a.value > 0).length;
                      final negCount =
                          controller.actions.where((a) => a.value < 0).length;
                      return Row(
                        children: [
                          _buildSheetFilterChip(
                            label: '全部 ($totalCount)',
                            selected: filterMode.value == 0,
                            activeColor: AppTheme.ink,
                            onTap: () => filterMode.value = 0,
                          ),
                          SizedBox(width: 8.w),
                          _buildSheetFilterChip(
                            label: '🌟 奖励好习惯 ($posCount)',
                            selected: filterMode.value == 1,
                            activeColor: AppTheme.teal,
                            onTap: () => filterMode.value = 1,
                          ),
                          SizedBox(width: 8.w),
                          _buildSheetFilterChip(
                            label: '🔔 提醒改进 ($negCount)',
                            selected: filterMode.value == 2,
                            activeColor: AppTheme.tomato,
                            onTap: () => filterMode.value = 2,
                          ),
                        ],
                      );
                    }),
                  ),
                  SizedBox(height: 6.h),
                  // 快捷记录 3 列网格
                  Expanded(
                    child: Obx(() {
                      final all = controller.actions;
                      final list = all.where((a) {
                        if (filterMode.value == 1) return a.value > 0;
                        if (filterMode.value == 2) return a.value < 0;
                        return true;
                      }).toList();

                      if (list.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('🗂️', style: TextStyle(fontSize: 40.sp)),
                              SizedBox(height: 8.h),
                              Text(
                                '该分类下暂无快捷习惯项',
                                style: TextStyle(
                                  color: AppTheme.textSub,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.sp,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return GridView.builder(
                        controller: scrollController,
                        padding: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 28.h),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 10.h,
                          crossAxisSpacing: 10.w,
                          childAspectRatio: 0.90,
                        ),
                        itemCount: list.length,
                        itemBuilder: (context, index) {
                          final action = list[index];
                          return _buildQuickActionCard(
                            controller,
                            action,
                            modeController,
                            _actionTints[index % _actionTints.length],
                          );
                        },
                      );
                    }),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ===========================================================================
  // 弹框 2：星星足迹底部弹框（支持类型筛选、今日汇总、撤销最近一条与分页加载）
  // ===========================================================================
  void _showStarFootprintsSheet(
    BuildContext context,
    UserController controller,
  ) {
    final RxString typeFilter = 'all'.obs; // all | star | piggy | pocket
    final RxInt pageSize = 15.obs;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.78,
          minChildSize: 0.50,
          maxChildSize: 0.92,
          expand: false,
          builder: (_, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: AppTheme.cream,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
                boxShadow: AppTheme.paperShadow(h: 14.0),
              ),
              child: Column(
                children: [
                  SizedBox(height: 10.h),
                  Container(
                    width: 44.w,
                    height: 5.h,
                    decoration: BoxDecoration(
                      color: AppTheme.ink.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  // 顶部标题栏 + 统计胶囊
                  Padding(
                    padding: EdgeInsets.fromLTRB(18.w, 12.h, 14.w, 8.h),
                    child: Row(
                      children: [
                        Container(
                          width: 40.w,
                          height: 40.w,
                          decoration: BoxDecoration(
                            color: AppTheme.cobalt,
                            borderRadius: BorderRadius.circular(12.r),
                            boxShadow: AppTheme.paperShadow(h: 4.0),
                          ),
                          alignment: Alignment.center,
                          child: Text('📜', style: TextStyle(fontSize: 20.sp)),
                        ),
                        SizedBox(width: 10.w),
                        Expanded(
                          child: Obx(() {
                            final todayDelta = _todayStarDelta(controller);
                            final totalLogs = controller.logs.length;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '星星足迹成长账本',
                                  style: TextStyle(
                                    fontSize: 17.sp,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.ink,
                                  ),
                                ),
                                Text(
                                  '累计 $totalLogs 条成长记录 · 今日净得 ${todayDelta >= 0 ? '+' : ''}${todayDelta.toInt()}⭐',
                                  style: TextStyle(
                                    fontSize: 11.5.sp,
                                    color: AppTheme.textSub,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            );
                          }),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: Icon(Icons.close_rounded,
                              color: AppTheme.ink, size: 22.sp),
                        ),
                      ],
                    ),
                  ),
                  // 类型筛选栏
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding:
                        EdgeInsets.symmetric(horizontal: 18.w, vertical: 6.h),
                    child: Obx(() => Row(
                          children: [
                            _buildSheetFilterChip(
                              label: '全部足迹',
                              selected: typeFilter.value == 'all',
                              activeColor: AppTheme.ink,
                              onTap: () => typeFilter.value = 'all',
                            ),
                            SizedBox(width: 8.w),
                            _buildSheetFilterChip(
                              label: '⭐ 星星记录',
                              selected: typeFilter.value == 'star',
                              activeColor: AppTheme.teal,
                              onTap: () => typeFilter.value = 'star',
                            ),
                            SizedBox(width: 8.w),
                            _buildSheetFilterChip(
                              label: '🐷 存钱罐',
                              selected: typeFilter.value == 'piggy',
                              activeColor: AppTheme.pink,
                              onTap: () => typeFilter.value = 'piggy',
                            ),
                            SizedBox(width: 8.w),
                            _buildSheetFilterChip(
                              label: '💰 零花钱',
                              selected: typeFilter.value == 'pocket',
                              activeColor: AppTheme.cobalt,
                              onTap: () => typeFilter.value = 'pocket',
                            ),
                          ],
                        )),
                  ),
                  SizedBox(height: 6.h),
                  // 足迹列表
                  Expanded(
                    child: Obx(() {
                      final filtered = controller.logs.where((l) {
                        if (typeFilter.value == 'all') return true;
                        if (typeFilter.value == 'piggy') {
                          return l.type == 'piggy' || l.type == 'interest';
                        }
                        return l.type == typeFilter.value;
                      }).toList();

                      if (filtered.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('🐣', style: TextStyle(fontSize: 42.sp)),
                              SizedBox(height: 8.h),
                              Text(
                                '还没有足迹记录哦，快去赚第一颗星星吧',
                                style: TextStyle(
                                  color: AppTheme.textSub,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.sp,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      final showCount = filtered.length > pageSize.value
                          ? pageSize.value
                          : filtered.length;

                      return ListView.builder(
                        controller: scrollController,
                        padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 28.h),
                        itemCount:
                            showCount + (filtered.length > showCount ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == showCount) {
                            return Padding(
                              padding: EdgeInsets.only(top: 8.h, bottom: 12.h),
                              child: Center(
                                child: BouncyTap(
                                  onTap: () => pageSize.value += 15,
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 18.w, vertical: 9.h),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(999),
                                      boxShadow: AppTheme.paperShadow(h: 4.0),
                                    ),
                                    child: Text(
                                      '加载更多足迹 (还有 ${filtered.length - showCount} 条) ▾',
                                      style: TextStyle(
                                        fontSize: 12.sp,
                                        fontWeight: FontWeight.w900,
                                        color: AppTheme.ink,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }
                          return _buildLogItem(filtered[index]);
                        },
                      );
                    }),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// 弹框内通用筛选胶囊
  Widget _buildSheetFilterChip({
    required String label,
    required bool selected,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return BouncyTap(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: selected ? activeColor : Colors.white,
          borderRadius: BorderRadius.circular(999),
          boxShadow: AppTheme.paperShadow(h: selected ? 4.0 : 2.0),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5.sp,
            fontWeight: FontWeight.w900,
            color: selected ? Colors.white : AppTheme.ink,
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // 2. 今日好习惯闯关舱（实时进度条 + 快捷习惯一键打卡）
  // ===========================================================================
  Widget _buildInteractiveChallengeHub(
    UserController controller,
    AppModeController modeController,
  ) {
    return Obx(() {
      final positiveActions =
          controller.actions.where((a) => a.value > 0).take(6).toList();
      final doneCount = positiveActions
          .where((a) => _isDoneToday(controller, a.name))
          .length;
      final totalCount = positiveActions.length;
      final progress =
          totalCount == 0 ? 0.0 : (doneCount / totalCount).clamp(0.0, 1.0);

      return Container(
        margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24.r),
          boxShadow: AppTheme.paperShadow(h: 8.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题行 + 今日完成进度胶囊
            Row(
              children: [
                Container(
                  width: 38.w,
                  height: 38.w,
                  decoration: BoxDecoration(
                    color: AppTheme.tomato,
                    borderRadius: BorderRadius.circular(12.r),
                    boxShadow: AppTheme.paperShadow(h: 4.0),
                  ),
                  alignment: Alignment.center,
                  child: Text('🎯', style: TextStyle(fontSize: 19.sp)),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '今日好习惯闯关舱',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15.5.sp,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.ink,
                        ),
                      ),
                      Text(
                        doneCount >= totalCount && totalCount > 0
                            ? '🎉 太棒啦！今日推荐好习惯已全部通关！'
                            : '点一下完成今日习惯，集齐进度解锁大满贯',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: AppTheme.textSub,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 6.w),
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: doneCount >= totalCount && totalCount > 0
                        ? AppTheme.teal
                        : AppTheme.yellow,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: AppTheme.paperShadow(h: 3.0),
                  ),
                  child: Text(
                    '$doneCount / $totalCount 已打卡',
                    style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w900,
                      color: doneCount >= totalCount && totalCount > 0
                          ? Colors.white
                          : AppTheme.ink,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 10.h),
            // 进度条
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8.h,
                backgroundColor: AppTheme.cream,
                valueColor: AlwaysStoppedAnimation<Color>(
                  progress >= 1.0 ? AppTheme.teal : AppTheme.tomato,
                ),
              ),
            ),
            if (positiveActions.isNotEmpty) ...[
              SizedBox(height: 12.h),
              // 日常习惯快打胶囊
              Wrap(
                spacing: 8.w,
                runSpacing: 8.h,
                children: positiveActions.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final act = entry.value;
                  final done = _isDoneToday(controller, act.name);
                  final tint = _actionTints[idx % _actionTints.length];
                  return BouncyTap(
                    onTap: () {
                      if (modeController.isChildMode) {
                        Get.snackbar('👀 只能看哦', '请爸爸妈妈帮忙点亮今日习惯吧~');
                        return;
                      }
                      HapticFeedback.lightImpact();
                      _updateStarsWithFx(
                          controller, act.value.toInt(), act.name);
                    },
                    child: Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 11.w, vertical: 7.h),
                      decoration: BoxDecoration(
                        color: done ? AppTheme.tealSoft : tint.bg,
                        borderRadius: BorderRadius.circular(14.r),
                        boxShadow: AppTheme.paperShadow(h: 3.0),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            done
                                ? '✅'
                                : (act.iconName.isNotEmpty
                                    ? act.iconName
                                    : '⭐'),
                            style: TextStyle(fontSize: 14.sp),
                          ),
                          SizedBox(width: 6.w),
                          Flexible(
                            child: Text(
                              act.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.sp,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.ink,
                              ),
                            ),
                          ),
                          SizedBox(width: 6.w),
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 6.w, vertical: 1.5.h),
                            decoration: BoxDecoration(
                              color: done ? AppTheme.teal : tint.fg,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              done ? '已达成' : '+${act.value}⭐',
                              style: TextStyle(
                                fontSize: 10.sp,
                                fontWeight: FontWeight.w900,
                                color: (done || tint.fg == AppTheme.cobalt)
                                    ? Colors.white
                                    : AppTheme.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      );
    });
  }

  // ===========================================================================
  // 3. Bento 商业双拼看板：「🎁 下一站心愿目标」×「🏦 财富小金库」
  // ===========================================================================
  Widget _buildBentoGoalAndWealthRow(
    UserController controller,
    ShopController shopController,
  ) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 6.h),
      child: Obx(() {
        final baby = controller.currentBaby.value;
        if (baby == null) return const SizedBox();

        // 从未兑换的心愿商品中挑选进度最高（最接近达成）的一个作为牵引目标
        final unredeemed =
            shopController.products.where((p) => !p.isRedeemed).toList();
        Product? targetWish;
        if (unredeemed.isNotEmpty) {
          unredeemed.sort((a, b) => shopController
              .getProgress(b)
              .compareTo(shopController.getProgress(a)));
          targetWish = unredeemed.first;
        }
        final wishProgress =
            targetWish != null ? shopController.getProgress(targetWish) : 0.0;
        final remainStars = targetWish != null
            ? (targetWish.price - baby.starCount).clamp(0, 999999)
            : 0;

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 左卡：心愿目标牵引卡
              Expanded(
                child: Container(
                  padding: EdgeInsets.all(14.w),
                  decoration: BoxDecoration(
                    color: AppTheme.pinkSoft,
                    borderRadius: BorderRadius.circular(22.r),
                    boxShadow: AppTheme.paperShadow(h: 6.0),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 8.w, vertical: 3.h),
                              decoration: BoxDecoration(
                                color: AppTheme.pink,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '🎁 心愿目标',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10.5.sp,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.ink,
                                ),
                              ),
                            ),
                          ),
                          if (targetWish != null) ...[
                            SizedBox(width: 4.w),
                            Text(
                              '${(wishProgress * 100).toInt()}%',
                              style: TextStyle(
                                fontSize: 12.sp,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.ink,
                              ),
                            ),
                          ],
                        ],
                      ),
                      SizedBox(height: 10.h),
                      if (targetWish == null) ...[
                        Text(
                          '还没有许下心愿礼物',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5.sp,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.ink,
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          '去底部「商城」添加宝贝最想要的奖励吧 ✨',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.sp,
                            color: AppTheme.textSub,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ] else ...[
                        Text(
                          targetWish.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5.sp,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.ink,
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          remainStars == 0
                              ? '🎉 星星已攒够(${targetWish.price}⭐)，快去商城兑换！'
                              : '再攒 $remainStars 颗⭐即可兑换 (${baby.starCount}/${targetWish.price})',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.sp,
                            color: AppTheme.textSub,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 8.h),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: wishProgress,
                            minHeight: 7.h,
                            backgroundColor: Colors.white,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              remainStars == 0 ? AppTheme.teal : AppTheme.tomato,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              SizedBox(width: 12.w),
              // 右卡：小金库财富看板
              Expanded(
                child: Container(
                  padding: EdgeInsets.all(14.w),
                  decoration: BoxDecoration(
                    color: AppTheme.tealSoft,
                    borderRadius: BorderRadius.circular(22.r),
                    boxShadow: AppTheme.paperShadow(h: 6.0),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 8.w, vertical: 3.h),
                              decoration: BoxDecoration(
                                color: AppTheme.teal,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '🏦 财富金库',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10.5.sp,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 4.w),
                          Text(
                            '年化${(controller.currentInterestRate.value * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 10.sp,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.teal,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8.h),
                      // 存钱罐余额
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 10.w, vertical: 6.h),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: Row(
                          children: [
                            Text('🐷', style: TextStyle(fontSize: 16.sp)),
                            SizedBox(width: 6.w),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '存钱罐生息中',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 9.5.sp,
                                      color: AppTheme.textSub,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '¥${baby.piggyBankBalance.toStringAsFixed(1)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13.5.sp,
                                      fontWeight: FontWeight.w900,
                                      color: AppTheme.ink,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 6.h),
                      // 零花钱余额
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 10.w, vertical: 6.h),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: Row(
                          children: [
                            Text('👛', style: TextStyle(fontSize: 16.sp)),
                            SizedBox(width: 6.w),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '可用零花钱',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 9.5.sp,
                                      color: AppTheme.textSub,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '¥${baby.pocketMoneyBalance.toStringAsFixed(1)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13.5.sp,
                                      fontWeight: FontWeight.w900,
                                      color: AppTheme.ink,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  // ===========================================================================
  // 4. 跨模块直达横滑舱：🚀 星球乐园 · 今日推荐
  // ===========================================================================
  Widget _buildPlanetPlaygroundCarousel() {
    String weiqiBadge = '启蒙闯关 · 趣味吃子';
    if (Get.isRegistered<WeiqiService>()) {
      final wq = Get.find<WeiqiService>();
      final rank = wq.rankInfo;
      weiqiBadge = '${rank.rank} · ${rank.title}';
    }

    String musicBadge = '黑胶电台 · 睡前儿歌';
    if (Get.isRegistered<MusicPlayerController>()) {
      final mc = Get.find<MusicPlayerController>();
      if (mc.playlist.isNotEmpty) {
        musicBadge = '已藏 ${mc.playlist.length} 首好歌';
      }
    }

    final items = [
      (
        emoji: '⚫',
        title: '棋妙岛围棋',
        sub: weiqiBadge,
        tag: 'AI陪练',
        bg: AppTheme.yellowSoft,
        accent: AppTheme.yellow,
        onTap: () => Get.to(() => const WeiqiHomePage()),
      ),
      (
        emoji: '🎵',
        title: '黑胶音乐厅',
        sub: musicBadge,
        tag: '动态歌词',
        bg: AppTheme.tomatoSoft,
        accent: AppTheme.tomato,
        onTap: () => Get.to(() => const MusicHomePage()),
      ),
      (
        emoji: '📖',
        title: '星海识字绘本',
        sub: 'AI故事互动认汉字',
        tag: '趣味认字',
        bg: AppTheme.cobaltSoft,
        accent: AppTheme.cobalt,
        onTap: () => Get.to(() => const HanziLearningPage()),
      ),
      (
        emoji: '🧠',
        title: '脑筋急转弯',
        sub: '亲子爆笑问答闯关',
        tag: '开动脑筋',
        bg: AppTheme.lilacSoft,
        accent: AppTheme.lilac,
        onTap: () => Get.to(() => const RiddlePage()),
      ),
      (
        emoji: '🔬',
        title: '十万个为什么',
        sub: '探索奇妙科学百科',
        tag: '科学探索',
        bg: AppTheme.tealSoft,
        accent: AppTheme.teal,
        onTap: () => Get.to(() => const EncyclopediaPage()),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(18.w, 10.h, 18.w, 8.h),
          child: Row(
            children: [
              Text(
                '🚀 星球乐园 · 今日推荐',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.ink,
                ),
              ),
              SizedBox(width: 8.w),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                decoration: BoxDecoration(
                  color: AppTheme.yellow,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '寓教于乐',
                  style: TextStyle(
                    fontSize: 10.sp,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 118.h,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
            itemCount: items.length,
            separatorBuilder: (_, __) => SizedBox(width: 10.w),
            itemBuilder: (context, index) {
              final it = items[index];
              return BouncyTap(
                onTap: it.onTap,
                child: Container(
                  width: 148.w,
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20.r),
                    boxShadow: AppTheme.paperShadow(h: 5.0),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 34.w,
                            height: 34.w,
                            decoration: BoxDecoration(
                              color: it.bg,
                              borderRadius: BorderRadius.circular(10.r),
                            ),
                            alignment: Alignment.center,
                            child: Text(it.emoji,
                                style: TextStyle(fontSize: 18.sp)),
                          ),
                          const Spacer(),
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 6.w, vertical: 2.h),
                            decoration: BoxDecoration(
                              color: it.accent,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              it.tag,
                              style: TextStyle(
                                fontSize: 9.sp,
                                fontWeight: FontWeight.w900,
                                color: (it.accent == AppTheme.cobalt ||
                                        it.accent == AppTheme.tomato ||
                                        it.accent == AppTheme.teal)
                                    ? Colors.white
                                    : AppTheme.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        it.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5.sp,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.ink,
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        it.sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5.sp,
                          color: AppTheme.textSub,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // 5. 数据洞察：📊 近 7 日星星能量趋势图（支持点击柱子查看当日明细）
  // ===========================================================================
  Widget _buildWeeklyTrendCard(UserController controller) {
    return Obx(() {
      final now = DateTime.now();
      final days = List.generate(7, (i) {
        final d = now.subtract(Duration(days: 6 - i));
        int gained = 0;
        int lost = 0;
        for (final log in controller.logs) {
          if (log.type != 'star') continue;
          final t = log.timestamp;
          if (t.year == d.year && t.month == d.month && t.day == d.day) {
            if (log.changeAmount > 0) {
              gained += log.changeAmount.toInt();
            } else {
              lost += log.changeAmount.abs().toInt();
            }
          }
        }
        return (
          date: d,
          label: i == 6 ? '今日' : '${d.month}/${d.day}',
          gained: gained,
          lost: lost,
        );
      });

      int maxVal = 1;
      for (final d in days) {
        if (d.gained > maxVal) maxVal = d.gained;
      }

      final selIdx = _selectedChartDayIndex.clamp(0, 6);
      final selDay = days[selIdx];

      return Container(
        margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24.r),
          boxShadow: AppTheme.paperShadow(h: 8.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36.w,
                  height: 36.w,
                  decoration: BoxDecoration(
                    color: AppTheme.yellow,
                    borderRadius: BorderRadius.circular(11.r),
                    boxShadow: AppTheme.paperShadow(h: 3.0),
                  ),
                  alignment: Alignment.center,
                  child: Text('📊', style: TextStyle(fontSize: 18.sp)),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '近 7 日星星能量趋势',
                        style: TextStyle(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.ink,
                        ),
                      ),
                      Text(
                        '点击柱状图查看每天的得星表现',
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: AppTheme.textSub,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                // 选中日期的实时气泡
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: AppTheme.cream,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${selDay.label}: +${selDay.gained}⭐${selDay.lost > 0 ? ' / -${selDay.lost}⭐' : ''}',
                    style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.ink,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 14.h),
            SizedBox(
              height: 104.h,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(7, (index) {
                  final d = days[index];
                  final isSelected = index == selIdx;
                  final ratio = (d.gained / maxVal).clamp(0.12, 1.0);
                  final barColor = isSelected
                      ? AppTheme.tomato
                      : (d.gained > 0 ? AppTheme.teal : AppTheme.cream);

                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _selectedChartDayIndex = index;
                        });
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            d.gained > 0 ? '+${d.gained}' : '0',
                            style: TextStyle(
                              fontSize: 10.sp,
                              fontWeight: FontWeight.w900,
                              color: isSelected
                                  ? AppTheme.tomato
                                  : AppTheme.textSub,
                            ),
                          ),
                          SizedBox(height: 4.h),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 280),
                            curve: Curves.elasticOut,
                            width: isSelected ? 22.w : 16.w,
                            height: (46.h * ratio).clamp(8.h, 46.h),
                            decoration: BoxDecoration(
                              color: barColor,
                              borderRadius: BorderRadius.circular(8.r),
                              boxShadow: isSelected
                                  ? AppTheme.paperShadow(h: 4.0)
                                  : null,
                            ),
                          ),
                          SizedBox(height: 5.h),
                          Text(
                            d.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.sp,
                              fontWeight: isSelected
                                  ? FontWeight.w900
                                  : FontWeight.w700,
                              color:
                                  isSelected ? AppTheme.ink : AppTheme.textSub,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      );
    });
  }

  // ===========================================================================
  // 6. 商业级实时成长信息流：✨ 星球成长喜报流（带喝彩点赞交互 + 打开星星足迹弹框）
  // ===========================================================================
  Widget _buildLiveActivityFeed(
    UserController controller,
    AppModeController modeController,
  ) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24.r),
        boxShadow: AppTheme.paperShadow(h: 8.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 信息流头部
          Row(
            children: [
              Container(
                width: 36.w,
                height: 36.w,
                decoration: BoxDecoration(
                  color: AppTheme.pink,
                  borderRadius: BorderRadius.circular(11.r),
                  boxShadow: AppTheme.paperShadow(h: 3.0),
                ),
                alignment: Alignment.center,
                child: Text('✨', style: TextStyle(fontSize: 18.sp)),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '星球成长动态流',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5.sp,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.ink,
                      ),
                    ),
                    Text(
                      '记录宝贝每一次进步，点个👏为TA喝彩',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: AppTheme.textSub,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 6.w),
              BouncyTap(
                onTap: () => _showStarFootprintsSheet(context, controller),
                child: Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
                  decoration: BoxDecoration(
                    color: AppTheme.cobalt,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: AppTheme.paperShadow(h: 3.0),
                  ),
                  child: Text(
                    '全部足迹 ›',
                    style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Obx(() {
            final recent = controller.logs.take(5).toList();
            if (recent.isEmpty) {
              return Container(
                padding: EdgeInsets.symmetric(vertical: 22.h, horizontal: 16.w),
                decoration: BoxDecoration(
                  color: AppTheme.cream,
                  borderRadius: BorderRadius.circular(18.r),
                ),
                child: Center(
                  child: Column(
                    children: [
                      Text('🌟', style: TextStyle(fontSize: 34.sp)),
                      SizedBox(height: 6.h),
                      Text(
                        '暂时还没有成长动态，快点击上方「⚡ 快捷记录」打卡吧！',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: AppTheme.textSub,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return Column(
              children: [
                ...recent.map((log) => _buildFeedCardItem(log)),
                SizedBox(height: 6.h),
                // 底部唤起完整星星足迹弹框按钮
                BouncyTap(
                  onTap: () => _showStarFootprintsSheet(context, controller),
                  child: Container(
                    width: double.infinity,
                    padding:
                        EdgeInsets.symmetric(vertical: 11.h, horizontal: 12.w),
                    decoration: BoxDecoration(
                      color: AppTheme.cream,
                      borderRadius: BorderRadius.circular(16.r),
                      boxShadow: AppTheme.paperShadow(h: 3.0),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '📜 打开完整星星足迹账本 (共 ${controller.logs.length} 条记录) ›',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5.sp,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.ink,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  /// 信息流单条动态喜报卡（带 👏 喝彩点赞按钮，全自适应防溢出布局）
  Widget _buildFeedCardItem(Log log) {
    final isPositive = log.changeAmount >= 0;
    String badgeText = '🌟 喜报';
    Color badgeColor = AppTheme.teal;
    String unit = '⭐';

    if (log.type == 'piggy' || log.type == 'interest') {
      badgeText = log.type == 'interest' ? '📈 生息' : '🐷 存钱罐';
      badgeColor = AppTheme.pink;
      unit = '元';
    } else if (log.type == 'pocket') {
      badgeText = '👛 零花钱';
      badgeColor = AppTheme.cobalt;
      unit = '元';
    } else if (!isPositive) {
      badgeText = '🔔 提醒';
      badgeColor = AppTheme.tomato;
    }

    final logKey =
        '${log.timestamp.millisecondsSinceEpoch}_${log.description}';
    final claps = _feedClapCounts[logKey] ?? 1;

    return Container(
      margin: EdgeInsets.only(bottom: 10.h),
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: AppTheme.cream,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: AppTheme.paperShadow(h: 3.0),
      ),
      child: Row(
        children: [
          Container(
            width: 36.w,
            height: 36.w,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(11.r),
            ),
            alignment: Alignment.center,
            child: Text(
              isPositive ? '🏆' : '⚡',
              style: TextStyle(fontSize: 18.sp),
            ),
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: 6.w, vertical: 1.5.h),
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        badgeText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9.5.sp,
                          fontWeight: FontWeight.w900,
                          color: badgeColor == AppTheme.pink
                              ? AppTheme.ink
                              : Colors.white,
                        ),
                      ),
                    ),
                    SizedBox(width: 6.w),
                    Flexible(
                      child: Text(
                        '${log.timestamp.month}/${log.timestamp.day} ${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.sp,
                          color: AppTheme.textSub,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 3.h),
                Text(
                  log.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.ink,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 6.w),
          // 变动数值胶囊
          Container(
            padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 3.5.h),
            decoration: BoxDecoration(
              color: isPositive ? AppTheme.yellow : AppTheme.tomato,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${isPositive ? '+' : ''}${unit == '⭐' ? log.changeAmount.toInt() : log.changeAmount.toStringAsFixed(1)}$unit',
              style: TextStyle(
                fontSize: 11.sp,
                fontWeight: FontWeight.w900,
                color: isPositive ? AppTheme.ink : Colors.white,
              ),
            ),
          ),
          SizedBox(width: 5.w),
          // 👏 喝彩点赞互动按钮
          BouncyTap(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() {
                _feedClapCounts[logKey] = claps + 1;
              });
            },
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 3.5.h),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('👏', style: TextStyle(fontSize: 11.5.sp)),
                  SizedBox(width: 2.w),
                  Text(
                    '$claps',
                    style: TextStyle(
                      fontSize: 10.5.sp,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 星星足迹弹框内的单条日志卡片
  Widget _buildLogItem(Log log) {
    final isPositive = log.changeAmount > 0;
    final accent = isPositive ? AppTheme.teal : AppTheme.tomato;
    final accentBg = isPositive ? AppTheme.tealSoft : AppTheme.tomatoSoft;
    final isStar = log.type == 'star';
    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14.r),
        boxShadow: AppTheme.paperShadow(h: 4.0),
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
              color: AppTheme.ink,
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
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5.sp,
                    color: AppTheme.ink,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  "${log.timestamp.month}-${log.timestamp.day} ${log.timestamp.hour}:${log.timestamp.minute.toString().padLeft(2, '0')}",
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: AppTheme.textSub,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              isStar
                  ? "${isPositive ? '+' : ''}${log.changeAmount.toInt()} ⭐"
                  : "${isPositive ? '+' : ''}¥${log.changeAmount.toStringAsFixed(1)}",
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w900,
                color: Colors.white,
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
      initialValue: value,
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
