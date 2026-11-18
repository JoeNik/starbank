import 'dart:math';

/// 对局规则模式枚举
enum WqRuleMode {
  /// 吃子棋模式：先提走指定颗数棋子获胜（启蒙核心玩法）
  capture,

  /// 标准围地（数子/点目）模式：按终局子空合计与贴目判定胜负（商业标准围棋玩法）
  territory,
}

/// 围棋规则引擎（纯 Dart，可直接单元测试）。
/// 棋盘状态：0=空 1=黑 2=白；支持气/连接/提子/打劫/禁入点(自杀)/虚手(Pass)/让子(Handicap)/领地计算。
/// 索引：idx = y * n + x。
class WqGame {
  final int n;
  final List<int> s;
  int ko = -1; // 打劫禁着点（-1 表示无）
  int last = -1; // 最后一手（-1 表示无）
  int capBlack = 0; // 黑方累计提子数（提走的白子）
  int capWhite = 0; // 白方累计提子数（提走的黑子）
  int consecutivePasses = 0; // 连续虚手（停一手）次数，达到 2 次即终局
  int handicap = 0; // 让子数（0 表示分先，2~9 表示黑方让子）

  WqGame({this.n = 9}) : s = List.filled(n * n, 0);

  /// 克隆当前棋局快照
  WqGame clone() {
    final g = WqGame(n: n);
    for (var i = 0; i < s.length; i++) {
      g.s[i] = s[i];
    }
    g.ko = ko;
    g.last = last;
    g.capBlack = capBlack;
    g.capWhite = capWhite;
    g.consecutivePasses = consecutivePasses;
    g.handicap = handicap;
    return g;
  }

  /// 从快照恢复棋盘状态
  void restoreFrom(WqGame snap) {
    for (var i = 0; i < s.length; i++) {
      s[i] = snap.s[i];
    }
    ko = snap.ko;
    last = snap.last;
    capBlack = snap.capBlack;
    capWhite = snap.capWhite;
    consecutivePasses = snap.consecutivePasses;
    handicap = snap.handicap;
  }

  int xOf(int i) => i % n;
  int yOf(int i) => i ~/ n;

  /// 获取相邻交叉点列表（上下左右）
  List<int> nbrs(int i) {
    final x = xOf(i), y = yOf(i);
    final r = <int>[];
    if (x > 0) r.add(i - 1);
    if (x < n - 1) r.add(i + 1);
    if (y > 0) r.add(i - n);
    if (y < n - 1) r.add(i + n);
    return r;
  }

  /// 获取对角交叉点列表（用于真假眼位与虎口判定）
  List<int> diagNbrs(int i) {
    final x = xOf(i), y = yOf(i);
    final r = <int>[];
    if (x > 0 && y > 0) r.add((y - 1) * n + (x - 1));
    if (x < n - 1 && y > 0) r.add((y - 1) * n + (x + 1));
    if (x > 0 && y < n - 1) r.add((y + 1) * n + (x - 1));
    if (x < n - 1 && y < n - 1) r.add((y + 1) * n + (x + 1));
    return r;
  }

  /// i 点所在棋组（同色连通块）
  List<int> groupAt(int i) => groupOn(s, i);

  List<int> groupOn(List<int> board, int i) {
    final c = board[i];
    final seen = <int>{i};
    final st = <int>[i];
    final out = <int>[];
    while (st.isNotEmpty) {
      final k = st.removeLast();
      out.add(k);
      for (final nb in nbrs(k)) {
        if (board[nb] == c && !seen.contains(nb)) {
          seen.add(nb);
          st.add(nb);
        }
      }
    }
    return out;
  }

  /// 棋组的气点集合
  Set<int> libsOf(List<int> group) => libsOn(s, group);

  Set<int> libsOn(List<int> board, List<int> group) {
    final l = <int>{};
    for (final k in group) {
      for (final nb in nbrs(k)) {
        if (board[nb] == 0) l.add(nb);
      }
    }
    return l;
  }

  /// 摆放标准星位让子（支持 2~9 子，9/13/19 路自适应）
  void setupHandicap(int count) {
    for (var i = 0; i < s.length; i++) {
      s[i] = 0;
    }
    ko = -1;
    last = -1;
    capBlack = 0;
    capWhite = 0;
    consecutivePasses = 0;
    final clamped = count.clamp(0, 9);
    handicap = clamped < 2 ? 0 : clamped;
    if (handicap == 0) return;

    final edge = n >= 13 ? 3 : 2;
    final far = n - 1 - edge;
    final mid = n ~/ 2;
    int pt(int x, int y) => y * n + x;

    // 传统让子星位顺序：右上、左下、右下、左上、天元、左中、右中、上中、下中
    final starOrder = <int>[
      pt(far, edge), // 右上
      pt(edge, far), // 左下
      pt(far, far), // 右下
      pt(edge, edge), // 左上
      pt(mid, mid), // 天元
      pt(edge, mid), // 左边星
      pt(far, mid), // 右边星
      pt(mid, edge), // 上边星
      pt(mid, far), // 下边星
    ];

    List<int> chosen;
    if (handicap == 5) {
      chosen = [starOrder[0], starOrder[1], starOrder[2], starOrder[3], starOrder[4]];
    } else if (handicap == 6) {
      chosen = [
        starOrder[0],
        starOrder[1],
        starOrder[2],
        starOrder[3],
        starOrder[5],
        starOrder[6],
      ];
    } else if (handicap == 7) {
      chosen = [
        starOrder[0],
        starOrder[1],
        starOrder[2],
        starOrder[3],
        starOrder[5],
        starOrder[6],
        starOrder[4],
      ];
    } else if (handicap == 8) {
      chosen = [
        starOrder[0],
        starOrder[1],
        starOrder[2],
        starOrder[3],
        starOrder[5],
        starOrder[6],
        starOrder[7],
        starOrder[8],
      ];
    } else {
      chosen = starOrder.take(handicap).toList();
    }

    for (final p in chosen) {
      if (p >= 0 && p < s.length) s[p] = 1;
    }
  }

  /// 虚手（停一手 Pass）
  void pass(int color) {
    ko = -1;
    last = -1;
    consecutivePasses++;
  }

  /// 落子（含提子/劫/禁入点判定）。失败时不改变棋盘状态。
  WqPlayResult tryPlay(int? i, int color) {
    if (i == null || i < 0 || i >= n * n) {
      return const WqPlayResult(ok: false, reason: 'offboard');
    }
    if (s[i] != 0) return const WqPlayResult(ok: false, reason: 'occupied');
    if (ko == i) return const WqPlayResult(ok: false, reason: 'ko');
    s[i] = color;
    final opp = 3 - color;
    var captured = <int>[];
    for (final nb in nbrs(i)) {
      if (s[nb] == opp) {
        final gg = groupAt(nb);
        if (libsOf(gg).isEmpty) {
          for (final k in gg) {
            captured.add(k);
          }
        }
      }
    }
    captured = captured.toSet().toList();
    if (captured.isEmpty && libsOf(groupAt(i)).isEmpty) {
      s[i] = 0;
      return const WqPlayResult(ok: false, reason: 'suicide');
    }
    for (final k in captured) {
      s[k] = 0;
    }
    final my = groupAt(i);
    ko = (captured.length == 1 && my.length == 1 && libsOf(my).length == 1)
        ? captured[0]
        : -1;
    last = i;
    consecutivePasses = 0;
    if (color == 1) {
      capBlack += captured.length;
    } else {
      capWhite += captured.length;
    }
    return WqPlayResult(ok: true, captured: captured);
  }

  /// 纯模拟：不处理劫，返回落子后的棋盘快照（用于 AI 评估）。
  WqSimCap? simCap(int i, int color) {
    if (s[i] != 0) return null;
    if (ko == i) return null;
    final t = List<int>.from(s);
    t[i] = color;
    final opp = 3 - color;
    var cap = <int>[];
    for (final nb in nbrs(i)) {
      if (t[nb] == opp) {
        final gg = groupOn(t, nb);
        if (libsOn(t, gg).isEmpty) {
          for (final k in gg) {
            cap.add(k);
          }
        }
      }
    }
    cap = cap.toSet().toList();
    if (cap.isEmpty && libsOn(t, groupOn(t, i)).isEmpty) return null;
    for (final k in cap) {
      t[k] = 0;
    }
    return WqSimCap(s: t, cap: cap, myLibs: libsOn(t, groupOn(t, i)).length);
  }

  /// 判断空点 [i] 是否是 [color] 方的真眼（防止 AI 自填真眼）
  bool isTrueEye(int i, int color) {
    if (s[i] != 0) return false;
    for (final nb in nbrs(i)) {
      if (s[nb] != color) return false;
    }
    final diags = diagNbrs(i);
    final opp = 3 - color;
    var oppDiag = 0;
    for (final d in diags) {
      if (s[d] == opp) oppDiag++;
    }
    // 角部或边上不能有对方斜控制点，中腹最多允许 1 个对方对角子
    final onEdge = diags.length < 4;
    if (onEdge && oppDiag > 0) return false;
    if (!onEdge && oppDiag > 1) return false;
    return true;
  }

  int stoneCount() {
    var c = 0;
    for (final v in s) {
      if (v != 0) c++;
    }
    return c;
  }
}

/// 标准围棋棋盘坐标标签（如 A1, D4，字母跳过 I）
String wqCoordLabel(int pt, int n) {
  if (pt < 0) return '虚手(Pass)';
  const cols = 'ABCDEFGHJKLMNOPQRST';
  final x = pt % n;
  final y = pt ~/ n;
  final colChar = x < cols.length ? cols[x] : '?';
  final rowNum = n - y;
  return '$colChar$rowNum';
}

class WqPlayResult {
  final bool ok;
  final String reason; // 'occupied' | 'ko' | 'suicide' | 'offboard'
  final List<int> captured;

  const WqPlayResult({
    required this.ok,
    this.reason = '',
    this.captured = const [],
  });
}

class WqSimCap {
  final List<int> s;
  final List<int> cap;
  final int myLibs;

  const WqSimCap({
    required this.s,
    required this.cap,
    required this.myLibs,
  });
}

/// 形势判断与终局点目结算结果
class WqScoreSummary {
  final int n;
  final int blackStones; // 存活黑子数
  final int whiteStones; // 存活白子数
  final int blackTerritory; // 黑方围空数
  final int whiteTerritory; // 白方围空数
  final int neutralPoints; // 公共单官数
  final double komi; // 白方贴目
  final List<int> ownerMap; // 每个点的领地归属：0=无 1=黑空 2=白空
  final Set<int> deadStones; // 被判定为死子的点集合

  const WqScoreSummary({
    required this.n,
    required this.blackStones,
    required this.whiteStones,
    required this.blackTerritory,
    required this.whiteTerritory,
    required this.neutralPoints,
    required this.komi,
    required this.ownerMap,
    required this.deadStones,
  });

  /// 黑方子空合计（中国规则盘面子空皆地）
  int get blackArea => blackStones + blackTerritory;

  /// 白方子空合计
  int get whiteArea => whiteStones + whiteTerritory;

  /// 黑方最终总分
  double get blackTotal => blackArea.toDouble();

  /// 白方最终总分（含贴目）
  double get whiteTotal => whiteArea + komi;

  /// 黑方领先目数（正数为黑胜，负数为白胜）
  double get blackLead => blackTotal - whiteTotal;

  /// 黑方是否获胜
  bool get isBlackWin => blackLead > 0;
}

/// 商业级围棋形势判断与终局点目估算器
class WqTerritoryEstimator {
  WqTerritoryEstimator._();

  /// 根据路数与让子数返回标准贴目（分先：9路 5.5 目，13路 6.5 目，19路 7.5 目；让子局 0.5 目）
  static double defaultKomi(int n, {int handicap = 0}) {
    if (handicap >= 2) return 0.5;
    if (n <= 9) return 5.5;
    if (n <= 13) return 6.5;
    return 7.5;
  }

  /// 自动推断盘面上的死子（气数极少且被对方活棋团团包围、做不出两眼的孤子）
  static Set<int> detectAutoDeadStones(WqGame g) {
    final dead = <int>{};
    final visited = <int>{};
    for (var i = 0; i < g.n * g.n; i++) {
      final c = g.s[i];
      if (c == 0 || visited.contains(i)) continue;
      final grp = g.groupAt(i);
      visited.addAll(grp);
      final libs = g.libsOf(grp);

      // 1) 只剩 1 口气且子数较少，几乎必死
      if (libs.length == 1 && grp.length <= 4) {
        // 检查唯一气点落子后是否也无法逃出（征子或闷吃）
        final esc = g.simCap(libs.first, c);
        if (esc == null || esc.myLibs <= 1) {
          dead.addAll(grp);
          continue;
        }
      }

      // 2) 子数 <= 3 且气 <= 2，四周全被对方强棋包围
      if (grp.length <= 3 && libs.length <= 2) {
        var oppAround = 0;
        var friendlyAround = 0;
        for (final pt in libs) {
          for (final nb in g.nbrs(pt)) {
            if (grp.contains(nb)) continue;
            if (g.s[nb] == 3 - c) oppAround++;
            if (g.s[nb] == c) friendlyAround++;
          }
        }
        if (oppAround >= libs.length * 2 && friendlyAround == 0) {
          dead.addAll(grp);
        }
      }
    }
    return dead;
  }

  /// 计算盘面形势、双方领地与胜负结果
  /// [manualDead]：玩家手动切换的死子集合；若 [autoDetectDead] 为 true 则先做自动死子识别
  static WqScoreSummary estimate(
    WqGame g, {
    Set<int>? deadStones,
    double? komi,
    bool includeInfluence = false,
  }) {
    final effectiveDead = deadStones ?? detectAutoDeadStones(g);
    final effectiveKomi = komi ?? defaultKomi(g.n, handicap: g.handicap);

    // 移除死子后的虚拟盘面
    final board = List<int>.from(g.s);
    for (final d in effectiveDead) {
      if (d >= 0 && d < board.length) board[d] = 0;
    }

    final ownerMap = List<int>.filled(g.n * g.n, 0);
    final visitedEmpty = <int>{};

    // Flood-fill 遍历所有连通空点块
    for (var i = 0; i < g.n * g.n; i++) {
      if (board[i] != 0 || visitedEmpty.contains(i)) continue;
      final region = <int>[];
      final queue = <int>[i];
      visitedEmpty.add(i);
      var touchesBlack = false;
      var touchesWhite = false;

      while (queue.isNotEmpty) {
        final cur = queue.removeLast();
        region.add(cur);
        for (final nb in g.nbrs(cur)) {
          final v = board[nb];
          if (v == 0) {
            if (!visitedEmpty.contains(nb)) {
              visitedEmpty.add(nb);
              queue.add(nb);
            }
          } else if (v == 1) {
            touchesBlack = true;
          } else if (v == 2) {
            touchesWhite = true;
          }
        }
      }

      if (touchesBlack && !touchesWhite) {
        for (final pt in region) {
          ownerMap[pt] = 1;
        }
      } else if (touchesWhite && !touchesBlack) {
        for (final pt in region) {
          ownerMap[pt] = 2;
        }
      } else if (includeInfluence && (touchesBlack || touchesWhite)) {
        // 对局中开启「形势判断」时，对尚未完全封口的空点按辐射影响力估算领地倾向
        for (final pt in region) {
          final inf = _pointInfluence(g, board, pt);
          if (inf >= 2.2) {
            ownerMap[pt] = 1;
          } else if (inf <= -2.2) {
            ownerMap[pt] = 2;
          }
        }
      }
    }

    var bStones = 0, wStones = 0, bTerr = 0, wTerr = 0, neutral = 0;
    for (var i = 0; i < g.n * g.n; i++) {
      if (board[i] == 1) {
        bStones++;
      } else if (board[i] == 2) {
        wStones++;
      } else {
        if (ownerMap[i] == 1) {
          bTerr++;
        } else if (ownerMap[i] == 2) {
          wTerr++;
        } else {
          neutral++;
        }
      }
    }

    return WqScoreSummary(
      n: g.n,
      blackStones: bStones,
      whiteStones: wStones,
      blackTerritory: bTerr,
      whiteTerritory: wTerr,
      neutralPoints: neutral,
      komi: effectiveKomi,
      ownerMap: ownerMap,
      deadStones: effectiveDead,
    );
  }

  /// 计算单个空点受黑白棋子的距离辐射影响值（正数偏黑，负数偏白）
  static double _pointInfluence(WqGame g, List<int> board, int pt) {
    final px = g.xOf(pt), py = g.yOf(pt);
    var score = 0.0;
    for (var j = 0; j < g.n * g.n; j++) {
      final c = board[j];
      if (c == 0) continue;
      final dist = (px - g.xOf(j)).abs() + (py - g.yOf(j)).abs();
      if (dist == 0 || dist > 4) continue;
      final weight = 1.0 / dist;
      score += (c == 1 ? weight : -weight) * 2.4;
    }
    return score;
  }
}

/// 拟人 AI 引擎：支持「吃子棋」与「标准围地」双规则模式，具备真眼保护、金角银边布局与收官判断。
/// [skill] 0~1：1 接近不犯错，越低越「迷糊」。
class WqAi {
  WqAi._();

  static int? pickMove(
    WqGame g,
    int color,
    double skill, {
    Random? rnd,
    WqRuleMode mode = WqRuleMode.capture,
  }) {
    final random = rnd ?? Random();
    final s = g.s;
    final opp = 3 - color;
    final pMiss = skill >= 0.99 ? 0.0 : (1 - skill) * 0.50 + 0.04;
    final scored = <_Scored>[];

    for (var i = 0; i < g.n * g.n; i++) {
      if (s[i] != 0) continue;
      final r = g.simCap(i, color);
      if (r == null) continue;

      // 严禁在不需要提子时自填己方真眼
      final isOwnEye = g.isTrueEye(i, color);
      if (isOwnEye && r.cap.isEmpty) {
        continue;
      }

      double sc = random.nextDouble() * 4.5;
      // 1) 提子高优奖励
      sc += r.cap.length * 105;

      // 2) 自投虎口（送吃）严厉惩罚
      if (r.myLibs == 1) {
        sc -= r.cap.isNotEmpty ? 20 : 95;
      }

      // 3) 打吃对方（对方大块更优先）
      double atariGain = 0;
      final seen = <int>{};
      for (var j = 0; j < g.n * g.n; j++) {
        if (r.s[j] == opp && !seen.contains(j)) {
          final gg = g.groupOn(r.s, j);
          seen.addAll(gg);
          if (g.libsOn(r.s, gg).length == 1) {
            atariGain = max(atariGain, 44.0 + gg.length * 9);
          }
        }
      }
      sc += atariGain;

      // 4) 拯救己方被打吃的棋组
      List<int>? ownAtari;
      final seen2 = <int>{};
      for (final nb in g.nbrs(i)) {
        if (s[nb] == color && !seen2.contains(nb)) {
          final gg = g.groupAt(nb);
          seen2.addAll(gg);
          if (g.libsOf(gg).length == 1) ownAtari = gg;
        }
      }
      if (ownAtari != null && r.myLibs >= 2) {
        sc += 76 + ownAtari.length * 8;
      }

      // 5) 连接与长气价值
      double adj = 0;
      for (final nb in g.nbrs(i)) {
        if (s[nb] == color) adj += 5.5;
      }
      sc += min(r.myLibs, 5) * 3.0;

      // 6) 标准围地模式专属策略（金角银边、三四线拆边、收官边界、避免过度凝形）
      if (mode == WqRuleMode.territory) {
        sc += _evaluateTerritoryValue(g, i, color, r);
      } else {
        // 吃子棋模式：贴近最后一手展开肉搏
        if (g.last >= 0) {
          final d =
              (g.xOf(i) - g.xOf(g.last)).abs() + (g.yOf(i) - g.yOf(g.last)).abs();
          adj += max(0, 8 - d * 2);
        }
      }
      sc += adj;

      scored.add(_Scored(i, sc, sc - r.cap.length * 105 - atariGain));
    }

    if (scored.isEmpty) return null;
    scored.sort((a, b) => b.sc.compareTo(a.sc));

    // 标准围地模式下：如果盘面已经下满大半且最高分着法也毫无价值（全在填自己空），则选择虚手 Pass
    if (mode == WqRuleMode.territory &&
        g.stoneCount() > g.n * g.n * 0.52 &&
        scored.first.sc < 12.0) {
      return null;
    }

    if (random.nextDouble() < pMiss) {
      final soft = scored.where((m) => m.missSafe > -35).toList();
      final pool = soft.isNotEmpty ? soft : scored;
      return pool[min(pool.length - 1, 1 + random.nextInt(3))].i;
    }
    return scored[0].i;
  }

  /// 评估标准围地模式下的布局、围空与收官价值
  static double _evaluateTerritoryValue(
      WqGame g, int i, int color, WqSimCap sim) {
    final n = g.n;
    final x = g.xOf(i), y = g.yOf(i);
    final distEdgeX = min(x, n - 1 - x);
    final distEdgeY = min(y, n - 1 - y);
    final minLine = min(distEdgeX, distEdgeY); // 0=一线(边线), 1=二线, 2=三线, 3=四线
    var val = 0.0;

    // 金角银边草肚皮：三线（2）与四线（3）在序盘中价值最高，一线（0）早下扣分
    final stones = g.stoneCount();
    if (stones < n * n * 0.35) {
      if (minLine == 0) {
        val -= 18; // 序盘不走死亡一线
      } else if (minLine == 1) {
        val -= 4;
      } else if (minLine == 2) {
        val += 14; // 三线实地线
      } else if (minLine == 3 && n >= 13) {
        val += 15; // 13/19路四线势力线
      }
      // 角部星位/小目区域额外加分
      if (distEdgeX >= 2 && distEdgeX <= 3 && distEdgeY >= 2 && distEdgeY <= 3) {
        val += 10;
      }
    }

    // 避免凝形（四邻已有太多同色子且不提子、不救子时属于效率低下的蠢棋）
    var sameNbrs = 0;
    var oppNbrs = 0;
    for (final nb in g.nbrs(i)) {
      if (g.s[nb] == color) sameNbrs++;
      if (g.s[nb] == 3 - color) oppNbrs++;
    }
    if (sameNbrs >= 3 && oppNbrs == 0 && sim.cap.isEmpty) {
      val -= 28; // 在自己厚实的空里自填一子
    }

    // 收官边界：同时接触黑白双方或靠近对方棋子封口的位置加分
    if (sameNbrs >= 1 && oppNbrs >= 1) {
      val += 14; // 双方交界官子要津
    } else if (sameNbrs == 0 && oppNbrs == 0) {
      // 拆边/占大场：周围 2 格内较为空旷时加分
      var nearCount = 0;
      for (var dy = -2; dy <= 2; dy++) {
        for (var dx = -2; dx <= 2; dx++) {
          final nx = x + dx, ny = y + dy;
          if (nx >= 0 && nx < n && ny >= 0 && ny < n) {
            if (g.s[ny * n + nx] != 0) nearCount++;
          }
        }
      }
      if (nearCount == 0 && minLine >= 2) {
        val += 12; // 占空旷大场
      } else if (nearCount <= 2 && minLine >= 2) {
        val += 8; // 守角或拆边
      }
    }

    return val;
  }

  /// 求助目标：最值得下的点（提子 > 逃子 > 围地好点）。
  static WqHint? hintTarget(
    WqGame g,
    int color, {
    WqRuleMode mode = WqRuleMode.capture,
  }) {
    final s = g.s;
    final seen = <int>{};
    // 1) 能一手提掉的对方棋组
    for (var j = 0; j < g.n * g.n; j++) {
      if (s[j] == 3 - color && !seen.contains(j)) {
        final gg = g.groupAt(j);
        seen.addAll(gg);
        final lb = g.libsOf(gg);
        if (lb.length == 1 && g.simCap(lb.first, color) != null) {
          return WqHint(type: 'capture', pt: lb.first, grp: gg);
        }
      }
    }
    // 2) 自己被打吃的棋组：找长气最多的逃跑点
    List<int>? ownAtari;
    seen.clear();
    for (var j = 0; j < g.n * g.n; j++) {
      if (s[j] == color && !seen.contains(j)) {
        final gg = g.groupAt(j);
        seen.addAll(gg);
        if (g.libsOf(gg).length == 1) ownAtari = gg;
      }
    }
    if (ownAtari != null) {
      final lb = g.libsOf(ownAtari);
      int? bestPt;
      var bestN = -1;
      for (final p in lb) {
        final r = g.simCap(p, color);
        if (r != null && r.myLibs > bestN) {
          bestN = r.myLibs;
          bestPt = p;
        }
      }
      if (bestPt != null && bestN >= 2) {
        return WqHint(type: 'escape', pt: bestPt, grp: ownAtari);
      }
    }
    // 3) 若无紧急提子/逃子，由高水平 AI 推荐当前局面最佳选点（占角/打吃/收官）
    final bestMove = pickMove(g, color, 1.0, mode: mode);
    if (bestMove != null) {
      return WqHint(type: 'territory', pt: bestMove, grp: [bestMove]);
    }
    return null;
  }
}

/// 棋棋的棋力档位
class WqAiLevel {
  final String name; // 档位名
  final String persona; // 形象名/级位
  final String desc; // 一句话介绍
  final double skill;

  const WqAiLevel(this.name, this.persona, this.desc, this.skill);
}

/// 陪下棋力档位（对齐少儿围棋协会级位体系，5 档渐进）
const List<WqAiLevel> wqAiLevels = [
  WqAiLevel('启蒙', '25级·新手村', '常常看漏打吃，最适合刚学会规则的你', 0.55),
  WqAiLevel('初级', '18级·小棋童', '懂得基本逃跑，开始注意保护自己的棋', 0.70),
  WqAiLevel('中级', '12级·上进生', '很少放跑猎物，会主动打吃和占角围地', 0.82),
  WqAiLevel('高级', '5级·小高手', '抢先提子、金角银边寸步不让，需要认真应对', 0.92),
  WqAiLevel('大师', '1段·职业范', '一步不漏，算路精准，把它当成大 Boss 挑战吧', 1.0),
];

class _Scored {
  final int i;
  final double sc;
  final double missSafe;

  _Scored(this.i, this.sc, this.missSafe);
}

class WqHint {
  final String type; // 'capture' | 'escape' | 'territory'
  final int pt;
  final List<int> grp;

  const WqHint({required this.type, required this.pt, required this.grp});
}
