import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import 'weiqi_course_page.dart';
import 'weiqi_data.dart';
import 'weiqi_theme.dart';
import 'weiqi_widgets.dart';

/// 围棋百科小词典：包含全部 16 课核心术语 + 故事化解释 + 出处课程直达。
class WeiqiGlossaryPage extends StatelessWidget {
  const WeiqiGlossaryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final entries = _buildEntries();
    const badgeColors = [
      WqTheme.sun,
      WqTheme.green,
      WqTheme.pink,
      WqTheme.grape,
    ];
    return Scaffold(
      backgroundColor: WqTheme.cream,
      appBar: AppBar(
        title: const Text('围棋百科小词典'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: WqTheme.ink,
      ),
      body: ListView.builder(
        padding: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 24.h),
        itemCount: entries.length,
        itemBuilder: (context, i) {
          final e = entries[i];
          final bg = badgeColors[i % badgeColors.length];
          return Padding(
            padding: EdgeInsets.only(bottom: 10.h),
            child: WqCard(
              padding: EdgeInsets.all(12.w),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42.w,
                    height: 42.w,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: bg,
                      shape: BoxShape.circle,
                      border: WqTheme.border(),
                      boxShadow: WqTheme.paperShadow(h: 8.0),
                    ),
                    child: Text(
                      e.glyph,
                      style: TextStyle(
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w900,
                        color: WqTheme.ink,
                      ),
                    ),
                  ),
                  SizedBox(width: 12.w),
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
                                fontWeight: FontWeight.w900,
                                color: WqTheme.ink,
                              ),
                            ),
                            const Spacer(),
                            if (e.lessonNo != null)
                              GestureDetector(
                                onTap: () => Get.to(() =>
                                    WeiqiCoursePageShim(lessonNo: e.lessonNo!)),
                                child: WqChip.sun(
                                  text: '第${e.lessonNo}课 ›',
                                  tiltDeg: -2.5,
                                ),
                              ),
                          ],
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          e.story,
                          style: TextStyle(
                            fontSize: 12.5.sp,
                            fontWeight: FontWeight.w700,
                            height: 1.55,
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
        _GlossaryEntry('征子', '征', '俗称「扭羊头」：从两边交替连续打吃，逼着敌人沿着斜线一路逃到墙边被全部吃掉。', 13),
        _GlossaryEntry('倒扑', '扑', '故意送一颗子跳进对方虎口，哪怕对方提掉这一颗，也会只剩一口气被我方反提整块！', 14),
        _GlossaryEntry('枷吃', '枷', '不贴着对方硬追，而是在斜前方像竹篮一样罩住它，让它往哪边冲都冲不出去。', 14),
        _GlossaryEntry('真眼', '眼', '自己棋子牢牢围住的独立空房间，对方无法落子进来。', 15),
        _GlossaryEntry('两眼活棋', '活', '一块棋只要拥有两个独立的真眼，对方永远无法把气堵光，就成了不死之身的「活棋」！', 15),
        _GlossaryEntry('点眼', '点', '抢先下在对方分出两只眼的关键位置，让对方只能做出一只眼，从而吃掉整块棋。', 15),
        _GlossaryEntry('金角银边', '围', '角部两面有墙最好围地（金角），边上一面有墙次之（银边），中腹四面漏风最难围（草肚皮）。', 16),
        _GlossaryEntry('收官与虚手', '官', '终局阶段把双方领地边界补好叫「收官」；无处可争时停一手叫「虚手(Pass)」，双方连续虚手即可点目判胜负。', 16),
      ];
}

class _GlossaryEntry {
  final String term;
  final String glyph;
  final String story;
  final int? lessonNo;

  const _GlossaryEntry(this.term, this.glyph, this.story, this.lessonNo);
}

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
