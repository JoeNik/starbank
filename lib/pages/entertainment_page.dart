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

/// 孟菲斯（Memphis Milano）风格娱乐模块入口页面
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
                  // 孟菲斯风格顶部欢迎横幅（泡泡糖粉底 + 粗黑边 + 硬投影 + 几何积木贴片）
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppTheme.pink,
                      borderRadius: BorderRadius.circular(22.r),
                      border: Border.all(color: AppTheme.ink, width: 3.0),
                      boxShadow: const [
                        BoxShadow(
                          color: AppTheme.ink,
                          offset: Offset(6, 6),
                          blurRadius: 0,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(19.r),
                      child: Stack(
                        children: [
                          Positioned(
                            top: -12.w,
                            right: -10.w,
                            child: const MemphisShapeBadge(
                              shape: MemphisShapeType.circle,
                              color: AppTheme.yellow,
                              size: 68,
                              tiltDeg: 12,
                              shadowOffset: 3,
                            ),
                          ),
                          Positioned(
                            bottom: 10.h,
                            right: 22.w,
                            child: const MemphisShapeBadge(
                              shape: MemphisShapeType.triangle,
                              color: AppTheme.teal,
                              size: 34,
                              tiltDeg: -14,
                              shadowOffset: 2.5,
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.all(18.w),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                MemphisTag(
                                  text: 'MEMPHIS PLAYGROUND ✦',
                                  color: AppTheme.yellow,
                                  tiltDeg: -3.5,
                                  fontSize: 10.5.sp,
                                  shadowOffset: 2.5,
                                ),
                                SizedBox(height: 10.h),
                                Text(
                                  '🎉 欢迎来到娱乐乐园！',
                                  style: TextStyle(
                                    fontSize: 21.sp,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.ink,
                                  ),
                                ),
                                SizedBox(height: 6.h),
                                Container(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 10.w, vertical: 4.h),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8.r),
                                    border: Border.all(
                                        color: AppTheme.ink, width: 2.0),
                                  ),
                                  child: Text(
                                    '好玩的游戏与益智学习，点一块积木马上出发！',
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
                        cardBg: Colors.white,
                        onTap: () => Get.to(() => const RiddlePage()),
                      ),
                      _buildFeatureCard(
                        emoji: '📚',
                        title: '看图讲故事',
                        subtitle: 'AI引导讲故事',
                        color: AppTheme.teal,
                        cardBg: Colors.white,
                        onTap: () => Get.to(() => const StoryGamePage()),
                      ),
                      _buildFeatureCard(
                        emoji: '🎵',
                        title: '儿歌播放器',
                        subtitle: '海量儿歌随心听',
                        color: AppTheme.pink,
                        cardBg: Colors.white,
                        onTap: () => Get.to(() => const MusicHomePage()),
                      ),
                      _buildFeatureCard(
                        emoji: '🧧',
                        title: '新年知多少',
                        subtitle: '小年兽问答',
                        color: AppTheme.tomato,
                        cardBg: Colors.white,
                        onTap: () => Get.to(() => const QuizPage()),
                      ),
                      _buildFeatureCard(
                        emoji: '📖',
                        title: '新年故事',
                        subtitle: '语音绘本模式',
                        color: AppTheme.lilac,
                        cardBg: Colors.white,
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
                        cardBg: Colors.white,
                        onTap: () => Get.to(() => const EncyclopediaPage()),
                      ),
                      _buildFeatureCard(
                        emoji: '🔤',
                        title: '星海识字',
                        subtitle: 'AI趣味识字',
                        color: AppTheme.lilac,
                        cardBg: Colors.white,
                        onTap: () => Get.to(() => const HanziLearningPage()),
                      ),
                      _buildFeatureCard(
                        emoji: '🗣️',
                        title: '拼音小耳朵',
                        subtitle: '听准声母韵母',
                        color: AppTheme.pink,
                        cardBg: Colors.white,
                        onTap: () => Get.to(() => const PinyinLearningPage()),
                      ),
                      _buildFeatureCard(
                        emoji: '🔢',
                        title: '数学乐园',
                        subtitle: '计算器和练习题',
                        color: AppTheme.yellow,
                        cardBg: Colors.white,
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

  /// 构建孟菲斯分类标题行（撞色贴纸 + 波浪线）
  Widget _buildCategoryHeader(String title, Color tagColor) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
          decoration: BoxDecoration(
            color: tagColor,
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: AppTheme.ink, width: 2.5),
            boxShadow: const [
              BoxShadow(
                color: AppTheme.ink,
                offset: Offset(3, 3),
                blurRadius: 0,
              ),
            ],
          ),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w900,
              color: AppTheme.ink,
            ),
          ),
        ),
        SizedBox(width: 12.w),
        const Expanded(
          child: MemphisSquiggle(
            height: 10,
            color: AppTheme.ink,
            strokeWidth: 2.5,
            waves: 6,
          ),
        ),
      ],
    );
  }

  /// 构建孟菲斯风格功能积木卡片
  Widget _buildFeatureCard({
    required String emoji,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    Color cardBg = Colors.white,
    String? badgeText,
    bool isComingSoon = false,
  }) {
    return MemphisCard(
      color: cardBg,
      borderRadius: 20.r,
      borderWidth: 2.5,
      shadowOffset: 5.0,
      onTap: isComingSoon ? null : onTap,
      child: Stack(
        children: [
          Center(
            child: Padding(
              padding: EdgeInsets.all(14.w),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Emoji 图标积木底座（一块一色 + 粗黑描边 + 硬投影）
                  Container(
                    width: 62.w,
                    height: 62.w,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(18.r),
                      border: Border.all(color: AppTheme.ink, width: 2.3),
                      boxShadow: const [
                        BoxShadow(
                          color: AppTheme.ink,
                          offset: Offset(3.5, 3.5),
                          blurRadius: 0,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        emoji,
                        style: TextStyle(fontSize: 30.sp),
                      ),
                    ),
                  ),
                  SizedBox(height: 12.h),
                  // 标题（水平正排，黑体）
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
                  // 副标题
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
          // 歪斜贴纸角标（遵循规则 04：只歪玩具贴纸，不歪正文信息）
          if (badgeText != null)
            Positioned(
              top: 10.w,
              right: 10.w,
              child: MemphisTag(
                text: badgeText,
                color: AppTheme.tomato,
                textColor: Colors.white,
                tiltDeg: 8.0,
                fontSize: 10.sp,
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.5.h),
                shadowOffset: 2.0,
              ),
            ),
          if (isComingSoon)
            Positioned(
              top: 10.w,
              right: 10.w,
              child: MemphisTag(
                text: '即将上线',
                color: AppTheme.creamDeep,
                tiltDeg: -6.0,
                fontSize: 10.sp,
              ),
            ),
        ],
      ),
    );
  }
}
