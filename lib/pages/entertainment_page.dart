import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../theme/app_theme.dart';
import '../widgets/memphis_widgets.dart';
import '../widgets/module_background_scene.dart';
import 'riddle_page.dart';
import 'story/story_game_page.dart';
import 'entertainment/music/music_home_page.dart';
import 'entertainment/quiz/quiz_page.dart';
import 'entertainment/new_year_story/new_year_story_page.dart';
import 'entertainment/hanzi_learning/hanzi_learning_page.dart';
import 'entertainment/encyclopedia/encyclopedia_page.dart';
import 'entertainment/pinyin_learning/pinyin_learning_page.dart';
import 'entertainment/math/math_calculator_page.dart';
import 'entertainment/weiqi/weiqi_home_page.dart';

/// 017 · 中世纪现代（Mid-Century Modern）风格娱乐模块入口页面
/// 致敬 Saul Bass 剪纸美学与 Eames 糖果色纸片高度体系
class EntertainmentPage extends StatelessWidget {
  const EntertainmentPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.cream,
      appBar: AppBar(
        title: const Text('娱乐乐园'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: ModuleBackgroundScene(
              theme: ModuleBackgroundTheme.entertainment,
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.all(16.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 中世纪现代剪纸欢迎横幅（番茄红主色 + 太阳叠印 + 暖棕高度阴影 h=14）
                  BouncyTap(
                    onTap: () => Get.to(() => const MusicHomePage()),
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppTheme.tomato,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(24.r),
                          topRight: Radius.circular(18.r),
                          bottomLeft: Radius.circular(20.r),
                          bottomRight: Radius.circular(26.r),
                        ),
                        boxShadow: AppTheme.paperShadow(h: 14.0),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22.r),
                        child: Stack(
                          children: [
                            Positioned(
                              top: -10.w,
                              right: -8.w,
                              child: const MemphisShapeBadge(
                                shape: MemphisShapeType.circle,
                                color: AppTheme.yellow,
                                size: 78,
                                tiltDeg: 10,
                                shadowOffset: 3,
                              ),
                            ),
                            Positioned(
                              bottom: 10.h,
                              right: 22.w,
                              child: const MemphisShapeBadge(
                                shape: MemphisShapeType.triangle,
                                color: AppTheme.teal,
                                size: 36,
                                tiltDeg: -12,
                                shadowOffset: 2.5,
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.all(18.w),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  MemphisTag(
                                    text: 'MID-CENTURY 1955 ✦',
                                    color: AppTheme.yellow,
                                    tiltDeg: -2.5,
                                    fontSize: 10.5.sp,
                                    shadowOffset: 2.5,
                                  ),
                                  SizedBox(height: 10.h),
                                  Text(
                                    '🎉 欢迎来到娱乐乐园！',
                                    style: TextStyle(
                                      fontSize: 21.sp,
                                      fontWeight: FontWeight.w900,
                                      color: AppTheme.paperWhite,
                                    ),
                                  ),
                                  SizedBox(height: 6.h),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 10.w, vertical: 5.h),
                                    decoration: BoxDecoration(
                                      color: AppTheme.cream,
                                      borderRadius: BorderRadius.circular(9.r),
                                      boxShadow: AppTheme.paperShadow(h: 4.0),
                                    ),
                                    child: Text(
                                      '剪纸手作温度 · 点一张彩纸马上出发！',
                                      style: TextStyle(
                                        fontSize: 12.sp,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.ink,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 24.h),

                  // 益智游戏分类标题
                  _buildCategoryHeader('🎮 益智游戏', AppTheme.yellow),
                  SizedBox(height: 14.h),

                  // 功能卡片网格
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 16.w,
                    crossAxisSpacing: 16.w,
                    childAspectRatio: 0.9,
                    children: [
                      _buildFeatureCard(
                        emoji: '🤔',
                        title: '脑筋急转弯',
                        subtitle: '100+趣味问答',
                        color: AppTheme.yellow,
                        cardBg: AppTheme.paperWhite,
                        onTap: () => Get.to(() => const RiddlePage()),
                      ),
                      _buildFeatureCard(
                        emoji: '📚',
                        title: '看图讲故事',
                        subtitle: 'AI引导讲故事',
                        color: AppTheme.teal,
                        cardBg: AppTheme.paperWhite,
                        onTap: () => Get.to(() => const StoryGamePage()),
                      ),
                      _buildFeatureCard(
                        emoji: '🎵',
                        title: '儿歌播放器',
                        subtitle: '黑胶唱机 · 随心听',
                        color: AppTheme.tomato,
                        cardBg: AppTheme.paperWhite,
                        badgeText: 'HI-FI',
                        onTap: () => Get.to(() => const MusicHomePage()),
                      ),
                      _buildFeatureCard(
                        emoji: '🧧',
                        title: '新年知多少',
                        subtitle: '小年兽问答',
                        color: AppTheme.pink,
                        cardBg: AppTheme.paperWhite,
                        onTap: () => Get.to(() => const QuizPage()),
                      ),
                      _buildFeatureCard(
                        emoji: '📖',
                        title: '新年故事',
                        subtitle: '语音绘本模式',
                        color: AppTheme.cobalt,
                        cardBg: AppTheme.paperWhite,
                        onTap: () => Get.to(() => const NewYearStoryPage()),
                      ),
                    ],
                  ),
                  SizedBox(height: 26.h),

                  // 趣味学习分类标题
                  _buildCategoryHeader('📚 趣味学习', AppTheme.teal),
                  SizedBox(height: 14.h),

                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 16.w,
                    crossAxisSpacing: 16.w,
                    childAspectRatio: 0.9,
                    children: [
                      // 棋妙岛围棋（纯学习模块，全面进化版）
                      _buildFeatureCard(
                        emoji: '⚫',
                        title: '棋妙岛围棋',
                        subtitle: '闯关 · 围地 · AI考级',
                        color: AppTheme.teal,
                        cardBg: AppTheme.yellowSoft,
                        badgeText: 'PRO',
                        onTap: () => Get.to(() => const WeiqiHomePage()),
                      ),
                      _buildFeatureCard(
                        emoji: '🌍',
                        title: '生活科学百科',
                        subtitle: '一问一答学知识',
                        color: AppTheme.cobalt,
                        cardBg: AppTheme.paperWhite,
                        onTap: () => Get.to(() => const EncyclopediaPage()),
                      ),
                      _buildFeatureCard(
                        emoji: '🔤',
                        title: '星海识字',
                        subtitle: 'AI趣味识字',
                        color: AppTheme.tomato,
                        cardBg: AppTheme.paperWhite,
                        onTap: () => Get.to(() => const HanziLearningPage()),
                      ),
                      _buildFeatureCard(
                        emoji: '🗣️',
                        title: '拼音小耳朵',
                        subtitle: '听准声母韵母',
                        color: AppTheme.pink,
                        cardBg: AppTheme.paperWhite,
                        onTap: () => Get.to(() => const PinyinLearningPage()),
                      ),
                      _buildFeatureCard(
                        emoji: '🔢',
                        title: '数学乐园',
                        subtitle: '计算器和练习题',
                        color: AppTheme.yellow,
                        cardBg: AppTheme.paperWhite,
                        onTap: () => Get.to(() => const MathCalculatorPage()),
                      ),
                    ],
                  ),
                  SizedBox(height: 20.h),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建中世纪现代分类标题行（剪纸彩片 + Eames 钢丝彩球线）
  Widget _buildCategoryHeader(String title, Color tagColor) {
    final isDark = tagColor == AppTheme.tomato || tagColor == AppTheme.cobalt;
    return Row(
      children: [
        Transform.rotate(
          angle: -0.025,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
            decoration: BoxDecoration(
              color: tagColor,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(14.r),
                topRight: Radius.circular(10.r),
                bottomLeft: Radius.circular(11.r),
                bottomRight: Radius.circular(15.r),
              ),
              boxShadow: AppTheme.paperShadow(h: 6.0),
            ),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w900,
                color: isDark ? AppTheme.paperWhite : AppTheme.ink,
              ),
            ),
          ),
        ),
        SizedBox(width: 12.w),
        const Expanded(
          child: MemphisSquiggle(
            height: 12,
            color: AppTheme.ink,
            strokeWidth: 2.0,
            waves: 6,
          ),
        ),
      ],
    );
  }

  /// 构建中世纪现代功能剪纸卡片（带 Q 弹物理缩放与暖棕高度投影）
  Widget _buildFeatureCard({
    required String emoji,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    Color cardBg = AppTheme.paperWhite,
    String? badgeText,
    bool isComingSoon = false,
  }) {
    return MemphisCard(
      color: cardBg,
      borderRadius: 20.r,
      shadowOffset: 5.5,
      onTap: isComingSoon ? null : onTap,
      child: Stack(
        children: [
          Center(
            child: Padding(
              padding: EdgeInsets.all(14.w),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Emoji 图标剪纸底座（无粗黑边 + 暖棕高度影子 h=7）
                  Transform.rotate(
                    angle: -0.03,
                    child: Container(
                      width: 62.w,
                      height: 62.w,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(20.r),
                          topRight: Radius.circular(15.r),
                          bottomLeft: Radius.circular(16.r),
                          bottomRight: Radius.circular(21.r),
                        ),
                        boxShadow: AppTheme.paperShadow(h: 7.0),
                      ),
                      child: Center(
                        child: Text(
                          emoji,
                          style: TextStyle(fontSize: 30.sp),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 12.h),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5.sp,
                      fontWeight: FontWeight.w900,
                      color: isComingSoon ? Colors.grey : AppTheme.ink,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5.sp,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSub,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 剪纸角标贴片（±3° 微斜）
          if (badgeText != null)
            Positioned(
              top: 10.w,
              right: 10.w,
              child: MemphisTag(
                text: badgeText,
                color: AppTheme.tomato,
                textColor: AppTheme.paperWhite,
                tiltDeg: 3.0,
                fontSize: 10.sp,
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.5.h),
                shadowOffset: 2.5,
              ),
            ),
          if (isComingSoon)
            Positioned(
              top: 10.w,
              right: 10.w,
              child: MemphisTag(
                text: '即将上线',
                color: AppTheme.creamDeep,
                tiltDeg: -3.0,
                fontSize: 10.sp,
              ),
            ),
        ],
      ),
    );
  }
}
