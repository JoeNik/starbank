import 'dart:math';

final Random _rand = Random();

/// 生成本地唯一 ID（时间戳 + 随机后缀），用于同步记录标识与计数操作幂等。
String newSyncId() {
  final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final salt = List.generate(
    8,
    (_) => '0123456789abcdefghijklmnopqrstuvwxyz'[_rand.nextInt(36)],
  ).join();
  return '$ts$salt';
}
