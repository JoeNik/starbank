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
          goalPoint2: pz.goalPoint2,
          captured: r.captured,
        );
        expect(done, isTrue, reason: '${pz.id} 答案点未达成目标');
      }
    });
  });

  group('大棋盘（可变尺寸）', () {
    test('19 路：铺 120 子后 AI 仍能给出合法着法', () {
      final g = WqGame(n: 19);
      final rnd = Random(7);
      var color = 1;
      for (var k = 0; k < 120; k++) {
        final empty = [for (var i = 0; i < g.n * g.n; i++) if (g.s[i] == 0) i];
        if (empty.isEmpty) break;
        final i = empty[rnd.nextInt(empty.length)];
        if (g.tryPlay(i, color).ok) color = 3 - color;
      }
      final sw = Stopwatch()..start();
      final mv = WqAi.pickMove(g, color, 0.88, rnd: Random(1));
      sw.stop();
      expect(mv, isNotNull, reason: '19 路中盘仍应有合法点');
      expect(g.tryPlay(mv, color).ok, isTrue);
      expect(sw.elapsedMilliseconds, lessThan(2000),
          reason: '单步 AI 计算不应卡住界面');
    });

    test('13/19 路棋盘：提子与越界判定按 n 计算', () {
      final g = WqGame(n: 13);
      expect(g.s.length, 169);
      // 13 路角上提子
      g.tryPlay(0, 2); // (0,0)
      g.tryPlay(1, 1); // (1,0)，角上白子剩 1 气
      final r = g.tryPlay(13, 1); // (0,1)，提走角上白子
      expect(r.captured, [0]);
      expect(g.tryPlay(14, 1).ok, isTrue); // (1,1) 仍是空点
      expect(g.tryPlay(169, 1).ok, isFalse);
      expect(g.tryPlay(169, 1).reason, 'offboard');
      expect(g.tryPlay(-1, 1).reason, 'offboard');
    });
  });

  group('商业级围地模式、让子与多步题库验证', () {
    test('虚手(Pass)与让子(Handicap)星位摆放正确', () {
      final g = WqGame(n: 9);
      g.setupHandicap(4);
      expect(g.handicap, 4);
      expect(g.stoneCount(), 4);
      // 9路四角星位 (2,2), (6,2), (2,6), (6,6)
      expect(g.s[p(2, 2)], 1);
      expect(g.s[p(6, 2)], 1);
      expect(g.s[p(2, 6)], 1);
      expect(g.s[p(6, 6)], 1);

      g.pass(2);
      expect(g.consecutivePasses, 1);
      g.pass(1);
      expect(g.consecutivePasses, 2);
      // 落子后连续虚手清零
      g.tryPlay(p(4, 4), 2);
      expect(g.consecutivePasses, 0);
    });

    test('WqTerritoryEstimator 领地与贴目计算准确', () {
      final g = WqGame(n: 9);
      // 黑棋完整围住左上角 2x2 空点：(0,0),(1,0),(0,1),(1,1) 共 4 空，花 5 颗子
      for (final pt in [p(2, 0), p(2, 1), p(2, 2), p(1, 2), p(0, 2)]) {
        g.tryPlay(pt, 1);
      }
      // 白棋完整围住右下角 1x1 空点 (8,8)，花 3 颗子
      for (final pt in [p(7, 8), p(7, 7), p(8, 7)]) {
        g.tryPlay(pt, 2);
      }
      final summary = WqTerritoryEstimator.estimate(
        g,
        deadStones: const {},
        includeInfluence: false,
      );
      expect(summary.blackStones, 5);
      expect(summary.blackTerritory, 4);
      expect(summary.blackArea, 9);
      expect(summary.whiteStones, 3);
      expect(summary.whiteTerritory, 1);
      expect(summary.whiteArea, 4);
    });

    test('多步连续应对死活题全流程合法（含 AI 抵抗手与第 2 手终结）', () {
      final multiPuzzles = wqPuzzles.where((pz) => pz.isMultiStep).toList();
      expect(multiPuzzles, isNotEmpty);
      for (final pz in multiPuzzles) {
        final g = WqGame();
        for (final op in pz.setup) {
          if (!op.reset) g.tryPlay(op.point, op.color!);
        }
        // 第 1 手玩家正解
        expect(g.tryPlay(pz.answerPoint, pz.playerColor).ok, isTrue,
            reason: '${pz.id} 第1手非法');
        // AI 自动应对手
        expect(g.tryPlay(pz.aiReplyPoint!, 3 - pz.playerColor).ok, isTrue,
            reason: '${pz.id} AI应对手非法');
        // 第 2 手玩家终结手
        final r2 = g.tryPlay(pz.secondAnswerPoint!, pz.playerColor);
        expect(r2.ok, isTrue, reason: '${pz.id} 第2手非法');
        expect(r2.captured, isNotEmpty, reason: '${pz.id} 第2手应完成提子终结');
      }
    });
  });
}
