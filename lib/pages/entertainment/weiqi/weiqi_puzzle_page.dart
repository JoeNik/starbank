import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../../widgets/toast_utils.dart';
import 'weiqi_board.dart';
import 'weiqi_data.dart';
import 'weiqi_engine.dart';
import 'weiqi_panda.dart';
import 'weiqi_sfx.dart';
import 'weiqi_service.dart';
import 'weiqi_theme.dart';
import 'weiqi_widgets.dart';

/// 死活/吃子题闯关：语音读题、三层提示、错题进藏宝箱（无惩罚：没有红叉）。
class WeiqiPuzzlePage extends StatefulWidget {
  const WeiqiPuzzlePage({super.key});

  @override
  State<WeiqiPuzzlePage> createState() => _WeiqiPuzzlePageState();
}

class _WeiqiPuzzlePageState extends State<WeiqiPuzzlePage> {
  late final WeiqiService _svc;
  int _n = 0;
  late WqGame _game;
  bool _solved = false;
  int _hints = 0;
  Set<int> _blink = {};
  int? _glowCenter;
  int? _ghost;
  int _ghostColor = 1;
  Timer? _timer;
  final WqBoardController _boardCtrl = WqBoardController();

  WqPuzzle get pz => wqPuzzles[_n];

  @override
  void initState() {
    super.initState();
    _svc = Get.find<WeiqiService>();
    _loadPuzzle(0, speak: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _svc.stopSpeak();
    super.dispose();
  }

  void _loadPuzzle(int index, {bool speak = false}) {
    _n = index;
    _game = WqGame();
    for (final op in pz.setup) {
      if (!op.reset) _game.tryPlay(op.point, op.color!);
    }
    _solved = false;
    _hints = 0;
    _blink = {};
    _glowCenter = null;
    _ghost = null;
    setState(() {});
    if (speak) _svc.speak(pz.voice);
  }

  void _onTap(int i) {
    if (_solved) return;
    if (_game.s[i] != 0) {
      WqSfx.oops();
      ToastUtils.showInfo('这里已经有棋子啦');
      return;
    }
    if (_game.ko == i) {
      WqSfx.oops();
      ToastUtils.showInfo('打劫：这里刚被提过一颗子，要隔一手才能下回来');
      return;
    }
    final snap = _game.clone();
    final r = _game.tryPlay(i, pz.playerColor);
    if (!r.ok) {
      WqSfx.oops();
      _game.restoreFrom(snap);
      ToastUtils.showInfo(r.reason == 'suicide'
          ? '这里没有气，棋子站不住哦——这叫「禁入点」'
          : '这里不能下哦，再想一想！');
      return;
    }
    final done = wqCheckGoal(
      _game,
      pz.goal,
      playerColor: pz.playerColor,
      minCapture: pz.minCapture,
      minLibs: pz.minLibs,
      goalPoint: pz.goalPoint,
      goalPoint2: pz.goalPoint2,
      captured: r.captured,
    );
    if (done) {
      // 先置完成状态并记录，再播庆祝特效（特效异常不影响进度）
      _solved = true;
      _svc.recordPuzzle(pz.id, true);
      setState(() {});
      WqSfx.stone();
      HapticFeedback.lightImpact();
      if (r.captured.isNotEmpty) {
        WqSfx.capture();
        _boardCtrl.flyCaptures(r.captured, 3 - pz.playerColor);
      }
      WqSfx.star();
      WqConfetti.burst(context, count: 30);
      _svc.speak(pz.okText);
      _timer = Timer(const Duration(milliseconds: 1800), _next);
    } else {
      // 不达标：收回这步棋，温柔提示
      _game.restoreFrom(snap);
      WqSfx.oops();
      _svc.recordPuzzle(pz.id, false);
      ToastUtils.showInfo('再想一想，先数一数气！');
      setState(() {});
    }
  }

  void _next() {
    if (_n < wqPuzzles.length - 1) {
      _loadPuzzle(_n + 1, speak: true);
    } else {
      WqSfx.star();
      ToastUtils.showInfo('今天的题目全部完成！真厉害！');
      Get.back();
    }
  }

  void _useHint() {
    if (_solved || _hints >= 3) return;
    final stage = _hints;
    _blink = {};
    _glowCenter = null;
    _ghost = null;
    if (stage == 0) {
      setState(() => _glowCenter = pz.zoneCenter);
      _svc.speak(pz.hints[0]);
      WqSfx.pop();
    } else if (stage == 1) {
      setState(() => _blink = {pz.answerPoint});
      _svc.speak(pz.hints[1]);
      WqSfx.pop();
    } else {
      _svc.speak(pz.hints[2]);
      setState(() {
        _blink = {pz.answerPoint};
        _ghost = pz.answerPoint;
        _ghostColor = pz.playerColor;
      });
      WqSfx.stone();
      _timer = Timer(const Duration(milliseconds: 1100), () {
        if (!mounted) return;
        setState(() => _ghost = null);
        _svc.speak('魔法收回啦，轮到你啦！');
      });
    }
    _hints++;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WqTheme.cream,
      body: SafeArea(
        child: Column(
          children: [
            // 头部
            Padding(
              padding: EdgeInsets.fromLTRB(14.w, 10.h, 14.w, 0),
              child: Row(
                children: [
                  WqIconButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      size: 40,
                      onTap: () {
                        _svc.stopSpeak();
                        Get.back();
                      }),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '吃子竞技场 · 闯关',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w800,
                            color: WqTheme.ink,
                          ),
                        ),
                        Text(
                          '${pz.title} · 每日 5-10 题',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w600,
                            color: WqTheme.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                  WqChip.sun(
                      text: '第 ${_n + 1} / ${wqPuzzles.length} 题'),
                ],
              ),
            ),
            SizedBox(height: 8.h),
            // 棋棋读题
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 14.w),
              child: WqCard(
                padding: EdgeInsets.all(10.w),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    WqPanda(
                        mood: _solved ? WqPandaMood.cheer : WqPandaMood.happy,
                        size: 44),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                _solved ? '棋棋恭喜' : '棋棋读题',
                                style: TextStyle(
                                  fontSize: 11.sp,
                                  fontWeight: FontWeight.w900,
                                  color: WqTheme.greenDeep,
                                ),
                              ),
                              SizedBox(width: 4.w),
                              WqChip(text: pz.tag),
                            ],
                          ),
                          SizedBox(height: 2.h),
                          Text(
                            _solved ? pz.okText : pz.voice,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w700,
                              height: 1.55,
                              color: WqTheme.ink,
                            ),
                          ),
                          if (!_solved) ...[
                            SizedBox(height: 6.h),
                            GestureDetector(
                              onTap: () => _svc.speak(pz.voice),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.volume_up_rounded,
                                      size: 16, color: WqTheme.green),
                                  SizedBox(width: 4.w),
                                  Text(
                                    '再听一遍',
                                    style: TextStyle(
                                      fontSize: 11.sp,
                                      fontWeight: FontWeight.w800,
                                      color: WqTheme.greenDeep,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 10.h),
            // 棋盘
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(14.w, 6.h, 14.w, 8.h),
                child: WeiqiBoardView(
                    controller: _boardCtrl,
                    stones: _game.s,
                    lastMove: _game.last,
                    blinkPoints: _blink,
                    glowCenter: _glowCenter,
                    glowRadius: 26,
                    ghostStone: _ghost,
                    ghostColor: _ghostColor,
                    capByBlack: _game.capBlack,
                    capByWhite: _game.capWhite,
                    onPointTap: _solved ? null : _onTap,
                  ),
                ),
            ),
            // 操作 + 藏宝箱
            Padding(
              padding: EdgeInsets.fromLTRB(14.w, 6.h, 14.w, 4.h),
              child: Row(
                children: [
                  Expanded(
                    child: WqGhostButton(
                      text: '💡 问棋棋（${3 - _hints > 0 ? 3 - _hints : 0} 层提示）',
                      height: 42.h,
                      fontSize: 13.sp,
                      onTap: _useHint,
                    ),
                  ),
                  SizedBox(width: 8.w),
                  WqIconButton(
                    icon: Icons.replay_rounded,
                    size: 42,
                    onTap: () => _loadPuzzle(_n, speak: false),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(14.w, 0, 14.w, 10.h),
              child: WqCard(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                child: Row(
                  children: [
                    Container(
                      width: 36.w,
                      height: 36.w,
                      decoration: BoxDecoration(
                        color: WqTheme.sunSoft,
                        borderRadius: BorderRadius.circular(14.r),
                      ),
                      child: const Center(
                          child: Text('🎁', style: TextStyle(fontSize: 18))),
                    ),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '错题藏宝箱',
                            style: TextStyle(
                              fontSize: 12.5.sp,
                              fontWeight: FontWeight.w800,
                              color: WqTheme.ink,
                            ),
                          ),
                          Text(
                            '做错的题会变成宝箱，下次再来挑战吧',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5.sp,
                              fontWeight: FontWeight.w600,
                              color: WqTheme.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                    WqChip.coral(text: '${_svc.wrongPuzzles.length} 道'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
