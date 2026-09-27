// 棋妙岛课程与题库数据。
// 9 路棋盘，索引 = y * 9 + x（天元 = 40）。
// 所有演示/挑战棋形均已按规则引擎验证：该提的提得掉、
// 该拒绝的（禁入点/打劫）会被拒绝。
import 'weiqi_engine.dart';

int _p(int x, int y) => y * 9 + x;

const int _w = 2;
const int _b = 1;

WqOp _put(int x, int y, int c) => WqOp.put(_p(x, y), c);
WqOp _try(int x, int y, int c) => WqOp.tryPut(_p(x, y), c);

/// 挑战目标
enum WqGoal {
  /// 提掉至少 [min] 颗子
  capture,

  /// 让 [target] 所在棋组的气 ≥ [minLibs]（逃子）
  escape,

  /// 一手同时打吃 ≥2 块对方棋组（双打）
  doubleAtari,
}

/// 演示操作
class WqOp {
  final bool reset;
  final int? point;
  final int? color;
  final bool tryOnly; // 演示性落子：可能被引擎拒绝（禁入点/打劫），用于教学

  const WqOp.put(this.point, this.color)
      : reset = false,
        tryOnly = false;
  const WqOp.tryPut(this.point, this.color)
      : reset = false,
        tryOnly = true;
  const WqOp.reset()
      : reset = true,
        point = null,
        color = null,
        tryOnly = false;
}

/// 「点亮所有的气」问答
class WqFindQuiz {
  final int target; // 目标棋子
  final List<String> missHints; // 答错时的两层引导
  final String doneText;

  const WqFindQuiz({
    required this.target,
    required this.missHints,
    required this.doneText,
  });
}

/// 动手落子挑战
class WqMoveQuiz {
  final int playerColor;
  final WqGoal goal;
  final int minCapture;
  final int minLibs;
  final int? goalPoint; // escape 目标棋组参照点
  final String prompt;
  final String doneText;
  final List<String> hints; // 失败时的引导

  const WqMoveQuiz({
    required this.playerColor,
    required this.goal,
    this.minCapture = 1,
    this.minLibs = 2,
    this.goalPoint,
    required this.prompt,
    required this.doneText,
    required this.hints,
  });
}

/// 课程步骤
class WqStep {
  final String caption;
  final String bubble; // 棋棋的话（TTS 播报）
  final List<WqOp> ops;
  final List<int> breathe; // 气点小灯
  final bool warn; // 打吃警示色
  final List<int> captureDemo; // 演示提子飞入口袋的目标点
  final WqFindQuiz? findQuiz;
  final WqMoveQuiz? moveQuiz;

  const WqStep({
    required this.caption,
    required this.bubble,
    this.ops = const [],
    this.breathe = const [],
    this.warn = false,
    this.captureDemo = const [],
    this.findQuiz,
    this.moveQuiz,
  });
}

class WqLesson {
  final String id;
  final String island;
  final int no;
  final String glyph; // 地图奖章上的单字
  final String title;
  final String subtitle;
  final List<String> teaches; // 结算页「学会了」
  final List<WqStep> steps;

  const WqLesson({
    required this.id,
    required this.island,
    required this.no,
    required this.glyph,
    required this.title,
    required this.subtitle,
    required this.teaches,
    required this.steps,
  });
}

/// 死活/吃子题
class WqPuzzle {
  final String id;
  final String tag;
  final String title;
  final String voice; // 语音读题
  final List<WqOp> setup;
  final int playerColor;
  final WqGoal goal;
  final int minCapture;
  final int minLibs;
  final int? goalPoint;
  final int zoneCenter; // L1 提示：区域微光中心
  final int answerPoint; // L2/L3 提示：闪烁点/演示点
  final List<String> hints;
  final String okText;

  const WqPuzzle({
    required this.id,
    required this.tag,
    required this.title,
    required this.voice,
    required this.setup,
    required this.playerColor,
    required this.goal,
    this.minCapture = 1,
    this.minLibs = 2,
    this.goalPoint,
    required this.zoneCenter,
    required this.answerPoint,
    required this.hints,
    required this.okText,
  });
}

// ============================================================
// 课程：第①岛 气之森林 / 第②岛 吃子竞技场
// ============================================================

final List<WqLesson> wqLessons = [
  // ---------- L1 棋子的呼吸（认识棋盘/气/打吃/提子） ----------
  WqLesson(
    id: 'l1',
    island: '第①岛 气之森林',
    no: 1,
    glyph: '气',
    title: '棋子的呼吸',
    subtitle: '认识棋盘 · 气 · 打吃 · 提子',
    teaches: ['气', '打吃', '提子'],
    steps: [
      WqStep(
        caption: '认识棋盘',
        bubble: '棋盘上每一个交叉点，都可以站一颗棋子士兵。看，白棋小士兵来啦！',
        ops: [_put(4, 4, _w)],
      ),
      WqStep(
        caption: '气 = 呼吸',
        bubble: '它紧挨着的 4 个空点，闪着绿色的小灯——这就是它的「气」，就像士兵的呼吸！',
        breathe: [_p(3, 4), _p(5, 4), _p(4, 3), _p(4, 5)],
      ),
      WqStep(
        caption: '气变少了',
        bubble: '黑棋站上了一个呼吸口！白棋现在只剩 3 口气啦。数一数？',
        ops: [_put(3, 4, _b)],
        breathe: [_p(5, 4), _p(4, 3), _p(4, 5)],
      ),
      WqStep(
        caption: '越来越紧张',
        bubble: '又被堵住一个，只剩 2 口气了……白棋有点紧张。',
        ops: [_put(5, 4, _b)],
        breathe: [_p(4, 3), _p(4, 5)],
      ),
      WqStep(
        caption: '打吃！',
        bubble: '只剩最后一口气！这叫「打吃」——就像有人捂住了士兵的鼻子，好危险！',
        ops: [_put(4, 3, _b)],
        breathe: [_p(4, 5)],
        warn: true,
      ),
      WqStep(
        caption: '提子！',
        bubble: '最后一口气也被堵住——气全没了，白棋就被「提」走啦！看它飞进了口袋。',
        ops: [_put(4, 5, _b)],
        captureDemo: [_p(4, 4)],
      ),
      WqStep(
        caption: '动手试试',
        bubble: '轮到你来啦！点一点：哪些点是白棋的「气」？把它们全部点亮！',
        ops: [WqOp.reset(), _put(4, 4, _w)],
        findQuiz: WqFindQuiz(
          target: _p(4, 4),
          missHints: [
            '差一点点！「气」是紧挨着白棋的空点，离得远的可不是哦～',
            '再看看：一定要紧挨着这颗白棋，才是它的呼吸呀！',
          ],
          doneText: '哇，4 口气全找齐！你已经是懂「气」的小棋手啦！',
        ),
      ),
      WqStep(
        caption: '你来提子',
        bubble: '太棒了！现在黑棋包围了它——点最后一口气，把它提走！',
        ops: [_put(3, 4, _b), _put(5, 4, _b), _put(4, 3, _b)],
        moveQuiz: WqMoveQuiz(
          playerColor: _b,
          goal: WqGoal.capture,
          prompt: '点最后一口气，提走它！',
          doneText: '提子成功！你亲手把气全堵住，赢下了第一颗棋子！这就是围棋最开心的魔法～',
          hints: [
            '数一数：白棋士兵还有几口气？',
            '它只剩最后一口气啦，点紧挨着它的那个空点！',
          ],
        ),
      ),
    ],
  ),

  // ---------- L2 逃出去（逃子/长气） ----------
  WqLesson(
    id: 'l2',
    island: '第①岛 气之森林',
    no: 2,
    glyph: '逃',
    title: '逃出去！',
    subtitle: '逃子 · 长气',
    teaches: ['逃子', '长气'],
    steps: [
      WqStep(
        caption: '被夹住了',
        bubble: '白棋小士兵被两面夹击！它还剩几口气？一起数一数。',
        ops: [_put(4, 4, _w), _put(3, 4, _b), _put(5, 4, _b)],
      ),
      WqStep(
        caption: '两口气',
        bubble: '对，还有 2 口气。被围住的士兵只要还有气，就不怕！',
        breathe: [_p(4, 3), _p(4, 5)],
      ),
      WqStep(
        caption: '打吃！',
        bubble: '黑棋又堵住一口——只剩最后 1 口气了，这叫「打吃」，快想想办法！',
        ops: [_put(4, 3, _b)],
        breathe: [_p(4, 5)],
        warn: true,
      ),
      WqStep(
        caption: '长出去！',
        bubble: '白棋往下长了一步！连成两颗，有 3 口气啦。逃跑的秘诀 = 让自己多口气。',
        ops: [_put(4, 5, _w)],
        breathe: [_p(3, 5), _p(5, 5), _p(4, 6)],
      ),
      WqStep(
        caption: '你来救它',
        bubble: '这次换你来当救兵！帮白棋士兵逃出去吧。',
        ops: [WqOp.reset(), _put(4, 4, _w), _put(3, 4, _b), _put(5, 4, _b), _put(4, 3, _b)],
        moveQuiz: WqMoveQuiz(
          playerColor: _w,
          goal: WqGoal.escape,
          goalPoint: _p(4, 4),
          minLibs: 2,
          prompt: '白棋只剩 1 口气了！点一个让它多口气、逃出去的地方。',
          doneText: '逃出来啦！多一口气的士兵就安全了！',
          hints: [
            '士兵往哪个空点跑，能带出新的气呢？',
            '往下逃跑试试——先数一数那个点自己有几口气！',
          ],
        ),
      ),
    ],
  ),

  // ---------- L7 危险的边线（边线/角/赶向边线） ----------
  WqLesson(
    id: 'l7',
    island: '第①岛 气之森林',
    no: 3,
    glyph: '边',
    title: '危险的边线',
    subtitle: '边线 · 角 · 赶向边线',
    teaches: ['边线', '赶向边线'],
    steps: [
      WqStep(
        caption: '认识边线',
        bubble: '棋盘最外圈的一条线叫「边线」，像一圈围墙。站在边线上的士兵，只有 3 口气！',
        ops: [_put(4, 0, _w)],
        breathe: [_p(3, 0), _p(5, 0), _p(4, 1)],
      ),
      WqStep(
        caption: '角上更少',
        bubble: '角上的士兵更可怜，只有 2 口气。所以下棋要先占角、再占边，中间最后来！',
        ops: [WqOp.reset(), _put(0, 0, _w)],
        breathe: [_p(1, 0), _p(0, 1)],
      ),
      WqStep(
        caption: '赶到边线',
        bubble: '黑棋把白棋往边线赶——靠墙的士兵，最容易被打吃！',
        ops: [WqOp.reset(), _put(4, 0, _w), _put(3, 0, _b), _put(5, 0, _b)],
        breathe: [_p(4, 1)],
        warn: true,
      ),
      WqStep(
        caption: '关上门',
        bubble: '堵住最后一口气，提走！把敌人往边线赶，是吃子的好办法哦。',
        ops: [_put(4, 1, _b)],
        captureDemo: [_p(4, 0)],
      ),
      WqStep(
        caption: '你来关门',
        bubble: '白棋又躲到了边线上！你来把它提走。',
        ops: [WqOp.reset(), _put(4, 0, _w), _put(3, 0, _b), _put(5, 0, _b)],
        moveQuiz: WqMoveQuiz(
          playerColor: _b,
          goal: WqGoal.capture,
          prompt: '点白棋最后一口气，把它提走！',
          doneText: '关门成功！靠边的士兵逃不掉啦。',
          hints: [
            '数一数：边线上的白棋还剩几口气？',
            '它下面紧挨着的那个交叉点，就是最后一口气！',
          ],
        ),
      ),
    ],
  ),

  // ---------- L3 大老虎的嘴（虎口） ----------
  WqLesson(
    id: 'l3',
    island: '第①岛 气之森林',
    no: 4,
    glyph: '虎',
    title: '大老虎的嘴',
    subtitle: '认识虎口',
    teaches: ['虎口'],
    steps: [
      WqStep(
        caption: '虎口形状',
        bubble: '三颗黑棋围出的这个形状，像不像大老虎张开的嘴？中间那个空点就是「虎口」。',
        ops: [_put(4, 3, _b), _put(3, 4, _b), _put(5, 4, _b)],
      ),
      WqStep(
        caption: '跳进虎口',
        bubble: '白棋跳进老虎嘴——它只剩 1 口气，下一步就要被吃掉啦！',
        ops: [_put(4, 4, _w)],
        breathe: [_p(4, 5)],
        warn: true,
      ),
      WqStep(
        caption: '一口吞掉',
        bubble: '黑棋轻轻一堵，就把白棋提走了。所以跳进虎口，是大忌哦！',
        ops: [_put(4, 5, _b)],
        captureDemo: [_p(4, 4)],
      ),
      WqStep(
        caption: '你来喂老虎',
        bubble: '白棋又跳进来了！快把老虎嘴合上！',
        ops: [WqOp.reset(), _put(4, 3, _b), _put(3, 4, _b), _put(5, 4, _b), _put(4, 4, _w)],
        moveQuiz: WqMoveQuiz(
          playerColor: _b,
          goal: WqGoal.capture,
          prompt: '白棋跳进了虎口！点最后一口气，把它提走！',
          doneText: '提走啦！以后你也可以用虎口保护自己的棋哦。',
          hints: [
            '白棋还剩几口气？它的气在哪个空点上？',
            '点紧挨着白棋的、最下面那个空点试试！',
          ],
        ),
      ),
    ],
  ),

  // ---------- L4 一手打两块（双打） ----------
  WqLesson(
    id: 'l4',
    island: '第②岛 吃子竞技场',
    no: 5,
    glyph: '双',
    title: '一手打两块',
    subtitle: '双打',
    teaches: ['双打'],
    steps: [
      WqStep(
        caption: '两颗白棋',
        bubble: '两颗白棋士兵站得很近，每颗都只剩 2 口气，而且有一口气是同一个点！',
        ops: [
          _put(3, 4, _w), _put(5, 4, _w),
          _put(3, 3, _b), _put(3, 5, _b),
          _put(5, 3, _b), _put(5, 5, _b),
        ],
      ),
      WqStep(
        caption: '双打！',
        bubble: '黑棋站上共同的那口气——一手同时打吃两块白棋！这就是「双打」！',
        ops: [_put(4, 4, _b)],
        breathe: [_p(2, 4), _p(6, 4)],
        warn: true,
      ),
      WqStep(
        caption: '救得了一边',
        bubble: '白棋救了一边……黑棋就提走另一边！下出双打，总会赢到东西。',
        ops: [_put(2, 4, _w), _put(6, 4, _b)],
        captureDemo: [_p(5, 4)],
      ),
      WqStep(
        caption: '你来双打',
        bubble: '轮到你出招啦！找到那个神奇的点，一手打吃两颗白棋！',
        ops: [
          WqOp.reset(),
          _put(3, 4, _w), _put(5, 4, _w),
          _put(3, 3, _b), _put(3, 5, _b),
          _put(5, 3, _b), _put(5, 5, _b),
        ],
        moveQuiz: WqMoveQuiz(
          playerColor: _b,
          goal: WqGoal.doubleAtari,
          prompt: '点一个点，同时打吃两颗白棋！',
          doneText: '好一个双打！对方只能救一边，你一定能提到子！',
          hints: [
            '找一找：两颗白棋共同的气在哪里？',
            '就是它们正中间的那个交叉点！',
          ],
        ),
      ),
    ],
  ),

  // ---------- L5 不能进去的陷阱（禁入点） ----------
  WqLesson(
    id: 'l5',
    island: '第②岛 吃子竞技场',
    no: 6,
    glyph: '禁',
    title: '不能进去的陷阱',
    subtitle: '禁入点',
    teaches: ['禁入点'],
    steps: [
      WqStep(
        caption: '围住的空点',
        bubble: '四颗白棋围住了一个空点。咦，黑棋能跳进去吗？',
        ops: [_put(4, 3, _w), _put(3, 4, _w), _put(5, 4, _w), _put(4, 5, _w)],
      ),
      WqStep(
        caption: '禁入点！',
        bubble: '黑棋跳进去立刻就没气了——站不住！这样的点叫「禁入点」，像陷阱，不能进。',
        ops: [_try(4, 4, _b)],
      ),
      WqStep(
        caption: '气尽就不一样',
        bubble: '换个局面：这两颗白棋被围得只剩最后 1 口气了！',
        ops: [
          WqOp.reset(),
          _put(3, 4, _w), _put(4, 4, _w),
          _put(2, 4, _b), _put(5, 4, _b),
          _put(3, 3, _b), _put(4, 3, _b), _put(3, 5, _b),
        ],
        breathe: [_p(4, 5)],
        warn: true,
      ),
      WqStep(
        caption: '提子不算送死',
        bubble: '黑棋跳进去，把两颗白棋全提走！记住：能提子的点，永远不是禁入点。',
        ops: [_put(4, 5, _b)],
        captureDemo: [_p(3, 4), _p(4, 4)],
      ),
      WqStep(
        caption: '你来判断',
        bubble: '同样的陷阱，这次白棋只剩 1 口气——你能下出那手「不算送死」的棋吗？',
        ops: [
          WqOp.reset(),
          _put(3, 4, _w), _put(4, 4, _w),
          _put(2, 4, _b), _put(5, 4, _b),
          _put(3, 3, _b), _put(4, 3, _b), _put(3, 5, _b),
        ],
        moveQuiz: WqMoveQuiz(
          playerColor: _b,
          goal: WqGoal.capture,
          prompt: '白棋只剩 1 口气了！点那个既能落子又能提子的点！',
          doneText: '答对啦！能提子的点永远可以下！',
          hints: [
            '先找一找：白棋的最后一口气在哪里？',
            '白棋最下面紧挨着的那个空点，就是它们的最后一口气！',
          ],
        ),
      ),
    ],
  ),

  // ---------- L6 交换玩具的规则（打劫） ----------
  WqLesson(
    id: 'l6',
    island: '第②岛 吃子竞技场',
    no: 7,
    glyph: '劫',
    title: '交换玩具的规则',
    subtitle: '打劫',
    teaches: ['打劫'],
    steps: [
      WqStep(
        caption: '一颗孤子',
        bubble: '白棋这颗小旗手只剩 1 口气了！黑棋只要堵住它左边的空点，就能提走它。',
        ops: [
          _put(3, 4, _w), _put(4, 3, _w), _put(4, 5, _w), _put(5, 4, _w),
          _put(6, 4, _b), _put(5, 3, _b), _put(5, 5, _b),
        ],
      ),
      WqStep(
        caption: '提走啦',
        bubble: '黑棋提走白旗手！可是注意——黑棋这颗子也只剩下 1 口气了。',
        ops: [_put(4, 4, _b)],
        captureDemo: [_p(5, 4)],
      ),
      WqStep(
        caption: '不能马上提回来',
        bubble: '白棋想马上提回来？规则说：不可以！就像交换玩具——你得先去别处下一手，再回来交换。这就是「打劫」。',
        ops: [_try(5, 4, _w)],
      ),
      WqStep(
        caption: '你来提劫',
        bubble: '轮到你啦：找到那手能提走白旗手的棋！',
        ops: [
          WqOp.reset(),
          _put(3, 4, _w), _put(4, 3, _w), _put(4, 5, _w), _put(5, 4, _w),
          _put(6, 4, _b), _put(5, 3, _b), _put(5, 5, _b),
        ],
        moveQuiz: WqMoveQuiz(
          playerColor: _b,
          goal: WqGoal.capture,
          prompt: '点那个能一手提走白旗手的点！',
          doneText: '提劫成功！别忘了：对方不能马上提回来哦。',
          hints: [
            '白旗手只剩哪一口气？',
            '它左边紧挨着的那个空点！',
          ],
        ),
      ),
    ],
  ),
];

// ============================================================
// 死活/吃子题（吃子竞技场闯关）
// ============================================================

final List<WqPuzzle> wqPuzzles = [
  WqPuzzle(
    id: 'pz1',
    tag: '吃子题 · L1',
    title: '一手提子',
    voice: '白棋的士兵只剩一口气啦！点一个能把它的气全堵住的地方。',
    setup: [_put(6, 2, _w), _put(5, 2, _b), _put(7, 2, _b), _put(6, 1, _b)],
    playerColor: _b,
    goal: WqGoal.capture,
    zoneCenter: _p(6, 2),
    answerPoint: _p(6, 3),
    hints: [
      '白棋被黑棋围住三面了……它还剩几个空点挨着它？',
      '紧挨着白棋的最后一个空点，就是答案！',
      '看棋棋变魔法——记住这种感觉哦！',
    ],
    okText: '提掉啦！你找到了它最后一口气！',
  ),
  WqPuzzle(
    id: 'pz2',
    tag: '逃子题 · L1',
    title: '帮士兵逃出来',
    voice: '白棋士兵被打吃了！你执白——点一个让它能多口气、逃出去的地方。',
    setup: [_put(4, 4, _w), _put(3, 4, _b), _put(5, 4, _b)],
    playerColor: _w,
    goal: WqGoal.escape,
    goalPoint: _p(4, 4),
    minLibs: 2,
    zoneCenter: _p(4, 4),
    answerPoint: _p(4, 5),
    hints: [
      '士兵只剩一口气了……往哪个空点跑，能带出新的气呢？',
      '往下逃跑试试，先数一数那个点自己有几口气！',
      '看棋棋变魔法——记住这种感觉哦！',
    ],
    okText: '逃出来啦！多一口气的士兵就安全了！',
  ),
  WqPuzzle(
    id: 'pz3',
    tag: '吃子题 · L2',
    title: '一口气提两颗',
    voice: '两颗相连的白棋只剩最后一口气啦！找到它，一口气提走两颗！',
    setup: [
      _put(3, 4, _w), _put(4, 4, _w),
      _put(2, 4, _b), _put(5, 4, _b),
      _put(3, 3, _b), _put(4, 3, _b), _put(3, 5, _b),
    ],
    playerColor: _b,
    goal: WqGoal.capture,
    zoneCenter: _p(3, 4),
    answerPoint: _p(4, 5),
    hints: [
      '这对白棋的气几乎都被堵住了……它们的最后一口气在哪里？',
      '看最下面——紧挨着白棋的那个空点！',
      '看棋棋变魔法——记住这种感觉哦！',
    ],
    okText: '好球！一口气提走两颗，这就是「双提」！',
  ),
  WqPuzzle(
    id: 'pz4',
    tag: '逃子题 · L2',
    title: '接力逃跑',
    voice: '两颗白棋只剩最后一口气！你执白，帮它们一起逃出去！',
    setup: [
      _put(3, 4, _w), _put(4, 4, _w),
      _put(2, 4, _b), _put(5, 4, _b),
      _put(3, 3, _b), _put(4, 3, _b), _put(3, 5, _b),
    ],
    playerColor: _w,
    goal: WqGoal.escape,
    goalPoint: _p(3, 4),
    minLibs: 2,
    zoneCenter: _p(3, 4),
    answerPoint: _p(4, 5),
    hints: [
      '两颗棋要一起跑——点一个能让整队都多口气的地方！',
      '往下长一个：和两颗白棋都挨着的那个空点！',
      '看棋棋变魔法——记住这种感觉哦！',
    ],
    okText: '逃出来啦！连在一起的队伍，有好几口气了！',
  ),
  WqPuzzle(
    id: 'pz5',
    tag: '双打题 · L2',
    title: '一网打尽',
    voice: '两颗白棋各只剩一口气，而且这两个「最后一口气」是同一个点！一手把它们全提走！',
    setup: [
      _put(3, 3, _w), _put(3, 5, _w),
      _put(2, 3, _b), _put(4, 3, _b),
      _put(3, 2, _b), _put(2, 5, _b), _put(4, 5, _b), _put(3, 6, _b),
    ],
    playerColor: _b,
    goal: WqGoal.capture,
    minCapture: 2,
    zoneCenter: _p(3, 4),
    answerPoint: _p(3, 4),
    hints: [
      '找一找：哪颗黑棋站下去，能同时堵住两颗白棋的气？',
      '两颗白棋正中间的那个交叉点！',
      '看棋棋变魔法——记住这种感觉哦！',
    ],
    okText: '好一个「双提」！一手棋赢了两颗子！',
  ),
  WqPuzzle(
    id: 'pz6',
    tag: '吃子题 · L2',
    title: '边线关门',
    voice: '白棋躲到了边线上！它只剩最后一口气啦，点那个点把它提走！',
    setup: [_put(4, 0, _w), _put(3, 0, _b), _put(5, 0, _b)],
    playerColor: _b,
    goal: WqGoal.capture,
    zoneCenter: _p(4, 0),
    answerPoint: _p(4, 1),
    hints: [
      '边线上的白棋还剩几口气？',
      '紧挨着白棋、靠里侧的那个空点！',
      '看棋棋变魔法——记住这种感觉哦！',
    ],
    okText: '关门成功！靠边的士兵逃不掉啦。',
  ),
  WqPuzzle(
    id: 'pz7',
    tag: '吃子题 · L2',
    title: '角落里的士兵',
    voice: '白棋躲进了棋盘的角落！角上只有 2 口气，一手就能提走它！',
    setup: [_put(0, 0, _w), _put(1, 0, _b)],
    playerColor: _b,
    goal: WqGoal.capture,
    zoneCenter: _p(0, 0),
    answerPoint: _p(0, 1),
    hints: [
      '角上的白棋只有 2 口气，黑棋已经堵住一个啦！',
      '紧挨着白棋、往下数的那个空点！',
      '看棋棋变魔法——记住这种感觉哦！',
    ],
    okText: '提走啦！角落是最容易被关住的地方。',
  ),
  WqPuzzle(
    id: 'pz8',
    tag: '逃子题 · L2',
    title: '向中腹逃跑',
    voice: '白棋在边线被打吃了！你执白——往中间逃跑，那里气最多！',
    setup: [_put(4, 5, _w), _put(4, 4, _b), _put(3, 5, _b), _put(5, 5, _b)],
    playerColor: _w,
    goal: WqGoal.escape,
    goalPoint: _p(4, 5),
    minLibs: 2,
    zoneCenter: _p(4, 5),
    answerPoint: _p(4, 6),
    hints: [
      '白棋只剩 1 口气了……往哪边逃跑能带来新的气？',
      '往棋盘中间长一个：白棋下面紧挨着的空点！',
      '看棋棋变魔法——记住这种感觉哦！',
    ],
    okText: '逃出来啦！往中间跑，气就多啦。',
  ),
];

/// 判断挑战是否达成
bool wqCheckGoal(
  WqGame g,
  WqGoal goal, {
  int playerColor = 1,
  int minCapture = 1,
  int minLibs = 2,
  int? goalPoint,
  List<int> captured = const [],
}) {
  switch (goal) {
    case WqGoal.capture:
      return captured.length >= minCapture;
    case WqGoal.escape:
      if (goalPoint == null || g.s[goalPoint] == 0) return false;
      return g.libsOf(g.groupAt(goalPoint)).length >= minLibs;
    case WqGoal.doubleAtari:
      final opp = 3 - playerColor;
      final seen = <int>{};
      var atariGroups = 0;
      for (var j = 0; j < g.n * g.n; j++) {
        if (g.s[j] == opp && !seen.contains(j)) {
          final gg = g.groupAt(j);
          seen.addAll(gg);
          if (g.libsOf(gg).length == 1) atariGroups++;
        }
      }
      return atariGroups >= 2;
  }
}
