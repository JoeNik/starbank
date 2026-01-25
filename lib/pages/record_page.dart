import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../controllers/user_controller.dart';
import '../theme/app_theme.dart';
import 'poop/poop_record_page.dart';

/// 记录模块入口页面
/// 包含宝宝健康相关的各种记录功能
class RecordPage extends StatelessWidget {
  const RecordPage({super.key});

  @override
  Widget build(BuildContext context) {
    final userController = Get.find<UserController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('宝宝记录'),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          // 当前宝宝提示
          Obx(() {
            final baby = userController.currentBaby.value;
            if (baby == null) {
              return Container(
                margin: EdgeInsets.all(16.w),
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber,
                        color: Colors.orange, size: 24.sp),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Text(
                        '请先在主页选择或添加宝宝',
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }
            return Container(
              margin: EdgeInsets.all(16.w),
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.primaryLight, AppTheme.primary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20.r,
                    backgroundColor: Colors.white,
                    child: Text(
                      baby.name.isNotEmpty ? baby.name[0] : '宝',
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '当前记录：${baby.name}',
                          style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          '所有记录将关联到此宝宝',
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),

          // 功能列表
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              children: [
                // 便便记录
                _buildFeatureCard(
                  icon: Icons.calendar_month,
                  iconColor: Colors.brown,
                  title: '便便记录',
                  subtitle: '记录宝宝排便情况，AI 智能分析',
                  onTap: () => Get.to(() => const PoopRecordPage()),
                ),

                SizedBox(height: 12.h),

                // 其他功能（预留）
                _buildFeatureCard(
                  icon: Icons.restaurant,
                  iconColor: Colors.orange,
                  title: '喂养记录',
                  subtitle: '记录宝宝饮食情况（开发中）',
                  onTap: () => _showComingSoon('喂养记录'),
                  enabled: false,
                ),

                SizedBox(height: 12.h),

                _buildFeatureCard(
                  icon: Icons.bedtime,
                  iconColor: Colors.indigo,
                  title: '睡眠记录',
                  subtitle: '记录宝宝睡眠情况（开发中）',
                  onTap: () => _showComingSoon('睡眠记录'),
                  enabled: false,
                ),

                SizedBox(height: 12.h),

                _buildFeatureCard(
                  icon: Icons.height,
                  iconColor: Colors.green,
                  title: '生长记录',
                  subtitle: '记录身高体重变化（开发中）',
                  onTap: () => _showComingSoon('生长记录'),
                  enabled: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(12.r),
          child: Padding(
            padding: EdgeInsets.all(16.w),
            child: Row(
              children: [
                Container(
                  width: 56.w,
                  height: 56.w,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Icon(
                    icon,
                    color: iconColor,
                    size: 28.sp,
                  ),
                ),
                SizedBox(width: 16.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: Colors.grey,
                  size: 24.sp,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showComingSoon(String feature) {
    Get.snackbar(
      '敬请期待',
      '$feature 功能正在开发中',
      snackPosition: SnackPosition.BOTTOM,
    );
  }
}
