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
import 'weiqi_play_page.dart';
import 'weiqi_sfx.dart';
import 'weiqi_service.dart';
import 'weiqi_theme.dart';
import 'weiqi_widgets.dart';

/// 课程步骤讲解页：每一步 = 棋棋的话 + 分步演示 + 动手挑战。
/// 孩子永远掌控节奏：可暂停（不动）、回退（上一步）、重播。
class WeiqiCoursePage extends StatefulWidget {
  final int lessonIndex;

  const WeiqiCoursePage({super.key, required this.lessonIndex});

  @override
  State<WeiqiCoursePage> createState() => _WeiqiCoursePageState();
}

class _WeiqiCoursePageState extends State<WeiqiCoursePage> {
  late final WqLesson lesson;
  late final WeiqiService _svc;

  int _step = 0;
  late WqGame _game;
  WqBoardController boardCtrl = WqBoardController();
  final Set<int> _found = {};
  bool _quizDone = false;
  int _misses = 0;
  int _missHintTurn = 0;
  int? _refusedPoint;
  Timer? _refusedTimer;
  String _extraBubble = '';

  WqStep get step => lesson.steps[_step];

  @override
  void initState() {
    super.initState();
    lesson = wqLessons[widget.lessonIndex];
    _svc = Get.find<WeiqiService>();
    _applyStep(0);
  }

  @override
  void dispose() {
    _refusedTimer?.cancel();
    _svc.stopSpeak();
    super.dispose();
  }

  /// 重放第 0..k 步的演示操作，重建局面（回退也正确）。
  void _applyStep(int k) {
    _step = k;
    _game = WqGame();
    final st = step;
    List<int> capturedNow = [];
    int? refused;
    for (var si = 0; si <= k; si++) {
      final s = lesson.steps[si];
      capturedNow = [];
      for (final op in s.ops) {
        if (op.reset) {
          _game = WqGame();
          continue;
        }
        final r = _game.tryPlay(op.point, op.color!);
        if (r.ok) {
          capturedNow.addAll(r.captured);
        } else if (si == k && op.tryOnly) {
          refused = op.point;
        }
      }
    }
    _found.clear();
    _quizDone = false;
    _extraBubble = '';
    setState(() {});
    // 先语音后特效：即使特效动画出错，讲解也不缺席
    WqSfx.pop();
    _svc.speak(st.bubble);
    if (refused != null) {
      _showRefused(refused);
    } else if (st.captureDemo.isNotEmpty && capturedNow.isNotEmpty) {
      WqSfx.capture();
      boardCtrl.flyCaptures(st.captureDemo, 2);
    }
  }

  void _showRefused(int point) {
    WqSfx.oops();
    _refusedTimer?.cancel();
    setState(() => _refusedPoint = point);
    _refusedTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _refusedPoint = null);
    });
  }

  void _next() {
    final st = step;
    if (st.findQuiz != null && !_quizDone ||
        st.moveQuiz != null && !_quizDone) {
      WqSfx.oops();
      ToastUtils.showInfo('先完成这一步的小任务哦～');
      return;
    }
    if (_step >= lesson.steps.length - 1) {
      _showReward();
      return;
    }
    _applyStep(_step + 1);
  }

  void _onBoardTap(int i) {
    final st = step;
    if (st.findQuiz != null) return _handleFindQuiz(i);
    if (st.moveQuiz != null) return _handleMoveQuiz(i);
  }

  // ---- 找气问答 ----
  void _handleFindQuiz(int i) {
    final quiz = step.findQuiz!;
    if (_found.contains(i)) return;
    final answers = _game.libsOf(_game.groupAt(quiz.target));
    if (answers.contains(i)) {
      WqSfx.pop();
      _found.add(i);
      if (_found.length == answers.length) {
        // 先置完成状态，再播庆祝特效（特效失败不影响进度）
        _quizDone = true;
        _extraBubble = quiz.doneText;
        setState(() {});
        WqSfx.star();
        WqConfetti.burst(context, count: 26);
        _svc.speak(quiz.doneText);
      }
      setState(() {});
    } else {
      WqSfx.oops();
      HapticFeedback.selectionClick();
      _misses++;
      _extraBubble = quiz.missHints[_missHintTurn % quiz.missHints.length];
      _missHintTurn++;
      setState(() {});
      _svc.speak(_extraBubble);
    }
  }

  // ---- 动手落子挑战 ----
  void _handleMoveQuiz(int i) {
    final quiz = step.moveQuiz!;
    if (_quizDone) return;
    if (_game.s[i] != 0) {
      WqSfx.oops();
      ToastUtils.showInfo('这里已经有棋子啦');
      return;
    }
    if (_game.ko == i) {
      WqSfx.oops();
      ToastUtils.showInfo('这里刚被提过一颗子，要隔一手才能下回来——这就是「打劫」');
      return;
    }
    final snap = _game.clone();
    final r = _game.tryPlay(i, quiz.playerColor);
    if (!r.ok) {
      WqSfx.oops();
      if (r.reason == 'suicide') {
        _showRefused(i);
        ToastUtils.showInfo('这里没有气，棋子站不住哦——这叫「禁入点」');
      } else {
        ToastUtils.showInfo('这里不能下哦，再想一想！');
      }
      return;
    }
    final done = wqCheckGoal(
      _game,
      quiz.goal,
      playerColor: quiz.playerColor,
      minCapture: quiz.minCapture,
      minLibs: quiz.minLibs,
      goalPoint: quiz.goalPoint,
      goalPoint2: quiz.goalPoint2,
      captured: r.captured,
    );
    if (!done) {
      // 允许落子但不达标 → 收回这步棋，温柔提示
      _game.restoreFrom(snap);
      WqSfx.oops();
      _misses++;
      _extraBubble = quiz.hints[_missHintTurn % quiz.hints.length];
      _missHintTurn++;
      setState(() {});
      _svc.speak(_extraBubble);
      return;
    }
    // 先置完成状态并刷新 UI，再播放音效/动画（任何特效异常都不影响进度）
    _quizDone = true;
    _extraBubble = quiz.doneText;
    setState(() {});
    WqSfx.stone();
    HapticFeedback.lightImpact();
    if (r.captured.isNotEmpty) {
      WqSfx.capture();
      boardCtrl.flyCaptures(r.captured, 3 - quiz.playerColor);
    }
    WqSfx.star();
    WqConfetti.burst(context, count: 26);
    _svc.speak(quiz.doneText);
  }

  // ---- 结算 ----
  void _showReward() {
    final stars = _svc.recordLesson(lesson.id, _misses);
    WqSfx.star();
    WqConfetti.burst(context, count: 40);
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        // 底部安全区；内容全部使用固定逻辑尺寸（不用 .sp/.w/.h），
        // 手机与桌面窗口观感一致；FittedBox 仅在极端小窗口下等比缩小兜底
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(ctx).padding.bottom + 12,
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Container(
              width: 300,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: WqTheme.cream,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(
                      widthFactor: 1,
                      child: WqPanda(mood: WqPandaMood.cheer, size: 58)),
                  const SizedBox(height: 4),
                  const Text(
                    '课程完成！',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: WqTheme.ink),
                  ),
                  Text(
                    '${lesson.island} · 第${lesson.no}课 「${lesson.title}」',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: WqTheme.inkSoft),
                  ),
                  const SizedBox(height: 6),
                  Center(
                      widthFactor: 1,
                      child: WqStarsRow(stars: stars, pop: true, size: 26)),
                  const SizedBox(height: 8),
                  Center(
                    widthFactor: 1,
                    child: WqChip(
                      text: '学会：${lesson.teaches.join(' · ')}',
                      fixedFontSize: 11.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  WqPrimaryButton(
                    text: _nextLessonText(),
                    height: 46,
                    fontSize: 15,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      if (widget.lessonIndex + 1 < wqLessons.length) {
                        Get.off(() => WeiqiCoursePage(
                            lessonIndex: widget.lessonIndex + 1));
                      } else {
                        Get.back();
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  WqGhostButton(
                    text: '和棋棋下一盘',
                    height: 42,
                    fontSize: 13.5,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _showOpponentPicker();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _nextLessonText() {
    if (widget.lessonIndex + 1 < wqLessons.length) {
      return '继续闯关 ›';
    }
    return '真厉害，全部学完啦！';
  }

  void _showOpponentPicker() {
    // 从课程结算进入的对局：结束后直接回棋妙岛主页
    showWqOpponentPicker(context, exitToHomeAfterGame: true);
  }

  @override
  Widget build(BuildContext context) {
    final st = step;
    String quizHint = '';
    if (st.findQuiz != null && !_quizDone) {
      quizHint =
          '已点亮 ${_found.length} / ${_game.libsOf(_game.groupAt(st.findQuiz!.target)).length} 个气点';
    } else if (st.moveQuiz != null && !_quizDone) {
      quizHint = st.moveQuiz!.prompt;
    }
    return Scaffold(
      backgroundColor: WqTheme.cream,
      body: SafeArea(
        child: Column(
          children: [
            // 头部（对应原型 .lesson-head）
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
                    },
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${lesson.island} · 第${lesson.no}课',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w800,
                            color: WqTheme.ink,
                          ),
                        ),
                        Text(
                          '${lesson.subtitle} · ${st.caption}',
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
                  WqChip(text: '9路棋盘'),
                ],
              ),
            ),
            // 进度点（对应原型 .progress-dots）
            Padding(
              padding: EdgeInsets.symmetric(vertical: 7.h),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(lesson.steps.length, (k) {
                  final cur = k == _step;
                  final done = k < _step;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: EdgeInsets.symmetric(horizontal: 2.5.w),
                    width: cur ? 18.w : 7.w,
                    height: 7.h,
                    decoration: BoxDecoration(
                      color: cur
                          ? WqTheme.green
                          : done
                              ? WqTheme.greenSoft
                              : const Color(0xFFE2E7EF),
                      borderRadius: BorderRadius.circular(6.r),
                    ),
                  );
                }),
              ),
            ),
            // 棋棋的话（Flexible：小屏自动压缩，永不溢出）
            Flexible(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                child: WqBubble(
                  text: _extraBubble.isEmpty ? st.bubble : _extraBubble,
                  speaking: true,
                  mood: _quizDone ? WqPandaMood.cheer : WqPandaMood.happy,
                  maxLines: 4,
                  tail: true,
                  onReplay: () {
                    WqSfx.pop();
                    _svc.speak(_extraBubble.isEmpty ? st.bubble : _extraBubble);
                  },
                ),
              ),
            ),
            SizedBox(height: 8.h),
            // 棋盘
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(14.w, 0, 14.w, 14.h),
                child: WeiqiBoardView(
                  controller: boardCtrl,
                  stones: _game.s,
                  lastMove: _game.last,
                  breathePoints: {
                    ...st.breathe,
                    if (st.findQuiz != null) ..._found,
                  },
                  breatheWarn: st.warn,
                  blinkPoints: {
                    if (_refusedPoint != null) _refusedPoint!,
                  },
                  capByBlack: _game.capBlack,
                  capByWhite: _game.capWhite,
                  onPointTap:
                      (st.findQuiz != null || st.moveQuiz != null) && !_quizDone
                          ? _onBoardTap
                          : null,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 4.h),
              child: SizedBox(
                height: 18.h,
                child: Text(
                  quizHint,
                  style: TextStyle(
                    fontSize: 11.5.sp,
                    fontWeight: FontWeight.w700,
                    color: WqTheme.inkFaint,
                  ),
                ),
              ),
            ),
            // 底部操作（对应原型 .lesson-actions，紧凑不裁切）
            Padding(
              padding: EdgeInsets.fromLTRB(14.w, 0, 14.w, 14.h),
              child: Row(
                children: [
                  WqIconButton(
                    icon: Icons.replay_rounded,
                    size: 44,
                    onTap: () => _applyStep(_step),
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: WqGhostButton(
                      text: '上一步',
                      height: 42.h,
                      fontSize: 13.5.sp,
                      onTap: _step > 0 ? () => _applyStep(_step - 1) : null,
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    flex: 2,
                    child: WqPrimaryButton(
                      text: _step == lesson.steps.length - 1
                          ? '完成本课 ✦'
                          : '下一步 ›',
                      height: 44.h,
                      fontSize: 15.sp,
                      onTap: _next,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
