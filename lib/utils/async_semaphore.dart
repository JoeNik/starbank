import 'dart:async';
import 'dart:collection';

/// 限制并发数量的轻量信号量，用于避免大量并行下载/哈希/解码任务
/// 挤占 IO 与 CPU 导致界面卡顿。
class AsyncSemaphore {
  AsyncSemaphore(int slots)
      : assert(slots > 0),
        _slots = slots;

  int _slots;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  Future<T> run<T>(Future<T> Function() action) async {
    if (_slots > 0) {
      _slots--;
    } else {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    }
    try {
      return await action();
    } finally {
      if (_waiters.isNotEmpty) {
        _waiters.removeFirst().complete();
      } else {
        _slots++;
      }
    }
  }
}
