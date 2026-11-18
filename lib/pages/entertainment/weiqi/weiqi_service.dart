import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../../../services/tts_service.dart';
import 'weiqi_data.dart';
import 'weiqi_engine.dart';
import 'weiqi_sfx.dart';

/// 少儿围棋段级位成长档案信息
class WqRankInfo {
  final String rank; // 如 '25级', '10级', '1段'
  final String title; // 称号，如 '启蒙小棋童'
  final int currentExp; // 当前总经验
  final int nextExp; // 下一级门槛经验
  final double progress; // 当前级位内进度 0.0 ~ 1.0

  const WqRankInfo({
    required this.rank,
    required this.title,
    required this.currentExp,
    required this.nextExp,
    required this.progress,
  });
}

/// 棋妙岛服务：纯学习模块。
/// 只持久化「学习进度 / 练习记录 / 历史棋谱库 / 模块内设置」，没有任何金币或可消费积分；
/// 课程星级仅表示该课的完成质量，不与宿主 App 的星星（奖励货币）互通。
class WeiqiService extends GetxService {
  static const String _boxName = 'weiqi_progress';

  Box? _box;

  // ---- 学习进度 ----
  /// 每课星级（1~3，取历史最好成绩）
  final RxMap<String, int> lessonStars = <String, int>{}.obs;

  /// 已答对的题
  final RxSet<String> solvedPuzzles = <String>{}.obs;

  /// 藏宝箱（做错的题，复习答对后移出）
  final RxSet<String> wrongPuzzles = <String>{}.obs;

  // ================= 历史棋谱库（最近 20 局 + 主页「上局复盘」入口） =================

  Map<String, dynamic>? _lastGame;

  /// 多局历史棋谱列表（最新一局在最前，最多保存 20 局）
  final RxList<Map<String, dynamic>> gameHistory =
      <Map<String, dynamic>>[].obs;

  /// 保存最近一局的回放数据（每手颜色/落点 + 关键手讲解），并记入历史棋谱库
  void saveLastGame(
    List<({int color, int point})> moves,
    Map<int, String> notes, [
    Map<int, int> marks = const {},
    Map<int, String> grades = const {},
    Map<int, int> better = const {},
    int boardSize = 9,
    String mode = 'capture',
    String result = 'review',
    String scoreSummary = '',
  ]) {
    final record = {
      'n': boardSize,
      'mode': mode,
      'result': result,
      'scoreSummary': scoreSummary,
      'moves': [
        for (final m in moves) {'c': m.color, 'p': m.point}
      ],
      'notes': {for (final e in notes.entries) e.key.toString(): e.value},
      'marks': {for (final e in marks.entries) e.key.toString(): e.value},
      'grades': {for (final e in grades.entries) e.key.toString(): e.value},
      'better': {for (final e in better.entries) e.key.toString(): e.value},
      'playedAt': DateTime.now().toIso8601String(),
    };
    _lastGame = record;
    gameHistory.insert(0, record);
    if (gameHistory.length > 20) {
      gameHistory.removeRange(20, gameHistory.length);
    }
    _save();
  }

  Map<String, dynamic>? get lastGame => _lastGame;

  /// 解析单条棋谱 Map 为强类型回放元组
  ({
    int n,
    String mode,
    String result,
    String scoreSummary,
    String playedAt,
    List<({int color, int point})> moves,
    Map<int, String> notes,
    Map<int, int> marks,
    Map<int, String> grades,
    Map<int, int> better,
  })? _parseGameMap(Map<String, dynamic>? g) {
    if (g == null) return null;
    final rawMoves = g['moves'];
    if (rawMoves is! List || rawMoves.isEmpty) return null;
    final moves = <({int color, int point})>[
      for (final m in rawMoves)
        (
          color: (m['c'] as num).toInt(),
          point: (m['p'] as num).toInt(),
        )
    ];
    final notes = <int, String>{
      for (final e in ((g['notes'] as Map?) ?? const {}).entries)
        int.parse(e.key.toString()): e.value.toString(),
    };
    final marks = <int, int>{
      for (final e in ((g['marks'] as Map?) ?? const {}).entries)
        int.parse(e.key.toString()): (e.value as num).toInt(),
    };
    final grades = <int, String>{
      for (final e in ((g['grades'] as Map?) ?? const {}).entries)
        int.parse(e.key.toString()): e.value.toString(),
    };
    final better = <int, int>{
      for (final e in ((g['better'] as Map?) ?? const {}).entries)
        int.parse(e.key.toString()): (e.value as num).toInt(),
    };
    return (
      n: (g['n'] as num?)?.toInt() ?? 9,
      mode: (g['mode'] as String?) ?? 'capture',
      result: (g['result'] as String?) ?? 'review',
      scoreSummary: (g['scoreSummary'] as String?) ?? '',
      playedAt: (g['playedAt'] as String?) ?? '',
      moves: moves,
      notes: notes,
      marks: marks,
      grades: grades,
      better: better,
    );
  }

  /// 从持久化数据恢复最近一局回放参数；无记录返回 null
  ({
    int n,
    List<({int color, int point})> moves,
    Map<int, String> notes,
    Map<int, int> marks,
    Map<int, String> grades,
    Map<int, int> better,
  })? loadLastGame() {
    final parsed = _parseGameMap(_lastGame);
    if (parsed == null) return null;
    return (
      n: parsed.n,
      moves: parsed.moves,
      notes: parsed.notes,
      marks: parsed.marks,
      grades: parsed.grades,
      better: parsed.better,
    );
  }

  /// 读取历史棋谱库中第 [index] 局的完整信息
  ({
    int n,
    String mode,
    String result,
    String scoreSummary,
    String playedAt,
    List<({int color, int point})> moves,
    Map<int, String> notes,
    Map<int, int> marks,
    Map<int, String> grades,
    Map<int, int> better,
  })? loadGameAt(int index) {
    if (index < 0 || index >= gameHistory.length) return null;
    return _parseGameMap(gameHistory[index]);
  }

  // ---- 对局记录（陪下） ----
  final RxInt playWins = 0.obs;
  final RxInt playLosses = 0.obs;
  final RxInt playDraws = 0.obs;

  /// 每日学习活动：日期 -> {lesson, puzzles, correct, games}
  final RxMap<String, Map<String, int>> dailyActivity =
      <String, Map<String, int>>{}.obs;

  // ---- 模块内设置（含商业级对局设置） ----
  final RxBool voiceOn = true.obs; // 语音讲解
  final RxBool remindOn = true.obs; // 对局中失误提醒
  final RxBool sfxOn = true.obs; // 音效
  final RxBool atariLightsOn = true.obs; // 对局中被打吃警示灯
  final RxInt aiLevelIndex = 1.obs; // 棋棋棋力档位（0..4）
  final RxInt winCaptures = 3.obs; // 吃子棋目标：先提走对方几颗算赢（2~10）
  final RxInt boardSize = 9.obs; // 对局棋盘路数：9/13/19
  final RxString ruleMode = 'capture'.obs; // 对局规则：'capture'吃子棋 | 'territory'标准围地
  final RxBool showCoords = true.obs; // 棋盘坐标显示（A-T / 1-19）
  final RxBool showMoveNumbers = false.obs; // 棋子手数显示
  final RxBool confirmMove = false.obs; // 13/19路防误触十字准星二次确认落子（家长小屋可开启）
  final RxInt handicap = 0.obs; // 让子数：0(分先) / 2 / 3 / 4 / 5 / 9
  final RxInt timeLimitMinutes = 0.obs; // 棋钟时限（分钟）：0无限时 / 5快棋 / 15慢棋

  /// 当前选择的规则模式枚举
  WqRuleMode get currentRuleMode =>
      ruleMode.value == 'territory' ? WqRuleMode.territory : WqRuleMode.capture;

  WeiqiService() {
    voiceOn.listen((v) {
      if (!v) stopSpeak();
      _save();
    });
    remindOn.listen((_) => _save());
    sfxOn.listen((v) {
      WqSfx.enabled = v;
      _save();
    });
    atariLightsOn.listen((_) => _save());
    aiLevelIndex.listen((_) => _save());
    winCaptures.listen((_) => _save());
    boardSize.listen((_) => _save());
    ruleMode.listen((_) => _save());
    showCoords.listen((_) => _save());
    showMoveNumbers.listen((_) => _save());
    confirmMove.listen((_) => _save());
    handicap.listen((_) => _save());
    timeLimitMinutes.listen((_) => _save());
  }

  Future<WeiqiService> init() async {
    try {
      _box = await Hive.openBox(_boxName);
    } catch (e) {
      debugPrint('打开 $boxDisplayName 失败，尝试恢复: $e');
      try {
        await Hive.deleteBoxFromDisk(_boxName);
      } catch (_) {}
      _box = await Hive.openBox(_boxName);
    }
    WqSfx.enabled = sfxOn.value;
    _load();
    return this;
  }

  String get boxDisplayName => _boxName;

  // ================= 少儿围棋段级位成长计算 =================

  /// 计算当前孩子的围棋级位与成长进度（25级 -> 1段）
  WqRankInfo get rankInfo {
    final exp = totalLessonStars * 15 +
        solvedPuzzles.length * 12 +
        playWins.value * 20 +
        (playLosses.value + playDraws.value) * 6;

    const tiers = [
      (exp: 0, rank: '25级', title: '启蒙小棋童'),
      (exp: 60, rank: '20级', title: '气之观察者'),
      (exp: 140, rank: '15级', title: '吃子小猎手'),
      (exp: 240, rank: '10级', title: '手筋修行生'),
      (exp: 360, rank: '5级', title: '棋妙岛先锋'),
      (exp: 500, rank: '2级', title: '围地小统帅'),
      (exp: 680, rank: '1级', title: '冲段预备役'),
      (exp: 900, rank: '1段', title: '棋妙小国手'),
    ];

    var idx = 0;
    for (var i = 0; i < tiers.length; i++) {
      if (exp >= tiers[i].exp) idx = i;
    }
    final cur = tiers[idx];
    if (idx >= tiers.length - 1) {
      return WqRankInfo(
        rank: cur.rank,
        title: cur.title,
        currentExp: exp,
        nextExp: cur.exp,
        progress: 1.0,
      );
    }
    final next = tiers[idx + 1];
    final span = (next.exp - cur.exp).clamp(1, 99999);
    final prog = ((exp - cur.exp) / span).clamp(0.0, 1.0);
    return WqRankInfo(
      rank: cur.rank,
      title: cur.title,
      currentExp: exp,
      nextExp: next.exp,
      progress: prog,
    );
  }

  // ================= 课程 =================

  /// 记录一次完课，返回本次获得的星级（misses 越少星越多）
  int recordLesson(String lessonId, int misses) {
    final stars = misses == 0 ? 3 : (misses <= 3 ? 2 : 1);
    final best = lessonStars[lessonId] ?? 0;
    if (stars > best) lessonStars[lessonId] = stars;
    _bumpDay('lesson', 1);
    _save();
    return stars;
  }

  bool isLessonUnlocked(int index) {
    if (index <= 0) return true;
    final prev = wqLessonIdAt(index - 1);
    return prev != null && (lessonStars[prev] ?? 0) > 0;
  }

  int get totalLessonStars => lessonStars.values.fold(0, (a, b) => a + b);

  int get completedLessonCount => lessonStars.values.where((v) => v > 0).length;

  // ================= 死活题 =================

  void recordPuzzle(String puzzleId, bool solved) {
    if (solved) {
      solvedPuzzles.add(puzzleId);
      wrongPuzzles.remove(puzzleId);
    } else {
      wrongPuzzles.add(puzzleId);
    }
    _bumpDay('puzzles', 1);
    if (solved) _bumpDay('correct', 1);
    _save();
  }

  // ================= 陪下对局 =================

  void recordGame({required String result}) {
    switch (result) {
      case 'win':
        playWins.value++;
        break;
      case 'lose':
        playLosses.value++;
        break;
      default:
        playDraws.value++;
    }
    _bumpDay('games', 1);
    _save();
  }

  // ================= 统计 =================

  String _todayKey() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }

  Map<String, int> _todayActivity() =>
      dailyActivity.putIfAbsent(_todayKey(), () => {});

  void _bumpDay(String key, int delta) {
    final day = _todayActivity();
    day[key] = (day[key] ?? 0) + delta;
  }

  /// 连续学习天数（今天有活动或昨天有活动都算连续起点）
  int streakDays() {
    var streak = 0;
    final now = DateTime.now();
    for (var i = 0; i < 400; i++) {
      final date = now.subtract(Duration(days: i));
      final key =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final act = dailyActivity[key];
      final active = act != null && act.values.any((v) => v > 0);
      if (active) {
        streak++;
      } else if (i == 0) {
        continue;
      } else {
        break;
      }
    }
    return streak;
  }

  /// 最近 [days] 天的学习汇总（家长周报用）
  Map<String, int> weeklySummary({int days = 7}) {
    final now = DateTime.now();
    var lesson = 0, puzzles = 0, correct = 0, games = 0, activeDays = 0;
    for (var i = 0; i < days; i++) {
      final date = now.subtract(Duration(days: i));
      final key =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final act = dailyActivity[key];
      if (act == null) continue;
      lesson += act['lesson'] ?? 0;
      puzzles += act['puzzles'] ?? 0;
      correct += act['correct'] ?? 0;
      games += act['games'] ?? 0;
      if (act.values.any((v) => v > 0)) activeDays++;
    }
    return {
      'lessons': lesson,
      'puzzles': puzzles,
      'correct': correct,
      'games': games,
      'activeDays': activeDays,
    };
  }

  /// 知识点掌握（0~100，家长页条形图）
  Map<String, int> knowledgeMastery() {
    List<int> byLessons(List<String> ids) {
      var sum = 0, count = 0;
      for (final id in ids) {
        final s = lessonStars[id];
        if (s != null) {
          sum += s * 100 ~/ 3;
          count++;
        }
      }
      return count == 0 ? const [] : [sum ~/ count];
    }

    int merge(List<int> parts) {
      if (parts.isEmpty) return -1;
      return parts.fold(0, (a, b) => a + b) ~/ parts.length;
    }

    final qi = merge(byLessons(['l1']));
    final tao = merge(byLessons(['l2', 'l9', 'l12']));
    final hu = merge(byLessons(['l3']));
    final shuang = merge(byLessons(['l4', 'l8', 'l10']));
    final jin = merge(byLessons(['l5']));
    final jie = merge(byLessons(['l6']));
    final tesuji = merge(byLessons(['l13', 'l14']));
    final lifeTerritory = merge(byLessons(['l15', 'l16']));

    int withPuzzles(int base, List<String> solvedIds, List<String> allIds) {
      final solvedCount = solvedIds.where(solvedPuzzles.contains).length;
      final puzzleScore =
          allIds.isEmpty ? -1 : solvedCount * 100 ~/ allIds.length;
      if (base < 0) return puzzleScore;
      if (puzzleScore < 0) return base;
      return (base + puzzleScore) ~/ 2;
    }

    return {
      '气与打吃': withPuzzles(qi, ['pz1'], wqPuzzles.map((e) => e.id).toList()),
      '提子与逃子': withPuzzles(
          tao, ['pz2', 'pz4', 'pz8', 'pz12', 'pz19'], ['pz2', 'pz4', 'pz8', 'pz12', 'pz19']),
      '边线与角': withPuzzles(
          merge(byLessons(['l7', 'l11'])), ['pz6', 'pz7', 'pz14'], ['pz6', 'pz7', 'pz14']),
      '虎口': merge(hu < 0 ? const [] : [hu]),
      '双打与禁入点': withPuzzles(
          merge([
            if (shuang >= 0) shuang,
            if (jin >= 0) jin,
          ]),
          ['pz3', 'pz5', 'pz9', 'pz10', 'pz11'],
          ['pz3', 'pz5', 'pz9', 'pz10', 'pz11']),
      '打劫': merge(jie < 0 ? const [] : [jie]),
      '征子与手筋': withPuzzles(
          tesuji, ['pz13', 'pz15', 'pz16'], ['pz13', 'pz15', 'pz16']),
      '活棋与围地': withPuzzles(
          lifeTerritory, ['pz17', 'pz18', 'pz20'], ['pz17', 'pz18', 'pz20']),
    }..removeWhere((k, v) => v < 0);
  }

  // ================= 语音 =================

  int _speechSeq = 0;
  int _stopSeq = 0;

  Future<void> speak(String text) async {
    if (!voiceOn.value) return;
    final seq = ++_speechSeq;
    try {
      if (!Get.isRegistered<TtsService>()) return;
      final tts = Get.find<TtsService>();
      await tts.speak(text, featureKey: 'weiqi');
      if (seq <= _stopSeq) {
        await tts.stop();
      }
    } catch (e) {
      debugPrint('棋妙岛 TTS 播报失败: $e');
    }
  }

  Future<void> stopSpeak() async {
    _stopSeq++;
    final speechSeqAtStop = _speechSeq;
    try {
      if (Get.isRegistered<TtsService>()) {
        final tts = Get.find<TtsService>();
        await tts.stop();
        Future.delayed(const Duration(milliseconds: 300), () async {
          if (_speechSeq == speechSeqAtStop) {
            try {
              await tts.stop();
            } catch (_) {}
          }
        });
      }
    } catch (_) {}
  }

  // ================= 持久化 =================

  void _load() {
    try {
      final raw = _box?.get('data') as String?;
      if (raw == null || raw.isEmpty) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final stars = data['lessonStars'];
      if (stars is Map) {
        stars.forEach((k, v) => lessonStars[k.toString()] = (v as num).toInt());
      }
      solvedPuzzles
          .addAll((data['solvedPuzzles'] as List?)?.cast<String>() ?? []);
      wrongPuzzles
          .addAll((data['wrongPuzzles'] as List?)?.cast<String>() ?? []);
      playWins.value = (data['playWins'] as num?)?.toInt() ?? 0;
      playLosses.value = (data['playLosses'] as num?)?.toInt() ?? 0;
      playDraws.value = (data['playDraws'] as num?)?.toInt() ?? 0;
      final daily = data['dailyActivity'];
      if (daily is Map) {
        daily.forEach((k, v) {
          if (v is Map) {
            dailyActivity[k.toString()] =
                v.map((kk, vv) => MapEntry(kk.toString(), (vv as num).toInt()));
          }
        });
      }
      final last = data['lastGame'];
      if (last is Map) _lastGame = Map<String, dynamic>.from(last);
      final hist = data['gameHistory'];
      if (hist is List) {
        gameHistory.assignAll([
          for (final item in hist)
            if (item is Map) Map<String, dynamic>.from(item),
        ]);
      } else if (_lastGame != null) {
        gameHistory.assignAll([_lastGame!]);
      }
      atariLightsOn.value = data['atariLightsOn'] as bool? ?? true;
      voiceOn.value = data['voiceOn'] as bool? ?? true;
      remindOn.value = data['remindOn'] as bool? ?? true;
      sfxOn.value = data['sfxOn'] as bool? ?? true;
      aiLevelIndex.value = ((data['aiLevelIndex'] as num?)?.toInt() ?? 1)
          .clamp(0, wqAiLevels.length - 1);
      winCaptures.value =
          ((data['winCaptures'] as num?)?.toInt() ?? 3).clamp(2, 10);
      final n = (data['boardSize'] as num?)?.toInt() ?? 9;
      boardSize.value = const [9, 13, 19].contains(n) ? n : 9;
      ruleMode.value = (data['ruleMode'] as String?) == 'territory'
          ? 'territory'
          : 'capture';
      showCoords.value = data['showCoords'] as bool? ?? true;
      showMoveNumbers.value = data['showMoveNumbers'] as bool? ?? false;
      confirmMove.value = data['confirmMove'] as bool? ?? false;
      handicap.value = ((data['handicap'] as num?)?.toInt() ?? 0).clamp(0, 9);
      timeLimitMinutes.value = (data['timeLimitMinutes'] as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('棋妙岛进度加载失败(忽略): $e');
    }
  }

  void _save() {
    try {
      final data = {
        'lessonStars': lessonStars,
        'solvedPuzzles': solvedPuzzles.toList(),
        'wrongPuzzles': wrongPuzzles.toList(),
        'playWins': playWins.value,
        'playLosses': playLosses.value,
        'playDraws': playDraws.value,
        'dailyActivity': dailyActivity,
        'lastGame': _lastGame,
        'gameHistory': gameHistory.toList(),
        'atariLightsOn': atariLightsOn.value,
        'voiceOn': voiceOn.value,
        'remindOn': remindOn.value,
        'sfxOn': sfxOn.value,
        'aiLevelIndex': aiLevelIndex.value,
        'winCaptures': winCaptures.value,
        'boardSize': boardSize.value,
        'ruleMode': ruleMode.value,
        'showCoords': showCoords.value,
        'showMoveNumbers': showMoveNumbers.value,
        'confirmMove': confirmMove.value,
        'handicap': handicap.value,
        'timeLimitMinutes': timeLimitMinutes.value,
      };
      _box?.put('data', jsonEncode(data));
    } catch (e) {
      debugPrint('棋妙岛进度保存失败: $e');
    }
  }
}

String? wqLessonIdAt(int index) {
  if (index < 0 || index >= wqLessons.length) return null;
  return wqLessons[index].id;
}
