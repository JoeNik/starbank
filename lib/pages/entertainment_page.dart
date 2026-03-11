import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../theme/app_theme.dart';
import 'riddle_page.dart';
import 'story/story_game_page.dart';
import 'entertainment/music/music_home_page.dart';
import 'entertainment/quiz/quiz_page.dart';
import 'entertainment/new_year_story/new_year_story_page.dart';
import 'entertainment/hanzi_learning/hanzi_learning_page.dart';

/// 娱乐模块入口页面
class EntertainmentPage extends StatelessWidget {
  const EntertainmentPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPink,
      appBar: AppBar(
        title: const Text('娱乐乐园'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.all(16.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 欢迎语
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(20.w),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFFF6B9D),
                      Color(0xFFFF8E53),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24.r),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF6B9D).withOpacity(0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🎉 欢迎来到娱乐乐园！',
                      style: TextStyle(
                        fontSize: 22.sp,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    Text(
                      '这里有好玩的游戏和益智学习',
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 24.h),

              // 功能分类
              Text(
                '🎮 益智游戏',
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textMain,
                ),
              ),
              SizedBox(height: 12.h),

              // 功能卡片网格
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 16.w,
                crossAxisSpacing: 16.w,
                childAspectRatio: 0.9,
                children: [
                  // 脑筋急转弯
                  _buildFeatureCard(
                    emoji: '🤔',
                    title: '脑筋急转弯',
                    subtitle: '100+趣味问答',
                    color: const Color(0xFFFFB74D),
                    onTap: () => Get.to(() => const RiddlePage()),
                  ),
                  // 看图讲故事
                  _buildFeatureCard(
                    emoji: '📚',
                    title: '看图讲故事',
                    subtitle: 'AI引导讲故事',
                    color: const Color(0xFF81C784),
                    onTap: () => Get.to(() => const StoryGamePage()),
                  ),
                  // 音乐播放器
                  _buildFeatureCard(
                    emoji: '🎵',
                    title: '儿歌播放器',
                    subtitle: '海量儿歌随心听',
                    color: const Color(0xFF64B5F6),
                    onTap: () => Get.to(() => const MusicHomePage()),
                  ),
                  // 新年知多少
                  _buildFeatureCard(
                    emoji: '🧧',
                    title: '新年知多少',
                    subtitle: '小年兽问答',
                    color: const Color(0xFFEF5350),
                    onTap: () => Get.to(() => const QuizPage()),
                  ),
                  // 新年故事听听
                  _buildFeatureCard(
                    emoji: '📖',
                    title: '新年故事',
                    subtitle: '语音绘本模式',
                    color: const Color(0xFFAB47BC),
                    onTap: () => Get.to(() => const NewYearStoryPage()),
                  ),
                ],
              ),
              SizedBox(height: 24.h),

              // 学习分类
              Text(
                '📚 趣味学习',
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textMain,
                ),
              ),
              SizedBox(height: 12.h),

              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 16.w,
                crossAxisSpacing: 16.w,
                childAspectRatio: 0.9,
                children: [
                  _buildFeatureCard(
                    emoji: '🔤',
                    title: '星海识字',
                    subtitle: 'AI趣味识字',
                    color: const Color(0xFF7C4DFF),
                    onTap: () => Get.to(() => const HanziLearningPage()),
                  ),
                  _buildFeatureCard(
                    emoji: '🔢',
                    title: '数学乐园',
                    subtitle: '敬请期待',
                    color: Colors.grey.shade300,
                    isComingSoon: true,
                    onTap: () {},
                  ),
                ],
              ),
              SizedBox(height: 20.h),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureCard({
    required String emoji,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    bool isComingSoon = false,
  }) {
    return GestureDetector(
      onTap: isComingSoon ? null : onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24.r),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(isComingSoon ? 0.1 : 0.2),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.all(16.w),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Emoji 图标
                  Container(
                    width: 64.w,
                    height: 64.w,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20.r),
                    ),
                    child: Center(
                      child: Text(
                        emoji,
                        style: TextStyle(fontSize: 32.sp),
                      ),
                    ),
                  ),
                  SizedBox(height: 12.h),
                  // 标题
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold,
                      color: isComingSoon ? Colors.grey : AppTheme.textMain,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  // 副标题
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
            // 敬请期待标签
            if (isComingSoon)
              Positioned(
                top: 12.w,
                right: 12.w,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Text(
                    '即将上线',
                    style: TextStyle(
                      fontSize: 10.sp,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
