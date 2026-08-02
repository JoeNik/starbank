import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:star_bank/models/baby.dart';
import 'package:star_bank/models/music/playlist.dart';
import 'package:star_bank/models/poop_record.dart';
import 'package:star_bank/models/quiz_config.dart';
import 'package:star_bank/services/family_sync_service.dart';
import 'package:star_bank/services/storage_service.dart';

void main() {
  final binding = _NetworkTestBinding();

  test('family sync uploads owned data and applies remote poop records',
      () async {
    final temp = await Directory.systemTemp.createTemp('starbank_family_sync_');
    final server = await _FakeFamilySyncServer.start();
    FamilySyncService? service;
    try {
      const avatar =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
      Hive.init(temp.path);
      _mockDocumentsDirectory(binding, temp.path);
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
        'syncEpoch': 0,
      });

      server.addCloudRecord(
        section: 'poop_records',
        recordId: 'remote-poop',
        payload: {
          'id': 'remote-poop',
          'babyId': 'remote-baby',
          'dateTime': '2026-08-01T08:30:00.000',
          'note': '远端记录',
          'type': 2,
          'color': 3,
        },
      );

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
          dateTime: DateTime(2015, 8, 1, 9),
          note: '本地记录',
          type: 1,
          color: 2,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        (jsonDecode(state.get('dirty') as String) as List)
            .contains('poop_records'),
        isTrue,
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

  test(
      'owner authoritative sync restores missing old records and removes stale cloud data',
      () async {
    final temp = await Directory.systemTemp.createTemp('starbank_owner_sync_');
    final server = await _FakeFamilySyncServer.start();
    FamilySyncService? service;
    try {
      Hive.init(temp.path);
      _mockDocumentsDirectory(binding, temp.path);
      final storage = await StorageService().init();
      Get.put(storage, permanent: true);

      await storage.babyBox.put(
        'owner-baby',
        Baby(
          id: 'owner-baby',
          name: '主号宝宝',
          avatarPath: '',
          starCount: 17,
          piggyBankBalance: 12.5,
          pocketMoneyBalance: 3,
        ),
      );
      await storage.poopRecordBox.put(
        'old-owner-poop',
        PoopRecord(
          id: 'old-owner-poop',
          babyId: 'owner-baby',
          dateTime: DateTime(2020, 1, 2, 8),
          note: '多年以前的记录',
          type: 1,
          color: 2,
        ),
      );

      final state = await Hive.openBox('family_sync_state');
      await state.putAll({
        'enabled': true,
        'endpoint': server.baseUrl,
        'token': 'owner-token',
        'username': 'owner',
        'role': 'owner',
        'lastSeq': 0,
        'manifest': '{}',
        'shadow': '{}',
        'ops': '[]',
        'syncEpoch': 0,
      });

      service = FamilySyncService();
      await service.init();
      await service.syncNow(manual: true);
      expect(server.hasCloudRecord('poop_records', 'old-owner-poop'), isTrue);

      // 模拟旧服务端曾漏掉主号记录，同时残留主号本机已经不存在的数据。
      server.removeCloudRecord('poop_records', 'old-owner-poop');
      server.addCloudRecord(
        section: 'poop_records',
        recordId: 'stale-cloud-poop',
        payload: {
          'id': 'stale-cloud-poop',
          'babyId': 'owner-baby',
          'dateTime': '2019-01-01T08:00:00.000',
          'note': '云端残留',
          'type': 1,
          'color': 1,
        },
      );

      final backupPath = await service.forceOwnerDataToCloud();
      expect(File(backupPath).existsSync(), isTrue);
      expect(server.epoch, 1);
      expect(server.replacing, isFalse);
      expect(server.hasCloudRecord('poop_records', 'old-owner-poop'), isTrue);
      expect(
          server.hasCloudRecord('poop_records', 'stale-cloud-poop'), isFalse);
      expect(server.counterTotal('owner-baby', 'star'), 17);
      expect(server.counterTotal('owner-baby', 'piggy'), 12.5);
      expect(server.counterTotal('owner-baby', 'pocket'), 3);
    } finally {
      if (service != null) {
        await service.logoutAndDisable();
        service.onClose();
      }
      await server.close();
      Get.reset();
      await Hive.close();
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  });

  test('member adopts a newer owner epoch before uploading stale local records',
      () async {
    final temp = await Directory.systemTemp.createTemp('starbank_member_sync_');
    final server = (await _FakeFamilySyncServer.start())
      ..epoch = 2
      ..addCloudRecord(
        section: 'poop_records',
        recordId: 'owner-poop',
        payload: {
          'id': 'owner-poop',
          'babyId': 'owner-baby',
          'dateTime': '2026-08-02T09:00:00.000',
          'note': '主号权威记录',
          'type': 2,
          'color': 3,
        },
      );
    FamilySyncService? service;
    try {
      Hive.init(temp.path);
      _mockDocumentsDirectory(binding, temp.path);
      final storage = await StorageService().init();
      Get.put(storage, permanent: true);
      await storage.poopRecordBox.put(
        'member-stale-poop',
        PoopRecord(
          id: 'member-stale-poop',
          babyId: 'old-baby',
          dateTime: DateTime(2018, 5, 1),
          note: '子号旧残留',
          type: 1,
          color: 1,
        ),
      );
      final state = await Hive.openBox('family_sync_state');
      await state.putAll({
        'enabled': true,
        'endpoint': server.baseUrl,
        'token': 'member-token',
        'username': 'member',
        'role': 'member',
        'lastSeq': 99,
        'manifest': '{}',
        'shadow': '{}',
        'ops': '[]',
        'syncEpoch': 0,
      });

      service = FamilySyncService();
      await service.init();
      await service.syncNow(manual: true);

      expect(service.lastError.value, isEmpty);
      expect(storage.poopRecordBox.containsKey('member-stale-poop'), isFalse);
      expect(storage.poopRecordBox.containsKey('owner-poop'), isTrue);
      expect(
        server.pushedRecords.any(
          (record) => record['recordId'] == 'member-stale-poop',
        ),
        isFalse,
      );
      expect(state.get('syncEpoch'), 2);
      expect(
          File(state.get('lastSafetySnapshot') as String).existsSync(), isTrue);
    } finally {
      if (service != null) {
        await service.logoutAndDisable();
        service.onClose();
      }
      await server.close();
      Get.reset();
      await Hive.close();
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  });
}

void _mockDocumentsDirectory(_NetworkTestBinding binding, String path) {
  binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => path,
  );
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
  final Map<String, double> _counters = {};
  int epoch = 0;
  bool replacing = false;
  int _seq = 0;
  String _authorityToken = '';

  String get baseUrl => 'http://${_server.address.host}:${_server.port}';

  static Future<_FakeFamilySyncServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _FakeFamilySyncServer._(server);
    unawaited(fake._serve());
    return fake;
  }

  Future<void> close() => _server.close(force: true);

  bool hasCloudRecord(String section, String recordId) => remoteRecords.any(
        (record) =>
            record['section'] == section && record['recordId'] == recordId,
      );

  void removeCloudRecord(String section, String recordId) {
    remoteRecords.removeWhere(
      (record) =>
          record['section'] == section && record['recordId'] == recordId,
    );
  }

  void addCloudRecord({
    required String section,
    required String recordId,
    required Map<String, dynamic> payload,
  }) {
    _seq++;
    remoteRecords.add({
      'section': section,
      'recordId': recordId,
      'seq': _seq,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'deleted': false,
      'payload': payload,
    });
  }

  double? counterTotal(String babyId, String field) =>
      _counters['$babyId:$field'];

  Future<void> _serve() async {
    await for (final request in _server) {
      final path = request.uri.path;
      if (request.method == 'GET' && path == '/api/sync/status') {
        await _json(request, {
          'epoch': epoch,
          'replacing': replacing,
          'seq': _seq,
        });
        continue;
      }
      if (request.method == 'POST' && path == '/api/sync/authoritative/start') {
        await request.drain<void>();
        epoch++;
        replacing = true;
        _authorityToken = 'authority-$epoch';
        remoteRecords.clear();
        _counters.clear();
        _seq = 1;
        await _json(request, {
          'ok': true,
          'epoch': epoch,
          'authorityToken': _authorityToken,
          'seq': _seq,
        });
        continue;
      }
      if (request.method == 'POST' &&
          path == '/api/sync/authoritative/finish') {
        final body = await utf8.decoder.bind(request).join();
        final json = Map<String, dynamic>.from(jsonDecode(body) as Map);
        if (json['epoch'] != epoch ||
            json['authorityToken'] != _authorityToken) {
          request.response.statusCode = HttpStatus.conflict;
          await _json(request, {'error': '覆盖会话失效'});
          continue;
        }
        replacing = false;
        await _json(request, {'ok': true, 'epoch': epoch, 'seq': _seq});
        continue;
      }
      if (request.method == 'POST' && path == '/api/sync/push') {
        final body = await utf8.decoder.bind(request).join();
        final json = Map<String, dynamic>.from(jsonDecode(body) as Map);
        if (json['epoch'] != epoch ||
            (replacing && json['authorityToken'] != _authorityToken)) {
          request.response.statusCode = HttpStatus.conflict;
          await _json(request, {'error': '同步世代已更新'});
          continue;
        }
        final records = json['records'] as List? ?? const [];
        if (records.isNotEmpty) _seq++;
        for (final item in records) {
          final record = Map<String, dynamic>.from(item as Map);
          pushedRecords.add(record);
          removeCloudRecord(
            record['section'].toString(),
            record['recordId'].toString(),
          );
          remoteRecords.add({...record, 'seq': _seq});
        }
        await _json(request, {'ok': true, 'epoch': epoch, 'seq': _seq});
        continue;
      }
      if (request.method == 'POST' && path == '/api/sync/set-counters') {
        final body = await utf8.decoder.bind(request).join();
        final json = Map<String, dynamic>.from(jsonDecode(body) as Map);
        if (json['epoch'] != epoch ||
            (replacing && json['authorityToken'] != _authorityToken)) {
          request.response.statusCode = HttpStatus.conflict;
          await _json(request, {'error': '同步世代已更新'});
          continue;
        }
        for (final raw in (json['counters'] as List? ?? const [])) {
          final counter = Map<String, dynamic>.from(raw as Map);
          _counters['${counter['babyId']}:${counter['field']}'] =
              (counter['total'] as num).toDouble();
        }
        await _json(
            request, {'ok': true, 'epoch': epoch, 'counters': const []});
        continue;
      }
      if (request.method == 'GET' && path == '/api/sync/changes') {
        final since = int.parse(request.uri.queryParameters['since'] ?? '0');
        final requestedEpoch =
            int.parse(request.uri.queryParameters['epoch'] ?? '0');
        if (requestedEpoch != epoch || replacing) {
          request.response.statusCode = HttpStatus.conflict;
          await _json(request, {'error': '同步世代已更新'});
          continue;
        }
        final records = remoteRecords
            .where((record) => (record['seq'] as int) > since)
            .toList();
        await _json(request, {
          'records': records,
          'counters': _counters.entries.map((entry) {
            final split = entry.key.split(':');
            return {
              'babyId': split.first,
              'field': split.last,
              'total': entry.value,
            };
          }).toList(),
          'nextSince': records.isEmpty ? since : records.last['seq'],
          'nextSection': null,
          'nextRecord': null,
          'hasMore': false,
          'seq': _seq,
          'epoch': epoch,
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
