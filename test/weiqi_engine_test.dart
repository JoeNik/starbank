import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:star_bank/pages/entertainment/weiqi/weiqi_data.dart';
import 'package:star_bank/pages/entertainment/weiqi/weiqi_engine.dart';

void main() {
  // 索引 = y * 9 + x
  int p(int x, int y) => y * 9 + x;

  group('WqGame 基本规则', () {
    test('中央棋子有4口气，落子后减少', () {
      final g = WqGame();
      expect(g.tryPlay(p(4, 4), 2).ok, isTrue);
      expect(g.libsOf(g.groupAt(p(4, 4))).length, 4);
      g.tryPlay(p(3, 4), 1);
      expect(g.libsOf(g.groupAt(p(4, 4))).length, 3);
    });

    test('提子：堵住最后一口气后整组被提走', () {
      final g = WqGame();
      g.tryPlay(p(6, 2), 2);
      g.tryPlay(p(5, 2), 1);
      g.tryPlay(p(7, 2), 1);
      g.tryPlay(p(6, 1), 1);
      final r = g.tryPlay(p(6, 3), 1); // 最后一口气
      expect(r.ok, isTrue);
      expect(r.captured, [p(6, 2)]);
      expect(g.s[p(6, 2)], 0);
      expect(g.capBlack, 1);
    });

    test('禁入点：无气且无提子的落子被拒绝', () {
      final g = WqGame();
      g.tryPlay(p(4, 3), 2);
      g.tryPlay(p(3, 4), 2);
      g.tryPlay(p(5, 4), 2);
      g.tryPlay(p(4, 5), 2);
      final r = g.tryPlay(p(4, 4), 1);
      expect(r.ok, isFalse);
      expect(r.reason, 'suicide');
      expect(g.s[p(4, 4)], 0); // 棋盘未被改变
    });

    test('能提子的点不是禁入点', () {
      final g = WqGame();
      // 白 39+40 两子，黑填 38/41/30/31/48
      g.tryPlay(p(3, 4), 2);
      g.tryPlay(p(4, 4), 2);
      g.tryPlay(p(2, 4), 1);
      g.tryPlay(p(5, 4), 1);
      g.tryPlay(p(3, 3), 1);
      g.tryPlay(p(4, 3), 1);
      g.tryPlay(p(3, 5), 1);
      final r = g.tryPlay(p(4, 5), 1);
      expect(r.ok, isTrue);
      expect(r.captured.toSet(), {p(3, 4), p(4, 4)});
    });

    test('打劫：提劫后对方不能马上提回', () {
      final g = WqGame();
      // 白: 39/31/49/41，黑: 42/32/50
      g.tryPlay(p(3, 4), 2);
      g.tryPlay(p(4, 3), 2);
      g.tryPlay(p(4, 5), 2);
      g.tryPlay(p(5, 4), 2);
      g.tryPlay(p(6, 4), 1);
      g.tryPlay(p(5, 3), 1);
      g.tryPlay(p(5, 5), 1);
      final r1 = g.tryPlay(p(4, 4), 1); // 提走 41
      expect(r1.ok, isTrue);
      expect(r1.captured, [p(5, 4)]);
      expect(g.ko, p(5, 4));
      final r2 = g.tryPlay(p(5, 4), 2); // 马上提回 → 劫争禁止
      expect(r2.ok, isFalse);
      expect(r2.reason, 'ko');
    });

    test('clone / restoreFrom 快照一致性', () {
      final g = WqGame();
      g.tryPlay(p(4, 4), 1);
      final snap = g.clone();
      g.tryPlay(p(0, 0), 2);
      g.restoreFrom(snap);
      expect(g.s[p(0, 0)], 0);
      expect(g.s[p(4, 4)], 1);
      expect(g.capWhite, 0);
    });
  });

  group('拟人 AI 与求助', () {
    test('AI 会抓住一手提子的机会', () {
      final g = WqGame();
      g.tryPlay(p(6, 2), 2); // 白子只剩一口气
      g.tryPlay(p(5, 2), 1);
      g.tryPlay(p(7, 2), 1);
      g.tryPlay(p(6, 1), 1);
      final mv = WqAi.pickMove(g, 1, 1.0, rnd: Random(42)); // 固定种子，稳定不犯错
      expect(mv, p(6, 3));
    });

    test('AI 求助目标：优先指向可提子的气点', () {
      final g = WqGame();
      g.tryPlay(p(6, 2), 2);
      g.tryPlay(p(5, 2), 1);
      g.tryPlay(p(7, 2), 1);
      g.tryPlay(p(6, 1), 1);
      final hint = WqAi.hintTarget(g, 1);
      expect(hint, isNotNull);
      expect(hint!.type, 'capture');
      expect(hint.pt, p(6, 3));
    });

    test('AI 求助目标：自己被打吃时指向逃跑点', () {
      final g = WqGame();
      g.tryPlay(p(4, 4), 2); // 白子
      g.tryPlay(p(3, 4), 1);
      g.tryPlay(p(5, 4), 1);
      g.tryPlay(p(4, 3), 1); // 白子只剩 1 口气 (4,5)
      final hint = WqAi.hintTarget(g, 2);
      expect(hint, isNotNull);
      expect(hint!.type, 'escape');
      expect(hint.pt, p(4, 5));
    });
  });

  group('课程/题库数据合法性', () {
    test('所有课程的演示操作都能被规则引擎正确执行（累积重放）', () {
      for (final lesson in wqLessons) {
        var g = WqGame();
        for (final step in lesson.steps) {
          if (step.ops.any((op) => op.reset)) {
            g = WqGame();
          }
          for (final op in step.ops) {
            if (op.reset) continue;
            final r = g.tryPlay(op.point, op.color!);
            if (op.tryOnly) {
              // tryPut 用于演示「被拒绝」的着法（禁入点/打劫）
              expect(r.ok, isFalse,
                  reason: '${lesson.id} tryPut(${op.point}) 应被拒绝');
            } else {
              expect(r.ok, isTrue,
                  reason:
                      '${lesson.id} 第${lesson.no}课 put(${op.point}) 非法: ${r.reason}');
            }
          }
        }
      }
    });

    test('带 reset 的课程步骤重放后局面正确（L1 提子演示）', () {
      // L1 第6步：黑 39/41/31/49 四手应提走天元白子
      final g = WqGame();
      g.tryPlay(p(4, 4), 2);
      g.tryPlay(p(3, 4), 1);
      g.tryPlay(p(5, 4), 1);
      g.tryPlay(p(4, 3), 1);
      final r = g.tryPlay(p(4, 5), 1);
      expect(r.ok, isTrue);
      expect(r.captured, [p(4, 4)]);
    });

    test('所有死活题的答案点都能达成目标', () {
      for (final pz in wqPuzzles) {
        final g = WqGame();
        for (final op in pz.setup) {
          final r = g.tryPlay(op.point, op.color!);
          expect(r.ok, isTrue,
              reason: '${pz.id} 摆题非法: put(${op.point}) ${r.reason}');
        }
        final r = g.tryPlay(pz.answerPoint, pz.playerColor);
        expect(r.ok, isTrue, reason: '${pz.id} 答案点非法');
        final done = wqCheckGoal(
          g,
          pz.goal,
          playerColor: pz.playerColor,
          minCapture: pz.minCapture,
          minLibs: pz.minLibs,
          goalPoint: pz.goalPoint,
          captured: r.captured,
        );
        expect(done, isTrue, reason: '${pz.id} 答案点未达成目标');
      }
    });
  });
}
