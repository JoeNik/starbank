import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../../controllers/app_mode_controller.dart';
import 'weiqi_panda.dart';
import 'weiqi_service.dart';
import 'weiqi_theme.dart';
import 'weiqi_widgets.dart';

/// 家长小屋：学习周报 + 模块设置。
/// 措辞原则：讲过程与坚持，不讲名次与胜负。
/// 受宿主家长模式保护。
class WeiqiParentPage extends StatelessWidget {
  const WeiqiParentPage({super.key});

  @override
  Widget build(BuildContext context) {
    final mode = Get.find<AppModeController>();
    if (!mode.isParentMode) {
      return Scaffold(
        backgroundColor: WqTheme.cream,
        appBar: AppBar(
          title: const Text('家长小屋'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(32.w),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const WqPanda(mood: WqPandaMood.think, size: 90),
                SizedBox(height: 16.h),
                Text(
                  '这里是爸爸妈妈的秘密基地',
                  style: TextStyle(
                    fontSize: 17.sp,
                    fontWeight: FontWeight.w800,
                    color: WqTheme.ink,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  '请家长切换到家长模式后查看学习周报哦～',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                    color: WqTheme.inkSoft,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return const _ParentReportBody();
  }
}

class _ParentReportBody extends StatelessWidget {
  const _ParentReportBody();

  @override
  Widget build(BuildContext context) {
    final svc = Get.find<WeiqiService>();
    return Scaffold(
      backgroundColor: WqTheme.cream,
      appBar: AppBar(
        title: const Text('家长小屋'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: WqTheme.ink,
      ),
      body: Obx(() {
        final week = svc.weeklySummary();
        final accuracy = week['puzzles']! > 0
            ? (week['correct']! * 100 ~/ week['puzzles']!)
            : -1;
        final mastery = svc.knowledgeMastery();
        String? weakest;
        var minVal = 101;
        mastery.forEach((k, v) {
          if (v < minVal) {
            minVal = v;
            weakest = k;
          }
        });
        final suggestion = weakest == null
            ? '本周还没有学习记录，陪孩子上第一节「棋子的呼吸」吧！'
            : '本周「$weakest」还有进步空间，建议每天加练 3 道相关题目，或陪下一局 9 路吃子棋巩固手感。';
        return ListView(
          padding: EdgeInsets.all(16.w),
          children: [
            // 周报头部
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '围棋学习周报',
                        style: TextStyle(
                          fontSize: 22.sp,
                          fontWeight: FontWeight.w900,
                          color: WqTheme.ink,
                        ),
                      ),
                      Text(
                        '最近 7 天 · 学习了 ${week['activeDays']} 天',
                        style: TextStyle(
                          fontSize: 12.5.sp,
                          fontWeight: FontWeight.w700,
                          color: WqTheme.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
                const WqPanda(mood: WqPandaMood.happy, size: 54),
              ],
            ),
            SizedBox(height: 12.h),
            // 统计卡
            Row(
              children: [
                _statCard('${week['lessons']}', '完课', '节'),
                SizedBox(width: 10.w),
                _statCard(
                    accuracy >= 0 ? '$accuracy' : '--', '练习正确率', accuracy >= 0 ? '%' : ''),
                SizedBox(width: 10.w),
                _statCard('${week['games']}', '陪下对局', '局'),
              ],
            ),
            SizedBox(height: 12.h),
            // 知识点掌握
            WqCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '知识点掌握',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w800,
                      color: WqTheme.ink,
                    ),
                  ),
                  SizedBox(height: 10.h),
                  if (mastery.isEmpty)
                    Text(
                      '还没有学习记录，从「气之森林」开始吧！',
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                        color: WqTheme.inkSoft,
                      ),
                    )
                  else
                    ...mastery.entries.map((e) => _barRow(e.key, e.value)),
                  if (weakest != null) ...[
                    SizedBox(height: 8.h),
                    Text(
                      '浅色条目 = 建议本周加练，每日 3 题即可',
                      style: TextStyle(
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w600,
                        color: WqTheme.inkFaint,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(height: 12.h),
            // 棋棋建议
            WqCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const WqPanda(mood: WqPandaMood.think, size: 54),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '棋棋的学习建议',
                          style: TextStyle(
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w900,
                            color: WqTheme.greenDeep,
                          ),
                        ),
                        SizedBox(height: 3.h),
                        Text(
                          suggestion,
                          style: TextStyle(
                            fontSize: 13.5.sp,
                            fontWeight: FontWeight.w700,
                            height: 1.6,
                            color: WqTheme.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 12.h),
            // 模块设置
            WqCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '学习设置',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w800,
                      color: WqTheme.ink,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Obx(() => _switchRow(
                        '语音讲解（棋棋说话）',
                        svc.voiceOn.value,
                        (v) => svc.voiceOn.value = v,
                      )),
                  Obx(() => _switchRow(
                        '对局中失误提醒',
                        svc.remindOn.value,
                        (v) => svc.remindOn.value = v,
                      )),
                  Obx(() => _switchRow(
                        '音效（落子/提子）',
                        svc.sfxOn.value,
                        (v) => svc.sfxOn.value = v,
                      )),
                  Obx(() => _chipsRow(
                        '棋棋棋力',
                        [
                          ('温和', 0.68),
                          ('标准', 0.82),
                          ('厉害', 0.92),
                        ],
                        svc.aiSkill.value,
                        (v) => svc.aiSkill.value = v,
                      )),
                ],
              ),
            ),
            SizedBox(height: 20.h),
          ],
        );
      }),
    );
  }

  Widget _statCard(String num, String label, String unit) {
    return Expanded(
      child: WqCard(
        padding: EdgeInsets.symmetric(vertical: 13.h),
        child: Column(
          children: [
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: num,
                    style: TextStyle(
                      fontSize: 24.sp,
                      fontWeight: FontWeight.w900,
                      color: WqTheme.ink,
                    ),
                  ),
                  TextSpan(
                    text: ' $unit',
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w800,
                      color: WqTheme.inkFaint,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 2.h),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.sp,
                fontWeight: FontWeight.w700,
                color: WqTheme.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _barRow(String name, int value) {
    final color = value >= 80
        ? WqTheme.green
        : value >= 55
            ? WqTheme.sun
            : WqTheme.coral;
    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: Row(
        children: [
          SizedBox(
            width: 72.w,
            child: Text(
              name,
              style: TextStyle(
                fontSize: 12.5.sp,
                fontWeight: FontWeight.w800,
                color: WqTheme.ink,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: value / 100),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => LinearProgressIndicator(
                  value: v,
                  minHeight: 12.h,
                  backgroundColor: const Color(0xFFEEF1F6),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 40.w,
            child: Text(
              value >= 0 ? '$value%' : '--',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w900,
                color: WqTheme.inkSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _switchRow(
      String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5.sp,
              fontWeight: FontWeight.w800,
              color: WqTheme.ink,
            ),
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: WqTheme.green,
        ),
      ],
    );
  }

  Widget _chipsRow(
    String label,
    List<(String, double)> options,
    double current,
    ValueChanged<double> onChanged,
  ) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.5.sp,
                fontWeight: FontWeight.w800,
                color: WqTheme.ink,
              ),
            ),
          ),
          Row(
            children: options
                .map((e) => Padding(
                      padding: EdgeInsets.only(left: 6.w),
                      child: GestureDetector(
                        onTap: () => onChanged(e.$2),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 12.w, vertical: 6.h),
                          decoration: BoxDecoration(
                            color: (current - e.$2).abs() < 0.01
                                ? WqTheme.greenSoft
                                : const Color(0xFFF0F2F7),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            e.$1,
                            style: TextStyle(
                              fontSize: 12.sp,
                              fontWeight: FontWeight.w800,
                              color: (current - e.$2).abs() < 0.01
                                  ? WqTheme.greenDeep
                                  : WqTheme.inkFaint,
                            ),
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}
