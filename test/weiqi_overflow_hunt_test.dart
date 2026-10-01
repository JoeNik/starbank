import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:star_bank/controllers/app_mode_controller.dart';
import 'package:star_bank/pages/entertainment/weiqi/weiqi_course_page.dart';
import 'package:star_bank/pages/entertainment/weiqi/weiqi_home_page.dart';
import 'package:star_bank/pages/entertainment/weiqi/weiqi_parent_page.dart';
import 'package:star_bank/pages/entertainment/weiqi/weiqi_play_page.dart';
import 'package:star_bank/pages/entertainment/weiqi/weiqi_puzzle_page.dart';
import 'package:star_bank/pages/entertainment/weiqi/weiqi_service.dart';

/// 溢出狩猎：在多种小屏尺寸下逐页渲染（含交互态），收集 RenderFlex 溢出等渲染错误。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('weiqi_hunt');
    Hive.init(dir.path);
    final svc = WeiqiService();
    Get.put(svc);
    await svc.init();
    Get.put(AppModeController());
  });

  tearDownAll(() async {
    await Get.delete<AppModeController>(force: true);
    await Get.delete<WeiqiService>(force: true);
  });

  Future<List<String>> pumpAndCollect(
      WidgetTester tester, Widget page, {int pumps = 2}) async {
    final errors = <String>[];
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      final msg = details.exceptionAsString();
      final first = msg.split('\n').first;
      if (!first.contains('overflowed')) return;
      final ctxLines = details.informationCollector == null
          ? ''
          : details.informationCollector!().join(' | ');
      final key = '$first :: $ctxLines';
      if (!errors.contains(key)) errors.add(key);
    };
    try {
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (context, child) => GetMaterialApp(home: page),
        ),
      );
      for (var i = 0; i < pumps; i++) {
        await tester.pump(const Duration(milliseconds: 400));
      }
    } finally {
      FlutterError.onError = original;
    }
    return errors;
  }

  Future<void> tapPoint(WidgetTester tester, double fx, double fy) async {
    final rect = tester.getRect(find.byKey(const ValueKey('wq-board-square')));
    await tester.tapAt(
        Offset(rect.left + rect.width * fx, rect.top + rect.height * fy));
    await tester.pump(const Duration(milliseconds: 150));
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final finder = find.text(text);
    if (finder.evaluate().isNotEmpty) {
      await tester.tap(finder.last);
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  for (final screen in [
    const Size(375, 812),
    const Size(360, 640),
    const Size(320, 568),
    const Size(800, 600),
    const Size(640, 480),
    const Size(500, 400),
  ]) {
    testWidgets('溢出检查 $screen', (tester) async {
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 3.0;
      });

      final report = <String>[];

      // ---- 静态页 ----
      for (final entry in [
        'home: WeiqiHomePage()',
        'course: WeiqiCoursePage(0)',
        'puzzle: WeiqiPuzzlePage()',
        'play: WeiqiPlayPage(ai)',
        'parent: WeiqiParentPage()',
      ]) {
        Widget page;
        if (entry.startsWith('home')) {
          page = const WeiqiHomePage();
        } else if (entry.startsWith('course')) {
          page = const WeiqiCoursePage(lessonIndex: 0);
        } else if (entry.startsWith('puzzle')) {
          page = const WeiqiPuzzlePage();
        } else if (entry.startsWith('play')) {
          page = const WeiqiPlayPage(opponent: WqOpponent.ai);
        } else {
          page = const WeiqiParentPage();
        }
        final errs = await pumpAndCollect(tester, page);
        for (final e in errs) {
          report.add('$entry @ $screen -> $e');
        }
      }

      // ---- 课程交互全流程（到结算面板 + 对手选择） ----
      await pumpAndCollect(tester, const WeiqiCoursePage(lessonIndex: 0));
      for (var i = 0; i < 6; i++) {
        await tapText(tester, '下一步 ›');
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tapPoint(tester, 0.37, 0.37);
      await tapPoint(tester, 0.63, 0.37);
      await tapPoint(tester, 0.37, 0.63);
      await tapPoint(tester, 0.63, 0.63);
      await tapText(tester, '下一步 ›');
      await tapPoint(tester, 0.63, 0.63); // 提子
      await tester.pump(const Duration(milliseconds: 200));
      await tapText(tester, '领取奖励 ✦');
      await tester.pump(const Duration(milliseconds: 300));
      await tapText(tester, '和棋棋下一盘巩固一下'); // 对手选择弹层
      await tester.pump(const Duration(milliseconds: 300));
      // 收集弹层阶段的渲染错误
      {
        final original = FlutterError.onError;
        final errs = <String>[];
        FlutterError.onError = (d) {
          final first = d.exceptionAsString().split('\n').first;
          if (!errs.contains(first)) errs.add(first);
        };
        try {
          await tester.pump(const Duration(milliseconds: 300));
        } finally {
          FlutterError.onError = original;
        }
        for (final e in errs) {
          report.add('course-flow(结算/弹层) @ $screen -> $e');
        }
      }

      // ---- 陪下交互：落子 + 复盘卡 ----
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await pumpAndCollect(tester, const WeiqiPlayPage(opponent: WqOpponent.ai));
      await tapPoint(tester, 0.15, 0.15);
      await tester.pump(const Duration(milliseconds: 2300)); // AI 完成一手
      await tapPoint(tester, 0.85, 0.15);
      await tester.pump(const Duration(milliseconds: 2300));
      {
        final original = FlutterError.onError;
        final errs = <String>[];
        FlutterError.onError = (d) {
          final first = d.exceptionAsString().split('\n').first;
          if (!errs.contains(first)) errs.add(first);
        };
        try {
          await tapText(tester, '结束'); // 3+1 复盘卡
          await tester.pump(const Duration(milliseconds: 400));
        } finally {
          FlutterError.onError = original;
        }
        for (final e in errs) {
          report.add('play-flow(复盘卡) @ $screen -> $e');
        }
      }

      debugPrint('==== 溢出狩猎结果 $screen ====');
      if (report.isEmpty) {
        debugPrint('  ✅ 无溢出');
      } else {
        report.toSet().forEach(debugPrint);
      }
      expect(report, isEmpty, reason: '发现布局溢出，见日志 $screen');
    });
  }
}
