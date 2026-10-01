import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'weiqi_board.dart';
import 'weiqi_engine.dart';
import 'weiqi_panda.dart';
import 'weiqi_sfx.dart';
import 'weiqi_play_page.dart';
import 'weiqi_theme.dart';
import 'weiqi_widgets.dart';

/// 对局回放：逐手重演刚下完的棋，关键手附棋棋讲解，
/// 帮初学者看清「哪一步走得好、哪一步吃亏了、怎么走更好」。
class WeiqiReplayPage extends StatefulWidget {
  /// 每一手的（颜色, 落点），从空盘开始顺序重演
  final List<({int color, int point})> moves;

  /// 关键手的讲解：着手序号（0 基）→ 讲解文字
  final Map<int, String> notes;

  /// 讲解标记：着手序号 → 要圈出的「最后一口气」位置
  final Map<int, int> marks;

  const WeiqiReplayPage({
    super.key,
    required this.moves,
    this.notes = const {},
    this.marks = const {},
  });

  @override
  State<WeiqiReplayPage> createState() => _WeiqiReplayPageState();
}

class _WeiqiReplayPageState extends State<WeiqiReplayPage> {
  late WqGame _game;
  int _idx = 0; // 已重演的手数（0 = 空盘）
  bool _justCaptured = false;

  @override
  void initState() {
    super.initState();
    _game = WqGame();
  }

  /// 重演到第 [idx] 手（从空盘顺序重放，引擎保证与实际对局一致）
  void _seek(int idx) {
    final clamped = idx.clamp(0, widget.moves.length);
    if (clamped == _idx) return;
    final forward = clamped > _idx;
    _game = WqGame();
    for (var k = 0; k < clamped; k++) {
      final m = widget.moves[k];
      _game.tryPlay(m.point, m.color);
    }
    setState(() {
      _idx = clamped;
      _justCaptured = clamped > 0 && widget.notes[clamped - 1] != null;
    });
    if (forward) WqSfx.stone();
  }

  /// 当前这手（_idx-1）的讲解
  String get _caption {
    if (_idx == 0) {
      return '这是我们刚下完的棋！点「下一手」，棋棋陪你一步一步回顾吧。';
    }
    final move = widget.moves[_idx - 1];
    final who = move.color == 1 ? '你' : '棋棋';
    final note = widget.notes[_idx - 1];
    if (note != null) {
      final hasMark = widget.marks.containsKey(_idx - 1);
      return '第 $_idx 手（$who）：$note${hasMark ? '（棋盘上橙色圈就是它）' : ''}';
    }
    return '第 $_idx 手（$who）落子，稳稳的一步。';
  }

  WqPandaMood get _mood {
    if (_idx == 0) return WqPandaMood.happy;
    if (_justCaptured) return WqPandaMood.cheer;
    return WqPandaMood.happy;
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.moves.length;
    final atEnd = _idx >= total;
    return Scaffold(
      backgroundColor: WqTheme.cream,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
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
                          '对局回放 · 一起复盘',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: WqTheme.ink,
                          ),
                        ),
                        Text(
                          '看看每一步发生了什么',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: WqTheme.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                  WqChip.sun(text: '第 $_idx / $total 手'),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
              child: Row(
                children: [
                  WqChip(text: '你提子 ${_game.capBlack}'),
                  const SizedBox(width: 6),
                  WqChip.grape(text: '棋棋提子 ${_game.capWhite}'),
                ],
              ),
            ),
            Flexible(
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
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                child: WeiqiBoardView(
                  stones: _game.s,
                  lastMove: _idx > 0 ? widget.moves[_idx - 1].point : -1,
                  blinkPoints: _idx > 0 && widget.marks.containsKey(_idx - 1)
                      ? {widget.marks[_idx - 1]!}
                      : const {},
                  capByBlack: _game.capBlack,
                  capByWhite: _game.capWhite,
                ),
              ),
            ),
            // 进度滑杆：直接拖到想看的第几手
            if (total > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
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
                    activeColor: WqTheme.green,
                    inactiveColor: const Color(0xFFE2E7EF),
                    label: '第 $_idx 手',
                    onChanged: (v) => _seek(v.round()),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
              child: Row(
                children: [
                  WqIconButton(
                    icon: Icons.first_page_rounded,
                    size: 44,
                    onTap: _idx > 0 ? () => _seek(0) : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: WqGhostButton(
                      text: '‹ 上一手',
                      height: 44,
                      fontSize: 14,
                      onTap: _idx > 0 ? () => _seek(_idx - 1) : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: WqPrimaryButton(
                      text: atEnd ? '已经到终局啦' : '下一手 ›',
                      height: 46,
                      fontSize: 15,
                      color: atEnd ? WqTheme.inkFaint : WqTheme.greenBright,
                      deep: atEnd ? WqTheme.inkSoft : WqTheme.greenDeep,
                      onTap: atEnd ? null : () => _seek(_idx + 1),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                  14, 0, 14, MediaQuery.of(context).padding.bottom + 12),
              child: Row(
                children: [
                  Expanded(
                    child: WqPrimaryButton(
                      text: '再来一局',
                      height: 44,
                      fontSize: 14,
                      onTap: () {
                        // 一路退回棋妙岛主页，再开新局（无论从复盘卡还是主页进入）
                        Get.until((route) =>
                            route.isFirst ||
                            route.settings.name == '/WeiqiHomePage');
                        Get.to(() =>
                            const WeiqiPlayPage(opponent: WqOpponent.ai));
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
