import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:star_bank/models/baby.dart';
import 'package:star_bank/models/music/playlist.dart';
import 'package:star_bank/models/poop_record.dart';
import 'package:star_bank/models/quiz_config.dart';
import 'package:star_bank/services/family_sync_service.dart';
import 'package:star_bank/services/storage_service.dart';

void main() {
  _NetworkTestBinding();

  test('family sync uploads owned data and applies remote poop records',
      () async {
    final temp = await Directory.systemTemp.createTemp('starbank_family_sync_');
    final server = await _FakeFamilySyncServer.start();
    FamilySyncService? service;
    try {
      const avatar =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
      Hive.init(temp.path);
      final storage = await StorageService().init();
      Get.put(storage, permanent: true);
      // 真实启动顺序中，家庭同步启动前这些业务盒已按强类型打开。
      await Hive.openBox<QuizConfig>('quiz_config');
      final profile = storage.userBox.values.first;
      profile.avatarPath = avatar;
      await profile.save();
      await storage.babyBox.put(
        'local-baby',
        Baby(
          id: 'local-baby',
          name: '小星星',
          avatarPath: avatar,
          gender: 'female',
        ),
      );

      final state = await Hive.openBox('family_sync_state');
      await state.putAll({
        'enabled': true,
        'endpoint': server.baseUrl,
        'token': 'test-token',
        'lastSeq': 0,
        'manifest': '{}',
        'shadow': '{}',
        'ops': '[]',
      });

      server.remoteRecords.add({
        'section': 'poop_records',
        'recordId': 'remote-poop',
        'seq': 1,
        'updatedAt': '2026-08-01T00:00:00.000Z',
        'deleted': false,
        'payload': {
          'id': 'remote-poop',
          'babyId': 'remote-baby',
          'dateTime': '2026-08-01T08:30:00.000',
          'note': '远端记录',
          'type': 2,
          'color': 3,
        },
      });

      service = FamilySyncService();
      await service.init();
      await service.syncNow(manual: true);

      final remotePoop = storage.poopRecordBox.get('remote-poop');
      expect(remotePoop, isNotNull);
      expect(remotePoop!.babyId, 'remote-baby');
      expect(
        storage.babyBox.values.any((baby) => baby.id == 'remote-baby'),
        isTrue,
      );

      await storage.poopRecordBox.put(
        'local-poop',
        PoopRecord(
          id: 'local-poop',
          babyId: storage.babyBox.values.first.id,
          dateTime: DateTime(2026, 8, 1, 9),
          note: '本地记录',
          type: 1,
          color: 2,
        ),
      );
      await storage.playlistBox.put(
        'favorites',
        Playlist(
          id: 'favorites',
          name: '我的收藏',
          tracks: const [],
          createdAt: DateTime(2026, 8, 1),
        ),
      );
      await storage.settingsBox.put('parent_password_hash', 'hash-value');
      await (await Hive.openBox('pinyin_audio_settings'))
          .put('cache_limit', 800);
      await (await Hive.openBox('app_settings'))
          .put('parent_password_hash', 'hash-value');
      await (await Hive.openBox('tunehub_config')).put('legacy_key', 'value');
      await (await Hive.openBox('player_settings')).put('volume', 0.8);

      await service.syncNow(manual: true);
      expect(service.lastError.value, isEmpty);

      final pushed = server.pushedRecords;
      expect(
        pushed.any((record) =>
            record['section'] == 'poop_records' &&
            record['recordId'] == 'local-poop'),
        isTrue,
      );
      expect(
        pushed.any((record) =>
            record['section'] == 'music_playlists' &&
            record['recordId'] == 'favorites'),
        isTrue,
      );
      final babyRecord = pushed.lastWhere(
        (record) =>
            record['section'] == 'babies' && record['recordId'] == 'local-baby',
      );
      expect(
        (babyRecord['payload'] as Map)['avatarPath'],
        avatar,
      );
      final userProfiles = _snapshotPayload(pushed, 'user_profile') as List;
      expect((userProfiles.first as Map)['avatarPath'], avatar);
      expect(_snapshotData(pushed, 'settings')['parent_password_hash'],
          'hash-value');
      expect(
          _snapshotData(pushed, 'pinyin_audio_settings')['cache_limit'], 800);
      expect(_snapshotData(pushed, 'app_settings')['parent_password_hash'],
          'hash-value');
      expect(_snapshotData(pushed, 'tunehub_config')['legacy_key'], 'value');
      expect(_snapshotData(pushed, 'player_settings')['volume'], 0.8);
    } finally {
      if (service != null) {
        await service.logoutAndDisable();
        service.onClose();
      }
      await server.close();
      Get.reset();
      await Hive.close();
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    }
  });
}

class _NetworkTestBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

Map<String, dynamic> _snapshotData(
  List<Map<String, dynamic>> records,
  String section,
) {
  return Map<String, dynamic>.from(_snapshotPayload(records, section) as Map);
}

dynamic _snapshotPayload(
  List<Map<String, dynamic>> records,
  String section,
) {
  final record = records.lastWhere(
    (item) => item['section'] == section && item['recordId'] == 'all',
  );
  final payload = Map<String, dynamic>.from(record['payload'] as Map);
  return payload['data'];
}

class _FakeFamilySyncServer {
  _FakeFamilySyncServer._(this._server);

  final HttpServer _server;
  final List<Map<String, dynamic>> remoteRecords = [];
  final List<Map<String, dynamic>> pushedRecords = [];

  String get baseUrl => 'http://${_server.address.host}:${_server.port}';

  static Future<_FakeFamilySyncServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _FakeFamilySyncServer._(server);
    unawaited(fake._serve());
    return fake;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _serve() async {
    await for (final request in _server) {
      final path = request.uri.path;
      if (request.method == 'POST' && path == '/api/sync/push') {
        final body = await utf8.decoder.bind(request).join();
        final json = Map<String, dynamic>.from(jsonDecode(body) as Map);
        for (final item in (json['records'] as List? ?? const [])) {
          pushedRecords.add(Map<String, dynamic>.from(item as Map));
        }
        await _json(request, {'ok': true});
        continue;
      }
      if (request.method == 'GET' && path == '/api/sync/changes') {
        final since = int.parse(request.uri.queryParameters['since'] ?? '0');
        final records = since < 1 ? remoteRecords : <Map<String, dynamic>>[];
        await _json(request, {
          'records': records,
          'counters': const [],
          'nextSince': 1,
          'nextSection': null,
          'nextRecord': null,
          'hasMore': false,
          'seq': 1,
        });
        continue;
      }
      if (request.method == 'POST' && path == '/api/logout') {
        await request.drain<void>();
        await _json(request, {'ok': true});
        continue;
      }
      request.response.statusCode = HttpStatus.notFound;
      await _json(request, {'error': 'not found'});
    }
  }

  Future<void> _json(HttpRequest request, Map<String, dynamic> body) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }
}
