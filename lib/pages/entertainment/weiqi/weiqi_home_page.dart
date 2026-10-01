import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../../controllers/app_mode_controller.dart';
import 'weiqi_course_page.dart';
import 'weiqi_data.dart';
import 'weiqi_parent_page.dart';
import 'weiqi_panda.dart';
import 'weiqi_play_page.dart';
import 'weiqi_replay_page.dart';
import 'weiqi_puzzle_page.dart';
import 'weiqi_service.dart';
import 'weiqi_sfx.dart';
import 'weiqi_theme.dart';
import 'weiqi_widgets.dart';

/// 棋妙岛 · 模块首页
/// 纯学习模块：没有金币与商店，只有课程闯关 / 陪下 / 死活题 / 家长小屋。
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

  /// 当前应学的课（第一个已解锁但未拿星的），地图上会发光
  int _currentIndex() {
    for (var i = 0; i < wqLessons.length; i++) {
      if (!_svc.isLessonUnlocked(i)) return (i - 1).clamp(0, wqLessons.length - 1);
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
                  padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 96.h),
                  children: [
                    _header(),
                    SizedBox(height: 12.h),
                    _dailyQuests(),
                    SizedBox(height: 12.h),
                    _playCta(),
                    SizedBox(height: 18.h),
                    if (_svc.loadLastGame() != null) ...[
                      _lastGameEntry(),
                      SizedBox(height: 12.h),
                    ],
                    _sectionTitle('🗺️ 课程地图'),
                    SizedBox(height: 10.h),
                    ..._buildIslandSections(),
                    SizedBox(height: 16.h),
                    _entries(),
                  ],
                )),
          ),
        ],
      ),
    );
  }

  /// 分岛分节：每岛一个彩色标题 + 独立小地图，
  /// 节点在节内蛇形均匀分布，杜绝标题/标签与节点重叠
  List<Widget> _buildIslandSections() {
    final islands = <String>[];
    for (final l in wqLessons) {
      if (!islands.contains(l.island)) islands.add(l.island);
    }
    const islandColors = [Color(0xFF5FAEE3), WqTheme.grape];
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
            ),
            SizedBox(width: 8.w),
            Expanded(
              child: Divider(
                color: (islandColors[i % islandColors.length])
                    .withValues(alpha: 0.3),
                thickness: 1.5,
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
      backgroundColor: WqTheme.ink,
      colorText: Colors.white,
      margin: EdgeInsets.all(16.w),
      borderRadius: 16.r,
    );
  }

  // ================= 顶部问候 =================

  Widget _header() {
    return Row(
      children: [
        const WqPanda(mood: WqPandaMood.happy, size: 46),
        SizedBox(width: 10.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '欢迎来到棋妙岛！',
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w900,
                  color: WqTheme.ink,
                ),
              ),
              Text(
                '今天也要棋开得胜哦！',
                style: TextStyle(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
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
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: WqTheme.sun.withValues(alpha: 0.4)),
        boxShadow: const [
          BoxShadow(color: Color(0x1A23324D), blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department_rounded,
              size: 15, color: WqTheme.sunDeep),
          SizedBox(width: 3.w),
          Text(
            '$days',
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.w900,
              color: WqTheme.sunDeep,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Row(
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.w900,
            color: WqTheme.ink,
          ),
        ),
        SizedBox(width: 8.w),
        Expanded(
          child: Divider(
            color: WqTheme.green.withValues(alpha: 0.25),
            thickness: 1.5,
          ),
        ),
      ],
    );
  }

  /// 上一局复盘入口：终局后随时可以回来逐步回顾
  Widget _lastGameEntry() {
    final last = _svc.loadLastGame();
    if (last == null) return const SizedBox.shrink();
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20.r),
      child: InkWell(
        onTap: () => Get.to(() => WeiqiReplayPage(
              moves: last.moves,
              notes: last.notes,
              marks: last.marks,
            )),
        borderRadius: BorderRadius.circular(20.r),
        child: Container(
          padding: EdgeInsets.all(12.w),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20.r),
            border: Border.all(color: WqTheme.green.withValues(alpha: 0.35)),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x1A23324D), blurRadius: 16, offset: Offset(0, 6)),
            ],
          ),
          child: Row(
            children: [
              const WqPanda(mood: WqPandaMood.think, size: 44),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '上局复盘 · 学一手',
                      style: TextStyle(
                        fontSize: 14.5.sp,
                        fontWeight: FontWeight.w800,
                        color: WqTheme.ink,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      '一步一步回看刚下的棋，棋棋讲解每一手',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w600,
                        color: WqTheme.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: WqTheme.inkFaint),
            ],
          ),
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
                '今日任务',
                style: TextStyle(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w800,
                  color: WqTheme.ink,
                ),
              ),
              WqChip.sun(
                text: '连续 ${_svc.streakDays()} 天',
              ),
            ],
          ),
          SizedBox(height: 6.h),
          _questRow(
            done: lessons > 0,
            icon: Icons.menu_book_rounded,
            name: '上一节课',
            sub: lessons > 0 ? '已完成，真棒！' : '气之森林 · 棋子的呼吸',
            onTap: _openFirstUnlockedLesson,
          ),
          _questRow(
            done: puzzles >= 5,
            icon: Icons.extension_rounded,
            name: '做 5 道吃子题',
            sub: puzzles >= 5 ? '已完成，真棒！' : '已完成 $puzzles / 5 题',
            onTap: () => Get.to(() => const WeiqiPuzzlePage()),
          ),
          _questRow(
            done: games > 0,
            icon: Icons.sports_esports_rounded,
            name: '和棋棋下一盘',
            sub: games > 0 ? '已完成 $games 局！' : '吃子棋 · 先提 3 颗获胜',
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
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        children: [
          Container(
            width: 24.w,
            height: 24.w,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? WqTheme.green : const Color(0xFFEEF1F6),
            ),
            child: done
                ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                : Icon(icon, size: 13, color: WqTheme.inkFaint),
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
                    fontWeight: FontWeight.w800,
                    color: WqTheme.ink,
                  ),
                ),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5.sp,
                    fontWeight: FontWeight.w600,
                    color: WqTheme.inkFaint,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
              decoration: BoxDecoration(
                color: WqTheme.greenSoft,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                done ? '再来一次' : '去完成',
                style: TextStyle(
                  fontSize: 11.5.sp,
                  fontWeight: FontWeight.w800,
                  color: WqTheme.greenDeep,
                ),
              ),
            ),
          ),
        ],
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

  // ================= 陪下 CTA =================

  Widget _playCta() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => showWqOpponentPicker(context),
        borderRadius: BorderRadius.circular(24.r),
        child: Ink(
          padding: EdgeInsets.all(14.w),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24.r),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [WqTheme.greenBright, WqTheme.greenDeep],
            ),
            boxShadow: [
              BoxShadow(
                color: WqTheme.greenDeep.withValues(alpha: 0.35),
                offset: const Offset(0, 10),
                blurRadius: 0,
              ),
            ],
          ),
          child: Row(
            children: [
              const WqPanda(mood: WqPandaMood.happy, size: 48),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '和棋棋下一盘',
                      style: TextStyle(
                        fontSize: 16.5.sp,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '棋棋会陪你慢慢下，还会悄悄犯错哦',
                      style: TextStyle(
                        fontSize: 11.5.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 52.w,
                    height: 52.w,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                  ),
                  Container(
                    width: 38.w,
                    height: 38.w,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(Icons.chevron_right_rounded,
                          color: WqTheme.greenDeep),
                    ),
                  ),
                ],
              ),
            ],
          ),
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
            title: '死活题闯关',
            subtitle: '已答对 ${_svc.solvedPuzzles.length}/${wqPuzzles.length} 题',
            color: WqTheme.skySoft,
            onTap: () => Get.to(() => const WeiqiPuzzlePage()),
          ),
        ),
        SizedBox(width: 12.w),
        Expanded(
          child: _entryCard(
            emoji: '🏡',
            title: '家长小屋',
            subtitle: '学习周报 · 设置',
            color: WqTheme.grapeSoft,
            onTap: () => Get.to(() => const WeiqiParentPage()),
            trailing: Get.find<AppModeController>().isParentMode
                ? null
                : const Icon(Icons.lock_rounded, size: 15, color: WqTheme.inkFaint),
          ),
        ),
      ],
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
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20.r),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20.r),
        child: Container(
          padding: EdgeInsets.all(12.w),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20.r),
            border: Border.all(color: const Color(0x0F23324D)),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x1A23324D), blurRadius: 16, offset: Offset(0, 6)),
            ],
          ),
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
                      borderRadius: BorderRadius.circular(13.r),
                    ),
                    child: Center(child: Text(emoji, style: TextStyle(fontSize: 20.sp))),
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
                  fontWeight: FontWeight.w800,
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
                  fontWeight: FontWeight.w600,
                  color: WqTheme.inkFaint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// 岛屿地图（对应原型首页 .map：虚线路径 + 奖章节点 + 岛屿标签）
// ============================================================

class _IslandMap extends StatefulWidget {
  final Map<String, int> stars;
  final int unlockedCount;
  final int current;
  final void Function(int index) onNodeTap;

  /// 本岛包含的全局课程序号（每节 1~5 个节点）
  final List<int> lessonIndices;

  const _IslandMap({
    required this.stars,
    required this.unlockedCount,
    required this.current,
    required this.onNodeTap,
    required this.lessonIndices,
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
      // 节点在节内蛇形均匀分布：垂直间距 96px，首尾各留 52px，
      // 保证奖章+标签不与相邻节点或分节标题重叠
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
            // 虚线路径
            Positioned.fill(
              child: CustomPaint(
                painter: _MapPathPainter(centers: centers),
              ),
            ),
            // 课程节点
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
                  width: 58.w + 10.w * t,
                  height: 58.w + 10.w * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: WqTheme.sun.withValues(alpha: 0.28 * (1 - t) + 0.06),
                  ),
                  child: child,
                );
              },
              child: _medal(lesson, stars, unlocked, isCurrent),
            )
          else
            _medal(lesson, stars, unlocked, isCurrent),
          SizedBox(height: 4.h),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(999),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x1A23324D), blurRadius: 6, offset: Offset(0, 2)),
              ],
            ),
            child: Text(
              unlocked ? '第${lesson.no}课 ${lesson.title}' : lesson.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5.sp,
                fontWeight: FontWeight.w800,
                color: unlocked ? WqTheme.ink : WqTheme.inkFaint,
              ),
            ),
          ),
          if (stars > 0) WqStarsRow(stars: stars, size: 11),
        ],
      ),
    );
  }

  Widget _medal(WqLesson lesson, int stars, bool unlocked, bool isCurrent) {
    final gradient = stars > 0
        ? const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [WqTheme.greenBright, WqTheme.greenDeep],
          )
        : (isCurrent
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF8FD9B4), Color(0xFF4CB98A)],
              )
            : null);
    return Container(
      width: 52.w,
      height: 52.w,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: unlocked ? gradient : null,
        color: unlocked ? null : const Color(0xFFC7CFDC),
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(color: Color(0x3823324D), blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Center(
        child: unlocked
            ? Text(
                lesson.glyph,
                style: TextStyle(
                  fontSize: 19.sp,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1,
                ),
              )
            : Icon(Icons.lock_rounded, size: 18, color: const Color(0xFFEDF1F7)),
      ),
    );
  }
}

/// 蜿蜒的虚线路径（S 形贝塞尔 + PathMetrics 切虚线）
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
      ..color = WqTheme.green.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    // 虚线
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


/// 岛屿分节标题的彩色胶囊
class _IslandTag extends StatelessWidget {
  final String text;
  final Color color;

  const _IslandTag({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 5.h),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
              color: Color(0x1A23324D), blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.sp,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
    );
  }
}
