import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../controllers/user_controller.dart';
import '../models/action_item.dart';
import '../theme/app_theme.dart';
import 'dart:math';

/// 快捷记录管理页面
class ActionSettingsPage extends StatelessWidget {
  const ActionSettingsPage({super.key});

  // 随机 Emoji 列表 - 丰富表情支持
  static const List<String> emojiList = [
    // ⏰ 时间与日常
    '⏰', '🌅', '🌙', '☀️', '🌈', '⭐', '✨', '💫', '🕐', '⏳', '📅', '🗓️',
    // 🍚 饮食
    '🍚', '🍼', '🍎', '🥗', '🍳', '🥛', '🍰', '🍕', '🍜', '🥤', '🍪', '🍓',
    '🍌', '🥕', '🥦', '🍞', '🥚', '🧀', '🍦', '🍫', '🍇', '🍉', '🥝', '🍑',
    // 📚 学习
    '📚', '📖', '✏️', '📝', '🎒', '💡', '🔬', '🎓', '🧮', '📐', '🖊️', '📓',
    '🔢', '🔤', '🎹', '🖼️', '🧩', '🔍', '💻', '📱',
    // 🏃 运动健康
    '🏃', '⚽', '🏀', '🎾', '🚴', '🏊', '💪', '🧘', '🤸', '⛹️', '🏸', '🥋',
    '🎿', '⛸️', '🛹', '🏓', '🥅', '🎳', '🏋️', '🤾',
    // 🚿 生活习惯
    '🚿', '🦷', '🧹', '🛏️', '👕', '🧺', '🗑️', '🪥', '🧼', '🪣', '🧴', '👟',
    '🩴', '🧦', '👖', '🧥', '🎽', '🪮', '💈', '🛁',
    // 📺 娱乐
    '📺', '🎮', '🎵', '🎨', '🧸', '🎭', '🎪', '🎬', '🎤', '🎧', '🎸', '🥁',
    '🎺', '🎻', '🪘', '🎲', '🧩', '🪀', '🪁', '🎠',
    // 😊 表情心情
    '😊', '😇', '🥰', '😎', '🤗', '😤', '😢', '😴', '🥺', '😃', '🤩', '😋',
    '🤔', '😌', '😏', '🙄', '😬', '🤭', '🥳', '😍',
    // 🏆 奖励惩罚
    '🏆', '🥇', '🎖️', '🎁', '💰', '👏', '👍', '👿', '🥈', '🥉', '🏅', '💵',
    '💎', '👑', '🎀', '🧧', '💯', '✅', '❌', '⚠️',
    // 🐾 动物
    '🐶', '🐱', '🐰', '🐻', '🐼', '🦁', '🐯', '🐮', '🐷', '🐸', '🐵', '🦊',
    '🐔', '🐧', '🦋', '🐢', '🐟', '🦄', '🐘', '🦒',
    // 🌸 自然
    '🌸', '🌺', '🌻', '🌷', '🌹', '🍀', '🌲', '🌴', '🍁', '🍂', '🌾', '🌵',
    // 🚗 交通
    '🚗', '🚌', '🚂', '✈️', '🚀', '🛸', '🚁', '⛵', '🚲', '🛴',
    // 🎯 其他
    '🔔', '💤', '🎯', '🚀', '💎', '🌟', '❤️', '🔥', '💖', '💕', '🙏', '✋',
    '👋', '🤝', '💪', '🦶', '👀', '👂', '🧠', '💭',
  ];

  /// 获取随机 Emoji
  static String getRandomEmoji() {
    return emojiList[Random().nextInt(emojiList.length)];
  }

  @override
  Widget build(BuildContext context) {
    final UserController controller = Get.find<UserController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('快捷记录管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => _showAddActionDialog(controller),
          ),
        ],
      ),
      backgroundColor: AppTheme.bgBlue,
      body: Obx(() {
        final actions = controller.actions;
        if (actions.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.flash_on, size: 60.sp, color: Colors.grey.shade300),
                SizedBox(height: 16.h),
                Text(
                  '还没有快捷记录',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                SizedBox(height: 20.h),
                ElevatedButton.icon(
                  onPressed: () => _showAddActionDialog(controller),
                  icon: const Icon(Icons.add),
                  label: const Text('添加快捷记录'),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            Padding(
              padding: EdgeInsets.all(16.w),
              child: Text(
                '💡 长按拖动可调整顺序',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12.sp),
              ),
            ),
            Expanded(
              child: ReorderableListView.builder(
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                itemCount: actions.length,
                onReorder: (oldIndex, newIndex) {
                  controller.reorderAction(oldIndex, newIndex);
                },
                itemBuilder: (context, index) {
                  final action = actions[index];
                  return _buildActionTile(controller, action, index);
                },
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildActionTile(
      UserController controller, ActionItem action, int index) {
    final isPositive = action.value > 0;

    // 排序后 index 会变；用 syncId（或内容指纹）做稳定 key，避免 ReorderableListView 错乱
    final stableKey = action.syncId?.isNotEmpty == true
        ? action.syncId!
        : '${action.name}|${action.value}|${action.iconName}|$index';
    return Card(
      key: ValueKey(stableKey),
      margin: EdgeInsets.only(bottom: 12.h),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
      child: ListTile(
        leading: Container(
          width: 48.w,
          height: 48.w,
          decoration: BoxDecoration(
            color: isPositive
                ? Colors.green.withOpacity(0.1)
                : Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12.r),
          ),
          child: Center(
            child: Text(
              action.iconName.isNotEmpty ? action.iconName : '⭐️',
              style: TextStyle(fontSize: 24.sp),
            ),
          ),
        ),
        title: Text(
          action.name,
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${isPositive ? '+' : ''}${action.value.toInt()} 颗星星',
          style: TextStyle(
            color: isPositive ? Colors.green : Colors.red,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: AppTheme.textSub),
              onPressed: () => _showEditActionDialog(controller, action, index),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.red.shade300),
              onPressed: () => _confirmDeleteAction(controller, action, index),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddActionDialog(UserController controller) {
    final nameController = TextEditingController();
    final valueController = TextEditingController(text: '1');
    final RxString selectedEmoji = getRandomEmoji().obs;
    final RxBool isPositive = true.obs;

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
              Text(
                '添加快捷记录',
                style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 20.h),

              // Emoji 选择
              GestureDetector(
                onTap: () => _showEmojiPicker(selectedEmoji),
                child: Obx(() => Container(
                      width: 80.w,
                      height: 80.w,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20.r),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Center(
                        child: Text(
                          selectedEmoji.value,
                          style: TextStyle(fontSize: 40.sp),
                        ),
                      ),
                    )),
              ),
              TextButton(
                onPressed: () => selectedEmoji.value = getRandomEmoji(),
                child: const Text('🎲 随机换一个'),
              ),

              SizedBox(height: 16.h),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '记录名称',
                  hintText: '例如: 按时起床、主动学习',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 16.h),

              // 类型选择
              Obx(() => Row(
                    children: [
                      const Text('类型: '),
                      SizedBox(width: 8.w),
                      ChoiceChip(
                        label: const Text('加星星 ⭐'),
                        selected: isPositive.value,
                        selectedColor: Colors.green.withOpacity(0.2),
                        onSelected: (_) => isPositive.value = true,
                      ),
                      SizedBox(width: 8.w),
                      ChoiceChip(
                        label: const Text('扣星星 💔'),
                        selected: !isPositive.value,
                        selectedColor: Colors.red.withOpacity(0.2),
                        onSelected: (_) => isPositive.value = false,
                      ),
                    ],
                  )),

              SizedBox(height: 16.h),
              TextField(
                controller: valueController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '星星数量',
                  hintText: '1',
                  border: OutlineInputBorder(),
                ),
              ),

              SizedBox(height: 24.h),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (nameController.text.isNotEmpty) {
                      final value = int.tryParse(valueController.text) ?? 1;
                      controller.addAction(ActionItem(
                        name: nameController.text,
                        type: isPositive.value ? 'reward' : 'punish',
                        value: isPositive.value
                            ? value.toDouble()
                            : -value.toDouble(),
                        iconName: selectedEmoji.value,
                      ));
                      Get.back();
                    }
                  },
                  child: const Text('添加'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditActionDialog(
      UserController controller, ActionItem action, int index) {
    final nameController = TextEditingController(text: action.name);
    final valueController = TextEditingController(
      text: action.value.abs().toInt().toString(),
    );
    final RxString selectedEmoji =
        (action.iconName.isEmpty ? '⭐️' : action.iconName).obs;
    final RxBool isPositive = (action.value > 0).obs;

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
              Text(
                '编辑快捷记录',
                style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 20.h),

              // Emoji 选择
              GestureDetector(
                onTap: () => _showEmojiPicker(selectedEmoji),
                child: Obx(() => Container(
                      width: 80.w,
                      height: 80.w,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20.r),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Center(
                        child: Text(
                          selectedEmoji.value,
                          style: TextStyle(fontSize: 40.sp),
                        ),
                      ),
                    )),
              ),
              TextButton(
                onPressed: () => selectedEmoji.value = getRandomEmoji(),
                child: const Text('🎲 随机换一个'),
              ),

              SizedBox(height: 16.h),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '记录名称',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 16.h),

              // 类型选择
              Obx(() => Row(
                    children: [
                      const Text('类型: '),
                      SizedBox(width: 8.w),
                      ChoiceChip(
                        label: const Text('加星星 ⭐'),
                        selected: isPositive.value,
                        selectedColor: Colors.green.withOpacity(0.2),
                        onSelected: (_) => isPositive.value = true,
                      ),
                      SizedBox(width: 8.w),
                      ChoiceChip(
                        label: const Text('扣星星 💔'),
                        selected: !isPositive.value,
                        selectedColor: Colors.red.withOpacity(0.2),
                        onSelected: (_) => isPositive.value = false,
                      ),
                    ],
                  )),

              SizedBox(height: 16.h),
              TextField(
                controller: valueController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '星星数量',
                  border: OutlineInputBorder(),
                ),
              ),

              SizedBox(height: 24.h),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (nameController.text.isNotEmpty) {
                      final value = int.tryParse(valueController.text) ?? 1;
                      controller.updateAction(
                        index,
                        nameController.text,
                        isPositive.value ? value.toDouble() : -value.toDouble(),
                        selectedEmoji.value,
                      );
                      Get.back();
                    }
                  },
                  child: const Text('保存修改'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEmojiPicker(RxString selectedEmoji) {
    Get.bottomSheet(
      Container(
        height: 400.h, // 固定高度
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
        ),
        child: Column(
          children: [
            Text(
              '选择图标',
              style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16.h),
            // 使用 Expanded + GridView 使其可滑动
            Expanded(
              child: GridView.builder(
                physics: const BouncingScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6, // 每行6个
                  childAspectRatio: 1,
                  crossAxisSpacing: 8.w,
                  mainAxisSpacing: 8.h,
                ),
                itemCount: emojiList.length,
                itemBuilder: (context, index) {
                  final emoji = emojiList[index];
                  return GestureDetector(
                    onTap: () {
                      selectedEmoji.value = emoji;
                      Get.back();
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      child: Center(
                        child: Text(emoji, style: TextStyle(fontSize: 24.sp)),
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(height: 12.h),
            // 随机按钮
            TextButton.icon(
              onPressed: () {
                selectedEmoji.value = getRandomEmoji();
                Get.back();
              },
              icon: const Text('🎲'),
              label: const Text('随机选择'),
            ),
          ],
        ),
      ),
      isScrollControlled: true, // 允许更高的 bottom sheet
    );
  }

  void _confirmDeleteAction(
      UserController controller, ActionItem action, int index) {
    Get.defaultDialog(
      title: '确认删除',
      middleText: '确定要删除「${action.name}」吗？',
      textConfirm: '删除',
      textCancel: '取消',
      confirmTextColor: Colors.white,
      buttonColor: Colors.red,
      onConfirm: () async {
        await controller.deleteAction(index);
        Get.back();
      },
    );
  }
}
