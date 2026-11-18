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
import 'weiqi_replay_page.dart';
import 'weiqi_service.dart';
import 'weiqi_sfx.dart';
import 'weiqi_theme.dart';
import 'weiqi_widgets.dart';

/// 对手与商业级对局参数选择底部弹层（课程结算页与模块首页共用）。
Future<void> showWqOpponentPicker(
  BuildContext context, {
  bool exitToHomeAfterGame = false,
}) async {
  final svc = Get.find<WeiqiService>();
  await showModalBottomSheet(
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
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Container(
              width: 340,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: WqTheme.cream,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: WqTheme.ink, width: 3.0),
                boxShadow: const [
                  BoxShadow(
                    color: WqTheme.ink,
                    offset: Offset(6, 6),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: Obx(() {
                final selLevel =
                    svc.aiLevelIndex.value.clamp(0, wqAiLevels.length - 1);
                final isTerritory = svc.ruleMode.value == 'territory';
                final curBoard = svc.boardSize.value;
                final curHandicap = svc.handicap.value;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '🎯 开启一局新对弈',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: WqTheme.ink,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 1. 对局规则模式切换（吃子棋 vs 标准围地）
                    const Text(
                      '对局规则',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        color: WqTheme.inkSoft,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: _modeTab(
                            selected: !isTerritory,
                            title: '🎯 吃子棋',
                            sub: '先提 ${svc.winCaptures.value} 颗获胜',
                            color: WqTheme.sun,
                            onTap: () => svc.ruleMode.value = 'capture',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _modeTab(
                            selected: isTerritory,
                            title: '🏆 标准围地',
                            sub: '围空数子 · 正式规则',
                            color: WqTheme.green,
                            onTap: () => svc.ruleMode.value = 'territory',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // 2. 棋盘路数与让子设置
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '棋盘大小',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: WqTheme.inkSoft,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [9, 13, 19].map((sz) {
                                  final on = curBoard == sz;
                                  return Expanded(
                                    child: GestureDetector(
                                      onTap: () => svc.boardSize.value = sz,
                                      child: Container(
                                        margin: const EdgeInsets.only(right: 4),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 6),
                                        decoration: BoxDecoration(
                                          color: on
                                              ? WqTheme.pink
                                              : Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: Border.all(
                                              color: WqTheme.ink, width: 1.8),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          '$sz路',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w900,
                                            color: WqTheme.ink,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '黑方让子（亲子/闯关）',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: WqTheme.inkSoft,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [0, 2, 3, 4].map((hc) {
                                  final on = curHandicap == hc;
                                  return Expanded(
                                    child: GestureDetector(
                                      onTap: () => svc.handicap.value = hc,
                                      child: Container(
                                        margin: const EdgeInsets.only(right: 4),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 6),
                                        decoration: BoxDecoration(
                                          color: on
                                              ? WqTheme.grape
                                              : Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: Border.all(
                                              color: WqTheme.ink, width: 1.8),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          hc == 0 ? '分先' : '$hc子',
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w900,
                                            color: WqTheme.ink,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // 3. 棋棋 5 档少儿级位
                    const Text(
                      '棋棋今天的状态（AI 级位）',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: WqTheme.inkSoft,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        for (var k = 0; k < wqAiLevels.length; k++)
                          Expanded(
                            child: GestureDetector(
                              onTap: () => svc.aiLevelIndex.value = k,
                              child: Container(
                                margin: EdgeInsets.only(
                                    right: k == wqAiLevels.length - 1 ? 0 : 4),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 6, horizontal: 2),
                                decoration: BoxDecoration(
                                  color: selLevel == k
                                      ? WqTheme.sun
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(9),
                                  border: Border.all(
                                    color: WqTheme.ink,
                                    width: 1.8,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      wqAiLevels[k].name,
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w900,
                                        color: WqTheme.ink,
                                      ),
                                    ),
                                    Text(
                                      wqAiLevels[k].persona.split('·').first,
                                      style: const TextStyle(
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.w800,
                                        color: WqTheme.inkSoft,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      wqAiLevels[selLevel].desc,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: WqTheme.inkSoft,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 4. 选择对手开始
                    _opponentOption(
                      ctx,
                      panda: const WqPanda(mood: WqPandaMood.happy, size: 48),
                      title: '和棋棋下',
                      subtitle: isTerritory
                          ? '$curBoard路标准围地 · AI 形势判断与点目'
                          : '$curBoard路吃子棋 · 棋棋会陪你慢慢下',
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
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: WqTheme.sun,
                          shape: BoxShape.circle,
                          border: Border.all(color: WqTheme.ink, width: 2.0),
                        ),
                        child: const Center(
                          child: Text('👪', style: TextStyle(fontSize: 24)),
                        ),
                      ),
                      title: '和家长同机下',
                      subtitle: isTerritory
                          ? '同机轮流落子 · $curBoard路围地数子'
                          : '同机轮流落子 · $curBoard路先提 ${svc.winCaptures.value} 颗赢',
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
                );
              }),
            ),
          ),
        ),
      );
    },
  );
}

Widget _modeTab({
  required bool selected,
  required String title,
  required String sub,
  required Color color,
  required VoidCallback onTap,
}) {
  return GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: selected ? color : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WqTheme.ink, width: 2.2),
        boxShadow: selected
            ? const [
                BoxShadow(
                  color: WqTheme.ink,
                  offset: Offset(3, 3),
                  blurRadius: 0,
                ),
              ]
            : const [],
      ),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: WqTheme.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: WqTheme.inkSoft,
            ),
          ),
        ],
      ),
    ),
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
  return GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: WqTheme.ink, width: 2.4),
        boxShadow: const [
          BoxShadow(
            color: WqTheme.ink,
            offset: Offset(4, 4),
            blurRadius: 0,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: WqTheme.ink, width: 2.0),
            ),
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
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                    color: WqTheme.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: WqTheme.inkSoft,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: WqTheme.ink),
        ],
      ),
    ),
  );
}

enum WqOpponent { ai, parent }

/// 商业级少儿围棋对局页：
/// 支持「吃子棋」与「标准围地（数子/点目）」双规则、让子、棋钟计时、
/// 实时形势判断（领地可视化）、虚手（Pass）、终局死子点选与点目结算、
/// 13/19路十字准星防误触确认、点棋问气、三层引导求助与复盘记录。
class WeiqiPlayPage extends StatefulWidget {
  final WqOpponent opponent;
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
  int get _maxStones => (_game.n * _game.n * 0.85).round();

  int _winCaptures = 3;
  late WqRuleMode _ruleMode;

  late final WeiqiService _svc;
  late WqGame _game;
  final List<WqGame> _history = [];
  bool _over = false;
  bool _busy = false;
  int _helpLeft = 3;
  int _helpStage = 0;
  String _helpKey = '';
  int _turn = 1; // 1=黑方(孩子) 2=白方(AI/家长)
  final Set<int> _reminded = {};
  int? _ownAtariBefore;
  bool _pendingCapture = false;
  final List<String> _milestones = [];
  String? _improvement;
  Timer? _aiTimer;

  /// 对局回放数据
  final List<({int color, int point})> _replayMoves = [];
  final Map<int, String> _replayNotes = {};
  final Map<int, int> _replayMarks = {};
  final Map<int, String> _replayGrades = {};
  final Map<int, int> _replayBetter = {};

  /// 孩子的棋被打吃时的最后一口气（警示小灯）
  Set<int> _dangerLibs = {};

  /// 提子现场讲解：残影（点→色）+ 计时器
  Map<int, int> _explainGhosts = {};
  Timer? _explainTimer;

  /// 点棋问棋棋：正在检视的棋组的气
  Set<int> _inspectLibs = {};
  Timer? _blinkTimer;

  final WqBoardController _boardCtrl = WqBoardController();
  Set<int> _blink = {};
  int? _glowCenter;
  String _bubbleText = '';
  WqPandaMood _mood = WqPandaMood.happy;

  /// 终局信息与点目状态
  String _endResult = '';
  String _endScoreSummaryText = '';
  Set<int> _endBlink = {};

  /// 是否开启实时形势判断（领地叠加层）
  bool _showTerritoryLive = false;

  /// 是否处于终局死子确认与点目结算阶段（标准围地模式）
  bool _scoringPhase = false;
  Set<int> _deadStones = {};
  WqScoreSummary? _scoreSummary;

  /// 13/19路防误触十字准星预览点
  int? _previewPoint;

  /// 对局棋钟（秒）
  Timer? _clockTimer;
  int _blackSeconds = 0;
  int _whiteSeconds = 0;

  bool get _isAi => widget.opponent == WqOpponent.ai;
  bool get _isTerritory => _ruleMode == WqRuleMode.territory;

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
    _blinkTimer?.cancel();
    _clockTimer?.cancel();
    _svc.stopSpeak();
    super.dispose();
  }

  void _resetGame() {
    _aiTimer?.cancel();
    _clockTimer?.cancel();
    _ruleMode = _svc.currentRuleMode;
    _game = WqGame(n: _svc.boardSize.value.clamp(9, 19).toInt());
    final hc = _svc.handicap.value;
    if (hc >= 2) {
      _game.setupHandicap(hc);
    }
    _history.clear();
    _over = false;
    _busy = false;
    _scoringPhase = false;
    _showTerritoryLive = false;
    _deadStones.clear();
    _scoreSummary = null;
    _previewPoint = null;
    _winCaptures = _svc.winCaptures.value;
    _endResult = '';
    _endScoreSummaryText = '';
    _endBlink = {};
    _helpLeft = 3;
    _helpStage = 0;
    _helpKey = '';
    // 让子局白棋先下，分先局黑棋先下
    _turn = _game.handicap >= 2 ? 2 : 1;
    _reminded.clear();
    _ownAtariBefore = null;
    _pendingCapture = false;
    _milestones.clear();
    _improvement = null;
    _replayMoves.clear();
    _replayNotes.clear();
    _replayMarks.clear();
    _replayGrades.clear();
    _replayBetter.clear();
    _dangerLibs = {};
    _explainGhosts = {};
    _explainTimer?.cancel();
    _inspectLibs = {};
    _blinkTimer?.cancel();
    _blink = {};
    _glowCenter = null;

    final limitMin = _svc.timeLimitMinutes.value;
    _blackSeconds = limitMin > 0 ? limitMin * 60 : 0;
    _whiteSeconds = limitMin > 0 ? limitMin * 60 : 0;
    if (limitMin > 0) _startClock();

    final hcText = _game.handicap >= 2 ? '（黑让 ${_game.handicap} 子，白棋先下）' : '（你执黑先下）';
    _say(
      _isTerritory
          ? '标准围地对局开始！${_game.n}路棋盘$hcText，先占金角、再占银边，终局看谁围的领地大！随时可点「形势」看地盘哦～'
          : (_isAi
              ? '我来啦！我们玩吃子棋$hcText：谁先把对方提走 $_winCaptures 颗棋子，谁就赢！'
              : '亲子吃子棋开始$hcText！谁先提走对方 $_winCaptures 颗棋子就赢！'),
      WqPandaMood.happy,
      speakIt: true,
    );
    setState(() {});

    // 如果让子局且对手是 AI，则由 AI 执白走第一手
    if (_isAi && _turn == 2) {
      _aiTurn();
    }
  }

  void _startClock() {
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _over || _scoringPhase) return;
      setState(() {
        if (_turn == 1 && !_busy) {
          if (_blackSeconds > 0) _blackSeconds--;
        } else {
          if (_whiteSeconds > 0) _whiteSeconds--;
        }
      });
    });
  }

  String _formatClock(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _say(String text, WqPandaMood mood, {bool speakIt = false}) {
    _bubbleText = text;
    _mood = mood;
    setState(() {});
    if (speakIt) _svc.speak(text);
  }

  /// 构建当前棋盘上的手数映射（用于显示手数编号）
  Map<int, int> _buildMoveNumbers() {
    if (!_svc.showMoveNumbers.value) return const {};
    final map = <int, int>{};
    for (var k = 0; k < _replayMoves.length; k++) {
      final pt = _replayMoves[k].point;
      if (pt >= 0 && _game.s[pt] != 0) {
        map[pt] = k + 1;
      }
    }
    return map;
  }

  // ================= 落子与点目点击 =================

  void _onTap(int i) {
    if (_over) return;

    // 终局点目阶段：点击棋子切换死/活状态
    if (_scoringPhase) {
      _toggleDeadStoneGroup(i);
      return;
    }

    if (_busy) return;
    if (_game.s[i] != 0) {
      _previewPoint = null;
      _inspect(i); // 点棋问棋棋：查看这块棋的气
      return;
    }

    // 13路/19路且开启落子确认时：首次点击显示十字准星，再次点击同一点或点底部确认才落子
    final needConfirm = _game.n >= 13 && _svc.confirmMove.value;
    if (needConfirm && _previewPoint != i) {
      WqSfx.pop();
      setState(() {
        _previewPoint = i;
        _inspectLibs = {};
      });
      return;
    }
    _previewPoint = null;
    _inspectLibs = {};
    if (!_isAi && _turn == 2) {
      _parentMove(i);
      return;
    }
    _childMove(i);
  }

  void _confirmPreviewMove() {
    final pt = _previewPoint;
    if (pt == null) return;
    _previewPoint = null;
    if (!_isAi && _turn == 2) {
      _parentMove(pt);
    } else {
      _childMove(pt);
    }
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
        _say('这里没有气，棋子站不住哦——这叫「禁入点」，换一个地方下吧！',
            WqPandaMood.think,
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
    _inspectLibs = {};
    final myIdx = _replayMoves.length;
    final whiteAtariLibs = _atariLibsOf(2);
    final threatBefore = WqAi.hintTarget(_game, 1, mode: _ruleMode);
    final enemyAtariBefore = _atariLibsOf(2).isNotEmpty;
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
      _replayGrades[myIdx] = 'great';
      _say(
        r.captured.length > 1
            ? '哇！一手提走 ${r.captured.length} 颗，这是「双打」的好棋呀！'
            : '提子成功！你把白棋的呼吸全堵住啦～',
        WqPandaMood.cheer,
        speakIt: true,
      );
      if (!_isTerritory && _game.capBlack >= _winCaptures) {
        return _endGame('win', captured: r.captured);
      }
    } else {
      if (_ownAtariBefore != null) {
        final grp = _game.groupAt(_ownAtariBefore!);
        if (grp.isNotEmpty && _game.libsOf(grp).length >= 2) {
          _milestones.add('被包围的士兵成功逃出来啦，会「长气」了！');
          _replayNotes[myIdx] = '这一手让被包围的士兵长出了气，逃出去啦！';
          _replayGrades[myIdx] = 'great';
        }
        _ownAtariBefore = null;
      }
      if (_replayGrades[myIdx] == null) {
        if (threatBefore != null &&
            threatBefore.type == 'capture' &&
            i != threatBefore.pt) {
          _replayGrades[myIdx] = 'miss';
          _replayBetter[myIdx] = threatBefore.pt;
          _replayNotes[myIdx] ??=
              '其实橙色圈那个点能一手提走白棋——看到打吃，先提为敬！';
          _replayMarks[myIdx] = threatBefore.pt;
        } else if (threatBefore != null &&
            threatBefore.type == 'escape' &&
            i != threatBefore.pt) {
          final grp = _game.groupAt(threatBefore.grp.first);
          if (grp.isNotEmpty && _game.libsOf(grp).length <= 1) {
            _replayGrades[myIdx] = 'danger';
            _replayBetter[myIdx] = threatBefore.pt;
            _replayNotes[myIdx] ??=
                '自己的棋还剩一口气！更好的下法是橙色圈先逃出去（或反提对方）';
            _replayMarks[myIdx] = threatBefore.pt;
          } else {
            _replayGrades[myIdx] = 'ok';
          }
        } else if (!enemyAtariBefore && _atariLibsOf(2).isNotEmpty) {
          _replayGrades[myIdx] = 'good';
          _replayNotes[myIdx] ??= '这一手打吃了白棋——它的气只剩最后一口啦！';
        } else {
          _replayGrades[myIdx] = 'ok';
        }
      }
      if (_pendingCapture) {
        _improvement ??=
            '白棋的士兵曾只剩一口气，机会悄悄溜走了——下次看到「打吃」，先一手提走它！';
        _replayNotes[myIdx] ??=
            '这一手之前，白棋有子只剩一口气——橙色圈就是那口气，应该在这里一手提掉哦';
        if (whiteAtariLibs.isNotEmpty) {
          _replayMarks[myIdx] = whiteAtariLibs.first;
        }
        _pendingCapture = false;
      }
      final myAtariLibs = _atariLibsOf(1);
      if (myAtariLibs.isNotEmpty) {
        _replayNotes[myIdx] ??=
            '这手棋之后，自己的棋只剩一口气了——橙色圈就是那口气，被堵住就会被提走哦';
        _replayMarks[myIdx] = myAtariLibs.first;
      }
    }
    _updateDanger();
    if (_showTerritoryLive) _refreshLiveTerritory();

    if (!_isTerritory && _game.stoneCount() >= _maxStones) {
      return _endGame('review');
    }
    if (_isTerritory && _game.stoneCount() >= _maxStones) {
      return _enterScoringPhase();
    }

    if (_isAi) {
      _turn = 2;
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
      if (!_isTerritory && _game.capWhite >= _winCaptures) {
        return _endGame('lose', captured: r.captured);
      }
    }
    _updateDanger();
    if (_showTerritoryLive) _refreshLiveTerritory();
    _turn = 1;
    _say('轮到你（黑棋）啦！', WqPandaMood.happy, speakIt: false);
    setState(() {});
  }

  // ================= 虚手（Pass）与形势判断/点目结算 =================

  /// 玩家或家长点击「虚手（停一手）」
  void _handlePass() {
    if (_over || _busy || _scoringPhase) return;
    _history.add(_game.clone());
    _previewPoint = null;
    final whoColor = (!_isAi && _turn == 2) ? 2 : 1;
    _game.pass(whoColor);
    WqSfx.pop();

    if (_game.consecutivePasses >= 2) {
      _say('双方都选择了虚手（停一手），棋局收官完成！现在进入点目结算阶段～',
          WqPandaMood.cheer,
          speakIt: true);
      _enterScoringPhase();
      return;
    }

    if (_isAi) {
      _say('你选择了虚手（停一手），让棋棋看看还有没有地方可下……', WqPandaMood.think,
          speakIt: false);
      _turn = 2;
      _aiTurn();
    } else {
      _turn = 3 - _turn;
      _say(
        '${whoColor == 1 ? '黑棋' : '白棋'}选择了虚手（停一手）！如果对方也虚手，就进入终局数子结算。',
        WqPandaMood.think,
        speakIt: true,
      );
      setState(() {});
    }
  }

  /// 切换实时形势判断（领地叠加层）
  void _toggleLiveTerritory() {
    WqSfx.pop();
    setState(() {
      _showTerritoryLive = !_showTerritoryLive;
      if (_showTerritoryLive) {
        _refreshLiveTerritory();
        final s = _scoreSummary!;
        final leadAbs = s.blackLead.abs().toStringAsFixed(1);
        final who = s.isBlackWin ? '黑方(你)领先' : '白方领先';
        _say(
          '形势判断：黑方子空 ${s.blackArea}（${s.blackStones}子+${s.blackTerritory}空），白方子空 ${s.whiteArea}（贴${s.komi}目），目前$who $leadAbs 目！',
          s.isBlackWin ? WqPandaMood.cheer : WqPandaMood.think,
          speakIt: true,
        );
      } else {
        _scoreSummary = null;
      }
    });
  }

  void _refreshLiveTerritory() {
    _scoreSummary = WqTerritoryEstimator.estimate(
      _game,
      includeInfluence: true,
    );
  }

  /// 进入终局死子确认与点目结算阶段（标准围地模式）
  void _enterScoringPhase() {
    _aiTimer?.cancel();
    _busy = false;
    _scoringPhase = true;
    _previewPoint = null;
    _deadStones = WqTerritoryEstimator.detectAutoDeadStones(_game);
    _recalcFinalScore();
  }

  void _toggleDeadStoneGroup(int pt) {
    if (_game.s[pt] == 0) return;
    WqSfx.pop();
    final grp = _game.groupAt(pt);
    final alreadyDead = _deadStones.contains(pt);
    setState(() {
      if (alreadyDead) {
        _deadStones.removeAll(grp);
      } else {
        _deadStones.addAll(grp);
      }
      _recalcFinalScore();
    });
  }

  void _recalcFinalScore() {
    final summary = WqTerritoryEstimator.estimate(
      _game,
      deadStones: _deadStones,
      includeInfluence: false,
    );
    _scoreSummary = summary;
    final leadAbs = summary.blackLead.abs().toStringAsFixed(1);
    final winText = summary.isBlackWin ? '黑棋胜 $leadAbs 目' : '白棋胜 $leadAbs 目';
    _endScoreSummaryText =
        '黑 ${summary.blackArea} 子/空 vs 白 ${summary.whiteArea}+${summary.komi}贴目 · $winText';
    _say(
      '终局点目：$winText！（黑方 ${summary.blackStones}子+${summary.blackTerritory}空=${summary.blackArea}；白方 ${summary.whiteStones}子+${summary.whiteTerritory}空+贴${summary.komi}=${summary.whiteTotal.toStringAsFixed(1)}）。可点棋子切换死子，确认无误请点「确认结算」！',
      summary.isBlackWin ? WqPandaMood.cheer : WqPandaMood.think,
      speakIt: true,
    );
    setState(() {});
  }

  void _confirmTerritoryResult() {
    final summary = _scoreSummary ??
        WqTerritoryEstimator.estimate(_game, deadStones: _deadStones);
    _scoringPhase = false;
    _milestones.add(
      '完成了一整局 ${_game.n} 路标准围地对局，围住 ${summary.blackTerritory} 目领地！',
    );
    _endGame(summary.isBlackWin ? 'win' : 'lose');
    _showSettlement();
  }

  // ================= AI（棋棋） =================

  int? _openingMove() {
    if (_game.stoneCount() > 3) return null;
    final n = _game.n;
    final edge = n >= 13 ? 3 : 2;
    final mid = n ~/ 2;
    final openings = n >= 13
        ? <int>[
            for (final y in [edge, mid, n - 1 - edge])
              for (final x in [edge, mid, n - 1 - edge]) y * n + x,
          ]
        : <int>[
            edge * n + edge,
            edge * n + (n - 1 - edge),
            (n - 1 - edge) * n + edge,
            (n - 1 - edge) * n + (n - 1 - edge),
            mid * n + mid,
          ];
    final candidates =
        openings.where((pt) => _game.s[pt] == 0).toList()..shuffle();
    return candidates.isEmpty ? null : candidates.first;
  }

  void _aiTurn() {
    _busy = true;
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
      _say('咦？你的黑士兵好像只剩 1 口气啦……要不要先帮它找个逃跑的路？',
          WqPandaMood.think,
          speakIt: true);
    }
    _aiTimer = Timer(Duration(milliseconds: danger != null ? 1300 : 150), () {
      if (!mounted || _over || _scoringPhase) return;
      _say('棋棋想一下……', WqPandaMood.think, speakIt: false);
      _aiTimer =
          Timer(Duration(milliseconds: 650 + math.Random().nextInt(550)), () {
        if (!mounted || _over || _scoringPhase) return;
        final level = wqAiLevels[
            _svc.aiLevelIndex.value.clamp(0, wqAiLevels.length - 1)];

        // 如果玩家刚刚虚手且在围地模式下盘面已进入官子尾声，AI 评估是否跟着虚手终局
        final mv = (_game.consecutivePasses > 0 &&
                _isTerritory &&
                _game.stoneCount() > _game.n * _game.n * 0.42)
            ? null
            : (_openingMove() ??
                WqAi.pickMove(
                  _game,
                  2,
                  level.skill,
                  rnd: math.Random(),
                  mode: _ruleMode,
                ));

        if (mv == null) {
          _game.pass(2);
          _busy = false;
          _turn = 1;
          if (_isTerritory) {
            if (_game.consecutivePasses >= 2) {
              _enterScoringPhase();
            } else {
              _say('棋棋觉得地盘已经围好啦，选择「虚手（停一手）」！如果你也觉得下完了，点「虚手」或「点目」就能算胜负啦！',
                  WqPandaMood.cheer,
                  speakIt: true);
              setState(() {});
            }
            return;
          }
          return _endGame('review');
        }

        final r = _game.tryPlay(mv, 2);
        WqSfx.stone();
        final aiIdx = _replayMoves.length;
        final whiteAtariBeforeAi = _atariLibsOf(2).isNotEmpty;
        if (r.ok) {
          _replayMoves.add((color: 2, point: mv));
        }
        if (r.ok && r.captured.isEmpty) {
          final newAtari = _atariLibsOf(1).isNotEmpty;
          final aiSavedSelf = whiteAtariBeforeAi && _atariLibsOf(2).isEmpty;
          _replayNotes[aiIdx] ??= newAtari
              ? '棋棋在打吃你的棋——想一路把气堵光提掉它'
              : aiSavedSelf
                  ? '棋棋在逃自己被打吃的棋，不让白棋白白牺牲'
                  : (_isTerritory
                      ? '棋棋在占角拆边、围大自己的领地'
                      : '棋棋在稳稳行棋：连接自己的棋、寻找下一步机会');
        }
        if (r.ok && r.captured.isNotEmpty) {
          WqSfx.capture();
          _boardCtrl.flyCaptures(r.captured, 1);
          _improvement ??= '有一手棋你的士兵被白棋提走了——下次落子前，先数一数自己还有几口气。';
          _replayNotes[aiIdx] =
              '棋棋下了橙色圈这个点，堵住了你最后的气——${r.captured.length} 颗黑棋被提走了';
          _replayMarks[aiIdx] = mv;
          _showCaptureExplanation(
            captured: r.captured,
            capturedColor: 1,
            movePoint: mv,
            moverColor: 2,
          );
          if (!_isTerritory && _game.capWhite >= _winCaptures) {
            return _endGame('lose', captured: r.captured);
          }
        } else {
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
        if (_showTerritoryLive) _refreshLiveTerritory();

        if (!_isTerritory) {
          if (_game.capBlack >= _winCaptures) return _endGame('win');
          if (_game.capWhite >= _winCaptures) return _endGame('lose');
          if (_game.stoneCount() >= _maxStones) return _endGame('review');
        } else if (_game.stoneCount() >= _maxStones) {
          return _enterScoringPhase();
        }

        _busy = false;
        _turn = 1;
        final newDanger = _atariLibsOf(1);
        if (r.ok &&
            r.captured.isEmpty &&
            newDanger.isNotEmpty &&
            _svc.remindOn.value) {
          _blink = {newDanger.first};
          _say('棋棋打吃你的黑棋啦！闪烁的这口气再被堵住，棋子就会被提走——点自己的棋看看怎么救！',
              WqPandaMood.think,
              speakIt: true);
          _blinkTimer?.cancel();
          _blinkTimer = Timer(const Duration(milliseconds: 3000), () {
            if (mounted) setState(() => _blink = {});
          });
        } else if (r.ok && r.captured.isEmpty) {
          if (math.Random().nextDouble() < 0.38) {
            _say(_encouragements[math.Random().nextInt(_encouragements.length)],
                WqPandaMood.happy,
                speakIt: false);
          } else {
            _say('轮到你（${wqCoordLabel(mv, _game.n)}）啦！', WqPandaMood.happy,
                speakIt: false);
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

  void _inspect(int i) {
    final color = _game.s[i];
    final grp = _game.groupAt(i);
    final libs = _game.libsOf(grp);
    final isMine = color == 1;
    final n = libs.length;
    if (n == 0) return;
    final String text;
    if (n == 1) {
      text = isMine
          ? '这块黑棋只剩 1 口气啦（亮着的点）！再被堵住就会被提走——快逃跑或者反提！'
          : '这块白棋只剩 1 口气（亮着的点）！下在那里就能把它提走！';
    } else if (n == 2) {
      text = isMine
          ? '这块黑棋有 2 口气（亮起的点），暂时安全，但要小心被打吃。'
          : '这块白棋有 2 口气（亮起的点）。堵住 1 口就是打吃，2 口全堵住就能提走它！';
    } else {
      text = isMine
          ? '这块黑棋手拉手连成一体，共有 $n 口气（亮起的点），很安全！'
          : '这块白棋有 $n 口气（亮起的点）。棋子越多、气越多，越难被吃。';
    }
    _explainTimer?.cancel();
    _explainGhosts = {};
    _blink = {};
    _blinkTimer?.cancel();
    _mood = n == 1 && isMine ? WqPandaMood.think : WqPandaMood.happy;
    _bubbleText = text;
    _svc.speak(text);
    setState(() => _inspectLibs = libs);
  }

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

  void _updateDanger() {
    _dangerLibs = _atariLibsOf(1);
    if (mounted) setState(() {});
  }

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
      text = '$who下了最后一口气那个点——你的 $n 颗黑棋没有气了，就被提走啦。下次落子前，先数一数自己的气哦！';
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
    if (_over || _busy || _scoringPhase) return;
    if (_helpLeft <= 0) {
      WqSfx.oops();
      ToastUtils.showInfo('这局的求助机会用完啦，再下一局就有哦～');
      return;
    }
    final t = WqAi.hintTarget(_game, 1, mode: _ruleMode);
    final key = t == null ? 'none' : '${t.type}${t.pt}';
    if (key != _helpKey) {
      _helpStage = 0;
      _helpKey = key;
    }
    final stage = _helpStage;
    _helpLeft--;
    _clearMarks();
    if (t == null) {
      _say('嗯……现在局面很安稳，把棋下在空旷的角或边上，慢慢围自己的地盘吧！', WqPandaMood.think);
      _helpStage = 0;
      return;
    }
    switch (stage) {
      case 0:
        _say(
          t.type == 'capture'
              ? '看棋盘上微光区域，白棋有个小士兵快没气了——找找它的气在哪里？'
              : t.type == 'escape'
                  ? '别急！你的士兵被包围了，帮它找一个能多口气的地方吧～'
                  : '看这片微光区域，这里是目前围地和扩张最好的要点（${wqCoordLabel(t.pt, _game.n)}附近）！',
          WqPandaMood.think,
          speakIt: true,
        );
        setState(() => _glowCenter = t.grp[t.grp.length ~/ 2]);
        break;
      case 1:
        _say(
          t.type == 'capture'
              ? '它只剩最后一口气啦！点这个闪光的交叉点（${wqCoordLabel(t.pt, _game.n)}）试试？'
              : t.type == 'escape'
                  ? '点这个闪光的点（${wqCoordLabel(t.pt, _game.n)}），你的士兵就能呼吸更多口气啦！'
                  : '棋棋推荐下在闪光的要点（${wqCoordLabel(t.pt, _game.n)}），既稳健又能抢占先机！',
          WqPandaMood.think,
          speakIt: true,
        );
        setState(() => _blink = {t.pt});
        break;
      default:
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
      _say('魔法收回啦！现在轮到你，自己把它下出来吧！', WqPandaMood.happy, speakIt: true);
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
      _resetGame();
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
    if (_over || _scoringPhase) return;
    if (_history.isEmpty) {
      ToastUtils.showInfo('还没有历史棋步哦');
      return;
    }
    final ok = await _confirm(
      title: '真的要悔棋吗？',
      body: '棋棋觉得这步棋还有救哦～再想一下，或者悔一步重新想想也可以！',
      okText: '悔一步',
      cancelText: '再想想',
    );
    if (!ok) return;
    _aiTimer?.cancel();
    _game.restoreFrom(_history.removeLast());
    if (_replayMoves.isNotEmpty) _replayMoves.removeLast();
    if (_isAi && _replayMoves.isNotEmpty && _replayMoves.last.color == 2) {
      _replayMoves.removeLast();
    }
    _busy = false;
    _turn = 1;
    _previewPoint = null;
    _helpStage = 0;
    _clearMarks();
    _updateDanger();
    if (_showTerritoryLive) _refreshLiveTerritory();
    _say('好，悔一步。棋棋再给你一次机会想清楚哦——这步棋一定还有更好的下法！',
        WqPandaMood.think,
        speakIt: true);
    setState(() {});
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String okText,
    String cancelText = '再想想',
  }) async {
    final res = await Get.dialog<bool>(
      Dialog(
        backgroundColor: WqTheme.cream,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24.r),
          side: const BorderSide(color: WqTheme.ink, width: 3.0),
        ),
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
                  fontSize: 17.sp,
                  fontWeight: FontWeight.w900,
                  color: WqTheme.ink,
                ),
              ),
              SizedBox(height: 6.h),
              Text(
                body,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w700,
                  color: WqTheme.inkSoft,
                ),
              ),
              SizedBox(height: 16.h),
              Row(
                children: [
                  Expanded(
                    child: WqGhostButton(
                      text: cancelText,
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

  void _endGame(String result, {List<int> captured = const []}) {
    if (_over) return;
    _over = true;
    _busy = false;
    _scoringPhase = false;
    _aiTimer?.cancel();
    _clockTimer?.cancel();
    _endResult = result;
    _endBlink = Set.of(captured);

    final win = result == 'win' ||
        (result == 'review' && _game.capBlack >= _game.capWhite);
    _svc.recordGame(
      result: result == 'win' ? 'win' : (result == 'lose' ? 'lose' : 'draw'),
    );

    if (_endScoreSummaryText.isEmpty) {
      _endScoreSummaryText = _isTerritory
          ? '围地模式 · 黑提${_game.capBlack} 白提${_game.capWhite}'
          : '吃子棋 · 黑提${_game.capBlack} 比 白提${_game.capWhite}';
    }

    if (_replayMoves.isNotEmpty) {
      _svc.saveLastGame(
        _replayMoves,
        _replayNotes,
        _replayMarks,
        _replayGrades,
        _replayBetter,
        _game.n,
        _isTerritory ? 'territory' : 'capture',
        result,
        _endScoreSummaryText,
      );
    }

    if (win) {
      WqSfx.star();
    } else {
      WqSfx.pop();
    }

    if (!_isTerritory) {
      _say(
        result == 'win'
            ? '第 $_winCaptures 颗白棋被你提走啦，赢咯！看，棋盘上一闪一闪的就是刚被提走的白子。点下面的「看看战报」查看详细复盘卡！'
            : result == 'lose'
                ? '这手棋把你的黑子提走了……棋盘上一闪一闪的就是刚才被提走的棋。点「看看战报」一起找答案！'
                : '这一局就下到这里！点下面的「看看战报」，棋棋陪你一步一步回顾。',
        win ? WqPandaMood.cheer : WqPandaMood.sad,
        speakIt: true,
      );
    }
    setState(() {});
  }

  /// 结算卡（战报）
  void _showSettlement() {
    if (!_over) return;
    final result = _endResult;
    final win = result == 'win' ||
        (result == 'review' && _game.capBlack >= _game.capWhite);
    final ms = List<String>.from(_milestones.take(3));
    final defaults = [
      '敢和 AI 陪练下满一整局，勇气满分！',
      '每一步都认真思考了，棋棋都看在眼里～',
      '今天的你比昨天更懂金角银边与数气了！',
    ];
    var di = 0;
    while (ms.length < 3) {
      ms.add(defaults[di++ % defaults.length]);
    }
    final imp = _improvement ?? '下次可以试试「落子前先看自己和对方的气」，棋棋保证你会更强！';
    final title = result == 'win'
        ? '你赢啦！'
        : win
            ? '你领先！'
            : (_isAi ? '棋棋险胜！' : '家长险胜！');
    final sub = _isTerritory && _endScoreSummaryText.isNotEmpty
        ? _endScoreSummaryText
        : (result == 'win'
            ? '$_winCaptures 颗提子 · 你把白棋的呼吸全堵住了'
            : result == 'lose'
                ? '${_game.capWhite} 比 ${_game.capBlack} · 棋盘上闪一闪的就是被提走的棋'
                : '本局结束 · 黑 ${_game.capBlack} 比 白 ${_game.capWhite}');

    final rank = _svc.rankInfo;

    Get.dialog(
      Dialog(
        backgroundColor: WqTheme.cream,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26.r),
          side: const BorderSide(color: WqTheme.ink, width: 3.0),
        ),
        insetPadding: EdgeInsets.all(20.w),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(18.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              WqPanda(mood: win ? WqPandaMood.cheer : WqPandaMood.sad, size: 78),
              SizedBox(height: 6.h),
              Text(
                title,
                style: TextStyle(
                  fontSize: 22.sp,
                  fontWeight: FontWeight.w900,
                  color: WqTheme.ink,
                ),
              ),
              SizedBox(height: 2.h),
              Text(
                sub,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5.sp,
                  fontWeight: FontWeight.w800,
                  color: WqTheme.inkSoft,
                ),
              ),
              SizedBox(height: 8.h),
              WqStarsRow(stars: win ? 3 : 2, pop: true, size: 26),
              SizedBox(height: 8.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  WqChip.sun(
                    text: '当前棋力：${rank.rank} · ${rank.title}',
                    tiltDeg: -2.0,
                  ),
                ],
              ),
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
                sub: '已记入复盘笔记，重看棋局会更强哦',
                improve: true,
              ),
              SizedBox(height: 12.h),
              if (_replayMoves.isNotEmpty)
                WqGhostButton(
                  text: '重看棋局 · 学一手',
                  height: 42.h,
                  fontSize: 13.5.sp,
                  onTap: () {
                    Get.back();
                    Get.to(() => WeiqiReplayPage(
                          moves: _replayMoves,
                          notes: _replayNotes,
                          marks: _replayMarks,
                          grades: _replayGrades,
                          better: _replayBetter,
                          n: _game.n,
                        ));
                  },
                ),
              if (_replayMoves.isNotEmpty) SizedBox(height: 8.h),
              WqPrimaryButton(
                text: win ? '再来一局！' : '我们再战一局！',
                color: WqTheme.sun,
                onTap: () {
                  Get.back();
                  _resetGame();
                },
              ),
              SizedBox(height: 8.h),
              WqGhostButton(
                text: '回小岛休息一下',
                onTap: () {
                  Get.back();
                  Get.back();
                  if (widget.exitToHome) {
                    Get.back();
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
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.all(10.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: WqTheme.ink, width: 2.0),
        boxShadow: const [
          BoxShadow(color: WqTheme.ink, blurRadius: 0, offset: Offset(3, 3)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28.w,
            height: 28.w,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: improve ? WqTheme.sun : WqTheme.green,
              border: Border.all(color: WqTheme.ink, width: 1.6),
            ),
            child: Center(
              child: Text(
                rank,
                style: TextStyle(
                  fontSize: 12.5.sp,
                  fontWeight: FontWeight.w900,
                  color: WqTheme.ink,
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
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w900,
                    height: 1.45,
                    color: WqTheme.ink,
                  ),
                ),
                Text(
                  sub,
                  style: TextStyle(
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w700,
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
    final limitMin = _svc.timeLimitMinutes.value;
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
              // 顶部状态与专业工具栏
              Padding(
                padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 2.h),
                child: Row(
                  children: [
                    WqIconButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      size: 38,
                      onTap: () async {
                        final exit = await _confirmExit();
                        if (exit && mounted) {
                          _svc.stopSpeak();
                          Get.back();
                        }
                      },
                    ),
                    SizedBox(width: 6.w),
                    Expanded(
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 8.w, vertical: 6.h),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: WqTheme.ink, width: 2.0),
                          boxShadow: const [
                            BoxShadow(
                              color: WqTheme.ink,
                              blurRadius: 0,
                              offset: Offset(2.5, 2.5),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 7.w, vertical: 2.5.h),
                              decoration: BoxDecoration(
                                color: _turn == 1 ? WqTheme.ink : WqTheme.sun,
                                borderRadius: BorderRadius.circular(999),
                                border:
                                    Border.all(color: WqTheme.ink, width: 1.5),
                              ),
                              child: Text(
                                _scoringPhase
                                    ? '点目结算'
                                    : (_isAi
                                        ? (_turn == 1 ? '你·执黑' : '棋棋·执白')
                                        : (_turn == 1 ? '孩子·黑' : '家长·白')),
                                style: TextStyle(
                                  fontSize: 10.5.sp,
                                  fontWeight: FontWeight.w900,
                                  color:
                                      _turn == 1 ? Colors.white : WqTheme.ink,
                                ),
                              ),
                            ),
                            SizedBox(width: 6.w),
                            Flexible(
                              child: Text(
                                limitMin > 0
                                    ? '⚫${_formatClock(_blackSeconds)} ⚪${_formatClock(_whiteSeconds)}'
                                    : (_isTerritory
                                        ? '${_game.n}路围地 · 贴${WqTerritoryEstimator.defaultKomi(_game.n, handicap: _game.handicap)}目'
                                        : '先提 $_winCaptures 颗获胜'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10.5.sp,
                                  fontWeight: FontWeight.w800,
                                  color: WqTheme.ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: 6.w),
                    // 实时形势判断按钮
                    WqIconButton(
                      icon: Icons.grid_view_rounded,
                      size: 38,
                      bgColor: (_showTerritoryLive || _scoringPhase)
                          ? WqTheme.sun
                          : Colors.white,
                      onTap: _scoringPhase ? null : _toggleLiveTerritory,
                    ),
                    SizedBox(width: 5.w),
                    // 手数与坐标开关
                    Obx(() => WqIconButton(
                          icon: Icons.pin_rounded,
                          size: 38,
                          bgColor: _svc.showMoveNumbers.value
                              ? WqTheme.greenSoft
                              : Colors.white,
                          onTap: () {
                            _svc.showMoveNumbers.value =
                                !_svc.showMoveNumbers.value;
                            setState(() {});
                          },
                        )),
                    SizedBox(width: 5.w),
                    WqIconButton(
                      icon: Icons.replay_rounded,
                      size: 38,
                      onTap: _confirmRestart,
                    ),
                  ],
                ),
              ),

              // 棋棋对话气泡区
              Flexible(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(12.w, 6.h, 12.w, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          WqPanda(mood: _mood, size: 52),
                          if (_isAi)
                            Container(
                              margin: const EdgeInsets.only(top: 3),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: WqTheme.sun,
                                borderRadius: BorderRadius.circular(999),
                                border:
                                    Border.all(color: WqTheme.ink, width: 1.5),
                              ),
                              child: Obx(() {
                                final lv = wqAiLevels[_svc.aiLevelIndex.value
                                    .clamp(0, wqAiLevels.length - 1)];
                                return Text(
                                  lv.persona,
                                  style: const TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w900,
                                    color: WqTheme.ink,
                                  ),
                                );
                              }),
                            ),
                        ],
                      ),
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

              // 棋盘主体
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(12.w, 4.h, 12.w, 4.h),
                  child: Center(
                    child: Obx(() => WeiqiBoardView(
                          n: _game.n,
                          controller: _boardCtrl,
                          stones: _game.s,
                          lastMove: _game.last,
                          showCoords: _svc.showCoords.value,
                          moveNumbers: _buildMoveNumbers(),
                          territoryOwnerMap:
                              (_showTerritoryLive || _scoringPhase)
                                  ? _scoreSummary?.ownerMap
                                  : null,
                          deadStones: _scoringPhase
                              ? _deadStones
                              : (_showTerritoryLive
                                  ? (_scoreSummary?.deadStones ?? const {})
                                  : const {}),
                          previewPoint: _previewPoint,
                          previewColor: (!_isAi && _turn == 2) ? 2 : 1,
                          blinkPoints: {..._blink, ..._endBlink},
                          glowCenter: _glowCenter,
                          glowRadius: 22,
                          ghostStone: _ghostStone,
                          ghostColor: 1,
                          ghostStones: _explainGhosts,
                          breathePoints: _inspectLibs.isNotEmpty
                              ? _inspectLibs
                              : (_isAi &&
                                      _svc.remindOn.value &&
                                      _svc.atariLightsOn.value
                                  ? _dangerLibs
                                  : const {}),
                          breatheWarn: _inspectLibs.isEmpty,
                          capByBlack: _game.capBlack,
                          capByWhite: _game.capWhite,
                          onPointTap: _onTap,
                        )),
                  ),
                ),
              ),

              // 13/19路十字准星防误触确认条
              if (_previewPoint != null && !_over && !_scoringPhase)
                Padding(
                  padding: EdgeInsets.fromLTRB(14.w, 0, 14.w, 4.h),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: WqPrimaryButton(
                          text:
                              '🎯 确认落子 (${wqCoordLabel(_previewPoint!, _game.n)})',
                          height: 40.h,
                          fontSize: 13.5.sp,
                          color: WqTheme.sun,
                          onTap: _confirmPreviewMove,
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: WqGhostButton(
                          text: '取消选点',
                          height: 40.h,
                          fontSize: 12.5.sp,
                          onTap: () => setState(() => _previewPoint = null),
                        ),
                      ),
                    ],
                  ),
                ),

              // 底部商业级操作栏
              Padding(
                padding: EdgeInsets.fromLTRB(12.w, 2.h, 12.w, 10.h),
                child: Row(
                  children: [
                    if (_scoringPhase) ...[
                      _actionButton(
                        emoji: '✓',
                        label: '确认结算',
                        sub: '生成胜负战报',
                        color: WqTheme.green,
                        onTap: _confirmTerritoryResult,
                      ),
                      SizedBox(width: 8.w),
                      _actionButton(
                        emoji: '↩',
                        label: '继续下棋',
                        sub: '退出点目',
                        color: Colors.white,
                        onTap: () => setState(() {
                          _scoringPhase = false;
                          _scoreSummary = null;
                        }),
                      ),
                    ] else if (_over) ...[
                      _actionButton(
                        emoji: '📋',
                        label: '看看战报',
                        sub: '3+1复盘卡',
                        color: WqTheme.sun,
                        onTap: _showSettlement,
                      ),
                      SizedBox(width: 8.w),
                      _actionButton(
                        emoji: '🎬',
                        label: '逐手复盘',
                        sub: '含试下研究',
                        color: WqTheme.greenSoft,
                        onTap: () => Get.to(() => WeiqiReplayPage(
                              moves: _replayMoves,
                              notes: _replayNotes,
                              marks: _replayMarks,
                              grades: _replayGrades,
                              better: _replayBetter,
                              n: _game.n,
                            )),
                      ),
                      SizedBox(width: 8.w),
                      _actionButton(
                        emoji: '🔄',
                        label: '再来一局',
                        sub: '重新开始',
                        color: Colors.white,
                        onTap: _resetGame,
                      ),
                    ] else ...[
                      if (_isAi)
                        _actionButton(
                          emoji: '💡',
                          label: '问棋棋',
                          sub: '剩 $_helpLeft 次',
                          color: WqTheme.sun,
                          onTap: _useHelp,
                        )
                      else
                        _actionButton(
                          emoji: _turn == 1 ? '⚫' : '⚪',
                          label: '轮到${_turn == 1 ? '孩子' : '家长'}',
                          sub: '点棋盘落子',
                          color:
                              _turn == 1 ? WqTheme.sunSoft : WqTheme.skySoft,
                        ),
                      SizedBox(width: 6.w),
                      if (_isTerritory) ...[
                        _actionButton(
                          emoji: '⏸',
                          label: '虚手',
                          sub: '停一手Pass',
                          color: WqTheme.pinkSoft,
                          onTap: _handlePass,
                        ),
                        SizedBox(width: 6.w),
                      ],
                      _actionButton(
                        emoji: '↩',
                        label: '悔棋',
                        sub: '退回一步',
                        color: Colors.white,
                        onTap: _undo,
                      ),
                      SizedBox(width: 6.w),
                      _actionButton(
                        emoji: _isTerritory ? '🧮' : '✓',
                        label: _isTerritory ? '点目' : '结束',
                        sub: _isTerritory ? '数子判胜负' : '生成复盘卡',
                        color: WqTheme.greenSoft,
                        onTap: () => _isTerritory
                            ? _enterScoringPhase()
                            : _endGame('review'),
                      ),
                    ],
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
    required Color color,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 6.5.h, horizontal: 2.w),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(14.r),
            border: Border.all(color: WqTheme.ink, width: 2.2),
            boxShadow: const [
              BoxShadow(
                color: WqTheme.ink,
                offset: Offset(3, 3),
                blurRadius: 0,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                emoji,
                style: TextStyle(fontSize: 15.sp),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w900,
                  color: WqTheme.ink,
                ),
              ),
              Text(
                sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.sp,
                  fontWeight: FontWeight.w700,
                  color: WqTheme.inkSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
