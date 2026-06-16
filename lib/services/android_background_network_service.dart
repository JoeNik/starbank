import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AndroidBackgroundNetworkService {
  AndroidBackgroundNetworkService._();

  static const MethodChannel _channel =
      MethodChannel('star_bank/background_network_service');

  static final Map<String, _NetworkOperation> _operations = {};
  static bool _foregroundActive = false;

  static Future<T> protect<T>(
    String operationId,
    Future<T> Function() action, {
    required String title,
    required String text,
  }) async {
    await startOperation(operationId, title: title, text: text);
    try {
      return await action();
    } finally {
      await stopOperation(operationId);
    }
  }

  static Future<void> startOperation(
    String operationId, {
    required String title,
    required String text,
  }) async {
    if (!Platform.isAndroid) return;
    _operations[operationId] = _NetworkOperation(title: title, text: text);
    await _syncForegroundService();
  }

  static Future<void> stopOperation(String operationId) async {
    if (!Platform.isAndroid) return;
    _operations.remove(operationId);
    await _syncForegroundService();
  }

  static Future<void> _syncForegroundService() async {
    if (!Platform.isAndroid) return;
    try {
      if (_operations.isEmpty) {
        if (!_foregroundActive) return;
        _foregroundActive = false;
        await _channel.invokeMethod<bool>('stop');
        return;
      }

      final latest = _operations.values.last;
      await _channel.invokeMethod<bool>(
        'start',
        {
          'activeCount': _operations.length,
          'title': latest.title,
          'text': latest.text,
        },
      );
      _foregroundActive = true;
    } on MissingPluginException {
      // Non-Android test shells do not register the platform channel.
    } catch (e) {
      debugPrint('Android background network service error: $e');
    }
  }
}

class _NetworkOperation {
  const _NetworkOperation({
    required this.title,
    required this.text,
  });

  final String title;
  final String text;
}
