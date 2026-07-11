import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:star_bank/models/baby.dart';
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

      expect(server.libraryManifestPutCount, greaterThan(0));
      expect(server.totalRequestCount, greaterThan(0));

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

      expect(server.albumIndexGetCount, 1);
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
    libraryManifestPutCount = 0;
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
    if (!_dirs.contains(path)) {
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
      final raw = jsonDecode(utf8.decode(bytes));
      if (raw is Map) {
        final babies = raw['babies'];
        if (babies is List) {
          for (final baby in babies.whereType<Map>()) {
            final dir = baby['babyDir']?.toString();
            if (dir != null && dir.trim().isNotEmpty) {
              _dirs.add(_normalizePath(dir));
            }
          }
        }
      }
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
