import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:star_bank/pages/entertainment/weiqi/weiqi_play_page.dart';
import 'package:star_bank/pages/entertainment/weiqi/weiqi_service.dart';

/// 陪下对局的终局交互回归：
/// 1. 达到提子目标后**不**立刻弹结算卡——先停在盘面（孩子看清输赢在哪），
///    底部换成「看看战报 / 再来一局」，悔棋/结束等已无意义的按钮消失
/// 2. 点「看看战报」才弹结算卡；点「再来一局」重新开局
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('weiqi_play_test');
    Hive.init(dir.path);
    final svc = WeiqiService();
    Get.put(svc);
    await svc.init();
  });

  tearDownAll(() async {
    await Get.delete<WeiqiService>(force: true);
  });

  WeiqiService svc() => Get.find<WeiqiService>();

  Future<void> tapPoint(WidgetTester tester, int x, int y) async {
    final rect = tester.getRect(find.byKey(const ValueKey('wq-board-square')));
    const pad = 6.2;
    final step = (100 - pad * 2) / 8;
    final dx = rect.left + rect.width * ((pad + x * step) / 100);
    final dy = rect.top + rect.height * ((pad + y * step) / 100);
    await tester.tapAt(Offset(dx, dy));
    await tester.pump(const Duration(milliseconds: 120));
  }

  Future<void> drainFx(WidgetTester tester) async {
    Get.closeAllSnackbars();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('提子达标后停在盘面，「看看战报」才弹结算', (tester) async {
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(1080, 2340);
    addTearDown(tester.view.reset);
    svc().winCaptures.value = 2;

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        minTextAdapt: true,
        builder: (context, child) => GetMaterialApp(
          home: const WeiqiPlayPage(opponent: WqOpponent.parent),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // 家长陪下：黑白轮流点击即可。黑棋提两颗孤子（提子目标设为 2）：
    // 黑(3,4) 白(4,4) 黑(5,4) 白(0,0) 黑(4,3) 白(8,8)
    // 黑(4,5) 提走 (4,4) → 1 颗；白(2,8) 黑(1,0) 白(6,0) 黑(0,1) 提走 (0,0) → 2 颗，终局
    const moves = [
      (3, 4), (4, 4), //
      (5, 4), (0, 0), //
      (4, 3), (8, 8), //
      (4, 5), (2, 8), // 提走第一颗
      (1, 0), (6, 0), //
      (0, 1), // 提走第二颗 → 达标
    ];
    for (final (x, y) in moves) {
      await tapPoint(tester, x, y);
      await tester.pump(const Duration(milliseconds: 120));
    }
    await tester.pump(const Duration(milliseconds: 300));

    // 不立刻弹结算卡
    expect(find.text('你赢啦！'), findsNothing,
        reason: '终局先停在盘面，不自动弹结算');
    expect(find.textContaining('赢咯'), findsOneWidget,
        reason: '气泡先讲清楚赢在哪里');

    // 底部按钮换成战报/再来一局，死按钮消失
    expect(find.text('看看战报'), findsOneWidget);
    expect(find.text('再来一局'), findsOneWidget);
    expect(find.text('悔棋'), findsNothing);
    expect(find.text('结束'), findsNothing);

    // 点「看看战报」→ 结算卡出现
    await tester.tap(find.text('看看战报'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('你赢啦！'), findsOneWidget);
    expect(find.text('重看棋局 · 学一手'), findsOneWidget);

    // 「再来一局」关掉结算并重开：悔棋/结束回来了
    await tester.tap(find.text('再来一局！'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('你赢啦！'), findsNothing);
    expect(find.text('悔棋'), findsOneWidget);
    expect(find.text('结束'), findsOneWidget);
    expect(find.text('看看战报'), findsNothing);
    await drainFx(tester);
  });
}
