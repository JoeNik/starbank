import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:star_bank/pages/entertainment/weiqi/weiqi_replay_page.dart';

/// 回放页布局回归：讲解气泡高度固定，棋盘不得随文字长短跳动。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('讲解文字长短变化时棋盘尺寸与位置保持不变', (tester) async {
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(1080, 2340);
    addTearDown(tester.view.reset);

    const longNote =
        '这一手之前，白棋有一块棋只剩一口气——橙色圈就是那口气，应该在那个点一手提掉它：'
        '看到「打吃」先提为敬，别急着去别处围空，否则机会就悄悄溜走啦。';
    final moves = <({int color, int point})>[
      (color: 1, point: 2 * 9 + 2),
      (color: 2, point: 4 * 9 + 4),
      (color: 1, point: 6 * 9 + 6),
      (color: 2, point: 2 * 9 + 6),
    ];

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        minTextAdapt: true,
        builder: (context, child) => GetMaterialApp(
          home: WeiqiReplayPage(
            moves: moves,
            notes: {0: '好棋！', 1: longNote, 2: '稳一手。'},
            marks: {1: 3 * 9 + 4},
            grades: {0: 'great', 2: 'ok'},
            better: {1: 3 * 9 + 4},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    final boardFinder = find.byKey(const ValueKey('wq-board-square'));
    final base = tester.getRect(boardFinder);

    // 逐手前进：每一步的气泡文字长度不同（含超长讲解）
    for (var k = 1; k <= moves.length; k++) {
      await tester.tap(find.text('下一手 ›'));
      await tester.pump(const Duration(milliseconds: 300));
      final now = tester.getRect(boardFinder);
      expect(now.top, closeTo(base.top, 0.5),
          reason: '第 $k 手后棋盘纵向位置发生变化');
      expect(now.width, closeTo(base.width, 0.5),
          reason: '第 $k 手后棋盘宽度发生变化');
      expect(now.height, closeTo(base.height, 0.5),
          reason: '第 $k 手后棋盘高度发生变化');
    }

    // 切换进入「试下研究」模式再退出，棋盘位置与尺寸同样保持恒定不跳动
    await tester.tap(find.text('🧪 试下研究'));
    await tester.pump(const Duration(milliseconds: 300));
    final studyRect = tester.getRect(boardFinder);
    expect(studyRect.top, closeTo(base.top, 0.5));
    expect(studyRect.height, closeTo(base.height, 0.5));
  });
}