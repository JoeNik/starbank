import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/baby.dart';
import '../models/baby_cloud_entry.dart';
import '../models/baby_cloud_media.dart';
import '../models/baby_cloud_source.dart';
import '../models/baby_cloud_upload_task.dart';
import '../services/android_background_network_service.dart';
import '../services/storage_service.dart';
import '../widgets/toast_utils.dart';

class BabyCloudSourceCheckResult {
  const BabyCloudSourceCheckResult({
    required this.ok,
    required this.message,
    this.endpoint,
    this.url,
  });

  final bool ok;
  final String message;
  final String? endpoint;
  final String? url;

  String get endpointLabel {
    if (endpoint == 'lan') return '内网';
    if (endpoint == 'external') return '外网';
    return '未选择';
  }
}

const int _generatedThumbnailSize = 360;
const int _generatedThumbnailJpegQuality = 62;

class _CachedSourceCheck {
  const _CachedSourceCheck(
    this.result,
    this.checkedAt,
    this.lookedLocal,
    this.endpointMode,
  );

  final BabyCloudSourceCheckResult result;
  final DateTime checkedAt;
  final bool lookedLocal;
  final String endpointMode;

  bool isFresh(bool currentLooksLocal) {
    // 网络环境变了，缓存无效（如内外网切换时能立刻切过来）
    if (lookedLocal != currentLooksLocal) return false;
    final ttl =
        result.ok ? const Duration(seconds: 45) : const Duration(seconds: 5);
    return DateTime.now().difference(checkedAt) < ttl;
  }
}

class _WebDavEndpointCandidate {
  const _WebDavEndpointCandidate(this.endpoint, this.url, {this.note});

  final String endpoint;
  final String url;
  final String? note;
}

abstract class _BabyCloudRemoteClient {
  Future<void> statDir(String remotePath);

  Future<void> stat(String remotePath);

  Future<List<_BabyCloudRemoteEntry>> readDir(String remotePath);

  Future<void> mkdir(String remotePath);

  Future<List<int>> read(String remotePath);

  Future<void> write(String remotePath, List<int> bytes, {String? mimeType});

  Future<void> remove(String remotePath);

  Future<void> move(String fromPath, String toPath);
}

class _BabyCloudRemoteEntry {
  const _BabyCloudRemoteEntry({
    required this.path,
    required this.isDir,
    this.size,
  });

  final String path;
  final bool isDir;
  final int? size;
}

class _BabyWebDavClient implements _BabyCloudRemoteClient {
  _BabyWebDavClient({
    required String endpointUrl,
    required String username,
    required String password,
  })  : _baseUri = Uri.parse(endpointUrl),
        _username = username,
        _password = password;

  final Uri _baseUri;
  final String _username;
  final String _password;

  @override
  Future<void> statDir(String remotePath) async {
    await _propFind(remotePath, depth: '0');
  }

  @override
  Future<void> stat(String remotePath) async {
    await _request(
      'PROPFIND',
      remotePath,
      headers: {
        'Depth': '0',
        'Content-Type': 'application/xml; charset=utf-8',
      },
      body: utf8.encode(
        '<?xml version="1.0" encoding="utf-8"?>'
        '<propfind xmlns="DAV:"><prop>'
        '<resourcetype/><getcontentlength/>'
        '</prop></propfind>',
      ),
      expectedStatuses: const {207, 200},
    );
  }

  @override
  Future<List<_BabyCloudRemoteEntry>> readDir(String remotePath) async {
    final response = await _propFind(remotePath, depth: '1');
    return _parseMultiStatus(response.bodyText);
  }

  Future<_BabyWebDavResponse> _propFind(
    String remotePath, {
    required String depth,
  }) {
    return _request(
      'PROPFIND',
      remotePath,
      collection: true,
      headers: {
        'Depth': depth,
        'Content-Type': 'application/xml; charset=utf-8',
      },
      body: utf8.encode(
        '<?xml version="1.0" encoding="utf-8"?>'
        '<propfind xmlns="DAV:"><prop>'
        '<resourcetype/><getcontentlength/>'
        '</prop></propfind>',
      ),
      expectedStatuses: const {207, 200},
    );
  }

  @override
  Future<void> mkdir(String remotePath) async {
    final attempts = <_BabyWebDavResponse>[];
    _BabyWebDavResponse? existingResponse;

    for (final target in _resolveCollectionTargets(
      remotePath,
      preferTrailingSlash: false,
    )) {
      final response = await _send('MKCOL', target);
      attempts.add(response);
      if (const {200, 201, 204}.contains(response.statusCode)) return;

      // 405 usually means the collection already exists. Keep trying the
      // other slash variant first because some servers reject MKCOL /dir/
      // but accept MKCOL /dir.
      if (response.statusCode == 405) {
        existingResponse ??= response;
      }
    }

    if (existingResponse != null) return;
    throw _BabyWebDavRequestException(
      method: 'MKCOL',
      expectedStatuses: const {200, 201, 204, 405},
      attempts: attempts,
    );
  }

  @override
  Future<List<int>> read(String remotePath) async {
    final response = await _request(
      'GET',
      remotePath,
      expectedStatuses: const {200},
    );
    return response.bodyBytes;
  }

  @override
  Future<void> write(
    String remotePath,
    List<int> bytes, {
    String? mimeType,
  }) async {
    await _request(
      'PUT',
      remotePath,
      body: bytes,
      headers: {
        'Content-Type': mimeType?.trim().isNotEmpty == true
            ? mimeType!.trim()
            : 'application/octet-stream',
      },
      expectedStatuses: const {200, 201, 204},
    );
  }

  @override
  Future<void> remove(String remotePath) async {
    await _request(
      'DELETE',
      remotePath,
      expectedStatuses: const {200, 202, 204, 404},
    );
  }

  @override
  Future<void> move(String fromPath, String toPath) async {
    await _request(
      'MOVE',
      fromPath,
      collection: true,
      headers: {
        'Destination': _resolve(toPath, collection: true).toString(),
        'Overwrite': 'F',
      },
      expectedStatuses: const {200, 201, 204},
    );
  }

  Future<_BabyWebDavResponse> _request(
    String method,
    String remotePath, {
    bool collection = false,
    Map<String, String> headers = const {},
    List<int>? body,
    Set<int> expectedStatuses = const {},
    bool throwOnUnexpected = true,
  }) async {
    final targets = collection
        ? _resolveCollectionTargets(remotePath, preferTrailingSlash: true)
        : <Uri>[_resolve(remotePath)];

    final attempts = <_BabyWebDavResponse>[];
    for (final target in targets) {
      final response = await _send(
        method,
        target,
        headers: headers,
        body: body,
      );
      attempts.add(response);
      if (expectedStatuses.contains(response.statusCode)) {
        return response;
      }
    }

    if (throwOnUnexpected) {
      throw _BabyWebDavRequestException(
        method: method,
        expectedStatuses: expectedStatuses,
        attempts: attempts,
      );
    }
    return attempts.last;
  }

  Future<_BabyWebDavResponse> _send(
    String method,
    Uri target, {
    Map<String, String> headers = const {},
    List<int>? body,
  }) async {
    final request = http.Request(method, target)
      ..followRedirects = true
      ..headers.addAll(_baseHeaders())
      ..headers.addAll(headers);
    if (body != null) {
      request.bodyBytes = body;
    }

    final client = http.Client();
    try {
      final response = await AndroidBackgroundNetworkService.protect(
        'baby_cloud_http_${method}_${DateTime.now().microsecondsSinceEpoch}',
        () async {
          final streamed = await client.send(request).timeout(
                const Duration(seconds: 15),
              );
          final bytes = await streamed.stream.toBytes();
          return _BabyWebDavResponse(
            method: method,
            requestUri: target,
            statusCode: streamed.statusCode,
            bodyBytes: bytes,
            reasonPhrase: streamed.reasonPhrase,
          );
        },
        title: 'StarBank 亲宝宝',
        text: '正在同步云相册数据',
      );
      return response;
    } finally {
      client.close();
    }
  }

  Map<String, String> _baseHeaders() {
    final headers = <String, String>{
      'Accept': '*/*',
      'User-Agent': 'StarBank BabyCloud WebDAV',
    };
    if (_username.isNotEmpty || _password.isNotEmpty) {
      headers[HttpHeaders.authorizationHeader] =
          'Basic ${base64Encode(utf8.encode('$_username:$_password'))}';
    }
    return headers;
  }

  Uri _resolve(String remotePath, {bool collection = false}) {
    final basePath = _normalizeBasePath(_baseUri.path);
    final normalizedRemote = _normalizeRemotePath(remotePath);
    final append = normalizedRemote == '/' ? '' : normalizedRemote;
    var fullPath = _joinUrlPath(basePath, append);
    if (collection && !fullPath.endsWith('/')) {
      fullPath = '$fullPath/';
    }
    return _baseUri.replace(path: fullPath);
  }

  List<Uri> _resolveCollectionTargets(
    String remotePath, {
    required bool preferTrailingSlash,
  }) {
    final plain = _resolve(remotePath);
    final trailing = _resolve(remotePath, collection: true);
    final ordered = preferTrailingSlash ? [trailing, plain] : [plain, trailing];
    final seen = <String>{};
    return [
      for (final uri in ordered)
        if (seen.add(uri.toString())) uri,
    ];
  }

  List<_BabyCloudRemoteEntry> _parseMultiStatus(String xml) {
    final responses = RegExp(
      r'<(?:[A-Za-z0-9_]+:)?response\b[^>]*>(.*?)</(?:[A-Za-z0-9_]+:)?response>',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(xml);
    return responses
        .map((match) {
          final block = match.group(1) ?? '';
          final href = RegExp(
            r'<(?:[A-Za-z0-9_]+:)?href\b[^>]*>(.*?)</(?:[A-Za-z0-9_]+:)?href>',
            caseSensitive: false,
            dotAll: true,
          ).firstMatch(block)?.group(1);
          if (href == null || href.trim().isEmpty) return null;
          final path = _remotePathFromHref(href.trim());
          final isDir = RegExp(
            r'<(?:[A-Za-z0-9_]+:)?collection\b',
            caseSensitive: false,
          ).hasMatch(block);
          final sizeText = RegExp(
            r'<(?:[A-Za-z0-9_]+:)?getcontentlength\b[^>]*>(.*?)</(?:[A-Za-z0-9_]+:)?getcontentlength>',
            caseSensitive: false,
            dotAll: true,
          ).firstMatch(block)?.group(1);
          return _BabyCloudRemoteEntry(
            path: path,
            isDir: isDir,
            size: int.tryParse(sizeText?.trim() ?? ''),
          );
        })
        .whereType<_BabyCloudRemoteEntry>()
        .toList();
  }

  String _remotePathFromHref(String href) {
    final decodedHref = _decodeXml(href);
    Uri? uri;
    try {
      uri = Uri.parse(decodedHref);
    } catch (_) {
      uri = null;
    }
    var path = uri?.hasScheme == true ? uri!.path : decodedHref;
    try {
      path = Uri.decodeFull(path);
    } catch (_) {}

    final basePath = _normalizeBasePath(_baseUri.path);
    if (basePath != '/' && path.startsWith(basePath)) {
      path = path.substring(basePath.length);
    }
    path = _normalizeRemotePath(path);
    return path;
  }

  String _decodeXml(String value) {
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
  }

  String _normalizeBasePath(String path) {
    var value = path.trim();
    if (value.isEmpty) return '';
    while (value.contains('//')) {
      value = value.replaceAll('//', '/');
    }
    if (value.length > 1 && value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value == '/' ? '' : value;
  }

  String _normalizeRemotePath(String path) {
    var value = path.trim().replaceAll('\\', '/');
    if (value.isEmpty) return '/';
    while (value.contains('//')) {
      value = value.replaceAll('//', '/');
    }
    if (!value.startsWith('/')) value = '/$value';
    if (value.length > 1 && value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  String _joinUrlPath(String basePath, String appendPath) {
    final base = basePath.replaceAll(RegExp(r'/+$'), '');
    final append = appendPath.replaceAll(RegExp(r'^/+'), '');
    if (base.isEmpty && append.isEmpty) return '/';
    if (append.isEmpty) return base.startsWith('/') ? base : '/$base';
    if (base.isEmpty) return '/$append';
    final joined = '$base/$append';
    return joined.startsWith('/') ? joined : '/$joined';
  }
}

class _BabyWebDavResponse {
  const _BabyWebDavResponse({
    required this.method,
    required this.requestUri,
    required this.statusCode,
    required this.bodyBytes,
    this.reasonPhrase,
  });

  final String method;
  final Uri requestUri;
  final int statusCode;
  final List<int> bodyBytes;
  final String? reasonPhrase;

  String get bodyText => utf8.decode(bodyBytes, allowMalformed: true);

  String summary({int bodyLimit = 120}) {
    final preview = bodyText.trim().replaceAll(RegExp(r'\s+'), ' ');
    final body = preview.length > bodyLimit
        ? '${preview.substring(0, bodyLimit)}...'
        : preview;
    return '$method $requestUri -> WebDAV $statusCode'
        '${reasonPhrase?.isNotEmpty == true ? ' $reasonPhrase' : ''}'
        '${body.isNotEmpty ? ': $body' : ''}';
  }
}

class _BabyWebDavRequestException implements Exception {
  const _BabyWebDavRequestException({
    required this.method,
    required this.expectedStatuses,
    required this.attempts,
  });

  final String method;
  final Set<int> expectedStatuses;
  final List<_BabyWebDavResponse> attempts;

  @override
  String toString() {
    final expected = expectedStatuses.toList()..sort();
    final lines = attempts
        .asMap()
        .entries
        .map((entry) => '${entry.key + 1}) ${entry.value.summary()}')
        .join('；');
    return '$method 请求失败，期望状态码 ${expected.join('/')}，实际尝试：$lines';
  }
}

typedef _AliyunAccessTokenProvider = Future<String> Function(
  BabyCloudSource source, {
  bool force,
});

class _AliyunFileInfo {
  const _AliyunFileInfo({
    required this.id,
    required this.path,
    required this.name,
    required this.isFolder,
    this.size,
  });

  final String id;
  final String path;
  final String name;
  final bool isFolder;
  final int? size;
}

class _AliyunPathNotFoundException implements Exception {
  const _AliyunPathNotFoundException(this.path);

  final String path;

  @override
  String toString() => '阿里云盘路径不存在: $path';
}

class _AliyunDriveClient implements _BabyCloudRemoteClient {
  _AliyunDriveClient({
    required BabyCloudSource source,
    required _AliyunAccessTokenProvider accessTokenProvider,
    required Future<void> Function(BabyCloudSource source) onSourceChanged,
  })  : _source = source,
        _accessTokenProvider = accessTokenProvider,
        _onSourceChanged = onSourceChanged;

  static const String _apiBase = 'https://openapi.alipan.com/adrive/v1.0';
  static const int _uploadPartSize = 10 * 1024 * 1024;

  final BabyCloudSource _source;
  final _AliyunAccessTokenProvider _accessTokenProvider;
  final Future<void> Function(BabyCloudSource source) _onSourceChanged;
  final Map<String, _AliyunFileInfo> _pathCache = {
    '/': const _AliyunFileInfo(
      id: 'root',
      path: '/',
      name: '/',
      isFolder: true,
    ),
  };

  @override
  Future<void> statDir(String remotePath) async {
    await _resolve(remotePath, requireFolder: true);
  }

  @override
  Future<void> stat(String remotePath) async {
    await _resolve(remotePath);
  }

  @override
  Future<List<_BabyCloudRemoteEntry>> readDir(String remotePath) async {
    final dir = await _resolve(remotePath, requireFolder: true);
    final children = await _listChildren(dir);
    return children
        .map(
          (item) => _BabyCloudRemoteEntry(
            path: item.path,
            isDir: item.isFolder,
            size: item.size,
          ),
        )
        .toList();
  }

  @override
  Future<void> mkdir(String remotePath) async {
    final normalized = _normalizePath(remotePath);
    if (normalized == '/') return;
    final parentPath = _parentPath(normalized);
    final parent = await _resolve(parentPath, requireFolder: true);
    final name = _nameFromPath(normalized);
    try {
      final existing = await _resolve(normalized, requireFolder: true);
      _pathCache[normalized] = existing;
      return;
    } on _AliyunPathNotFoundException {
      // Not found: create below.
    }

    try {
      final payload = await _post('/openFile/create', {
        'drive_id': await _driveId(),
        'parent_file_id': parent.id,
        'name': name,
        'type': 'folder',
        'check_name_mode': 'refuse',
      });
      final fileId = _firstNonEmpty(payload, const ['file_id']);
      if (fileId == null) throw Exception('创建目录响应缺少 file_id');
      _pathCache[normalized] = _AliyunFileInfo(
        id: fileId,
        path: normalized,
        name: name,
        isFolder: true,
      );
    } catch (e) {
      final existing = await _tryResolve(normalized, requireFolder: true);
      if (existing != null) return;
      rethrow;
    }
  }

  @override
  Future<List<int>> read(String remotePath) async {
    final file = await _resolve(remotePath);
    if (file.isFolder) throw Exception('阿里云盘路径是目录，不能读取为文件: $remotePath');
    final payload = await _post('/openFile/getDownloadUrl', {
      'drive_id': await _driveId(),
      'file_id': file.id,
      'expire_sec': 900,
    });
    final url = _firstNonEmpty(payload, const ['url', 'download_url']);
    if (url == null) throw Exception('下载地址响应缺少 url');

    final headers = <String, String>{};
    final rawHeaders = payload['headers'];
    if (rawHeaders is Map) {
      rawHeaders.forEach((key, value) {
        if (key != null && value != null) {
          headers[key.toString()] = value.toString();
        }
      });
    }
    final response = await http
        .get(Uri.parse(url), headers: headers)
        .timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('下载阿里云盘文件失败 HTTP ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  @override
  Future<void> write(
    String remotePath,
    List<int> bytes, {
    String? mimeType,
  }) async {
    final normalized = _normalizePath(remotePath);
    if (normalized == '/') throw Exception('不能把文件写到阿里云盘根目录');
    final parentPath = _parentPath(normalized);
    final parent = await _resolve(parentPath, requireFolder: true);
    final name = _nameFromPath(normalized);

    final existing = await _tryResolve(normalized);
    if (existing != null) {
      await _deleteByFileId(existing.id);
      _pathCache.remove(normalized);
    }

    final partCount = max(1, (bytes.length / _uploadPartSize).ceil());
    final payload = await _post('/openFile/create', {
      'drive_id': await _driveId(),
      'parent_file_id': parent.id,
      'name': name,
      'type': 'file',
      'check_name_mode': 'refuse',
      'size': bytes.length,
      'part_info_list': [
        for (var i = 1; i <= partCount; i++) {'part_number': i},
      ],
    });
    final fileId = _firstNonEmpty(payload, const ['file_id']);
    final uploadId = _firstNonEmpty(payload, const ['upload_id']);
    if (fileId == null || uploadId == null) {
      throw Exception('创建上传任务响应缺少 file_id 或 upload_id');
    }

    final rawParts = payload['part_info_list'];
    if (rawParts is! List || rawParts.isEmpty) {
      throw Exception('创建上传任务响应缺少 part_info_list');
    }
    final uploadUrls = <int, String>{};
    for (final raw in rawParts) {
      if (raw is! Map) continue;
      final partNumber = _intFromJson(raw['part_number']);
      final uploadUrl = _firstNonEmpty(
        Map<String, dynamic>.from(raw),
        const ['upload_url', 'internal_upload_url'],
      );
      if (partNumber != null && uploadUrl != null) {
        uploadUrls[partNumber] = uploadUrl;
      }
    }

    for (var partNumber = 1; partNumber <= partCount; partNumber++) {
      final uploadUrl = uploadUrls[partNumber];
      if (uploadUrl == null) {
        throw Exception('第 $partNumber 分片缺少上传地址');
      }
      final start = (partNumber - 1) * _uploadPartSize;
      final end = min(start + _uploadPartSize, bytes.length);
      final chunk = bytes.sublist(start, end);
      await _uploadPart(uploadUrl, chunk, mimeType: mimeType);
    }

    await _post('/openFile/complete', {
      'drive_id': await _driveId(),
      'file_id': fileId,
      'upload_id': uploadId,
    });

    _pathCache[normalized] = _AliyunFileInfo(
      id: fileId,
      path: normalized,
      name: name,
      isFolder: false,
      size: bytes.length,
    );
  }

  @override
  Future<void> remove(String remotePath) async {
    final normalized = _normalizePath(remotePath);
    if (normalized == '/') return;
    final file = await _tryResolve(normalized);
    if (file == null) return;
    await _deleteByFileId(file.id);
    _pathCache.removeWhere((path, _) {
      return path == normalized || path.startsWith('$normalized/');
    });
  }

  @override
  Future<void> move(String fromPath, String toPath) async {
    final from = await _resolve(fromPath);
    final targetPath = _normalizePath(toPath);
    if (targetPath == '/') throw Exception('不能移动到阿里云盘根目录');
    final targetParent = await _resolve(
      _parentPath(targetPath),
      requireFolder: true,
    );
    await _post('/openFile/move', {
      'drive_id': await _driveId(),
      'file_id': from.id,
      'to_parent_file_id': targetParent.id,
      'new_name': _nameFromPath(targetPath),
    });
    _pathCache.removeWhere((path, _) {
      final normalizedFrom = _normalizePath(fromPath);
      return path == normalizedFrom || path.startsWith('$normalizedFrom/');
    });
  }

  Future<String> _driveId() async {
    final existing = _source.aliyunDriveDriveId?.trim() ?? '';
    if (existing.isNotEmpty) return existing;

    final payload = await _post('/user/getDriveInfo', const {});
    final driveId = _firstNonEmpty(payload, const [
      'default_drive_id',
      'drive_id',
      'resource_drive_id',
      'backup_drive_id',
    ]);
    if (driveId == null) throw Exception('阿里云盘账号信息缺少 drive_id');
    _source.aliyunDriveDriveId = driveId;
    _source.aliyunDriveUserId ??= _firstNonEmpty(payload, const ['user_id']);
    _source.aliyunDriveNickName ??= _firstNonEmpty(
      payload,
      const ['nick_name', 'nickname', 'name', 'user_name'],
    );
    await _onSourceChanged(_source);
    return driveId;
  }

  Future<_AliyunFileInfo?> _tryResolve(
    String remotePath, {
    bool requireFolder = false,
  }) async {
    try {
      return await _resolve(remotePath, requireFolder: requireFolder);
    } on _AliyunPathNotFoundException {
      return null;
    }
  }

  Future<_AliyunFileInfo> _resolve(
    String remotePath, {
    bool requireFolder = false,
  }) async {
    final normalized = _normalizePath(remotePath);
    final cached = _pathCache[normalized];
    if (cached != null) {
      if (requireFolder && !cached.isFolder) {
        throw Exception('阿里云盘路径不是目录: $normalized');
      }
      return cached;
    }
    if (normalized == '/') return _pathCache['/']!;

    var current = _pathCache['/']!;
    var currentPath = '';
    final parts = normalized.split('/').where((part) => part.isNotEmpty);
    for (final part in parts) {
      final children = await _listChildren(current);
      final next = children.firstWhereOrNull((item) => item.name == part);
      if (next == null) throw _AliyunPathNotFoundException(normalized);
      current = next;
      currentPath = currentPath.isEmpty ? '/$part' : '$currentPath/$part';
      _pathCache[currentPath] = current;
    }
    if (requireFolder && !current.isFolder) {
      throw Exception('阿里云盘路径不是目录: $normalized');
    }
    return current;
  }

  Future<List<_AliyunFileInfo>> _listChildren(_AliyunFileInfo parent) async {
    if (!parent.isFolder) throw Exception('阿里云盘路径不是目录: ${parent.path}');
    final result = <_AliyunFileInfo>[];
    String? marker;
    do {
      final payload = await _post('/openFile/list', {
        'drive_id': await _driveId(),
        'parent_file_id': parent.id,
        'limit': 100,
        if (marker?.isNotEmpty == true) 'marker': marker,
        'order_by': 'name',
        'order_direction': 'ASC',
      });
      final rawItems = payload['items'];
      if (rawItems is List) {
        for (final raw in rawItems) {
          if (raw is! Map) continue;
          final item = Map<String, dynamic>.from(raw);
          final fileId = _firstNonEmpty(item, const ['file_id']);
          final name = _firstNonEmpty(item, const ['name']);
          if (fileId == null || name == null) continue;
          final childPath = _joinPath(parent.path, name);
          final child = _AliyunFileInfo(
            id: fileId,
            path: childPath,
            name: name,
            isFolder: item['type']?.toString() == 'folder',
            size: _intFromJson(item['size']),
          );
          result.add(child);
          _pathCache[childPath] = child;
        }
      }
      marker = _firstNonEmpty(payload, const ['next_marker']);
    } while (marker != null && marker.isNotEmpty);
    return result;
  }

  Future<void> _deleteByFileId(String fileId) async {
    await _post('/openFile/delete', {
      'drive_id': await _driveId(),
      'file_id': fileId,
    });
  }

  Future<void> _uploadPart(
    String uploadUrl,
    List<int> chunk, {
    String? mimeType,
  }) async {
    final response = await http
        .put(
          Uri.parse(uploadUrl),
          body: chunk,
        )
        .timeout(const Duration(minutes: 2));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('上传阿里云盘分片失败 HTTP ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    bool retryOnUnauthorized = true,
  }) async {
    final token = await _accessTokenProvider(_source);
    final response = await http
        .post(
          Uri.parse('$_apiBase$path'),
          headers: {
            HttpHeaders.authorizationHeader: 'Bearer $token',
            HttpHeaders.contentTypeHeader: 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 401 && retryOnUnauthorized) {
      await _accessTokenProvider(_source, force: true);
      return _post(path, body, retryOnUnauthorized: false);
    }

    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    final raw = _jsonMapOrNull(text) ?? <String, dynamic>{};
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = (raw['message'] ??
              raw['error_description'] ??
              raw['error'] ??
              raw['code'] ??
              text)
          .toString();
      throw Exception('阿里云盘 API $path HTTP ${response.statusCode}: $message');
    }
    return raw;
  }

  Map<String, dynamic>? _jsonMapOrNull(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return <String, dynamic>{};
    try {
      final raw = jsonDecode(trimmed);
      return raw is Map ? Map<String, dynamic>.from(raw) : null;
    } catch (_) {
      return null;
    }
  }

  static int? _intFromJson(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static String? _firstNonEmpty(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key]?.toString().trim();
      if (value?.isNotEmpty == true) return value;
    }
    return null;
  }

  static String _normalizePath(String path) {
    var normalized = path.trim().replaceAll('\\', '/');
    if (normalized.isEmpty) return '/';
    while (normalized.contains('//')) {
      normalized = normalized.replaceAll('//', '/');
    }
    if (!normalized.startsWith('/')) normalized = '/$normalized';
    if (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  static String _parentPath(String path) {
    final normalized = _normalizePath(path);
    if (normalized == '/') return '/';
    final index = normalized.lastIndexOf('/');
    if (index <= 0) return '/';
    return normalized.substring(0, index);
  }

  static String _nameFromPath(String path) {
    final normalized = _normalizePath(path);
    if (normalized == '/') return '/';
    return normalized.split('/').where((part) => part.isNotEmpty).last;
  }

  static String _joinPath(String parent, String name) {
    final normalizedParent = _normalizePath(parent);
    if (normalizedParent == '/') return '/$name';
    return '$normalizedParent/$name';
  }
}

class BabyCloudService extends GetxService {
  static const int _albumIndexFormat = 3;
  static const String _albumIndexType = 'starbank.baby_cloud.album_index';
  static const int _libraryManifestFormat = 1;
  static const String _libraryManifestType = 'starbank.baby_cloud.library';
  static const int _maxUploadRetries = 3;
  static const Duration _automaticSyncFreshness = Duration(minutes: 10);
  static const String aliyunDriveDefaultRedirectUri =
      'starbank://aliyundrive/oauth';
  static const String aliyunDriveDefaultScope =
      'user:base,file:all:read,file:all:write';
  static const String aliyunDriveDefaultAuthUrl =
      'https://www.alipan.com/o/oauth/authorize';
  static const String aliyunDriveDefaultTokenUrl =
      'https://openapi.alipan.com/oauth/access_token';
  static const MethodChannel _aliyunOAuthChannel =
      MethodChannel('star_bank/aliyun_oauth');
  static const bool _debugMediaCache = false;

  final StorageService _storage = Get.find<StorageService>();

  final RxList<BabyCloudSource> sources = <BabyCloudSource>[].obs;
  final Rx<BabyCloudSource?> currentSource = Rx<BabyCloudSource?>(null);
  final RxList<BabyCloudEntry> entries = <BabyCloudEntry>[].obs;
  final RxList<BabyCloudMedia> media = <BabyCloudMedia>[].obs;
  final RxList<BabyCloudUploadTask> uploadTasks = <BabyCloudUploadTask>[].obs;
  final RxBool isSyncing = false.obs;

  bool _queueRunning = false;
  bool _aliyunOAuthChannelInitialized = false;
  Future<void>? _activeSync;
  final Map<String, Future<String?>> _localFileFutures = {};
  final Map<String, Future<String?>> _localThumbnailFutures = {};
  final Set<String> _thumbnailAutoFailedKeys = <String>{};
  final Map<String, String> _manifestBabyDirs = {};
  final Map<String, String> _manifestCloudBabyIds = {};
  final Map<String, _CachedSourceCheck> _sourceCheckCache = {};
  final Map<String, Future<BabyCloudSourceCheckResult>> _sourceCheckFutures =
      {};
  final Set<String> _deletedTaskIds = <String>{};
  Directory? _appDocumentsDir;

  bool get hasUsableCurrentSource {
    final source = currentSource.value;
    if (source == null) return false;
    if (source.isWebDav) return _hasAnyWebDavEndpoint(source);
    if (source.isAliyunDrive) {
      return _hasAliyunDriveToken(source);
    }
    return false;
  }

  String get currentSourceSetupMessage {
    final source = currentSource.value;
    if (source == null) return '请先配置亲宝宝云相册数据源';
    if (source.isAliyunDrive) {
      if (!_hasAliyunDriveToken(source)) {
        return '请先完成阿里云盘 OAuth 授权，或填写可用的 Access Token';
      }
      return '';
    }
    if (!_hasAnyWebDavEndpoint(source)) {
      return '亲宝宝 WebDAV 外网/内网地址至少填写一个，请先完善数据源配置';
    }
    return '';
  }

  Future<BabyCloudService> init() async {
    await _warmAppDocumentsDir();
    _loadLocal();
    _initAliyunOAuthChannel();
    unawaited(_consumeInitialAliyunOAuthUri());
    await _recoverInterruptedTasks();
    unawaited(processQueue());
    return this;
  }

  Future<void> _warmAppDocumentsDir() async {
    try {
      _appDocumentsDir = await getApplicationDocumentsDirectory();
    } catch (e) {
      debugPrint('BabyCloudCache: 初始化本地缓存目录失败: $e');
    }
  }

  String _entryTypeForMedia(List<BabyCloudMedia> items) {
    final types = items.map((item) => item.mediaType).toSet();
    if (types.length == 1) {
      final only = types.single;
      if (only == 'diary') return 'diary';
      if (only == 'audio') return 'audio';
      return 'media';
    }
    return 'mixed';
  }

  void _loadLocal() {
    sources.assignAll(_storage.babyCloudSourceBox.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt)));
    uploadTasks.assignAll(_storage.babyCloudUploadTaskBox.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

    final savedId = _storage.settingsBox.get('baby_cloud_current_source_id');
    currentSource.value =
        sources.firstWhereOrNull((s) => s.id == savedId) ?? sources.firstOrNull;
    _refreshEntries();
    _refreshMedia();
  }

  Future<void> _recoverInterruptedTasks() async {
    var changed = false;
    for (final task in _storage.babyCloudUploadTaskBox.values) {
      if (task.status == 'running' && task.progress < 1) {
        task
          ..status = 'queued'
          ..errorMessage = null
          ..updatedAt = DateTime.now();
        await task.save();
        changed = true;
      }
    }
    if (changed) {
      _reloadTasks();
    }
  }

  void _initAliyunOAuthChannel() {
    if (_aliyunOAuthChannelInitialized) return;
    _aliyunOAuthChannelInitialized = true;
    _aliyunOAuthChannel.setMethodCallHandler((call) async {
      if (call.method == 'oauthRedirect') {
        final url = call.arguments?.toString() ?? '';
        if (url.trim().isEmpty) return false;
        final result = await handleAliyunOAuthRedirect(url);
        if (result.ok) {
          ToastUtils.showSuccess('阿里云盘授权成功');
        } else {
          ToastUtils.showError(result.message);
        }
        return result.ok;
      }
      return null;
    });
  }

  Future<void> _consumeInitialAliyunOAuthUri() async {
    try {
      final url = await _aliyunOAuthChannel.invokeMethod<String>(
        'getInitialUri',
      );
      if (url?.trim().isNotEmpty == true) {
        final result = await handleAliyunOAuthRedirect(url!);
        if (result.ok) ToastUtils.showSuccess('阿里云盘授权成功');
      }
    } on MissingPluginException {
      // Desktop/tests do not provide the Android deep-link bridge.
    } catch (e) {
      debugPrint('读取阿里云盘 OAuth 回调失败: $e');
    }
  }

  void _refreshEntries() {
    final source = currentSource.value;
    if (source == null) {
      entries.clear();
      return;
    }
    final sourceLibraryId = _libraryIdForSource(source);
    final items = _storage.babyCloudEntryBox.values.where((entry) {
      if (entry.purgedAt != null) return false;
      if (sourceLibraryId != null && entry.libraryId == sourceLibraryId) {
        return true;
      }
      return entry.dataSourceId == source.id;
    }).toList()
      ..sort((a, b) => b.takenAt.compareTo(a.takenAt));
    entries.assignAll(items);
  }

  void _refreshMedia() {
    final source = currentSource.value;
    if (source == null) {
      media.clear();
      return;
    }
    final sourceLibraryId = _libraryIdForSource(source);
    final items = _storage.babyCloudMediaBox.values.where((item) {
      if (item.purgedAt != null) return false;
      if (sourceLibraryId != null && item.libraryId == sourceLibraryId) {
        return true;
      }
      return item.dataSourceId == source.id;
    }).toList()
      ..sort((a, b) => b.takenAt.compareTo(a.takenAt));
    media.assignAll(items);
  }

  void reloadLocalMedia() => _refreshMedia();

  List<BabyCloudMedia> mediaForBaby(
    String babyId, {
    bool includeDeleted = false,
    bool includePurged = false,
  }) {
    final sourceId = currentSource.value?.id;
    if (sourceId == null) return const [];
    return media
        .where((m) =>
            m.babyId == babyId &&
            _belongsToCurrentSource(m) &&
            (includePurged || !m.isPurged) &&
            (includeDeleted || !m.isDeleted))
        .toList();
  }

  List<BabyCloudEntry> entriesForBaby(
    String babyId, {
    bool includeDeleted = false,
    bool includePurged = false,
  }) {
    return entries
        .where((entry) =>
            entry.babyId == babyId &&
            _entryBelongsToCurrentSource(entry) &&
            (includePurged || !entry.isPurged) &&
            (includeDeleted || !entry.isDeleted))
        .toList();
  }

  bool _belongsToCurrentSource(BabyCloudMedia item) {
    final source = currentSource.value;
    if (source == null) return false;
    final sourceLibraryId = _libraryIdForSource(source);
    if (sourceLibraryId != null && item.libraryId == sourceLibraryId) {
      return true;
    }
    return item.dataSourceId == source.id;
  }

  bool _entryBelongsToCurrentSource(BabyCloudEntry entry) {
    final source = currentSource.value;
    if (source == null) return false;
    final sourceLibraryId = _libraryIdForSource(source);
    if (sourceLibraryId != null && entry.libraryId == sourceLibraryId) {
      return true;
    }
    return entry.dataSourceId == source.id;
  }

  Future<void> saveSource(BabyCloudSource source) async {
    source.updatedAt = DateTime.now();
    await _storage.babyCloudSourceBox.put(source.id, source);
    _loadLocal();
    if (currentSource.value == null || currentSource.value!.id == source.id) {
      await selectSource(source.id);
    }
  }

  Future<void> selectSource(String sourceId) async {
    final source = sources.firstWhereOrNull((s) => s.id == sourceId);
    if (source == null) return;
    currentSource.value = source;
    await _storage.settingsBox.put('baby_cloud_current_source_id', source.id);
    _refreshEntries();
    _refreshMedia();
  }

  Uri aliyunDriveAuthorizationUri(
    BabyCloudSource source, {
    required String state,
  }) {
    final clientId = source.aliyunDriveClientId?.trim() ?? '';
    final redirectUri = _aliyunRedirectUri(source);
    final scope = _aliyunScope(source);
    final authBase = _aliyunAuthUrl(source);
    if (clientId.isEmpty) {
      throw Exception('请先填写阿里云盘开放平台 Client ID');
    }
    final base = Uri.parse(authBase);
    return base.replace(
      queryParameters: {
        ...base.queryParameters,
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': scope,
        'state': state,
      },
    );
  }

  Future<void> startAliyunDriveOAuth(BabyCloudSource source) async {
    _validateAliyunOAuthConfig(source);
    await saveSource(source);
    final state = _newAliyunOAuthState(source.id);
    await _storage.settingsBox.put('baby_cloud_aliyun_oauth_state', state);
    await _storage.settingsBox
        .put('baby_cloud_aliyun_oauth_source_id', source.id);
    await _storage.settingsBox.put(
      'baby_cloud_aliyun_oauth_created_at',
      DateTime.now().toIso8601String(),
    );

    final uri = aliyunDriveAuthorizationUri(source, state: state);
    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        throw Exception('无法打开浏览器，请检查系统是否有可用浏览器');
      }
    } catch (_) {
      await _clearAliyunOAuthPending();
      rethrow;
    }
  }

  Future<BabyCloudSourceCheckResult> completeAliyunOAuthWithInput(
    BabyCloudSource source,
    String input,
  ) async {
    _validateAliyunOAuthConfig(source);
    final code = _extractAliyunOAuthCode(input);
    if (code == null || code.isEmpty) {
      return const BabyCloudSourceCheckResult(
        ok: false,
        message: '没有从输入内容中识别到授权 code',
      );
    }
    await saveSource(source);
    final stored =
        sources.firstWhereOrNull((item) => item.id == source.id) ?? source;
    return _finishAliyunOAuthCode(stored, code, clearPending: true);
  }

  Future<BabyCloudSourceCheckResult> handleAliyunOAuthRedirect(
    String rawUrl,
  ) async {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) {
      return const BabyCloudSourceCheckResult(
        ok: false,
        message: '阿里云盘 OAuth 回调地址无法解析',
      );
    }
    final error = uri.queryParameters['error'];
    if (error?.isNotEmpty == true) {
      final description = uri.queryParameters['error_description'] ??
          uri.queryParameters['errorMessage'] ??
          '';
      return BabyCloudSourceCheckResult(
        ok: false,
        message: '阿里云盘授权失败：$error${description.isEmpty ? '' : '，$description'}',
      );
    }

    final code = uri.queryParameters['code']?.trim() ?? '';
    final state = uri.queryParameters['state']?.trim() ?? '';
    if (code.isEmpty) {
      return const BabyCloudSourceCheckResult(
        ok: false,
        message: '阿里云盘 OAuth 回调缺少 code',
      );
    }
    if (state.isEmpty) {
      return const BabyCloudSourceCheckResult(
        ok: false,
        message: '阿里云盘 OAuth 回调缺少 state',
      );
    }

    final pendingState =
        _storage.settingsBox.get('baby_cloud_aliyun_oauth_state') as String?;
    if (pendingState?.isNotEmpty == true && pendingState != state) {
      return const BabyCloudSourceCheckResult(
        ok: false,
        message: '阿里云盘 OAuth state 不匹配，请重新发起授权',
      );
    }

    final pendingSourceId = _storage.settingsBox
        .get('baby_cloud_aliyun_oauth_source_id') as String?;
    final stateSourceId = _sourceIdFromAliyunOAuthState(state);
    final sourceId = pendingSourceId?.trim().isNotEmpty == true
        ? pendingSourceId!.trim()
        : stateSourceId;
    if (sourceId == null || sourceId.isEmpty) {
      return const BabyCloudSourceCheckResult(
        ok: false,
        message: '无法定位阿里云盘授权对应的数据源',
      );
    }
    final source = sources.firstWhereOrNull((item) => item.id == sourceId) ??
        _storage.babyCloudSourceBox.get(sourceId);
    if (source == null) {
      return const BabyCloudSourceCheckResult(
        ok: false,
        message: '阿里云盘授权对应的数据源已不存在',
      );
    }
    return _finishAliyunOAuthCode(source, code, clearPending: true);
  }

  Future<BabyCloudSourceCheckResult> checkSource(
    BabyCloudSource source, {
    bool persist = true,
    bool initializeRoot = false,
  }) async {
    if (source.isAliyunDrive) {
      return _checkAliyunDriveSource(
        source,
        persist: persist,
        initializeRoot: initializeRoot,
      );
    }
    if (!source.isWebDav) {
      final message = '暂不支持的数据源类型：${source.type}';
      await _recordSourceCheck(
        source,
        ok: false,
        message: message,
        persist: persist,
      );
      return BabyCloudSourceCheckResult(ok: false, message: message);
    }
    if (!_hasAnyWebDavEndpoint(source)) {
      const message = '亲宝宝 WebDAV 外网/内网地址至少填写一个';
      await _recordSourceCheck(
        source,
        ok: false,
        message: message,
        persist: persist,
      );
      return const BabyCloudSourceCheckResult(ok: false, message: message);
    }

    if (!initializeRoot && persist) {
      final cacheKey = _sourceCheckCacheKey(source);
      final currentLooksLocal = await _looksLikeLocalNetwork();
      final currentEndpointMode = _webDavEndpointMode(source);
      final cached = _sourceCheckCache[cacheKey];
      if (cached != null &&
          cached.endpointMode == currentEndpointMode &&
          cached.isFresh(currentLooksLocal)) {
        return cached.result;
      }

      final pending = _sourceCheckFutures[cacheKey];
      if (pending != null) return pending;

      final future = _checkWebDavSource(
        source,
        persist: persist,
        initializeRoot: initializeRoot,
      );
      _sourceCheckFutures[cacheKey] = future;
      try {
        final result = await future;
        _sourceCheckCache[cacheKey] = _CachedSourceCheck(
          result,
          DateTime.now(),
          currentLooksLocal,
          currentEndpointMode,
        );
        return result;
      } finally {
        _sourceCheckFutures.remove(cacheKey);
      }
    }

    return _checkWebDavSource(
      source,
      persist: persist,
      initializeRoot: initializeRoot,
    );
  }

  Future<BabyCloudSourceCheckResult> _checkAliyunDriveSource(
    BabyCloudSource source, {
    required bool persist,
    bool initializeRoot = false,
  }) async {
    if (!_hasAliyunDriveToken(source)) {
      const message = '阿里云盘需要先完成 OAuth 授权，或填写可用的 Access Token';
      await _recordSourceCheck(
        source,
        ok: false,
        message: message,
        persist: persist,
        status: 'notInitialized',
      );
      return const BabyCloudSourceCheckResult(ok: false, message: message);
    }

    try {
      await _refreshAliyunDriveTokenIfNeeded(source, force: false);
      final client = _aliyunDriveClient(
        source,
        persistSourceChanges: persist,
      );
      await client.readDir('/').timeout(const Duration(seconds: 8));
      if (initializeRoot) {
        final root = _normalizeRoot(source.rootPath);
        if (root != '/') await _ensureRemoteDir(client, root);
      }
      final name = source.aliyunDriveNickName?.trim();
      final drive = source.aliyunDriveDriveId?.trim();
      final message = [
        '阿里云盘授权有效',
        if (name?.isNotEmpty == true) '账号：$name',
        if (drive?.isNotEmpty == true) 'Drive ID：$drive',
      ].join('；');
      await _recordSourceCheck(
        source,
        ok: true,
        message: message,
        persist: persist,
      );
      return BabyCloudSourceCheckResult(
        ok: true,
        message: message,
        endpoint: 'aliyunDrive',
      );
    } catch (e) {
      final message = '阿里云盘授权不可用，请重新登录：$e';
      await _recordSourceCheck(
        source,
        ok: false,
        message: message,
        persist: persist,
      );
      return BabyCloudSourceCheckResult(ok: false, message: message);
    }
  }

  Future<BabyCloudSourceCheckResult> _finishAliyunOAuthCode(
    BabyCloudSource source,
    String code, {
    required bool clearPending,
  }) async {
    try {
      final payload = await _requestAliyunDriveToken(source, {
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': _aliyunRedirectUri(source),
      });
      _applyAliyunDriveTokenPayload(source, payload);
      await _recordSourceCheck(
        source,
        ok: true,
        message: '阿里云盘授权成功',
        persist: true,
      );
      if (clearPending) await _clearAliyunOAuthPending();
      return const BabyCloudSourceCheckResult(
        ok: true,
        message: '阿里云盘授权成功',
        endpoint: 'aliyunDrive',
      );
    } catch (e) {
      final message = '阿里云盘授权换取 token 失败：$e';
      await _recordSourceCheck(
        source,
        ok: false,
        message: message,
        persist: true,
      );
      return BabyCloudSourceCheckResult(ok: false, message: message);
    }
  }

  Future<void> _refreshAliyunDriveTokenIfNeeded(
    BabyCloudSource source, {
    required bool force,
  }) async {
    final refreshToken = source.aliyunDriveRefreshToken?.trim() ?? '';
    final expiresAt = source.aliyunDriveTokenExpiresAt;
    final accessToken = source.aliyunDriveAccessToken?.trim() ?? '';
    if (refreshToken.isEmpty) {
      if (accessToken.isNotEmpty && !force) return;
      throw Exception('Access Token 不可用，请重新填写或完成 OAuth 授权');
    }
    final shouldRefresh = force ||
        accessToken.isEmpty ||
        expiresAt == null ||
        expiresAt.isBefore(DateTime.now().add(const Duration(minutes: 3)));
    if (!shouldRefresh) return;
    final payload = await _requestAliyunDriveToken(source, {
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
    });
    _applyAliyunDriveTokenPayload(source, payload);
  }

  Future<Map<String, dynamic>> _requestAliyunDriveToken(
    BabyCloudSource source,
    Map<String, dynamic> fields,
  ) async {
    _validateAliyunOAuthConfig(source);
    final body = <String, dynamic>{
      'client_id': source.aliyunDriveClientId!.trim(),
      if (source.aliyunDriveClientSecret?.trim().isNotEmpty == true)
        'client_secret': source.aliyunDriveClientSecret!.trim(),
      ...fields,
    };
    final response = await http
        .post(
          Uri.parse(_aliyunTokenUrl(source)),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    final raw = _jsonMapOrNull(text);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = raw != null
          ? (raw['message'] ?? raw['error_description'] ?? raw['error'] ?? text)
              .toString()
          : text;
      throw Exception('HTTP ${response.statusCode}: $message');
    }
    if (raw == null) throw Exception('token 响应格式不是 JSON 对象: $text');
    return raw;
  }

  Map<String, dynamic>? _jsonMapOrNull(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return <String, dynamic>{};
    try {
      final raw = jsonDecode(trimmed);
      return raw is Map ? Map<String, dynamic>.from(raw) : null;
    } catch (_) {
      return null;
    }
  }

  void _applyAliyunDriveTokenPayload(
    BabyCloudSource source,
    Map<String, dynamic> payload,
  ) {
    final accessToken = payload['access_token']?.toString().trim() ?? '';
    if (accessToken.isEmpty) throw Exception('token 响应缺少 access_token');
    final refreshToken = payload['refresh_token']?.toString().trim();
    final expiresIn = _intFromJson(payload['expires_in']) ??
        _intFromJson(payload['expire_time']) ??
        7200;
    source
      ..aliyunDriveAccessToken = accessToken
      ..aliyunDriveRefreshToken = refreshToken?.isNotEmpty == true
          ? refreshToken
          : source.aliyunDriveRefreshToken
      ..aliyunDriveTokenExpiresAt = DateTime.now().add(
        Duration(seconds: expiresIn > 120 ? expiresIn - 60 : expiresIn),
      )
      ..aliyunDriveDriveId = _firstNonEmpty(
            payload,
            const ['default_drive_id', 'drive_id', 'resource_drive_id'],
          ) ??
          source.aliyunDriveDriveId
      ..aliyunDriveUserId =
          _firstNonEmpty(payload, const ['user_id']) ?? source.aliyunDriveUserId
      ..aliyunDriveNickName = _firstNonEmpty(
            payload,
            const ['nick_name', 'nickname', 'name', 'user_name'],
          ) ??
          source.aliyunDriveNickName;
  }

  void _validateAliyunOAuthConfig(BabyCloudSource source) {
    if ((source.aliyunDriveClientId?.trim() ?? '').isEmpty) {
      throw Exception('请填写阿里云盘开放平台 Client ID');
    }
    if (_aliyunRedirectUri(source).trim().isEmpty) {
      throw Exception('请填写 OAuth Redirect URI');
    }
    if (_aliyunAuthUrl(source).trim().isEmpty) {
      throw Exception('请填写 OAuth 授权地址');
    }
    if (_aliyunTokenUrl(source).trim().isEmpty) {
      throw Exception('请填写 OAuth Token 地址');
    }
  }

  String? _extractAliyunOAuthCode(String input) {
    final value = input.trim();
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    final code = uri?.queryParameters['code']?.trim();
    if (code?.isNotEmpty == true) return code;
    return value;
  }

  String _newAliyunOAuthState(String sourceId) {
    final random = Random.secure();
    final bytes = List<int>.generate(18, (_) => random.nextInt(256));
    final token = base64Url.encode(bytes).replaceAll('=', '');
    return '$sourceId.$token';
  }

  String? _sourceIdFromAliyunOAuthState(String state) {
    final index = state.indexOf('.');
    if (index <= 0) return null;
    return state.substring(0, index);
  }

  Future<void> _clearAliyunOAuthPending() async {
    await _storage.settingsBox.delete('baby_cloud_aliyun_oauth_state');
    await _storage.settingsBox.delete('baby_cloud_aliyun_oauth_source_id');
    await _storage.settingsBox.delete('baby_cloud_aliyun_oauth_created_at');
  }

  String _aliyunRedirectUri(BabyCloudSource source) {
    final value = source.aliyunDriveRedirectUri?.trim() ?? '';
    return value.isEmpty ? aliyunDriveDefaultRedirectUri : value;
  }

  String _aliyunScope(BabyCloudSource source) {
    final value = source.aliyunDriveScope?.trim() ?? '';
    return value.isEmpty ? aliyunDriveDefaultScope : value;
  }

  String _aliyunAuthUrl(BabyCloudSource source) {
    final value = source.aliyunDriveAuthUrl?.trim() ?? '';
    return value.isEmpty ? aliyunDriveDefaultAuthUrl : value;
  }

  String _aliyunTokenUrl(BabyCloudSource source) {
    final value = source.aliyunDriveTokenUrl?.trim() ?? '';
    return value.isEmpty ? aliyunDriveDefaultTokenUrl : value;
  }

  bool _hasAliyunDriveToken(BabyCloudSource source) {
    return source.aliyunDriveAccessToken?.trim().isNotEmpty == true ||
        source.aliyunDriveRefreshToken?.trim().isNotEmpty == true;
  }

  int? _intFromJson(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  String? _firstNonEmpty(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key]?.toString().trim();
      if (value?.isNotEmpty == true) return value;
    }
    return null;
  }

  Future<String> _aliyunAccessTokenFor(
    BabyCloudSource source, {
    required bool force,
    required bool persist,
  }) async {
    await _refreshAliyunDriveTokenIfNeeded(source, force: force);
    final token = source.aliyunDriveAccessToken?.trim() ?? '';
    if (token.isEmpty) throw Exception('阿里云盘 access token 为空');
    if (persist) await _persistSourceSilently(source);
    return token;
  }

  _AliyunDriveClient _aliyunDriveClient(
    BabyCloudSource source, {
    bool persistSourceChanges = true,
  }) {
    return _AliyunDriveClient(
      source: source,
      accessTokenProvider: (source, {force = false}) => _aliyunAccessTokenFor(
        source,
        force: force,
        persist: persistSourceChanges,
      ),
      onSourceChanged: persistSourceChanges
          ? _persistSourceSilently
          : (_) async {},
    );
  }

  Future<_BabyCloudRemoteClient> _remoteClientForSource(
    BabyCloudSource source, {
    BabyCloudSourceCheckResult? check,
    bool persistSourceChanges = true,
  }) async {
    if (source.isAliyunDrive) {
      await _refreshAliyunDriveTokenIfNeeded(source, force: false);
      if (persistSourceChanges) await _persistSourceSilently(source);
      return _aliyunDriveClient(
        source,
        persistSourceChanges: persistSourceChanges,
      );
    }
    if (source.isWebDav) {
      final endpointUrl = check?.url ?? _effectiveWebDavUrl(source);
      if (endpointUrl == null || endpointUrl.isEmpty) {
        throw Exception('亲宝宝 WebDAV 地址不可用');
      }
      return _webDavClient(source, endpointUrl: endpointUrl);
    }
    throw Exception('暂不支持的数据源类型：${source.type}');
  }

  Future<void> _persistSourceSilently(BabyCloudSource source) async {
    source.updatedAt = DateTime.now();
    await _storage.babyCloudSourceBox.put(source.id, source);
    final index = sources.indexWhere((item) => item.id == source.id);
    if (index >= 0) {
      sources[index] = source;
      sources.refresh();
    }
    if (currentSource.value?.id == source.id) {
      currentSource.value = source;
    }
  }

  Future<BabyCloudSourceCheckResult> _checkWebDavSource(
    BabyCloudSource source, {
    required bool persist,
    required bool initializeRoot,
  }) async {
    final looksLocal = await _looksLikeLocalNetwork();
    final endpointMode = _webDavEndpointMode(source);
    final candidates = await _orderedWebDavCandidates(source);

    if (candidates.isEmpty) {
      final message = endpointMode == 'lan'
          ? '已切换为固定内网模式，请先填写内网 WebDAV 地址'
          : endpointMode == 'external'
              ? '已切换为固定外网模式，请先填写外网 WebDAV 地址'
              : '亲宝宝 WebDAV 外网/内网地址至少填写一个';
      await _recordSourceCheck(
        source,
        ok: false,
        message: message,
        persist: persist,
      );
      return BabyCloudSourceCheckResult(ok: false, message: message);
    }

    if (endpointMode == 'lan' || endpointMode == 'external') {
      final preferred = candidates
          .where((candidate) => candidate.endpoint == endpointMode)
          .toList();
      final fallback = candidates
          .where((candidate) => candidate.endpoint != endpointMode)
          .toList();
      return _checkWebDavCandidateBatch(
        source,
        preferred.isNotEmpty ? preferred : fallback,
        looksLocal: looksLocal,
        initializeRoot: initializeRoot,
        persist: persist,
      );
    }

    final preferredEndpoint = looksLocal ? 'lan' : 'external';
    final preferred = candidates
        .where((candidate) => candidate.endpoint == preferredEndpoint)
        .toList();
    final fallback = candidates
        .where((candidate) => candidate.endpoint != preferredEndpoint)
        .toList();

    final preferredResult = await _checkWebDavCandidateBatch(
      source,
      preferred.isNotEmpty ? preferred : candidates,
      looksLocal: looksLocal,
      initializeRoot: initializeRoot,
      persist: persist,
      recordFailure: false,
    );
    if (preferredResult.ok) return preferredResult;

    if (fallback.isEmpty) {
      await _recordSourceCheck(
        source,
        ok: false,
        message: preferredResult.message,
        persist: persist,
      );
      return preferredResult;
    }

    final fallbackResult = await _checkWebDavCandidateBatch(
      source,
      fallback,
      looksLocal: looksLocal,
      initializeRoot: initializeRoot,
      persist: persist,
      failurePrefix:
          '$preferredEndpoint 优先检测失败，已回退到${preferredEndpoint == 'lan' ? '外网' : '内网'}：',
    );
    if (fallbackResult.ok) return fallbackResult;

    final combinedMessage =
        '${preferredResult.message}；${fallbackResult.message}';
    await _recordSourceCheck(
      source,
      ok: false,
      message: combinedMessage,
      persist: persist,
    );
    return BabyCloudSourceCheckResult(ok: false, message: combinedMessage);
  }

  Future<BabyCloudSourceCheckResult> _checkWebDavCandidateBatch(
    BabyCloudSource source,
    List<_WebDavEndpointCandidate> candidates, {
    required bool looksLocal,
    required bool initializeRoot,
    required bool persist,
    bool recordFailure = true,
    String? failurePrefix,
  }) async {
    // 并发检测同一优先级批次里的候选端点，但只接受“第一个成功结果”。
    final futures = candidates
        .map(
          (candidate) => _checkSingleWebDavEndpoint(
            source,
            candidate,
            looksLocal: looksLocal,
            initializeRoot: initializeRoot,
            persist: persist,
          ),
        )
        .toList();

    final allResultsFuture = Future.wait(
      futures,
      eagerError: false,
    );
    final firstSuccess = Completer<BabyCloudSourceCheckResult>();
    var remaining = futures.length;
    for (final future in futures) {
      future.then((result) {
        if (result.ok && !firstSuccess.isCompleted) {
          firstSuccess.complete(result);
        }
      }).whenComplete(() {
        remaining -= 1;
        if (remaining == 0 && !firstSuccess.isCompleted) {
          firstSuccess.completeError(StateError('no-success'));
        }
      });
    }

    try {
      final result = await firstSuccess.future;
      if (result.ok) return result;
    } catch (_) {
      // 没有任何候选端点成功，继续汇总错误信息。
    }

    final candidateErrors = <String>[];
    final results = await allResultsFuture;

    for (var i = 0; i < results.length; i++) {
      final result = results[i];
      if (!result.ok) {
        candidateErrors.add(result.message);
      }
    }

    final body = candidateErrors.join('；');
    final message = failurePrefix?.trim().isNotEmpty == true
        ? '${failurePrefix!}$body'
        : 'WebDAV 不可用，请检查地址、账号密码和网络：$body';
    if (recordFailure) {
      await _recordSourceCheck(
        source,
        ok: false,
        message: message,
        persist: persist,
      );
    }
    return BabyCloudSourceCheckResult(ok: false, message: message);
  }

  Future<BabyCloudSourceCheckResult> _checkSingleWebDavEndpoint(
    BabyCloudSource source,
    _WebDavEndpointCandidate candidate, {
    required bool looksLocal,
    required bool initializeRoot,
    required bool persist,
  }) async {
    try {
      final client = _webDavClient(source, endpointUrl: candidate.url);

      // 优化超时设置：内网应该非常快
      final mismatch = looksLocal
          ? candidate.endpoint == 'external'
          : candidate.endpoint == 'lan';

      final checkTimeout = initializeRoot
          ? const Duration(seconds: 8)
          : mismatch
              ? const Duration(milliseconds: 1500) // 不匹配：1.5秒
              : (candidate.endpoint == 'lan'
                  ? const Duration(seconds: 3) // 内网：3秒（成功则立即返回）
                  : const Duration(seconds: 10));      // 外网：10秒（网络可能较慢）

      final endpointLabel = candidate.endpoint == 'lan' ? '内网' : '外网';
      final rootWarning = initializeRoot
          ? await _checkWebDavRoot(client, source).timeout(checkTimeout)
          : await _quickCheckWebDav(client, source).timeout(checkTimeout);

      final notes = [
        if (candidate.note?.isNotEmpty == true) candidate.note!,
        if (rootWarning?.isNotEmpty == true) rootWarning!,
      ];
      final message = notes.isEmpty
          ? '$endpointLabel WebDAV 可用'
          : '$endpointLabel WebDAV 可用；${notes.join('；')}';

      source
        ..activeWebDavUrl = candidate.url
        ..activeWebDavEndpoint = candidate.endpoint;

      await _recordSourceCheck(
        source,
        ok: true,
        message: message,
        persist: persist,
      );

      return BabyCloudSourceCheckResult(
        ok: true,
        message: message,
        endpoint: candidate.endpoint,
        url: candidate.url,
      );
    } catch (e) {
      final endpointLabel = candidate.endpoint == 'lan' ? '内网' : '外网';
      return BabyCloudSourceCheckResult(
        ok: false,
        message: '$endpointLabel ${candidate.url}: $e',
      );
    }
  }

  String _sourceCheckCacheKey(BabyCloudSource source) {
    return [
      source.id,
      source.type,
      source.webDavUrl?.trim() ?? '',
      source.webDavLanUrl?.trim() ?? '',
      source.webDavUsername?.trim() ?? '',
      source.webDavPassword ?? '',
      _webDavEndpointMode(source),
    ].join('\u001f');
  }

  String _webDavEndpointMode(BabyCloudSource source) {
    final mode = source.webDavEndpointMode.trim().toLowerCase();
    if (mode == 'lan' || mode == 'external') return mode;
    return 'auto';
  }

  Future<List<Map<String, dynamic>>> listRemoteDirectories(
    BabyCloudSource source,
    String path, {
    bool persistCheck = true,
  }) async {
    final check = await checkSource(source, persist: persistCheck);
    if (!check.ok) throw Exception(check.message);
    final client = await _remoteClientForSource(
      source,
      check: check,
      persistSourceChanges: persistCheck,
    );
    final dir = _normalizeRemoteDir(path);
    if (dir != '/') {
      await _ensureRemoteDir(client, dir);
    }
    final files = await client.readDir(dir);
    return files
        .where((f) => f.isDir && f.path.isNotEmpty)
        .map((f) {
          final childPath = _normalizeRemoteDir(f.path);
          return {
            'path': childPath,
            'name': _remoteName(childPath),
          };
        })
        .where((d) => d['path'] != dir)
        .toList()
      ..sort((a, b) => a['name'].toString().compareTo(b['name'].toString()));
  }

  Future<String> createRemoteDirectory(
    BabyCloudSource source,
    String parentPath,
    String name, {
    bool persistCheck = true,
  }) async {
    final cleanName = _cleanRemoteDirName(name);
    if (cleanName.isEmpty) throw Exception('目录名不能为空');
    final check = await checkSource(source, persist: persistCheck);
    if (!check.ok) throw Exception(check.message);
    final client = await _remoteClientForSource(
      source,
      check: check,
      persistSourceChanges: persistCheck,
    );
    final path = _joinRemoteDir(parentPath, cleanName);
    await _ensureRemoteDir(client, path);
    return path;
  }

  Future<void> renameRemoteDirectory(
    BabyCloudSource source,
    String path,
    String newName, {
    bool persistCheck = true,
  }) async {
    final current = _normalizeRemoteDir(path);
    final cleanName = _cleanRemoteDirName(newName);
    if (current == '/') throw Exception('不能重命名云端根目录');
    if (cleanName.isEmpty) throw Exception('目录名不能为空');
    final check = await checkSource(source, persist: persistCheck);
    if (!check.ok) throw Exception(check.message);
    final parent = _parentRemoteDir(current);
    final target = _joinRemoteDir(parent, cleanName);
    final client = await _remoteClientForSource(
      source,
      check: check,
      persistSourceChanges: persistCheck,
    );
    await client.move(current, target);
  }

  Future<void> syncBaby(
    Baby baby, {
    bool showErrors = true,
    bool forceRemote = false,
  }) {
    final source = currentSource.value;
    if (source == null) return Future<void>.value();
    if (!forceRemote && _hasFreshBabySyncCache(source, baby)) {
      _refreshEntries();
      _refreshMedia();
      return Future<void>.value();
    }

    final active = _activeSync;
    if (active != null) return active;

    final operation = _syncBabyInternal(baby, showErrors: showErrors);
    _activeSync = operation;
    return operation.whenComplete(() {
      if (identical(_activeSync, operation)) {
        _activeSync = null;
      }
    });
  }

  bool _hasFreshBabySyncCache(BabyCloudSource source, Baby baby) {
    final raw = _storage.settingsBox.get(_babySyncCacheKey(source.id, baby.id));
    final syncedAt = raw is DateTime
        ? raw
        : DateTime.tryParse(raw?.toString() ?? '');
    if (syncedAt == null) return false;
    return DateTime.now().difference(syncedAt) < _automaticSyncFreshness;
  }

  Future<void> _markBabySyncCacheFresh(String sourceId, String babyId) {
    return _storage.settingsBox.put(
      _babySyncCacheKey(sourceId, babyId),
      DateTime.now().toIso8601String(),
    );
  }

  String _babySyncCacheKey(String sourceId, String babyId) {
    return 'baby_cloud_last_sync_${_safeFileSegment(sourceId)}_${_safeFileSegment(babyId)}';
  }

  Future<void> _syncBabyInternal(Baby baby, {bool showErrors = true}) async {
    final source = currentSource.value;
    if (source == null) return;

    isSyncing.value = true;
    try {
      final check = await checkSource(source);
      if (!check.ok) {
        if (showErrors) ToastUtils.showError(check.message);
        return;
      }
      final client = await _remoteClientForSource(source, check: check);
      await _prepareBabyCloudStructure(client, source, baby);
      final remote = await _readRemoteIndexAt(client, _indexPath(source, baby));
      if (remote != null) {
        await _mergeRemoteIndex(source, baby, remote);
      }
      await _writeLocalIndexFor(
        source.id,
        baby.id,
        waitForActiveSync: false,
      );
      source.status = 'normal';
      await saveSource(source);
      _refreshEntries();
      _refreshMedia();
    } catch (e) {
      source.status = 'invalid';
      await saveSource(source);
      if (showErrors) ToastUtils.showError('同步亲宝宝数据源失败: $e');
    } finally {
      isSyncing.value = false;
    }
  }

  Future<void> _waitForActiveSync() async {
    final active = _activeSync;
    if (active != null) await active;
  }

  bool hasUploadedHash(String babyId, String hash) {
    if (currentSource.value == null) return false;
    return media.any(
      (m) =>
          _belongsToCurrentSource(m) &&
          m.babyId == babyId &&
          m.sha256 == hash &&
          !m.isDeleted &&
          !m.isPurged,
    );
  }

  Future<bool> queueUpload({
    required Baby baby,
    required String localPath,
    required String fileName,
    required String mediaType,
    String? mimeType,
    DateTime? takenAt,
    String? sha256Hash,
    String? localThumbnailPath,
    String? entryId,
    String? description,
    List<String>? tags,
    String? locationName,
    String? actorRole,
    String visibility = 'family',
  }) async {
    if (!hasUsableCurrentSource) {
      ToastUtils.showWarning(currentSourceSetupMessage);
      return false;
    }
    final source = currentSource.value!;
    final file = File(localPath);
    if (!await file.exists()) {
      ToastUtils.showError('文件不可读取: $fileName');
      return false;
    }
    if (sha256Hash != null && hasUploadedHash(baby.id, sha256Hash)) {
      ToastUtils.showInfo('$fileName 已在当前宝宝的当前数据源中存在');
      return false;
    }
    final preparedThumbnailPath = await _prepareLocalThumbnailPath(
      localPath: localPath,
      fileName: fileName,
      mediaType: mediaType,
      cacheKey: sha256Hash ?? DateTime.now().microsecondsSinceEpoch.toString(),
      existingThumbnailPath: localThumbnailPath,
    );
    final task = BabyCloudUploadTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      babyId: baby.id,
      dataSourceId: source.id,
      localPath: localPath,
      fileName: fileName,
      mediaType: mediaType,
      mimeType: mimeType ?? _mimeFromName(fileName, mediaType),
      sizeBytes: await file.length(),
      sha256: sha256Hash,
      takenAt: takenAt,
      localThumbnailPath: preparedThumbnailPath,
      entryId: entryId,
      description: description,
      tags: tags,
      locationName: locationName,
      actorRole: actorRole,
      visibility: visibility,
    );
    await _storage.babyCloudUploadTaskBox.put(task.id, task);
    uploadTasks.insert(0, task);
    unawaited(processQueue());
    return true;
  }

  Future<bool> createDiaryEntry({
    required Baby baby,
    required String description,
    DateTime? takenAt,
    List<String>? tags,
    String? locationName,
    String? actorRole,
    String visibility = 'family',
  }) async {
    await _waitForActiveSync();
    if (!hasUsableCurrentSource) {
      ToastUtils.showWarning(currentSourceSetupMessage);
      return false;
    }
    final source = currentSource.value!;
    final now = DateTime.now();
    final entryId = '${now.microsecondsSinceEpoch}_diary';
    final cloudBabyId = _cloudBabyId(source, baby);
    final libraryId = _libraryScopeForSource(source);
    final entry = BabyCloudEntry(
      id: entryId,
      babyId: baby.id,
      dataSourceId: source.id,
      libraryId: libraryId,
      cloudBabyId: cloudBabyId,
      entryType: 'diary',
      description: description,
      tags: tags,
      locationName: locationName,
      actorRole: actorRole,
      visibility: visibility,
      takenAt: takenAt ?? now,
      mediaIds: [entryId],
    );
    final item = BabyCloudMedia(
      id: entryId,
      babyId: baby.id,
      dataSourceId: source.id,
      libraryId: libraryId,
      cloudBabyId: cloudBabyId,
      sha256: entryId,
      fileName: '日记',
      mediaType: 'diary',
      mimeType: 'text/plain',
      remotePath: '',
      localPath: null,
      sizeBytes: 0,
      takenAt: takenAt ?? now,
      entryId: entryId,
      description: description,
      tags: tags,
      locationName: locationName,
      actorRole: actorRole,
      visibility: visibility,
    );
    await _storage.babyCloudEntryBox.put(entry.id, entry);
    await _storage.babyCloudMediaBox.put(item.id, item);
    _refreshEntries();
    _refreshMedia();
    await publishIndexFor(source.id, baby.id);
    return true;
  }

  Future<bool> updateEntryMetadata({
    required String entryId,
    required Baby baby,
    required String description,
    required DateTime takenAt,
    required List<String> tags,
    required String? locationName,
    required String? actorRole,
    String visibility = 'family',
  }) async {
    await _waitForActiveSync();
    final source = currentSource.value;
    if (source == null) return false;
    final updated = await _applyEntryMetadataLocally(
      source: source,
      entryId: entryId,
      baby: baby,
      description: description,
      takenAt: takenAt,
      tags: tags,
      locationName: locationName,
      actorRole: actorRole,
      visibility: visibility,
    );
    if (!updated) return false;
    await publishIndexFor(source.id, baby.id);
    return true;
  }

  Future<bool> queueEntryMetadataUpdate({
    required String entryId,
    required Baby baby,
    required String description,
    required DateTime takenAt,
    required List<String> tags,
    required String? locationName,
    required String? actorRole,
    String visibility = 'family',
  }) async {
    final source = currentSource.value;
    if (source == null) return false;
    final updated = await _applyEntryMetadataLocally(
      source: source,
      entryId: entryId,
      baby: baby,
      description: description,
      takenAt: takenAt,
      tags: tags,
      locationName: locationName,
      actorRole: actorRole,
      visibility: visibility,
    );
    if (!updated) return false;

    final task = BabyCloudUploadTask(
      id: '${DateTime.now().microsecondsSinceEpoch}_metadata_$entryId',
      babyId: baby.id,
      dataSourceId: source.id,
      localPath: '',
      fileName: '同步动态修改',
      mediaType: 'metadata',
      mimeType: 'application/json',
      sizeBytes: 0,
      entryId: entryId,
      description: description,
      tags: tags,
      locationName: locationName,
      actorRole: actorRole,
      visibility: visibility,
      takenAt: takenAt,
      taskType: 'metadata',
      targetId: entryId,
    );
    await _storage.babyCloudUploadTaskBox.put(task.id, task);
    uploadTasks.insert(0, task);
    unawaited(processQueue());
    return true;
  }

  Future<bool> _applyEntryMetadataLocally({
    required BabyCloudSource source,
    required String entryId,
    required Baby baby,
    required String description,
    required DateTime takenAt,
    required List<String> tags,
    required String? locationName,
    required String? actorRole,
    required String visibility,
  }) async {
    final entry = _storage.babyCloudEntryBox.get(entryId);
    if (entry == null) return false;
    final now = DateTime.now();
    entry
      ..description = description
      ..tags = tags
      ..locationName = locationName
      ..actorRole = actorRole
      ..visibility = visibility
      ..takenAt = takenAt
      ..updatedAt = now;
    await entry.save();

    final items = _storage.babyCloudMediaBox.values
        .where((item) =>
            item.entryId == entryId &&
            item.babyId == baby.id &&
            _mediaBelongsToSource(source, item))
        .toList();
    for (final item in items) {
      item
        ..description = description
        ..tags = tags
        ..locationName = locationName
        ..actorRole = actorRole
        ..visibility = visibility
        ..takenAt = takenAt
        ..updatedAt = now;
      await item.save();
    }
    _refreshEntries();
    _refreshMedia();
    return true;
  }

  Future<String?> ensureLocalMediaFile(BabyCloudMedia item) {
    final existing = _readableMediaPath(item);
    if (existing != null) {
      _logMediaCache('原图已记录且可读', item, existing);
      return Future.value(existing);
    }
    final cachedFile = _localMediaCacheFile(item);
    if (cachedFile != null && cachedFile.existsSync()) {
      _logMediaCache('原图磁盘命中', item, cachedFile.path);
      return _rememberLocalMediaPath(item, cachedFile.path);
    }
    final stored = _storage.babyCloudMediaBox.get(item.id);
    if (stored != null) {
      final storedPath = _readableMediaPath(stored);
      if (storedPath != null) {
        item
          ..localPath = storedPath
          ..updatedAt = stored.updatedAt;
        _logMediaCache('原图从Hive记录命中', item, storedPath);
        return Future.value(storedPath);
      }
      final storedCachedFile = _localMediaCacheFile(stored);
      if (storedCachedFile != null && storedCachedFile.existsSync()) {
        item.localPath = storedCachedFile.path;
        _logMediaCache('原图从Hive记录推导磁盘命中', item, storedCachedFile.path);
        return _rememberLocalMediaPath(stored, storedCachedFile.path);
      }
    }
    final futureKey = _localMediaCacheKey(item);
    if (_localFileFutures.containsKey(futureKey)) {
      _logMediaCache('原图复用下载任务', item, futureKey);
    } else {
      _logMediaCache('原图准备远程下载', item, item.remotePath);
    }
    return _localFileFutures.putIfAbsent(futureKey, () async {
      try {
        return await _downloadMediaToLocalCache(item);
      } catch (_) {
        return null;
      } finally {
        _localFileFutures.remove(futureKey);
      }
    });
  }

  Future<String?> ensureLocalThumbnailFile(
    BabyCloudMedia item, {
    bool forceRemote = false,
  }) {
    final existing = _readableThumbnailPath(item);
    if (existing != null) {
      _logMediaCache('缩略图已记录且可读', item, existing);
      return Future<String?>.value(existing);
    }
    if (!item.isVideo) {
      final original = _readableMediaPath(item);
      if (original != null) {
        final generated = _prepareLocalThumbnailPath(
          localPath: original,
          fileName: item.fileName,
          mediaType: item.mediaType,
          cacheKey: item.sha256,
          existingThumbnailPath: item.localThumbnailPath,
        ).then((path) {
          if (path != null && path != original) {
            _logMediaCache('缩略图从本地原图生成', item, path);
            return _rememberLocalThumbnailPath(item, path);
          }
          _logMediaCache('缩略图使用本地原图替代', item, original);
          return Future<String?>.value(original);
        });
        return generated;
      }
      final originalCachedFile = _localMediaCacheFile(item);
      if (originalCachedFile != null && originalCachedFile.existsSync()) {
        final generated = _prepareLocalThumbnailPath(
          localPath: originalCachedFile.path,
          fileName: item.fileName,
          mediaType: item.mediaType,
          cacheKey: item.sha256,
          existingThumbnailPath: item.localThumbnailPath,
        ).then((path) async {
          await _rememberLocalMediaPath(item, originalCachedFile.path);
          if (path != null && path != originalCachedFile.path) {
            _logMediaCache('缩略图从原图磁盘缓存生成', item, path);
            return _rememberLocalThumbnailPath(item, path);
          }
          _logMediaCache('缩略图从原图磁盘缓存替代', item, originalCachedFile.path);
          return originalCachedFile.path;
        });
        return generated;
      }
    }
    final cachedFile = _localThumbnailCacheFile(item);
    if (cachedFile != null && cachedFile.existsSync()) {
      _logMediaCache('缩略图磁盘命中', item, cachedFile.path);
      return _rememberLocalThumbnailPath(item, cachedFile.path);
    }
    final stored = _storage.babyCloudMediaBox.get(item.id);
    final storedPath = stored == null ? null : _readableThumbnailPath(stored);
    if (storedPath != null) {
      item.localThumbnailPath = storedPath;
      _logMediaCache('缩略图从Hive记录命中', item, storedPath);
      return Future<String?>.value(storedPath);
    }
    if (stored != null) {
      if (!stored.isVideo) {
        final storedOriginal = _readableMediaPath(stored);
        if (storedOriginal != null) {
          item.localPath = storedOriginal;
          final generated = _prepareLocalThumbnailPath(
            localPath: storedOriginal,
            fileName: stored.fileName,
            mediaType: stored.mediaType,
            cacheKey: stored.sha256,
            existingThumbnailPath: stored.localThumbnailPath,
          ).then((path) {
            if (path != null && path != storedOriginal) {
              item.localThumbnailPath = path;
              _logMediaCache('缩略图从Hive原图记录生成', item, path);
              return _rememberLocalThumbnailPath(stored, path);
            }
            _logMediaCache('缩略图从Hive原图记录替代', item, storedOriginal);
            return Future<String?>.value(storedOriginal);
          });
          return generated;
        }
        final storedOriginalCachedFile = _localMediaCacheFile(stored);
        if (storedOriginalCachedFile != null &&
            storedOriginalCachedFile.existsSync()) {
          item.localPath = storedOriginalCachedFile.path;
          final generated = _prepareLocalThumbnailPath(
            localPath: storedOriginalCachedFile.path,
            fileName: stored.fileName,
            mediaType: stored.mediaType,
            cacheKey: stored.sha256,
            existingThumbnailPath: stored.localThumbnailPath,
          ).then((path) async {
            await _rememberLocalMediaPath(stored, storedOriginalCachedFile.path);
            if (path != null && path != storedOriginalCachedFile.path) {
              item.localThumbnailPath = path;
              _logMediaCache('缩略图从Hive原图磁盘缓存生成', item, path);
              return _rememberLocalThumbnailPath(stored, path);
            }
            _logMediaCache(
              '缩略图从Hive原图磁盘缓存替代',
              item,
              storedOriginalCachedFile.path,
            );
            return storedOriginalCachedFile.path;
          });
          return generated;
        }
      }
      final storedCachedFile = _localThumbnailCacheFile(stored);
      if (storedCachedFile != null && storedCachedFile.existsSync()) {
        item.localThumbnailPath = storedCachedFile.path;
        _logMediaCache('缩略图从Hive记录推导磁盘命中', item, storedCachedFile.path);
        return _rememberLocalThumbnailPath(stored, storedCachedFile.path);
      }
    }
    if (item.thumbnailRemotePath?.trim().isNotEmpty != true) {
      return Future<String?>.value(null);
    }

    final futureKey = _localMediaCacheKey(item);
    if (!forceRemote && _thumbnailAutoFailedKeys.contains(futureKey)) {
      return Future<String?>.value(null);
    }
    if (_localThumbnailFutures.containsKey(futureKey)) {
      _logMediaCache('缩略图复用下载任务', item, futureKey);
    } else {
      _logMediaCache('缩略图准备远程下载', item, item.thumbnailRemotePath ?? '');
    }
    return _localThumbnailFutures.putIfAbsent(futureKey, () async {
      try {
        final path = await _downloadThumbnailToLocalCache(item);
        if (path != null) _thumbnailAutoFailedKeys.remove(futureKey);
        return path;
      } catch (_) {
        _thumbnailAutoFailedKeys.add(futureKey);
        return null;
      } finally {
        _localThumbnailFutures.remove(futureKey);
      }
    });
  }

  Future<void> processQueue() async {
    if (_queueRunning) return;
    _queueRunning = true;
    var keepAliveStarted = false;
    try {
      while (true) {
        final runnable = _storage.babyCloudUploadTaskBox.values
            .where((t) =>
                t.status == 'queued' ||
                (t.status == 'running' && t.progress < 1))
            .take(2)
            .toList();
        if (runnable.isEmpty) break;
        await _startUploadKeepAlive(activeCount: runnable.length);
        keepAliveStarted = true;
        await Future.wait(
          runnable.map(_runBackgroundTask),
        );
        _reloadTasks();
      }
    } finally {
      _queueRunning = false;
      if (keepAliveStarted) {
        await _stopUploadKeepAlive();
      }
    }
  }

  Future<void> _startUploadKeepAlive({required int activeCount}) async {
    await AndroidBackgroundNetworkService.startOperation(
      'baby_cloud_queue',
      title: 'StarBank 亲宝宝',
      text: activeCount > 1 ? '正在处理云相册后台任务' : '正在上传云相册内容',
    );
  }

  Future<void> _stopUploadKeepAlive() async {
    await AndroidBackgroundNetworkService.stopOperation('baby_cloud_queue');
  }

  Future<void> _runBackgroundTask(BabyCloudUploadTask task) {
    switch (task.taskType) {
      case 'metadata':
        return _runMetadataTask(task);
      case 'purgeMedia':
        return _runPurgeMediaTask(task);
      case 'purgeEntry':
        return _runPurgeEntryTask(task);
      default:
        return _runUploadTask(task);
    }
  }

  Future<void> pauseTask(BabyCloudUploadTask task) async {
    if (task.status == 'completed') return;
    task.status = 'paused';
    task.updatedAt = DateTime.now();
    await task.save();
    _reloadTasks();
  }

  Future<void> pauseTasks(Iterable<BabyCloudUploadTask> tasks) async {
    var changed = false;
    for (final task in tasks) {
      if (task.status != 'queued' && task.status != 'running') continue;
      task
        ..status = 'paused'
        ..updatedAt = DateTime.now();
      await task.save();
      changed = true;
    }
    if (changed) _reloadTasks();
  }

  Future<void> resumeTask(BabyCloudUploadTask task) async {
    if (task.status != 'paused' && task.status != 'failed') return;
    _deletedTaskIds.remove(task.id);
    task.status = 'queued';
    task.errorMessage = null;
    task.retryCount = 0;
    task.updatedAt = DateTime.now();
    await task.save();
    _reloadTasks();
    unawaited(processQueue());
  }

  Future<void> resumeTasks(Iterable<BabyCloudUploadTask> tasks) async {
    var changed = false;
    for (final task in tasks) {
      if (task.status != 'paused' && task.status != 'failed') continue;
      _deletedTaskIds.remove(task.id);
      task
        ..status = 'queued'
        ..errorMessage = null
        ..retryCount = 0
        ..updatedAt = DateTime.now();
      await task.save();
      changed = true;
    }
    if (!changed) return;
    _reloadTasks();
    unawaited(processQueue());
  }

  Future<void> retryFailedTasks([Iterable<BabyCloudUploadTask>? tasks]) {
    final failed = (tasks ?? _storage.babyCloudUploadTaskBox.values)
        .where((task) => task.status == 'failed')
        .toList();
    return resumeTasks(failed);
  }

  Future<void> cancelTask(BabyCloudUploadTask task) async {
    task.status = 'cancelled';
    task.updatedAt = DateTime.now();
    await task.save();
    _reloadTasks();
  }

  Future<void> deleteTask(BabyCloudUploadTask task) async {
    if (task.isActive) return;
    _deletedTaskIds.add(task.id);
    task.status = 'cancelled';
    task.updatedAt = DateTime.now();
    try {
      if (task.isInBox) {
        await task.delete();
      }
    } catch (_) {}
    _reloadTasks();
  }

  Future<void> clearCompletedTasks() async {
    await clearSuccessfulTasks();
  }

  Future<int> clearSuccessfulTasks() async {
    return _clearTasksWhere((task) => task.status == 'completed');
  }

  Future<int> clearFailedTasks() async {
    return _clearTasksWhere((task) => task.status == 'failed');
  }

  Future<int> _clearTasksWhere(
    bool Function(BabyCloudUploadTask task) test,
  ) async {
    final targets = _storage.babyCloudUploadTaskBox.values
        .where((task) => !task.isActive && test(task))
        .toList();
    for (final task in targets) {
      _deletedTaskIds.add(task.id);
      await task.delete();
    }
    _reloadTasks();
    return targets.length;
  }

  Future<bool> queueHardDeleteMedia(BabyCloudMedia item) {
    if (item.isPurged) return Future.value(false);
    return _enqueueBackgroundTask(
      taskType: 'purgeMedia',
      targetId: item.id,
      babyId: item.babyId,
      sourceId: item.dataSourceId,
      title: '永久删除文件',
      mediaType: item.mediaType,
      entryId: item.entryId,
    );
  }

  Future<bool> queueHardDeleteEntry(BabyCloudEntry entry) {
    if (entry.isPurged) return Future.value(false);
    return _enqueueBackgroundTask(
      taskType: 'purgeEntry',
      targetId: entry.id,
      babyId: entry.babyId,
      sourceId: entry.dataSourceId,
      title: '永久删除动态',
      mediaType: 'entry',
      entryId: entry.id,
    );
  }

  Future<bool> _enqueueBackgroundTask({
    required String taskType,
    required String targetId,
    required String babyId,
    required String sourceId,
    required String title,
    required String mediaType,
    required String entryId,
  }) async {
    final existing = _storage.babyCloudUploadTaskBox.values
        .toList()
        .firstWhereOrNull((task) =>
            task.taskType == taskType &&
            task.targetId == targetId &&
            task.babyId == babyId &&
            task.dataSourceId == sourceId &&
            task.status != 'completed' &&
            task.status != 'cancelled');
    if (existing != null) {
      existing
        ..status = 'queued'
        ..progress = 0
        ..errorMessage = null
        ..updatedAt = DateTime.now();
      await existing.save();
      _reloadTasks();
      unawaited(processQueue());
      return true;
    }

    final task = BabyCloudUploadTask(
      id: '${DateTime.now().microsecondsSinceEpoch}_${taskType}_$targetId',
      babyId: babyId,
      dataSourceId: sourceId,
      localPath: '',
      fileName: title,
      mediaType: mediaType,
      mimeType: 'application/json',
      sizeBytes: 0,
      entryId: entryId,
      taskType: taskType,
      targetId: targetId,
    );
    await _storage.babyCloudUploadTaskBox.put(task.id, task);
    uploadTasks.insert(0, task);
    unawaited(processQueue());
    return true;
  }

  Future<void> softDeleteMedia(BabyCloudMedia item) async {
    await _waitForActiveSync();
    item
      ..deletedAt = DateTime.now()
      ..deleteReason = 'singleFileDeleted'
      ..updatedAt = DateTime.now();
    await item.save();
    final entry = _storage.babyCloudEntryBox.get(item.entryId);
    if (entry != null) {
      entry.updatedAt = DateTime.now();
      await entry.save();
    }
    _refreshEntries();
    _refreshMedia();
    await publishIndexFor(item.dataSourceId, item.babyId);
  }

  Future<void> softDeleteEntry(List<BabyCloudMedia> items) async {
    if (items.isEmpty) return;
    await _waitForActiveSync();
    final now = DateTime.now();
    final sourceId = items.first.dataSourceId;
    final babyId = items.first.babyId;
    final entryId = items.first.entryId;
    final mediaIds = items.map((item) => item.id).toSet();
    final entry = _storage.babyCloudEntryBox.get(entryId);
    if (entry != null) {
      entry
        ..deletedAt = now
        ..deleteReason = 'entryDeleted'
        ..mediaIds = {...entry.mediaIds, ...mediaIds}.toList()
        ..updatedAt = now;
      await entry.save();
    }
    for (final item in items) {
      item
        ..deletedAt = now
        ..deleteReason = 'entryDeleted'
        ..updatedAt = now;
      await item.save();
    }
    _refreshEntries();
    _refreshMedia();
    await publishIndexFor(sourceId, babyId);
  }

  Future<void> restoreMedia(BabyCloudMedia item) async {
    await _waitForActiveSync();
    item
      ..deletedAt = null
      ..deleteReason = null
      ..replacedByMediaId = null
      ..updatedAt = DateTime.now();
    await item.save();
    final entry = _storage.babyCloudEntryBox.get(item.entryId);
    if (entry != null && entry.deleteReason != 'entryDeleted') {
      entry.updatedAt = DateTime.now();
      await entry.save();
    }
    _refreshEntries();
    _refreshMedia();
    await publishIndexFor(item.dataSourceId, item.babyId);
  }

  Future<void> restoreEntry(BabyCloudEntry entry) async {
    await _waitForActiveSync();
    final now = DateTime.now();
    entry
      ..deletedAt = null
      ..deleteReason = null
      ..updatedAt = now;
    await entry.save();
    final mediaIds = entry.mediaIds.toSet();
    final items = _storage.babyCloudMediaBox.values
        .where((item) =>
            (item.entryId == entry.id || mediaIds.contains(item.id)) &&
            item.babyId == entry.babyId &&
            (item.dataSourceId == entry.dataSourceId ||
                item.libraryId == entry.libraryId))
        .toList();
    for (final item in items) {
      if (!item.isDeleted || item.isPurged) continue;
      item
        ..deletedAt = null
        ..deleteReason = null
        ..updatedAt = now;
      await item.save();
    }
    _refreshEntries();
    _refreshMedia();
    await publishIndexFor(entry.dataSourceId, entry.babyId);
  }

  Future<void> hardDeleteMedia(BabyCloudMedia item) async {
    await _waitForActiveSync();
    try {
      await _purgeMediaNow(item);
    } catch (e) {
      ToastUtils.showWarning('云端暂不可用，未执行永久删除：$e');
    }
  }

  Future<void> hardDeleteEntry(BabyCloudEntry entry) async {
    await _waitForActiveSync();
    try {
      await _purgeEntryNow(entry);
    } catch (e) {
      ToastUtils.showWarning('云端暂不可用，未执行永久删除：$e');
    }
  }

  Future<void> _purgeMediaNow(BabyCloudMedia item) async {
    final source = sources.firstWhereOrNull((s) => s.id == item.dataSourceId);
    if (source != null) {
      final check = await checkSource(source);
      if (check.ok) {
        final client = await _remoteClientForSource(source, check: check);
        if (item.remotePath.trim().isNotEmpty) {
          try {
            await client.remove(item.remotePath);
          } catch (_) {}
        }
        if (item.thumbnailRemotePath?.trim().isNotEmpty == true) {
          try {
            await client.remove(item.thumbnailRemotePath!);
          } catch (_) {}
        }
      } else {
        throw Exception(check.message);
      }
    }
    final sourceId = item.dataSourceId;
    final babyId = item.babyId;
    item
      ..purgedAt = DateTime.now()
      ..updatedAt = DateTime.now();
    await item.save();
    _refreshEntries();
    _refreshMedia();
    await publishIndexFor(sourceId, babyId);
  }

  Future<void> _purgeEntryNow(BabyCloudEntry entry) async {
    final source = sources.firstWhereOrNull((s) => s.id == entry.dataSourceId);
    final mediaIds = entry.mediaIds.toSet();
    final items = _storage.babyCloudMediaBox.values
        .where((item) =>
            (item.entryId == entry.id || mediaIds.contains(item.id)) &&
            item.babyId == entry.babyId &&
            item.purgedAt == null)
        .toList();
    if (source != null) {
      final check = await checkSource(source);
      if (check.ok) {
        final client = await _remoteClientForSource(source, check: check);
        for (final item in items) {
          if (item.remotePath.trim().isNotEmpty) {
            try {
              await client.remove(item.remotePath);
            } catch (_) {}
          }
          if (item.thumbnailRemotePath?.trim().isNotEmpty == true) {
            try {
              await client.remove(item.thumbnailRemotePath!);
            } catch (_) {}
          }
        }
      } else {
        throw Exception(check.message);
      }
    }
    final now = DateTime.now();
    for (final item in items) {
      item
        ..purgedAt = now
        ..updatedAt = now;
      await item.save();
    }
    entry
      ..purgedAt = now
      ..updatedAt = now;
    await entry.save();
    _refreshEntries();
    _refreshMedia();
    await publishIndexFor(entry.dataSourceId, entry.babyId);
  }

  Future<void> publishIndexFor(String sourceId, String babyId) async {
    await _waitForActiveSync();
    await _writeLocalIndexFor(sourceId, babyId);
  }

  Future<void> _writeLocalIndexFor(
    String sourceId,
    String babyId, {
    bool waitForActiveSync = true,
  }) async {
    if (waitForActiveSync) {
      await _waitForActiveSync();
    }
    final source = sources.firstWhereOrNull((s) => s.id == sourceId);
    if (source == null) return;
    final check = await checkSource(source);
    if (!check.ok) return;
    final client = await _remoteClientForSource(source, check: check);
    final babyName = _babySafeName(babyId);
    final baby = Baby(id: babyId, name: babyName, avatarPath: '');
    await _prepareBabyCloudStructure(client, source, baby);
    final indexPath = _indexPath(source, baby);
    final remote = await _readRemoteIndexAt(client, indexPath);
    if (remote != null) {
      await _mergeRemoteIndex(source, baby, remote);
    }
    await _normalizeLocalCloudIdentity(source, baby);
    final cloudBabyId = _cloudBabyId(source, baby);
    final scope = _libraryScopeForSource(source);
    final entryItems = _storage.babyCloudEntryBox.values
        .where((entry) =>
            _entryBelongsToSource(source, entry) && entry.babyId == babyId)
        .map((entry) => entry.toJson())
        .toList();
    final items = _storage.babyCloudMediaBox.values
        .where((m) => _mediaBelongsToSource(source, m) && m.babyId == babyId)
        .map((m) => m.toJson())
        .toList();
    final payload = {
      'format': _albumIndexFormat,
      'type': _albumIndexType,
      'libraryId': scope,
      'cloudBabyId': cloudBabyId,
      'sourceId': sourceId,
      'babyId': babyId,
      'babyName': babyName,
      'babyDir': _babyDir(source, baby),
      'updatedAt': DateTime.now().toIso8601String(),
      'entries': entryItems,
      'media': items,
    };
    await client.write(indexPath, utf8.encode(jsonEncode(payload)));
    await _markBabySyncCacheFresh(sourceId, babyId);
    await _storage.babyCloudSourceBox.put(source.id, source);
    _refreshEntries();
    _refreshMedia();
  }

  Future<List<Map<String, dynamic>>> listRemoteBabyDirs(
      BabyCloudSource source) async {
    final check = await checkSource(source);
    if (!check.ok) throw Exception(check.message);
    final client = await _remoteClientForSource(source, check: check);
    final manifest = await _readLibraryManifest(client, source);
    if (manifest == null) return const [];
    final libraryId = manifest['libraryId']?.toString().trim() ?? '';
    if (libraryId.isNotEmpty) {
      source.libraryId = libraryId;
      source.libraryName = manifest['name']?.toString();
      await _storage.babyCloudSourceBox.put(source.id, source);
    }
    return _manifestBabies(manifest).map((babyNode) {
      final localBabyIds =
          ((babyNode['localBabyIds'] as List?) ?? const <dynamic>[])
              .map((e) => e.toString())
              .where((id) => id.trim().isNotEmpty)
              .toList();
      final cloudBabyId = babyNode['cloudBabyId']?.toString() ?? '';
      final path = _normalizeRemoteDir(
        babyNode['babyDir']?.toString().trim().isNotEmpty == true
            ? babyNode['babyDir'].toString()
            : '${_rootChildPath(source, 'babies')}/$cloudBabyId',
      );
      final name = babyNode['name']?.toString().trim().isNotEmpty == true
          ? babyNode['name'].toString()
          : _remoteName(path);
      return {
        'path': path,
        'name': name,
        'babyId': localBabyIds.isNotEmpty ? localBabyIds.first : cloudBabyId,
        'cloudBabyId': cloudBabyId,
        'localBabyIds': localBabyIds,
      };
    }).toList()
      ..sort((a, b) => (a['name'] ?? '').toString().compareTo(
            (b['name'] ?? '').toString(),
          ));
  }

  void _reloadTasks() {
    uploadTasks.assignAll(_storage.babyCloudUploadTaskBox.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
    uploadTasks.refresh();
  }

  Future<void> _runMetadataTask(BabyCloudUploadTask task) async {
    try {
      if (!await _checkpointTask(task)) return;
      task
        ..status = 'running'
        ..progress = 0.2
        ..errorMessage = null
        ..updatedAt = DateTime.now();
      if (!await _saveTaskIfAlive(task)) return;

      await publishIndexFor(task.dataSourceId, task.babyId);
      if (!await _checkpointTask(task)) return;
      task
        ..status = 'completed'
        ..progress = 1
        ..errorMessage = null
        ..updatedAt = DateTime.now();
      await _saveTaskIfAlive(task);
    } catch (e) {
      await _failTask(task, e.toString());
    }
  }

  Future<void> _runPurgeMediaTask(BabyCloudUploadTask task) async {
    try {
      if (!await _checkpointTask(task)) return;
      task
        ..status = 'running'
        ..progress = 0.12
        ..errorMessage = null
        ..updatedAt = DateTime.now();
      if (!await _saveTaskIfAlive(task)) return;

      final item = _storage.babyCloudMediaBox.get(task.targetId);
      if (item != null && !item.isPurged) {
        await _purgeMediaNow(item);
      }
      if (!await _checkpointTask(task)) return;
      task
        ..status = 'completed'
        ..progress = 1
        ..errorMessage = null
        ..updatedAt = DateTime.now();
      await _saveTaskIfAlive(task);
    } catch (e) {
      await _failTask(task, e.toString());
    }
  }

  Future<void> _runPurgeEntryTask(BabyCloudUploadTask task) async {
    try {
      if (!await _checkpointTask(task)) return;
      task
        ..status = 'running'
        ..progress = 0.12
        ..errorMessage = null
        ..updatedAt = DateTime.now();
      if (!await _saveTaskIfAlive(task)) return;

      final entry = _storage.babyCloudEntryBox.get(task.targetId);
      if (entry != null && !entry.isPurged) {
        await _purgeEntryNow(entry);
      }
      if (!await _checkpointTask(task)) return;
      task
        ..status = 'completed'
        ..progress = 1
        ..errorMessage = null
        ..updatedAt = DateTime.now();
      await _saveTaskIfAlive(task);
    } catch (e) {
      await _failTask(task, e.toString());
    }
  }

  Future<void> _runUploadTask(BabyCloudUploadTask task) async {
    if (!_shouldContinueTask(task)) return;
    if (task.errorMessage?.isNotEmpty == true) {
      task
        ..errorMessage = null
        ..updatedAt = DateTime.now();
      if (!await _saveTaskIfAlive(task)) return;
    }
    final source = sources.firstWhereOrNull((s) => s.id == task.dataSourceId);
    if (source == null) {
      await _failTask(task, '当前数据源不可用或暂不支持上传');
      return;
    }
    final baby = _storage.babyBox.values
        .toList()
        .firstWhereOrNull((b) => b.id == task.babyId);
    if (baby == null) {
      await _failTask(task, '宝宝资料已不存在');
      return;
    }
    await _waitForActiveSync();
    final file = File(task.localPath);
    if (!await file.exists()) {
      await _failTask(task, '原文件已不存在，请重新选择');
      return;
    }
    final check = await checkSource(source);
    if (!check.ok) {
      await _failTask(task, check.message, allowRetry: true);
      return;
    }

    try {
      if (!await _checkpointTask(task)) return;
      task
        ..status = 'running'
        ..progress = 0.05
        ..errorMessage = null
        ..updatedAt = DateTime.now();
      if (!await _saveTaskIfAlive(task)) return;

      final bytes = await file.readAsBytes();
      if (!await _checkpointTask(task)) return;
      final hash = task.sha256 ?? sha256.convert(bytes).toString();
      task
        ..sha256 = hash
        ..progress = 0.25
        ..updatedAt = DateTime.now();
      if (!await _saveTaskIfAlive(task)) return;

      final client = await _remoteClientForSource(source, check: check);
      await _prepareBabyCloudStructure(client, source, baby);
      await _normalizeLocalCloudIdentity(source, baby);

      final duplicate =
          _storage.babyCloudMediaBox.values.toList().firstWhereOrNull(
                (m) =>
                    _mediaBelongsToSource(source, m) &&
                    m.babyId == baby.id &&
                    m.sha256 == hash &&
                    !m.isDeleted,
              );
      if (duplicate != null) {
        if (!await _checkpointTask(task)) return;
        final thumbnailRemotePath =
            duplicate.thumbnailRemotePath?.trim().isNotEmpty == true
                ? duplicate.thumbnailRemotePath
                : await _uploadTaskThumbnailIfAvailable(
                    client: client,
                    source: source,
                    baby: baby,
                    task: task,
                    hash: hash,
                  );
        if (!await _checkpointTask(task)) return;
        duplicate
          ..dataSourceId = source.id
          ..libraryId = _libraryScopeForSource(source)
          ..cloudBabyId = _cloudBabyId(source, baby)
          ..thumbnailRemotePath = thumbnailRemotePath
          ..localThumbnailPath =
              duplicate.localThumbnailPath ?? task.localThumbnailPath
          ..description = task.description ?? duplicate.description
          ..tags = task.tags.isNotEmpty ? task.tags : duplicate.tags
          ..locationName = task.locationName ?? duplicate.locationName
          ..actorRole = task.actorRole ?? duplicate.actorRole
          ..visibility = task.visibility
          ..entryId = task.entryId
          ..takenAt = task.takenAt ?? duplicate.takenAt
          ..updatedAt = DateTime.now();
        await duplicate.save();
        await _ensureEntryForMedia(source, baby, duplicate);
        _refreshMedia();
        task
          ..status = 'completed'
          ..progress = 1
          ..remotePath = duplicate.remotePath
          ..errorMessage = null
          ..retryCount = 0
          ..updatedAt = DateTime.now();
        await _saveTaskIfAlive(task);
        await publishIndexFor(source.id, baby.id);
        return;
      }

      String? remotePath = task.remotePath;
      if (remotePath != null && remotePath.trim().isNotEmpty) {
        remotePath = _normalizeRemoteDir(remotePath);
        final albumRoot = '${_babyDir(source, baby)}/album/';
        if (!remotePath.startsWith(albumRoot)) {
          remotePath = null;
        } else {
          try {
            await client.stat(remotePath);
          } catch (_) {
            remotePath = null;
          }
        }
      }
      remotePath ??= _mediaPath(
        source,
        baby,
        task.fileName,
        hash,
        task.mediaType,
        task.takenAt ?? file.lastModifiedSync(),
      );
      if (task.remotePath != remotePath) {
        task
          ..remotePath = remotePath
          ..updatedAt = DateTime.now();
        if (!await _saveTaskIfAlive(task)) return;
      }
      if (!await _checkpointTask(task)) return;
      if (task.progress < 0.85) {
        await _ensureRemoteDir(client, _parentRemoteDir(remotePath));
        await client.write(remotePath, bytes, mimeType: task.mimeType);
      }
      if (!await _checkpointTask(task)) return;
      task
        ..progress = 0.85
        ..remotePath = remotePath
        ..updatedAt = DateTime.now();
      if (!await _saveTaskIfAlive(task)) return;

      final thumbnailRemotePath = await _uploadTaskThumbnailIfAvailable(
        client: client,
        source: source,
        baby: baby,
        task: task,
        hash: hash,
      );
      if (!await _checkpointTask(task)) return;

      final item = BabyCloudMedia(
        id: '${DateTime.now().microsecondsSinceEpoch}_$hash',
        babyId: baby.id,
        dataSourceId: source.id,
        libraryId: _libraryScopeForSource(source),
        cloudBabyId: _cloudBabyId(source, baby),
        sha256: hash,
        fileName: task.fileName,
        mediaType: task.mediaType,
        mimeType: task.mimeType,
        remotePath: remotePath,
        thumbnailRemotePath: thumbnailRemotePath,
        localPath: task.localPath,
        localThumbnailPath: task.localThumbnailPath,
        sizeBytes: bytes.length,
        takenAt: task.takenAt ?? File(task.localPath).lastModifiedSync(),
        entryId: task.entryId,
        description: task.description,
        tags: task.tags,
        locationName: task.locationName,
        actorRole: task.actorRole,
        visibility: task.visibility,
      );
      await _storage.babyCloudMediaBox.put(item.id, item);
      await _ensureEntryForMedia(source, baby, item);
      _refreshEntries();
      _refreshMedia();
      await publishIndexFor(source.id, baby.id);

      if (!await _checkpointTask(task)) return;
      task
        ..status = 'completed'
        ..progress = 1
        ..errorMessage = null
        ..retryCount = 0
        ..updatedAt = DateTime.now();
      await _saveTaskIfAlive(task);
      _refreshMedia();
    } catch (e) {
      await _failTask(task, e.toString(), allowRetry: true);
    }
  }

  bool _shouldContinueTask(BabyCloudUploadTask task) {
    return !_deletedTaskIds.contains(task.id) &&
        task.status != 'paused' &&
        task.status != 'cancelled';
  }

  Future<bool> _checkpointTask(BabyCloudUploadTask task) async {
    if (_deletedTaskIds.contains(task.id)) return false;
    if (task.status == 'paused' || task.status == 'cancelled') {
      task.updatedAt = DateTime.now();
      await _saveTaskIfAlive(task);
      return false;
    }
    return true;
  }

  Future<bool> _saveTaskIfAlive(BabyCloudUploadTask task) async {
    if (_deletedTaskIds.contains(task.id) || !task.isInBox) return false;
    if (task.status == 'completed' && task.errorMessage?.isNotEmpty == true) {
      task.errorMessage = null;
    }
    await task.save();
    _reloadTasks();
    return true;
  }

  Future<void> _failTask(
    BabyCloudUploadTask task,
    String message, {
    bool allowRetry = false,
  }) async {
    if (_deletedTaskIds.contains(task.id) || !task.isInBox) return;
    if (allowRetry &&
        task.taskType == 'upload' &&
        task.retryCount < _maxUploadRetries &&
        _shouldContinueTask(task)) {
      final nextRetry = task.retryCount + 1;
      task
        ..status = 'queued'
        ..progress = 0
        ..retryCount = nextRetry
        ..errorMessage = '上传失败，自动重试 $nextRetry/$_maxUploadRetries：$message'
        ..updatedAt = DateTime.now();
      await task.save();
      _reloadTasks();
      return;
    }
    task
      ..status = 'failed'
      ..errorMessage = message
      ..updatedAt = DateTime.now();
    await task.save();
    _reloadTasks();
  }

  String? _readableMediaPath(BabyCloudMedia item) {
    final path = item.localPath;
    if (path == null || path.trim().isEmpty) return null;
    try {
      return File(path).existsSync() ? path : null;
    } catch (_) {
      return null;
    }
  }

  String? _readableThumbnailPath(BabyCloudMedia item) {
    final path = item.localThumbnailPath;
    if (path == null || path.trim().isEmpty) return null;
    if (!item.isVideo &&
        !item.isAudio &&
        item.localPath != null &&
        item.localPath!.trim().isNotEmpty &&
        path == item.localPath) {
      return null;
    }
    try {
      return File(path).existsSync() ? path : null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _prepareLocalThumbnailPath({
    required String localPath,
    required String fileName,
    required String mediaType,
    required String cacheKey,
    String? existingThumbnailPath,
  }) async {
    final existing = existingThumbnailPath?.trim();
    final existingIsOriginal = existing == localPath;
    if (existing != null && existing.isNotEmpty) {
      try {
        if (await File(existing).exists() && !existingIsOriginal) {
          return existing;
        }
      } catch (_) {}
    }
    if (mediaType != 'photo') {
      return existingIsOriginal ? null : existingThumbnailPath;
    }
    final generated = await _generatePhotoThumbnail(
      sourcePath: localPath,
      cacheKey: cacheKey,
    );
    return generated ?? (existingIsOriginal ? null : existingThumbnailPath);
  }

  Future<String?> _generatePhotoThumbnail({
    required String sourcePath,
    required String cacheKey,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) return null;
    try {
      final base = _appDocumentsDir ?? await getApplicationDocumentsDirectory();
      _appDocumentsDir ??= base;
      final dir = Directory(
        [
          base.path,
          'baby_cloud_thumbnails',
        ].join(Platform.pathSeparator),
      );
      await dir.create(recursive: true);
      final file = File(
        [
          dir.path,
          '${_safeFileSegment(cacheKey)}_${_generatedThumbnailSize}_q$_generatedThumbnailJpegQuality.jpg',
        ].join(Platform.pathSeparator),
      );
      if (await file.exists() && await file.length() > 0) return file.path;

      final bytes = await source.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      final oriented = img.bakeOrientation(decoded);
      final resized = img.copyResize(
        oriented,
        width: oriented.width >= oriented.height
            ? _generatedThumbnailSize
            : null,
        height: oriented.height > oriented.width
            ? _generatedThumbnailSize
            : null,
        interpolation: img.Interpolation.average,
      );
      final thumbnailBytes = img.encodeJpg(
        resized,
        quality: _generatedThumbnailJpegQuality,
      );
      if (thumbnailBytes.isEmpty) return null;
      await file.writeAsBytes(thumbnailBytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _downloadMediaToLocalCache(BabyCloudMedia item) async {
    if (item.remotePath.trim().isEmpty) return null;
    final source = sources.firstWhereOrNull((s) => s.id == item.dataSourceId);
    if (source == null) return null;

    final dir = await _localMediaCacheDir(item);
    final file = _localMediaCacheFileInDir(item, dir.path);
    if (await file.exists()) {
      _logMediaCache('原图下载前磁盘命中', item, file.path);
      return _rememberLocalMediaPath(item, file.path);
    }
    _logMediaCache('原图开始远程下载', item, item.remotePath);
    final client = await _remoteClientForSource(source);
    final bytes = await client.read(item.remotePath);
    await file.writeAsBytes(bytes, flush: true);
    _logMediaCache('原图远程下载完成', item, file.path);
    return _rememberLocalMediaPath(item, file.path);
  }

  Future<String?> _downloadThumbnailToLocalCache(BabyCloudMedia item) async {
    final remotePath = item.thumbnailRemotePath?.trim();
    if (remotePath == null || remotePath.isEmpty) return null;
    final source = sources.firstWhereOrNull((s) => s.id == item.dataSourceId);
    if (source == null) return null;

    final dir = await _localMediaCacheDir(item);
    final file = _localThumbnailCacheFileInDir(item, dir.path);
    if (await file.exists()) {
      _logMediaCache('缩略图下载前磁盘命中', item, file.path);
      return _rememberLocalThumbnailPath(item, file.path);
    }
    _logMediaCache('缩略图开始远程下载', item, remotePath);
    final client = await _remoteClientForSource(source);
    final bytes = await client.read(remotePath);
    await file.writeAsBytes(bytes, flush: true);
    _logMediaCache('缩略图远程下载完成', item, file.path);
    return _rememberLocalThumbnailPath(item, file.path);
  }

  File? _localMediaCacheFile(BabyCloudMedia item) {
    final dirPath = _localMediaCacheDirPath(item);
    if (dirPath == null) return null;
    return _localMediaCacheFileInDir(item, dirPath);
  }

  File _localMediaCacheFileInDir(BabyCloudMedia item, String dirPath) {
    final ext = _extension(item.fileName).isNotEmpty
        ? _extension(item.fileName)
        : item.isVideo
            ? '.mp4'
            : item.isAudio
                ? '.m4a'
                : '.jpg';
    return File(
      [
        dirPath,
        '${_safeFileSegment(item.sha256)}$ext',
      ].join(Platform.pathSeparator),
    );
  }

  File? _localThumbnailCacheFile(BabyCloudMedia item) {
    final dirPath = _localMediaCacheDirPath(item);
    if (dirPath == null) return null;
    return _localThumbnailCacheFileInDir(item, dirPath);
  }

  File _localThumbnailCacheFileInDir(BabyCloudMedia item, String dirPath) {
    final remotePath = item.thumbnailRemotePath?.trim() ?? '';
    final ext = _extension(remotePath).isNotEmpty
        ? _extension(remotePath)
        : _extension(item.fileName).isNotEmpty
            ? _extension(item.fileName)
            : '.jpg';
    return File(
      [
        dirPath,
        '${_safeFileSegment(item.sha256)}_thumb$ext',
      ].join(Platform.pathSeparator),
    );
  }

  String? _localMediaCacheDirPath(BabyCloudMedia item) {
    final base = _appDocumentsDir?.path;
    if (base == null) return null;
    return [
      base,
      'baby_cloud_cache',
      _safeFileSegment(item.dataSourceId),
      _safeFileSegment(item.babyId),
    ].join(Platform.pathSeparator);
  }

  String _localMediaCacheKey(BabyCloudMedia item) {
    return [
      item.dataSourceId,
      item.babyId,
      item.sha256,
    ].map(_safeFileSegment).join('|');
  }

  Future<String?> _rememberLocalMediaPath(
    BabyCloudMedia item,
    String path,
  ) async {
    item.localPath = path;
    final generatedThumbnail = !item.isVideo && !item.isAudio
        ? await _prepareLocalThumbnailPath(
            localPath: path,
            fileName: item.fileName,
            mediaType: item.mediaType,
            cacheKey: item.sha256,
            existingThumbnailPath: item.localThumbnailPath,
          )
        : null;
    if (!item.isVideo &&
        !item.isAudio &&
        generatedThumbnail != null &&
        generatedThumbnail != path &&
        _readableThumbnailPath(item) == null) {
      item.localThumbnailPath = generatedThumbnail;
    }
    final stored = _storage.babyCloudMediaBox.get(item.id);
    if (stored != null && !identical(stored, item)) {
      stored.localPath = path;
      final storedGeneratedThumbnail = !stored.isVideo && !stored.isAudio
          ? await _prepareLocalThumbnailPath(
              localPath: path,
              fileName: stored.fileName,
              mediaType: stored.mediaType,
              cacheKey: stored.sha256,
              existingThumbnailPath: stored.localThumbnailPath,
            )
          : null;
      if (!stored.isVideo &&
          !stored.isAudio &&
          storedGeneratedThumbnail != null &&
          storedGeneratedThumbnail != path &&
          _readableThumbnailPath(stored) == null) {
        stored.localThumbnailPath = storedGeneratedThumbnail;
      }
      await stored.save();
    } else if (item.isInBox) {
      await item.save();
    }
    return path;
  }

  Future<String?> _rememberLocalThumbnailPath(
    BabyCloudMedia item,
    String path,
  ) async {
    item.localThumbnailPath = path;
    final stored = _storage.babyCloudMediaBox.get(item.id);
    if (stored != null && !identical(stored, item)) {
      stored.localThumbnailPath = path;
      await stored.save();
    } else if (item.isInBox) {
      await item.save();
    }
    return path;
  }

  Future<Directory> _localMediaCacheDir(BabyCloudMedia item) async {
    final base = _appDocumentsDir ?? await getApplicationDocumentsDirectory();
    _appDocumentsDir ??= base;
    final dir = Directory(
      [
        base.path,
        'baby_cloud_cache',
        _safeFileSegment(item.dataSourceId),
        _safeFileSegment(item.babyId),
      ].join(Platform.pathSeparator),
    );
    await dir.create(recursive: true);
    return dir;
  }

  void _logMediaCache(String event, BabyCloudMedia item, String path) {
    if (!_debugMediaCache) return;
    debugPrint(
      'BabyCloudCache: $event '
      'id=${item.id} type=${item.mediaType} '
      'hash=${item.sha256.length > 12 ? item.sha256.substring(0, 12) : item.sha256} '
      'entry=${item.entryId} path=$path',
    );
  }

  Future<void> _prepareBabyCloudStructure(
    _BabyCloudRemoteClient client,
    BabyCloudSource source,
    Baby baby,
  ) async {
    final manifest = await _readOrCreateLibraryManifest(client, source);
    final libraryId = manifest['libraryId']?.toString().trim() ?? '';
    if (libraryId.isNotEmpty) {
      source.libraryId = libraryId;
      source.libraryName = manifest['name']?.toString();
    }
    _rememberBabyMappingFromManifest(source, baby, manifest);
    await _bindBabyInManifest(client, source, baby, manifest);
    await _ensureBabyDirs(client, source, baby);
  }

  Future<void> _normalizeLocalCloudIdentity(
    BabyCloudSource source,
    Baby baby,
  ) async {
    final libraryId = _libraryScopeForSource(source);
    final cloudBabyId = _cloudBabyId(source, baby);

    for (final entry in _storage.babyCloudEntryBox.values.where(
      (entry) =>
          _entryBelongsToSource(source, entry) && entry.babyId == baby.id,
    )) {
      if (entry.dataSourceId == source.id &&
          entry.libraryId == libraryId &&
          entry.cloudBabyId == cloudBabyId) {
        continue;
      }
      entry
        ..dataSourceId = source.id
        ..libraryId = libraryId
        ..cloudBabyId = cloudBabyId;
      await entry.save();
    }

    for (final item in _storage.babyCloudMediaBox.values.where(
      (item) => _mediaBelongsToSource(source, item) && item.babyId == baby.id,
    )) {
      if (item.dataSourceId == source.id &&
          item.libraryId == libraryId &&
          item.cloudBabyId == cloudBabyId) {
        continue;
      }
      item
        ..dataSourceId = source.id
        ..libraryId = libraryId
        ..cloudBabyId = cloudBabyId;
      await item.save();
    }
  }

  Future<Map<String, dynamic>> _readOrCreateLibraryManifest(
    _BabyCloudRemoteClient client,
    BabyCloudSource source,
  ) async {
    final root = _normalizeRoot(source.rootPath);
    if (root != '/') {
      await _ensureRemoteDir(client, root);
    }
    final existing = await _readLibraryManifest(client, source);
    if (existing != null) return existing;

    final now = DateTime.now().toIso8601String();
    final libraryId = source.libraryId?.trim().isNotEmpty == true
        ? source.libraryId!.trim()
        : 'lib_${sha256.convert(utf8.encode('${source.id}|$root|$now')).toString().substring(0, 16)}';
    final manifest = <String, dynamic>{
      'format': _libraryManifestFormat,
      'type': _libraryManifestType,
      'libraryId': libraryId,
      'name': source.libraryName?.trim().isNotEmpty == true
          ? source.libraryName
          : '亲宝宝云相册',
      'rootPath': root,
      'deletePolicy': 'soft_delete_default',
      'createdAt': now,
      'updatedAt': now,
      'babies': <Map<String, dynamic>>[],
    };
    await _writeLibraryManifest(client, source, manifest);
    return manifest;
  }

  Future<Map<String, dynamic>?> _readLibraryManifest(
    _BabyCloudRemoteClient client,
    BabyCloudSource source,
  ) async {
    try {
      final bytes = await client.read(_libraryManifestPath(source));
      final raw = jsonDecode(utf8.decode(bytes));
      if (raw is! Map) return null;
      final manifest = Map<String, dynamic>.from(raw);
      if (manifest['format'] != _libraryManifestFormat ||
          manifest['type'] != _libraryManifestType) {
        return null;
      }
      return manifest;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeLibraryManifest(
    _BabyCloudRemoteClient client,
    BabyCloudSource source,
    Map<String, dynamic> manifest,
  ) async {
    manifest['updatedAt'] = DateTime.now().toIso8601String();
    final root = _normalizeRoot(source.rootPath);
    if (root != '/') await _ensureRemoteDir(client, root);
    await client.write(
      _libraryManifestPath(source),
      utf8.encode(jsonEncode(manifest)),
    );
  }

  void _rememberBabyMappingFromManifest(
    BabyCloudSource source,
    Baby baby,
    Map<String, dynamic> manifest,
  ) {
    final babyNode = _findManifestBaby(manifest, baby);
    if (babyNode == null) return;
    final babyDir = babyNode['babyDir']?.toString();
    if (babyDir != null && babyDir.trim().isNotEmpty) {
      _rememberManifestBabyDir(source, baby.id, babyDir);
    }
    final cloudBabyId = babyNode['cloudBabyId']?.toString();
    if (cloudBabyId != null && cloudBabyId.trim().isNotEmpty) {
      _rememberCloudBabyId(source, baby.id, cloudBabyId);
    }
  }

  Future<void> _bindBabyInManifest(
    _BabyCloudRemoteClient client,
    BabyCloudSource source,
    Baby baby,
    Map<String, dynamic> manifest,
  ) async {
    final babies = _manifestBabies(manifest);
    final existingIndex = _manifestBabyIndex(babies, baby);
    final existing = existingIndex >= 0 ? babies[existingIndex] : null;
    final now = DateTime.now().toIso8601String();
    final cloudBabyId =
        existing?['cloudBabyId']?.toString().trim().isNotEmpty == true
            ? existing!['cloudBabyId'].toString()
            : _cloudBabyId(source, baby);
    final babyDir = existing?['babyDir']?.toString().trim().isNotEmpty == true
        ? _normalizeRemoteDir(existing!['babyDir'].toString())
        : _defaultBabyDir(source, baby);
    final node = <String, dynamic>{
      'cloudBabyId': cloudBabyId,
      'localBabyIds': <String>{
        baby.id,
        ...((existing?['localBabyIds'] as List?) ?? const [])
            .map((e) => e.toString()),
      }.toList(),
      'name': baby.name,
      'safeName': _safeName(baby.name),
      'babyDir': babyDir,
      'updatedAt': now,
      'createdAt': existing?['createdAt']?.toString() ?? now,
    };
    if (existing == null) {
      babies.add(node);
    } else if (existingIndex >= 0) {
      babies[existingIndex] = node;
    }
    manifest['babies'] = babies;
    _rememberManifestBabyDir(source, baby.id, babyDir);
    _rememberCloudBabyId(source, baby.id, cloudBabyId);
    await _writeLibraryManifest(client, source, manifest);
  }

  List<Map<String, dynamic>> _manifestBabies(Map<String, dynamic> manifest) {
    final raw = manifest['babies'];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Map<String, dynamic>? _findManifestBaby(
    Map<String, dynamic> manifest,
    Baby baby,
  ) {
    final babies = _manifestBabies(manifest);
    final index = _manifestBabyIndex(babies, baby);
    return index >= 0 ? babies[index] : null;
  }

  int _manifestBabyIndex(
    List<Map<String, dynamic>> babies,
    Baby baby,
  ) {
    for (var index = 0; index < babies.length; index++) {
      final item = babies[index];
      final ids =
          (item['localBabyIds'] as List?)?.map((e) => e.toString()).toSet() ??
              <String>{};
      final name = item['name']?.toString();
      final safeName = item['safeName']?.toString();
      if (ids.contains(baby.id) ||
          name == baby.name ||
          safeName?.toLowerCase() == _safeName(baby.name).toLowerCase()) {
        return index;
      }
    }
    return -1;
  }

  BabyCloudMedia? _findExistingLocalMedia(
    BabyCloudSource source,
    Baby baby,
    BabyCloudMedia incoming,
  ) {
    final byId = _storage.babyCloudMediaBox.get(incoming.id);
    if (byId != null &&
        _mediaBelongsToSource(source, byId) &&
        byId.babyId == baby.id) {
      return byId;
    }
    return _storage.babyCloudMediaBox.values.toList().firstWhereOrNull(
          (item) =>
              _mediaBelongsToSource(source, item) &&
              item.babyId == baby.id &&
              ((incoming.sha256.isNotEmpty && item.sha256 == incoming.sha256) ||
                  (incoming.remotePath.isNotEmpty &&
                      item.remotePath == incoming.remotePath)),
        );
  }

  BabyCloudEntry? _findExistingLocalEntry(
    BabyCloudSource source,
    Baby baby,
    BabyCloudEntry incoming,
  ) {
    final byId = _storage.babyCloudEntryBox.get(incoming.id);
    if (byId != null &&
        _entryBelongsToSource(source, byId) &&
        byId.babyId == baby.id) {
      return byId;
    }
    return _storage.babyCloudEntryBox.values.toList().firstWhereOrNull(
          (entry) =>
              _entryBelongsToSource(source, entry) &&
              entry.babyId == baby.id &&
              entry.id == incoming.id,
        );
  }

  String? _readablePath(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    try {
      return File(path).existsSync() ? path : null;
    } catch (_) {
      return null;
    }
  }

  String _importedMediaId(BabyCloudSource source, Baby baby, String remoteId) {
    return sha256
        .convert(utf8.encode('${source.id}|${baby.id}|$remoteId'))
        .toString();
  }

  Future<void> _mergeRemoteIndex(
    BabyCloudSource source,
    Baby baby,
    Map<String, dynamic>? remote,
  ) async {
    if (remote == null) return;
    final expectedLibraryId = _libraryScopeForSource(source);
    final remoteLibraryId = remote['libraryId']?.toString().trim() ?? '';
    if (remoteLibraryId != expectedLibraryId) {
      return;
    }
    final expectedCloudBabyId = _cloudBabyId(source, baby);
    final cloudBabyId = remote['cloudBabyId']?.toString().trim() ?? '';
    if (cloudBabyId != expectedCloudBabyId) {
      return;
    }

    final rawEntries = remote['entries'];
    if (rawEntries is List) {
      for (final raw in rawEntries) {
        if (raw is! Map) continue;
        final incoming = BabyCloudEntry.fromJson(
          Map<String, dynamic>.from(raw),
        );
        incoming
          ..dataSourceId = source.id
          ..babyId = baby.id
          ..libraryId = _libraryScopeForSource(source)
          ..cloudBabyId = cloudBabyId;

        final existing = _findExistingLocalEntry(source, baby, incoming);
        if (existing == null) {
          await _storage.babyCloudEntryBox.put(incoming.id, incoming);
        } else {
          _mergeEntryIntoExisting(existing, incoming);
          await existing.save();
        }
      }
    }

    final rawItems = remote['media'];
    if (rawItems is! List) return;
    for (final raw in rawItems) {
      if (raw is! Map) continue;
      final incoming = BabyCloudMedia.fromJson(Map<String, dynamic>.from(raw));
      incoming
        ..dataSourceId = source.id
        ..babyId = baby.id
        ..libraryId = _libraryScopeForSource(source)
        ..cloudBabyId = cloudBabyId
        ..localPath = _readablePath(incoming.localPath)
        ..localThumbnailPath = _readablePath(incoming.localThumbnailPath);

      final idConflict = _storage.babyCloudMediaBox.get(incoming.id);
      if (idConflict != null &&
          (idConflict.dataSourceId != source.id ||
              idConflict.babyId != baby.id)) {
        incoming.id = _importedMediaId(source, baby, incoming.id);
      }

      final existing = _findExistingLocalMedia(source, baby, incoming);
      if (existing == null) {
        await _storage.babyCloudMediaBox.put(incoming.id, incoming);
        await _ensureEntryForMedia(source, baby, incoming);
      } else {
        _mergeMediaIntoExisting(existing, incoming);
        await existing.save();
        await _ensureEntryForMedia(source, baby, existing);
      }
    }
  }

  void _mergeEntryIntoExisting(
    BabyCloudEntry existing,
    BabyCloudEntry incoming,
  ) {
    final localMediaIds = existing.mediaIds.toSet();
    final remoteMediaIds = incoming.mediaIds.toSet();
    final mergedMediaIds = {...localMediaIds, ...remoteMediaIds}.toList();
    final incomingNewer = incoming.updatedAt.isAfter(existing.updatedAt);
    final incomingDeletesActive = incoming.deletedAt != null &&
        existing.deletedAt == null &&
        !incoming.updatedAt.isBefore(existing.updatedAt);
    final incomingStatusWins = incomingNewer || incomingDeletesActive;
    final incomingPurgeWins =
        incoming.purgedAt != null && existing.purgedAt == null;

    if (incomingStatusWins || incomingPurgeWins) {
      final localCreatedAt = existing.createdAt;
      existing
        ..dataSourceId = incoming.dataSourceId
        ..libraryId = incoming.libraryId
        ..cloudBabyId = incoming.cloudBabyId
        ..entryType = incoming.entryType
        ..description = incoming.description
        ..tags = incoming.tags
        ..locationName = incoming.locationName
        ..actorRole = incoming.actorRole
        ..visibility = incoming.visibility
        ..takenAt = incoming.takenAt
        ..updatedAt = incoming.updatedAt
        ..deletedAt =
            incomingStatusWins ? incoming.deletedAt : existing.deletedAt
        ..deleteReason =
            incomingStatusWins ? incoming.deleteReason : existing.deleteReason
        ..purgedAt = incoming.purgedAt ?? existing.purgedAt
        ..createdAt = localCreatedAt.isBefore(incoming.createdAt)
            ? localCreatedAt
            : incoming.createdAt;
    }
    existing.mediaIds = mergedMediaIds;
  }

  void _mergeMediaIntoExisting(
    BabyCloudMedia existing,
    BabyCloudMedia incoming,
  ) {
    final incomingNewer = incoming.updatedAt.isAfter(existing.updatedAt);
    final incomingDeletesActive = incoming.deletedAt != null &&
        existing.deletedAt == null &&
        !incoming.updatedAt.isBefore(existing.updatedAt);
    final incomingStatusWins = incomingNewer || incomingDeletesActive;
    final incomingPurgeWins =
        incoming.purgedAt != null && existing.purgedAt == null;
    final localPath = _readablePath(existing.localPath);
    final localThumbnailPath = _readablePath(existing.localThumbnailPath);

    if (incomingStatusWins || incomingPurgeWins) {
      existing
        ..dataSourceId = incoming.dataSourceId
        ..libraryId = incoming.libraryId
        ..cloudBabyId = incoming.cloudBabyId
        ..sha256 = incoming.sha256
        ..fileName = incoming.fileName
        ..mediaType = incoming.mediaType
        ..mimeType = incoming.mimeType
        ..remotePath = incoming.remotePath
        ..thumbnailRemotePath = incoming.thumbnailRemotePath
        ..sizeBytes = incoming.sizeBytes
        ..width = incoming.width
        ..height = incoming.height
        ..durationSeconds = incoming.durationSeconds
        ..takenAt = incoming.takenAt
        ..uploadedAt = incoming.uploadedAt
        ..updatedAt = incoming.updatedAt
        ..deletedAt =
            incomingStatusWins ? incoming.deletedAt : existing.deletedAt
        ..entryId = incoming.entryId
        ..description = incoming.description
        ..tags = incoming.tags
        ..locationName = incoming.locationName
        ..actorRole = incoming.actorRole
        ..visibility = incoming.visibility
        ..deleteReason =
            incomingStatusWins ? incoming.deleteReason : existing.deleteReason
        ..replacedByMediaId =
            incoming.replacedByMediaId ?? existing.replacedByMediaId
        ..purgedAt = incoming.purgedAt ?? existing.purgedAt;
    }
    existing
      ..localPath = localPath ?? _readablePath(incoming.localPath)
      ..localThumbnailPath =
          localThumbnailPath ?? _readablePath(incoming.localThumbnailPath);
  }

  Future<BabyCloudEntry> _ensureEntryForMedia(
    BabyCloudSource source,
    Baby baby,
    BabyCloudMedia item,
  ) async {
    final existing = _storage.babyCloudEntryBox.get(item.entryId);
    final cloudBabyId = item.cloudBabyId.trim().isNotEmpty
        ? item.cloudBabyId
        : _cloudBabyId(source, baby);
    final libraryId = item.libraryId.trim().isNotEmpty
        ? item.libraryId
        : _libraryScopeForSource(source);
    if (existing == null || !_entryBelongsToSource(source, existing)) {
      final entry = BabyCloudEntry(
        id: item.entryId,
        babyId: baby.id,
        dataSourceId: source.id,
        libraryId: libraryId,
        cloudBabyId: cloudBabyId,
        entryType: item.isDiary
            ? 'diary'
            : item.isAudio
                ? 'audio'
                : 'media',
        description: item.description,
        tags: item.tags,
        locationName: item.locationName,
        actorRole: item.actorRole,
        visibility: item.visibility,
        takenAt: item.takenAt,
        createdAt: item.uploadedAt,
        updatedAt: item.updatedAt,
        deletedAt: item.deleteReason == 'entryDeleted' ? item.deletedAt : null,
        deleteReason:
            item.deleteReason == 'entryDeleted' ? 'entryDeleted' : null,
        mediaIds: [item.id],
        purgedAt: item.purgedAt,
      );
      await _storage.babyCloudEntryBox.put(entry.id, entry);
      return entry;
    }

    existing
      ..libraryId =
          existing.libraryId.trim().isEmpty ? libraryId : existing.libraryId
      ..cloudBabyId = existing.cloudBabyId.trim().isEmpty
          ? cloudBabyId
          : existing.cloudBabyId
      ..dataSourceId = source.id
      ..babyId = baby.id
      ..entryType = _entryTypeForMedia(
        _storage.babyCloudMediaBox.values
            .where((mediaItem) =>
                mediaItem.entryId == item.entryId &&
                _mediaBelongsToSource(source, mediaItem))
            .toList(),
      )
      ..mediaIds = {...existing.mediaIds, item.id}.toList()
      ..updatedAt = existing.updatedAt.isAfter(item.updatedAt)
          ? existing.updatedAt
          : item.updatedAt;
    if (existing.description == null || existing.description!.trim().isEmpty) {
      existing.description = item.description;
    }
    if (existing.tags.isEmpty) existing.tags = item.tags;
    existing.locationName ??= item.locationName;
    existing.actorRole ??= item.actorRole;
    await existing.save();
    return existing;
  }

  Future<Map<String, dynamic>?> _readRemoteIndexAt(
    _BabyCloudRemoteClient client,
    String indexPath,
  ) async {
    try {
      final bytes = await client.read(indexPath);
      final raw = jsonDecode(utf8.decode(bytes));
      if (raw is Map) {
        final index = Map<String, dynamic>.from(raw);
        if (index['format'] != _albumIndexFormat ||
            index['type'] != _albumIndexType) {
          throw const FormatException('亲宝宝相册索引格式不匹配');
        }
        return index;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _ensureBabyDirs(
    _BabyCloudRemoteClient client,
    BabyCloudSource source,
    Baby baby,
  ) async {
    final root = _normalizeRoot(source.rootPath);
    final dirs = [
      if (root != '/') root,
      _rootChildPath(source, 'babies'),
      _babyDir(source, baby),
      '${_babyDir(source, baby)}/album',
      '${_babyDir(source, baby)}/album/photos',
      '${_babyDir(source, baby)}/album/videos',
      '${_babyDir(source, baby)}/album/audios',
      '${_babyDir(source, baby)}/album/thumbnails',
      '${_babyDir(source, baby)}/index',
      '${_babyDir(source, baby)}/trash',
    ];
    for (final dir in dirs) {
      await _ensureRemoteDir(client, dir);
    }
  }

  Future<bool> _ensureRemoteDir(
    _BabyCloudRemoteClient client,
    String path,
  ) async {
    final normalized = _normalizeRemoteDir(path);
    if (normalized == '/') return false;

    var created = false;
    var current = '';
    final parts = normalized.split('/').where((part) => part.isNotEmpty);
    for (final part in parts) {
      current = current.isEmpty ? '/$part' : '$current/$part';
      Object? readError;
      try {
        await client.statDir(current);
        continue;
      } catch (e) {
        readError = e;
      }

      try {
        await client.mkdir(current);
        await client.statDir(current);
      } catch (e) {
        throw Exception('创建云端目录 $current 失败；读取尝试：$readError；创建尝试：$e');
      }
      created = true;
    }
    return created;
  }

  Future<String?> _checkWebDavRoot(
    _BabyWebDavClient client,
    BabyCloudSource source,
  ) async {
    final messages = <String>[];

    final root = _normalizeRoot(source.rootPath);
    if (root == '/') {
      try {
        await client.statDir('/');
        return messages.isEmpty ? null : messages.join('；');
      } catch (e) {
        try {
          await client.mkdir('/');
          await client.statDir('/');
          messages.add('已创建 WebDAV 根目录');
          return messages.join('；');
        } catch (createError) {
          throw Exception(
            'WebDAV 根目录暂不可读或不可创建；初次读取：$e；创建尝试：$createError',
          );
        }
      }
    }

    Object? appRootReadError;
    try {
      await client.statDir(root);
      return messages.isEmpty ? null : messages.join('；');
    } catch (e) {
      appRootReadError = e;
    }

    try {
      final created = await _ensureRemoteDir(client, root);
      await client.statDir(root);
      if (created) {
        messages.add('已创建亲宝宝根目录 $root');
      }
      return messages.isEmpty ? null : messages.join('；');
    } catch (e) {
      return '亲宝宝根目录 $root 暂不可读或不可创建，可在目录选择中选择一个已有目录。读取尝试：$appRootReadError；创建尝试：$e';
    }
  }

  Future<String?> _quickCheckWebDav(
    _BabyWebDavClient client,
    BabyCloudSource source,
  ) async {
    return _checkWebDavRoot(client, source);
  }

  Future<void> _recordSourceCheck(
    BabyCloudSource source, {
    required bool ok,
    required String message,
    required bool persist,
    String? status,
  }) async {
    source
      ..status = status ?? (ok ? 'normal' : 'invalid')
      ..lastCheckedAt = DateTime.now()
      ..lastCheckMessage = message;
    if (!ok) {
      source
        ..activeWebDavUrl = null
        ..activeWebDavEndpoint = 'none';
    }
    if (persist) {
      await saveSource(source);
    }
  }

  Future<List<_WebDavEndpointCandidate>> _orderedWebDavCandidates(
    BabyCloudSource source,
  ) async {
    final external = source.webDavUrl?.trim() ?? '';
    final lan = source.webDavLanUrl?.trim() ?? '';
    final active = source.activeWebDavUrl?.trim() ?? '';
    final looksLocal = await _looksLikeLocalNetwork();
    final endpointMode = _webDavEndpointMode(source);
    final result = <_WebDavEndpointCandidate>[];

    void add(String endpoint, String url, {String? note}) {
      final normalized = _normalizeEndpointUrl(url);
      if (normalized.isEmpty) return;
      if (result.any((item) => item.url == normalized)) return;
      result.add(_WebDavEndpointCandidate(endpoint, normalized, note: note));
    }

    String endpointForUrl(String url, String fallback) {
      final normalized = _normalizeEndpointUrl(url);
      if (normalized.isEmpty) return fallback;
      if (lan.trim().isNotEmpty && normalized == _normalizeEndpointUrl(lan)) {
        return 'lan';
      }
      if (external.trim().isNotEmpty &&
          normalized == _normalizeEndpointUrl(external)) {
        return 'external';
      }
      return fallback == 'lan' || fallback == 'external'
          ? fallback
          : 'external';
    }

    if (active.isNotEmpty) {
      // 只在 active 地址与当前网络环境匹配时才优先复用，否则由网络排序决定
      final activeMatchesLocal = looksLocal &&
          (source.activeWebDavEndpoint == 'lan' ||
              _normalizeEndpointUrl(active) == _normalizeEndpointUrl(lan));
      final activeMatchesExternal = !looksLocal &&
          (source.activeWebDavEndpoint == 'external' ||
              _normalizeEndpointUrl(active) == _normalizeEndpointUrl(external));
      final activeMatchesMode = endpointMode == 'auto'
          ? activeMatchesLocal || activeMatchesExternal
          : source.activeWebDavEndpoint == endpointMode;
      if (activeMatchesMode) {
        add(
          endpointForUrl(active, source.activeWebDavEndpoint),
          active,
          note: '复用上次可用地址',
        );
      }
    }

    if (endpointMode == 'lan') {
      add('lan', lan);
    } else if (endpointMode == 'external') {
      add('external', external);
    } else if (looksLocal) {
      add('lan', lan);
      add('external', external);
    } else {
      add('external', external);
      add('lan', lan);
    }
    return result;
  }

  Future<bool> _looksLikeLocalNetwork() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      return interfaces
          .expand((interface) => interface.addresses)
          .any((address) => _isPrivateIpv4(address.address));
    } catch (_) {
      return true;
    }
  }

  bool _isPrivateIpv4(String address) {
    final parts = address.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((part) => part == null)) return false;
    final a = parts[0]!;
    final b = parts[1]!;
    return a == 10 || a == 192 && b == 168 || a == 172 && b >= 16 && b <= 31;
  }

  bool _hasAnyWebDavEndpoint(BabyCloudSource source) {
    return (source.webDavUrl?.trim().isNotEmpty ?? false) ||
        (source.webDavLanUrl?.trim().isNotEmpty ?? false);
  }

  String? _effectiveWebDavUrl(BabyCloudSource source) {
    final mode = _webDavEndpointMode(source);
    final active = source.activeWebDavUrl?.trim() ?? '';
    if (mode == 'auto') {
      if (active.isNotEmpty) return _normalizeEndpointUrl(active);
    } else if (mode == 'lan') {
      if (source.activeWebDavEndpoint == 'lan' && active.isNotEmpty) {
        return _normalizeEndpointUrl(active);
      }
      final lan = source.webDavLanUrl?.trim() ?? '';
      if (lan.isNotEmpty) return _normalizeEndpointUrl(lan);
    } else if (mode == 'external') {
      if (source.activeWebDavEndpoint == 'external' && active.isNotEmpty) {
        return _normalizeEndpointUrl(active);
      }
      final external = source.webDavUrl?.trim() ?? '';
      if (external.isNotEmpty) return _normalizeEndpointUrl(external);
    }
    final lan = source.webDavLanUrl?.trim() ?? '';
    if (lan.isNotEmpty) return _normalizeEndpointUrl(lan);
    final external = source.webDavUrl?.trim() ?? '';
    if (external.isNotEmpty) return _normalizeEndpointUrl(external);
    return null;
  }

  String _normalizeEndpointUrl(String url) {
    var value = url.trim();
    if (value.isEmpty) return '';
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+\-.]*://').hasMatch(value)) {
      value = 'http://$value';
    }
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) return '';
    if (uri.scheme != 'http' && uri.scheme != 'https') return '';
    return uri.toString().replaceAll(RegExp(r'/+$'), '');
  }

  _BabyWebDavClient _webDavClient(
    BabyCloudSource source, {
    String? endpointUrl,
  }) {
    return _BabyWebDavClient(
      endpointUrl: endpointUrl ?? _effectiveWebDavUrl(source) ?? '',
      username: source.webDavUsername ?? '',
      password: source.webDavPassword ?? '',
    );
  }

  String _libraryManifestPath(BabyCloudSource source) {
    final root = _normalizeRoot(source.rootPath);
    return root == '/'
        ? '/library_manifest.json'
        : '$root/library_manifest.json';
  }

  String? _libraryIdForSource(BabyCloudSource? source) {
    final libraryId = source?.libraryId?.trim() ?? '';
    if (libraryId.isNotEmpty) return libraryId;
    return null;
  }

  String _libraryScopeForSource(BabyCloudSource source) {
    return _libraryIdForSource(source) ?? source.id;
  }

  bool _mediaBelongsToSource(BabyCloudSource source, BabyCloudMedia item) {
    final libraryId = _libraryIdForSource(source);
    if (libraryId != null && item.libraryId == libraryId) return true;
    return item.dataSourceId == source.id;
  }

  bool _entryBelongsToSource(BabyCloudSource source, BabyCloudEntry entry) {
    final libraryId = _libraryIdForSource(source);
    if (libraryId != null && entry.libraryId == libraryId) return true;
    return entry.dataSourceId == source.id;
  }

  String _cloudBabyId(BabyCloudSource source, Baby baby) {
    final mapped = _mappedCloudBabyId(source, baby.id);
    if (mapped != null) return mapped;
    final libraryScope = _libraryScopeForSource(source);
    return 'baby_${sha256.convert(utf8.encode('$libraryScope|${baby.id}|${_safeName(baby.name)}')).toString().substring(0, 12)}';
  }

  void _rememberCloudBabyId(
    BabyCloudSource source,
    String babyId,
    String cloudBabyId,
  ) {
    final value = cloudBabyId.trim();
    if (value.isEmpty) return;
    _manifestCloudBabyIds[_manifestBabyKey(source, babyId)] = value;
  }

  String? _mappedCloudBabyId(BabyCloudSource source, String babyId) {
    final raw = _manifestCloudBabyIds[_manifestBabyKey(source, babyId)];
    if (raw == null || raw.trim().isEmpty) return null;
    return raw.trim();
  }

  String _manifestBabyKey(BabyCloudSource source, String babyId) =>
      '${_libraryScopeForSource(source)}|$babyId';

  Future<String?> _uploadTaskThumbnailIfAvailable({
    required _BabyCloudRemoteClient client,
    required BabyCloudSource source,
    required Baby baby,
    required BabyCloudUploadTask task,
    required String hash,
  }) async {
    final preparedPath = await _prepareLocalThumbnailPath(
      localPath: task.localPath,
      fileName: task.fileName,
      mediaType: task.mediaType,
      cacheKey: hash,
      existingThumbnailPath: task.localThumbnailPath,
    );
    if (preparedPath != task.localThumbnailPath) {
      task
        ..localThumbnailPath = preparedPath
        ..updatedAt = DateTime.now();
      await _saveTaskIfAlive(task);
    }
    final localPath = task.localThumbnailPath;
    if (localPath == null || localPath.trim().isEmpty) return null;
    final file = File(localPath);
    if (!await file.exists()) return null;

    final remotePath = _thumbnailPath(
      source,
      baby,
      file.path,
      hash,
      task.takenAt ?? file.lastModifiedSync(),
    );
    await _ensureRemoteDir(client, _parentRemoteDir(remotePath));
    await client.write(
      remotePath,
      await file.readAsBytes(),
      mimeType: _mimeFromName(file.path, 'photo'),
    );
    return remotePath;
  }

  String _mediaPath(
    BabyCloudSource source,
    Baby baby,
    String fileName,
    String hash,
    String mediaType,
    DateTime takenAt,
  ) {
    final ext = _extension(fileName);
    final year = DateFormat('yyyy').format(takenAt);
    final month = DateFormat('MM').format(takenAt);
    final ts = DateFormat('yyyyMMdd_HHmmss').format(takenAt);
    final bucket = mediaType == 'video'
        ? 'videos'
        : mediaType == 'audio'
            ? 'audios'
            : 'photos';
    return '${_babyDir(source, baby)}/album/$bucket/$year/$month/${ts}_${hash.substring(0, 12)}$ext';
  }

  String _thumbnailPath(
    BabyCloudSource source,
    Baby baby,
    String fileName,
    String hash,
    DateTime takenAt,
  ) {
    final rawExt = _extension(fileName);
    final ext = rawExt.isEmpty || rawExt.toLowerCase() == '.heic'
        ? '.jpg'
        : rawExt;
    final year = DateFormat('yyyy').format(takenAt);
    final month = DateFormat('MM').format(takenAt);
    final ts = DateFormat('yyyyMMdd_HHmmss').format(takenAt);
    return '${_babyDir(source, baby)}/album/thumbnails/$year/$month/${ts}_${hash.substring(0, 12)}_thumb$ext';
  }

  String _indexPath(BabyCloudSource source, Baby baby) =>
      '${_babyDir(source, baby)}/index/album_index.json';

  String _babyDir(BabyCloudSource source, Baby baby) =>
      _manifestBabyDir(source, baby.id) ?? _defaultBabyDir(source, baby);

  String _defaultBabyDir(BabyCloudSource source, Baby baby) =>
      '${_rootChildPath(source, 'babies')}/${_cloudBabyId(source, baby)}_${_safeName(baby.name)}';

  void _rememberManifestBabyDir(
    BabyCloudSource source,
    String babyId,
    String remoteDir,
  ) {
    final normalized = _normalizeRemoteDir(remoteDir);
    if (!_isUnderBabiesRoot(source, normalized)) return;
    _manifestBabyDirs[_manifestBabyKey(source, babyId)] = normalized;
  }

  String? _manifestBabyDir(BabyCloudSource source, String babyId) {
    final raw = _manifestBabyDirs[_manifestBabyKey(source, babyId)];
    if (raw == null || raw.trim().isEmpty) return null;
    final mapped = _normalizeRemoteDir(raw);
    return _isUnderBabiesRoot(source, mapped) ? mapped : null;
  }

  bool _isUnderBabiesRoot(BabyCloudSource source, String path) {
    final babiesRoot = _normalizeRemoteDir(_rootChildPath(source, 'babies'));
    final normalized = _normalizeRemoteDir(path);
    return normalized.startsWith('$babiesRoot/');
  }

  String _rootChildPath(BabyCloudSource source, String child) {
    final root = _normalizeRoot(source.rootPath);
    return root == '/' ? '/$child' : '$root/$child';
  }

  String _normalizeRoot(String root) {
    var normalized = root.trim().replaceAll('\\', '/');
    if (normalized.isEmpty) normalized = 'starbank_baby_cloud';
    if (normalized == '/') return '/';
    if (!normalized.startsWith('/')) normalized = '/$normalized';
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  String _normalizeRemoteDir(String path) {
    var normalized = path.trim().replaceAll('\\', '/');
    if (normalized.isEmpty) return '/';
    while (normalized.contains('//')) {
      normalized = normalized.replaceAll('//', '/');
    }
    if (!normalized.startsWith('/')) normalized = '/$normalized';
    if (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  String _joinRemoteDir(String parent, String name) {
    final normalizedParent = _normalizeRemoteDir(parent);
    final cleanName = _cleanRemoteDirName(name);
    if (normalizedParent == '/') return '/$cleanName';
    return '$normalizedParent/$cleanName';
  }

  String _parentRemoteDir(String path) {
    final normalized = _normalizeRemoteDir(path);
    if (normalized == '/') return '/';
    final index = normalized.lastIndexOf('/');
    if (index <= 0) return '/';
    return normalized.substring(0, index);
  }

  String _remoteName(String path) {
    final normalized = _normalizeRemoteDir(path);
    if (normalized == '/') return '/';
    return normalized.split('/').where((part) => part.isNotEmpty).last;
  }

  String _cleanRemoteDirName(String name) {
    return name
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
  }

  String _safeName(String name) {
    final value = name.trim().isEmpty ? 'baby' : name.trim();
    return value.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
  }

  String _safeFileSegment(String value) {
    final clean = value.trim().isEmpty ? 'item' : value.trim();
    return clean.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
  }

  String _babySafeName(String babyId) {
    return _storage.babyBox.values
            .toList()
            .firstWhereOrNull((b) => b.id == babyId)
            ?.name ??
        'history';
  }

  String _extension(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot <= 0) return '';
    return fileName.substring(dot).toLowerCase();
  }

  String _mimeFromName(String fileName, String mediaType) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    return mediaType == 'video' ? 'video/mp4' : 'image/jpeg';
  }
}
