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
import 'weiqi_service.dart';
import 'weiqi_sfx.dart';
import 'weiqi_theme.dart';
import 'weiqi_widgets.dart';

/// 商业级死活/手筋题闯关页：
/// 支持专题分类筛选（全部/吃子/逃子连接/手筋/死活）、题目总览跳题、
/// AI 自动应对的多步连续手筋题、语音读题、三层提示、错题藏宝箱。
class WeiqiPuzzlePage extends StatefulWidget {
  const WeiqiPuzzlePage({super.key});

  @override
  State<WeiqiPuzzlePage> createState() => _WeiqiPuzzlePageState();
}

class _WeiqiPuzzlePageState extends State<WeiqiPuzzlePage> {
  late final WeiqiService _svc;
  int _n = 0; // 在 wqPuzzles 全局列表中的索引
  String _selectedCategory = 'all'; // 'all' | 'capture' | 'escape' | 'tesuji' | 'life'
  late WqGame _game;
  bool _solved = false;
  int _stepPhase = 0; // 0=第1手, 1=多步题等待第2手
  bool _aiReplying = false;
  int _hints = 0;
  Set<int> _blink = {};
  int? _glowCenter;
  int? _ghost;
  int _ghostColor = 1;
  String _customBubble = '';
  Timer? _timer;
  final WqBoardController _boardCtrl = WqBoardController();

  WqPuzzle get pz => wqPuzzles[_n];

  /// 当前分类下的题目全局索引列表
  List<int> get _filteredIndices {
    if (_selectedCategory == 'all') {
      return List.generate(wqPuzzles.length, (i) => i);
    }
    final list = <int>[];
    for (var i = 0; i < wqPuzzles.length; i++) {
      if (wqPuzzles[i].category == _selectedCategory) list.add(i);
    }
    return list.isEmpty ? [0] : list;
  }

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

  void _selectCategory(String cat) {
    if (_selectedCategory == cat) return;
    WqSfx.pop();
    _selectedCategory = cat;
    final indices = _filteredIndices;
    _loadPuzzle(indices.first, speak: true);
  }

  void _loadPuzzle(int index, {bool speak = false}) {
    _timer?.cancel();
    _n = index.clamp(0, wqPuzzles.length - 1);
    _game = WqGame();
    for (final op in pz.setup) {
      if (!op.reset) _game.tryPlay(op.point, op.color!);
    }
    _solved = false;
    _stepPhase = 0;
    _aiReplying = false;
    _hints = 0;
    _blink = {};
    _glowCenter = null;
    _ghost = null;
    _customBubble = '';
    setState(() {});
    if (speak) _svc.speak(pz.voice);
  }

  void _onTap(int i) {
    if (_solved || _aiReplying) return;
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

    // 多步连续应对题的第 2 手判定
    if (pz.isMultiStep && _stepPhase == 1) {
      final snap = _game.clone();
      final r = _game.tryPlay(i, pz.playerColor);
      if (!r.ok || i != pz.secondAnswerPoint) {
        _game.restoreFrom(snap);
        WqSfx.oops();
        _svc.recordPuzzle(pz.id, false);
        ToastUtils.showInfo('差一点！再看看白棋最后一口气在哪里？');
        setState(() {});
        return;
      }
      _completePuzzle(r);
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
      // 如果是多步连续应对题：先触发 AI 抵抗手，等待玩家下第 2 手
      if (pz.isMultiStep && _stepPhase == 0) {
        WqSfx.stone();
        HapticFeedback.lightImpact();
        _aiReplying = true;
        _blink = {};
        _glowCenter = null;
        setState(() {});
        _timer = Timer(const Duration(milliseconds: 460), () {
          if (!mounted) return;
          final opp = 3 - pz.playerColor;
          _game.tryPlay(pz.aiReplyPoint!, opp);
          WqSfx.stone();
          _stepPhase = 1;
          _aiReplying = false;
          _customBubble =
              pz.step1Text ?? '好棋！棋棋拼命往外逃了一步——再追一手把它彻底拿下！';
          setState(() {});
          _svc.speak(_customBubble);
        });
        return;
      }
      _completePuzzle(r);
    } else {
      _game.restoreFrom(snap);
      WqSfx.oops();
      _svc.recordPuzzle(pz.id, false);
      ToastUtils.showInfo('再想一想，先数一数气！');
      setState(() {});
    }
  }

  void _completePuzzle(WqPlayResult r) {
    _solved = true;
    _customBubble = '';
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
  }

  void _skip() {
    WqSfx.pop();
    _svc.recordPuzzle(pz.id, false);
    ToastUtils.showInfo('没关系，这题先进藏宝箱，下次再来！');
    _next();
  }

  void _next() {
    final indices = _filteredIndices;
    final pos = indices.indexOf(_n);
    if (pos >= 0 && pos < indices.length - 1) {
      _loadPuzzle(indices[pos + 1], speak: true);
    } else if (_n < wqPuzzles.length - 1) {
      _loadPuzzle(_n + 1, speak: true);
    } else {
      WqSfx.star();
      ToastUtils.showInfo('本组题目全部完成！真厉害！');
      Get.back();
    }
  }

  void _useHint() {
    if (_solved || _hints >= 3) return;
    final stage = _hints;
    final targetPt = (pz.isMultiStep && _stepPhase == 1)
        ? pz.secondAnswerPoint!
        : pz.answerPoint;
    _blink = {};
    _glowCenter = null;
    _ghost = null;
    if (stage == 0) {
      setState(() => _glowCenter = pz.zoneCenter);
      _svc.speak(pz.hints[0]);
      WqSfx.pop();
    } else if (stage == 1) {
      setState(() => _blink = {targetPt});
      _svc.speak(pz.hints[1]);
      WqSfx.pop();
    } else {
      _svc.speak(pz.hints[2]);
      setState(() {
        _blink = {targetPt};
        _ghost = targetPt;
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

  /// 打开题目总览选择器
  void _openPuzzlePicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(ctx).padding.bottom + 12,
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: 330,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.65,
              ),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: WqTheme.cream,
                borderRadius: BorderRadius.circular(24),
                border: WqTheme.border(),
                boxShadow: WqTheme.paperShadow(h: 8.0),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '🧩 题库总览（共 20 题）',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: WqTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: GridView.builder(
                      shrinkWrap: true,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 1.15,
                      ),
                      itemCount: wqPuzzles.length,
                      itemBuilder: (ctx, idx) {
                        final p = wqPuzzles[idx];
                        final solved = _svc.solvedPuzzles.contains(p.id);
                        final current = idx == _n;
                        return GestureDetector(
                          onTap: () {
                            Navigator.of(ctx).pop();
                            _loadPuzzle(idx, speak: true);
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: current
                                  ? WqTheme.sun
                                  : (solved ? WqTheme.greenSoft : Colors.white),
                              borderRadius: BorderRadius.circular(12),
                              border: WqTheme.border(),
                              boxShadow: WqTheme.paperShadow(h: 8.0),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '第${idx + 1}题',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    color: WqTheme.ink,
                                  ),
                                ),
                                Text(
                                  solved ? '✓ 已通关' : (p.isMultiStep ? '2步题' : '挑战'),
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    color: solved
                                        ? WqTheme.greenDeep
                                        : WqTheme.inkSoft,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 打开错题藏宝箱
  void _openTreasureBox() {
    final wrong = _svc.wrongPuzzles.toList();
    if (wrong.isEmpty) {
      WqSfx.pop();
      ToastUtils.showInfo('藏宝箱空空如也，快去闯关吧！');
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(ctx).padding.bottom + 12,
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: 320,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.6,
              ),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: WqTheme.cream,
                borderRadius: BorderRadius.circular(24),
                border: WqTheme.border(),
                boxShadow: WqTheme.paperShadow(h: 8.0),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '🎁 错题藏宝箱',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: WqTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '点一道题，马上再挑战一次！',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: WqTheme.inkSoft,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: wrong.length,
                      itemBuilder: (ctx, k) {
                        final idx =
                            wqPuzzles.indexWhere((p) => p.id == wrong[k]);
                        if (idx < 0) return const SizedBox.shrink();
                        final p = wqPuzzles[idx];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GestureDetector(
                            onTap: () {
                              Navigator.of(ctx).pop();
                              _loadPuzzle(idx, speak: true);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border:
                                    WqTheme.border(),
                                boxShadow: WqTheme.paperShadow(h: 8.0),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: WqTheme.sun,
                                      shape: BoxShape.circle,
                                      border: WqTheme.border(),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      '${idx + 1}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                        color: WqTheme.ink,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      p.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w900,
                                        color: WqTheme.ink,
                                      ),
                                    ),
                                  ),
                                  WqChip(text: p.tag),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.chevron_right_rounded,
                                      size: 20, color: WqTheme.ink),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const categories = [
      (id: 'all', label: '全部'),
      (id: 'capture', label: '🎯 吃子'),
      (id: 'escape', label: '🏃 逃子连接'),
      (id: 'tesuji', label: '⚡ 手筋'),
      (id: 'life', label: '🏠 死活对杀'),
    ];

    return Scaffold(
      backgroundColor: WqTheme.cream,
      body: SafeArea(
        child: Column(
          children: [
            // 头部
            Padding(
              padding: EdgeInsets.fromLTRB(14.w, 8.h, 14.w, 0),
              child: Row(
                children: [
                  WqIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    size: 40,
                    onTap: () {
                      _svc.stopSpeak();
                      Get.back();
                    },
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '死活与手筋特训',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w900,
                            color: WqTheme.ink,
                          ),
                        ),
                        Text(
                          '${pz.title} · ${pz.isMultiStep ? "连续2步应对" : "每日 5-10 题"}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w700,
                            color: WqTheme.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _openPuzzlePicker,
                    child: WqChip.sun(
                      text: '第 ${_n + 1} / ${wqPuzzles.length} 题 ▾',
                    ),
                  ),
                ],
              ),
            ),

            // 专题分类筛选条
            Padding(
              padding: EdgeInsets.fromLTRB(14.w, 6.h, 14.w, 4.h),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: categories.map((cat) {
                    final on = _selectedCategory == cat.id;
                    return Padding(
                      padding: EdgeInsets.only(right: 6.w),
                      child: GestureDetector(
                        onTap: () => _selectCategory(cat.id),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 10.w, vertical: 4.h),
                          decoration: BoxDecoration(
                            color: on ? WqTheme.pink : Colors.white,
                            borderRadius: BorderRadius.circular(999),
                            border: WqTheme.border(),
                            boxShadow: on
                                ? WqTheme.paperShadow(h: 8.0)
                                : const [],
                          ),
                          child: Text(
                            cat.label,
                            style: TextStyle(
                              fontSize: 11.sp,
                              fontWeight: FontWeight.w900,
                              color: WqTheme.ink,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            // 棋棋读题卡片（恒定高度槽位：无论未解/已解/长短提示语，高度 100% 锁定，棋盘不跳动）
            Flexible(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 14.w),
                child: LayoutBuilder(builder: (context, constraints) {
                  final cardH = constraints.hasBoundedHeight
                      ? (constraints.maxHeight < 76.0
                          ? constraints.maxHeight
                          : 76.0)
                      : 76.0;
                  return SizedBox(
                    height: cardH,
                    child: WqCard(
                      padding:
                          EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          WqPanda(
                            mood: _solved
                                ? WqPandaMood.cheer
                                : WqPandaMood.happy,
                            size: 38,
                          ),
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
                                    SizedBox(width: 6.w),
                                    WqChip(text: pz.tag),
                                    const Spacer(),
                                    GestureDetector(
                                      onTap: () => _svc.speak(
                                        _solved
                                            ? pz.okText
                                            : (_customBubble.isNotEmpty
                                                ? _customBubble
                                                : pz.voice),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.volume_up_rounded,
                                              size: 13, color: WqTheme.ink),
                                          SizedBox(width: 3.w),
                                          Text(
                                            '再听一遍',
                                            style: TextStyle(
                                              fontSize: 10.sp,
                                              fontWeight: FontWeight.w900,
                                              color: WqTheme.ink,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 2.h),
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      _solved
                                          ? pz.okText
                                          : (_customBubble.isNotEmpty
                                              ? _customBubble
                                              : pz.voice),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12.sp,
                                        fontWeight: FontWeight.w800,
                                        height: 1.32,
                                        color: WqTheme.ink,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
            SizedBox(height: 4.h),

            // 棋盘
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(14.w, 2.h, 14.w, 6.h),
                child: Obx(() => WeiqiBoardView(
                      controller: _boardCtrl,
                      stones: _game.s,
                      lastMove: _game.last,
                      showCoords: _svc.showCoords.value,
                      blinkPoints: _blink,
                      glowCenter: _glowCenter,
                      glowRadius: 26,
                      ghostStone: _ghost,
                      ghostColor: _ghostColor,
                      capByBlack: _game.capBlack,
                      capByWhite: _game.capWhite,
                      onPointTap: _solved ? null : _onTap,
                    )),
              ),
            ),

            // 操作按钮行（恒定高度 42.h，切换未解/已解时棋盘不跳动）
            Padding(
              padding: EdgeInsets.fromLTRB(14.w, 4.h, 14.w, 4.h),
              child: SizedBox(
                height: 42.h,
                child: Row(
                  children: [
                    if (_solved)
                      Expanded(
                        child: WqPrimaryButton(
                          text: _n < wqPuzzles.length - 1 ? '下一题 ›' : '完成闯关 ✦',
                          height: 42.h,
                          fontSize: 15.sp,
                          color: WqTheme.sun,
                          onTap: _next,
                        ),
                      )
                    else ...[
                      Expanded(
                        child: WqGhostButton(
                          text:
                              '💡 问棋棋（${3 - _hints > 0 ? 3 - _hints : 0} 层提示）',
                          height: 42.h,
                          fontSize: 13.sp,
                          onTap: _useHint,
                        ),
                      ),
                      SizedBox(width: 8.w),
                      WqIconButton(
                        icon: Icons.skip_next_rounded,
                        size: 42,
                        bgColor: WqTheme.sunSoft,
                        onTap: _skip,
                      ),
                      SizedBox(width: 8.w),
                      WqIconButton(
                        icon: Icons.replay_rounded,
                        size: 42,
                        onTap: () => _loadPuzzle(_n, speak: false),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(14.w, 2.h, 14.w, 10.h),
              child: GestureDetector(
                onTap: _openTreasureBox,
                child: WqCard(
                  padding:
                      EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                  child: Row(
                    children: [
                      Container(
                        width: 34.w,
                        height: 34.w,
                        decoration: BoxDecoration(
                          color: WqTheme.sun,
                          borderRadius: BorderRadius.circular(10.r),
                          border: WqTheme.border(),
                        ),
                        child: const Center(
                          child: Text('🎁', style: TextStyle(fontSize: 17)),
                        ),
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
                                fontWeight: FontWeight.w900,
                                color: WqTheme.ink,
                              ),
                            ),
                            Text(
                              '点开复习做错的题，答对就移出宝箱',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5.sp,
                                fontWeight: FontWeight.w700,
                                color: WqTheme.inkSoft,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Obx(() =>
                          WqChip.coral(text: '${_svc.wrongPuzzles.length} 道')),
                      SizedBox(width: 4.w),
                      const Icon(Icons.chevron_right_rounded,
                          size: 20, color: WqTheme.ink),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
