import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:star_bank/models/baby.dart';
import 'package:star_bank/models/baby_cloud_entry.dart';
import 'package:star_bank/models/baby_cloud_media.dart';
import 'package:star_bank/models/baby_cloud_source.dart';
import 'package:star_bank/services/baby_cloud_service.dart';
import 'package:star_bank/services/storage_service.dart';

void main() {
  test('baby cloud sync reuses fresh state and avoids duplicate remote work',
      () async {
    final temp = await Directory.systemTemp.createTemp('starbank_baby_cloud_');
    final server = await _FakeWebDavServer.start();
    try {
      Hive.init(temp.path);
      final storage = await StorageService().init();
      Get.put(storage, permanent: true);

      final baby = Baby(id: 'baby-1', name: '宝宝', avatarPath: '');
      final source = BabyCloudSource(
        id: 'source-1',
        name: '测试 WebDAV',
        rootPath: 'starbank_baby_cloud',
        webDavUrl: server.baseUrl,
        webDavUsername: 'user',
        webDavPassword: 'pass',
      );
      await storage.babyBox.put(baby.id, baby);
      await storage.babyCloudSourceBox.put(source.id, source);

      final service = BabyCloudService();
      service.sources.assignAll([source]);
      service.currentSource.value = source;

      await service.syncBaby(
        baby,
        showErrors: false,
        forceRemote: true,
        trigger: BabyCloudSyncTrigger.manualRefresh,
      );

      // Pull/refresh no longer creates/binds library_manifest on remote.
      expect(server.libraryManifestPutCount, 0);

      server.resetCounts();
      await service.syncBaby(baby, showErrors: false);

      expect(server.totalRequestCount, 0);

      server.resetCounts();
      await service.syncBaby(
        baby,
        showErrors: false,
        forceRemote: true,
        trigger: BabyCloudSyncTrigger.manualRefresh,
      );

      expect(server.albumIndexPutCount, 0);
    } finally {
      await server.close();
      Get.reset();
      await Hive.close();
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    }
  });

  test('manual refresh treats remote album index as authority for cloud boxes only',
      () async {
    final temp =
        await Directory.systemTemp.createTemp('starbank_baby_cloud_auth_');
    final server = await _FakeWebDavServer.start();
    try {
      Hive.init(temp.path);
      final storage = await StorageService().init();
      Get.put(storage, permanent: true);

      final baby = Baby(id: 'baby-1', name: '宝宝', avatarPath: '');
      final source = BabyCloudSource(
        id: 'source-1',
        name: '测试 WebDAV',
        rootPath: 'starbank_baby_cloud',
        webDavUrl: server.baseUrl,
        webDavUsername: 'user',
        webDavPassword: 'pass',
        libraryId: 'lib-test',
      );
      await storage.babyBox.put(baby.id, baby);
      await storage.babyCloudSourceBox.put(source.id, source);

      server.seedDir('/starbank_baby_cloud');
      server.seedDir('/starbank_baby_cloud/babies');
      server.seedDir('/starbank_baby_cloud/babies/baby-1');
      server.seedDir('/starbank_baby_cloud/babies/baby-1/index');
      server.seedFile(
        '/starbank_baby_cloud/library_manifest.json',
        utf8.encode(
          jsonEncode({
            'format': 1,
            'type': 'starbank.baby_cloud.library',
            'libraryId': 'lib-test',
            'name': '亲宝宝云相册',
            'rootPath': '/starbank_baby_cloud',
            'babies': [
              {
                'cloudBabyId': 'cloud-baby-1',
                'localBabyIds': [baby.id],
                'name': baby.name,
                'safeName': 'baby-1',
                'babyDir': '/starbank_baby_cloud/babies/baby-1',
              }
            ],
          }),
        ),
      );

      final remoteIndex = {
        'format': 3,
        'type': 'starbank.baby_cloud.album_index',
        'libraryId': 'lib-test',
        'cloudBabyId': 'cloud-baby-1',
        'sourceId': source.id,
        'babyId': baby.id,
        'babyName': baby.name,
        'babyDir': '/starbank_baby_cloud/babies/baby-1',
        'updatedAt': DateTime.now().toIso8601String(),
        'entries': [
          {
            'id': 'remote-entry-1',
            'babyId': baby.id,
            'dataSourceId': source.id,
            'libraryId': 'lib-test',
            'cloudBabyId': 'cloud-baby-1',
            'entryType': 'media',
            'description': '远端动态',
            'tags': ['远程'],
            'takenAt': DateTime(2026, 1, 1).toIso8601String(),
            'createdAt': DateTime(2026, 1, 1).toIso8601String(),
            'updatedAt': DateTime(2026, 1, 2).toIso8601String(),
            'mediaIds': ['remote-media-1'],
            'actorRole': '妈妈',
          }
        ],
        'media': [
          {
            'id': 'remote-media-1',
            'babyId': baby.id,
            'dataSourceId': source.id,
            'libraryId': 'lib-test',
            'cloudBabyId': 'cloud-baby-1',
            'sha256': 'abc',
            'fileName': 'a.jpg',
            'mediaType': 'photo',
            'mimeType': 'image/jpeg',
            'remotePath':
                '/starbank_baby_cloud/babies/baby-1/2026/01/a.jpg',
            'sizeBytes': 10,
            'takenAt': DateTime(2026, 1, 1).toIso8601String(),
            'entryId': 'remote-entry-1',
            'description': '远端动态',
            'tags': ['远程'],
            'actorRole': '妈妈',
          }
        ],
      };
      server.seedFile(
        '/starbank_baby_cloud/babies/baby-1/index/album_index.json',
        utf8.encode(jsonEncode(remoteIndex)),
      );

      // Stale local synced entry that remote no longer has.
      final stale = BabyCloudEntry(
        id: 'stale-entry',
        babyId: baby.id,
        dataSourceId: source.id,
        libraryId: 'lib-test',
        cloudBabyId: 'cloud-baby-1',
        entryType: 'media',
        description: '本地陈旧',
        takenAt: DateTime(2025, 1, 1),
        mediaIds: const ['stale-media'],
      );
      await storage.babyCloudEntryBox.put(stale.id, stale);
      final staleMedia = BabyCloudMedia(
        id: 'stale-media',
        babyId: baby.id,
        dataSourceId: source.id,
        libraryId: 'lib-test',
        cloudBabyId: 'cloud-baby-1',
        sha256: 'stale',
        fileName: 'old.jpg',
        mediaType: 'photo',
        mimeType: 'image/jpeg',
        remotePath: '/starbank_baby_cloud/babies/baby-1/2025/01/old.jpg',
        sizeBytes: 1,
        takenAt: DateTime(2025, 1, 1),
        entryId: 'stale-entry',
      );
      await storage.babyCloudMediaBox.put(staleMedia.id, staleMedia);

      // Local unpublished draft (no remote path).
      final draft = BabyCloudEntry(
        id: 'local-draft-entry',
        babyId: baby.id,
        dataSourceId: source.id,
        libraryId: 'lib-test',
        cloudBabyId: 'cloud-baby-1',
        entryType: 'diary',
        description: '本地草稿',
        takenAt: DateTime(2026, 2, 1),
        mediaIds: const ['local-draft-media'],
        actorRole: '爸爸',
      );
      await storage.babyCloudEntryBox.put(draft.id, draft);
      final draftMedia = BabyCloudMedia(
        id: 'local-draft-media',
        babyId: baby.id,
        dataSourceId: source.id,
        libraryId: 'lib-test',
        cloudBabyId: 'cloud-baby-1',
        sha256: 'draft',
        fileName: '日记',
        mediaType: 'diary',
        mimeType: 'text/plain',
        remotePath: '',
        sizeBytes: 0,
        takenAt: DateTime(2026, 2, 1),
        entryId: 'local-draft-entry',
        description: '本地草稿',
        actorRole: '爸爸',
      );
      await storage.babyCloudMediaBox.put(draftMedia.id, draftMedia);

      // App-wide settings marker: album sync must not restore/clear these.
      await storage.settingsBox.put('webdav_url', 'http://should-remain');
      await storage.settingsBox.put('demo_app_setting', 'keep-me');

      final service = BabyCloudService();
      service.sources.assignAll([source]);
      service.currentSource.value = source;

      await service.syncBaby(
        baby,
        showErrors: false,
        forceRemote: true,
        trigger: BabyCloudSyncTrigger.manualRefresh,
      );

      expect(storage.babyCloudEntryBox.get('remote-entry-1'), isNotNull);
      expect(storage.babyCloudMediaBox.get('remote-media-1'), isNotNull);
      expect(storage.babyCloudEntryBox.get('stale-entry'), isNull);
      expect(storage.babyCloudMediaBox.get('stale-media'), isNull);
      expect(storage.babyCloudEntryBox.get('local-draft-entry'), isNotNull);
      expect(storage.babyCloudMediaBox.get('local-draft-media'), isNotNull);
      expect(storage.settingsBox.get('webdav_url'), 'http://should-remain');
      expect(storage.settingsBox.get('demo_app_setting'), 'keep-me');
      expect(server.albumIndexPutCount, 0);
      expect(server.libraryManifestPutCount, 0);
    } finally {
      await server.close();
      Get.reset();
      await Hive.close();
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    }
  });
}

class _FakeWebDavServer {
  _FakeWebDavServer._(this._server);

  final HttpServer _server;
  final Set<String> _dirs = {'/'};
  final Map<String, List<int>> _files = {};

  int totalRequestCount = 0;
  int albumIndexGetCount = 0;
  int albumIndexPutCount = 0;
  int libraryManifestPutCount = 0;

  String get baseUrl => 'http://${_server.address.host}:${_server.port}';

  static Future<_FakeWebDavServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _FakeWebDavServer._(server);
    unawaited(fake._serve());
    return fake;
  }

  void resetCounts() {
    totalRequestCount = 0;
    albumIndexGetCount = 0;
    albumIndexPutCount = 0;
    libraryManifestPutCount = 0;
  }

  void seedDir(String path) {
    _dirs.add(_normalizePath(path));
  }

  void seedFile(String path, List<int> bytes) {
    final normalized = _normalizePath(path);
    _files[normalized] = bytes;
    // ensure parent dirs exist
    final parts = normalized.split('/');
    var cur = '';
    for (final part in parts) {
      if (part.isEmpty) continue;
      cur = '$cur/$part';
      if (!cur.contains('.')) {
        _dirs.add(cur);
      } else {
        // parent only
        final parent = cur.substring(0, cur.lastIndexOf('/'));
        if (parent.isNotEmpty) _dirs.add(parent);
      }
    }
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _serve() async {
    await for (final request in _server) {
      totalRequestCount += 1;
      final path = _normalizePath(Uri.decodeComponent(request.uri.path));
      switch (request.method) {
        case 'PROPFIND':
          await _handlePropFind(request, path);
          break;
        case 'MKCOL':
          _dirs.add(path);
          request.response.statusCode = HttpStatus.created;
          await request.response.close();
          break;
        case 'GET':
          await _handleGet(request, path);
          break;
        case 'PUT':
          await _handlePut(request, path);
          break;
        default:
          request.response.statusCode = HttpStatus.methodNotAllowed;
          await request.response.close();
      }
    }
  }

  Future<void> _handlePropFind(HttpRequest request, String path) async {
    if (!_dirs.contains(path) && !_files.containsKey(path)) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    request.response
      ..statusCode = 207
      ..headers.contentType = ContentType('application', 'xml');
    request.response.add(utf8.encode(
      '<?xml version="1.0" encoding="utf-8"?>'
      '<multistatus xmlns="DAV:"><response><href>$path</href></response></multistatus>',
    ));
    await request.response.close();
  }

  Future<void> _handleGet(HttpRequest request, String path) async {
    if (path.endsWith('/index/album_index.json')) {
      albumIndexGetCount += 1;
    }
    final bytes = _files[path];
    if (bytes == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    request.response
      ..statusCode = HttpStatus.ok
      ..add(bytes);
    await request.response.close();
  }

  Future<void> _handlePut(HttpRequest request, String path) async {
    final bytes = await request.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
    _files[path] = bytes;
    if (path.endsWith('/library_manifest.json')) {
      libraryManifestPutCount += 1;
    }
    if (path.endsWith('/index/album_index.json')) {
      albumIndexPutCount += 1;
    }
    request.response.statusCode = HttpStatus.created;
    await request.response.close();
  }

  String _normalizePath(String value) {
    var path = value.trim().replaceAll('\\', '/');
    if (path.isEmpty) return '/';
    while (path.contains('//')) {
      path = path.replaceAll('//', '/');
    }
    if (!path.startsWith('/')) path = '/$path';
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return path;
  }
}
