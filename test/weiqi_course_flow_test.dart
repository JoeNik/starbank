import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:star_bank/pages/entertainment/weiqi/weiqi_board.dart';
import 'package:star_bank/pages/entertainment/weiqi/weiqi_course_page.dart';
import 'package:star_bank/pages/entertainment/weiqi/weiqi_service.dart';

/// 回归用户报告的 bug：完成提子挑战后，点「下一步/领取奖励」仍提示要下棋。
/// 根因是棋盘 State 的 SingleTickerProviderStateMixin 在提子动画时抛异常，
/// 导致完成状态未置位。此测试走通 L1 全流程做回归。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('weiqi_test');
    Hive.init(dir.path);
    final svc = WeiqiService();
    Get.put(svc);
    await svc.init();
  });

  tearDownAll(() async {
    await Get.delete<WeiqiService>(force: true);
  });

  /// 把棋盘交叉点 (x, y) 换算成全局坐标并点击
  Future<void> tapPoint(WidgetTester tester, int x, int y) async {
    final rect = tester.getRect(find.byType(WeiqiBoardView));
    const pad = 6.2;
    final step = (100 - pad * 2) / 8;
    final dx = rect.left + rect.width * ((pad + x * step) / 100);
    final dy = rect.top + rect.height * ((pad + y * step) / 100);
    await tester.tapAt(Offset(dx, dy));
    await tester.pump(const Duration(milliseconds: 120));
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.tap(find.text(text).last);
    await tester.pump(const Duration(milliseconds: 120));
  }

  testWidgets('L1 全流程：找气问答 → 提子挑战 → 领取奖励', (tester) async {
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (context, child) => GetMaterialApp(
          home: const WeiqiCoursePage(lessonIndex: 0),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    // 步骤 1-6 都是演示，连点 6 次下一步
    for (var i = 0; i < 6; i++) {
      await tapText(tester, '下一步 ›');
      await tester.pump(const Duration(milliseconds: 150));
    }
    // 现在应处于第 7 步「动手试试」（找气问答）
    expect(find.text('已点亮 0 / 4 个气点'), findsOneWidget,
        reason: '应进入找气问答步骤');

    // 点亮天元白棋的 4 口气: (3,4) (5,4) (4,3) (4,5)
    await tapPoint(tester, 3, 4);
    await tapPoint(tester, 5, 4);
    await tapPoint(tester, 4, 3);
    await tapPoint(tester, 4, 5);
    await tester.pump(const Duration(milliseconds: 200));

    // 完成后点下一步 → 不应被拦截
    await tapText(tester, '下一步 ›');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('先完成这一步的小任务哦～'), findsNothing,
        reason: '找气问答完成后，下一步不应再被拦截');
    expect(find.text('点最后一口气，提走它！'), findsOneWidget,
        reason: '应进入第 8 步提子挑战');

    // 【核心回归】完成提子挑战：点 (4,5) 提走天元白棋
    await tapPoint(tester, 4, 5);
    await tester.pump(const Duration(milliseconds: 300));

    // 再点领取奖励 → 不应再被拦截（这正是用户报告的 bug 场景）
    await tapText(tester, '领取奖励 ✦');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('先完成这一步的小任务哦～'), findsNothing,
        reason: '提子挑战完成后，领取奖励不应再被拦截');
    expect(find.text('课程完成！'), findsOneWidget, reason: '应弹出结算面板');

    // 让庆祝彩带等挂起的 Timer 走完，避免测试收尾报 pending timer
    await tester.pump(const Duration(seconds: 3));
  });
}
