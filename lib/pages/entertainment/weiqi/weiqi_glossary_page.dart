import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import 'weiqi_course_page.dart';
import 'weiqi_data.dart';
import 'weiqi_theme.dart';
import 'weiqi_widgets.dart';

/// 围棋小词典：所有学过的术语 + 故事化解释 + 出处课程。
/// 初学者任何时候忘了概念，都能来这里查。
class WeiqiGlossaryPage extends StatelessWidget {
  const WeiqiGlossaryPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 术语 → （故事解释，出处课程序号）
    final entries = _buildEntries();
    return Scaffold(
      backgroundColor: WqTheme.cream,
      appBar: AppBar(
        title: const Text('围棋小词典'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: WqTheme.ink,
      ),
      body: ListView.builder(
        padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 24.h),
        itemCount: entries.length,
        itemBuilder: (context, i) {
          final e = entries[i];
          return Padding(
            padding: EdgeInsets.only(bottom: 10.h),
            child: WqCard(
              padding: EdgeInsets.all(12.w),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40.w,
                  height: 40.w,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: WqTheme.greenSoft,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    e.glyph,
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w900,
                      color: WqTheme.greenDeep,
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
                            e.term,
                            style: TextStyle(
                              fontSize: 15.sp,
                              fontWeight: FontWeight.w800,
                              color: WqTheme.ink,
                            ),
                          ),
                          const Spacer(),
                          if (e.lessonNo != null)
                            GestureDetector(
                              onTap: e.lessonNo == null
                                  ? null
                                  : () => Get.to(() => WeiqiCoursePageShim(
                                      lessonNo: e.lessonNo!)),
                              child: WqChip.sun(text: '第${e.lessonNo}课'),
                            ),
                        ],
                      ),
                      SizedBox(height: 3.h),
                      Text(
                        e.story,
                        style: TextStyle(
                          fontSize: 12.5.sp,
                          fontWeight: FontWeight.w600,
                          height: 1.6,
                          color: WqTheme.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            ),
          );
        },
      ),
    );
  }

  List<_GlossaryEntry> _buildEntries() => const [
        _GlossaryEntry('气', '气', '棋子士兵的呼吸。棋子紧挨着的空点就是它的气，气全被堵住士兵就无法呼吸。', 1),
        _GlossaryEntry('打吃', '打', '只差一步就提掉对方——就像有人捂住了士兵的鼻子，好危险！被打吃的一方要赶紧想办法。', 1),
        _GlossaryEntry('提子', '提', '把对方最后的气堵住，棋子就被「提」走啦——飞进提子口袋。', 1),
        _GlossaryEntry('逃子', '逃', '被围住的士兵往外跑一步，让自己多几口气，就叫逃子。', 2),
        _GlossaryEntry('长气', '长', '逃跑的秘诀：连接自己人或往空旷处走，让气变多。', 2),
        _GlossaryEntry('边线', '边', '棋盘最外圈的围墙。边线上的士兵只有 3 口气，角上只有 2 口——金角银边草肚皮！', 3),
        _GlossaryEntry('角', '角', '棋盘的四角，气最少也最容易守住，所以下棋要先占角。', 3),
        _GlossaryEntry('虎口', '虎', '三颗棋子围出的像大老虎张开的嘴——跳进去的棋子只剩一口气，会被一口吞掉！', 4),
        _GlossaryEntry('双打', '双', '一手同时打吃两块对方棋子！对方只能救一边，另一边一定被提。', 5),
        _GlossaryEntry('禁入点', '禁', '进去就完全没有气的陷阱点，不能下。但如果能提子，它就不是禁入点！', 6),
        _GlossaryEntry('打劫', '劫', '像交换玩具的规则：刚被提走一颗子，对方不能马上提回来，要先去别处下一手。', 7),
        _GlossaryEntry('打二还一', '二', '提了对方两颗，自己一颗马上被提回来——你提我两颗，我还你一颗。', 8),
        _GlossaryEntry('断点', '断', '两颗棋子中间还没连上的缺口——被对方插进来就会被切成两半。', 9),
        _GlossaryEntry('切断', '切', '插进对方的断点，把它的棋分成两块，各自作战力气就小了。', 9),
        _GlossaryEntry('互相打吃', '互', '双方都只剩一口气——先下手的一方赢！', 10),
        _GlossaryEntry('打吃方向', '赶', '把对方往边线赶，墙边没有退路，最容易吃到子。', 11),
        _GlossaryEntry('连接', '连', '让自己的棋子手拉手连成一体，气变多、切不断。', 12),
        _GlossaryEntry('吃子棋', '吃', '本模块的对局玩法：谁先提走对方 3 颗棋子谁就赢。', null),
      ];
}

class _GlossaryEntry {
  final String term;
  final String glyph;
  final String story;
  final int? lessonNo;

  const _GlossaryEntry(this.term, this.glyph, this.story, this.lessonNo);
}

/// 由课程编号跳转（词典 → 对应课程）
class WeiqiCoursePageShim extends StatelessWidget {
  final int lessonNo;

  const WeiqiCoursePageShim({super.key, required this.lessonNo});

  @override
  Widget build(BuildContext context) {
    final idx = wqLessons.indexWhere((l) => l.no == lessonNo);
    if (idx < 0) return const SizedBox.shrink();
    return _CourseProxy(lessonIndex: idx);
  }
}

class _CourseProxy extends StatelessWidget {
  final int lessonIndex;

  const _CourseProxy({required this.lessonIndex});

  @override
  Widget build(BuildContext context) {
    return WeiqiCoursePage(lessonIndex: lessonIndex);
  }
}
