import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:star_bank/pages/entertainment/weiqi/weiqi_puzzle_page.dart';
import 'package:star_bank/pages/entertainment/weiqi/weiqi_service.dart';

/// 死活题交互回归：
/// 1. 答对后出现「下一题」按钮，不再 1.8 秒自动跳题（孩子看得清棋盘）
/// 2. 做不出可「跳过」，题目进藏宝箱
/// 3. 错题藏宝箱可点开，从列表跳回指定题重做
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('weiqi_puzzle_test');
    Hive.init(dir.path);
    final svc = WeiqiService();
    Get.put(svc);
    await svc.init();
  });

  tearDownAll(() async {
    await Get.delete<WeiqiService>(force: true);
  });

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

  WeiqiService svc() => Get.find<WeiqiService>();

  /// 用小米 10 Pro 的真实逻辑视口(1080×2340 @ DPR 3 ≈ 360×780),
  /// 避免默认 800×600 面板下 ScreenUtil 横竖缩放比失真造成假溢出
  void useRealDeviceViewport(WidgetTester tester) {
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(1080, 2340);
  }

  Future<WeiqiPuzzlePage> pumpPage(WidgetTester tester) async {
    useRealDeviceViewport(tester);
    addTearDown(() {
      tester.view.reset();
    });
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        minTextAdapt: true,
        builder: (context, child) => GetMaterialApp(
          home: const WeiqiPuzzlePage(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    return const WeiqiPuzzlePage();
  }

  testWidgets('答对后出现「下一题」，不再自动跳题', (tester) async {
    svc().solvedPuzzles.clear();
    svc().wrongPuzzles.clear();
    await pumpPage(tester);
    expect(find.textContaining('第 1 /'), findsOneWidget);

    // pz1: 白(6,2) 被围三面，答案 (6,3)
    await tapPoint(tester, 6, 3);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('下一题 ›'), findsOneWidget,
        reason: '答对后应出现手动「下一题」按钮');
    expect(find.text('棋棋恭喜'), findsOneWidget);

    // 推进 3 秒：不应自动跳到第 2 题
    await tester.pump(const Duration(seconds: 3));
    expect(find.textContaining('第 1 /'), findsOneWidget,
        reason: '不再自动跳题，孩子可以慢慢看棋盘');

    // 手动点「下一题」→ 进入第 2 题
    await tester.tap(find.text('下一题 ›'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('第 2 /'), findsOneWidget);
    await drainFx(tester);
  });

  testWidgets('跳过：题目记入藏宝箱并进入下一题', (tester) async {
    svc().solvedPuzzles.clear();
    svc().wrongPuzzles.clear();
    await pumpPage(tester);
    expect(find.textContaining('第 1 /'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.skip_next_rounded));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('第 2 /'), findsOneWidget,
        reason: '跳过后应直接进入下一题');
    expect(svc().wrongPuzzles.contains('pz1'), isTrue,
        reason: '跳过的题应进藏宝箱');
    await drainFx(tester);
  });

  testWidgets('错题藏宝箱：空箱有提示，有错题可点开跳题', (tester) async {
    svc().solvedPuzzles.clear();
    svc().wrongPuzzles.clear();
    await pumpPage(tester);

    // 空箱：点开只弹提示
    await tester.tap(find.text('错题藏宝箱'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('藏宝箱空空如也，快去闯关吧！'), findsOneWidget);
    await drainFx(tester);

    // 放一道错题进去，再点开 → 列表出现 pz1，点击跳回第 1 题
    svc().wrongPuzzles.add('pz1');
    await tester.pump();
    await tester.tap(find.text('错题藏宝箱'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('🎁 错题藏宝箱'), findsOneWidget);
    expect(find.text('一手提子'), findsOneWidget, reason: '错题 pz1 应出现在列表里');

    await tester.tap(find.text('一手提子'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('第 1 /'), findsOneWidget,
        reason: '点宝箱里的题应直接跳到该题');
    await drainFx(tester);
  });
}
