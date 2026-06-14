import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../models/baby.dart';
import '../models/baby_cloud_entry.dart';
import '../models/baby_cloud_media.dart';
import '../models/baby_cloud_source.dart';
import '../models/baby_cloud_upload_task.dart';
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

class _WebDavEndpointCandidate {
  const _WebDavEndpointCandidate(this.endpoint, this.url, {this.note});

  final String endpoint;
  final String url;
  final String? note;
}

class _BabyWebDavEntry {
  const _BabyWebDavEntry({
    required this.path,
    required this.isDir,
    this.size,
  });

  final String path;
  final bool isDir;
  final int? size;
}

class _BabyWebDavClient {
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

  Future<void> statDir(String remotePath) async {
    await _propFind(remotePath, depth: '0');
  }

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

  Future<List<_BabyWebDavEntry>> readDir(String remotePath) async {
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

  Future<List<int>> read(String remotePath) async {
    final response = await _request(
      'GET',
      remotePath,
      expectedStatuses: const {200},
    );
    return response.bodyBytes;
  }

  Future<void> write(String remotePath, List<int> bytes) async {
    await _request(
      'PUT',
      remotePath,
      body: bytes,
      headers: const {'Content-Type': 'application/octet-stream'},
      expectedStatuses: const {200, 201, 204},
    );
  }

  Future<void> remove(String remotePath) async {
    await _request(
      'DELETE',
      remotePath,
      expectedStatuses: const {200, 202, 204, 404},
    );
  }

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

  List<_BabyWebDavEntry> _parseMultiStatus(String xml) {
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
          return _BabyWebDavEntry(
            path: path,
            isDir: isDir,
            size: int.tryParse(sizeText?.trim() ?? ''),
          );
        })
        .whereType<_BabyWebDavEntry>()
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

class BabyCloudService extends GetxService {
  static const int _albumIndexFormat = 3;
  static const String _albumIndexType = 'starbank.baby_cloud.album_index';
  static const int _libraryManifestFormat = 1;
  static const String _libraryManifestType = 'starbank.baby_cloud.library';
  static const int _maxUploadRetries = 3;

  final StorageService _storage = Get.find<StorageService>();

  final RxList<BabyCloudSource> sources = <BabyCloudSource>[].obs;
  final Rx<BabyCloudSource?> currentSource = Rx<BabyCloudSource?>(null);
  final RxList<BabyCloudEntry> entries = <BabyCloudEntry>[].obs;
  final RxList<BabyCloudMedia> media = <BabyCloudMedia>[].obs;
  final RxList<BabyCloudUploadTask> uploadTasks = <BabyCloudUploadTask>[].obs;
  final RxBool isSyncing = false.obs;

  bool _queueRunning = false;
  Future<void>? _activeSync;
  final Map<String, Future<String?>> _localFileFutures = {};
  final Map<String, String> _manifestBabyDirs = {};
  final Map<String, String> _manifestCloudBabyIds = {};
  final Set<String> _deletedTaskIds = <String>{};

  bool get hasUsableCurrentSource {
    final source = currentSource.value;
    return source != null && source.isWebDav && _hasAnyWebDavEndpoint(source);
  }

  String get currentSourceSetupMessage {
    final source = currentSource.value;
    if (source == null) return '请先配置亲宝宝 WebDAV 数据源';
    if (!source.isWebDav) return '阿里云盘入口已预留，第一版请使用亲宝宝 WebDAV';
    if (!_hasAnyWebDavEndpoint(source)) {
      return '亲宝宝 WebDAV 外网/内网地址至少填写一个，请先完善数据源配置';
    }
    return '';
  }

  Future<BabyCloudService> init() async {
    _loadLocal();
    return this;
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

  Future<BabyCloudSourceCheckResult> checkSource(
    BabyCloudSource source, {
    bool persist = true,
  }) async {
    if (!source.isWebDav) {
      return const BabyCloudSourceCheckResult(
        ok: false,
        message: '阿里云盘入口已预留，第一版请使用亲宝宝 WebDAV',
      );
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

    final candidateErrors = <String>[];
    for (final candidate in await _orderedWebDavCandidates(source)) {
      try {
        final client = _webDavClient(source, endpointUrl: candidate.url);
        final rootWarning = await _checkWebDavRoot(client, source)
            .timeout(const Duration(seconds: 8));
        final endpointLabel = candidate.endpoint == 'lan' ? '内网' : '外网';
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
        candidateErrors.add('$endpointLabel ${candidate.url}: $e');
      }
    }

    final message = 'WebDAV 不可用，请检查地址、账号密码和网络：${candidateErrors.join('；')}';
    await _recordSourceCheck(
      source,
      ok: false,
      message: message,
      persist: persist,
    );
    return BabyCloudSourceCheckResult(ok: false, message: message);
  }

  Future<List<Map<String, dynamic>>> listRemoteDirectories(
    BabyCloudSource source,
    String path, {
    bool persistCheck = true,
  }) async {
    if (!source.isWebDav) return const [];
    final check = await checkSource(source, persist: persistCheck);
    if (!check.ok) throw Exception(check.message);
    final client = _webDavClient(source, endpointUrl: check.url);
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
    final client = _webDavClient(source, endpointUrl: check.url);
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
    if (current == '/') throw Exception('不能重命名 WebDAV 根目录');
    if (cleanName.isEmpty) throw Exception('目录名不能为空');
    final check = await checkSource(source, persist: persistCheck);
    if (!check.ok) throw Exception(check.message);
    final parent = _parentRemoteDir(current);
    final target = _joinRemoteDir(parent, cleanName);
    final client = _webDavClient(source, endpointUrl: check.url);
    await client.move(current, target);
  }

  Future<void> syncBaby(Baby baby, {bool showErrors = true}) {
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

  Future<void> _syncBabyInternal(Baby baby, {bool showErrors = true}) async {
    final source = currentSource.value;
    if (source == null) return;
    if (!source.isWebDav) {
      if (showErrors) {
        ToastUtils.showInfo('阿里云盘数据源已预留，第一版请先使用亲宝宝 WebDAV');
      }
      return;
    }

    isSyncing.value = true;
    try {
      final check = await checkSource(source);
      if (!check.ok) {
        if (showErrors) ToastUtils.showError(check.message);
        return;
      }
      final client = _webDavClient(source, endpointUrl: check.url);
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
      localThumbnailPath: localThumbnailPath,
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
    if (existing != null) return Future.value(existing);
    return _localFileFutures.putIfAbsent(item.ref, () async {
      try {
        return await _downloadMediaToLocalCache(item);
      } catch (_) {
        return null;
      } finally {
        _localFileFutures.remove(item.ref);
      }
    });
  }

  Future<void> processQueue() async {
    if (_queueRunning) return;
    _queueRunning = true;
    try {
      while (true) {
        final runnable = _storage.babyCloudUploadTaskBox.values
            .where((t) =>
                t.status == 'queued' ||
                (t.status == 'running' && t.progress < 1))
            .take(2)
            .toList();
        if (runnable.isEmpty) break;
        await Future.wait(
          runnable.map(_runBackgroundTask),
        );
        _reloadTasks();
      }
    } finally {
      _queueRunning = false;
    }
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

  Future<void> cancelTask(BabyCloudUploadTask task) async {
    task.status = 'cancelled';
    task.updatedAt = DateTime.now();
    await task.save();
    _reloadTasks();
  }

  Future<void> deleteTask(BabyCloudUploadTask task) async {
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
    final completed = _storage.babyCloudUploadTaskBox.values
        .where((t) => t.status == 'completed' || t.status == 'cancelled')
        .toList();
    for (final task in completed) {
      _deletedTaskIds.add(task.id);
      await task.delete();
    }
    _reloadTasks();
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
    if (source?.isWebDav == true) {
      final check = await checkSource(source!);
      if (check.ok) {
        final client = _webDavClient(source, endpointUrl: check.url);
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
    if (source?.isWebDav == true) {
      final check = await checkSource(source!);
      if (check.ok) {
        final client = _webDavClient(source, endpointUrl: check.url);
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
    if (source == null || !source.isWebDav) return;
    final check = await checkSource(source);
    if (!check.ok) return;
    final client = _webDavClient(source, endpointUrl: check.url);
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
    await _storage.babyCloudSourceBox.put(source.id, source);
    _refreshEntries();
    _refreshMedia();
  }

  Future<List<Map<String, dynamic>>> listRemoteBabyDirs(
      BabyCloudSource source) async {
    if (!source.isWebDav) return const [];
    final check = await checkSource(source);
    if (!check.ok) throw Exception(check.message);
    final client = _webDavClient(source, endpointUrl: check.url);
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
  }

  Future<void> _runMetadataTask(BabyCloudUploadTask task) async {
    try {
      if (!await _checkpointTask(task)) return;
      task
        ..status = 'running'
        ..progress = 0.2
        ..updatedAt = DateTime.now();
      if (!await _saveTaskIfAlive(task)) return;

      await publishIndexFor(task.dataSourceId, task.babyId);
      if (!await _checkpointTask(task)) return;
      task
        ..status = 'completed'
        ..progress = 1
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
        ..updatedAt = DateTime.now();
      await _saveTaskIfAlive(task);
    } catch (e) {
      await _failTask(task, e.toString());
    }
  }

  Future<void> _runUploadTask(BabyCloudUploadTask task) async {
    if (!_shouldContinueTask(task)) return;
    final source = sources.firstWhereOrNull((s) => s.id == task.dataSourceId);
    if (source == null || !source.isWebDav) {
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

      final client = _webDavClient(source, endpointUrl: check.url);
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
        duplicate
          ..dataSourceId = source.id
          ..libraryId = _libraryScopeForSource(source)
          ..cloudBabyId = _cloudBabyId(source, baby)
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
        await client.write(remotePath, bytes);
      }
      if (!await _checkpointTask(task)) return;
      task
        ..progress = 0.85
        ..remotePath = remotePath
        ..updatedAt = DateTime.now();
      if (!await _saveTaskIfAlive(task)) return;

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

  Future<String?> _downloadMediaToLocalCache(BabyCloudMedia item) async {
    if (item.remotePath.trim().isEmpty) return null;
    final source = sources.firstWhereOrNull((s) => s.id == item.dataSourceId);
    if (source == null || !source.isWebDav) return null;

    final endpointUrl = _effectiveWebDavUrl(source);
    if (endpointUrl == null || endpointUrl.isEmpty) return null;
    final client = _webDavClient(source, endpointUrl: endpointUrl);
    final bytes = await client.read(item.remotePath);
    final dir = await _localMediaCacheDir(item);
    final ext = _extension(item.fileName).isNotEmpty
        ? _extension(item.fileName)
        : item.isVideo
            ? '.mp4'
            : item.isAudio
                ? '.m4a'
                : '.jpg';
    final file = File(
      '${dir.path}${Platform.pathSeparator}${_safeFileSegment(item.sha256)}$ext',
    );
    await file.writeAsBytes(bytes, flush: true);
    item
      ..localPath = file.path
      ..updatedAt = DateTime.now();
    await item.save();
    return file.path;
  }

  Future<Directory> _localMediaCacheDir(BabyCloudMedia item) async {
    final base = await getApplicationDocumentsDirectory();
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

  Future<void> _prepareBabyCloudStructure(
    _BabyWebDavClient client,
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
    _BabyWebDavClient client,
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
    _BabyWebDavClient client,
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
    _BabyWebDavClient client,
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
    _BabyWebDavClient client,
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
    _BabyWebDavClient client,
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
    _BabyWebDavClient client,
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
      '${_babyDir(source, baby)}/index',
      '${_babyDir(source, baby)}/trash',
    ];
    for (final dir in dirs) {
      await _ensureRemoteDir(client, dir);
    }
  }

  Future<bool> _ensureRemoteDir(
    _BabyWebDavClient client,
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
        throw Exception('创建 WebDAV 目录 $current 失败；读取尝试：$readError；创建尝试：$e');
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
    Object? rootReadError;

    try {
      await client.statDir('/');
    } catch (e) {
      rootReadError = e;
      try {
        await client.mkdir('/');
        await client.statDir('/');
        messages.add('已创建 WebDAV 根目录');
      } catch (e) {
        throw Exception(
          'WebDAV 根目录暂不可读或不可创建；初次读取：$rootReadError；创建尝试：$e',
        );
      }
    }

    final root = _normalizeRoot(source.rootPath);
    if (root == '/') return messages.isEmpty ? null : messages.join('；');

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

  Future<void> _recordSourceCheck(
    BabyCloudSource source, {
    required bool ok,
    required String message,
    required bool persist,
  }) async {
    source
      ..status = ok ? 'normal' : 'invalid'
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
    final looksLocal = await _looksLikeLocalNetwork();
    final result = <_WebDavEndpointCandidate>[];

    void add(String endpoint, String url, {String? note}) {
      final normalized = _normalizeEndpointUrl(url);
      if (normalized.isEmpty) return;
      if (result.any((item) => item.url == normalized)) return;
      result.add(_WebDavEndpointCandidate(endpoint, normalized, note: note));
    }

    void addWithOriginFallback(String endpoint, String url) {
      final normalized = _normalizeEndpointUrl(url);
      if (normalized.isEmpty) return;
      add(endpoint, normalized);

      final origin = _originEndpointUrl(normalized);
      if (origin == null || origin == normalized) return;
      final path = Uri.parse(normalized).path;
      add(
        endpoint,
        origin,
        note: '原地址路径 ${path.isEmpty ? '/' : path} 不可用，已自动改用同主机根地址 $origin',
      );
    }

    if (looksLocal) {
      addWithOriginFallback('lan', lan);
      addWithOriginFallback('external', external);
    } else {
      addWithOriginFallback('external', external);
      addWithOriginFallback('lan', lan);
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
    final active = source.activeWebDavUrl?.trim() ?? '';
    if (active.isNotEmpty) return _normalizeEndpointUrl(active);
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

  String? _originEndpointUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return null;
    final origin = uri.replace(path: '', query: null, fragment: null);
    return _normalizeEndpointUrl(origin.toString());
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
