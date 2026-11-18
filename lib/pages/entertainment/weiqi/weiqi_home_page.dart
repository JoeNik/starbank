import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../../controllers/app_mode_controller.dart';
import 'weiqi_course_page.dart';
import 'weiqi_data.dart';
import 'weiqi_glossary_page.dart';
import 'weiqi_panda.dart';
import 'weiqi_parent_page.dart';
import 'weiqi_play_page.dart';
import 'weiqi_puzzle_page.dart';
import 'weiqi_replay_page.dart';
import 'weiqi_service.dart';
import 'weiqi_sfx.dart';
import 'weiqi_theme.dart';
import 'weiqi_widgets.dart';

/// 棋妙岛 · 模块首页（孟菲斯视觉 + 商业级段级位成长与双模式入口）
class WeiqiHomePage extends StatefulWidget {
  const WeiqiHomePage({super.key});

  @override
  State<WeiqiHomePage> createState() => _WeiqiHomePageState();
}

class _WeiqiHomePageState extends State<WeiqiHomePage> {
  late final WeiqiService _svc;

  @override
  void initState() {
    super.initState();
    _svc = Get.find<WeiqiService>();
  }

  /// 当前应学的课（第一个已解锁但未拿星的），地图上会脉冲发光
  int _currentIndex() {
    for (var i = 0; i < wqLessons.length; i++) {
      if (!_svc.isLessonUnlocked(i)) {
        return (i - 1).clamp(0, wqLessons.length - 1);
      }
      if ((_svc.lessonStars[wqLessons[i].id] ?? 0) == 0) return i;
    }
    return wqLessons.length - 1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WqTheme.cream,
      body: Stack(
        children: [
          const Positioned.fill(child: WqHills()),
          SafeArea(
            child: Obx(() => ListView(
                  padding: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 96.h),
                  children: [
                    _header(),
                    SizedBox(height: 10.h),
                    _rankBanner(),
                    SizedBox(height: 12.h),
                    _dailyQuests(),
                    SizedBox(height: 12.h),
                    _playCta(),
                    SizedBox(height: 14.h),
                    if (_svc.loadLastGame() != null) ...[
                      _lastGameEntry(),
                      SizedBox(height: 14.h),
                    ],
                    _sectionTitle('🗺️ 课程闯关地图（共 ${wqLessons.length} 课）'),
                    SizedBox(height: 10.h),
                    ..._buildIslandSections(),
                    SizedBox(height: 14.h),
                    _entries(),
                    SizedBox(height: 12.h),
                    _glossaryEntry(),
                  ],
                )),
          ),
        ],
      ),
    );
  }

  /// 构建少儿围棋段级位成长看板（孟菲斯柠檬黄/薄荷青撞色卡）
  Widget _rankBanner() {
    final rank = _svc.rankInfo;
    return Container(
      padding: EdgeInsets.all(13.w),
      decoration: BoxDecoration(
        color: WqTheme.sunSoft,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: WqTheme.ink, width: 2.5),
        boxShadow: const [
          BoxShadow(color: WqTheme.ink, offset: Offset(4.5, 4.5), blurRadius: 0),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // 歪斜级位大徽章
              Transform.rotate(
                angle: -0.06,
                child: Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                  decoration: BoxDecoration(
                    color: WqTheme.sun,
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: WqTheme.ink, width: 2.2),
                    boxShadow: const [
                      BoxShadow(color: WqTheme.ink, offset: Offset(2.5, 2.5)),
                    ],
                  ),
                  child: Text(
                    rank.rank,
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w900,
                      color: WqTheme.ink,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          rank.title,
                          style: TextStyle(
                            fontSize: 14.5.sp,
                            fontWeight: FontWeight.w900,
                            color: WqTheme.ink,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'EXP ${rank.currentExp} / ${rank.nextExp}',
                          style: TextStyle(
                            fontSize: 10.5.sp,
                            fontWeight: FontWeight.w900,
                            color: WqTheme.inkSoft,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 5.h),
                    // 孟菲斯黑边进度条
                    Container(
                      height: 9.h,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: WqTheme.ink, width: 1.6),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: FractionallySizedBox(
                          widthFactor: rank.progress,
                          alignment: Alignment.centerLeft,
                          child: Container(color: WqTheme.green),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          // 三项核心成长指标
          Row(
            children: [
              _miniStatPill(
                '⭐ 课程星章',
                '${_svc.totalLessonStars}/${wqLessons.length * 3}',
                Colors.white,
              ),
              SizedBox(width: 8.w),
              _miniStatPill(
                '🧩 题库通关',
                '${_svc.solvedPuzzles.length}/${wqPuzzles.length}',
                Colors.white,
              ),
              SizedBox(width: 8.w),
              _miniStatPill(
                '🏆 对局胜场',
                '${_svc.playWins.value} 胜',
                Colors.white,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStatPill(String label, String val, Color bg) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 5.h, horizontal: 6.w),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: WqTheme.ink, width: 1.8),
        ),
        child: Column(
          children: [
            Text(
              val,
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w900,
                color: WqTheme.ink,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5.sp,
                fontWeight: FontWeight.w700,
                color: WqTheme.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 分岛分节：4 座岛屿各自一个孟菲斯糖果色贴纸标题 + 独立小地图
  List<Widget> _buildIslandSections() {
    final islands = <String>[];
    for (final l in wqLessons) {
      if (!islands.contains(l.island)) islands.add(l.island);
    }
    const islandColors = [
      WqTheme.green,
      WqTheme.sun,
      WqTheme.pink,
      WqTheme.grape,
    ];
    final widgets = <Widget>[];
    for (var i = 0; i < islands.length; i++) {
      final indices = <int>[];
      for (var k = 0; k < wqLessons.length; k++) {
        if (wqLessons[k].island == islands[i]) indices.add(k);
      }
      widgets.add(
        Row(
          children: [
            _IslandTag(
              text: islands[i],
              color: islandColors[i % islandColors.length],
              tiltDeg: i.isEven ? -2.0 : 2.0,
            ),
            SizedBox(width: 10.w),
            const Expanded(
              child: Divider(
                color: WqTheme.ink,
                thickness: 2.0,
              ),
            ),
          ],
        ),
      );
      widgets.add(SizedBox(height: 6.h));
      widgets.add(
        _IslandMap(
          stars: _svc.lessonStars,
          unlockedCount: _unlockedCount(),
          current: _currentIndex(),
          onNodeTap: _onNodeTap,
          lessonIndices: indices,
          accentColor: islandColors[i % islandColors.length],
        ),
      );
      widgets.add(SizedBox(height: 12.h));
    }
    return widgets;
  }

  int _unlockedCount() {
    var n = 0;
    for (var i = 0; i < wqLessons.length; i++) {
      if (_svc.isLessonUnlocked(i)) n++;
    }
    return n;
  }

  void _onNodeTap(int index) {
    final unlocked = _svc.isLessonUnlocked(index);
    if (unlocked) {
      Get.to(() => WeiqiCoursePage(lessonIndex: index));
      return;
    }
    WqSfx.oops();
    Get.snackbar(
      '先完成前面的课程再来吧！',
      '和棋棋一起学完上一课，就能解锁这里啦～',
      snackPosition: SnackPosition.TOP,
      backgroundColor: WqTheme.sun,
      colorText: WqTheme.ink,
      margin: EdgeInsets.all(16.w),
      borderRadius: 16.r,
    );
  }

  // ================= 顶部问候与返回 =================

  Widget _header() {
    return Row(
      children: [
        WqIconButton(
          icon: Icons.arrow_back_ios_new_rounded,
          size: 38,
          onTap: () => Get.back(),
        ),
        SizedBox(width: 8.w),
        const WqPanda(mood: WqPandaMood.happy, size: 44),
        SizedBox(width: 8.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '欢迎来到棋妙岛！',
                style: TextStyle(
                  fontSize: 17.5.sp,
                  fontWeight: FontWeight.w900,
                  color: WqTheme.ink,
                ),
              ),
              Text(
                '今天也要棋开得胜哦！',
                style: TextStyle(
                  fontSize: 11.5.sp,
                  fontWeight: FontWeight.w700,
                  color: WqTheme.inkSoft,
                ),
              ),
            ],
          ),
        ),
        Obx(() => _streakChip()),
      ],
    );
  }

  Widget _streakChip() {
    final days = _svc.streakDays();
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
      decoration: BoxDecoration(
        color: WqTheme.sun,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: WqTheme.ink, width: 2.0),
        boxShadow: const [
          BoxShadow(color: WqTheme.ink, blurRadius: 0, offset: Offset(2.5, 2.5)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department_rounded,
              size: 16, color: WqTheme.coral),
          SizedBox(width: 3.w),
          Text(
            '$days天',
            style: TextStyle(
              fontSize: 12.sp,
              fontWeight: FontWeight.w900,
              color: WqTheme.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
          decoration: BoxDecoration(
            color: WqTheme.sun,
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(color: WqTheme.ink, width: 2.0),
            boxShadow: const [
              BoxShadow(color: WqTheme.ink, offset: Offset(2.5, 2.5)),
            ],
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14.5.sp,
              fontWeight: FontWeight.w900,
              color: WqTheme.ink,
            ),
          ),
        ),
        SizedBox(width: 8.w),
        const Expanded(
          child: Divider(
            color: WqTheme.ink,
            thickness: 2.0,
          ),
        ),
      ],
    );
  }

  /// 上一局复盘与历史棋谱库入口
  Widget _lastGameEntry() {
    final last = _svc.loadLastGame();
    if (last == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => Get.to(() => WeiqiReplayPage(
            moves: last.moves,
            notes: last.notes,
            marks: last.marks,
            grades: last.grades,
            better: last.better,
            n: last.n,
          )),
      child: WqCard(
        padding: EdgeInsets.all(12.w),
        color: Colors.white,
        child: Row(
          children: [
            const WqPanda(mood: WqPandaMood.think, size: 44),
            SizedBox(width: 10.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '棋谱复盘 · 试下研究',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5.sp,
                            fontWeight: FontWeight.w900,
                            color: WqTheme.ink,
                          ),
                        ),
                      ),
                      SizedBox(width: 6.w),
                      WqChip.pink(text: '存 ${_svc.gameHistory.length} 局'),
                    ],
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    '逐手回看对局 · 支持自由摆子试下变化图',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w700,
                      color: WqTheme.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: WqTheme.ink),
          ],
        ),
      ),
    );
  }

  // ================= 今日任务 =================

  Widget _dailyQuests() {
    final now = DateTime.now();
    final key =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final act = _svc.dailyActivity[key] ?? const {};
    final lessons = act['lesson'] ?? 0;
    final puzzles = act['puzzles'] ?? 0;
    final games = act['games'] ?? 0;
    return WqCard(
      padding: EdgeInsets.all(12.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '📋 今日修行任务',
                style: TextStyle(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w900,
                  color: WqTheme.ink,
                ),
              ),
              WqChip.sun(
                text: '连续 ${_svc.streakDays()} 天',
                tiltDeg: -2.5,
              ),
            ],
          ),
          SizedBox(height: 6.h),
          _questRow(
            done: lessons > 0,
            icon: Icons.menu_book_rounded,
            name: '上一节围棋课',
            sub: lessons > 0 ? '已完成，真棒！' : '4 座主题小岛 · 16 节互动课',
            onTap: _openFirstUnlockedLesson,
          ),
          _questRow(
            done: puzzles >= 5,
            icon: Icons.extension_rounded,
            name: '做 5 道死活/手筋题',
            sub: puzzles >= 5 ? '已完成，真棒！' : '已完成 $puzzles / 5 题',
            onTap: () => Get.to(() => const WeiqiPuzzlePage()),
          ),
          _questRow(
            done: games > 0,
            icon: Icons.sports_esports_rounded,
            name: '和棋棋对弈一局',
            sub: games > 0
                ? '今日已下 $games 局！'
                : '${_svc.ruleMode.value == "territory" ? "标准围地" : "吃子棋"} · ${_svc.boardSize.value} 路棋盘',
            onTap: () => showWqOpponentPicker(context),
          ),
        ],
      ),
    );
  }

  Widget _questRow({
    required bool done,
    required IconData icon,
    required String name,
    required String sub,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 4.5.h),
        child: Row(
          children: [
            Container(
              width: 26.w,
              height: 26.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? WqTheme.green : WqTheme.cream,
                border: Border.all(color: WqTheme.ink, width: 1.8),
              ),
              child: done
                  ? const Icon(Icons.check_rounded, size: 15, color: WqTheme.ink)
                  : Icon(icon, size: 13, color: WqTheme.ink),
            ),
            SizedBox(width: 9.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w900,
                      color: WqTheme.ink,
                    ),
                  ),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5.sp,
                      fontWeight: FontWeight.w700,
                      color: WqTheme.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 11.w, vertical: 5.h),
              decoration: BoxDecoration(
                color: done ? WqTheme.greenSoft : WqTheme.sun,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: WqTheme.ink, width: 1.8),
                boxShadow: const [
                  BoxShadow(color: WqTheme.ink, offset: Offset(2, 2)),
                ],
              ),
              child: Text(
                done ? '再来一次' : '去完成',
                style: TextStyle(
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w900,
                  color: WqTheme.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openFirstUnlockedLesson() {
    for (var i = 0; i < wqLessons.length; i++) {
      if (!_svc.isLessonUnlocked(i)) break;
      if ((_svc.lessonStars[wqLessons[i].id] ?? 0) == 0) {
        Get.to(() => WeiqiCoursePage(lessonIndex: i));
        return;
      }
    }
    var last = 0;
    for (var i = 0; i < wqLessons.length; i++) {
      if (_svc.isLessonUnlocked(i)) last = i;
    }
    Get.to(() => WeiqiCoursePage(lessonIndex: last));
  }

  // ================= 陪下 CTA（孟菲斯撞色积木大卡，无渐变） =================

  Widget _playCta() {
    return GestureDetector(
      onTap: () => showWqOpponentPicker(context),
      child: Container(
        padding: EdgeInsets.all(14.w),
        decoration: BoxDecoration(
          color: WqTheme.green,
          borderRadius: BorderRadius.circular(22.r),
          border: Border.all(color: WqTheme.ink, width: 3.0),
          boxShadow: const [
            BoxShadow(
              color: WqTheme.ink,
              offset: Offset(6, 6),
              blurRadius: 0,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: WqTheme.ink, width: 2.0),
              ),
              child: const WqPanda(mood: WqPandaMood.happy, size: 46),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '和棋棋下一盘',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16.5.sp,
                            fontWeight: FontWeight.w900,
                            color: WqTheme.ink,
                          ),
                        ),
                      ),
                      SizedBox(width: 6.w),
                      WqChip.sun(
                        text: _svc.ruleMode.value == 'territory'
                            ? '标准围地'
                            : '吃子棋',
                        tiltDeg: 4.0,
                      ),
                    ],
                  ),
                  SizedBox(height: 3.h),
                  Text(
                    '支持 9/13/19 路 · 让子 · 形势判断与点目结算',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w800,
                      color: WqTheme.ink,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 38.w,
              height: 38.w,
              decoration: BoxDecoration(
                color: WqTheme.sun,
                shape: BoxShape.circle,
                border: Border.all(color: WqTheme.ink, width: 2.2),
                boxShadow: const [
                  BoxShadow(color: WqTheme.ink, offset: Offset(2.5, 2.5)),
                ],
              ),
              child: const Center(
                child: Icon(Icons.play_arrow_rounded, color: WqTheme.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================= 更多入口 =================

  Widget _entries() {
    return Row(
      children: [
        Expanded(
          child: _entryCard(
            emoji: '🧩',
            title: '死活与手筋特训',
            subtitle: '已通关 ${_svc.solvedPuzzles.length}/${wqPuzzles.length} 题',
            color: WqTheme.pink,
            onTap: () => Get.to(() => const WeiqiPuzzlePage()),
          ),
        ),
        SizedBox(width: 12.w),
        Expanded(
          child: _entryCard(
            emoji: '🏡',
            title: '家长小屋',
            subtitle: '学习周报 · 规则设置',
            color: WqTheme.grape,
            onTap: () => Get.to(() => const WeiqiParentPage()),
            trailing: Get.find<AppModeController>().isParentMode
                ? null
                : const Icon(Icons.lock_rounded, size: 16, color: WqTheme.ink),
          ),
        ),
      ],
    );
  }

  /// 围棋小词典全宽入口
  Widget _glossaryEntry() {
    return GestureDetector(
      onTap: () => Get.to(() => const WeiqiGlossaryPage()),
      child: WqCard(
        padding: EdgeInsets.all(12.w),
        child: Row(
          children: [
            Container(
              width: 40.w,
              height: 40.w,
              decoration: BoxDecoration(
                color: WqTheme.sun,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: WqTheme.ink, width: 2.0),
                boxShadow: const [
                  BoxShadow(color: WqTheme.ink, offset: Offset(2.5, 2.5)),
                ],
              ),
              child: const Center(
                child: Text('📖', style: TextStyle(fontSize: 20)),
              ),
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '围棋百科小词典',
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w900,
                      color: WqTheme.ink,
                    ),
                  ),
                  Text(
                    '气 · 打劫 · 征子 · 倒扑 · 真眼 · 金角银边随时查',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5.sp,
                      fontWeight: FontWeight.w700,
                      color: WqTheme.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: WqTheme.ink),
          ],
        ),
      ),
    );
  }

  Widget _entryCard({
    required String emoji,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: WqCard(
        padding: EdgeInsets.all(12.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40.w,
                  height: 40.w,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: WqTheme.ink, width: 2.0),
                    boxShadow: const [
                      BoxShadow(color: WqTheme.ink, offset: Offset(2.5, 2.5)),
                    ],
                  ),
                  child: Center(
                    child: Text(emoji, style: TextStyle(fontSize: 20.sp)),
                  ),
                ),
                const Spacer(),
                if (trailing != null) trailing,
              ],
            ),
            SizedBox(height: 8.h),
            Text(
              title,
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w900,
                color: WqTheme.ink,
              ),
            ),
            SizedBox(height: 2.h),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5.sp,
                fontWeight: FontWeight.w700,
                color: WqTheme.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 孟菲斯风格岛屿地图（粗黑描边路径 + 糖果色硬投影奖章节点）
// ============================================================

class _IslandMap extends StatefulWidget {
  final Map<String, int> stars;
  final int unlockedCount;
  final int current;
  final void Function(int index) onNodeTap;
  final List<int> lessonIndices;
  final Color accentColor;

  const _IslandMap({
    required this.stars,
    required this.unlockedCount,
    required this.current,
    required this.onNodeTap,
    required this.lessonIndices,
    required this.accentColor,
  });

  @override
  State<_IslandMap> createState() => _IslandMapState();
}

class _IslandMapState extends State<_IslandMap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final n = widget.lessonIndices.length;
      const gap = 96.0;
      final h = 52.0 * 2 + gap * (n - 1);
      final centers = <Offset>[];
      for (var k = 0; k < n; k++) {
        final x = (k.isEven ? 0.26 : 0.66) * w;
        final y = 52.0 + gap * k;
        centers.add(Offset(x, y));
      }
      return SizedBox(
        height: h,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _MapPathPainter(centers: centers),
              ),
            ),
            for (var k = 0; k < widget.lessonIndices.length; k++)
              Positioned(
                left: centers[k].dx,
                top: centers[k].dy,
                child: FractionalTranslation(
                  translation: const Offset(-0.5, -0.5),
                  child: _node(widget.lessonIndices[k]),
                ),
              ),
          ],
        ),
      );
    });
  }

  Widget _node(int i) {
    final lesson = wqLessons[i];
    final stars = widget.stars[lesson.id] ?? 0;
    final unlocked = i < widget.unlockedCount;
    final isCurrent = i == widget.current && stars == 0;
    return GestureDetector(
      onTap: () => widget.onNodeTap(i),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isCurrent)
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) {
                final t = (math.sin(_pulse.value * 2 * math.pi) + 1) / 2;
                return Container(
                  width: 58.w + 8.w * t,
                  height: 58.w + 8.w * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: WqTheme.sun.withValues(alpha: 0.35),
                    border: Border.all(color: WqTheme.ink, width: 1.5),
                  ),
                  child: child,
                );
              },
              child: _medal(lesson, stars, unlocked, isCurrent),
            )
          else
            _medal(lesson, stars, unlocked, isCurrent),
          SizedBox(height: 5.h),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: WqTheme.ink, width: 1.8),
              boxShadow: const [
                BoxShadow(
                  color: WqTheme.ink,
                  blurRadius: 0,
                  offset: Offset(2, 2),
                ),
              ],
            ),
            child: Text(
              unlocked ? '第${lesson.no}课 ${lesson.title}' : lesson.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5.sp,
                fontWeight: FontWeight.w900,
                color: unlocked ? WqTheme.ink : WqTheme.inkFaint,
              ),
            ),
          ),
          if (stars > 0) ...[
            SizedBox(height: 2.h),
            WqStarsRow(stars: stars, size: 12),
          ],
        ],
      ),
    );
  }

  Widget _medal(WqLesson lesson, int stars, bool unlocked, bool isCurrent) {
    final bgColor = !unlocked
        ? const Color(0xFFDAD5CA)
        : (isCurrent ? WqTheme.sun : widget.accentColor);
    return Container(
      width: 52.w,
      height: 52.w,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bgColor,
        border: Border.all(color: WqTheme.ink, width: 2.5),
        boxShadow: const [
          BoxShadow(color: WqTheme.ink, blurRadius: 0, offset: Offset(3.5, 3.5)),
        ],
      ),
      child: Center(
        child: unlocked
            ? Text(
                lesson.glyph,
                style: TextStyle(
                  fontSize: 19.sp,
                  fontWeight: FontWeight.w900,
                  color: WqTheme.ink,
                  height: 1,
                ),
              )
            : const Icon(Icons.lock_rounded, size: 18, color: WqTheme.inkSoft),
      ),
    );
  }
}

class _MapPathPainter extends CustomPainter {
  final List<Offset> centers;

  _MapPathPainter({required this.centers});

  @override
  void paint(Canvas canvas, Size size) {
    if (centers.length < 2) return;
    final path = Path()..moveTo(centers[0].dx, centers[0].dy);
    for (var i = 1; i < centers.length; i++) {
      final a = centers[i - 1];
      final b = centers[i];
      path.cubicTo(
        a.dx + (b.dx - a.dx) * 0.55,
        a.dy,
        b.dx - (b.dx - a.dx) * 0.55,
        b.dy,
        b.dx,
        b.dy,
      );
    }
    final paint = Paint()
      ..color = WqTheme.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    const dashLen = 7.0;
    const gapLen = 8.0;
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        final end = math.min(dist + dashLen, metric.length);
        canvas.drawPath(metric.extractPath(dist, end), paint);
        dist = end + gapLen;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MapPathPainter old) => old.centers != centers;
}

class _IslandTag extends StatelessWidget {
  final String text;
  final Color color;
  final double tiltDeg;

  const _IslandTag({
    required this.text,
    required this.color,
    this.tiltDeg = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: tiltDeg * math.pi / 180.0,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 5.h),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: WqTheme.ink, width: 2.2),
          boxShadow: const [
            BoxShadow(color: WqTheme.ink, blurRadius: 0, offset: Offset(3, 3)),
          ],
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11.5.sp,
            fontWeight: FontWeight.w900,
            color: WqTheme.ink,
          ),
        ),
      ),
    );
  }
}
