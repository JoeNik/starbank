import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../../controllers/app_mode_controller.dart';
import 'weiqi_engine.dart';
import 'weiqi_panda.dart';
import 'weiqi_service.dart';
import 'weiqi_theme.dart';
import 'weiqi_widgets.dart';

/// 家长小屋：孟菲斯风格学习周报 + 商业级围棋模块设置。
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
            child: WqCard(
              padding: EdgeInsets.all(24.w),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const WqPanda(mood: WqPandaMood.think, size: 84),
                  SizedBox(height: 16.h),
                  Text(
                    '这里是爸爸妈妈的秘密基地',
                    style: TextStyle(
                      fontSize: 17.sp,
                      fontWeight: FontWeight.w900,
                      color: WqTheme.ink,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    '请家长切换到家长模式后查看学习周报与规则设置哦～',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w700,
                      color: WqTheme.inkSoft,
                    ),
                  ),
                ],
              ),
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
        final rank = svc.rankInfo;
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
            : '本周「$weakest」还有进步空间，建议每天加练 3 道相关题目，或陪下一局巩固手感。';

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
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8.w,
                        runSpacing: 4.h,
                        children: [
                          Text(
                            '围棋学习周报',
                            style: TextStyle(
                              fontSize: 21.sp,
                              fontWeight: FontWeight.w900,
                              color: WqTheme.ink,
                            ),
                          ),
                          WqChip.sun(
                            text: '${rank.rank} · ${rank.title}',
                            tiltDeg: -3.0,
                          ),
                        ],
                      ),
                      SizedBox(height: 3.h),
                      Text(
                        '最近 7 天 · 累计学习了 ${week['activeDays']} 天',
                        style: TextStyle(
                          fontSize: 12.5.sp,
                          fontWeight: FontWeight.w800,
                          color: WqTheme.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
                const WqPanda(mood: WqPandaMood.happy, size: 52),
              ],
            ),
            SizedBox(height: 12.h),

            // 统计卡
            Row(
              children: [
                _statCard('${week['lessons']}', '完课', '节', WqTheme.sunSoft),
                SizedBox(width: 10.w),
                _statCard(
                  accuracy >= 0 ? '$accuracy' : '--',
                  '练习正确率',
                  accuracy >= 0 ? '%' : '',
                  WqTheme.greenSoft,
                ),
                SizedBox(width: 10.w),
                _statCard('${week['games']}', '陪下对局', '局', WqTheme.pinkSoft),
              ],
            ),
            SizedBox(height: 12.h),

            // 知识点掌握
            WqCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '📊 知识点掌握度',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w900,
                      color: WqTheme.ink,
                    ),
                  ),
                  SizedBox(height: 10.h),
                  if (mastery.isEmpty)
                    Text(
                      '还没有学习记录，从「气之森林」开始吧！',
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w700,
                        color: WqTheme.inkSoft,
                      ),
                    )
                  else
                    ...mastery.entries.map((e) => _barRow(e.key, e.value)),
                  if (weakest != null) ...[
                    SizedBox(height: 6.h),
                    Text(
                      '提示：可前往「死活与手筋特训」按分类专项强化薄弱项',
                      style: TextStyle(
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w700,
                        color: WqTheme.inkSoft,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(height: 12.h),

            // 棋棋建议
            WqCard(
              color: WqTheme.sunSoft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const WqPanda(mood: WqPandaMood.think, size: 52),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '棋棋的学习建议',
                          style: TextStyle(
                            fontSize: 11.5.sp,
                            fontWeight: FontWeight.w900,
                            color: WqTheme.ink,
                          ),
                        ),
                        SizedBox(height: 3.h),
                        Text(
                          suggestion,
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w800,
                            height: 1.5,
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
                    '⚙️ 学习与对局设置',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w900,
                      color: WqTheme.ink,
                    ),
                  ),
                  SizedBox(height: 6.h),
                  Obx(() => _switchRow(
                        '语音讲解（棋棋说话）',
                        svc.voiceOn.value,
                        (v) => svc.voiceOn.value = v,
                      )),
                  Obx(() => _switchRow(
                        '对局中失误提醒（语音）',
                        svc.remindOn.value,
                        (v) => svc.remindOn.value = v,
                      )),
                  Obx(() => _switchRow(
                        '被打吃警示灯（棋盘橙灯）',
                        svc.atariLightsOn.value,
                        (v) => svc.atariLightsOn.value = v,
                      )),
                  Obx(() => _switchRow(
                        '棋盘四周坐标刻度（A-T / 1-19）',
                        svc.showCoords.value,
                        (v) => svc.showCoords.value = v,
                      )),
                  Obx(() => _switchRow(
                        '13/19路十字准星二次确认防误触',
                        svc.confirmMove.value,
                        (v) => svc.confirmMove.value = v,
                      )),
                  Obx(() => _switchRow(
                        '音效（落子/提子）',
                        svc.sfxOn.value,
                        (v) => svc.sfxOn.value = v,
                      )),
                  const Divider(height: 18, color: WqTheme.ink),
                  Obx(() => _stringChipsRow(
                        '默认对局规则模式',
                        const [
                          ('capture', '🎯 吃子棋（启蒙）'),
                          ('territory', '🏆 标准围地（数子）'),
                        ],
                        svc.ruleMode.value,
                        (v) => svc.ruleMode.value = v,
                      )),
                  Obx(() => _chipsRow(
                        '棋棋棋力（AI 级位）',
                        [
                          for (final lv in wqAiLevels) (lv.name, lv.skill),
                        ],
                        wqAiLevels[svc.aiLevelIndex.value
                                .clamp(0, wqAiLevels.length - 1)]
                            .skill,
                        (v) => svc.aiLevelIndex.value = wqAiLevels
                            .indexWhere((lv) => lv.skill == v)
                            .clamp(0, wqAiLevels.length - 1),
                      )),
                  Obx(() => _countChipsRow(
                        '吃子棋目标（先提几颗算赢）',
                        const [2, 3, 4, 5, 6, 8, 10],
                        svc.winCaptures.value,
                        (v) => svc.winCaptures.value = v,
                        hint: '吃子棋模式的目标：谁先把对方提走这么多颗棋子就赢，默认 3。',
                      )),
                  Obx(() => _countChipsRow(
                        '对局棋盘大小（路数）',
                        const [9, 13, 19],
                        svc.boardSize.value,
                        (v) => svc.boardSize.value = v,
                        hint: '9 路适合刚学，13 路进阶，19 路是标准大棋盘；课程与题库固定 9 路。',
                      )),
                  Obx(() => _countChipsRow(
                        '黑方让子数（0 为分先）',
                        const [0, 2, 3, 4, 5, 9],
                        svc.handicap.value,
                        (v) => svc.handicap.value = v,
                        hint: '让子局开局自动在星位摆放黑子，由白方先行，适合挑战高段位 AI 或亲子对弈。',
                      )),
                  Obx(() => _countChipsRow(
                        '对局棋钟时限（分钟，0 为无限时）',
                        const [0, 5, 15],
                        svc.timeLimitMinutes.value,
                        (v) => svc.timeLimitMinutes.value = v,
                        hint: '0 表示不限时；5 分钟快棋或 15 分钟慢棋可培养孩子比赛时间观念。',
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

  Widget _statCard(String num, String label, String unit, Color bg) {
    return Expanded(
      child: WqCard(
        color: bg,
        padding: EdgeInsets.symmetric(vertical: 12.h),
        child: Column(
          children: [
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: num,
                    style: TextStyle(
                      fontSize: 23.sp,
                      fontWeight: FontWeight.w900,
                      color: WqTheme.ink,
                    ),
                  ),
                  TextSpan(
                    text: ' $unit',
                    style: TextStyle(
                      fontSize: 11.5.sp,
                      fontWeight: FontWeight.w900,
                      color: WqTheme.inkSoft,
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
                fontWeight: FontWeight.w800,
                color: WqTheme.ink,
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
            width: 82.w,
            child: Text(
              name,
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w900,
                color: WqTheme.ink,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 13.h,
              decoration: BoxDecoration(
                color: WqTheme.cream,
                borderRadius: BorderRadius.circular(999),
                border: WqTheme.border(),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: FractionallySizedBox(
                  widthFactor: (value / 100).clamp(0.0, 1.0),
                  alignment: Alignment.centerLeft,
                  child: Container(color: color),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 42.w,
            child: Text(
              value >= 0 ? '$value%' : '--',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w900,
                color: WqTheme.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.sp,
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

  Widget _stringChipsRow(
    String label,
    List<(String, String)> options,
    String current,
    ValueChanged<String> onChanged,
  ) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.w900,
              color: WqTheme.ink,
            ),
          ),
          SizedBox(height: 6.h),
          Wrap(
            spacing: 8.w,
            runSpacing: 6.h,
            children: options
                .map((opt) => GestureDetector(
                      onTap: () => onChanged(opt.$1),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 12.w, vertical: 6.h),
                        decoration: BoxDecoration(
                          color: current == opt.$1 ? WqTheme.sun : Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          border: WqTheme.border(),
                        ),
                        child: Text(
                          opt.$2,
                          style: TextStyle(
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w900,
                            color: WqTheme.ink,
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

  Widget _countChipsRow(
    String label,
    List<int> options,
    int current,
    ValueChanged<int> onChanged, {
    String? hint,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.w900,
              color: WqTheme.ink,
            ),
          ),
          SizedBox(height: 6.h),
          Wrap(
            spacing: 6.w,
            runSpacing: 6.h,
            children: options
                .map((v) => GestureDetector(
                      onTap: () => onChanged(v),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 13.w, vertical: 5.5.h),
                        decoration: BoxDecoration(
                          color: current == v ? WqTheme.green : Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          border: WqTheme.border(),
                        ),
                        child: Text(
                          '$v',
                          style: TextStyle(
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w900,
                            color: WqTheme.ink,
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
          if (hint != null) ...[
            SizedBox(height: 4.h),
            Text(
              hint,
              style: TextStyle(
                fontSize: 10.5.sp,
                fontWeight: FontWeight.w700,
                color: WqTheme.inkSoft,
              ),
            ),
          ],
        ],
      ),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.w900,
              color: WqTheme.ink,
            ),
          ),
          SizedBox(height: 6.h),
          Wrap(
            spacing: 6.w,
            runSpacing: 6.h,
            children: options
                .map((e) => GestureDetector(
                      onTap: () => onChanged(e.$2),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 11.w, vertical: 5.5.h),
                        decoration: BoxDecoration(
                          color: (current - e.$2).abs() < 0.01
                              ? WqTheme.sun
                              : Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          border: WqTheme.border(),
                        ),
                        child: Text(
                          e.$1,
                          style: TextStyle(
                            fontSize: 11.5.sp,
                            fontWeight: FontWeight.w900,
                            color: WqTheme.ink,
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
