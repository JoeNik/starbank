import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../../../services/tts_service.dart';
import 'weiqi_data.dart';
import 'weiqi_sfx.dart';

/// 棋妙岛服务：纯学习模块。
/// 只持久化「学习进度 / 练习记录 / 模块内设置」，没有任何金币或可消费积分；
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

  // ================= 最近一局（主页「上局复盘」入口） =================

  Map<String, dynamic>? _lastGame;

  /// 保存最近一局的回放数据（每手颜色/落点 + 关键手讲解）
  void saveLastGame(
      List<({int color, int point})> moves, Map<int, String> notes,
      [Map<int, int> marks = const {}]) {
    _lastGame = {
      'moves': [for (final m in moves) {'c': m.color, 'p': m.point}],
      'notes': {for (final e in notes.entries) e.key.toString(): e.value},
      'marks': {for (final e in marks.entries) e.key.toString(): e.value},
      'playedAt': DateTime.now().toIso8601String(),
    };
    _save();
  }

  Map<String, dynamic>? get lastGame => _lastGame;

  /// 从持久化数据恢复回放参数；无记录返回 null
  ({List<({int color, int point})> moves, Map<int, String> notes,
          Map<int, int> marks})?
      loadLastGame() {
    final g = _lastGame;
    if (g == null) return null;
    final moves = <({int color, int point})>[
      for (final m in (g['moves'] as List))
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
    if (moves.isEmpty) return null;
    return (moves: moves, notes: notes, marks: marks);
  }

  // ---- 对局记录（陪下） ----
  final RxInt playWins = 0.obs;
  final RxInt playLosses = 0.obs;
  final RxInt playDraws = 0.obs;

  /// 每日学习活动：日期 -> {lesson, puzzles, correct, games}
  final RxMap<String, Map<String, int>> dailyActivity =
      <String, Map<String, int>>{}.obs;

  // ---- 模块内设置 ----
  final RxBool voiceOn = true.obs; // 语音讲解
  final RxBool remindOn = true.obs; // 对局中失误提醒
  final RxBool sfxOn = true.obs; // 音效
  final RxBool atariLightsOn = true.obs; // 对局中被打吃警示灯
  final RxDouble aiSkill = 0.82.obs; // 棋棋棋力（0~1）

  WeiqiService() {
    voiceOn.listen((v) {
      if (!v) stopSpeak(); // 关闭语音讲解时，立即停掉正在播的内容
      _save();
    });
    remindOn.listen((v) => _save());
    sfxOn.listen((v) {
      WqSfx.enabled = v;
      _save();
    });
    atariLightsOn.listen((v) => _save());
    aiSkill.listen((v) => _save());
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

  int get totalLessonStars =>
      lessonStars.values.fold(0, (a, b) => a + b);

  int get completedLessonCount =>
      lessonStars.values.where((v) => v > 0).length;

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
        continue; // 今天还没学，从昨天起算
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
  /// 通过对应课程星级与题目完成度聚合。
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
      if (parts.isEmpty) return -1; // 未开始
      return parts.fold(0, (a, b) => a + b) ~/ parts.length;
    }

    final qi = merge(byLessons(['l1']));
    final tao = merge(byLessons(['l2']));
    final hu = merge(byLessons(['l3']));
    final shuang = merge(byLessons(['l4']));
    final jin = merge(byLessons(['l5']));
    final jie = merge(byLessons(['l6']));

    // 题目正确情况并入相应知识点
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
      '提子与逃子':
          withPuzzles(tao, ['pz2', 'pz4', 'pz8'], ['pz2', 'pz4', 'pz8']),
      '边线与角':
          withPuzzles(merge(byLessons(['l7'])), ['pz6', 'pz7'], ['pz6', 'pz7']),
      '虎口': merge(hu < 0 ? const [] : [hu]),
      '双打与禁入点': withPuzzles(
          merge([
            if (shuang >= 0) shuang,
            if (jin >= 0) jin,
          ]),
          ['pz3', 'pz5'],
          ['pz3', 'pz5']),
      '打劫': merge(jie < 0 ? const [] : [jie]),
    }..removeWhere((k, v) => v < 0);
  }

  // ================= 语音 =================

  /// 语音代际门闸：
  /// - [_speechSeq] 每次 speak 递增；
  /// - [_stopSeq] 每次 stopSpeak 递增，seq <= _stopSeq 的播报一律视为已取消。
  /// 退出页面时，可能还有播报链卡在 TTS 前置 await（系统引擎的参数设置，
  /// 或 CFTTS/OpenAI 路由的音频网络预取，可达数秒）——它们会在 stop 之后才起播。
  /// 播报链落定后检查自己的号是否已作废，作废则立即掐断。
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
        // 播报期间页面已退出/已请求停止：刚起播的声音立即停止
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
        // 兜底：覆盖「stop 之后才真正起播」的窄窗口。
        // 仅当之后没有任何新播报启动时才补刀，避免误杀新语音。
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
      solvedPuzzles.addAll((data['solvedPuzzles'] as List?)?.cast<String>() ?? []);
      wrongPuzzles.addAll((data['wrongPuzzles'] as List?)?.cast<String>() ?? []);
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
      atariLightsOn.value = data['atariLightsOn'] as bool? ?? true;
      voiceOn.value = data['voiceOn'] as bool? ?? true;
      remindOn.value = data['remindOn'] as bool? ?? true;
      sfxOn.value = data['sfxOn'] as bool? ?? true;
      aiSkill.value = (data['aiSkill'] as num?)?.toDouble() ?? 0.82;
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
        'atariLightsOn': atariLightsOn.value,
      'voiceOn': voiceOn.value,
        'remindOn': remindOn.value,
        'sfxOn': sfxOn.value,
        'aiSkill': aiSkill.value,
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
