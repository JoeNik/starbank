import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../../widgets/toast_utils.dart';
import 'weiqi_board.dart';
import 'weiqi_engine.dart';
import 'weiqi_panda.dart';
import 'weiqi_sfx.dart';
import 'weiqi_service.dart';
import 'weiqi_replay_page.dart';
import 'weiqi_theme.dart';
import 'weiqi_widgets.dart';

/// 对手选择底部弹层（课程结算页与模块首页共用）。
/// [exitToHomeAfterGame]：从课程结算进入时传 true，
/// 对局结束点「回小岛休息一下」会连课程页一起退出，直接回到棋妙岛主页。
Future<void> showWqOpponentPicker(
  BuildContext context, {
  bool exitToHomeAfterGame = false,
}) async {
  await showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return Padding(
        padding: const EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: 12,
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Container(
              width: 320,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: WqTheme.cream,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              const Text(
                '今天和谁下一盘？',
                textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: WqTheme.ink,
              ),
            ),
              const SizedBox(height: 14),
              _opponentOption(
                ctx,
                panda: const WqPanda(mood: WqPandaMood.happy, size: 52),
                title: '和棋棋下',
                subtitle: '棋棋会陪你慢慢下，还会悄悄犯错哦',
                color: WqTheme.greenSoft,
                onTap: () {
                  Navigator.of(ctx).pop();
                  Get.to(() => WeiqiPlayPage(
                        opponent: WqOpponent.ai,
                        exitToHome: exitToHomeAfterGame,
                      ));
                },
              ),
              const SizedBox(height: 10),
              _opponentOption(
                ctx,
                panda: Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    color: WqTheme.sunSoft,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                      child: Text('👪', style: TextStyle(fontSize: 26))),
                ),
                title: '和家长下',
                subtitle: '同一部手机轮流落子 · 先提 3 颗获胜',
                color: WqTheme.sunSoft,
                onTap: () {
                  Navigator.of(ctx).pop();
                  Get.to(() => WeiqiPlayPage(
                        opponent: WqOpponent.parent,
                        exitToHome: exitToHomeAfterGame,
                      ));
                },
              ),
            ],
          ),
        ),
          ),
        ),
      );
    },
  );
}

Widget _opponentOption(
  BuildContext ctx, {
  required Widget panda,
  required String title,
  required String subtitle,
  required Color color,
  required VoidCallback onTap,
}) {
  return Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0x0F23324D)),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Center(child: panda),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: WqTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: WqTheme.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: WqTheme.inkFaint),
          ],
        ),
      ),
    ),
  );
}

enum WqOpponent { ai, parent }

/// 陪下模式：熊猫棋棋坐对面陪孩子下一局（9 路吃子棋，先提 3 颗获胜）。
class WeiqiPlayPage extends StatefulWidget {
  final WqOpponent opponent;

  /// 从课程结算进入的对局：结束时「回小岛休息一下」直接回到棋妙岛主页
  final bool exitToHome;

  const WeiqiPlayPage({
    super.key,
    this.opponent = WqOpponent.ai,
    this.exitToHome = false,
  });

  @override
  State<WeiqiPlayPage> createState() => _WeiqiPlayPageState();
}

class _WeiqiPlayPageState extends State<WeiqiPlayPage> {
  static const int _winCaptures = 3;
  static const int _maxStones = 30;

  late final WeiqiService _svc;
  late WqGame _game;
  final List<WqGame> _history = [];
  bool _over = false;
  bool _busy = false;
  int _helpLeft = 3;
  int _helpStage = 0;
  String _helpKey = '';
  int _turn = 1; // 家长陪下：1=孩子 2=家长
  final Set<int> _reminded = {};
  int? _ownAtariBefore;
  bool _pendingCapture = false;
  final List<String> _milestones = [];
  String? _improvement;
  Timer? _aiTimer;

  /// 对局回放：每一手（颜色 + 落点）与关键手的讲解
  final List<({int color, int point})> _replayMoves = [];
  final Map<int, String> _replayNotes = {};
  /// 讲解标记：着手序号 → 棋盘上要圈出的「最后一口气」位置
  final Map<int, int> _replayMarks = {};
  /// 孩子的棋被打吃时的最后一口气（警示小灯）
  Set<int> _dangerLibs = {};

  /// 提子现场讲解：残影（点→色）+ 计时器
  Map<int, int> _explainGhosts = {};
  Timer? _explainTimer;

  final WqBoardController _boardCtrl = WqBoardController();
  Set<int> _blink = {};
  int? _glowCenter;
  String _bubbleText = '';
  WqPandaMood _mood = WqPandaMood.happy;

  bool get _isAi => widget.opponent == WqOpponent.ai;

  @override
  void initState() {
    super.initState();
    _svc = Get.find<WeiqiService>();
    _resetGame();
  }

  @override
  void dispose() {
    _aiTimer?.cancel();
    _explainTimer?.cancel();
    _svc.stopSpeak();
    super.dispose();
  }

  void _resetGame() {
    _game = WqGame();
    _history.clear();
    _over = false;
    _busy = false;
    _helpLeft = 3;
    _helpStage = 0;
    _helpKey = '';
    _turn = 1;
    _reminded.clear();
    _ownAtariBefore = null;
    _pendingCapture = false;
    _milestones.clear();
    _improvement = null;
    _replayMoves.clear();
    _replayNotes.clear();
    _replayMarks.clear();
    _dangerLibs = {};
    _explainGhosts = {};
    _explainTimer?.cancel();
    _blink = {};
    _glowCenter = null;
    _say(
      _isAi
          ? '我来啦！我们玩吃子棋：谁先把对方提走 $_winCaptures 颗棋子，谁就赢！你先下～'
          : '亲子吃子棋开始！你执黑先下，谁先提走对方 $_winCaptures 颗棋子就赢！',
      WqPandaMood.happy,
      speakIt: true,
    );
    setState(() {});
  }

  void _say(String text, WqPandaMood mood, {bool speakIt = false}) {
    _bubbleText = text;
    _mood = mood;
    setState(() {});
    if (speakIt) _svc.speak(text);
  }

  // ================= 落子 =================

  void _onTap(int i) {
    if (_over || _busy) return;
    if (_game.s[i] != 0) {
      WqSfx.oops();
      ToastUtils.showInfo('这里已经有棋子啦');
      return;
    }
    if (_isAi ? false : _turn == 2) {
      _parentMove(i);
      return;
    }
    _childMove(i);
  }

  void _childMove(int i) {
    _history.add(_game.clone());
    _clearMarks();
    final r = _game.tryPlay(i, 1);
    if (!r.ok) {
      _history.removeLast();
      WqSfx.oops();
      if (r.reason == 'ko') {
        _say('哎呀，这里刚被提过一颗子，要隔一手才能下回来——这叫「打劫」的小规则～',
            WqPandaMood.think,
            speakIt: true);
      } else if (r.reason == 'suicide') {
        _say('这里没有气，棋子站不住哦——这叫「禁入点」，换一个地方下吧！', WqPandaMood.think,
            speakIt: true);
        _blinkTemp(i);
      }
      return;
    }
    WqSfx.stone();
    HapticFeedback.lightImpact();
    _helpStage = 0;
    _explainTimer?.cancel();
    _explainGhosts = {};
    final myIdx = _replayMoves.length;
    // 落子前先看一眼：白棋是否有只剩一口气的子（错过机会时，回放要圈出那口气）
    final whiteAtariLibs = _atariLibsOf(2);
    _replayMoves.add((color: 1, point: i));
    if (r.captured.isNotEmpty) {
      WqSfx.capture();
      _boardCtrl.flyCaptures(r.captured, 2);
      _milestones.add(r.captured.length > 1
          ? '一手提走 ${r.captured.length} 颗棋子，好一个双打！'
          : '提子成功！你把白棋的呼吸全堵住啦～');
      _replayNotes[myIdx] = r.captured.length > 1
          ? '这一手提走 ${r.captured.length} 颗，好棋！'
          : '这一手把白棋的气全堵住了，提子成功！';
      _say(
        r.captured.length > 1
            ? '哇！一手提走 ${r.captured.length} 颗，这是「双打」的好棋呀！'
            : '提子成功！你把白棋的呼吸全堵住啦～',
        WqPandaMood.cheer,
        speakIt: true,
      );
      if (_game.capBlack >= _winCaptures) return _endGame('win');
    } else {
      // 逃子里程碑
      if (_ownAtariBefore != null) {
        final grp = _game.groupAt(_ownAtariBefore!);
        if (grp.isNotEmpty && _game.libsOf(grp).length >= 2) {
          _milestones.add('被包围的士兵成功逃出来啦，会「长气」了！');
          _replayNotes[myIdx] = '这一手让被包围的士兵长出了气，逃出去啦！';
        }
        _ownAtariBefore = null;
      }
      // 机会溜走：之前有可提的白子却没提
      if (_pendingCapture) {
        _improvement ??= '白棋的士兵曾只剩一口气，机会悄悄溜走了——下次看到「打吃」，先一手提走它！';
        _replayNotes[myIdx] ??= '这一手之前，白棋有子只剩一口气——橙色圈就是那口气，应该在这里一手提掉哦';
        if (whiteAtariLibs.isNotEmpty) {
          _replayMarks[myIdx] = whiteAtariLibs.first;
        }
        _pendingCapture = false;
      }
      // 自己的棋落入打吃
      final myAtariLibs = _atariLibsOf(1);
      if (myAtariLibs.isNotEmpty) {
        _replayNotes[myIdx] ??= '这手棋之后，自己的棋只剩一口气了——橙色圈就是那口气，被堵住就会被提走哦';
        _replayMarks[myIdx] = myAtariLibs.first;
      }
    }
    _updateDanger();
    if (_game.stoneCount() >= _maxStones) return _endGame('review');
    if (_isAi) {
      _aiTurn();
    } else {
      _turn = 2;
      _say('轮到家长啦！黑棋刚下了一手，白棋加油～', WqPandaMood.happy, speakIt: false);
      setState(() {});
    }
  }

  void _parentMove(int i) {
    _history.add(_game.clone());
    final r = _game.tryPlay(i, 2);
    if (!r.ok) {
      _history.removeLast();
      WqSfx.oops();
      if (r.reason == 'ko') ToastUtils.showInfo('打劫：刚被提的位置，要隔一手才能提回来');
      if (r.reason == 'suicide') ToastUtils.showInfo('禁入点：这里没有气，棋子站不住');
      return;
    }
    WqSfx.stone();
    HapticFeedback.lightImpact();
    _replayMoves.add((color: 2, point: i));
    if (r.captured.isNotEmpty) {
      WqSfx.capture();
      _boardCtrl.flyCaptures(r.captured, 1);
      if (_game.capWhite >= _winCaptures) return _endGame('lose');
    }
    _updateDanger();
    _turn = 1;
    _say('轮到你啦！', WqPandaMood.happy, speakIt: false);
    setState(() {});
  }

  // ================= AI（棋棋） =================

  void _aiTurn() {
    _busy = true;
    // 关怀提醒：孩子的棋被打吃
    int? danger;
    final seen = <int>{};
    for (var j = 0; j < _game.n * _game.n; j++) {
      if (_game.s[j] == 1 && !seen.contains(j)) {
        final gg = _game.groupAt(j);
        seen.addAll(gg);
        if (_game.libsOf(gg).length == 1) danger = gg[0];
      }
    }
    final remind = _svc.remindOn.value;
    if (danger != null && !_reminded.contains(danger) && remind) {
      _reminded.add(danger);
      _ownAtariBefore = danger;
      _say('咦？你的黑士兵好像只剩 1 口气啦……要不要先帮它找个逃跑的路？', WqPandaMood.think,
          speakIt: true);
    }
    _aiTimer = Timer(Duration(milliseconds: danger != null ? 1400 : 150), () {
      if (!mounted || _over) return;
      _say('棋棋想一下……', WqPandaMood.think, speakIt: false);
      _aiTimer = Timer(Duration(milliseconds: 700 + math.Random().nextInt(600)), () {
        if (!mounted || _over) return;
        final mv = WqAi.pickMove(_game, 2, _svc.aiSkill.value);
        if (mv == null) return _endGame('review');
        final r = _game.tryPlay(mv, 2);
        WqSfx.stone();
        final aiIdx = _replayMoves.length;
        if (r.ok) {
          _replayMoves.add((color: 2, point: mv));
        }
        if (r.ok && r.captured.isNotEmpty) {
          WqSfx.capture();
          _boardCtrl.flyCaptures(r.captured, 1);
          _improvement ??= '有一手棋你的士兵被白棋提走了——下次落子前，先数一数自己还有几口气。';
          _replayNotes[aiIdx] = '棋棋下了橙色圈这个点，堵住了你最后的气——${r.captured.length} 颗黑棋被提走了';
          _replayMarks[aiIdx] = mv;
          _showCaptureExplanation(
            captured: r.captured,
            capturedColor: 1,
            movePoint: mv,
            moverColor: 2,
          );
          if (_game.capWhite >= _winCaptures) return _endGame('lose');
        } else {
          // 棋棋有没有留下「可提的白子」
          var atari = false;
          final s2 = <int>{};
          for (var j = 0; j < _game.n * _game.n; j++) {
            if (_game.s[j] == 2 && !s2.contains(j)) {
              final gg = _game.groupAt(j);
              s2.addAll(gg);
              if (_game.libsOf(gg).length == 1) atari = true;
            }
          }
          _pendingCapture = atari;
        }
        _updateDanger();
        if (_game.capBlack >= _winCaptures) return _endGame('win');
        if (_game.capWhite >= _winCaptures) return _endGame('lose');
        if (_game.stoneCount() >= _maxStones) return _endGame('review');
        _busy = false;
        if (r.ok && r.captured.isEmpty) {
          if (math.Random().nextDouble() < 0.38) {
            _say(_encouragements[math.Random().nextInt(_encouragements.length)],
                WqPandaMood.happy, speakIt: false);
          } else {
            _say('轮到你啦！', WqPandaMood.happy, speakIt: false);
          }
        }
        setState(() {});
      });
    });
    setState(() {});
  }

  static const List<String> _encouragements = [
    '稳稳的一步！',
    '嗯嗯，棋棋看着呢。',
    '这步棋有股安静的力气～',
    '唔，白棋得小心一点了。',
  ];

  /// 找出 [color] 方所有只剩一口气的棋组，返回它们的最后一口气集合
  Set<int> _atariLibsOf(int color) {
    final libs = <int>{};
    final seen = <int>{};
    for (var j = 0; j < _game.n * _game.n; j++) {
      if (_game.s[j] == color && !seen.contains(j)) {
        final gg = _game.groupAt(j);
        seen.addAll(gg);
        final lb = _game.libsOf(gg);
        if (lb.length == 1) libs.addAll(lb);
      }
    }
    return libs;
  }

  /// 落子后刷新「被打吃」警示小灯（孩子的棋快没气时点亮，帮初学者看见危险）
  void _updateDanger() {
    _dangerLibs = _atariLibsOf(1);
    if (mounted) setState(() {});
  }

  /// 提子现场讲解：被提的棋子以半透明残影重现、落子点闪烁，
  /// 棋棋用一句话解释「为什么被提」。孩子落子或 2.4 秒后自动消散。
  void _showCaptureExplanation({
    required List<int> captured,
    required int capturedColor,
    required int movePoint,
    required int moverColor,
  }) {
    _explainTimer?.cancel();
    final who = moverColor == 1 ? '你' : '棋棋';
    final n = captured.length;
    final String text;
    if (capturedColor == 1) {
      text = '$who下了最后一口气那个点——你的 $n 颗黑棋没有气了，就被提走啦。'
          '下次落子前，先数一数自己的气哦！';
    } else {
      text = n > 1
          ? '一手堵住最后一口气，$n 颗白棋一起被提走，这就是「双打」的力量！'
          : '把白棋的最后一口气堵住，它就被提走啦！';
    }
    _explainGhosts = {for (final pt in captured) pt: capturedColor};
    _blink = {movePoint};
    _mood = capturedColor == 1 ? WqPandaMood.think : WqPandaMood.cheer;
    _bubbleText = text;
    _svc.speak(text);
    setState(() {});
    _explainTimer = Timer(const Duration(milliseconds: 2400), () {
      if (!mounted) return;
      setState(() {
        _explainGhosts = {};
        if (_blink.isNotEmpty) _blink = {};
      });
    });
  }

  // ================= 求助（三层引导） =================

  void _useHelp() {
    if (_over || _busy) return;
    if (_helpLeft <= 0) {
      WqSfx.oops();
      ToastUtils.showInfo('这局的求助机会用完啦，再下一局就有哦～');
      return;
    }
    final t = WqAi.hintTarget(_game, 1);
    final key = t == null ? 'none' : '${t.type}${t.pt}';
    if (key != _helpKey) {
      _helpStage = 0;
      _helpKey = key;
    }
    final stage = _helpStage;
    _helpLeft--;
    _clearMarks();
    if (t == null) {
      _say('嗯……现在局面很安稳，把棋下在棋棋的子旁边，慢慢把它养大！', WqPandaMood.think);
      _helpStage = 0;
      return;
    }
    switch (stage) {
      case 0: // L1 鼓励 + 方向微光
        _say(
          t.type == 'capture'
              ? '差一点点！看棋盘上，白棋有个小士兵快没气了——找找它的气在哪里？'
              : '别急！你的士兵被包围了，它也想呼吸——帮它找一个能多口气的地方吧～',
          WqPandaMood.think,
          speakIt: true,
        );
        setState(() => _glowCenter = t.grp[t.grp.length ~/ 2]);
        break;
      case 1: // L2 明确提示：闪烁候选点
        _say(
          t.type == 'capture'
              ? '它只剩最后一口气啦！点这个闪光的交叉点试试？'
              : '点这个闪光的点，你的士兵就能呼吸更多口气啦！',
          WqPandaMood.think,
          speakIt: true,
        );
        setState(() => _blink = {t.pt});
        break;
      default: // L3 动画演示
        _say('看棋棋变魔法——', WqPandaMood.cheer, speakIt: true);
        setState(() => _blink = {t.pt});
        WqSfx.stone();
        _demoGhost(t.pt);
        break;
    }
    _helpStage = math.min(3, _helpStage + 1);
  }

  int? _ghostStone;

  void _demoGhost(int pt) {
    setState(() => _ghostStone = pt);
    _aiTimer = Timer(const Duration(milliseconds: 1100), () {
      if (!mounted) return;
      setState(() {
        _ghostStone = null;
        _blink = {};
      });
      _say('魔法收回啦！现在轮到你，自己把它变出来吧！', WqPandaMood.happy, speakIt: true);
    });
  }

  void _blinkTemp(int i) {
    setState(() => _blink = {i});
    _aiTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _blink = {});
    });
  }

  void _clearMarks() {
    _blink = {};
    _glowCenter = null;
  }

  // ================= 悔棋 / 结束 =================

  Future<void> _confirmRestart() async {
    if (_history.isEmpty && !_over) {
      _resetGame(); // 还没落子，直接重开
      return;
    }
    final ok = await _confirm(
      title: '要重新开始吗？',
      body: '这盘棋的进度会清空，复盘卡也不会生成哦。',
      okText: '重新开始',
      cancelText: '继续下',
    );
    if (!ok) return;
    _resetGame();
  }

  Future<void> _undo() async {
    if (_over) return;
    if (_history.isEmpty) {
      ToastUtils.showInfo('还没有历史棋步哦');
      return;
    }
    final ok = await _confirm(
      title: '真的要悔棋吗？',
      body: '棋棋觉得这步棋还有救哦～再想一下，或者悔一步重新想想也可以！',
      okText: '悔一步',
      cancelText: '不下啦',
    );
    if (!ok) return;
    _aiTimer?.cancel();
    _game.restoreFrom(_history.removeLast());
    if (!_isAi) {
      // 家长陪下：孩子执黑先行，一直回退到「轮到孩子」的偶数手局面
      while (_history.isNotEmpty && _movesPlayed.isOdd) {
        _game.restoreFrom(_history.removeLast());
      }
      _turn = 1;
    }
    _busy = false;
    _helpStage = 0;
    _clearMarks();
    _say('好，悔一步。棋棋再给你一次机会想清楚哦——这步棋一定还有更好的下法！',
        WqPandaMood.think,
        speakIt: true);
    setState(() {});
  }

  /// 黑先白后：盘面手数（子数+提子数）为奇数说明最后落子的是黑方。
  int get _movesPlayed => _game.stoneCount() + _game.capBlack + _game.capWhite;

  Future<bool> _confirm({
    required String title,
    required String body,
    required String okText,
    String cancelText = '再想想',
  }) async {
    final res = await Get.dialog<bool>(
      Dialog(
        backgroundColor: WqTheme.cream,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.r)),
        child: Padding(
          padding: EdgeInsets.all(20.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const WqPanda(mood: WqPandaMood.think, size: 64),
              SizedBox(height: 10.h),
              Text(
                title,
                style: TextStyle(
                    fontSize: 17.sp, fontWeight: FontWeight.w800, color: WqTheme.ink),
              ),
              SizedBox(height: 6.h),
              Text(
                body,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13.sp, fontWeight: FontWeight.w600, color: WqTheme.inkSoft),
              ),
              SizedBox(height: 16.h),
              Row(
                children: [
                  Expanded(
                    child: WqGhostButton(
                      text: '再想想',
                      onTap: () => Get.back<bool>(result: false),
                    ),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: WqPrimaryButton(
                      text: okText,
                      onTap: () => Get.back<bool>(result: true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      barrierDismissible: false,
    );
    return res ?? false;
  }

  void _endGame(String result) {
    if (_over) return;
    _over = true;
    _busy = false;
    _aiTimer?.cancel();
    final win = result == 'win' ||
        (result == 'review' && _game.capBlack >= _game.capWhite);
    _svc.recordGame(result: result == 'win' ? 'win' : (result == 'lose' ? 'lose' : 'draw'));
    if (_replayMoves.isNotEmpty) {
      _svc.saveLastGame(_replayMoves, _replayNotes, _replayMarks);
    }
    if (win) {
      WqSfx.star();
    } else {
      WqSfx.pop();
    }
    final ms = List<String>.from(_milestones.take(3));
    final defaults = [
      '敢和 AI 陪练下满一整局，勇气满分！',
      '每一步都认真思考了，棋棋都看在眼里～',
      '今天的你比昨天更会数气了！',
    ];
    var di = 0;
    while (ms.length < 3) {
      ms.add(defaults[di++ % defaults.length]);
    }
    final imp = _improvement ?? '下次可以试试「下完一步就数一数气」，棋棋保证你会更强！';
    final title = result == 'win'
        ? '你赢啦！'
        : win
            ? '你领先！'
            : (_isAi ? '棋棋险胜！' : '家长险胜！');
    final sub = result == 'win'
        ? '$_winCaptures 颗提子 · 你把白棋的呼吸全堵住了'
        : result == 'lose'
            ? '${_game.capWhite} 比 ${_game.capBlack} · 差一点点就追上了'
            : '本局结束 · 黑 $_game.capBlack 比 白 ${_game.capWhite}';
    _say(
      win
          ? '赢棋啦！你的棋力又变强了一点点哦～'
          : (_isAi ? '别难过，棋棋赢得好险！你已经找到很多好棋了。' : '没关系，下一局赢回来！你已经下出很多好棋了。'),
      win ? WqPandaMood.cheer : WqPandaMood.sad,
      speakIt: true,
    );
    Get.dialog(
      Dialog(
        backgroundColor: WqTheme.cream,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28.r)),
        insetPadding: EdgeInsets.all(22.w),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(18.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              WqPanda(mood: win ? WqPandaMood.cheer : WqPandaMood.sad, size: 84),
              SizedBox(height: 6.h),
              Text(
                title,
                style: TextStyle(
                    fontSize: 22.sp, fontWeight: FontWeight.w900, color: WqTheme.ink),
              ),
              Text(
                sub,
                style: TextStyle(
                    fontSize: 13.sp, fontWeight: FontWeight.w700, color: WqTheme.inkSoft),
              ),
              SizedBox(height: 8.h),
              WqStarsRow(stars: win ? 3 : 2, pop: true, size: 26),
              SizedBox(height: 10.h),
              WqChip(text: '✦ 3 + 1 复盘卡 ✦'),
              SizedBox(height: 10.h),
              for (var k = 0; k < ms.length; k++)
                _reviewCard(
                  rank: '${k + 1}',
                  text: ms[k],
                  sub: '今天的一手好棋，继续保持！',
                ),
              _reviewCard(
                rank: '★',
                text: imp,
                sub: '已放进藏宝箱，明天复习一下会更强哦',
                improve: true,
              ),
              SizedBox(height: 14.h),
              if (_replayMoves.isNotEmpty)
                WqGhostButton(
                  text: '重看棋局 · 学一手',
                  height: 42.h,
                  fontSize: 13.5.sp,
                  onTap: () {
                    Get.back(); // 关闭结算，留在对局页进入回放
                    Get.to(() => WeiqiReplayPage(
                          moves: _replayMoves,
                          notes: _replayNotes,
                          marks: _replayMarks,
                        ));
                  },
                ),
              if (_replayMoves.isNotEmpty) SizedBox(height: 8.h),
              WqPrimaryButton(
                text: win ? '再来一局！' : '我们再战一局！',
                onTap: () {
                  Get.back();
                  _resetGame();
                },
              ),
              SizedBox(height: 10.h),
              WqGhostButton(
                text: '回小岛休息一下',
                onTap: () {
                  Get.back(); // 关闭结算
                  Get.back(); // 退出对局
                  if (widget.exitToHome) {
                    Get.back(); // 从课程结算进入：连课程页一起退出，回到课程地图
                  }
                },
              ),
            ],
          ),
        ),
      ),
      barrierDismissible: false,
    );
  }

  Widget _reviewCard({
    required String rank,
    required String text,
    required String sub,
    bool improve = false,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: 9.h),
      padding: EdgeInsets.all(11.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: const [
          BoxShadow(color: Color(0x14233240), blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30.w,
            height: 30.w,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: improve ? WqTheme.sunSoft : WqTheme.greenSoft,
            ),
            child: Center(
              child: Text(
                rank,
                style: TextStyle(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w900,
                  color: improve ? WqTheme.sunDeep : WqTheme.greenDeep,
                ),
              ),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 13.5.sp,
                    fontWeight: FontWeight.w800,
                    height: 1.5,
                    color: WqTheme.ink,
                  ),
                ),
                Text(
                  sub,
                  style: TextStyle(
                    fontSize: 11.5.sp,
                    fontWeight: FontWeight.w600,
                    color: WqTheme.inkSoft,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ================= UI =================

  Future<bool> _confirmExit() async {
    if (_over || _history.isEmpty) return true;
    final stay = await _confirm(
      title: '这盘棋还没下完哦',
      body: '现在离开的话，这局就不会有复盘卡啦。真的要回去吗？',
      okText: '继续下棋',
      cancelText: '回去休息',
    );
    return !stay;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final exit = await _confirmExit();
        if (exit && mounted) {
          _svc.stopSpeak();
          Get.back();
        }
      },
      child: Scaffold(
        backgroundColor: WqTheme.cream,
        body: SafeArea(
          child: Column(
            children: [
              // 头部
              Padding(
                padding: EdgeInsets.fromLTRB(14.w, 10.h, 14.w, 2.h),
                child: Row(
                  children: [
                    WqIconButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        size: 40,
                        onTap: () async {
                          final exit = await _confirmExit();
                          if (exit && mounted) {
                            _svc.stopSpeak();
                            Get.back();
                          }
                        }),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 10.w, vertical: 7.h),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: const [
                            BoxShadow(
                                color: Color(0x14233240),
                                blurRadius: 6,
                                offset: Offset(0, 2)),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 8.w, vertical: 3.h),
                            decoration: BoxDecoration(
                              color: _turn == 1 || _isAi
                                  ? const Color(0xFF2E2E38)
                                  : WqTheme.creamDeep,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              _isAi
                                  ? '你 · 执黑'
                                  : (_turn == 1 ? '孩子 · 执黑' : '家长 · 执白'),
                              style: TextStyle(
                                fontSize: 11.5.sp,
                                fontWeight: FontWeight.w900,
                                color: _turn == 1 || _isAi
                                    ? Colors.white
                                    : WqTheme.ink,
                              ),
                            ),
                          ),
                          SizedBox(width: 8.w),
                            Flexible(
                              child: Text(
                                '先提 $_winCaptures 颗获胜',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5.sp,
                                  fontWeight: FontWeight.w800,
                                  color: WqTheme.inkSoft,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Obx(() => WqIconButton(
                          icon: _svc.atariLightsOn.value
                              ? Icons.lightbulb_rounded
                              : Icons.lightbulb_outline_rounded,
                          size: 40,
                          color: _svc.atariLightsOn.value
                              ? WqTheme.sunDeep
                              : WqTheme.inkFaint,
                          onTap: () {
                            _svc.atariLightsOn.value =
                                !_svc.atariLightsOn.value;
                            _updateDanger();
                          },
                        )),
                    SizedBox(width: 6.w),
                    WqIconButton(
                      icon: Icons.replay_rounded,
                      size: 40,
                      onTap: _confirmRestart,
                    ),
                    SizedBox(width: 6.w),
                    WqIconButton(
                      icon: WqSfx.enabled
                          ? Icons.volume_up_rounded
                          : Icons.volume_off_rounded,
                      size: 40,
                      onTap: () => setState(() => WqSfx.enabled = !WqSfx.enabled),
                    ),
                  ],
                ),
              ),
              // 棋棋气泡区
              Flexible(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(14.w, 6.h, 14.w, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      WqPanda(mood: _mood, size: 56),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: WqBubble(
                          text: _bubbleText,
                          speaking: true,
                          mood: _mood,
                          maxLines: 3,
                          tail: true,
                          onReplay: () {
                            WqSfx.pop();
                            _svc.speak(_bubbleText);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 棋盘
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(14.w, 4.h, 14.w, 8.h),
                  child: Center(
                    child: WeiqiBoardView(
                      controller: _boardCtrl,
                      stones: _game.s,
                      lastMove: _game.last,
                      blinkPoints: _blink,
                      glowCenter: _glowCenter,
                      glowRadius: 22,
                      ghostStone: _ghostStone,
                      ghostColor: 1,
                      ghostStones: _explainGhosts,
                      breathePoints: _isAi &&
                              _svc.remindOn.value &&
                              _svc.atariLightsOn.value
                          ? _dangerLibs
                          : const {},
                      breatheWarn: true,
                      capByBlack: _game.capBlack,
                      capByWhite: _game.capWhite,
                      onPointTap: _onTap,
                    ),
                  ),
                ),
              ),
              // 底部操作
              Padding(
                padding: EdgeInsets.fromLTRB(14.w, 4.h, 14.w, 10.h),
                child: Row(
                  children: [
                    if (_isAi)
                      _actionButton(
                        emoji: '💡',
                        label: '问棋棋',
                        sub: '还剩 $_helpLeft 次',
                        care: true,
                        onTap: _useHelp,
                      )
                    else
                      _actionButton(
                        emoji: '👋',
                        label: '换人',
                        sub: '轮到${_turn == 1 ? '家长' : '孩子'}',
                        care: false,
                        onTap: null,
                      ),
                    SizedBox(width: 10.w),
                    _actionButton(
                      emoji: '↩',
                      label: '悔棋',
                      sub: '和棋棋商量一下',
                      care: false,
                      onTap: _undo,
                    ),
                    SizedBox(width: 10.w),
                    _actionButton(
                      emoji: '✓',
                      label: '结束',
                      sub: '生成复盘卡',
                      care: false,
                      onTap: () => _endGame('review'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionButton({
    required String emoji,
    required String label,
    required String sub,
    required bool care,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: Material(
        color: care ? WqTheme.sunSoft : Colors.white,
        borderRadius: BorderRadius.circular(18.r),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18.r),
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 7.h),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18.r),
              border: Border.all(
                color: care
                    ? WqTheme.sunDeep.withValues(alpha: 0.25)
                    : const Color(0x0F23324D),
              ),
            ),
            child: Column(
              children: [
                Text(
                  emoji,
                  style: TextStyle(fontSize: 16.sp),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5.sp,
                    fontWeight: FontWeight.w800,
                    color: WqTheme.ink,
                  ),
                ),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5.sp,
                    fontWeight: FontWeight.w600,
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
}
