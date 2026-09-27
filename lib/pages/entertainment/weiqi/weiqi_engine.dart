import 'dart:math';

/// 围棋规则引擎（纯 Dart，可直接单元测试）。
/// 棋盘状态：0=空 1=黑 2=白；支持气/连接/提子/打劫/禁入点(自杀)。
/// 索引：idx = y * n + x，与原型的 JS 引擎一一对应。
class WqGame {
  final int n;
  final List<int> s;
  int ko = -1; // 打劫禁着点（-1 表示无）
  int last = -1; // 最后一手（-1 表示无）
  int capBlack = 0; // 黑方累计提子数（提走的白子）
  int capWhite = 0; // 白方累计提子数（提走的黑子）

  WqGame({this.n = 9}) : s = List.filled(n * n, 0);

  WqGame clone() {
    final g = WqGame(n: n);
    for (var i = 0; i < s.length; i++) {
      g.s[i] = s[i];
    }
    g.ko = ko;
    g.last = last;
    g.capBlack = capBlack;
    g.capWhite = capWhite;
    return g;
  }

  void restoreFrom(WqGame snap) {
    for (var i = 0; i < s.length; i++) {
      s[i] = snap.s[i];
    }
    ko = snap.ko;
    last = snap.last;
    capBlack = snap.capBlack;
    capWhite = snap.capWhite;
  }

  int xOf(int i) => i % n;
  int yOf(int i) => i ~/ n;

  List<int> nbrs(int i) {
    final x = xOf(i), y = yOf(i);
    final r = <int>[];
    if (x > 0) r.add(i - 1);
    if (x < n - 1) r.add(i + 1);
    if (y > 0) r.add(i - n);
    if (y < n - 1) r.add(i + n);
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

  int stoneCount() {
    var c = 0;
    for (final v in s) {
      if (v != 0) c++;
    }
    return c;
  }
}

class WqPlayResult {
  final bool ok;
  final String reason; // 'occupied' | 'ko' | 'suicide' | 'offboard'
  final List<int> captured;

  const WqPlayResult({required this.ok, this.reason = '', this.captured = const []});
}

class WqSimCap {
  final List<int> s;
  final List<int> cap;
  final int myLibs;

  const WqSimCap({required this.s, required this.cap, required this.myLibs});
}

/// 拟人 AI：会抓住提子/逃子的机会，也会按「级位」犯该犯的错。
/// [skill] 0~1：1 接近不犯错，越低越「迷糊」。移植自原型 aiPick。
class WqAi {
  WqAi._();

  static int? pickMove(WqGame g, int color, double skill) {
    final rnd = Random();
    final s = g.s;
    final pMiss = (1 - skill) * 0.55 + 0.06;
    final scored = <_Scored>[];
    for (var i = 0; i < g.n * g.n; i++) {
      if (s[i] != 0) continue;
      final r = g.simCap(i, color);
      if (r == null) continue;
      double sc = rnd.nextDouble() * 6;
      sc += r.cap.length * 100;
      if (r.myLibs == 1) sc -= 85; // 不主动送吃
      // 打吃对方（对方大组更优先）
      final opp = 3 - color;
      double atariGain = 0;
      final seen = <int>{};
      for (var j = 0; j < g.n * g.n; j++) {
        if (r.s[j] == opp && !seen.contains(j)) {
          final gg = g.groupOn(r.s, j);
          seen.addAll(gg);
          if (g.libsOn(r.s, gg).length == 1) {
            atariGain = max(atariGain, 42.0 + gg.length * 8);
          }
        }
      }
      sc += atariGain;
      // 救自己的打吃
      List<int>? ownAtari;
      final seen2 = <int>{};
      for (final nb in g.nbrs(i)) {
        if (s[nb] == color && !seen2.contains(nb)) {
          final gg = g.groupAt(nb);
          seen2.addAll(gg);
          if (g.libsOf(gg).length == 1) ownAtari = gg;
        }
      }
      if (ownAtari != null && r.myLibs >= 2) sc += 72;
      // 粘住自己的棋，贴近最后一手
      double adj = 0;
      for (final nb in g.nbrs(i)) {
        if (s[nb] == color) adj += 6;
      }
      if (g.last >= 0) {
        final d = (g.xOf(i) - g.xOf(g.last)).abs() + (g.yOf(i) - g.yOf(g.last)).abs();
        adj += max(0, 8 - d * 2);
      }
      sc += adj;
      scored.add(_Scored(i, sc, sc - r.cap.length * 100 - atariGain));
    }
    if (scored.isEmpty) return null;
    scored.sort((a, b) => b.sc.compareTo(a.sc));
    if (rnd.nextDouble() < pMiss) {
      // 犯错：从「平庸着法」里挑一个不算太离谱的
      final soft = scored.where((m) => m.missSafe > -40).toList();
      final pool = soft.isNotEmpty ? soft : scored;
      return pool[min(pool.length - 1, 1 + rnd.nextInt(4))].i;
    }
    return scored[0].i;
  }

  /// 求助目标：最值得下的点（提子 > 逃子）。
  static WqHint? hintTarget(WqGame g, int color) {
    final s = g.s;
    final seen = <int>{};
    // 1) 能一手提掉的对方棋组
    for (var j = 0; j < g.n * g.n; j++) {
      if (s[j] == 3 - color && !seen.contains(j)) {
        final gg = g.groupAt(j);
        seen.addAll(gg);
        final lb = g.libsOf(gg);
        if (lb.length == 1) {
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
      if (bestPt != null) {
        return WqHint(type: 'escape', pt: bestPt, grp: ownAtari);
      }
    }
    return null;
  }
}

class _Scored {
  final int i;
  final double sc;
  final double missSafe;

  _Scored(this.i, this.sc, this.missSafe);
}

class WqHint {
  final String type; // 'capture' | 'escape'
  final int pt;
  final List<int> grp;

  const WqHint({required this.type, required this.pt, required this.grp});
}
