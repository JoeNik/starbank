import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'weiqi_board.dart';
import 'weiqi_engine.dart';
import 'weiqi_panda.dart';
import 'weiqi_play_page.dart';
import 'weiqi_service.dart';
import 'weiqi_sfx.dart';
import 'weiqi_theme.dart';
import 'weiqi_widgets.dart';

/// 商业级对局回放与试下研究页：
/// 支持逐手重演、AI 每手评级与正解圈选、手数/坐标/形势领地开关、
/// 多局历史棋谱库切换，以及「🧪 试下研究（变化图沙盘）」。
class WeiqiReplayPage extends StatefulWidget {
  final List<({int color, int point})> moves;
  final Map<int, String> notes;
  final Map<int, int> marks;
  final Map<int, String> grades;
  final Map<int, int> better;
  final int n;

  const WeiqiReplayPage({
    super.key,
    required this.moves,
    this.notes = const {},
    this.marks = const {},
    this.grades = const {},
    this.better = const {},
    this.n = 9,
  });

  @override
  State<WeiqiReplayPage> createState() => _WeiqiReplayPageState();
}

class _WeiqiReplayPageState extends State<WeiqiReplayPage> {
  late int _n;
  late List<({int color, int point})> _moves;
  late Map<int, String> _notes;
  late Map<int, int> _marks;
  late Map<int, String> _grades;
  late Map<int, int> _better;

  late WqGame _game;
  int _idx = 0; // 已重演的手数（0 = 空盘）
  bool _justCaptured = false;
  bool _showNumbers = true;
  bool _showTerritory = false;

  /// 试下研究模式（变化图沙盘）
  bool _studyMode = false;
  int _studyTurn = 1;
  final List<({int color, int point})> _studyMoves = [];

  @override
  void initState() {
    super.initState();
    _n = widget.n;
    _moves = List.of(widget.moves);
    _notes = Map.of(widget.notes);
    _marks = Map.of(widget.marks);
    _grades = Map.of(widget.grades);
    _better = Map.of(widget.better);
    _game = WqGame(n: _n);
  }

  /// 切换到历史棋谱库中的某一局
  void _loadHistoryRecord(int historyIndex) {
    if (!Get.isRegistered<WeiqiService>()) return;
    final svc = Get.find<WeiqiService>();
    final rec = svc.loadGameAt(historyIndex);
    if (rec == null) return;
    WqSfx.pop();
    setState(() {
      _n = rec.n;
      _moves = List.of(rec.moves);
      _notes = Map.of(rec.notes);
      _marks = Map.of(rec.marks);
      _grades = Map.of(rec.grades);
      _better = Map.of(rec.better);
      _idx = 0;
      _studyMode = false;
      _studyMoves.clear();
      _game = WqGame(n: _n);
    });
  }

  /// 重演到第 [idx] 手
  void _seek(int idx) {
    final clamped = idx.clamp(0, _moves.length);
    if (clamped == _idx && !_studyMode) return;
    final forward = clamped > _idx;
    _studyMode = false;
    _studyMoves.clear();
    _game = WqGame(n: _n);
    for (var k = 0; k < clamped; k++) {
      final m = _moves[k];
      if (m.point >= 0) {
        _game.tryPlay(m.point, m.color);
      } else {
        _game.pass(m.color);
      }
    }
    setState(() {
      _idx = clamped;
      _justCaptured = clamped > 0 && _notes[clamped - 1] != null;
    });
    if (forward) WqSfx.stone();
  }

  /// 开启或退出「试下研究（变化图沙盘）」
  void _toggleStudyMode() {
    WqSfx.pop();
    if (_studyMode) {
      // 退回原谱当前手数
      _seek(_idx);
      return;
    }
    final nextColor =
        _idx == 0 ? 1 : (3 - _moves[_idx - 1].color);
    setState(() {
      _studyMode = true;
      _studyTurn = nextColor;
      _studyMoves.clear();
    });
  }

  void _onStudyTap(int pt) {
    if (!_studyMode) return;
    final r = _game.tryPlay(pt, _studyTurn);
    if (!r.ok) {
      WqSfx.oops();
      return;
    }
    WqSfx.stone();
    setState(() {
      _studyMoves.add((color: _studyTurn, point: pt));
      _studyTurn = 3 - _studyTurn;
    });
  }

  Map<int, int> _buildMoveNumbers() {
    if (!_showNumbers) return const {};
    final map = <int, int>{};
    if (_studyMode) {
      for (var k = 0; k < _studyMoves.length; k++) {
        final pt = _studyMoves[k].point;
        if (_game.s[pt] != 0) map[pt] = k + 1;
      }
      return map;
    }
    for (var k = 0; k < _idx && k < _moves.length; k++) {
      final pt = _moves[k].point;
      if (pt >= 0 && _game.s[pt] != 0) {
        map[pt] = k + 1;
      }
    }
    return map;
  }

  String get _caption {
    if (_studyMode) {
      return '🧪 试下研究模式：已试下 ${_studyMoves.length} 手，现在轮到${_studyTurn == 1 ? '黑棋' : '白棋'}落子。点「退回原谱」可立即恢复原棋局。';
    }
    if (_idx == 0) {
      return '这是我们刚下完的棋！点「下一手」逐步回顾，或点「试下研究」在任意一步摆出变化图。';
    }
    final move = _moves[_idx - 1];
    final who = move.color == 1 ? '你' : '棋棋';
    final idx = _idx - 1;
    final note = _notes[idx];
    final grade = _gradeIcon(idx);
    final coord = wqCoordLabel(move.point, _n);
    final prefix = move.color == 1 ? (grade.isEmpty ? '' : '$grade ') : '🤍 ';
    if (_idx >= _moves.length && _grades.isNotEmpty) {
      var great = 0, good = 0, miss = 0, danger = 0;
      _grades.forEach((_, g) {
        switch (g) {
          case 'great':
            great++;
            break;
          case 'good':
            good++;
            break;
          case 'miss':
            miss++;
            break;
          case 'danger':
            danger++;
            break;
        }
      });
      final String verdict;
      if (miss == 0 && danger == 0) {
        verdict = '几乎没漏掉机会，下得非常漂亮！';
      } else if (miss + danger <= 2) {
        verdict = '整体下得不错，再抓住 ${miss + danger} 个机会就更完美啦！';
      } else {
        verdict = '下一次试试：看到打吃先提子、自己的棋只剩一口气先逃跑！';
      }
      return '本局回顾完啦！✨好手 $great 次，👍打吃 $good 次，💡错过提子 $miss 次，⚠️危险 $danger 次。$verdict';
    }
    if (note != null) {
      final hasMark = _marks.containsKey(idx);
      final hasBetter = _better.containsKey(idx);
      return '第 $_idx 手（$who·$coord）$prefix：$note'
          '${hasBetter ? '（橙色圈是更好的下法）' : hasMark ? '（棋盘上橙色圈就是它）' : ''}';
    }
    return '第 $_idx 手（$who·$coord）$prefix落子，稳稳的一步。';
  }

  String _gradeIcon(int idx) {
    final g = _grades[idx];
    switch (g) {
      case 'great':
        return '✨';
      case 'good':
        return '👍';
      case 'miss':
        return '💡';
      case 'danger':
        return '⚠️';
      default:
        return '';
    }
  }

  WqPandaMood get _mood {
    if (_studyMode) return WqPandaMood.think;
    if (_idx == 0) return WqPandaMood.happy;
    if (_justCaptured) return WqPandaMood.cheer;
    return WqPandaMood.happy;
  }

  /// 打开历史棋谱库列表
  void _openHistorySheet() {
    if (!Get.isRegistered<WeiqiService>()) return;
    final svc = Get.find<WeiqiService>();
    final list = svc.gameHistory;
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
                maxHeight: MediaQuery.of(ctx).size.height * 0.62,
              ),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: WqTheme.cream,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: WqTheme.ink, width: 3.0),
                boxShadow: const [
                  BoxShadow(color: WqTheme.ink, offset: Offset(6, 6)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '📚 历史棋谱库（最近 ${list.length} 局）',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: WqTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (list.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('还没有保存的棋谱记录哦'),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: list.length,
                        itemBuilder: (ctx, i) {
                          final rec = svc.loadGameAt(i);
                          if (rec == null) return const SizedBox.shrink();
                          final dateStr = rec.playedAt.length >= 16
                              ? rec.playedAt.substring(5, 16).replaceAll('T', ' ')
                              : '最近对局';
                          final isWin = rec.result == 'win';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: GestureDetector(
                              onTap: () {
                                Navigator.of(ctx).pop();
                                _loadHistoryRecord(i);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: WqTheme.ink, width: 2.0),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: WqTheme.ink,
                                      offset: Offset(3, 3),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isWin
                                            ? WqTheme.sun
                                            : WqTheme.greenSoft,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: WqTheme.ink, width: 1.5),
                                      ),
                                      child: Text(
                                        '${rec.n}路',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w900,
                                          color: WqTheme.ink,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            rec.scoreSummary.isNotEmpty
                                                ? rec.scoreSummary
                                                : '${rec.mode == 'territory' ? '标准围地' : '吃子棋'} · 共 ${rec.moves.length} 手',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w900,
                                              color: WqTheme.ink,
                                            ),
                                          ),
                                          Text(
                                            '$dateStr · 共 ${rec.moves.length} 手',
                                            style: const TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w700,
                                              color: WqTheme.inkSoft,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.chevron_right_rounded,
                                        color: WqTheme.ink),
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
    final total = _moves.length;
    final atEnd = _idx >= total;
    final territorySummary = _showTerritory
        ? WqTerritoryEstimator.estimate(_game, includeInfluence: true)
        : null;

    return Scaffold(
      backgroundColor: WqTheme.cream,
      body: SafeArea(
        child: Column(
          children: [
            // 顶部导航与棋谱库入口
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Row(
                children: [
                  WqIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    size: 40,
                    onTap: () => Get.back(),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '对局复盘 · 试下研究',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: WqTheme.ink,
                          ),
                        ),
                        Text(
                          '逐手复盘 · 变化图沙盘',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: WqTheme.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _openHistorySheet,
                    child: WqChip.pink(text: '📚 棋谱库 ▾'),
                  ),
                  const SizedBox(width: 6),
                  WqChip.sun(text: '第 $_idx / $total 手'),
                ],
              ),
            ),

            // 辅助功能条（提子统计 + 手数/形势/试下研究开关）
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    WqChip(text: '黑提 ${_game.capBlack}'),
                    const SizedBox(width: 6),
                    WqChip.grape(text: '白提 ${_game.capWhite}'),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => setState(() => _showNumbers = !_showNumbers),
                      child: WqChip(
                        text: _showNumbers ? '✓ 显示手数' : '显示手数',
                        bg: _showNumbers ? WqTheme.sun : Colors.white,
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () =>
                          setState(() => _showTerritory = !_showTerritory),
                      child: WqChip(
                        text: _showTerritory ? '✓ 形势领地' : '形势领地',
                        bg: _showTerritory ? WqTheme.green : Colors.white,
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: _toggleStudyMode,
                      child: WqChip(
                        text: _studyMode ? '↩ 退回原谱' : '🧪 试下研究',
                        bg: _studyMode ? WqTheme.coral : WqTheme.pinkSoft,
                        fg: _studyMode ? Colors.white : WqTheme.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 气泡槽
            SizedBox(
              height: 104,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                child: WqBubble(
                  text: _caption,
                  speaking: true,
                  mood: _mood,
                  maxLines: 3,
                  tail: true,
                ),
              ),
            ),

            // 棋盘视图
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                child: WeiqiBoardView(
                  n: _n,
                  stones: _game.s,
                  showCoords: true,
                  moveNumbers: _buildMoveNumbers(),
                  territoryOwnerMap: territorySummary?.ownerMap,
                  deadStones: territorySummary?.deadStones ?? const {},
                  lastMove: _studyMode
                      ? _game.last
                      : (_idx > 0 ? _moves[_idx - 1].point : -1),
                  blinkPoints: (!_studyMode && _idx > 0)
                      ? {
                          if (_better.containsKey(_idx - 1))
                            _better[_idx - 1]!
                          else if (_marks.containsKey(_idx - 1))
                            _marks[_idx - 1]!,
                        }
                      : const {},
                  capByBlack: _game.capBlack,
                  capByWhite: _game.capWhite,
                  onPointTap: _studyMode ? _onStudyTap : null,
                ),
              ),
            ),

            // 进度滑杆
            if (total > 0 && !_studyMode)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 9),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 15),
                  ),
                  child: Slider(
                    value: _idx.toDouble(),
                    min: 0,
                    max: total.toDouble(),
                    divisions: total > 1 ? total : null,
                    activeColor: WqTheme.ink,
                    inactiveColor: WqTheme.creamDeep,
                    label: '第 $_idx 手',
                    onChanged: (v) => _seek(v.round()),
                  ),
                ),
              ),

            // 步进控制按钮
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
              child: Row(
                children: [
                  WqIconButton(
                    icon: Icons.first_page_rounded,
                    size: 44,
                    onTap: _idx > 0 || _studyMode ? () => _seek(0) : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: WqGhostButton(
                      text: _studyMode ? '↩ 退出试下' : '‹ 上一手',
                      height: 44,
                      fontSize: 14,
                      onTap: _studyMode
                          ? () => _seek(_idx)
                          : (_idx > 0 ? () => _seek(_idx - 1) : null),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: WqPrimaryButton(
                      text: atEnd ? '已经到终局啦' : '下一手 ›',
                      height: 46,
                      fontSize: 15,
                      color: atEnd ? WqTheme.creamDeep : WqTheme.sun,
                      onTap: atEnd ? null : () => _seek(_idx + 1),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                14,
                0,
                14,
                MediaQuery.of(context).padding.bottom + 12,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: WqPrimaryButton(
                      text: '再来一局',
                      height: 44,
                      fontSize: 14,
                      color: WqTheme.green,
                      onTap: () {
                        Get.until((route) =>
                            route.isFirst ||
                            route.settings.name == '/WeiqiHomePage');
                        Get.to(
                            () => const WeiqiPlayPage(opponent: WqOpponent.ai));
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: WqGhostButton(
                      text: '返回小岛',
                      height: 44,
                      fontSize: 14,
                      onTap: () {
                        Get.until((route) =>
                            route.isFirst ||
                            route.settings.name == '/WeiqiHomePage');
                      },
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
